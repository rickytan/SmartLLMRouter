import Foundation

/// Converts between Anthropic and OpenAI API formats
enum ProtocolConverter {
    // MARK: - Request Conversion

    /// Convert Anthropic /v1/messages request to OpenAI /v1/chat/completions format
    static func anthropicToOpenAI(body: [String: Any]) throws -> [String: Any] {
        var openaiRequest: [String: Any] = [:]

        // Model
        if let model = body["model"] as? String {
            openaiRequest["model"] = model
        }

        // Max tokens
        if let maxTokens = body["max_tokens"] as? Int {
            openaiRequest["max_tokens"] = maxTokens
        }

        // Temperature
        if let temp = body["temperature"] as? Double {
            openaiRequest["temperature"] = temp
        }

        // Top P
        if let topP = body["top_p"] as? Double {
            openaiRequest["top_p"] = topP
        }

        // Stop sequences
        if let stop = body["stop_sequences"] as? [String] {
            openaiRequest["stop"] = stop
        } else if let stop = body["stop"] as? [String] {
            openaiRequest["stop"] = stop
        }

        // Stream
        if let stream = body["stream"] as? Bool {
            openaiRequest["stream"] = stream
            if stream {
                openaiRequest["stream_options"] = ["include_usage": true]
            }
        }

        // Build messages array
        var messages: [[String: Any]] = []

        // System prompt → system message
        if let system = body["system"] as? String {
            messages.append([
                "role": "system",
                "content": system,
            ])
        } else if let systemArray = body["system"] as? [[String: Any]] {
            // Anthropic multimodal system prompt
            let textContent = systemArray.compactMap { block -> String? in
                if block["type"] as? String == "text", let text = block["text"] as? String {
                    return text
                }
                return nil
            }.joined(separator: "\n")
            if !textContent.isEmpty {
                messages.append([
                    "role": "system",
                    "content": textContent,
                ])
            }
        }

        // Convert messages
        if let anthropicMessages = body["messages"] as? [[String: Any]] {
            for msg in anthropicMessages {
                guard let role = msg["role"] as? String else { continue }

                let openaiRole = switch role {
                case "user": "user"
                case "assistant": "assistant"
                case "tool": "tool"
                default: "user"
                }

                // Handle content (string or array)
                if let contentStr = msg["content"] as? String {
                    messages.append([
                        "role": openaiRole,
                        "content": contentStr,
                    ])
                } else if let contentArray = msg["content"] as? [[String: Any]] {
                    // Check if this is an assistant message with tool_use blocks
                    if openaiRole == "assistant" {
                        var textContent = ""
                        var toolCalls: [[String: Any]] = []

                        for block in contentArray {
                            switch block["type"] as? String {
                            case "text":
                                if let text = block["text"] as? String {
                                    textContent += text
                                }
                            case "tool_use":
                                if let id = block["id"] as? String,
                                   let name = block["name"] as? String,
                                   let input = block["input"]
                                {
                                    let inputStr: String
                                    if let dict = input as? [String: Any] {
                                        do {
                                            let jsonData = try JSONSerialization.data(withJSONObject: dict)
                                            inputStr = String(data: jsonData, encoding: .utf8) ?? "{}"
                                        } catch {
                                            Log.error("Failed to serialize tool input: \(error.localizedDescription)")
                                            inputStr = "{}"
                                        }
                                    } else if let str = input as? String {
                                        inputStr = str
                                    } else {
                                        inputStr = "{}"
                                    }
                                    toolCalls.append([
                                        "id": id,
                                        "type": "function",
                                        "function": ["name": name, "arguments": inputStr],
                                    ])
                                }
                            default:
                                break
                            }
                        }

                        var openaiMsg: [String: Any] = ["role": "assistant"]
                        openaiMsg["content"] = textContent.isEmpty ? NSNull() : textContent
                        if !toolCalls.isEmpty {
                            openaiMsg["tool_calls"] = toolCalls
                        }
                        messages.append(openaiMsg)
                    } else if openaiRole == "user" {
                        // Check for tool_result blocks - they become separate tool messages
                        var textParts: [String] = []
                        var toolResults: [(id: String, content: String)] = []

                        for block in contentArray {
                            switch block["type"] as? String {
                            case "text":
                                if let text = block["text"] as? String {
                                    textParts.append(text)
                                }
                            case "image":
                                textParts.append("[Image]")
                            case "tool_result":
                                if let toolUseId = block["tool_use_id"] as? String,
                                   let content = block["content"] as? String
                                {
                                    toolResults.append((id: toolUseId, content: content))
                                }
                            default:
                                break
                            }
                        }

                        // Add user message with text content if present
                        if !textParts.isEmpty {
                            messages.append([
                                "role": "user",
                                "content": textParts.joined(separator: "\n"),
                            ])
                        }

                        // Add separate tool messages for each tool_result
                        for result in toolResults {
                            messages.append([
                                "role": "tool",
                                "content": result.content,
                                "tool_call_id": result.id,
                            ])
                        }
                    }
                }
            }
        }

        openaiRequest["messages"] = messages

        // Tools conversion
        if let tools = body["tools"] as? [[String: Any]] {
            let openaiTools = tools.map { tool -> [String: Any] in
                var openaiTool: [String: Any] = [
                    "type": "function",
                    "function": [
                        "name": tool["name"] ?? "",
                        "description": tool["description"] ?? "",
                        "parameters": tool["input_schema"] ?? [:],
                    ],
                ]
                return openaiTool
            }
            openaiRequest["tools"] = openaiTools
        }

        // Tool choice - can be dict or string
        if let toolChoiceDict = body["tool_choice"] as? [String: Any] {
            let type = toolChoiceDict["type"] as? String
            if type == "auto" || type == "any" {
                openaiRequest["tool_choice"] = type
            } else if type == "tool", let name = toolChoiceDict["name"] as? String {
                openaiRequest["tool_choice"] = ["type": "function", "function": ["name": name]]
            }
        } else if let toolChoiceStr = body["tool_choice"] as? String {
            if toolChoiceStr == "auto" || toolChoiceStr == "any" {
                openaiRequest["tool_choice"] = toolChoiceStr
            }
        }

        return openaiRequest
    }

    /// OpenAI streaming responses omit usage unless the client explicitly requests it.
    /// Preserve existing stream options while ensuring token usage is included.
    static func requestingOpenAIStreamUsage(in body: Data) -> Data {
        guard var json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              json["stream"] as? Bool == true else {
            return body
        }

        var streamOptions = json["stream_options"] as? [String: Any] ?? [:]
        streamOptions["include_usage"] = true
        json["stream_options"] = streamOptions
        return (try? JSONSerialization.data(withJSONObject: json)) ?? body
    }

    /// Convert OpenAI /v1/chat/completions request to Anthropic /v1/messages format
    static func openAItoAnthropic(body: [String: Any]) throws -> [String: Any] {
        var anthropicRequest: [String: Any] = [:]

        // Model
        if let model = body["model"] as? String {
            anthropicRequest["model"] = model
        }

        // Max tokens
        if let maxTokens = body["max_tokens"] as? Int {
            anthropicRequest["max_tokens"] = maxTokens
        } else if let maxTokens = body["max_completion_tokens"] as? Int {
            anthropicRequest["max_tokens"] = maxTokens
        }

        // Temperature
        if let temp = body["temperature"] as? Double {
            anthropicRequest["temperature"] = temp
        }

        // Top P
        if let topP = body["top_p"] as? Double {
            anthropicRequest["top_p"] = topP
        }

        // Stop sequences
        if let stop = body["stop"] as? [String] {
            anthropicRequest["stop_sequences"] = stop
        } else if let stop = body["stop"] as? String {
            anthropicRequest["stop_sequences"] = [stop]
        }

        // Stream
        if let stream = body["stream"] as? Bool {
            anthropicRequest["stream"] = stream
        }

        // Extract system message and build messages
        var messages: [[String: Any]] = []
        var systemPrompt: String?

        if let msgs = body["messages"] as? [[String: Any]] {
            for msg in msgs {
                guard let role = msg["role"] as? String else { continue }

                switch role {
                case "system":
                    // Collect system messages
                    if let content = msg["content"] as? String {
                        if systemPrompt == nil {
                            systemPrompt = content
                        } else {
                            systemPrompt! += "\n" + content
                        }
                    }

                case "user", "assistant":
                    let anthropicRole = role // same in Anthropic
                    var anthropicMsg: [String: Any] = ["role": anthropicRole]

                    if let content = msg["content"] {
                        anthropicMsg["content"] = content
                    }

                    // Handle tool calls in assistant message
                    if let toolCalls = msg["tool_calls"] as? [[String: Any]] {
                        var contentArray: [[String: Any]] = []
                        if let textContent = msg["content"] as? String, !textContent.isEmpty {
                            contentArray.append(["type": "text", "text": textContent])
                        }

                        for toolCall in toolCalls {
                            if let function = toolCall["function"] as? [String: Any],
                               let name = function["name"] as? String,
                               let args = function["arguments"] as? String,
                               let id = toolCall["id"] as? String
                            {
                                contentArray.append([
                                    "type": "tool_use",
                                    "id": id,
                                    "name": name,
                                    "input": args,
                                ])
                            }
                        }
                        anthropicMsg["content"] = contentArray
                    }

                    messages.append(anthropicMsg)

                case "tool":
                    // Convert tool result to Anthropic format
                    var toolResultMsg: [String: Any] = ["role": "user"]
                    var contentArray: [[String: Any]] = []
                    var contentText: String?

                    if let content = msg["content"] as? String {
                        contentText = content
                        contentArray.append(["type": "text", "text": content])
                    }

                    if let toolCallId = msg["tool_call_id"] as? String {
                        contentArray.append([
                            "type": "tool_result",
                            "tool_use_id": toolCallId,
                            "content": contentText ?? "",
                        ])
                    }

                    toolResultMsg["content"] = contentArray
                    messages.append(toolResultMsg)

                default:
                    break
                }
            }
        }

        anthropicRequest["messages"] = messages

        // Set system prompt
        if let system = systemPrompt {
            anthropicRequest["system"] = system
        }

        // Convert tools
        if let tools = body["tools"] as? [[String: Any]] {
            let anthropicTools = tools.compactMap { tool -> [String: Any]? in
                guard let function = tool["function"] as? [String: Any] else { return nil }
                return [
                    "name": function["name"] ?? "",
                    "description": function["description"] ?? "",
                    "input_schema": function["parameters"] ?? [:],
                ]
            }
            if !anthropicTools.isEmpty {
                anthropicRequest["tools"] = anthropicTools
            }
        }

        // Tool choice - can be dict or string
        if let toolChoiceDict = body["tool_choice"] as? [String: Any] {
            if let type = toolChoiceDict["type"] as? String {
                switch type {
                case "auto":
                    anthropicRequest["tool_choice"] = ["type": "auto"]
                case "required":
                    anthropicRequest["tool_choice"] = ["type": "any"]
                case "function":
                    if let function = toolChoiceDict["function"] as? [String: Any],
                       let name = function["name"] as? String
                    {
                        anthropicRequest["tool_choice"] = ["type": "tool", "name": name]
                    }
                default:
                    break
                }
            }
        } else if let toolChoiceStr = body["tool_choice"] as? String {
            switch toolChoiceStr {
            case "auto":
                anthropicRequest["tool_choice"] = ["type": "auto"]
            case "required":
                anthropicRequest["tool_choice"] = ["type": "any"]
            case "none":
                // "none" is not supported in Anthropic - skip
                break
            default:
                break
            }
        }

        return anthropicRequest
    }

    // MARK: - Response Conversion

    /// Convert OpenAI response to Anthropic response format
    static func openAItoAnthropicResponse(body: [String: Any]) -> [String: Any] {
        var response: [String: Any] = [
            "id": body["id"] ?? UUID().uuidString,
            "type": "message",
            "role": "assistant",
            "content": [],
            "model": body["model"] ?? "",
            "stop_reason": "end_turn",
            "stop_sequence": NSNull(),
            "usage": [
                "input_tokens": 0,
                "output_tokens": 0,
            ],
        ]

        // Extract content from choices
        if let choices = body["choices"] as? [[String: Any]],
           let firstChoice = choices.first
        {
            if let message = firstChoice["message"] as? [String: Any] {
                var contentBlocks: [[String: Any]] = []

                if let content = message["content"] as? String {
                    contentBlocks.append(["type": "text", "text": content])
                }

                if let toolCalls = message["tool_calls"] as? [[String: Any]] {
                    for toolCall in toolCalls {
                        if let function = toolCall["function"] as? [String: Any],
                           let name = function["name"] as? String,
                           let id = toolCall["id"] as? String,
                           let args = function["arguments"] as? String
                        {
                            contentBlocks.append([
                                "type": "tool_use",
                                "id": id,
                                "name": name,
                                "input": args,
                            ])
                        }
                    }
                }

                response["content"] = contentBlocks

                // Stop reason
                if let finishReason = firstChoice["finish_reason"] as? String {
                    switch finishReason {
                    case "stop": response["stop_reason"] = "end_turn"
                    case "length": response["stop_reason"] = "max_tokens"
                    case "tool_calls": response["stop_reason"] = "tool_use"
                    case "content_filter": response["stop_reason"] = "stop_sequence"
                    default: response["stop_reason"] = "end_turn"
                    }
                }
            }
        }

        // Usage
        if let usage = body["usage"] as? [String: Any] {
            var anthropicUsage: [String: Any] = [:]
            if let promptTokens = usage["prompt_tokens"] as? Int {
                anthropicUsage["input_tokens"] = promptTokens
            }
            if let completionTokens = usage["completion_tokens"] as? Int {
                anthropicUsage["output_tokens"] = completionTokens
            }
            response["usage"] = anthropicUsage
        }

        return response
    }

    /// Convert Anthropic response to OpenAI response format
    static func anthropicToOpenAIResponse(body: [String: Any]) -> [String: Any] {
        var response: [String: Any] = [
            "id": body["id"] ?? UUID().uuidString,
            "object": "chat.completion",
            "created": Int(Date().timeIntervalSince1970),
            "model": body["model"] ?? "",
            "choices": [],
            "usage": [
                "prompt_tokens": 0,
                "completion_tokens": 0,
                "total_tokens": 0,
            ],
        ]

        // Build choice
        var message: [String: Any] = ["role": "assistant", "content": ""]
        var toolCalls: [[String: Any]] = []

        if let content = body["content"] as? [[String: Any]] {
            var textContent = ""
            for block in content {
                switch block["type"] as? String {
                case "text":
                    if let text = block["text"] as? String {
                        textContent += text
                    }
                case "tool_use":
                    if let id = block["id"] as? String,
                       let name = block["name"] as? String,
                       let input = block["input"]
                    {
                        let inputStr: String
                        if let dict = input as? [String: Any] {
                            do {
                                let jsonData = try JSONSerialization.data(withJSONObject: dict)
                                inputStr = String(data: jsonData, encoding: .utf8) ?? "{}"
                            } catch {
                                Log.error("Failed to serialize tool_use input in response: \(error.localizedDescription)")
                                inputStr = "{}"
                            }
                        } else if let str = input as? String {
                            inputStr = str
                        } else {
                            inputStr = "{}"
                        }
                        toolCalls.append([
                            "id": id,
                            "type": "function",
                            "function": ["name": name, "arguments": inputStr],
                        ])
                    }
                default:
                    break
                }
            }
            message["content"] = textContent.isEmpty ? NSNull() : textContent
        } else if let content = body["content"] as? String {
            message["content"] = content.isEmpty ? NSNull() : content
        }

        if !toolCalls.isEmpty {
            message["tool_calls"] = toolCalls
        }

        // Finish reason
        var finishReason = "stop"
        if let stopReason = body["stop_reason"] as? String {
            switch stopReason {
            case "end_turn": finishReason = "stop"
            case "max_tokens": finishReason = "length"
            case "tool_use": finishReason = "tool_calls"
            case "stop_sequence": finishReason = "content_filter"
            default: finishReason = "stop"
            }
        }

        let choice: [String: Any] = [
            "index": 0,
            "message": message,
            "finish_reason": finishReason,
        ]
        response["choices"] = [choice]

        // Usage
        if let usage = body["usage"] as? [String: Any] {
            var openaiUsage: [String: Any] = [:]
            let inputTokens = RequestForwarder.totalInputTokens(from: usage) ?? 0
            let outputTokens = RequestForwarder.outputTokens(from: usage) ?? 0
            openaiUsage["prompt_tokens"] = inputTokens
            openaiUsage["completion_tokens"] = outputTokens
            openaiUsage["total_tokens"] = inputTokens + outputTokens
            response["usage"] = openaiUsage
        }

        return response
    }

    // MARK: - Streaming Response Conversion

    /// Convert a buffered OpenAI-compatible SSE response into Anthropic SSE events.
    /// This preserves the existing forwarding path while ensuring Anthropic clients
    /// such as Claude Code receive the event grammar they expect.
    static func openAItoAnthropicStreamingResponse(
        data: Data,
        messageID: String = "msg_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))",
        model: String
    ) -> Data {
        var parser = SSEParser()
        var parseData = data
        if let text = String(data: data, encoding: .utf8), !text.hasSuffix("\n\n") {
            parseData.append(Data("\n\n".utf8))
        }

        var converter = OpenAIToAnthropicSSEConverter(messageID: messageID, model: model)
        let events = parser.parse(parseData)
        var output = ""

        for event in events {
            output += converter.convert(event: event)
        }

        output += converter.finishIfNeeded()
        return Data(output.utf8)
    }
}

struct OpenAIToAnthropicSSEConverter {
    private struct ToolState {
        let anthropicIndex: Int
        let id: String
        let name: String
        var started: Bool
        var stopped: Bool
    }

    private let messageID: String
    private let model: String
    private var messageStarted = false
    private var textBlockStarted = false
    private var textBlockStopped = false
    private var nextBlockIndex = 0
    private var toolStates: [Int: ToolState] = [:]
    private var messageStopped = false
    private var inputTokens = 0
    private var outputTokens = 0

    init(messageID: String, model: String) {
        self.messageID = messageID
        self.model = model
    }

    mutating func convert(event: SSEEvent) -> String {
        let trimmed = event.data.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "[DONE]" {
            return finishIfNeeded()
        }

        guard let json = parseJSONObject(trimmed) else {
            return ""
        }

        captureUsage(from: json["usage"] as? [String: Any])

        guard let choices = json["choices"] as? [[String: Any]], let firstChoice = choices.first else {
            return ""
        }

        var output = ensureMessageStarted()

        if let delta = firstChoice["delta"] as? [String: Any] {
            if let content = delta["content"] as? String, !content.isEmpty {
                output += ensureTextBlockStarted()
                output += encodeAnthropicEvent(
                    event: "content_block_delta",
                    object: [
                        "type": "content_block_delta",
                        "index": 0,
                        "delta": [
                            "type": "text_delta",
                            "text": content,
                        ],
                    ]
                )
            }

            if let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
                output += ensureTextBlockStarted()
                output += encodeAnthropicEvent(
                    event: "content_block_delta",
                    object: [
                        "type": "content_block_delta",
                        "index": 0,
                        "delta": [
                            "type": "text_delta",
                            "text": reasoning,
                        ],
                    ]
                )
            }

            if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                output += convertToolCalls(toolCalls)
            }
        }

        if let finishReason = firstChoice["finish_reason"] as? String, !finishReason.isEmpty {
            output += finish(stopReason: anthropicStopReason(for: finishReason))
        }

        return output
    }

    mutating func finishIfNeeded() -> String {
        guard !messageStopped else { return "" }
        return finish(stopReason: "end_turn")
    }

    private mutating func ensureMessageStarted() -> String {
        guard !messageStarted else { return "" }
        messageStarted = true
        return encodeAnthropicEvent(
            event: "message_start",
            object: [
                "type": "message_start",
                "message": [
                    "id": messageID,
                    "type": "message",
                    "role": "assistant",
                    "content": [],
                    "model": model,
                    "stop_reason": NSNull(),
                    "stop_sequence": NSNull(),
                    "usage": [
                        "input_tokens": inputTokens,
                        "output_tokens": outputTokens,
                    ],
                ],
            ]
        )
    }

    private mutating func ensureTextBlockStarted() -> String {
        guard !textBlockStarted else { return "" }
        textBlockStarted = true
        if nextBlockIndex == 0 {
            nextBlockIndex = 1
        }
        return encodeAnthropicEvent(
            event: "content_block_start",
            object: [
                "type": "content_block_start",
                "index": 0,
                "content_block": [
                    "type": "text",
                    "text": "",
                ],
            ]
        )
    }

    private mutating func stopTextBlockIfNeeded() -> String {
        guard textBlockStarted, !textBlockStopped else { return "" }
        textBlockStopped = true
        return encodeAnthropicEvent(
            event: "content_block_stop",
            object: [
                "type": "content_block_stop",
                "index": 0,
            ]
        )
    }

    private mutating func convertToolCalls(_ toolCalls: [[String: Any]]) -> String {
        var output = stopTextBlockIfNeeded()

        for toolCall in toolCalls {
            let openAIIndex = toolCall["index"] as? Int ?? 0
            let function = toolCall["function"] as? [String: Any]
            let id = toolCall["id"] as? String
                ?? toolStates[openAIIndex]?.id
                ?? "toolu_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
            let name = function?["name"] as? String
                ?? toolStates[openAIIndex]?.name
                ?? "tool"

            var state = toolStates[openAIIndex] ?? ToolState(
                anthropicIndex: nextBlockIndex,
                id: id,
                name: name,
                started: false,
                stopped: false
            )

            if !state.started {
                state.started = true
                nextBlockIndex = max(nextBlockIndex, state.anthropicIndex + 1)
                output += encodeAnthropicEvent(
                    event: "content_block_start",
                    object: [
                        "type": "content_block_start",
                        "index": state.anthropicIndex,
                        "content_block": [
                            "type": "tool_use",
                            "id": state.id,
                            "name": state.name,
                            "input": [:],
                        ],
                    ]
                )
            }

            if let arguments = function?["arguments"] as? String, !arguments.isEmpty {
                output += encodeAnthropicEvent(
                    event: "content_block_delta",
                    object: [
                        "type": "content_block_delta",
                        "index": state.anthropicIndex,
                        "delta": [
                            "type": "input_json_delta",
                            "partial_json": arguments,
                        ],
                    ]
                )
            }

            toolStates[openAIIndex] = state
        }

        return output
    }

    private mutating func finish(stopReason: String) -> String {
        guard !messageStopped else { return "" }
        var output = ensureMessageStarted()

        if !textBlockStarted && toolStates.isEmpty {
            output += ensureTextBlockStarted()
        }

        output += stopTextBlockIfNeeded()
        for key in toolStates.keys.sorted() {
            guard var state = toolStates[key], !state.stopped else { continue }
            state.stopped = true
            toolStates[key] = state
            output += encodeAnthropicEvent(
                event: "content_block_stop",
                object: [
                    "type": "content_block_stop",
                    "index": state.anthropicIndex,
                ]
            )
        }

        output += encodeAnthropicEvent(
            event: "message_delta",
            object: [
                "type": "message_delta",
                "delta": [
                    "stop_reason": stopReason,
                    "stop_sequence": NSNull(),
                ],
                "usage": [
                    "input_tokens": inputTokens,
                    "output_tokens": outputTokens,
                ],
            ]
        )
        output += encodeAnthropicEvent(
            event: "message_stop",
            object: ["type": "message_stop"]
        )
        messageStopped = true
        return output
    }

    private mutating func captureUsage(from usage: [String: Any]?) {
        guard let usage else { return }
        inputTokens = usage["prompt_tokens"] as? Int ?? inputTokens
        outputTokens = usage["completion_tokens"] as? Int ?? outputTokens
    }

    private func anthropicStopReason(for openAIReason: String) -> String {
        switch openAIReason {
        case "length":
            return "max_tokens"
        case "tool_calls", "function_call":
            return "tool_use"
        case "content_filter":
            return "stop_sequence"
        default:
            return "end_turn"
        }
    }

    private func parseJSONObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func encodeAnthropicEvent(event: String, object: [String: Any]) -> String {
        let data: String
        if let jsonData = try? JSONSerialization.data(withJSONObject: object),
           let json = String(data: jsonData, encoding: .utf8) {
            data = json
        } else {
            data = "{\"type\":\"error\",\"error\":{\"type\":\"serialization_error\",\"message\":\"Failed to encode SSE event\"}}"
        }
        return SSEEncoder.encode(event: event, data: data)
    }
}
