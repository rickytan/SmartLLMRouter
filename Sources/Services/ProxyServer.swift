import Foundation
import Swifter

private final class ChunkedResponseWriter: HttpResponseBodyWriter {
    private let writer: HttpResponseBodyWriter
    private let lock = NSLock()
    private var finished = false

    init(_ writer: HttpResponseBodyWriter) {
        self.writer = writer
    }

    func write(_ file: String.File) throws {
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = try file.read(&buffer)
            guard count > 0 else { return }
            try write(ArraySlice(buffer.prefix(count)))
        }
    }

    func write(_ data: [UInt8]) throws {
        try write(ArraySlice(data))
    }

    func write(_ data: ArraySlice<UInt8>) throws {
        try write(Data(data))
    }

    func write(_ data: NSData) throws {
        try write(data as Data)
    }

    func write(_ data: Data) throws {
        guard !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }

        try writer.write(Data(String(data.count, radix: 16).utf8))
        try writer.write(Data("\r\n".utf8))
        try writer.write(data)
        try writer.write(Data("\r\n".utf8))
    }

    func finish() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        try writer.write(Data("0\r\n\r\n".utf8))
    }
}

@MainActor
final class ProxyServer: ObservableObject {
    private let httpServer = HttpServer()
    private let services: RouterServices
    private let modelEndpointHandler: ModelEndpointHandler
    private let filesEndpointHandler: FilesEndpointHandler
    private let auxiliaryEndpointHandler: AuxiliaryEndpointHandler
    private let multipartEndpointHandler: MultipartEndpointHandler
    private let forwardingClient = HTTPForwardingClient()
    private let requestIDGenerator = RequestIDGenerator()

    @Published var isRunning: Bool = false
    @Published var port: Int = 1897
    @Published var lastError: String?

    private let upstreamTimeout: TimeInterval = 300
    private let streamingTimeout: TimeInterval = 3_600
    private let streamingFirstByteTimeout: TimeInterval = 45
    private let streamingPreBodyBudget: TimeInterval = 180
    private let streamingKeepaliveInterval: TimeInterval = 15

    private func nextRequestID() -> Int64 {
        requestIDGenerator.next()
    }

    init(services: RouterServices) {
        self.services = services
        modelEndpointHandler = ModelEndpointHandler(services: services)
        filesEndpointHandler = FilesEndpointHandler(
            services: services,
            forwardingClient: forwardingClient,
            requestIDGenerator: requestIDGenerator
        )
        auxiliaryEndpointHandler = AuxiliaryEndpointHandler(
            services: services,
            forwardingClient: forwardingClient,
            requestIDGenerator: requestIDGenerator,
            upstreamTimeout: upstreamTimeout
        )
        multipartEndpointHandler = MultipartEndpointHandler(
            services: services,
            forwardingClient: forwardingClient,
            requestIDGenerator: requestIDGenerator
        )
        setupRoutes()
    }

    @discardableResult
    func start(port: Int? = nil) -> Bool {
        // Thread-safe early exit: if already running, do nothing.
        // Since this class is @MainActor, calls are serialized on the main queue.
        guard !isRunning else {
            Log.info("Proxy already running on port \(self.port), skipping start")
            return true
        }

        let usePort = port ?? self.port
        do {
            try httpServer.start(in_port_t(usePort), forceIPv4: true)
            isRunning = true
            lastError = nil
            self.port = usePort
            Log.info("Proxy started on port \(usePort)")
            return true
        } catch {
            lastError = error.localizedDescription
            Log.error("Failed to start proxy: \(error.localizedDescription)")
            isRunning = false
            return false
        }
    }

    func stop() {
        httpServer.stop()
        isRunning = false
        lastError = nil
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
                "port": portNum
            ]
            return HttpResponse.ok(.json(json))
        }

        httpServer.get["/v1/models"] = { [weak self] _ in
            guard let self else { return HttpResponse.internalServerError }
            return self.modelEndpointHandler.handleListModels()
        }

        // MARK: - New API Endpoints

        // 1. Single model lookup
        httpServer["/v1/models/:modelId"] = { [weak self] request in
            guard let self else { return HttpResponse.internalServerError }
            return self.modelEndpointHandler.handleSingleModel(modelId: self.extractPathParameter(from: request, named: "modelId"))
        }

        // 2. Embeddings
        httpServer.post["/v1/embeddings"] = { [weak self] request in
            guard let self else { return HttpResponse.internalServerError }
            return self.auxiliaryEndpointHandler.handle(request, targetPath: "/v1/embeddings")
        }

        // 3. Image generation
        httpServer.post["/v1/images/generations"] = { [weak self] request in
            guard let self else { return HttpResponse.internalServerError }
            return self.auxiliaryEndpointHandler.handle(request, targetPath: "/v1/images/generations")
        }

        // 4. Image edits (multipart)
        httpServer.post["/v1/images/edits"] = { [weak self] request in
            guard let self else { return HttpResponse.internalServerError }
            return self.multipartEndpointHandler.handle(request, targetPath: "/v1/images/edits")
        }

        // 5. Image variations (multipart)
        httpServer.post["/v1/images/variations"] = { [weak self] request in
            guard let self else { return HttpResponse.internalServerError }
            return self.multipartEndpointHandler.handle(request, targetPath: "/v1/images/variations")
        }

        // 6. TTS
        httpServer.post["/v1/audio/speech"] = { [weak self] request in
            guard let self else { return HttpResponse.internalServerError }
            return self.auxiliaryEndpointHandler.handle(request, targetPath: "/v1/audio/speech")
        }

        // 7. Audio transcriptions (multipart)
        httpServer.post["/v1/audio/transcriptions"] = { [weak self] request in
            guard let self else { return HttpResponse.internalServerError }
            return self.multipartEndpointHandler.handle(request, targetPath: "/v1/audio/transcriptions")
        }

        // 8. Audio translations (multipart)
        httpServer.post["/v1/audio/translations"] = { [weak self] request in
            guard let self else { return HttpResponse.internalServerError }
            return self.multipartEndpointHandler.handle(request, targetPath: "/v1/audio/translations")
        }

        // 9. Moderations
        httpServer.post["/v1/moderations"] = { [weak self] request in
            guard let self else { return HttpResponse.internalServerError }
            return self.auxiliaryEndpointHandler.handle(request, targetPath: "/v1/moderations")
        }

        // 10. Files list/upload
        httpServer.get["/v1/files"] = { [weak self] request in
            guard let self else { return HttpResponse.internalServerError }
            return self.filesEndpointHandler.handle(request, method: "GET")
        }
        httpServer.post["/v1/files"] = { [weak self] request in
            guard let self else { return HttpResponse.internalServerError }
            return self.filesEndpointHandler.handle(request, method: "POST")
        }

        // 11. Files detail/delete/content
        httpServer["/v1/files/:fileId"] = { [weak self] request in
            guard let self else { return HttpResponse.internalServerError }
            let method = request.method.uppercased()
            if method == "GET" || method == "DELETE" {
                return self.filesEndpointHandler.handle(request, method: method)
            }
            return self.errorResponse(405, "Method not allowed")
        }
        httpServer.get["/v1/files/:fileId/content"] = { [weak self] request in
            guard let self else { return HttpResponse.internalServerError }
            return self.filesEndpointHandler.handle(request, method: "GET", isContent: true)
        }
    }

    // MARK: - Thread-safe state bridge

    /// Captures shared state from @MainActor services in a single main-thread hop.
    /// This struct is Sendable (all fields are value types) and safe to use on any thread.
    struct RequestState {
        let channel: Channel
        let apiKeys: [String]
        let routingDecision: RoutingDecision
    }

    private func readRequestState(
        request _: HttpRequest,
        bodyData: Data,
        reqIdString: String
    ) -> RequestState? {
        let modelName = extractModelName(from: bodyData)
        let override = services.modelOverrideState.snapshot()
        let routingModelName = override.selectedModelID ?? modelName
        guard let decision = services.runtimeState.selectChannel(
            requestID: reqIdString,
            modelName: routingModelName
        ) else {
            return nil
        }
        let apiKeys = services.channelServices.apiKeys(for: decision.channel.id)
        guard !apiKeys.isEmpty
        else {
            return nil
        }
        return RequestState(
            channel: decision.channel,
            apiKeys: apiKeys,
            routingDecision: decision
        )
    }

    private func readModelOverride() -> (hasOverride: Bool, selectedModelID: String?) {
        services.modelOverrideState.snapshot()
    }

    private func routerRecordSuccess(channelID: String) {
        services.runtimeState.recordSuccess(channelID: channelID)
    }

    private func routerHandleError(
        requestID: String,
        statusCode: Int,
        modelName: String?,
        errorBody: Data? = nil,
        requestProtocol: RequestForwarder.RequestProtocol? = nil
    ) -> RoutingDecision? {
        services.runtimeState.handleError(
            requestID: requestID,
            statusCode: statusCode,
            modelName: modelName,
            errorBody: errorBody,
            requestProtocol: requestProtocol
        )
    }

    private func routerCompleteRequest(requestID: String) {
        services.runtimeState.completeRequest(requestID: requestID)
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

    /// Build upstream URL from channel's baseURL, appending the correct endpoint.
    /// - If baseURL has no path, prepends /v1.
    /// - If baseURL path ends with a version (e.g. /v1, /v3), strips /v1 from endpoint.
    /// - If baseURL path has content but no version, keeps full /v1 endpoint.
    private func buildUpstreamURL(for channel: Channel, protocol: RequestForwarder.RequestProtocol) -> URL? {
        guard let baseURL = channel.baseURL(for: `protocol`) else {
            return nil
        }
        return URLBuilder.buildUpstreamURL(baseURL: baseURL, protocol: `protocol`)
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
        let parsedAt = Date()
        let parseLatency = String(format: "%.3f", parsedAt.timeIntervalSince(startTime))
        let streamFlag = RequestForwarder.isStreamingRequest(bodyData)
        Log.info("[#\(reqId)] Request parsed model=\(modelName ?? "unknown") stream=\(streamFlag) in \(parseLatency)s")

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
        let apiKeys = state.apiKeys
        let routingDecision = state.routingDecision
        Log.info("[#\(reqId)] Routed to \(channel.name) in \(String(format: "%.3f", Date().timeIntervalSince(startTime)))s")

        let isStream = RequestForwarder.isStreamingRequest(bodyData)
        if isStream {
            return buildStreamingForwardResponse(
                request: request,
                targetProtocol: targetProtocol,
                bodyData: bodyData,
                incomingProtocol: incomingProtocol,
                routingDecision: routingDecision,
                reqId: reqId,
                startTime: startTime
            )
        }

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
        guard let upstreamURL = buildUpstreamURL(for: channel, protocol: upstreamProtocol) else {
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

        // Remove hop-by-hop headers
        convertedHeaders.removeValue(forKey: "host")

        // Forward request via URLSession
        let keyForwardResult = forwardingClient.forwardSyncWithAPIKeyFailover(
            url: upstreamURL,
            headers: convertedHeaders,
            body: forwardedBody,
            timeout: upstreamTimeout,
            apiKeys: apiKeys,
            targetProtocol: upstreamProtocol,
            channelName: channel.name,
            requestID: "#\(reqId)",
            channelID: channel.id,
            apiKeyAvailabilityStore: services.apiKeyAvailabilityStore
        )
        let result = keyForwardResult.result

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
                        apiKeys: apiKeys,
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
                responseBody = convertResponseBodyIfNeeded(
                    data: data,
                    isStream: isStream,
                    incomingProtocol: incomingProtocol,
                    upstreamProtocol: upstreamProtocol,
                    model: routingDecision.effectiveModel ?? modelName ?? channel.models.first?.identifier ?? "unknown",
                    requestID: "#\(reqId)"
                )
            }

            // Record usage
            let cost = estimateCost(channel: channel, inputTokens: usage.input, outputTokens: usage.output)
            services.usageTracker.recordUsage(
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
            Log.error("[#\(reqId)] Forward failed: \(error.localizedDescription)")

            // Determine if this is a timeout for special retry handling
            let isTimeout = (error as? URLError)?.code == .timedOut
            let statusCode = isTimeout ? 408 : 502

            // Try to retry — single call (previous code called handleError twice,
            // which double-counted circuit breaker failures and retry attempts)
            if let retryDecision = routerHandleError(
                requestID: reqIdString,
                statusCode: statusCode,
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

            services.usageTracker.recordUsage(
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

        let apiKeys = services.channelServices.apiKeys(for: channel.id)
        guard !apiKeys.isEmpty
        else {
            routerCompleteRequest(requestID: reqIdString)
            return errorResponse(503, "No API key for retry channel")
        }

        let isStream = RequestForwarder.isStreamingRequest(bodyData)
        if isStream {
            return buildStreamingForwardResponse(
                request: request,
                targetProtocol: targetProtocol,
                bodyData: bodyData,
                incomingProtocol: incomingProtocol,
                routingDecision: routingDecision,
                reqId: reqId,
                startTime: startTime
            )
        }

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
        guard let upstreamURL = buildUpstreamURL(for: channel, protocol: upstreamProtocol) else {
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

        convertedHeaders.removeValue(forKey: "host")

        // Forward request
        let keyForwardResult = forwardingClient.forwardSyncWithAPIKeyFailover(
            url: upstreamURL,
            headers: convertedHeaders,
            body: forwardedBody,
            timeout: upstreamTimeout,
            apiKeys: apiKeys,
            targetProtocol: upstreamProtocol,
            channelName: channel.name,
            requestID: "#\(reqId)",
            channelID: channel.id,
            apiKeyAvailabilityStore: services.apiKeyAvailabilityStore
        )
        let result = keyForwardResult.result

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
                responseBody = convertResponseBodyIfNeeded(
                    data: data,
                    isStream: isStream,
                    incomingProtocol: incomingProtocol,
                    upstreamProtocol: upstreamProtocol,
                    model: routingDecision.effectiveModel ?? extractModelName(from: bodyData) ?? channel.models.first?.identifier ?? "unknown",
                    requestID: "#\(reqId)"
                )
            }

            // Record usage for retry channel
            let cost = estimateCost(channel: channel, inputTokens: usage.input, outputTokens: usage.output)
            services.usageTracker.recordUsage(
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
        apiKeys: [String],
        reqId: Int64,
        startTime: Date,
        modelName: String?
    ) -> HttpResponse {
        let isStream = RequestForwarder.isStreamingRequest(modifiedBody)
        let upstreamProtocol = upstreamProtocol(for: channel, clientProtocol: targetProtocol)

        // Build upstream URL
        guard let upstreamURL = buildUpstreamURL(for: channel, protocol: upstreamProtocol) else {
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

        convertedHeaders.removeValue(forKey: "host")

        // Forward request
        let keyForwardResult = forwardingClient.forwardSyncWithAPIKeyFailover(
            url: upstreamURL,
            headers: convertedHeaders,
            body: forwardedBody,
            timeout: upstreamTimeout,
            apiKeys: apiKeys,
            targetProtocol: upstreamProtocol,
            channelName: channel.name,
            requestID: "#\(reqId)",
            channelID: channel.id,
            apiKeyAvailabilityStore: services.apiKeyAvailabilityStore
        )
        let result = keyForwardResult.result

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
                responseBody = convertResponseBodyIfNeeded(
                    data: data,
                    isStream: isStream,
                    incomingProtocol: incomingProtocol,
                    upstreamProtocol: upstreamProtocol,
                    model: modelName ?? channel.models.first?.identifier ?? "unknown",
                    requestID: "#\(reqId)"
                )
            }

            let cost = estimateCost(channel: channel, inputTokens: usage.input, outputTokens: usage.output)
            services.usageTracker.recordUsage(
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
        let upstreamContentType = headers.first { $0.key.lowercased() == "content-type" }?.value
        responseHeaders["content-type"] = upstreamContentType
            ?? (isStream ? "text/event-stream" : "application/json")
        responseHeaders["content-length"] = String(body.count)
        for (key, value) in headers {
            if key.lowercased().hasPrefix("x-") || key.lowercased() == "retry-after" {
                responseHeaders[key] = value
            }
        }
        return rawResponse(statusCode: statusCode, headers: responseHeaders, body: body)
    }

    private func buildStreamingForwardResponse(
        request: HttpRequest,
        targetProtocol: RequestForwarder.RequestProtocol,
        bodyData: Data,
        incomingProtocol: RequestForwarder.RequestProtocol,
        routingDecision: RoutingDecision,
        reqId: Int64,
        startTime: Date
    ) -> HttpResponse {
        let responseHeaders = [
            "content-type": "text/event-stream",
            "cache-control": "no-cache",
            "transfer-encoding": "chunked",
            "connection": "close",
        ]
        let requestDeadline = startTime.addingTimeInterval(streamingPreBodyBudget)

        return HttpResponse.raw(200, "OK", responseHeaders) { [self] rawWriter in
            let writer = ChunkedResponseWriter(rawWriter)
            defer {
                do {
                    try writer.finish()
                    Log.debug("[#\(reqId)] Finished chunked streaming response")
                } catch {
                    Log.warn("[#\(reqId)] Failed to finish chunked streaming response: \(error.localizedDescription)")
                }
            }
            let reqIdString = "req-\(reqId)"
            var currentDecision: RoutingDecision? = routingDecision
            var finalMessage = "Upstream streaming request failed"

            while let decision = currentDecision {
                currentDecision = nil
                let channel = decision.channel
                let model = decision.effectiveModel ?? self.extractModelName(from: bodyData) ?? channel.models.first?.identifier ?? "unknown"
                let apiKeys = self.services.channelServices.apiKeys(for: channel.id)

                guard !apiKeys.isEmpty else {
                    finalMessage = "No API key configured for \(channel.name)"
                    Log.error("[#\(reqId)] \(finalMessage)")
                    self.services.usageTracker.recordUsage(
                        channelID: channel.id,
                        channelName: channel.name,
                        model: model,
                        inputTokens: 0,
                        outputTokens: 0,
                        estimatedCost: 0,
                        latency: Date().timeIntervalSince(startTime) * 1000,
                        statusCode: 502,
                        isError: true
                    )
                    if let retryDecision = self.routerHandleError(
                        requestID: reqIdString,
                        statusCode: 502,
                        modelName: self.extractModelName(from: bodyData),
                        requestProtocol: targetProtocol
                    ) {
                        Log.info("[#\(reqId)] Retrying streaming request with channel \(retryDecision.channel.name)")
                        currentDecision = retryDecision
                        continue
                    }
                    StreamingForwarder.writeErrorEvent(finalMessage, requestID: "#\(reqId)", targetProtocol: incomingProtocol, to: writer)
                    self.routerCompleteRequest(requestID: reqIdString)
                    return
                }

                let override = self.readModelOverride()
                let effectiveBody = self.applyModelOverride(
                    body: bodyData,
                    hasOverride: override.hasOverride,
                    selectedModelID: override.selectedModelID
                )

                var swappedBody = effectiveBody
                if let orig = decision.originalModel,
                   let eff = decision.effectiveModel,
                   orig != eff,
                   let swapped = RequestForwarder.swapModel(in: effectiveBody, newModel: eff) {
                    Log.info("Smart fallback: model swapped from \(orig) to \(eff) for streaming on channel \(channel.name)")
                    swappedBody = swapped
                }

                let upstreamProtocol = self.upstreamProtocol(for: channel, clientProtocol: targetProtocol)
                guard let upstreamURL = self.buildUpstreamURL(for: channel, protocol: upstreamProtocol) else {
                    finalMessage = "Invalid upstream URL"
                    Log.error("[#\(reqId)] \(finalMessage) for streaming channel \(channel.name)")
                    StreamingForwarder.writeErrorEvent(finalMessage, requestID: "#\(reqId)", targetProtocol: incomingProtocol, to: writer)
                    self.routerCompleteRequest(requestID: reqIdString)
                    return
                }

                let forwardedBody: Data
                var convertedHeaders = request.headers
                if incomingProtocol != upstreamProtocol {
                    do {
                        guard let json = try JSONSerialization.jsonObject(with: swappedBody) as? [String: Any] else {
                            finalMessage = "Invalid JSON body"
                            StreamingForwarder.writeErrorEvent(finalMessage, requestID: "#\(reqId)", targetProtocol: incomingProtocol, to: writer)
                            self.routerCompleteRequest(requestID: reqIdString)
                            return
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
                        finalMessage = "Protocol conversion failed"
                        Log.error("[#\(reqId)] \(finalMessage): \(error.localizedDescription)")
                        StreamingForwarder.writeErrorEvent(finalMessage, requestID: "#\(reqId)", targetProtocol: incomingProtocol, to: writer)
                        self.routerCompleteRequest(requestID: reqIdString)
                        return
                    }
                } else {
                    forwardedBody = swappedBody
                }
                convertedHeaders.removeValue(forKey: "host")

                let forwarder = StreamingForwarder(
                    url: upstreamURL,
                    headers: convertedHeaders,
                    body: forwardedBody,
                    timeout: self.streamingTimeout,
                    firstByteTimeout: self.streamingFirstByteTimeout,
                    streamTimeout: self.streamingTimeout,
                    requestDeadline: requestDeadline,
                    keepaliveInterval: self.streamingKeepaliveInterval,
                    apiKeys: apiKeys,
                    incomingProtocol: incomingProtocol,
                    upstreamProtocol: upstreamProtocol,
                    channelName: channel.name,
                    channelID: channel.id,
                    apiKeyAvailabilityStore: self.services.apiKeyAvailabilityStore,
                    requestID: "#\(reqId)",
                    model: model
                )
                let protocolName = upstreamProtocol == .anthropic ? "anthropic" : "openai"
                let remainingBudget = String(format: "%.1f", max(0, requestDeadline.timeIntervalSinceNow))
                Log.info(
                    "[#\(reqId)] Streaming to \(channel.name): \(upstreamURL.absoluteString) "
                        + "proto=\(protocolName) model=\(model) "
                        + "firstByteTimeout=\(self.streamingFirstByteTimeout)s "
                        + "streamTimeout=\(self.streamingTimeout)s budget=\(remainingBudget)s"
                )
                let completion = forwarder.stream(to: writer, writesErrorOnFailure: false)
                let latency = Date().timeIntervalSince(startTime)
                let headerText = completion.responseHeaderLatency.map { String(format: "%.3fs", $0) } ?? "none"
                let ttftText = completion.timeToFirstByte.map { String(format: "%.3fs", $0) } ?? "none"

                if completion.isSuccess {
                    self.routerRecordSuccess(channelID: channel.id)
                    Log.info(
                        "[#\(reqId)] Streaming success from \(channel.name) headers=\(headerText) "
                            + "ttft=\(ttftText) total=\(String(format: "%.1f", latency))s "
                            + "keepalive=\(completion.didWriteKeepalive) "
                            + "terminal=\(completion.hasTerminalEvent) "
                            + "synthesizedTerminal=\(completion.didSynthesizeTerminalEvent)"
                    )
                } else if completion.clientDisconnected {
                    Log.warn(
                        "[#\(reqId)] Streaming client disconnected from \(channel.name) "
                            + "headers=\(headerText) ttft=\(ttftText) "
                            + "total=\(String(format: "%.1f", latency))s "
                            + "error=\(completion.error?.localizedDescription ?? "nil")"
                    )
                } else if completion.didWriteBody {
                    Log.warn("[#\(reqId)] Stream ended prematurely from \(channel.name): HTTP \(completion.statusCode) didWriteBody=true error=\(completion.error?.localizedDescription ?? "nil") latency=\(String(format: "%.1f", latency))s")
                } else {
                    let bodyText = String(data: completion.body, encoding: .utf8)?.prefix(500) ?? ""
                    Log.error("[#\(reqId)] Streaming failed from \(channel.name): HTTP \(completion.statusCode) error=\(completion.error?.localizedDescription ?? "nil") latency=\(String(format: "%.1f", latency))s body=\(bodyText)")
                }

                let usage = (input: completion.inputTokens, output: completion.outputTokens)
                self.services.usageTracker.recordUsage(
                    channelID: channel.id,
                    channelName: channel.name,
                    model: model,
                    inputTokens: usage.input,
                    outputTokens: usage.output,
                    estimatedCost: self.estimateCost(channel: channel, inputTokens: usage.input, outputTokens: usage.output),
                    latency: latency * 1000,
                    statusCode: completion.statusCode,
                    isError: !completion.isSuccess
                )

                if completion.isSuccess || completion.didWriteBody {
                    if !completion.isSuccess,
                       completion.didWriteBody,
                       !completion.clientDisconnected {
                        let message = StreamingForwarder.errorMessage(from: completion)
                        StreamingForwarder.writeErrorEvent(
                            message,
                            requestID: "#\(reqId)",
                            targetProtocol: incomingProtocol,
                            to: writer
                        )
                    }
                    self.routerCompleteRequest(requestID: reqIdString)
                    return
                }

                if completion.clientDisconnected {
                    self.routerCompleteRequest(requestID: reqIdString)
                    return
                }

                finalMessage = StreamingForwarder.errorMessage(from: completion)
                // Detect timeout: use 408 status so SmartRouter can retry
                // the same channel before tripping the circuit breaker
                let retryStatusCode: Int
                if completion.isTimeout {
                    retryStatusCode = 408
                } else if completion.statusCode >= 200 && completion.statusCode < 300 {
                    retryStatusCode = 502
                } else {
                    retryStatusCode = completion.statusCode
                }
                // If the pre-body budget is exhausted, retrying is pointless - a new forwarder
                // would immediately re-fail on the same deadline and spin through maxRetries
                // without any network I/O. Stop here and surface the error to the client.
                let budgetExhausted = requestDeadline.timeIntervalSinceNow <= 0
                if !budgetExhausted,
                   let retryDecision = self.routerHandleError(
                    requestID: reqIdString,
                    statusCode: retryStatusCode,
                    modelName: self.extractModelName(from: bodyData),
                    errorBody: completion.body,
                    requestProtocol: targetProtocol
                ) {
                    let budget = String(format: "%.1f", max(0, requestDeadline.timeIntervalSinceNow))
                    Log.info(
                        "[#\(reqId)] Retrying streaming request with channel "
                            + "\(retryDecision.channel.name); remaining pre-body budget=\(budget)s"
                    )
                    currentDecision = retryDecision
                    continue
                }

                if completion.statusCode < 200 || completion.statusCode >= 300,
                   !completion.body.isEmpty {
                    StreamingForwarder.writeUpstreamErrorEvent(
                        completion.body,
                        requestID: "#\(reqId)",
                        targetProtocol: incomingProtocol,
                        to: writer
                    )
                } else {
                    StreamingForwarder.writeErrorEvent(
                        finalMessage,
                        requestID: "#\(reqId)",
                        targetProtocol: incomingProtocol,
                        to: writer
                    )
                }
                self.routerCompleteRequest(requestID: reqIdString)
                return
            }

            StreamingForwarder.writeErrorEvent(finalMessage, requestID: "#\(reqId)", targetProtocol: incomingProtocol, to: writer)
            self.routerCompleteRequest(requestID: "req-\(reqId)")
        }
    }

    private func convertResponseBodyIfNeeded(
        data: Data,
        isStream: Bool,
        incomingProtocol: RequestForwarder.RequestProtocol,
        upstreamProtocol: RequestForwarder.RequestProtocol,
        model: String,
        requestID: String
    ) -> Data {
        if isStream {
            switch (incomingProtocol, upstreamProtocol) {
            case (.anthropic, .openai):
                return ProtocolConverter.openAItoAnthropicStreamingResponse(data: data, model: model)
            default:
                return data
            }
        }

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
            return try JSONSerialization.data(withJSONObject: converted)
        } catch {
            Log.error("[\(requestID)] Response conversion failed")
            return data
        }
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

    private func errorResponse(_ statusCode: Int, _ message: String) -> HttpResponse {
        ProxyEndpointSupport.errorResponse(statusCode, message)
    }

    private func rawResponse(statusCode: Int, headers: [String: String], body: Data) -> HttpResponse {
        ProxyEndpointSupport.rawResponse(statusCode: statusCode, headers: headers, body: body)
    }

    private func rawResponse(statusCode: Int, headers: [String: String], json: [String: Any]) -> HttpResponse {
        ProxyEndpointSupport.rawResponse(statusCode: statusCode, headers: headers, json: json)
    }

    private func estimateCost(channel: Channel, inputTokens: Int, outputTokens: Int) -> Double {
        ProxyEndpointSupport.estimateCost(channel: channel, inputTokens: inputTokens, outputTokens: outputTokens)
    }
}
