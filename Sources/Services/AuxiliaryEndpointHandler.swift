import Foundation
import Swifter

@MainActor
final class AuxiliaryEndpointHandler {
    private let services: RouterServices
    private let forwardingClient: HTTPForwardingClient
    private let requestIDGenerator: RequestIDGenerator
    private let upstreamTimeout: TimeInterval

    init(
        services: RouterServices,
        forwardingClient: HTTPForwardingClient,
        requestIDGenerator: RequestIDGenerator,
        upstreamTimeout: TimeInterval
    ) {
        self.services = services
        self.forwardingClient = forwardingClient
        self.requestIDGenerator = requestIDGenerator
        self.upstreamTimeout = upstreamTimeout
    }

    /// Handles POST requests with JSON body that forward to upstream without protocol conversion.
    /// These are single-operation endpoints — no failover chain.
    func handle(_ request: HttpRequest, targetPath: String) -> HttpResponse {
        let reqId = requestIDGenerator.next()
        let startTime = Date()
        let reqIdString = "req-\(reqId)"

        Log.info("[#\(reqId)] \(request.method) \(request.path)")

        guard !request.body.isEmpty else {
            return ProxyEndpointSupport.errorResponse(400, "Empty request body")
        }
        let bodyData = Data(request.body)
        let modelName = extractModelName(from: bodyData)

        guard let state = readRequestState(bodyData: bodyData, reqIdString: reqIdString) else {
            Log.error("[#\(reqId)] No available channels or missing API key for \(targetPath)")
            return ProxyEndpointSupport.errorResponse(503, "No available channel")
        }

        let channel = state.channel
        let targetProtocol = targetProtocol(for: channel)
        let override = services.modelOverrideState.snapshot()
        let effectiveBody = applyModelOverride(
            body: bodyData,
            hasOverride: override.hasOverride,
            selectedModelID: override.selectedModelID
        )

        var components = URLComponents(string: channel.baseURL)
        components?.path = targetPath
        guard let upstreamURL = components?.url else {
            return ProxyEndpointSupport.errorResponse(500, "Invalid upstream URL")
        }

        var headers = request.headers
        headers["content-type"] = "application/json"
        headers["content-length"] = String(effectiveBody.count)
        ProxyEndpointSupport.setAuthHeaders(&headers, apiKey: state.apiKey, protocol: targetProtocol)
        headers.removeValue(forKey: "host")

        let result = forwardingClient.forwardSync(
            url: upstreamURL,
            headers: headers,
            body: effectiveBody,
            timeout: upstreamTimeout
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

            return buildFinalResponse(
                statusCode: statusCode,
                body: data,
                headers: responseHeaders
            )

        case let .failure(error):
            Log.error("[#\(reqId)] Forward failed: \(error.localizedDescription)")
            services.runtimeState.completeRequest(requestID: reqIdString)
            return ProxyEndpointSupport.errorResponse(502, "Upstream request failed")
        }
    }

    private struct RequestState {
        let channel: Channel
        let apiKey: String
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
        return RequestState(channel: decision.channel, apiKey: apiKey)
    }

    private func targetProtocol(for channel: Channel) -> RequestForwarder.RequestProtocol {
        switch channel.protocol {
        case .anthropic:
            .anthropic
        case .openai, .auto:
            .openai
        }
    }

    private func extractModelName(from body: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }
        return json["model"] as? String
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

    private func buildFinalResponse(
        statusCode: Int,
        body: Data,
        headers: [String: String]
    ) -> HttpResponse {
        var responseHeaders: [String: String] = [:]
        responseHeaders["content-type"] = "application/json"
        responseHeaders["content-length"] = String(body.count)
        for (key, value) in headers where key.lowercased().hasPrefix("x-") || key.lowercased() == "retry-after" {
            responseHeaders[key] = value
        }
        return ProxyEndpointSupport.rawResponse(statusCode: statusCode, headers: responseHeaders, body: body)
    }
}
