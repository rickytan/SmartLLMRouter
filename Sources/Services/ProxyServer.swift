import Foundation
import Swifter

@MainActor
final class ProxyServer: ObservableObject {
    static let shared = ProxyServer()
    private let httpServer = HttpServer()

    @Published var isRunning: Bool = false
    @Published var port: Int = 1897
    @Published var lastError: String?

    private var requestCount: Int64 = 0

    private init() {
        setupRoutes()
    }

    func start(port: Int? = nil) {
        // Thread-safe early exit: if already running, do nothing.
        // Since this class is @MainActor, calls are serialized on the main queue.
        guard !isRunning else {
            Log.info("Proxy already running on port \(self.port), skipping start")
            return
        }

        let usePort = port ?? self.port
        do {
            try httpServer.start(in_port_t(usePort), forceIPv4: true)
            isRunning = true
            self.port = usePort
            Log.info("Proxy started on port \(usePort)")
        } catch {
            lastError = error.localizedDescription
            Log.error("Failed to start proxy: \(error.localizedDescription)")
            isRunning = false
        }
    }

    func stop() {
        httpServer.stop()
        isRunning = false
        Log.info("Proxy stopped")
    }

    private func setupRoutes() {
        httpServer.post["/v1/messages"] = { [weak self] request in
            guard let self else { return HttpResponse.internalServerError }
            return handleRequestSync(request, targetProtocol: .anthropic)
        }

        httpServer.post["/v1/chat/completions"] = { [weak self] request in
            guard let self else { return HttpResponse.internalServerError }
            return handleRequestSync(request, targetProtocol: .openai)
        }

        httpServer["/health"] = { [weak self] _ in
            guard let self else { return HttpResponse.internalServerError }
            let json: [String: Any] = [
                "status": isRunning ? "running" : "stopped",
                "port": port,
            ]
            return HttpResponse.ok(.json(json))
        }

        httpServer.get["/v1/models"] = { [weak self] _ in
            guard let self else { return HttpResponse.internalServerError }
            return handleModelsRequest()
        }
    }

    private func handleRequestSync(
        _ request: HttpRequest,
        targetProtocol: RequestForwarder.RequestProtocol
    ) -> HttpResponse {
        requestCount += 1
        let reqId = requestCount
        let startTime = Date()
        let reqIdString = "req-\(reqId)"

        Log.info("[#\(reqId)] \(request.method) \(request.path)")

        // Parse body early to extract model name for routing
        let bodyData: Data
        let bytes = request.body
        if !bytes.isEmpty {
            bodyData = Data(bytes)
        } else {
            return errorResponse(400, "Empty request body")
        }

        let incomingProtocol = RequestForwarder.detectProtocol(path: request.path, body: bodyData)
        let modelName = extractModelName(from: bodyData)

        // Use SmartRouter for channel selection
        guard let routingDecision = SmartRouter.shared.selectChannel(requestID: reqIdString, modelName: modelName)
        else {
            Log.error("[#\(reqId)] No available channels")
            return errorResponse(503, "No available channel - all channels in cooldown or no channels configured")
        }

        let channel = routingDecision.channel

        // Validate API key
        guard let apiKey = KeychainManager.shared.getAPIKey(for: channel.id),
              !apiKey.isEmpty
        else {
            Log.error("[#\(reqId)] No API key for channel \(channel.name)")
            return errorResponse(503, "No API key configured for selected channel")
        }

        let isStream = RequestForwarder.isStreamingRequest(bodyData)

        // Apply model override from ModelSwitcher before forwarding
        let effectiveBody = applyModelOverride(body: bodyData)

        // Build upstream URL
        var components = URLComponents(string: channel.baseURL)
        components?.path = targetProtocol == .anthropic ? "/v1/messages" : "/v1/chat/completions"
        guard let upstreamURL = components?.url else {
            return errorResponse(500, "Invalid upstream URL")
        }

        // Convert protocol if needed
        let forwardedBody: Data
        var convertedHeaders = request.headers

        if incomingProtocol != targetProtocol {
            do {
                guard let json = try JSONSerialization.jsonObject(with: effectiveBody) as? [String: Any] else {
                    return errorResponse(400, "Invalid JSON body")
                }

                let converted: [String: Any] = switch (incomingProtocol, targetProtocol) {
                case (.anthropic, .openai):
                    try ProtocolConverter.anthropicToOpenAI(body: json)
                case (.openai, .anthropic):
                    try ProtocolConverter.openAItoAnthropic(body: json)
                default:
                    json
                }

                forwardedBody = try JSONSerialization.data(withJSONObject: converted)
                convertedHeaders["content-type"] = "application/json"
                convertedHeaders["content-length"] = String(forwardedBody.count)
            } catch {
                return errorResponse(400, "Protocol conversion failed")
            }
        } else {
            forwardedBody = effectiveBody
        }

        // Add auth headers
        switch targetProtocol {
        case .anthropic:
            convertedHeaders["x-api-key"] = apiKey
            convertedHeaders["anthropic-version"] = "2023-06-01"
        case .openai, .unknown:
            convertedHeaders["Authorization"] = "Bearer \(apiKey)"
        }

        // Remove hop-by-hop headers
        convertedHeaders.removeValue(forKey: "host")

        // Forward request via URLSession
        let result = forwardRequestSync(
            reqId: reqId,
            url: upstreamURL,
            headers: convertedHeaders,
            body: forwardedBody,
            timeout: 120
        )

        switch result {
        case let .success(data, statusCode, responseHeaders):
            let latency = Date().timeIntervalSince(startTime)

            // Check for error status that should trigger retry
            if statusCode >= 400, statusCode != 400, statusCode != 403 {
                // Try to retry with another channel
                if let retryDecision = SmartRouter.shared.handleError(
                    requestID: reqIdString,
                    statusCode: statusCode,
                    modelName: modelName
                ) {
                    Log.info(
                        "[#\(reqId)] Retrying with channel \(retryDecision.channel.name)"
                    )
                    return handleRetryRequest(
                        request: request,
                        targetProtocol: targetProtocol,
                        bodyData: bodyData,
                        incomingProtocol: incomingProtocol,
                        routingDecision: retryDecision,
                        reqId: reqId,
                        startTime: startTime
                    )
                }
            }

            // Parse usage
            let usage = RequestForwarder.parseUsage(from: data, isAnthropic: targetProtocol == .anthropic)

            // Convert response if needed
            var responseBody: Data? = data
            if incomingProtocol != targetProtocol {
                do {
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        throw NSError(domain: "ProxyServer", code: -1, userInfo: [:])
                    }
                    let converted: [String: Any] = switch (incomingProtocol, targetProtocol) {
                    case (.openai, .anthropic):
                        ProtocolConverter.anthropicToOpenAIResponse(body: json)
                    case (.anthropic, .openai):
                        ProtocolConverter.openAItoAnthropicResponse(body: json)
                    default:
                        json
                    }
                    responseBody = try JSONSerialization.data(withJSONObject: converted)
                } catch {
                    Log.error("[#\(reqId)] Response conversion failed")
                    responseBody = data
                }
            }

            // Record usage
            let cost = estimateCost(channel: channel, inputTokens: usage.input, outputTokens: usage.output)
            UsageTracker.shared.recordUsage(
                channelID: channel.id, channelName: channel.name,
                model: modelName ?? channel.models.first?.identifier ?? "unknown",
                inputTokens: usage.input, outputTokens: usage.output,
                estimatedCost: cost, latency: latency * 1000,
                statusCode: statusCode, isError: statusCode >= 400
            )

            // Complete request tracking
            SmartRouter.shared.completeRequest(requestID: reqIdString)

            // Build response
            return buildFinalResponse(
                statusCode: statusCode,
                body: responseBody ?? data,
                isStream: isStream,
                headers: responseHeaders
            )

        case let .failure(error):
            Log.error("[#\(reqId)] Forward failed: \(error.localizedDescription)")

            // Try to retry on network errors
            if let retryDecision = SmartRouter.shared.handleError(
                requestID: reqIdString,
                statusCode: 502,
                modelName: modelName
            ) {
                Log.info(
                    "[#\(reqId)] Retrying after network error with channel \(retryDecision.channel.name)"
                )
                return handleRetryRequest(
                    request: request,
                    targetProtocol: targetProtocol,
                    bodyData: bodyData,
                    incomingProtocol: incomingProtocol,
                    routingDecision: retryDecision,
                    reqId: reqId,
                    startTime: startTime
                )
            }

            UsageTracker.shared.recordUsage(
                channelID: channel.id, channelName: channel.name,
                model: modelName ?? channel.models.first?.identifier ?? "unknown",
                inputTokens: 0, outputTokens: 0, estimatedCost: 0,
                latency: Date().timeIntervalSince(startTime) * 1000,
                statusCode: 502, isError: true
            )

            SmartRouter.shared.completeRequest(requestID: reqIdString)
            return errorResponse(502, "Upstream request failed")
        }
    }

    /// Handle retry request with a different channel
    private func handleRetryRequest(
        request: HttpRequest,
        targetProtocol: RequestForwarder.RequestProtocol,
        bodyData: Data,
        incomingProtocol: RequestForwarder.RequestProtocol,
        routingDecision: RoutingDecision,
        reqId: Int64,
        startTime: Date
    ) -> HttpResponse {
        let reqIdString = "req-\(reqId)"
        let channel = routingDecision.channel

        guard let apiKey = KeychainManager.shared.getAPIKey(for: channel.id),
              !apiKey.isEmpty
        else {
            SmartRouter.shared.completeRequest(requestID: reqIdString)
            return errorResponse(503, "No API key for retry channel")
        }

        let isStream = RequestForwarder.isStreamingRequest(bodyData)

        // Apply model override from ModelSwitcher before forwarding
        let effectiveBody = applyModelOverride(body: bodyData)

        // Build upstream URL
        var components = URLComponents(string: channel.baseURL)
        components?.path = targetProtocol == .anthropic ? "/v1/messages" : "/v1/chat/completions"
        guard let upstreamURL = components?.url else {
            SmartRouter.shared.completeRequest(requestID: reqIdString)
            return errorResponse(500, "Invalid upstream URL")
        }

        // Convert protocol if needed
        let forwardedBody: Data
        var convertedHeaders = request.headers

        if incomingProtocol != targetProtocol {
            do {
                guard let json = try JSONSerialization.jsonObject(with: effectiveBody) as? [String: Any] else {
                    SmartRouter.shared.completeRequest(requestID: reqIdString)
                    return errorResponse(400, "Invalid JSON body")
                }

                let converted: [String: Any] = switch (incomingProtocol, targetProtocol) {
                case (.anthropic, .openai):
                    try ProtocolConverter.anthropicToOpenAI(body: json)
                case (.openai, .anthropic):
                    try ProtocolConverter.openAItoAnthropic(body: json)
                default:
                    json
                }

                forwardedBody = try JSONSerialization.data(withJSONObject: converted)
                convertedHeaders["content-type"] = "application/json"
                convertedHeaders["content-length"] = String(forwardedBody.count)
            } catch {
                SmartRouter.shared.completeRequest(requestID: reqIdString)
                return errorResponse(400, "Protocol conversion failed")
            }
        } else {
            forwardedBody = effectiveBody
        }

        // Add auth headers
        switch targetProtocol {
        case .anthropic:
            convertedHeaders["x-api-key"] = apiKey
            convertedHeaders["anthropic-version"] = "2023-06-01"
        case .openai, .unknown:
            convertedHeaders["Authorization"] = "Bearer \(apiKey)"
        }

        convertedHeaders.removeValue(forKey: "host")

        // Forward request
        let result = forwardRequestSync(
            reqId: reqId,
            url: upstreamURL,
            headers: convertedHeaders,
            body: forwardedBody,
            timeout: 120
        )

        switch result {
        case let .success(data, statusCode, responseHeaders):
            // Check for another retry
            if statusCode >= 400, statusCode != 400, statusCode != 403 {
                if let nextRetry = SmartRouter.shared.handleError(
                    requestID: reqIdString,
                    statusCode: statusCode,
                    modelName: extractModelName(from: bodyData)
                ) {
                    return handleRetryRequest(
                        request: request,
                        targetProtocol: targetProtocol,
                        bodyData: bodyData,
                        incomingProtocol: incomingProtocol,
                        routingDecision: nextRetry,
                        reqId: reqId,
                        startTime: startTime
                    )
                }
            }

            let latency = Date().timeIntervalSince(startTime)

            // Parse usage
            let usage = RequestForwarder.parseUsage(from: data, isAnthropic: targetProtocol == .anthropic)

            // Convert response if needed
            var responseBody: Data? = data
            if incomingProtocol != targetProtocol {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let converted: [String: Any] = switch (incomingProtocol, targetProtocol) {
                    case (.openai, .anthropic):
                        ProtocolConverter.anthropicToOpenAIResponse(body: json)
                    case (.anthropic, .openai):
                        ProtocolConverter.openAItoAnthropicResponse(body: json)
                    default:
                        json
                    }
                    responseBody = try? JSONSerialization.data(withJSONObject: converted)
                }
            }

            // Record usage for retry channel
            let cost = estimateCost(channel: channel, inputTokens: usage.input, outputTokens: usage.output)
            UsageTracker.shared.recordUsage(
                channelID: channel.id, channelName: channel.name,
                model: extractModelName(from: bodyData) ?? channel.models.first?.identifier ?? "unknown",
                inputTokens: usage.input, outputTokens: usage.output,
                estimatedCost: cost, latency: latency * 1000,
                statusCode: statusCode, isError: statusCode >= 400
            )

            SmartRouter.shared.completeRequest(requestID: reqIdString)

            return buildFinalResponse(
                statusCode: statusCode,
                body: responseBody ?? data,
                isStream: isStream,
                headers: responseHeaders
            )

        case .failure:
            SmartRouter.shared.completeRequest(requestID: reqIdString)
            return errorResponse(502, "All retry attempts failed")
        }
    }

    /// Forward request synchronously
    private func forwardRequestSync(
        reqId _: Int64,
        url: URL,
        headers: [String: String],
        body: Data,
        timeout: TimeInterval
    ) -> ForwardResult {
        var resultData: Data?
        var resultStatusCode = 200
        var resultHeaders: [String: String] = [:]
        var forwardErr: Error?
        let group = DispatchGroup()
        group.enter()

        Task {
            do {
                var urlRequest = URLRequest(url: url)
                urlRequest.httpMethod = "POST"
                urlRequest.httpBody = body
                urlRequest.timeoutInterval = timeout
                for (k, v) in headers {
                    urlRequest.setValue(v, forHTTPHeaderField: k)
                }

                let (responseData, urlResponse) = try await URLSession.shared.data(for: urlRequest)
                let httpResponse = urlResponse as? HTTPURLResponse

                let rHeaders: [String: String] = (httpResponse?.allHeaderFields ?? [:])
                    .reduce(into: [:]) { dict, pair in
                        if let key = pair.key as? String, let value = pair.value as? String {
                            dict[key] = value
                        }
                    }

                resultData = responseData
                resultStatusCode = httpResponse?.statusCode ?? 200
                resultHeaders = rHeaders
            } catch {
                forwardErr = error
            }
            group.leave()
        }

        _ = group.wait(timeout: .now() + timeout + 5)

        if let forwardErr {
            return .failure(forwardErr)
        }

        guard let data = resultData else {
            return .failure(NSError(
                domain: "ProxyServer",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No response data"]
            ))
        }

        return .success(data: data, statusCode: resultStatusCode, headers: resultHeaders)
    }

    /// Extract model name from request body
    private func extractModelName(from body: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }
        return json["model"] as? String
    }

    /// Apply model override from ModelSwitcher to request body
    /// Returns modified body data with the selected model, or original body if no override
    private func applyModelOverride(body: Data) -> Data {
        // Check if user has selected a specific model
        guard ModelSwitcher.shared.hasOverride,
              let modelID = ModelSwitcher.shared.selectedModelID,
              var json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            return body
        }

        json["model"] = modelID
        Log.info("Model override applied: \(modelID)")

        return (try? JSONSerialization.data(withJSONObject: json)) ?? body
    }

    /// Build final HTTP response
    private func buildFinalResponse(
        statusCode: Int,
        body: Data,
        isStream: Bool,
        headers: [String: String]
    ) -> HttpResponse {
        var responseHeaders: [String: String] = [:]
        responseHeaders["content-type"] = isStream ? "text/event-stream" : "application/json"
        responseHeaders["content-length"] = String(body.count)
        for (key, value) in headers {
            if key.lowercased().hasPrefix("x-") || key.lowercased() == "retry-after" {
                responseHeaders[key] = value
            }
        }
        return rawResponse(statusCode: statusCode, headers: responseHeaders, body: body)
    }

    /// Result of forwarding a request
    private enum ForwardResult {
        case success(data: Data, statusCode: Int, headers: [String: String])
        case failure(Error)
    }

    private func handleModelsRequest() -> HttpResponse {
        guard let channel = ChannelStore.shared.activeChannel else {
            return errorResponse(503, "No active channel configured")
        }
        let models = channel.models.map { model in
            ["id": model.identifier, "object": "model",
             "created": Int(Date().timeIntervalSince1970), "owned_by": channel.name] as [String: Any]
        }
        return HttpResponse.ok(.json(["object": "list", "data": models]))
    }

    private func errorResponse(_ statusCode: Int, _ message: String) -> HttpResponse {
        let body: [String: Any] = [
            "error": ["message": message, "type": "api_error", "code": statusCode],
        ]
        return rawResponse(statusCode: statusCode, headers: ["content-type": "application/json"], json: body)
    }

    private func rawResponse(statusCode: Int, headers: [String: String], body: Data) -> HttpResponse {
        let bytes = [UInt8](body)
        return HttpResponse.raw(statusCode, "OK", headers) { writer in
            try writer.write(bytes)
        }
    }

    private func rawResponse(statusCode: Int, headers: [String: String], json: [String: Any]) -> HttpResponse {
        let body = try? JSONSerialization.data(withJSONObject: json)
        return rawResponse(statusCode: statusCode, headers: headers, body: body ?? Data())
    }

    private func estimateCost(channel: Channel, inputTokens: Int, outputTokens: Int) -> Double {
        guard let model = channel.models.first else { return 0.0 }
        let inputCost = model.inputPricePer1M ?? 3.0
        let outputCost = model.outputPricePer1M ?? 15.0
        return (Double(inputTokens) / 1_000_000) * inputCost + (Double(outputTokens) / 1_000_000) * outputCost
    }
}

@MainActor
final class ChannelStore: ObservableObject {
    static let shared = ChannelStore()

    @Published var channels: [Channel] = []
    @Published var activeChannelID: String?

    var activeChannel: Channel? {
        guard let id = activeChannelID else { return channels.first }
        return channels.first { $0.id == id }
    }

    private init() {
        loadChannels()
    }

    func saveChannels() {
        do {
            let data = try JSONEncoder().encode(channels)
            UserDefaults.standard.set(data, forKey: "smartllm_channels")
            UserDefaults.standard.set(activeChannelID, forKey: "smartllm_active_channel")
        } catch {
            Log.error("Failed to save channels: \(error.localizedDescription)")
        }
    }

    func loadChannels() {
        do {
            guard let data = UserDefaults.standard.data(forKey: "smartllm_channels") else {
                channels = []
                return
            }
            channels = try JSONDecoder().decode([Channel].self, from: data)
            activeChannelID = UserDefaults.standard.string(forKey: "smartllm_active_channel")
            Log.debug("Loaded \(channels.count) channels")
        } catch {
            Log.error("Failed to load channels: \(error.localizedDescription)")
            channels = []
        }
    }

    func addChannel(_ channel: Channel) {
        channels.append(channel)
        if activeChannelID == nil { activeChannelID = channel.id }
        saveChannels()
    }

    func removeChannel(id: String) {
        channels.removeAll { $0.id == id }
        if activeChannelID == id { activeChannelID = channels.first?.id }
        saveChannels()
    }

    func updateChannel(_ channel: Channel) {
        if let index = channels.firstIndex(where: { $0.id == channel.id }) {
            channels[index] = channel
            saveChannels()
        }
    }

    func setActiveChannel(id: String) {
        activeChannelID = id
        saveChannels()
    }
}
