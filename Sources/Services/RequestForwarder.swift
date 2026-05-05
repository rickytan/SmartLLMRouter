import Foundation

/// HTTP method
enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
}

/// Handles HTTP request forwarding to upstream providers
enum RequestForwarder {
    struct ForwardResult {
        let statusCode: Int
        let headers: [String: String]
        let body: Data?
        let isStreaming: Bool
        let latency: TimeInterval
    }

    /// Forward a non-streaming request
    static func forward(
        url: URL,
        method: HTTPMethod,
        headers: [String: String],
        body: Data?,
        timeout: TimeInterval = 60
    ) async throws -> ForwardResult {
        let startTime = Date()

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.rawValue
        urlRequest.httpBody = body
        urlRequest.timeoutInterval = timeout

        for (key, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        let latency = Date().timeIntervalSince(startTime)
        let httpResponse = response as? HTTPURLResponse

        let responseHeaders: [String: String] = (httpResponse?.allHeaderFields ?? [:])
            .reduce(into: [String: String]()) { dict, pair in
                if let key = pair.key as? String, let value = pair.value as? String {
                    dict[key] = value
                }
            }

        return ForwardResult(
            statusCode: httpResponse?.statusCode ?? 200,
            headers: responseHeaders,
            body: data,
            isStreaming: false,
            latency: latency
        )
    }

    /// Parse usage from response body
    static func parseUsage(from body: Data?, isAnthropic: Bool) -> (input: Int, output: Int) {
        guard let body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            return (0, 0)
        }

        if isAnthropic {
            if let usage = json["usage"] as? [String: Any] {
                return (
                    usage["input_tokens"] as? Int ?? 0,
                    usage["output_tokens"] as? Int ?? 0
                )
            }
        } else {
            if let usage = json["usage"] as? [String: Any] {
                return (
                    usage["prompt_tokens"] as? Int ?? 0,
                    usage["completion_tokens"] as? Int ?? 0
                )
            }
        }

        return (0, 0)
    }

    /// Detect if request body indicates streaming mode
    static func isStreamingRequest(_ body: Data?) -> Bool {
        guard let body else { return false }
        do {
            guard let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                return false
            }
            return json["stream"] as? Bool == true
        } catch {
            Log.debug("isStreamingRequest: JSON parse error - \(error.localizedDescription)")
            return false
        }
    }

    /// Detect protocol from request
    enum RequestProtocol {
        case anthropic
        case openai
        case unknown
    }

    static func detectProtocol(path: String, body: Data?) -> RequestProtocol {
        // URL path detection first
        if path.hasSuffix("/v1/messages") {
            return .anthropic
        }
        if path.hasSuffix("/v1/chat/completions") {
            return .openai
        }

        // Fallback: inspect body
        guard let body else { return .unknown }
        do {
            guard let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                Log.debug("detectProtocol: body is not valid JSON")
                return .unknown
            }
            if json["system"] != nil || json["messages"] is [[String: Any]] {
                // Anthropic uses "messages" too, but "system" field is distinctive
                if json["system"] != nil {
                    return .anthropic
                }
            }
            // OpenAI typically has "messages" array as the main content
            if let msgs = json["messages"] as? [[String: Any]],
               !msgs.isEmpty,
               json["max_tokens"] == nil || json["max_tokens"] is Int
            {
                return .openai
            }
            return .unknown
        } catch {
            Log.debug("detectProtocol: JSON parse error - \(error.localizedDescription)")
            return .unknown
        }
    }
}

// MARK: - Streaming Support

/// SSE Event for streaming responses
struct SSEEvent {
    let event: String?
    let data: String
    let id: String?
}

/// Parser for Server-Sent Events
struct SSEParser {
    private var buffer = ""

    mutating func parse(_ chunk: Data) -> [SSEEvent] {
        buffer += String(decoding: chunk, as: UTF8.self)

        var events: [SSEEvent] = []
        let parts = buffer.components(separatedBy: "\n\n")

        // Keep last incomplete part in buffer
        buffer = parts.last ?? ""
        let completeParts = parts.dropLast()

        for part in completeParts {
            var event: String?
            var data = ""
            var id: String?

            for line in part.components(separatedBy: "\n") {
                if line.hasPrefix("event:") {
                    event = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("data:") {
                    let dataLine = String(line.dropFirst(5))
                    if dataLine.trimmingCharacters(in: .whitespaces).isEmpty {
                        continue
                    }
                    if data.isEmpty {
                        data = dataLine.trimmingCharacters(in: .whitespaces)
                    } else {
                        data += "\n" + dataLine.trimmingCharacters(in: .whitespaces)
                    }
                } else if line.hasPrefix("id:") {
                    id = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
            }

            if !data.isEmpty {
                events.append(SSEEvent(event: event, data: data, id: id))
            }
        }

        return events
    }
}

/// SSE line encoder
enum SSEEncoder {
    static func encode(event: String? = nil, data: String, id: String? = nil) -> String {
        var result = ""
        if let event {
            result += "event: \(event)\n"
        }
        if let id {
            result += "id: \(id)\n"
        }
        // Split data into lines
        for line in data.components(separatedBy: "\n") {
            result += "data: \(line)\n"
        }
        result += "\n"
        return result
    }
}
