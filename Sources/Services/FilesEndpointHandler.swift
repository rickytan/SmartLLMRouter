import Foundation
import Swifter

@MainActor
final class FilesEndpointHandler {
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

    /// Handles all Files API requests (list, upload, retrieve, delete, download).
    /// Uses the first available channel — no model matching needed.
    func handle(
        _ request: HttpRequest,
        method: String,
        isContent: Bool = false
    ) -> HttpResponse {
        let reqId = requestIDGenerator.next()
        let startTime = Date()
        let reqIdString = "req-\(reqId)"

        Log.info("[#\(reqId)] \(request.method) \(request.path) (files)")

        // Use first available OpenAI channel (Files API is OpenAI-only)
        guard let channel = getFirstOpenAIChannel() else {
            return errorResponse(503, "No available OpenAI channel for Files API")
        }

        let apiKeys = services.channelServices.apiKeys(for: channel.id)
        guard !apiKeys.isEmpty
        else {
            return errorResponse(503, "No API key for channel")
        }

        guard let upstreamURL = buildUpstreamURL(for: request, channel: channel, isContent: isContent) else {
            return errorResponse(500, "Invalid upstream URL")
        }

        let targetProtocol = targetProtocol(for: channel)
        var headers = request.headers
        headers.removeValue(forKey: "host")

        let bodyData: Data
        if method == "POST" && !request.body.isEmpty {
            bodyData = Data(request.body)
            if headers["content-length"] == nil {
                headers["content-length"] = String(bodyData.count)
            }
        } else {
            bodyData = Data()
        }

        let keyForwardResult = forwardingClient.forwardSyncWithAPIKeyFailover(
            url: upstreamURL,
            method: method,
            headers: headers,
            body: bodyData,
            timeout: 300,
            apiKeys: apiKeys,
            targetProtocol: targetProtocol,
            channelName: channel.name,
            requestID: "#\(reqId)",
            channelID: channel.id,
            apiKeyAvailabilityStore: services.apiKeyAvailabilityStore
        )
        let result = keyForwardResult.result

        switch result {
        case let .success(data, statusCode, responseHeaders):
            let latency = Date().timeIntervalSince(startTime)

            if statusCode >= 200 && statusCode < 300 {
                services.runtimeState.recordSuccess(channelID: channel.id)
            }

            let usage = RequestForwarder.parseUsage(from: data, isAnthropic: targetProtocol == .anthropic)
            let cost = ProxyEndpointSupport.estimateCost(channel: channel, inputTokens: usage.input, outputTokens: usage.output)
            services.usageTracker.recordUsage(
                channelID: channel.id, channelName: channel.name,
                model: channel.models.first?.identifier ?? "unknown",
                inputTokens: usage.input, outputTokens: usage.output,
                estimatedCost: cost, latency: latency * 1000,
                statusCode: statusCode, isError: statusCode >= 400
            )

            services.runtimeState.completeRequest(requestID: reqIdString)

            var responseContentType = "application/json"
            if let contentType = responseHeaders["content-type"]?.lowercased() {
                if contentType.contains("octet-stream") || contentType.contains("application/octet") {
                    responseContentType = contentType
                } else {
                    responseContentType = responseHeaders["content-type"] ?? "application/json"
                }
            }
            var finalHeaders: [String: String] = ["content-type": responseContentType]
            finalHeaders["content-length"] = String(data.count)
            for (key, value) in responseHeaders
                where key.lowercased().hasPrefix("x-") || key.lowercased() == "retry-after" || key.lowercased() == "request-id" {
                finalHeaders[key] = value
            }

            return ProxyEndpointSupport.rawResponse(statusCode: statusCode, headers: finalHeaders, body: data)

        case let .failure(error):
            Log.error("[#\(reqId)] Files API forward failed: \(error.localizedDescription)")
            services.runtimeState.completeRequest(requestID: reqIdString)
            return ProxyEndpointSupport.errorResponse(502, "Upstream request failed")
        }
    }

    private func buildUpstreamURL(for request: HttpRequest, channel: Channel, isContent: Bool) -> URL? {
        guard let baseURL = channel.baseURL(for: APIProtocol.openai) else {
            return nil
        }
        var components = URLComponents(string: baseURL)
        if isContent {
            guard let fileId = extractPathParameter(from: request, named: "fileId") else {
                return nil
            }
            components?.path = "/v1/files/\(fileId)/content"
        } else if request.path.hasPrefix("/v1/files/") {
            if let fileId = extractPathParameter(from: request, named: "fileId") {
                components?.path = "/v1/files/\(fileId)"
            } else {
                components?.path = "/v1/files"
            }
        } else {
            components?.path = "/v1/files"
        }

        if !request.queryParams.isEmpty {
            components?.queryItems = request.queryParams.map { URLQueryItem(name: $0.0, value: $0.1) }
        }

        return components?.url
    }

    private func getFirstOpenAIChannel() -> Channel? {
        services.runtimeState.enabledChannelsSnapshot().first { channel in
            switch channel.protocol {
            case .openai, .auto:
                true
            case .anthropic:
                false
            }
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

    private func extractPathParameter(from request: HttpRequest, named paramName: String) -> String? {
        request.params[paramName]
    }

    private func errorResponse(_ statusCode: Int, _ message: String) -> HttpResponse {
        ProxyEndpointSupport.errorResponse(statusCode, message)
    }
}
