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
    static func parseUsage(
        from body: Data?,
        isAnthropic: Bool,
        requestBody: Data? = nil
    ) -> (input: Int, output: Int) {
        guard let body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            return (0, 0)
        }

        let usage = json["usage"] as? [String: Any]
        let exactInput = usage.flatMap(totalInputTokens(from:)) ?? 0
        let exactOutput = usage.flatMap(outputTokens(from:)) ?? 0
        guard let requestBody else { return (exactInput, exactOutput) }
        return (
            exactInput > 0 ? exactInput : estimatedInputTokens(from: requestBody),
            exactOutput > 0 ? exactOutput : estimatedOutputTokens(from: json, isAnthropic: isAnthropic)
        )
    }

    /// Anthropic reports uncached, cache-write, and cache-read input separately.
    /// OpenAI-compatible responses use either prompt_tokens or input_tokens.
    static func totalInputTokens(from usage: [String: Any]) -> Int? {
        let uncached = usage["input_tokens"] as? Int ?? usage["prompt_tokens"] as? Int
        let cacheCreation = usage["cache_creation_input_tokens"] as? Int
        let cacheRead = usage["cache_read_input_tokens"] as? Int
        guard uncached != nil || cacheCreation != nil || cacheRead != nil else { return nil }
        return (uncached ?? 0) + (cacheCreation ?? 0) + (cacheRead ?? 0)
    }

    static func outputTokens(from usage: [String: Any]) -> Int? {
        usage["output_tokens"] as? Int ?? usage["completion_tokens"] as? Int
    }

    /// Some OpenAI-compatible providers ignore `stream_options.include_usage`.
    /// Use a conservative fallback only when the upstream supplied no usage.
    static func estimatedInputTokens(from body: Data) -> Int {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return estimatedTokenCount(for: String(data: body, encoding: .utf8) ?? "")
        }

        let payloadKeys = ["system", "messages", "prompt", "input", "tools"]
        let payload = payloadKeys.compactMap { key -> Any? in
            guard let value = json[key] else { return nil }
            return [key: value]
        }
        guard !payload.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else {
            return 0
        }
        return estimatedTokenCount(for: text)
    }

    static func estimatedTokenCount(for text: String) -> Int {
        guard !text.isEmpty else { return 0 }

        var asciiCount = 0
        var nonASCIICharacters = 0
        for scalar in text.unicodeScalars {
            if scalar.isASCII {
                asciiCount += 1
            } else if !CharacterSet.nonBaseCharacters.contains(scalar) {
                nonASCIICharacters += 1
            }
        }
        return max(1, Int(ceil(Double(asciiCount) / 4.0)) + nonASCIICharacters)
    }

    static func outputText(fromStreamingEvent json: [String: Any]) -> String {
        var fragments: [String] = []

        if let choices = json["choices"] as? [[String: Any]] {
            for choice in choices {
                if let delta = choice["delta"] as? [String: Any] {
                    appendOutputFragments(from: delta, to: &fragments)
                }
                if let text = choice["text"] as? String {
                    fragments.append(text)
                }
            }
        }

        if let delta = json["delta"] as? [String: Any] {
            appendOutputFragments(from: delta, to: &fragments)
        }
        if let contentBlock = json["content_block"] as? [String: Any] {
            appendOutputFragments(from: contentBlock, to: &fragments)
        }

        return fragments.joined()
    }

    private static func estimatedOutputTokens(from json: [String: Any], isAnthropic: Bool) -> Int {
        var fragments: [String] = []
        if isAnthropic, let content = json["content"] as? [[String: Any]] {
            content.forEach { appendOutputFragments(from: $0, to: &fragments) }
        } else if let choices = json["choices"] as? [[String: Any]] {
            for choice in choices {
                if let message = choice["message"] as? [String: Any] {
                    appendOutputFragments(from: message, to: &fragments)
                }
                if let text = choice["text"] as? String {
                    fragments.append(text)
                }
            }
        }
        return estimatedTokenCount(for: fragments.joined())
    }

    private static func appendOutputFragments(from object: [String: Any], to fragments: inout [String]) {
        for key in ["content", "text", "reasoning_content", "partial_json", "arguments"] {
            if let value = object[key] as? String {
                fragments.append(value)
            } else if let values = object[key] as? [[String: Any]] {
                values.forEach { appendOutputFragments(from: $0, to: &fragments) }
            }
        }

        if let toolCalls = object["tool_calls"] as? [[String: Any]] {
            for toolCall in toolCalls {
                if let function = toolCall["function"] as? [String: Any] {
                    appendOutputFragments(from: function, to: &fragments)
                }
            }
        }
        if let input = object["input"],
           let data = try? JSONSerialization.data(withJSONObject: input),
           let text = String(data: data, encoding: .utf8) {
            fragments.append(text)
        }
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

    /// Replace the model field in JSON body with a new model name.
    /// Works for both OpenAI and Anthropic protocol bodies (both use "model" key).
    static func swapModel(in body: Data, newModel: String) -> Data? {
        do {
            guard var json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                Log.warn("swapModel: body is not valid JSON")
                return nil
            }
            json["model"] = newModel
            return try JSONSerialization.data(withJSONObject: json)
        } catch {
            Log.error("swapModel: failed to modify body - \(error.localizedDescription)")
            return nil
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

    // MARK: - Stream Error Buffering

    /// Result of a streaming request that may have errored
    struct StreamForwardResult {
        let statusCode: Int
        let headers: [String: String]
        let body: Data
        let isError: Bool
        /// Parsed error body (only populated when isError = true)
        let errorJSON: [String: Any]?
        let latency: TimeInterval

        init(statusCode: Int, headers: [String: String], body: Data, latency: TimeInterval) {
            self.statusCode = statusCode
            self.headers = headers
            self.body = body
            self.latency = latency
            self.isError = statusCode < 200 || statusCode >= 300
            self.errorJSON = Self.parseErrorJSON(from: body)
        }

        private static func parseErrorJSON(from body: Data) -> [String: Any]? {
            guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                return nil
            }
            return json["error"] != nil ? json : nil
        }
    }

    /// Forward a request with explicit error body buffering for streaming scenarios.
    /// When the upstream returns a non-200 status, this reads the full body to capture
    /// the error JSON (e.g., `{"error": {"message": "...", "type": "..."}}`).
    /// This ensures the downstream client can see WHY the request failed.
    static func forwardWithErrorBuffering(
        url: URL,
        method: HTTPMethod = .post,
        headers: [String: String],
        body: Data?,
        timeout: TimeInterval = 600,
        isStreaming: Bool = false
    ) async throws -> StreamForwardResult {
        let startTime = Date()

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.rawValue
        urlRequest.httpBody = body
        urlRequest.timeoutInterval = timeout

        for (key, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        // Always use data(for:) to capture the FULL response body,
        // even for streaming requests. This is critical for error detection:
        // upstream may return non-200 with a JSON error body that we must forward.
        let (responseData, response) = try await URLSession.shared.data(for: urlRequest)

        let latency = Date().timeIntervalSince(startTime)
        let httpResponse = response as? HTTPURLResponse

        let responseHeaders: [String: String] = (httpResponse?.allHeaderFields ?? [:])
            .reduce(into: [String: String]()) { dict, pair in
                if let key = pair.key as? String, let value = pair.value as? String {
                    dict[key] = value
                }
            }

        let statusCode = httpResponse?.statusCode ?? 200

        // For streaming requests with error status, log the error body for debugging
        if isStreaming && statusCode >= 400 {
            if let bodyStr = String(data: responseData, encoding: .utf8) {
                Log.warn("[StreamBuffer] Upstream returned HTTP \(statusCode) for streaming request. Body: \(bodyStr.prefix(300))")
            }
        }

        return StreamForwardResult(
            statusCode: statusCode,
            headers: responseHeaders,
            body: responseData,
            latency: latency
        )
    }

    // MARK: - Thinking Rectification

    /// Check if the error response indicates a thinking budget issue
    static func containsThinkingBudgetError(_ body: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return false
        }

        if let error = json["error"] as? [String: Any] {
            if let message = error["message"] as? String {
                let lower = message.lowercased()
                if lower.contains("budget_tokens") ||
                    (lower.contains("thinking") && lower.contains("budget")) ||
                    (lower.contains("thinking") && lower.contains("exceed")) ||
                    lower.contains("thinking.enabled") ||
                    lower.contains("thinking budget") {
                    return true
                }
            }
            if let type = error["type"] as? String,
               type.lowercased().contains("thinking") ||
               type.lowercased().contains("budget") {
                return true
            }
        }

        if let type = json["type"] as? String,
           type.lowercased().contains("thinking") ||
           type.lowercased().contains("budget") {
            return true
        }

        return false
    }

    /// Extract max_tokens from request body
    static func extractMaxTokens(from body: Data) -> Int? {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }
        return json["max_tokens"] as? Int
    }

    /// Attempt thinking rectification: adjust budget_tokens to a safe value.
    /// If the error mentions budget_tokens (400 error), this creates a modified
    /// request body with `thinking: { type: "enabled", budget_tokens: max_tokens - 1 }`.
    static func tryThinkingRectification(originalBody: Data, maxTokens: Int?) -> Data? {
        guard var json = try? JSONSerialization.jsonObject(with: originalBody) as? [String: Any] else {
            return nil
        }

        let safeBudget: Int
        if let maxTokens {
            // Set budget_tokens to max_tokens - 1 (leaves room for non-thinking output)
            safeBudget = max(maxTokens - 1, 1024) // Minimum 1024 to be reasonable
        } else {
            // Default safe budget
            safeBudget = 4096
        }

        // Modify thinking.budget_tokens in the request body
        if var thinking = json["thinking"] as? [String: Any] {
            thinking["budget_tokens"] = safeBudget
            json["thinking"] = thinking
            Log.info("[Rectifier] Thinking budget reduced to \(safeBudget)")
        } else if maxTokens != nil {
            // If no thinking block but we have max_tokens, add a thinking block
            json["thinking"] = [
                "type": "enabled",
                "budget_tokens": safeBudget,
            ]
            Log.info("[Rectifier] Added thinking block with budget \(safeBudget)")
        } else {
            return nil // Can't rectify without knowing max_tokens
        }

        return try? JSONSerialization.data(withJSONObject: json)
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
