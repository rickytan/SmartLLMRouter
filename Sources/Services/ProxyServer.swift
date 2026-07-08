import Foundation
import Swifter

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

    private let upstreamTimeout: TimeInterval = 120

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
            lastError = nil
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
            // Record failure with CircuitBreaker
            _ = routerHandleError(
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
        responseHeaders["content-type"] = isStream ? "text/event-stream" : "application/json"
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
            "connection": "close",
        ]

        return HttpResponse.raw(200, "OK", responseHeaders) { [self] writer in
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
                    StreamingForwarder.writeErrorEvent(finalMessage, requestID: "#\(reqId)", to: writer)
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
                    StreamingForwarder.writeErrorEvent(finalMessage, requestID: "#\(reqId)", to: writer)
                    self.routerCompleteRequest(requestID: reqIdString)
                    return
                }

                let forwardedBody: Data
                var convertedHeaders = request.headers
                if incomingProtocol != upstreamProtocol {
                    do {
                        guard let json = try JSONSerialization.jsonObject(with: swappedBody) as? [String: Any] else {
                            finalMessage = "Invalid JSON body"
                            StreamingForwarder.writeErrorEvent(finalMessage, requestID: "#\(reqId)", to: writer)
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
                        StreamingForwarder.writeErrorEvent(finalMessage, requestID: "#\(reqId)", to: writer)
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
                    timeout: self.upstreamTimeout,
                    apiKeys: apiKeys,
                    incomingProtocol: incomingProtocol,
                    upstreamProtocol: upstreamProtocol,
                    channelName: channel.name,
                    channelID: channel.id,
                    apiKeyAvailabilityStore: self.services.apiKeyAvailabilityStore,
                    requestID: "#\(reqId)",
                    model: model
                )
                let completion = forwarder.stream(to: writer, writesErrorOnFailure: false)
                let latency = Date().timeIntervalSince(startTime)

                if completion.isSuccess {
                    self.routerRecordSuccess(channelID: channel.id)
                } else {
                    let bodyText = String(data: completion.body, encoding: .utf8)?.prefix(500) ?? ""
                    Log.error("[#\(reqId)] Streaming failed from \(channel.name): HTTP \(completion.statusCode) \(bodyText)")
                }

                let usage = RequestForwarder.parseUsage(from: completion.body, isAnthropic: upstreamProtocol == .anthropic)
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
                    self.routerCompleteRequest(requestID: reqIdString)
                    return
                }

                finalMessage = StreamingForwarder.errorMessage(from: completion)
                if let retryDecision = self.routerHandleError(
                    requestID: reqIdString,
                    statusCode: completion.statusCode,
                    modelName: self.extractModelName(from: bodyData),
                    errorBody: completion.body,
                    requestProtocol: targetProtocol
                ) {
                    Log.info("[#\(reqId)] Retrying streaming request with channel \(retryDecision.channel.name)")
                    currentDecision = retryDecision
                    continue
                }

                StreamingForwarder.writeErrorEvent(finalMessage, requestID: "#\(reqId)", to: writer)
                self.routerCompleteRequest(requestID: reqIdString)
                return
            }

            StreamingForwarder.writeErrorEvent(finalMessage, requestID: "#\(reqId)", to: writer)
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
