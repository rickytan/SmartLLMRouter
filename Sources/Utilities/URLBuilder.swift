import Foundation

/// Shared URL building logic for upstream API requests.
///
/// Rules:
/// - If baseURL has no path (or just `/`), prepends `/v1`.
/// - If baseURL path ends with a version (`/v1`, `/v3`, etc.), strips `/v1` from endpoint.
/// - If baseURL path has content but no version, keeps full `/v1` endpoint.
enum URLBuilder {

    /// Build the upstream URL for chat/messages endpoint.
    static func buildUpstreamURL(baseURL: String, protocol: RequestForwarder.RequestProtocol) -> URL? {
        let endpoint = `protocol` == .anthropic ? "/v1/messages" : "/v1/chat/completions"
        return buildURL(baseURL: baseURL, endpoint: endpoint)
    }

    /// Build the models listing URL.
    static func buildModelsURL(baseURL: String) -> URL? {
        return buildURL(baseURL: baseURL, endpoint: "/v1/models")
    }

    /// Build the chat completions URL for connection testing.
    static func buildChatCompletionsURL(baseURL: String, isAnthropic: Bool) -> URL? {
        guard !baseURL.isEmpty else { return nil }
        let suffix = isAnthropic ? "/messages" : "/chat/completions"
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if baseURL.range(of: #"/v\d+/?$"#, options: .regularExpression) != nil {
            return URL(string: trimmed + suffix)
        } else {
            return URL(string: trimmed + "/v1" + suffix)
        }
    }

    // MARK: - Private

    private static func buildURL(baseURL: String, endpoint: String) -> URL? {
        guard !baseURL.isEmpty else { return nil }
        var components = URLComponents(string: baseURL)
        var basePath = components?.path ?? ""
        // Strip trailing slash for consistent matching
        if basePath.hasSuffix("/") && basePath.count > 1 {
            basePath = String(basePath.dropLast())
            components?.path = basePath
        }
        let endpointSuffix = String(endpoint.dropFirst(3))
        if basePath == endpoint || basePath.hasSuffix(endpointSuffix) {
            components?.path = basePath
        } else if basePath.isEmpty || basePath == "/" {
            components?.path = endpoint
        } else if basePath.range(of: #"/v\d+$"#, options: .regularExpression) != nil {
            components?.path = basePath + String(endpoint.dropFirst(3))
        } else {
            components?.path = basePath + endpoint
        }
        return components?.url
    }
}
