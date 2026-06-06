import Foundation
import Swifter

@MainActor
final class ProxyServer: ObservableObject {
    static let shared = ProxyServer()
    private let httpServer = HttpServer()

    @Published var isRunning: Bool = false
    @Published var port: Int = 1897
    @Published var lastError: String?

    private var _requestCount: Int64 = 0
    private let requestCountLock = NSLock()

    private func nextRequestID() -> Int64 {
        requestCountLock.lock()
        defer { requestCountLock.unlock() }
        _requestCount += 1
        return _requestCount
    }

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
            return self.handleRequestSync(request, targetProtocol: .anthropic)
        }

        httpServer.post["/v1/chat/completions"] = { [weak self] request in
            guard let self else { return HttpResponse.internalServerError }
            return self.handleRequestSync(request, targetProtocol: .openai)
        }

        httpServer["/health"] = { [weak self] _ in
            guard let self else { return HttpResponse.internalServerError }
            // Read @MainActor properties via DispatchGroup bridge
            var status = "stopped"
            var portNum = 0
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.main.async {
                status = self.isRunning ? "running" : "stopped"
                portNum = self.port
                group.leave()
            }
            _ = group.wait(timeout: .now() + 1)
            let json: [String: Any] = [
                "status": status,
                "port": portNum,
            ]
            return HttpResponse.ok(.json(json))
        }

        httpServer.get["/v1/models"] = { [weak self] _ in
            guard let self else { return HttpResponse.internalServerError }
            return self.handleModelsRequest()
        }

        // MARK: - New API Endpoints

        // 1. Single model lookup
        httpServer["/v1/models/:modelId"] = { [weak self] request in
            guard let self else { return HttpResponse.internalServerError }
            return self.handleSingleModelRequest(request)
        }

        // 2. Embeddings
        httpServer.post["/v1/embeddings"] = { [weak self] request in
            guard let self else { return HttpResponse.internalServerError }
            return self.handleAuxiliaryRequest(request, targetPath: "/v1/embeddings")
        }

        // 3. Image generation
        httpServer.post["/v1/images/generations"] = { [weak self] request in
            guard let self else { return HttpResponse.internalServerError }
            return self.handleAuxiliaryRequest(request, targetPath: "/v1/images/generations")
        }

        // 4. Image edits (multipart)
        httpServer.post["/v1/images/edits"] = { [weak self] request in
            guard let self else { return HttpResponse.internalServerError }
            return self.handleMultipartRequest(request, targetPath: "/v1/images/edits")
        }

        // 5. Image variations (multipart)
        httpServer.post["/v1/images/variations"] = { [weak self] request in
            guard let self else { return HttpResponse.internalServerError }
            return self.handleMultipartRequest(request, targetPath: "/v1/images/variations")
        }

        // 6. TTS
        httpServer.post["/v1/audio/speech"] = { [weak self] request in
            guard let self else { return HttpResponse.internalServerError }
            return self.handleAuxiliaryRequest(request, targetPath: "/v1/audio/speech")
        }

        // 7. Audio transcriptions (multipart)
        httpServer.post["/v1/audio/transcriptions"] = { [weak self] request in
            guard let self else { return HttpResponse.internalServerError }
            return self.handleMultipartRequest(request, targetPath: "/v1/audio/transcriptions")
        }

        // 8. Audio translations (multipart)
        httpServer.post["/v1/audio/translations"] = { [weak self] request in
            guard let self else { return HttpResponse.internalServerError }
            return self.handleMultipartRequest(request, targetPath: "/v1/audio/translations")
        }

        // 9. Moderations
        httpServer.post["/v1/moderations"] = { [weak self] request in
            guard let self else { return HttpResponse.internalServerError }
            return self.handleAuxiliaryRequest(request, targetPath: "/v1/moderations")
        }

        // 10. Files list/upload
        httpServer.get["/v1/files"] = { [weak self] request in
            guard let self else { return HttpResponse.internalServerError }
            return self.handleFilesRequest(request, method: "GET")
        }
        httpServer.post["/v1/files"] = { [weak self] request in
            guard let self else { return HttpResponse.internalServerError }
            return self.handleFilesRequest(request, method: "POST")
        }

        // 11. Files detail/delete/content
        httpServer["/v1/files/:fileId"] = { [weak self] request in
            guard let self else { return HttpResponse.internalServerError }
            let method = request.method.uppercased()
            if method == "GET" || method == "DELETE" {
                return self.handleFilesRequest(request, method: method)
            }
            return self.errorResponse(405, "Method not allowed")
        }
        httpServer.get["/v1/files/:fileId/content"] = { [weak self] request in
            guard let self else { return HttpResponse.internalServerError }
            return self.handleFilesRequest(request, method: "GET", isContent: true)
        }
    }

    // MARK: - Thread-safe state bridge

    /// Captures shared state from @MainActor services in a single main-thread hop.
    /// This struct is Sendable (all fields are value types) and safe to use on any thread.
    struct RequestState {
        let channel: Channel
        let apiKey: String
        let routingDecision: RoutingDecision
    }

    /// Synchronously reads channel + routing decision from MainActor-isolated services.
    /// Must be called from a background thread (Swifter handler context).
    private func readRequestState(
        request: HttpRequest,
        bodyData: Data,
        reqIdString: String
    ) -> RequestState? {
        var result: RequestState?
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.main.sync {
            let modelName = self.extractModelName(from: bodyData)
            let routingModelName = ModelSwitcher.shared.selectedModelID ?? modelName
            guard let decision = SmartRouter.shared.selectChannel(
                requestID: reqIdString,
                modelName: routingModelName
            ) else {
                group.leave()
                return
            }
            guard let apiKey = KeychainManager.shared.getAPIKey(for: decision.channel.id),
                  !apiKey.isEmpty
            else {
                group.leave()
                return
            }
            result = RequestState(
                channel: decision.channel,
                apiKey: apiKey,
                routingDecision: decision
            )
            group.leave()
        }
        _ = group.wait(timeout: .now() + 1)
        return result
    }

    /// Synchronously reads model override info from MainActor-isolated ModelSwitcher.
    private func readModelOverride() -> (hasOverride: Bool, selectedModelID: String?) {
        var result: (Bool, String?) = (false, nil)
        DispatchQueue.main.sync {
            result = (ModelSwitcher.shared.hasOverride, ModelSwitcher.shared.selectedModelID)
        }
        return result
    }

    // MARK: - Thread-safe SmartRouter helpers
    // All SmartRouter methods are @MainActor-isolated; these helpers bridge from background threads.

    private func routerRecordSuccess(channelID: String) {
        DispatchQueue.main.sync {
            SmartRouter.shared.recordSuccess(channelID: channelID)
        }
    }

    private func routerHandleError(
        requestID: String,
        statusCode: Int,
        modelName: String?,
        errorBody: Data? = nil,
        requestProtocol: RequestForwarder.RequestProtocol? = nil
    ) -> RoutingDecision? {
        var decision: RoutingDecision?
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.main.sync {
            if let requestProtocol {
                decision = SmartRouter.shared.handleError(
                    requestID: requestID,
                    statusCode: statusCode,
                    modelName: modelName,
                    errorBody: errorBody,
                    requestProtocol: requestProtocol
                )
            } else {
                decision = SmartRouter.shared.handleError(
                    requestID: requestID,
                    statusCode: statusCode,
                    modelName: modelName
                )
            }
            group.leave()
        }
        _ = group.wait(timeout: .now() + 1)
        return decision
    }

    private func routerCompleteRequest(requestID: String) {
        DispatchQueue.main.sync {
            SmartRouter.shared.completeRequest(requestID: requestID)
        }
    }

    private func upstreamProtocol(
        for channel: Channel,
        clientProtocol: RequestForwarder.RequestProtocol
    ) -> RequestForwarder.RequestProtocol {
        switch channel.protocol {
        case .anthropic:
            return .anthropic
        case .openai:
            return .openai
        case .auto:
            return clientProtocol == .unknown ? .openai : clientProtocol
        }
    }

    private func handleRequestSync(
        _ request: HttpRequest,
        targetProtocol: RequestForwarder.RequestProtocol
    ) -> HttpResponse {
        let reqId = nextRequestID()
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

        // Thread-safe: read channel + routing decision from @MainActor services in one hop
        guard let state = readRequestState(
            request: request,
            bodyData: bodyData,
            reqIdString: reqIdString
        ) else {
            Log.error("[#\(reqId)] No available channels or missing API key")
            return errorResponse(503, "No available channel - all channels in cooldown or no channels configured")
        }

        let channel = state.channel
        let apiKey = state.apiKey
        let routingDecision = state.routingDecision

        let isStream = RequestForwarder.isStreamingRequest(bodyData)

        // Thread-safe: read model override from @MainActor ModelSwitcher
        let override = readModelOverride()
        let effectiveBody = applyModelOverride(body: bodyData, hasOverride: override.hasOverride, selectedModelID: override.selectedModelID)

        // Apply smart fallback model swap if routing decision has a different effective model
        var swappedBody = effectiveBody
        if let orig = routingDecision.originalModel,
           let eff = routingDecision.effectiveModel,
           orig != eff,
           let swapped = RequestForwarder.swapModel(in: effectiveBody, newModel: eff) {
            Log.info("Smart fallback: model swapped from \(orig) to \(eff) for channel \(channel.name)")
            swappedBody = swapped
        }

        let upstreamProtocol = upstreamProtocol(for: channel, clientProtocol: targetProtocol)

        // Build upstream URL
        var components = URLComponents(string: channel.baseURL)
        components?.path = upstreamProtocol == .anthropic ? "/v1/messages" : "/v1/chat/completions"
        guard let upstreamURL = components?.url else {
            return errorResponse(500, "Invalid upstream URL")
        }

        // Convert protocol if needed
        let forwardedBody: Data
        var convertedHeaders = request.headers

        if incomingProtocol != upstreamProtocol {
            do {
                guard let json = try JSONSerialization.jsonObject(with: swappedBody) as? [String: Any] else {
                    return errorResponse(400, "Invalid JSON body")
                }

                let converted: [String: Any] = switch (incomingProtocol, upstreamProtocol) {
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
            forwardedBody = swappedBody
        }

        setAuthHeaders(&convertedHeaders, apiKey: apiKey, protocol: upstreamProtocol)

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

            // Log non-2xx status codes
            if statusCode < 200 || statusCode >= 300 {
                let responseBodyStr = String(data: data, encoding: .utf8)?.prefix(500) ?? "nil"
                Log.error("[#\(reqId)] HTTP \(statusCode) response from \(channel.name): \(responseBodyStr)")
            }

            // Record success with CircuitBreaker for 2xx responses
            if statusCode >= 200 && statusCode < 300 {
                routerRecordSuccess(channelID: channel.id)
            }

            // Check for error status that should trigger retry
            // For 429/5xx: standard retry
            // For 400: check for context_length_exceeded or thinking budget issues in error body
            let isContextExceeded = statusCode == 400 && isContextLengthExceeded(data)
            let isThinkingIssue = statusCode == 400 && isThinkingBudgetIssue(data)

            if (statusCode >= 400 && statusCode != 400 && statusCode != 403) || isContextExceeded || isThinkingIssue {
                // Try thinking rectification first (for 400 with thinking budget issues)
                if isThinkingIssue,
                   let rectifiedBody = tryThinkingRectification(originalBody: bodyData, maxTokens: extractMaxTokens(from: bodyData)) {
                    Log.info("[#\(reqId)] Thinking rectification: retrying with adjusted budget_tokens")
                    return handleRetryWithModifiedBody(
                        request: request,
                        targetProtocol: targetProtocol,
                        modifiedBody: rectifiedBody,
                        bodyData: bodyData,
                        incomingProtocol: incomingProtocol,
                        channel: channel,
                        apiKey: apiKey,
                        reqId: reqId,
                        startTime: startTime,
                        modelName: modelName
                    )
                }

                // Try to retry with another channel
                if let retryDecision = routerHandleError(
                    requestID: reqIdString,
                    statusCode: statusCode,
                    modelName: modelName,
                    errorBody: isContextExceeded ? data : nil,
                    requestProtocol: targetProtocol
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
            let usage = RequestForwarder.parseUsage(from: data, isAnthropic: upstreamProtocol == .anthropic)

            // Convert response if needed
            var responseBody: Data? = data
            if statusCode >= 200 && statusCode < 300 && incomingProtocol != upstreamProtocol {
                do {
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        throw NSError(domain: "ProxyServer", code: -1, userInfo: [:])
                    }
                    let converted: [String: Any] = switch (incomingProtocol, upstreamProtocol) {
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
            routerCompleteRequest(requestID: reqIdString)

            // Build response
            return buildFinalResponse(
                statusCode: statusCode,
                body: responseBody ?? data,
                isStream: isStream,
                headers: responseHeaders
            )

        case let .failure(error):
            // Record failure with CircuitBreaker
            routerHandleError(
                requestID: reqIdString,
                statusCode: 502,
                modelName: modelName
            )

            Log.error("[#\(reqId)] Forward failed: \(error.localizedDescription)")

            // Try to retry on network errors
            if let retryDecision = routerHandleError(
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

            routerCompleteRequest(requestID: reqIdString)
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
            routerCompleteRequest(requestID: reqIdString)
            return errorResponse(503, "No API key for retry channel")
        }

        let isStream = RequestForwarder.isStreamingRequest(bodyData)

        // Thread-safe: read model override from @MainActor ModelSwitcher
        let override = readModelOverride()
        let effectiveBody = applyModelOverride(body: bodyData, hasOverride: override.hasOverride, selectedModelID: override.selectedModelID)

        // Apply smart fallback model swap if routing decision has a different effective model
        var swappedBody = effectiveBody
        if let orig = routingDecision.originalModel,
           let eff = routingDecision.effectiveModel,
           orig != eff,
           let swapped = RequestForwarder.swapModel(in: effectiveBody, newModel: eff) {
            Log.info("Smart fallback: model swapped from \(orig) to \(eff) for retry on channel \(channel.name)")
            swappedBody = swapped
        }

        let upstreamProtocol = upstreamProtocol(for: channel, clientProtocol: targetProtocol)

        // Build upstream URL
        var components = URLComponents(string: channel.baseURL)
        components?.path = upstreamProtocol == .anthropic ? "/v1/messages" : "/v1/chat/completions"
        guard let upstreamURL = components?.url else {
            routerCompleteRequest(requestID: reqIdString)
            return errorResponse(500, "Invalid upstream URL")
        }

        // Convert protocol if needed
        let forwardedBody: Data
        var convertedHeaders = request.headers

        if incomingProtocol != upstreamProtocol {
            do {
                guard let json = try JSONSerialization.jsonObject(with: swappedBody) as? [String: Any] else {
                    routerCompleteRequest(requestID: reqIdString)
                    return errorResponse(400, "Invalid JSON body")
                }

                let converted: [String: Any] = switch (incomingProtocol, upstreamProtocol) {
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
                routerCompleteRequest(requestID: reqIdString)
                return errorResponse(400, "Protocol conversion failed")
            }
        } else {
            forwardedBody = swappedBody
        }

        setAuthHeaders(&convertedHeaders, apiKey: apiKey, protocol: upstreamProtocol)

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
            // Log non-2xx status codes
            if statusCode < 200 || statusCode >= 300 {
                let responseBodyStr = String(data: data, encoding: .utf8)?.prefix(500) ?? "nil"
                Log.error("[#\(reqId)] HTTP \(statusCode) response from \(channel.name) (retry): \(responseBodyStr)")
            }

            // Check for another retry
            if statusCode >= 400, statusCode != 400, statusCode != 403 {
                if let nextRetry = routerHandleError(
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
            let usage = RequestForwarder.parseUsage(from: data, isAnthropic: upstreamProtocol == .anthropic)

            // Convert response if needed
            var responseBody: Data? = data
            if statusCode >= 200 && statusCode < 300 && incomingProtocol != upstreamProtocol {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let converted: [String: Any] = switch (incomingProtocol, upstreamProtocol) {
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

            routerCompleteRequest(requestID: reqIdString)

            return buildFinalResponse(
                statusCode: statusCode,
                body: responseBody ?? data,
                isStream: isStream,
                headers: responseHeaders
            )

        case .failure:
            routerCompleteRequest(requestID: reqIdString)
            return errorResponse(502, "All retry attempts failed")
        }
    }

    /// Set auth headers on a dictionary based on upstream protocol.
    /// Uses lowercase keys to match Swifter's lowercased header parsing.
    private func setAuthHeaders(_ headers: inout [String: String], apiKey: String, protocol: RequestForwarder.RequestProtocol) {
        switch `protocol` {
        case .anthropic:
            headers["x-api-key"] = apiKey
            headers["anthropic-version"] = "2023-06-01"
        case .openai, .unknown:
            headers["authorization"] = "Bearer \(apiKey)"
        }
    }

    /// Forward request synchronously
    private func forwardRequestSync(
        reqId _: Int64,
        url: URL,
        method: String = "POST",
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
                urlRequest.httpMethod = method
                if !body.isEmpty {
                    urlRequest.httpBody = body
                }
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

    /// Check if response body indicates a context_length_exceeded error
    private func isContextLengthExceeded(_ body: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return false
        }

        // OpenAI-style: error.code == "context_length_exceeded"
        if let error = json["error"] as? [String: Any] {
            if let code = error["code"] as? String, code == "context_length_exceeded" {
                return true
            }
            if let message = error["message"] as? String,
               message.localizedCaseInsensitiveContains("context") && message.localizedCaseInsensitiveContains("exceed") {
                return true
            }
            if let type = error["type"] as? String, type == "context_length_exceeded" {
                return true
            }
        }

        // Anthropic-style: error.type == "context_length_exceeded"
        if let error = json["error"] as? [String: Any],
           let type = error["type"] as? String,
           type == "context_length_exceeded" {
            return true
        }

        // Direct check
        if let type = json["type"] as? String, type == "context_length_exceeded" {
            return true
        }

        return false
    }

    /// Check if response body indicates a thinking budget error
    private func isThinkingBudgetIssue(_ body: Data) -> Bool {
        RequestForwarder.containsThinkingBudgetError(body)
    }

    /// Extract max_tokens from request body
    private func extractMaxTokens(from body: Data) -> Int? {
        RequestForwarder.extractMaxTokens(from: body)
    }

    /// Attempt thinking rectification: reduce budget_tokens to a safe value
    private func tryThinkingRectification(originalBody: Data, maxTokens: Int?) -> Data? {
        RequestForwarder.tryThinkingRectification(originalBody: originalBody, maxTokens: maxTokens)
    }

    /// Handle retry with a modified body (for thinking rectification)
    private func handleRetryWithModifiedBody(
        request: HttpRequest,
        targetProtocol: RequestForwarder.RequestProtocol,
        modifiedBody: Data,
        bodyData _: Data,
        incomingProtocol: RequestForwarder.RequestProtocol,
        channel: Channel,
        apiKey: String,
        reqId: Int64,
        startTime: Date,
        modelName: String?
    ) -> HttpResponse {
        let isStream = RequestForwarder.isStreamingRequest(modifiedBody)
        let upstreamProtocol = upstreamProtocol(for: channel, clientProtocol: targetProtocol)

        // Build upstream URL
        var components = URLComponents(string: channel.baseURL)
        components?.path = upstreamProtocol == .anthropic ? "/v1/messages" : "/v1/chat/completions"
        guard let upstreamURL = components?.url else {
            return errorResponse(500, "Invalid upstream URL")
        }

        // Convert protocol if needed
        let forwardedBody: Data
        var convertedHeaders = request.headers

        if incomingProtocol != upstreamProtocol {
            do {
                guard let json = try JSONSerialization.jsonObject(with: modifiedBody) as? [String: Any] else {
                    return errorResponse(400, "Invalid JSON body")
                }

                let converted: [String: Any] = switch (incomingProtocol, upstreamProtocol) {
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
            forwardedBody = modifiedBody
        }

        setAuthHeaders(&convertedHeaders, apiKey: apiKey, protocol: upstreamProtocol)

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
            if statusCode < 200 || statusCode >= 300 {
                let responseBodyStr = String(data: data, encoding: .utf8)?.prefix(500) ?? "nil"
                Log.error("[#\(reqId)] HTTP \(statusCode) after thinking rectification: \(responseBodyStr)")

                // If rectification failed, try standard failover
                if let retryDecision = routerHandleError(
                    requestID: "req-\(reqId)",
                    statusCode: statusCode,
                    modelName: modelName,
                    errorBody: data,
                    requestProtocol: targetProtocol
                ) {
                    return handleRetryRequest(
                        request: request,
                        targetProtocol: targetProtocol,
                        bodyData: modifiedBody,
                        incomingProtocol: incomingProtocol,
                        routingDecision: retryDecision,
                        reqId: reqId,
                        startTime: startTime
                    )
                }
            } else {
                routerRecordSuccess(channelID: channel.id)
            }

            let latency = Date().timeIntervalSince(startTime)
            let usage = RequestForwarder.parseUsage(from: data, isAnthropic: upstreamProtocol == .anthropic)

            var responseBody: Data? = data
            if statusCode >= 200 && statusCode < 300 && incomingProtocol != upstreamProtocol {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let converted: [String: Any] = switch (incomingProtocol, upstreamProtocol) {
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

            let cost = estimateCost(channel: channel, inputTokens: usage.input, outputTokens: usage.output)
            UsageTracker.shared.recordUsage(
                channelID: channel.id, channelName: channel.name,
                model: modelName ?? channel.models.first?.identifier ?? "unknown",
                inputTokens: usage.input, outputTokens: usage.output,
                estimatedCost: cost, latency: latency * 1000,
                statusCode: statusCode, isError: statusCode >= 400
            )

            routerCompleteRequest(requestID: "req-\(reqId)")

            return buildFinalResponse(
                statusCode: statusCode,
                body: responseBody ?? data,
                isStream: isStream,
                headers: responseHeaders
            )

        case let .failure(error):
            Log.error("[#\(reqId)] Thinking rectification retry failed: \(error.localizedDescription)")

            // Try standard failover
            if let retryDecision = routerHandleError(
                requestID: "req-\(reqId)",
                statusCode: 502,
                modelName: modelName
            ) {
                return handleRetryRequest(
                    request: request,
                    targetProtocol: targetProtocol,
                    bodyData: modifiedBody,
                    incomingProtocol: incomingProtocol,
                    routingDecision: retryDecision,
                    reqId: reqId,
                    startTime: startTime
                )
            }

            routerCompleteRequest(requestID: "req-\(reqId)")
            return errorResponse(502, "Upstream request failed after thinking rectification")
        }
    }

    /// Apply model override from ModelSwitcher to request body
    /// Returns modified body data with the selected model, or original body if no override
    private func applyModelOverride(body: Data, hasOverride: Bool, selectedModelID: String?) -> Data {
        // Check if user has selected a specific model
        guard hasOverride,
              let modelID = selectedModelID,
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

    // MARK: - Route parameter extraction

    /// Extract a path parameter value from a Swifter request.
    /// Swifter stores path params like `:modelId` in a `params` dictionary.
    private func extractPathParameter(from request: HttpRequest, named paramName: String) -> String? {
        // Swifter populates params for named routes like "/v1/models/:modelId"
        // The params dict is keyed by the param name without the colon
        return request.params[paramName]
    }

    // MARK: - New endpoint handlers

    // MARK: 1. Single model lookup — GET /v1/models/{id}

    private func handleSingleModelRequest(_ request: HttpRequest) -> HttpResponse {
        guard let modelId = extractPathParameter(from: request, named: "modelId") else {
            return errorResponse(400, "Missing model ID")
        }

        // Thread-safe: check cached models
        var foundModel: ModelEntry?
        var foundChannelName: String = "unknown"

        if ModelAggregator.shared.hasCachedModels() {
            let models = ModelAggregator.shared.allModels()
            foundModel = models.first { ModelSwitcher.modelMatches(requested: modelId, stored: $0.identifier) }
            if foundModel != nil {
                // Find which channel owns this model
                DispatchQueue.main.sync {
                    for channel in ChannelStore.shared.channels {
                        if channel.models.contains(where: { ModelSwitcher.modelMatches(requested: modelId, stored: $0.identifier) }) {
                            foundChannelName = channel.name
                            break
                        }
                    }
                }
                if let foundModel {
                    let modelJSON: [String: Any] = [
                        "id": foundModel.identifier,
                        "object": "model",
                        "created": Int(Date().timeIntervalSince1970),
                        "owned_by": foundChannelName
                    ]
                    return HttpResponse.ok(.json(modelJSON))
                }
            }
        }

        // Fallback: check ChannelStore directly
        DispatchQueue.main.sync {
            for channel in ChannelStore.shared.channels {
                if let model = channel.models.first(where: { ModelSwitcher.modelMatches(requested: modelId, stored: $0.identifier) }) {
                    foundModel = model
                    foundChannelName = channel.name
                    break
                }
            }
        }

        guard let model = foundModel else {
            return errorResponse(404, "Model '\(modelId)' not found")
        }

        let modelJSON: [String: Any] = [
            "id": model.identifier,
            "object": "model",
            "created": Int(Date().timeIntervalSince1970),
            "owned_by": foundChannelName
        ]
        return HttpResponse.ok(.json(modelJSON))
    }

    // MARK: 2,3,6,9. Auxiliary JSON endpoints (embeddings, images/generations, audio/speech, moderations)

    /// Handles POST requests with JSON body that forward to upstream without protocol conversion.
    /// These are single-operation endpoints — no failover chain.
    private func handleAuxiliaryRequest(_ request: HttpRequest, targetPath: String) -> HttpResponse {
        let reqId = nextRequestID()
        let startTime = Date()
        let reqIdString = "req-\(reqId)"

        Log.info("[#\(reqId)] \(request.method) \(request.path)")

        // Parse body to extract model name for routing
        guard !request.body.isEmpty else {
            return errorResponse(400, "Empty request body")
        }
        let bodyData = Data(request.body)
        let modelName = extractModelName(from: bodyData)

        // Thread-safe: read routing state
        guard let state = readRequestState(
            request: request,
            bodyData: bodyData,
            reqIdString: reqIdString
        ) else {
            Log.error("[#\(reqId)] No available channels or missing API key for \(targetPath)")
            return errorResponse(503, "No available channel")
        }

        let channel = state.channel
        let apiKey = state.apiKey

        // Thread-safe: read model override
        let override = readModelOverride()
        let effectiveBody = applyModelOverride(body: bodyData, hasOverride: override.hasOverride, selectedModelID: override.selectedModelID)

        // Determine target protocol based on channel
        let targetProtocol: RequestForwarder.RequestProtocol
        switch channel.protocol {
        case .anthropic:
            targetProtocol = .anthropic
        case .openai, .auto:
            targetProtocol = .openai
        }

        // Build upstream URL
        var components = URLComponents(string: channel.baseURL)
        components?.path = targetPath
        guard let upstreamURL = components?.url else {
            return errorResponse(500, "Invalid upstream URL")
        }

        // Build headers with auth
        var headers = request.headers
        headers["content-type"] = "application/json"
        headers["content-length"] = String(effectiveBody.count)
        setAuthHeaders(&headers, apiKey: apiKey, protocol: targetProtocol)
        headers.removeValue(forKey: "host")

        // Forward request
        let result = forwardRequestSync(
            reqId: reqId,
            url: upstreamURL,
            headers: headers,
            body: effectiveBody,
            timeout: 120
        )

        switch result {
        case let .success(data, statusCode, responseHeaders):
            let latency = Date().timeIntervalSince(startTime)

            // Record success
            if statusCode >= 200 && statusCode < 300 {
                routerRecordSuccess(channelID: channel.id)
            }

            // Record usage
            let usage = RequestForwarder.parseUsage(from: data, isAnthropic: targetProtocol == .anthropic)
            let cost = estimateCost(channel: channel, inputTokens: usage.input, outputTokens: usage.output)
            UsageTracker.shared.recordUsage(
                channelID: channel.id, channelName: channel.name,
                model: modelName ?? channel.models.first?.identifier ?? "unknown",
                inputTokens: usage.input, outputTokens: usage.output,
                estimatedCost: cost, latency: latency * 1000,
                statusCode: statusCode, isError: statusCode >= 400
            )

            routerCompleteRequest(requestID: reqIdString)

            return buildFinalResponse(
                statusCode: statusCode,
                body: data,
                isStream: false,
                headers: responseHeaders
            )

        case let .failure(error):
            Log.error("[#\(reqId)] Forward failed: \(error.localizedDescription)")
            routerCompleteRequest(requestID: reqIdString)
            return errorResponse(502, "Upstream request failed")
        }
    }

    // MARK: 4,5,7,8. Multipart endpoints (images/edits, images/variations, audio/transcriptions, audio/translations)

    /// Handles POST requests with multipart/form-data body.
    /// Raw body bytes are forwarded directly without parsing.
    private func handleMultipartRequest(_ request: HttpRequest, targetPath: String) -> HttpResponse {
        let reqId = nextRequestID()
        let startTime = Date()
        let reqIdString = "req-\(reqId)"

        Log.info("[#\(reqId)] \(request.method) \(request.path)")

        // Get the raw body bytes
        guard !request.body.isEmpty else {
            return errorResponse(400, "Empty request body")
        }
        let bodyData = Data(request.body)

        // Try to extract model name from multipart body (may fail for audio endpoints)
        let modelName = extractModelNameFromMultipart(bodyData)

        // Thread-safe: read routing state (may not find model, will use first channel)
        guard let state = readRequestState(
            request: request,
            bodyData: bodyData,
            reqIdString: reqIdString
        ) else {
            // Fallback: use first available channel, with model override applied
            guard let fallbackChannel = getFirstAvailableChannel() else {
                Log.error("[#\(reqId)] No available channels for \(targetPath)")
                return errorResponse(503, "No available channel")
            }
            let override = readModelOverride()
            let effectiveBody = applyModelOverride(body: bodyData, hasOverride: override.hasOverride, selectedModelID: override.selectedModelID)
            return forwardMultipartWithChannel(
                request: request, bodyData: effectiveBody, channel: fallbackChannel,
                targetPath: targetPath, reqId: reqId, startTime: startTime,
                reqIdString: reqIdString, modelName: modelName
            )
        }

        return forwardMultipartWithChannel(
            request: request, bodyData: bodyData, channel: state.channel,
            targetPath: targetPath, reqId: reqId, startTime: startTime,
            reqIdString: reqIdString, modelName: modelName
        )
    }

    /// Forward a multipart request using a specific channel.
    private func forwardMultipartWithChannel(
        request: HttpRequest,
        bodyData: Data,
        channel: Channel,
        targetPath: String,
        reqId: Int64,
        startTime: Date,
        reqIdString: String,
        modelName: String?
    ) -> HttpResponse {
        guard let apiKey = KeychainManager.shared.getAPIKey(for: channel.id),
              !apiKey.isEmpty
        else {
            routerCompleteRequest(requestID: reqIdString)
            return errorResponse(503, "No API key for channel")
        }

        // Determine target protocol based on channel
        let targetProtocol: RequestForwarder.RequestProtocol
        switch channel.protocol {
        case .anthropic:
            targetProtocol = .anthropic
        case .openai, .auto:
            targetProtocol = .openai
        }

        // Build upstream URL
        var components = URLComponents(string: channel.baseURL)
        components?.path = targetPath
        guard let upstreamURL = components?.url else {
            routerCompleteRequest(requestID: reqIdString)
            return errorResponse(500, "Invalid upstream URL")
        }

        // Forward multipart body as-is, preserving content-type boundary
        var headers = request.headers
        setAuthHeaders(&headers, apiKey: apiKey, protocol: targetProtocol)
        headers.removeValue(forKey: "host")
        // Keep original content-type (multipart boundary) and content-length
        if headers["content-type"] == nil {
            headers["content-type"] = "multipart/form-data"
        }

        let result = forwardRequestSync(
            reqId: reqId,
            url: upstreamURL,
            headers: headers,
            body: bodyData,
            timeout: 300  // Longer timeout for audio/image processing
        )

        switch result {
        case let .success(data, statusCode, responseHeaders):
            let latency = Date().timeIntervalSince(startTime)

            if statusCode >= 200 && statusCode < 300 {
                routerRecordSuccess(channelID: channel.id)
            }

            // Record usage (best effort — multipart responses may not have usage)
            let usage = RequestForwarder.parseUsage(from: data, isAnthropic: targetProtocol == .anthropic)
            let cost = estimateCost(channel: channel, inputTokens: usage.input, outputTokens: usage.output)
            UsageTracker.shared.recordUsage(
                channelID: channel.id, channelName: channel.name,
                model: modelName ?? channel.models.first?.identifier ?? "unknown",
                inputTokens: usage.input, outputTokens: usage.output,
                estimatedCost: cost, latency: latency * 1000,
                statusCode: statusCode, isError: statusCode >= 400
            )

            routerCompleteRequest(requestID: reqIdString)

            // For binary responses (audio/image), forward content-type from upstream
            var responseContentType = "application/json"
            if let ct = responseHeaders["content-type"]?.lowercased() {
                if ct.contains("audio") || ct.contains("image") || ct.contains("octet-stream") {
                    responseContentType = ct
                }
            }
            var finalHeaders: [String: String] = ["content-type": responseContentType]
            finalHeaders["content-length"] = String(data.count)
            for (key, value) in responseHeaders {
                if key.lowercased().hasPrefix("x-") || key.lowercased() == "retry-after" || key.lowercased() == "request-id" {
                    finalHeaders[key] = value
                }
            }

            return rawResponse(statusCode: statusCode, headers: finalHeaders, body: data)

        case let .failure(error):
            Log.error("[#\(reqId)] Multipart forward failed: \(error.localizedDescription)")
            routerCompleteRequest(requestID: reqIdString)
            return errorResponse(502, "Upstream request failed")
        }
    }

    /// Attempt to extract model name from multipart body by scanning for 'model' field.
    /// This is a best-effort heuristic for multipart/form-data.
    private func extractModelNameFromMultipart(_ data: Data) -> String? {
        guard let bodyStr = String(data: data, encoding: .utf8) else { return nil }
        // Look for the model field in multipart form data
        // Pattern: ...Content-Disposition: form-data; name="model"\r\n\r\n<model_name>
        let patterns = ["name=\"model\"\r\n\r\n", "name=\"model\"\n\n"]
        for pattern in patterns {
            if let range = bodyStr.range(of: pattern) {
                let afterModel = bodyStr[range.upperBound...]
                // The value ends at the next boundary or end of string
                let endPattern = "\r\n--"
                if let endRange = afterModel.range(of: endPattern) {
                    return String(afterModel[..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return String(afterModel).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    /// Get the first available channel as fallback.
    private func getFirstAvailableChannel() -> Channel? {
        var result: Channel?
        DispatchQueue.main.sync {
            result = ChannelStore.shared.channels.first
        }
        return result
    }

    /// Get the first available OpenAI-protocol channel (for OpenAI-only APIs like Files).
    private func getFirstOpenAIChannel() -> Channel? {
        var result: Channel?
        DispatchQueue.main.sync {
            for channel in ChannelStore.shared.channels {
                switch channel.protocol {
                case .openai, .auto:
                    result = channel
                    return
                case .anthropic:
                    break
                }
            }
        }
        return result
    }

    // MARK: 10,11. Files API endpoints

    /// Handles all Files API requests (list, upload, retrieve, delete, download).
    /// Uses the first available channel — no model matching needed.
    private func handleFilesRequest(
        _ request: HttpRequest,
        method: String,
        isContent: Bool = false
    ) -> HttpResponse {
        let reqId = nextRequestID()
        let startTime = Date()
        let reqIdString = "req-\(reqId)"

        Log.info("[#\(reqId)] \(request.method) \(request.path) (files)")

        // Use first available OpenAI channel (Files API is OpenAI-only)
        guard let channel = getFirstOpenAIChannel() else {
            return errorResponse(503, "No available OpenAI channel for Files API")
        }

        guard let apiKey = KeychainManager.shared.getAPIKey(for: channel.id),
              !apiKey.isEmpty
        else {
            return errorResponse(503, "No API key for channel")
        }

        // Build upstream URL
        var components = URLComponents(string: channel.baseURL)
        if isContent {
            // /v1/files/{id}/content → /v1/files/{id}/content
            if let fileId = extractPathParameter(from: request, named: "fileId") {
                components?.path = "/v1/files/\(fileId)/content"
            } else {
                return errorResponse(400, "Missing file ID")
            }
        } else if request.path.hasPrefix("/v1/files/") {
            // /v1/files/{id} → pass through path with fileId
            if let fileId = extractPathParameter(from: request, named: "fileId") {
                components?.path = "/v1/files/\(fileId)"
            } else {
                components?.path = "/v1/files"
            }
        } else {
            components?.path = "/v1/files"
        }

        // Forward query parameters (e.g., ?purpose=...)
        if !request.queryParams.isEmpty {
            components?.queryItems = request.queryParams.map { URLQueryItem(name: $0.0, value: $0.1) }
        }

        guard let upstreamURL = components?.url else {
            return errorResponse(500, "Invalid upstream URL")
        }

        // Determine protocol
        let targetProtocol: RequestForwarder.RequestProtocol
        switch channel.protocol {
        case .anthropic:
            targetProtocol = .anthropic
        case .openai, .auto:
            targetProtocol = .openai
        }

        // Build headers
        var headers = request.headers
        setAuthHeaders(&headers, apiKey: apiKey, protocol: targetProtocol)
        headers.removeValue(forKey: "host")

        // Body: only for POST (upload)
        let bodyData: Data
        if method == "POST" && !request.body.isEmpty {
            bodyData = Data(request.body)
            // Ensure content-type and content-length are set
            if headers["content-length"] == nil {
                headers["content-length"] = String(bodyData.count)
            }
        } else {
            bodyData = Data()
        }

        // Forward request with method
        let result = forwardRequestSync(
            reqId: reqId,
            url: upstreamURL,
            method: method,
            headers: headers,
            body: bodyData,
            timeout: 300
        )

        switch result {
        case let .success(data, statusCode, responseHeaders):
            let latency = Date().timeIntervalSince(startTime)

            if statusCode >= 200 && statusCode < 300 {
                routerRecordSuccess(channelID: channel.id)
            }

            // Record usage (best effort)
            let usage = RequestForwarder.parseUsage(from: data, isAnthropic: targetProtocol == .anthropic)
            let cost = estimateCost(channel: channel, inputTokens: usage.input, outputTokens: usage.output)
            UsageTracker.shared.recordUsage(
                channelID: channel.id, channelName: channel.name,
                model: channel.models.first?.identifier ?? "unknown",
                inputTokens: usage.input, outputTokens: usage.output,
                estimatedCost: cost, latency: latency * 1000,
                statusCode: statusCode, isError: statusCode >= 400
            )

            routerCompleteRequest(requestID: reqIdString)

            // Forward upstream content-type for binary downloads
            var responseContentType = "application/json"
            if let ct = responseHeaders["content-type"]?.lowercased() {
                if ct.contains("octet-stream") || ct.contains("application/octet") {
                    responseContentType = ct
                } else {
                    responseContentType = responseHeaders["content-type"] ?? "application/json"
                }
            }
            var finalHeaders: [String: String] = ["content-type": responseContentType]
            finalHeaders["content-length"] = String(data.count)
            for (key, value) in responseHeaders {
                if key.lowercased().hasPrefix("x-") || key.lowercased() == "retry-after" || key.lowercased() == "request-id" {
                    finalHeaders[key] = value
                }
            }

            return rawResponse(statusCode: statusCode, headers: finalHeaders, body: data)

        case let .failure(error):
            Log.error("[#\(reqId)] Files API forward failed: \(error.localizedDescription)")
            routerCompleteRequest(requestID: reqIdString)
            return errorResponse(502, "Upstream request failed")
        }
    }

    private func handleModelsRequest() -> HttpResponse {
        // Fast path: If we have cached models, return them immediately.
        if ModelAggregator.shared.hasCachedModels() {
            let models = ModelAggregator.shared.allModels()
            let modelsJSON = models.map { model in
                ["id": model.identifier, "object": "model",
                 "created": Int(Date().timeIntervalSince1970),
                 "owned_by": "aggregated"] as [String: Any]
            }
            return HttpResponse.ok(.json(["object": "list", "data": modelsJSON]))
        }

        // First request path: Block and wait for the fetch to complete.
        // We use a semaphore to bridge the async fetch into this sync handler.
        // Timeout is set to 8s (5s request timeout + 3s processing buffer).
        let semaphore = DispatchSemaphore(value: 0)
        var fetchCompleted = false

        Task {
            await ModelAggregator.shared.fetchAllModelsIfNeeded()
            fetchCompleted = true
            semaphore.signal()
        }

        // Wait for the fetch to finish, but don't wait forever.
        let waitResult = semaphore.wait(timeout: .now() + 8)

        if waitResult == .success && fetchCompleted {
            // Fetch succeeded, return fresh models
            let models = ModelAggregator.shared.allModels()
            let modelsJSON = models.map { model in
                ["id": model.identifier, "object": "model",
                 "created": Int(Date().timeIntervalSince1970),
                 "owned_by": "aggregated"] as [String: Any]
            }
            return HttpResponse.ok(.json(["object": "list", "data": modelsJSON]))
        }

        // Fallback path: Timeout or fetch failed.
        // Return whatever static models we have in ChannelStore to avoid empty response.
        Log.warn("[Proxy] /v1/models fetch timed out or failed, returning fallback models")
        var fallbackModels: [[String: Any]] = []
        DispatchQueue.main.sync {
            let channels = ChannelStore.shared.channels
            for channel in channels {
                for model in channel.models {
                    fallbackModels.append([
                        "id": model.identifier, "object": "model",
                        "created": Int(Date().timeIntervalSince1970),
                        "owned_by": channel.name
                    ])
                }
            }
        }
        
        return HttpResponse.ok(.json(["object": "list", "data": fallbackModels]))
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

    var enabledChannels: [Channel] {
        channels.filter(\.isEnabled)
    }

    var activeChannel: Channel? {
        guard let id = activeChannelID else { return enabledChannels.first }
        return channels.first { $0.id == id && $0.isEnabled } ?? enabledChannels.first
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
        // Prevent adding duplicate base URLs
        if channels.contains(where: { $0.baseURL.lowercased() == channel.baseURL.lowercased() }) {
            Log.info("[ChannelStore] Skipping duplicate channel: \\(channel.baseURL)")
            return
        }

        channels.append(channel)
        if activeChannelID == nil, channel.isEnabled { activeChannelID = channel.id }
        saveChannels()
    }

    func removeChannel(id: String) {
        channels.removeAll { $0.id == id }
        if activeChannelID == id { activeChannelID = enabledChannels.first?.id }
        saveChannels()
    }

    func updateChannel(_ channel: Channel) {
        if let index = channels.firstIndex(where: { $0.id == channel.id }) {
            channels[index] = channel
            saveChannels()
        }
    }

    func setActiveChannel(id: String) {
        guard channels.contains(where: { $0.id == id && $0.isEnabled }) else {
            return
        }
        activeChannelID = id
        saveChannels()
    }

    func setChannelEnabled(id: String, isEnabled: Bool) {
        guard let index = channels.firstIndex(where: { $0.id == id }) else {
            return
        }

        channels[index].isEnabled = isEnabled
        if !isEnabled, activeChannelID == id {
            activeChannelID = enabledChannels.first?.id
        } else if isEnabled, activeChannelID == nil {
            activeChannelID = id
        }
        saveChannels()
    }

    func moveChannel(from source: IndexSet, to destination: Int) {
        channels.move(fromOffsets: source, toOffset: destination)
        // Update priority based on new order
        for (index, channel) in channels.enumerated() {
            channels[index].priority = index + 1
        }
        saveChannels()
    }
}
