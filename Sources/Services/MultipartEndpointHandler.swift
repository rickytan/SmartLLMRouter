import Foundation
import Swifter

@MainActor
final class MultipartEndpointHandler {
    private let services: RouterServices
    private let forwardingClient: HTTPForwardingClient
    private let requestIDGenerator: RequestIDGenerator

    init(
        services: RouterServices,
        forwardingClient: HTTPForwardingClient,
        requestIDGenerator: RequestIDGenerator
    ) {
        self.services = services
        self.forwardingClient = forwardingClient
        self.requestIDGenerator = requestIDGenerator
    }

    /// Handles POST requests with multipart/form-data body.
    /// Raw body bytes are forwarded directly without parsing.
    func handle(_ request: HttpRequest, targetPath: String) -> HttpResponse {
        let reqId = requestIDGenerator.next()
        let startTime = Date()
        let reqIdString = "req-\(reqId)"

        Log.info("[#\(reqId)] \(request.method) \(request.path)")

        guard !request.body.isEmpty else {
            return ProxyEndpointSupport.errorResponse(400, "Empty request body")
        }
        let bodyData = Data(request.body)
        let modelName = extractModelNameFromMultipart(bodyData)

        guard let state = readRequestState(bodyData: bodyData, reqIdString: reqIdString) else {
            guard let fallbackChannel = getFirstAvailableChannel() else {
                Log.error("[#\(reqId)] No available channels for \(targetPath)")
                return ProxyEndpointSupport.errorResponse(503, "No available channel")
            }
            let override = services.modelOverrideState.snapshot()
            let effectiveBody = applyModelOverride(
                body: bodyData,
                hasOverride: override.hasOverride,
                selectedModelID: override.selectedModelID
            )
            return forwardWithChannel(
                request: request,
                bodyData: effectiveBody,
                channel: fallbackChannel,
                targetPath: targetPath,
                reqId: reqId,
                startTime: startTime,
                reqIdString: reqIdString,
                modelName: modelName
            )
        }

        return forwardWithChannel(
            request: request,
            bodyData: bodyData,
            channel: state.channel,
            targetPath: targetPath,
            reqId: reqId,
            startTime: startTime,
            reqIdString: reqIdString,
            modelName: modelName
        )
    }

    private struct RequestState {
        let channel: Channel
    }

    private func readRequestState(bodyData: Data, reqIdString: String) -> RequestState? {
        let modelName = extractModelName(from: bodyData)
        let override = services.modelOverrideState.snapshot()
        let routingModelName = override.selectedModelID ?? modelName
        guard let decision = services.runtimeState.selectChannel(
            requestID: reqIdString,
            modelName: routingModelName
        ) else {
            return nil
        }
        guard let apiKey = services.channelServices.apiKey(for: decision.channel.id),
              !apiKey.isEmpty
        else {
            return nil
        }
        return RequestState(channel: decision.channel)
    }

    private func forwardWithChannel(
        request: HttpRequest,
        bodyData: Data,
        channel: Channel,
        targetPath: String,
        reqId: Int64,
        startTime: Date,
        reqIdString: String,
        modelName: String?
    ) -> HttpResponse {
        guard let apiKey = services.channelServices.apiKey(for: channel.id),
              !apiKey.isEmpty
        else {
            services.runtimeState.completeRequest(requestID: reqIdString)
            return ProxyEndpointSupport.errorResponse(503, "No API key for channel")
        }

        let targetProtocol = targetProtocol(for: channel)
        var components = URLComponents(string: channel.baseURL)
        components?.path = targetPath
        guard let upstreamURL = components?.url else {
            services.runtimeState.completeRequest(requestID: reqIdString)
            return ProxyEndpointSupport.errorResponse(500, "Invalid upstream URL")
        }

        var headers = request.headers
        ProxyEndpointSupport.setAuthHeaders(&headers, apiKey: apiKey, protocol: targetProtocol)
        headers.removeValue(forKey: "host")
        if headers["content-type"] == nil {
            headers["content-type"] = "multipart/form-data"
        }

        let result = forwardingClient.forwardSync(
            url: upstreamURL,
            headers: headers,
            body: bodyData,
            timeout: 300
        )

        switch result {
        case let .success(data, statusCode, responseHeaders):
            let latency = Date().timeIntervalSince(startTime)

            if statusCode >= 200 && statusCode < 300 {
                services.runtimeState.recordSuccess(channelID: channel.id)
            }

            let usage = RequestForwarder.parseUsage(from: data, isAnthropic: targetProtocol == .anthropic)
            let cost = ProxyEndpointSupport.estimateCost(
                channel: channel,
                inputTokens: usage.input,
                outputTokens: usage.output
            )
            services.usageTracker.recordUsage(
                channelID: channel.id, channelName: channel.name,
                model: modelName ?? channel.models.first?.identifier ?? "unknown",
                inputTokens: usage.input, outputTokens: usage.output,
                estimatedCost: cost, latency: latency * 1000,
                statusCode: statusCode, isError: statusCode >= 400
            )

            services.runtimeState.completeRequest(requestID: reqIdString)

            var responseContentType = "application/json"
            if let contentType = responseHeaders["content-type"]?.lowercased(),
               contentType.contains("audio") || contentType.contains("image") || contentType.contains("octet-stream") {
                responseContentType = contentType
            }
            var finalHeaders: [String: String] = ["content-type": responseContentType]
            finalHeaders["content-length"] = String(data.count)
            for (key, value) in responseHeaders
                where key.lowercased().hasPrefix("x-") || key.lowercased() == "retry-after" || key.lowercased() == "request-id" {
                finalHeaders[key] = value
            }

            return ProxyEndpointSupport.rawResponse(statusCode: statusCode, headers: finalHeaders, body: data)

        case let .failure(error):
            Log.error("[#\(reqId)] Multipart forward failed: \(error.localizedDescription)")
            services.runtimeState.completeRequest(requestID: reqIdString)
            return ProxyEndpointSupport.errorResponse(502, "Upstream request failed")
        }
    }

    private func targetProtocol(for channel: Channel) -> RequestForwarder.RequestProtocol {
        switch channel.protocol {
        case .anthropic:
            .anthropic
        case .openai, .auto:
            .openai
        }
    }

    private func getFirstAvailableChannel() -> Channel? {
        services.runtimeState.enabledChannelsSnapshot().first
    }

    private func extractModelName(from body: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }
        return json["model"] as? String
    }

    private func extractModelNameFromMultipart(_ data: Data) -> String? {
        guard let bodyStr = String(data: data, encoding: .utf8) else { return nil }
        let patterns = ["name=\"model\"\r\n\r\n", "name=\"model\"\n\n"]
        for pattern in patterns {
            if let range = bodyStr.range(of: pattern) {
                let afterModel = bodyStr[range.upperBound...]
                let endPattern = "\r\n--"
                if let endRange = afterModel.range(of: endPattern) {
                    return String(afterModel[..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return String(afterModel).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private func applyModelOverride(body: Data, hasOverride: Bool, selectedModelID: String?) -> Data {
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
}
