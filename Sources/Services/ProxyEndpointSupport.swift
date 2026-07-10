import Foundation
import Swifter

enum ProxyEndpointSupport {
    static func setAuthHeaders(
        _ headers: inout [String: String],
        apiKey: String,
        protocol targetProtocol: RequestForwarder.RequestProtocol
    ) {
        switch targetProtocol {
        case .anthropic:
            headers["x-api-key"] = apiKey
            headers["anthropic-version"] = "2023-06-01"
        case .openai, .unknown:
            headers["authorization"] = "Bearer \(apiKey)"
        }
    }

    static func errorResponse(_ statusCode: Int, _ message: String) -> HttpResponse {
        let body: [String: Any] = [
            "error": ["message": message, "type": "api_error", "code": statusCode]
        ]
        return rawResponse(
            statusCode: statusCode,
            headers: ["content-type": "application/json"],
            json: body
        )
    }

    static func rawResponse(statusCode: Int, headers: [String: String], body: Data) -> HttpResponse {
        let bytes = [UInt8](body)
        return HttpResponse.raw(statusCode, "OK", headers) { writer in
            try writer.write(bytes)
        }
    }

    static func rawResponse(statusCode: Int, headers: [String: String], json: [String: Any]) -> HttpResponse {
        let body = try? JSONSerialization.data(withJSONObject: json)
        return rawResponse(statusCode: statusCode, headers: headers, body: body ?? Data())
    }

    static func shouldRetryWithNextAPIKey(statusCode: Int, body: Data?) -> Bool {
        if [401, 402, 403, 429].contains(statusCode) {
            return true
        }

        guard let bodyText = normalizedBodyText(body) else {
            return false
        }

        return bodyText.contains("invalid api key") ||
            bodyText.contains("invalid_api_key") ||
            bodyText.contains("insufficient_quota") ||
            bodyText.contains("quota") ||
            bodyText.contains("rate limit") ||
            bodyText.contains("rate_limit") ||
            bodyText.contains("billing")
    }

    static func shouldMarkAPIKeyUnavailable(statusCode: Int, body: Data?) -> Bool {
        if [401, 402].contains(statusCode) {
            return true
        }

        if statusCode == 429 || statusCode >= 500 {
            return false
        }

        guard let bodyText = normalizedBodyText(body) else {
            return false
        }

        return bodyText.contains("invalid api key") ||
            bodyText.contains("invalid_api_key") ||
            bodyText.contains("invalid token") ||
            bodyText.contains("insufficient_quota") ||
            bodyText.contains("exceeded your current quota") ||
            bodyText.contains("payment required") ||
            bodyText.contains("billing")
    }

    private static func normalizedBodyText(_ body: Data?) -> String? {
        guard let body,
              let bodyText = String(data: body, encoding: .utf8)?.lowercased()
        else {
            return nil
        }
        return bodyText
    }

    static func estimateCost(channel: Channel, inputTokens: Int, outputTokens: Int) -> Double {
        guard let model = channel.models.first else { return 0.0 }
        let inputCost = model.inputPricePer1M ?? 3.0
        let outputCost = model.outputPricePer1M ?? 15.0
        return (Double(inputTokens) / 1_000_000) * inputCost + (Double(outputTokens) / 1_000_000) * outputCost
    }
}
