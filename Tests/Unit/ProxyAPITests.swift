import XCTest
@testable import SmartLLMRouter

final class ProxyEndpointSupportTests: XCTestCase {
    func testUpstreamTimeoutUsesClientStainlessHeader() {
        let timeout = ProxyEndpointSupport.upstreamTimeout(
            from: ["X-Stainless-Timeout": "600"],
            fallback: 300
        )

        XCTAssertEqual(timeout.interval, 600)
        XCTAssertEqual(timeout.sourceHeader, "x-stainless-timeout")
    }

    func testUpstreamTimeoutPrefersReadTimeoutAndClampsUnsafeValues() {
        let timeout = ProxyEndpointSupport.upstreamTimeout(
            from: [
                "x-stainless-timeout": "600",
                "X-Stainless-Read-Timeout": "999999",
            ],
            fallback: 300
        )

        XCTAssertEqual(timeout.interval, 86_400)
        XCTAssertEqual(timeout.sourceHeader, "x-stainless-read-timeout")
    }

    func testUpstreamTimeoutIgnoresInvalidClientHeader() {
        let timeout = ProxyEndpointSupport.upstreamTimeout(
            from: ["x-stainless-timeout": "not-a-timeout"],
            fallback: 300
        )

        XCTAssertEqual(timeout.interval, 300)
        XCTAssertNil(timeout.sourceHeader)
    }

    func testForwardedResponseHeadersPreserveUpstreamContentTypeAndRetryMetadata() {
        let headers = ProxyEndpointSupport.forwardedResponseHeaders(
            bodyCount: 42,
            isStream: false,
            upstreamHeaders: [
                "Content-Type": "application/problem+json",
                "Retry-After": "60",
                "X-Request-ID": "request-1",
                "Server": "private-upstream"
            ]
        )

        XCTAssertEqual(headers["content-type"], "application/problem+json")
        XCTAssertEqual(headers["content-length"], "42")
        XCTAssertEqual(headers["Retry-After"], "60")
        XCTAssertEqual(headers["X-Request-ID"], "request-1")
        XCTAssertNil(headers["Server"])
    }

    func testForwardedResponseHeadersUseProtocolAwareContentTypeFallback() {
        XCTAssertEqual(
            ProxyEndpointSupport.forwardedResponseHeaders(
                bodyCount: 0,
                isStream: true,
                upstreamHeaders: [:]
            )["content-type"],
            "text/event-stream"
        )
        XCTAssertEqual(
            ProxyEndpointSupport.forwardedResponseHeaders(
                bodyCount: 0,
                isStream: false,
                upstreamHeaders: [:]
            )["content-type"],
            "application/json"
        )
    }
}

// MARK: - Protocol Detection Tests

final class ProtocolDetectionTests: XCTestCase {

    func testDetectProtocolFromAnthropicPath() {
        let body = "{\"model\":\"claude-3-opus\",\"max_tokens\":100}".data(using: .utf8)!
        let detectedProtocol = RequestForwarder.detectProtocol(path: "/v1/messages", body: body)
        XCTAssertEqual(detectedProtocol, .anthropic)
    }

    func testDetectProtocolFromOpenAIPath() {
        let body = "{\"model\":\"gpt-4\",\"messages\":[]}".data(using: .utf8)!
        let detectedProtocol = RequestForwarder.detectProtocol(path: "/v1/chat/completions", body: body)
        XCTAssertEqual(detectedProtocol, .openai)
    }

    func testDetectProtocolFromAnthropicBody() {
        // Anthropic has "system" field which is distinctive
        let body = "{\"model\":\"claude-3\",\"system\":\"You are helpful\",\"messages\":[{\"role\":\"user\",\"content\":\"Hi\"}],\"max_tokens\":100}".data(using: .utf8)!
        let detectedProtocol = RequestForwarder.detectProtocol(path: "/v1/unknown", body: body)
        XCTAssertEqual(detectedProtocol, .anthropic)
    }

    func testDetectProtocolFromOpenAIBody() {
        let body = "{\"model\":\"gpt-4\",\"messages\":[{\"role\":\"user\",\"content\":\"Hi\"}],\"max_completion_tokens\":100}".data(using: .utf8)!
        let detectedProtocol = RequestForwarder.detectProtocol(path: "/v1/unknown", body: body)
        XCTAssertEqual(detectedProtocol, .openai)
    }

    func testDetectProtocolUnknown() {
        let body = "{}".data(using: .utf8)!
        let detectedProtocol = RequestForwarder.detectProtocol(path: "/v1/unknown", body: body)
        XCTAssertEqual(detectedProtocol, .unknown)
    }

    func testDetectStreamingRequest() {
        let streamingBody = "{\"model\":\"gpt-4\",\"stream\":true}".data(using: .utf8)!
        XCTAssertTrue(RequestForwarder.isStreamingRequest(streamingBody))

        let nonStreamingBody = "{\"model\":\"gpt-4\",\"stream\":false}".data(using: .utf8)!
        XCTAssertFalse(RequestForwarder.isStreamingRequest(nonStreamingBody))

        let noStreamBody = "{\"model\":\"gpt-4\"}".data(using: .utf8)!
        XCTAssertFalse(RequestForwarder.isStreamingRequest(noStreamBody))
    }
}

// MARK: - Anthropic Request Tests (per spec)

final class AnthropicRequestTests: XCTestCase {

    // MARK: Basic Request Fields

    func testAnthropicRequestRequiredFields() throws {
        let anthropicBody: [String: Any] = [
            "model": "claude-3-opus-20240229",
            "max_tokens": 1024,
            "messages": [
                ["role": "user", "content": "Hello"]
            ]
        ]

        let openaiBody = try ProtocolConverter.anthropicToOpenAI(body: anthropicBody)

        XCTAssertEqual(openaiBody["model"] as? String, "claude-3-opus-20240229")
        XCTAssertEqual(openaiBody["max_tokens"] as? Int, 1024)

        let messages = openaiBody["messages"] as? [[String: Any]]
        XCTAssertNotNil(messages)
        XCTAssertEqual(messages?.count, 1)
    }

    func testAnthropicTemperature() throws {
        let anthropicBody: [String: Any] = [
            "model": "claude-3-opus",
            "max_tokens": 1024,
            "temperature": 0.7,
            "messages": [["role": "user", "content": "Hi"]]
        ]

        let openaiBody = try ProtocolConverter.anthropicToOpenAI(body: anthropicBody)
        XCTAssertEqual(openaiBody["temperature"] as? Double, 0.7)
    }

    func testAnthropicTopP() throws {
        let anthropicBody: [String: Any] = [
            "model": "claude-3-opus",
            "max_tokens": 1024,
            "top_p": 0.9,
            "messages": [["role": "user", "content": "Hi"]]
        ]

        let openaiBody = try ProtocolConverter.anthropicToOpenAI(body: anthropicBody)
        XCTAssertEqual(openaiBody["top_p"] as? Double, 0.9)
    }

    func testAnthropicStopSequences() throws {
        let anthropicBody: [String: Any] = [
            "model": "claude-3-opus",
            "max_tokens": 1024,
            "stop_sequences": ["END", "STOP"],
            "messages": [["role": "user", "content": "Hi"]]
        ]

        let openaiBody = try ProtocolConverter.anthropicToOpenAI(body: anthropicBody)
        let stop = openaiBody["stop"] as? [String]
        XCTAssertEqual(stop, ["END", "STOP"])
    }

    func testAnthropicStreamFlag() throws {
        let anthropicBody: [String: Any] = [
            "model": "claude-3-opus",
            "max_tokens": 1024,
            "stream": true,
            "messages": [["role": "user", "content": "Hi"]]
        ]

        let openaiBody = try ProtocolConverter.anthropicToOpenAI(body: anthropicBody)
        XCTAssertEqual(openaiBody["stream"] as? Bool, true)
        XCTAssertEqual(
            (openaiBody["stream_options"] as? [String: Any])?["include_usage"] as? Bool,
            true
        )
    }

    func testOpenAIStreamUsageRequestPreservesExistingOptions() throws {
        let original: [String: Any] = [
            "model": "gpt-test",
            "stream": true,
            "stream_options": ["custom_option": "preserved"],
        ]
        let data = try JSONSerialization.data(withJSONObject: original)

        let updatedData = ProtocolConverter.requestingOpenAIStreamUsage(in: data)
        let updated = try XCTUnwrap(
            JSONSerialization.jsonObject(with: updatedData) as? [String: Any]
        )
        let options = try XCTUnwrap(updated["stream_options"] as? [String: Any])

        XCTAssertEqual(options["include_usage"] as? Bool, true)
        XCTAssertEqual(options["custom_option"] as? String, "preserved")
    }

    func testNonStreamingOpenAIRequestIsNotModifiedForUsage() throws {
        let data = Data(#"{"model":"gpt-test","stream":false}"#.utf8)

        XCTAssertEqual(ProtocolConverter.requestingOpenAIStreamUsage(in: data), data)
    }

    // MARK: System Prompt

    func testAnthropicSystemPromptString() throws {
        let anthropicBody: [String: Any] = [
            "model": "claude-3-opus",
            "max_tokens": 1024,
            "system": "You are a helpful assistant.",
            "messages": [["role": "user", "content": "Hi"]]
        ]

        let openaiBody = try ProtocolConverter.anthropicToOpenAI(body: anthropicBody)

        let messages = openaiBody["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 2)

        let systemMessage = messages?.first
        XCTAssertEqual(systemMessage?["role"] as? String, "system")
        XCTAssertEqual(systemMessage?["content"] as? String, "You are a helpful assistant.")
    }

    func testAnthropicSystemPromptArray() throws {
        // Anthropic spec: system can be array of content blocks
        let anthropicBody: [String: Any] = [
            "model": "claude-3-opus",
            "max_tokens": 1024,
            "system": [
                ["type": "text", "text": "You are helpful."],
                ["type": "text", "text": "Be concise."]
            ],
            "messages": [["role": "user", "content": "Hi"]]
        ]

        let openaiBody = try ProtocolConverter.anthropicToOpenAI(body: anthropicBody)

        let messages = openaiBody["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 2)

        let systemMessage = messages?.first
        XCTAssertEqual(systemMessage?["role"] as? String, "system")
        // Should concatenate text blocks
        XCTAssertTrue((systemMessage?["content"] as? String)?.contains("You are helpful.") ?? false)
        XCTAssertTrue((systemMessage?["content"] as? String)?.contains("Be concise.") ?? false)
    }

    // MARK: Message Content

    func testAnthropicMessageContentString() throws {
        let anthropicBody: [String: Any] = [
            "model": "claude-3-opus",
            "max_tokens": 1024,
            "messages": [
                ["role": "user", "content": "Hello, world"]
            ]
        ]

        let openaiBody = try ProtocolConverter.anthropicToOpenAI(body: anthropicBody)

        let messages = openaiBody["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.first?["content"] as? String, "Hello, world")
    }

    func testAnthropicMessageContentArrayText() throws {
        // Anthropic spec: content can be array of content blocks
        let anthropicBody: [String: Any] = [
            "model": "claude-3-opus",
            "max_tokens": 1024,
            "messages": [
                ["role": "user", "content": [
                    ["type": "text", "text": "What's in this image?"]
                ]]
            ]
        ]

        let openaiBody = try ProtocolConverter.anthropicToOpenAI(body: anthropicBody)

        let messages = openaiBody["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.first?["content"] as? String, "What's in this image?")
    }

    func testAnthropicMessageContentImageBlock() throws {
        // Anthropic spec: ImageBlock with source
        let anthropicBody: [String: Any] = [
            "model": "claude-3-opus",
            "max_tokens": 1024,
            "messages": [
                ["role": "user", "content": [
                    ["type": "text", "text": "Analyze this"],
                    ["type": "image", "source": [
                        "type": "base64",
                        "media_type": "image/png",
                        "data": "abc123"
                    ]]
                ]]
            ]
        ]

        let openaiBody = try ProtocolConverter.anthropicToOpenAI(body: anthropicBody)

        let messages = openaiBody["messages"] as? [[String: Any]]
        let content = messages?.first?["content"] as? String
        XCTAssertTrue(content?.contains("Analyze this") ?? false)
        XCTAssertTrue(content?.contains("[Image]") ?? false)
    }

    func testAnthropicAssistantMessage() throws {
        let anthropicBody: [String: Any] = [
            "model": "claude-3-opus",
            "max_tokens": 1024,
            "messages": [
                ["role": "user", "content": "Hi"],
                ["role": "assistant", "content": "Hello!"]
            ]
        ]

        let openaiBody = try ProtocolConverter.anthropicToOpenAI(body: anthropicBody)

        let messages = openaiBody["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 2)
        XCTAssertEqual(messages?.last?["role"] as? String, "assistant")
        XCTAssertEqual(messages?.last?["content"] as? String, "Hello!")
    }

    // MARK: Tool Definition (per Anthropic spec)

    func testAnthropicToolDefinition() throws {
        // Anthropic spec: tools array with name, description, input_schema
        let anthropicBody: [String: Any] = [
            "model": "claude-3-opus",
            "max_tokens": 1024,
            "tools": [
                [
                    "name": "get_weather",
                    "description": "Get current weather for a location",
                    "input_schema": [
                        "type": "object",
                        "properties": [
                            "location": ["type": "string", "description": "City name"]
                        ],
                        "required": ["location"]
                    ]
                ]
            ],
            "messages": [["role": "user", "content": "Weather in Tokyo?"]]
        ]

        let openaiBody = try ProtocolConverter.anthropicToOpenAI(body: anthropicBody)

        let tools = openaiBody["tools"] as? [[String: Any]]
        XCTAssertEqual(tools?.count, 1)

        let tool = tools?.first
        XCTAssertEqual(tool?["type"] as? String, "function")

        let function = tool?["function"] as? [String: Any]
        XCTAssertEqual(function?["name"] as? String, "get_weather")
        XCTAssertEqual(function?["description"] as? String, "Get current weather for a location")
        XCTAssertNotNil(function?["parameters"])
    }

    func testAnthropicToolChoiceAuto() throws {
        let anthropicBody: [String: Any] = [
            "model": "claude-3-opus",
            "max_tokens": 1024,
            "tool_choice": "auto",
            "messages": [["role": "user", "content": "Hi"]]
        ]

        let openaiBody = try ProtocolConverter.anthropicToOpenAI(body: anthropicBody)
        XCTAssertEqual(openaiBody["tool_choice"] as? String, "auto")
    }

    func testAnthropicToolChoiceAny() throws {
        let anthropicBody: [String: Any] = [
            "model": "claude-3-opus",
            "max_tokens": 1024,
            "tool_choice": "any",
            "messages": [["role": "user", "content": "Hi"]]
        ]

        let openaiBody = try ProtocolConverter.anthropicToOpenAI(body: anthropicBody)
        XCTAssertEqual(openaiBody["tool_choice"] as? String, "any")
    }

    func testAnthropicToolChoiceSpecific() throws {
        // Anthropic spec: tool_choice can be {"type": "tool", "name": "xxx"}
        let anthropicBody: [String: Any] = [
            "model": "claude-3-opus",
            "max_tokens": 1024,
            "tool_choice": ["type": "tool", "name": "get_weather"],
            "messages": [["role": "user", "content": "Hi"]]
        ]

        let openaiBody = try ProtocolConverter.anthropicToOpenAI(body: anthropicBody)

        let toolChoice = openaiBody["tool_choice"] as? [String: Any]
        XCTAssertEqual(toolChoice?["type"] as? String, "function")

        let function = toolChoice?["function"] as? [String: Any]
        XCTAssertEqual(function?["name"] as? String, "get_weather")
    }

    // MARK: Tool Use Block in Assistant Message

    func testAnthropicToolUseInResponse() throws {
        // Anthropic spec: tool_use block in assistant response
        let anthropicResponse: [String: Any] = [
            "id": "msg_123",
            "type": "message",
            "role": "assistant",
            "model": "claude-3-opus",
            "content": [
                ["type": "text", "text": "Checking weather..."],
                ["type": "tool_use", "id": "toolu_001", "name": "get_weather", "input": ["location": "Tokyo"]]
            ],
            "stop_reason": "tool_use",
            "usage": ["input_tokens": 50, "output_tokens": 100]
        ]

        let openaiResponse = ProtocolConverter.anthropicToOpenAIResponse(body: anthropicResponse)

        XCTAssertEqual(openaiResponse["object"] as? String, "chat.completion")

        let choices = openaiResponse["choices"] as? [[String: Any]]
        XCTAssertEqual(choices?.first?["finish_reason"] as? String, "tool_calls")

        let message = choices?.first?["message"] as? [String: Any]
        let toolCalls = message?["tool_calls"] as? [[String: Any]]
        XCTAssertEqual(toolCalls?.count, 1)

        let toolCall = toolCalls?.first
        XCTAssertEqual(toolCall?["id"] as? String, "toolu_001")
        XCTAssertEqual(toolCall?["type"] as? String, "function")

        let function = toolCall?["function"] as? [String: Any]
        XCTAssertEqual(function?["name"] as? String, "get_weather")
    }

    // MARK: Tool Result Block (user message with tool result)

    func testAnthropicToolResultBlock() throws {
        // Anthropic spec: tool_result in user message content
        let anthropicBody: [String: Any] = [
            "model": "claude-3-opus",
            "max_tokens": 1024,
            "messages": [
                ["role": "user", "content": "What's the weather?"],
                ["role": "assistant", "content": [
                    ["type": "tool_use", "id": "toolu_001", "name": "get_weather", "input": ["location": "Tokyo"]]
                ]],
                ["role": "user", "content": [
                    ["type": "tool_result", "tool_use_id": "toolu_001", "content": "Sunny, 25°C"]
                ]]
            ]
        ]

        let openaiBody = try ProtocolConverter.anthropicToOpenAI(body: anthropicBody)

        let messages = openaiBody["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 3) // user, assistant with tool_calls, tool result

        // Find the tool result message (role: tool)
        let toolMessage = messages?.filter { ($0["role"] as? String) == "tool" }.first
        XCTAssertNotNil(toolMessage)
        XCTAssertEqual(toolMessage?["content"] as? String, "Sunny, 25°C")
        XCTAssertNotNil(toolMessage?["tool_call_id"])
    }
}

// MARK: - OpenAI Request Tests (per spec)

final class OpenAIRequestTests: XCTestCase {

    // MARK: Basic Request Fields

    func testOpenAIRequestRequiredFields() throws {
        let openaiBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "user", "content": "Hello"]
            ]
        ]

        let anthropicBody = try ProtocolConverter.openAItoAnthropic(body: openaiBody)

        XCTAssertEqual(anthropicBody["model"] as? String, "gpt-4o")

        let messages = anthropicBody["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 1)
        XCTAssertEqual(messages?.first?["role"] as? String, "user")
    }

    func testOpenAIMaxTokens() throws {
        let openaiBody: [String: Any] = [
            "model": "gpt-4o",
            "max_tokens": 4096,
            "messages": [["role": "user", "content": "Hi"]]
        ]

        let anthropicBody = try ProtocolConverter.openAItoAnthropic(body: openaiBody)
        XCTAssertEqual(anthropicBody["max_tokens"] as? Int, 4096)
    }

    func testOpenAIMaxCompletionTokens() throws {
        // OpenAI spec: max_completion_tokens is alternative to max_tokens
        let openaiBody: [String: Any] = [
            "model": "gpt-4o",
            "max_completion_tokens": 8192,
            "messages": [["role": "user", "content": "Hi"]]
        ]

        let anthropicBody = try ProtocolConverter.openAItoAnthropic(body: openaiBody)
        XCTAssertEqual(anthropicBody["max_tokens"] as? Int, 8192)
    }

    func testOpenAITemperature() throws {
        let openaiBody: [String: Any] = [
            "model": "gpt-4o",
            "temperature": 0.5,
            "messages": [["role": "user", "content": "Hi"]]
        ]

        let anthropicBody = try ProtocolConverter.openAItoAnthropic(body: openaiBody)
        XCTAssertEqual(anthropicBody["temperature"] as? Double, 0.5)
    }

    func testOpenAITopP() throws {
        let openaiBody: [String: Any] = [
            "model": "gpt-4o",
            "top_p": 0.95,
            "messages": [["role": "user", "content": "Hi"]]
        ]

        let anthropicBody = try ProtocolConverter.openAItoAnthropic(body: openaiBody)
        XCTAssertEqual(anthropicBody["top_p"] as? Double, 0.95)
    }

    func testOpenAIStopArray() throws {
        let openaiBody: [String: Any] = [
            "model": "gpt-4o",
            "stop": ["END", "STOP"],
            "messages": [["role": "user", "content": "Hi"]]
        ]

        let anthropicBody = try ProtocolConverter.openAItoAnthropic(body: openaiBody)
        let stopSequences = anthropicBody["stop_sequences"] as? [String]
        XCTAssertEqual(stopSequences, ["END", "STOP"])
    }

    func testOpenAIStopString() throws {
        // OpenAI spec: stop can be single string
        let openaiBody: [String: Any] = [
            "model": "gpt-4o",
            "stop": "END",
            "messages": [["role": "user", "content": "Hi"]]
        ]

        let anthropicBody = try ProtocolConverter.openAItoAnthropic(body: openaiBody)
        let stopSequences = anthropicBody["stop_sequences"] as? [String]
        XCTAssertEqual(stopSequences, ["END"])
    }

    func testOpenAIStreamFlag() throws {
        let openaiBody: [String: Any] = [
            "model": "gpt-4o",
            "stream": true,
            "messages": [["role": "user", "content": "Hi"]]
        ]

        let anthropicBody = try ProtocolConverter.openAItoAnthropic(body: openaiBody)
        XCTAssertEqual(anthropicBody["stream"] as? Bool, true)
    }

    // MARK: Message Types (per OpenAI spec)

    func testOpenAISystemMessage() throws {
        // OpenAI spec: SystemMessage with role: system
        let openaiBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "system", "content": "You are a helpful assistant."],
                ["role": "user", "content": "Hi"]
            ]
        ]

        let anthropicBody = try ProtocolConverter.openAItoAnthropic(body: openaiBody)

        // System should be extracted to top-level field
        XCTAssertEqual(anthropicBody["system"] as? String, "You are a helpful assistant.")

        // Messages should exclude system
        let messages = anthropicBody["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 1)
        XCTAssertEqual(messages?.first?["role"] as? String, "user")
    }

    func testOpenAIUserMessageString() throws {
        let openaiBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "user", "content": "Hello"]
            ]
        ]

        let anthropicBody = try ProtocolConverter.openAItoAnthropic(body: openaiBody)

        let messages = anthropicBody["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.first?["role"] as? String, "user")
        XCTAssertEqual(messages?.first?["content"] as? String, "Hello")
    }

    func testOpenAIUserMessageArray() throws {
        // OpenAI spec: UserMessage content can be array of ContentPart
        let openaiBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "user", "content": [
                    ["type": "text", "text": "What's this?"],
                    ["type": "image_url", "image_url": ["url": "https://example.com/img.png"]]
                ]]
            ]
        ]

        let anthropicBody = try ProtocolConverter.openAItoAnthropic(body: openaiBody)

        let messages = anthropicBody["messages"] as? [[String: Any]]
        XCTAssertNotNil(messages?.first?["content"])
    }

    func testOpenAIAssistantMessage() throws {
        // OpenAI spec: AssistantMessage
        let openaiBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "user", "content": "Hi"],
                ["role": "assistant", "content": "Hello! How can I help?"]
            ]
        ]

        let anthropicBody = try ProtocolConverter.openAItoAnthropic(body: openaiBody)

        let messages = anthropicBody["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 2)
        XCTAssertEqual(messages?.last?["role"] as? String, "assistant")
        XCTAssertEqual(messages?.last?["content"] as? String, "Hello! How can I help?")
    }

    func testOpenAIAssistantMessageWithToolCalls() throws {
        // OpenAI spec: AssistantMessage can have tool_calls
        let openaiBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "user", "content": "Weather in Tokyo?"],
                ["role": "assistant", "content": nil, "tool_calls": [
                    [
                        "id": "call_001",
                        "type": "function",
                        "function": [
                            "name": "get_weather",
                            "arguments": "{\"location\":\"Tokyo\"}"
                        ]
                    ]
                ]]
            ]
        ]

        let anthropicBody = try ProtocolConverter.openAItoAnthropic(body: openaiBody)

        let messages = anthropicBody["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 2)

        let assistantMsg = messages?.last
        XCTAssertEqual(assistantMsg?["role"] as? String, "assistant")

        let content = assistantMsg?["content"] as? [[String: Any]]
        XCTAssertNotNil(content)

        // Should have tool_use block
        let toolUseBlock = content?.filter { ($0["type"] as? String) == "tool_use" }.first
        XCTAssertNotNil(toolUseBlock)
        XCTAssertEqual(toolUseBlock?["id"] as? String, "call_001")
        XCTAssertEqual(toolUseBlock?["name"] as? String, "get_weather")
    }

    func testOpenAIToolMessage() throws {
        // OpenAI spec: ToolMessage with role: tool, tool_call_id
        let openaiBody: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "user", "content": "Weather?"],
                ["role": "assistant", "tool_calls": [
                    ["id": "call_001", "type": "function", "function": ["name": "get_weather", "arguments": "{}"]]
                ]],
                ["role": "tool", "tool_call_id": "call_001", "content": "Sunny, 25°C"]
            ]
        ]

        let anthropicBody = try ProtocolConverter.openAItoAnthropic(body: openaiBody)

        let messages = anthropicBody["messages"] as? [[String: Any]]

        // Tool message becomes user message with tool_result
        let toolResultMsg = messages?.last
        XCTAssertEqual(toolResultMsg?["role"] as? String, "user")

        let content = toolResultMsg?["content"] as? [[String: Any]]
        let toolResultBlock = content?.filter { ($0["type"] as? String) == "tool_result" }.first
        XCTAssertNotNil(toolResultBlock)
        XCTAssertEqual(toolResultBlock?["tool_use_id"] as? String, "call_001")
        XCTAssertEqual(toolResultBlock?["content"] as? String, "Sunny, 25°C")
    }

    // MARK: Tool Definition (per OpenAI spec)

    func testOpenAIToolDefinition() throws {
        // OpenAI spec: ChatCompletionTool with type: function
        let openaiBody: [String: Any] = [
            "model": "gpt-4o",
            "tools": [
                [
                    "type": "function",
                    "function": [
                        "name": "search",
                        "description": "Search the web",
                        "parameters": [
                            "type": "object",
                            "properties": [
                                "query": ["type": "string"]
                            ]
                        ]
                    ]
                ]
            ],
            "messages": [["role": "user", "content": "Search for cats"]]
        ]

        let anthropicBody = try ProtocolConverter.openAItoAnthropic(body: openaiBody)

        let tools = anthropicBody["tools"] as? [[String: Any]]
        XCTAssertEqual(tools?.count, 1)

        let tool = tools?.first
        XCTAssertEqual(tool?["name"] as? String, "search")
        XCTAssertEqual(tool?["description"] as? String, "Search the web")
        XCTAssertNotNil(tool?["input_schema"])
    }

    func testOpenAIToolChoiceNone() throws {
        let openaiBody: [String: Any] = [
            "model": "gpt-4o",
            "tool_choice": "none",
            "messages": [["role": "user", "content": "Hi"]]
        ]

        // Note: "none" is not converted to Anthropic (not supported)
        let anthropicBody = try ProtocolConverter.openAItoAnthropic(body: openaiBody)
        XCTAssertNil(anthropicBody["tool_choice"])
    }

    func testOpenAIToolChoiceAuto() throws {
        let openaiBody: [String: Any] = [
            "model": "gpt-4o",
            "tool_choice": "auto",
            "messages": [["role": "user", "content": "Hi"]]
        ]

        let anthropicBody = try ProtocolConverter.openAItoAnthropic(body: openaiBody)

        let toolChoice = anthropicBody["tool_choice"] as? [String: Any]
        XCTAssertEqual(toolChoice?["type"] as? String, "auto")
    }

    func testOpenAIToolChoiceFunction() throws {
        // OpenAI spec: NamedToolChoice with type: function, function.name
        let openaiBody: [String: Any] = [
            "model": "gpt-4o",
            "tool_choice": [
                "type": "function",
                "function": ["name": "search"]
            ],
            "messages": [["role": "user", "content": "Hi"]]
        ]

        let anthropicBody = try ProtocolConverter.openAItoAnthropic(body: openaiBody)

        let toolChoice = anthropicBody["tool_choice"] as? [String: Any]
        XCTAssertEqual(toolChoice?["type"] as? String, "tool")
        XCTAssertEqual(toolChoice?["name"] as? String, "search")
    }

    // MARK: Response Format

    func testOpenAIResponseFormatText() {
        // OpenAI spec: ResponseFormat type: text (default)
        // No conversion needed for Anthropic - not supported
        // This test verifies we don't crash on response_format
        let openaiBody: [String: Any] = [
            "model": "gpt-4o",
            "response_format": ["type": "text"],
            "messages": [["role": "user", "content": "Hi"]]
        ]

        XCTAssertNoThrow(try ProtocolConverter.openAItoAnthropic(body: openaiBody))
    }

    func testOpenAIResponseFormatJson() {
        // OpenAI spec: ResponseFormat type: json_object
        let openaiBody: [String: Any] = [
            "model": "gpt-4o",
            "response_format": ["type": "json_object"],
            "messages": [["role": "user", "content": "Hi"]]
        ]

        XCTAssertNoThrow(try ProtocolConverter.openAItoAnthropic(body: openaiBody))
    }
}

// MARK: - Response Conversion Tests

final class ResponseConversionTests: XCTestCase {

    // MARK: Anthropic → OpenAI Response

    func testAnthropicTextResponse() {
        let anthropicResponse: [String: Any] = [
            "id": "msg_123",
            "type": "message",
            "role": "assistant",
            "model": "claude-3-opus",
            "content": [
                ["type": "text", "text": "Hello! How can I help?"]
            ],
            "stop_reason": "end_turn",
            "usage": ["input_tokens": 10, "output_tokens": 20]
        ]

        let openaiResponse = ProtocolConverter.anthropicToOpenAIResponse(body: anthropicResponse)

        XCTAssertEqual(openaiResponse["id"] as? String, "msg_123")
        XCTAssertEqual(openaiResponse["object"] as? String, "chat.completion")
        XCTAssertEqual(openaiResponse["model"] as? String, "claude-3-opus")

        let choices = openaiResponse["choices"] as? [[String: Any]]
        XCTAssertEqual(choices?.count, 1)

        let message = choices?.first?["message"] as? [String: Any]
        XCTAssertEqual(message?["role"] as? String, "assistant")
        XCTAssertEqual(message?["content"] as? String, "Hello! How can I help?")
        XCTAssertEqual(choices?.first?["finish_reason"] as? String, "stop")

        let usage = openaiResponse["usage"] as? [String: Any]
        XCTAssertEqual(usage?["prompt_tokens"] as? Int, 10)
        XCTAssertEqual(usage?["completion_tokens"] as? Int, 20)
        XCTAssertEqual(usage?["total_tokens"] as? Int, 30)
    }

    func testAnthropicStopReasonEndTurn() {
        let anthropicResponse: [String: Any] = [
            "id": "msg_1",
            "stop_reason": "end_turn",
            "content": [["type": "text", "text": "Done"]]
        ]

        let openaiResponse = ProtocolConverter.anthropicToOpenAIResponse(body: anthropicResponse)
        let choices = openaiResponse["choices"] as? [[String: Any]]
        XCTAssertEqual(choices?.first?["finish_reason"] as? String, "stop")
    }

    func testAnthropicStopReasonMaxTokens() {
        let anthropicResponse: [String: Any] = [
            "id": "msg_1",
            "stop_reason": "max_tokens",
            "content": [["type": "text", "text": "Truncated"]]
        ]

        let openaiResponse = ProtocolConverter.anthropicToOpenAIResponse(body: anthropicResponse)
        let choices = openaiResponse["choices"] as? [[String: Any]]
        XCTAssertEqual(choices?.first?["finish_reason"] as? String, "length")
    }

    func testAnthropicStopReasonStopSequence() {
        let anthropicResponse: [String: Any] = [
            "id": "msg_1",
            "stop_reason": "stop_sequence",
            "content": [["type": "text", "text": "Stopped"]]
        ]

        let openaiResponse = ProtocolConverter.anthropicToOpenAIResponse(body: anthropicResponse)
        let choices = openaiResponse["choices"] as? [[String: Any]]
        XCTAssertEqual(choices?.first?["finish_reason"] as? String, "content_filter")
    }

    func testAnthropicStopReasonToolUse() {
        let anthropicResponse: [String: Any] = [
            "id": "msg_1",
            "stop_reason": "tool_use",
            "content": [["type": "tool_use", "id": "t1", "name": "search", "input": "{}"]]
        ]

        let openaiResponse = ProtocolConverter.anthropicToOpenAIResponse(body: anthropicResponse)
        let choices = openaiResponse["choices"] as? [[String: Any]]
        XCTAssertEqual(choices?.first?["finish_reason"] as? String, "tool_calls")
    }

    func testAnthropicToolUseContent() {
        let anthropicResponse: [String: Any] = [
            "id": "msg_123",
            "type": "message",
            "role": "assistant",
            "model": "claude-3-opus",
            "content": [
                ["type": "text", "text": "Let me search"],
                ["type": "tool_use", "id": "toolu_123", "name": "search", "input": "{\"query\":\"cats\"}"]
            ],
            "stop_reason": "tool_use",
            "usage": ["input_tokens": 10, "output_tokens": 15]
        ]

        let openaiResponse = ProtocolConverter.anthropicToOpenAIResponse(body: anthropicResponse)

        let choices = openaiResponse["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]

        XCTAssertEqual(message?["content"] as? String, "Let me search")

        let toolCalls = message?["tool_calls"] as? [[String: Any]]
        XCTAssertEqual(toolCalls?.count, 1)

        let toolCall = toolCalls?.first
        XCTAssertEqual(toolCall?["id"] as? String, "toolu_123")
        XCTAssertEqual(toolCall?["type"] as? String, "function")

        let function = toolCall?["function"] as? [String: Any]
        XCTAssertEqual(function?["name"] as? String, "search")
        XCTAssertEqual(function?["arguments"] as? String, "{\"query\":\"cats\"}")
    }

    func testAnthropicToolUseWithDictInput() {
        // Anthropic spec: input can be object (dict), needs JSON serialization
        let anthropicResponse: [String: Any] = [
            "id": "msg_123",
            "type": "message",
            "role": "assistant",
            "model": "claude-3-opus",
            "content": [
                ["type": "tool_use", "id": "toolu_001", "name": "get_weather", "input": ["location": "Tokyo", "unit": "celsius"]]
            ],
            "stop_reason": "tool_use",
            "usage": ["input_tokens": 10, "output_tokens": 15]
        ]

        let openaiResponse = ProtocolConverter.anthropicToOpenAIResponse(body: anthropicResponse)

        let choices = openaiResponse["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let toolCalls = message?["tool_calls"] as? [[String: Any]]
        let function = toolCalls?.first?["function"] as? [String: Any]

        // Input dict should be serialized to JSON string
        XCTAssertNotNil(function?["arguments"])
        XCTAssertTrue((function?["arguments"] as? String)?.contains("Tokyo") ?? false)
    }

    // MARK: OpenAI → Anthropic Response

    func testOpenAITextResponse() {
        let openaiResponse: [String: Any] = [
            "id": "chatcmpl-123",
            "object": "chat.completion",
            "created": 1234567890,
            "model": "gpt-4o",
            "choices": [
                [
                    "index": 0,
                    "message": ["role": "assistant", "content": "Hello!"],
                    "finish_reason": "stop"
                ]
            ],
            "usage": ["prompt_tokens": 10, "completion_tokens": 20, "total_tokens": 30]
        ]

        let anthropicResponse = ProtocolConverter.openAItoAnthropicResponse(body: openaiResponse)

        XCTAssertEqual(anthropicResponse["id"] as? String, "chatcmpl-123")
        XCTAssertEqual(anthropicResponse["type"] as? String, "message")
        XCTAssertEqual(anthropicResponse["role"] as? String, "assistant")
        XCTAssertEqual(anthropicResponse["model"] as? String, "gpt-4o")
        XCTAssertEqual(anthropicResponse["stop_reason"] as? String, "end_turn")

        let content = anthropicResponse["content"] as? [[String: Any]]
        XCTAssertEqual(content?.first?["type"] as? String, "text")
        XCTAssertEqual(content?.first?["text"] as? String, "Hello!")

        let usage = anthropicResponse["usage"] as? [String: Any]
        XCTAssertEqual(usage?["input_tokens"] as? Int, 10)
        XCTAssertEqual(usage?["output_tokens"] as? Int, 20)
    }

    func testOpenAIFinishReasonStop() {
        let openaiResponse: [String: Any] = [
            "id": "cmpl_1",
            "choices": [["finish_reason": "stop", "message": ["content": "Done"]]]
        ]

        let anthropicResponse = ProtocolConverter.openAItoAnthropicResponse(body: openaiResponse)
        XCTAssertEqual(anthropicResponse["stop_reason"] as? String, "end_turn")
    }

    func testOpenAIFinishReasonLength() {
        let openaiResponse: [String: Any] = [
            "id": "cmpl_1",
            "choices": [["finish_reason": "length", "message": ["content": "Truncated"]]]
        ]

        let anthropicResponse = ProtocolConverter.openAItoAnthropicResponse(body: openaiResponse)
        XCTAssertEqual(anthropicResponse["stop_reason"] as? String, "max_tokens")
    }

    func testOpenAIFinishReasonToolCalls() {
        let openaiResponse: [String: Any] = [
            "id": "cmpl_1",
            "choices": [["finish_reason": "tool_calls", "message": ["tool_calls": []]]]
        ]

        let anthropicResponse = ProtocolConverter.openAItoAnthropicResponse(body: openaiResponse)
        XCTAssertEqual(anthropicResponse["stop_reason"] as? String, "tool_use")
    }

    func testOpenAIFinishReasonContentFilter() {
        let openaiResponse: [String: Any] = [
            "id": "cmpl_1",
            "choices": [["finish_reason": "content_filter", "message": ["content": "Filtered"]]]
        ]

        let anthropicResponse = ProtocolConverter.openAItoAnthropicResponse(body: openaiResponse)
        XCTAssertEqual(anthropicResponse["stop_reason"] as? String, "stop_sequence")
    }

    func testOpenAIToolCallsResponse() {
        let openaiResponse: [String: Any] = [
            "id": "chatcmpl-123",
            "object": "chat.completion",
            "model": "gpt-4o",
            "choices": [
                [
                    "index": 0,
                    "message": [
                        "role": "assistant",
                        "content": nil,
                        "tool_calls": [
                            [
                                "id": "call_001",
                                "type": "function",
                                "function": ["name": "get_weather", "arguments": "{\"location\":\"Tokyo\"}"]
                            ]
                        ]
                    ],
                    "finish_reason": "tool_calls"
                ]
            ],
            "usage": ["prompt_tokens": 10, "completion_tokens": 15, "total_tokens": 25]
        ]

        let anthropicResponse = ProtocolConverter.openAItoAnthropicResponse(body: openaiResponse)

        XCTAssertEqual(anthropicResponse["stop_reason"] as? String, "tool_use")

        let content = anthropicResponse["content"] as? [[String: Any]]
        XCTAssertEqual(content?.count, 1)

        let toolUseBlock = content?.first
        XCTAssertEqual(toolUseBlock?["type"] as? String, "tool_use")
        XCTAssertEqual(toolUseBlock?["id"] as? String, "call_001")
        XCTAssertEqual(toolUseBlock?["name"] as? String, "get_weather")
        XCTAssertEqual(toolUseBlock?["input"] as? String, "{\"location\":\"Tokyo\"}")
    }

    func testOpenAIMultipleToolCallsResponse() {
        let openaiResponse: [String: Any] = [
            "id": "chatcmpl-123",
            "model": "gpt-4o",
            "choices": [
                [
                    "index": 0,
                    "message": [
                        "role": "assistant",
                        "content": nil,
                        "tool_calls": [
                            ["id": "call_1", "type": "function", "function": ["name": "search", "arguments": "{}"]],
                            ["id": "call_2", "type": "function", "function": ["name": "lookup", "arguments": "{}"]]
                        ]
                    ],
                    "finish_reason": "tool_calls"
                ]
            ]
        ]

        let anthropicResponse = ProtocolConverter.openAItoAnthropicResponse(body: openaiResponse)

        let content = anthropicResponse["content"] as? [[String: Any]]
        XCTAssertEqual(content?.count, 2)

        let toolNames = content?.compactMap { $0["name"] as? String }
        XCTAssertEqual(toolNames, ["search", "lookup"])
    }
}

// MARK: - Usage Parsing Tests

final class UsageParsingTests: XCTestCase {

    func testParseAnthropicUsage() {
        let responseJson: [String: Any] = [
            "id": "msg_123",
            "usage": ["input_tokens": 100, "output_tokens": 200]
        ]
        let data = try! JSONSerialization.data(withJSONObject: responseJson)

        let usage = RequestForwarder.parseUsage(from: data, isAnthropic: true)
        XCTAssertEqual(usage.input, 100)
        XCTAssertEqual(usage.output, 200)
    }

    func testParseClaudeCodeCacheOnlyInputUsage() {
        let responseJson: [String: Any] = [
            "id": "msg_cached",
            "usage": [
                "input_tokens": 0,
                "output_tokens": 12,
                "cache_creation_input_tokens": 0,
                "cache_read_input_tokens": 8_192,
            ],
        ]
        let data = try! JSONSerialization.data(withJSONObject: responseJson)

        let usage = RequestForwarder.parseUsage(from: data, isAnthropic: true)
        XCTAssertEqual(usage.input, 8_192)
        XCTAssertEqual(usage.output, 12)
    }

    func testParseAnthropicUsageWithCacheTokens() {
        // Anthropic spec: usage can have cache tokens
        let responseJson: [String: Any] = [
            "id": "msg_123",
            "usage": [
                "input_tokens": 100,
                "output_tokens": 200,
                "cache_creation_input_tokens": 50,
                "cache_read_input_tokens": 75
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: responseJson)

        let usage = RequestForwarder.parseUsage(from: data, isAnthropic: true)
        XCTAssertEqual(usage.input, 225)
        XCTAssertEqual(usage.output, 200)
    }

    func testParseOpenAIUsage() {
        let responseJson: [String: Any] = [
            "id": "chatcmpl-123",
            "usage": ["prompt_tokens": 50, "completion_tokens": 75, "total_tokens": 125]
        ]
        let data = try! JSONSerialization.data(withJSONObject: responseJson)

        let usage = RequestForwarder.parseUsage(from: data, isAnthropic: false)
        XCTAssertEqual(usage.input, 50)
        XCTAssertEqual(usage.output, 75)
    }

    func testParseOpenAICompatibleUsageAliases() {
        let responseJson: [String: Any] = [
            "id": "chatcmpl-123",
            "usage": ["input_tokens": 60, "output_tokens": 80],
        ]
        let data = try! JSONSerialization.data(withJSONObject: responseJson)

        let usage = RequestForwarder.parseUsage(from: data, isAnthropic: false)
        XCTAssertEqual(usage.input, 60)
        XCTAssertEqual(usage.output, 80)
    }

    func testParseUsageMissing() {
        let responseJson: [String: Any] = ["id": "msg_123"]
        let data = try! JSONSerialization.data(withJSONObject: responseJson)

        let usage = RequestForwarder.parseUsage(from: data, isAnthropic: true)
        XCTAssertEqual(usage.input, 0)
        XCTAssertEqual(usage.output, 0)
    }

    func testParseUsageFallsBackToEstimatedTokensWhenProviderOmitsUsage() throws {
        let request = try JSONSerialization.data(withJSONObject: [
            "model": "sensenova-test",
            "messages": [["role": "user", "content": "Explain this request in a concise way"]],
            "stream": false,
        ])
        let response = try JSONSerialization.data(withJSONObject: [
            "choices": [[
                "message": ["role": "assistant", "content": "A concise response"],
            ]],
        ])

        let usage = RequestForwarder.parseUsage(
            from: response,
            isAnthropic: false,
            requestBody: request
        )

        XCTAssertGreaterThan(usage.input, 0)
        XCTAssertGreaterThan(usage.output, 0)
    }

    func testParseUsagePrefersExactProviderValuesOverEstimates() throws {
        let request = Data(#"{"messages":[{"role":"user","content":"hello"}]}"#.utf8)
        let response = try JSONSerialization.data(withJSONObject: [
            "usage": ["prompt_tokens": 11, "completion_tokens": 7],
            "choices": [["message": ["content": "response"]]],
        ])

        let usage = RequestForwarder.parseUsage(
            from: response,
            isAnthropic: false,
            requestBody: request
        )

        XCTAssertEqual(usage.input, 11)
        XCTAssertEqual(usage.output, 7)
    }

    func testParseUsageInvalidData() {
        let data = "invalid json".data(using: .utf8)!

        let usage = RequestForwarder.parseUsage(from: data, isAnthropic: true)
        XCTAssertEqual(usage.input, 0)
        XCTAssertEqual(usage.output, 0)
    }
}

// MARK: - SSE Parsing Tests (per both specs)

final class SSEParsingTests: XCTestCase {

    func testParseSingleEvent() {
        var parser = SSEParser()
        let chunk = "data: {\"content\":\"Hello\"}\n\n".data(using: .utf8)!

        let events = parser.parse(chunk)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.data, "{\"content\":\"Hello\"}")
        XCTAssertNil(events.first?.event)
    }

    func testParseAnthropicStreamEvent() {
        // Anthropic spec: message_start event
        var parser = SSEParser()
        let chunk = "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_1\"}}\n\n".data(using: .utf8)!

        let events = parser.parse(chunk)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.event, "message_start")
        XCTAssertTrue(events.first?.data.contains("message_start") ?? false)
    }

    func testParseAnthropicContentBlockDelta() {
        // Anthropic spec: content_block_delta event
        var parser = SSEParser()
        let chunk = "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello\"}}\n\n".data(using: .utf8)!

        let events = parser.parse(chunk)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.event, "content_block_delta")
    }

    func testParseAnthropicMessageStop() {
        // Anthropic spec: message_stop event
        var parser = SSEParser()
        let chunk = "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n".data(using: .utf8)!

        let events = parser.parse(chunk)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.event, "message_stop")
    }

    func testParseAnthropicPingEvent() {
        // Anthropic spec: ping event
        var parser = SSEParser()
        let chunk = "event: ping\ndata: {\"type\":\"ping\"}\n\n".data(using: .utf8)!

        let events = parser.parse(chunk)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.event, "ping")
    }

    func testParseOpenAIStreamChunk() {
        // OpenAI spec: chat.completion.chunk
        var parser = SSEParser()
        let chunk = "data: {\"id\":\"chatcmpl-1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"delta\":{\"content\":\"Hi\"}}]}\n\n".data(using: .utf8)!

        let events = parser.parse(chunk)
        XCTAssertEqual(events.count, 1)
        XCTAssertNil(events.first?.event)
        XCTAssertTrue(events.first?.data.contains("chat.completion.chunk") ?? false)
    }

    func testParseOpenAIStreamDone() {
        // OpenAI spec: [DONE] marker
        var parser = SSEParser()
        let chunk = "data: [DONE]\n\n".data(using: .utf8)!

        let events = parser.parse(chunk)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.data, "[DONE]")
    }

    func testConvertOpenAITextStreamToAnthropicEvents() throws {
        let openAIStream = """
        data: {"id":"chatcmpl-1","object":"chat.completion.chunk","model":"gpt-4o","choices":[{"index":0,"delta":{"role":"assistant"},"finish_reason":null}]}

        data: {"id":"chatcmpl-1","object":"chat.completion.chunk","model":"gpt-4o","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}

        data: {"id":"chatcmpl-1","object":"chat.completion.chunk","model":"gpt-4o","choices":[{"index":0,"delta":{"content":" world"},"finish_reason":null}]}

        data: {"id":"chatcmpl-1","object":"chat.completion.chunk","model":"gpt-4o","choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":9,"completion_tokens":2}}

        data: [DONE]

        """

        let converted = ProtocolConverter.openAItoAnthropicStreamingResponse(
            data: Data(openAIStream.utf8),
            messageID: "msg_test",
            model: "gpt-4o"
        )

        var parser = SSEParser()
        let events = parser.parse(converted)
        XCTAssertEqual(events.map(\.event), [
            "message_start",
            "content_block_start",
            "content_block_delta",
            "content_block_delta",
            "content_block_stop",
            "message_delta",
            "message_stop",
        ])

        let messageStart = try XCTUnwrap(jsonObject(from: events[0].data))
        let message = try XCTUnwrap(messageStart["message"] as? [String: Any])
        XCTAssertEqual(message["id"] as? String, "msg_test")
        XCTAssertEqual(message["model"] as? String, "gpt-4o")

        let firstDelta = try XCTUnwrap(jsonObject(from: events[2].data))
        let firstDeltaBody = try XCTUnwrap(firstDelta["delta"] as? [String: Any])
        XCTAssertEqual(firstDeltaBody["type"] as? String, "text_delta")
        XCTAssertEqual(firstDeltaBody["text"] as? String, "Hello")

        let stop = try XCTUnwrap(jsonObject(from: events[5].data))
        let stopDelta = try XCTUnwrap(stop["delta"] as? [String: Any])
        let usage = try XCTUnwrap(stop["usage"] as? [String: Any])
        XCTAssertEqual(stopDelta["stop_reason"] as? String, "end_turn")
        XCTAssertEqual(usage["input_tokens"] as? Int, 9)
        XCTAssertEqual(usage["output_tokens"] as? Int, 2)
    }

    func testConvertOpenAIToolCallStreamToAnthropicEvents() throws {
        let openAIStream = """
        data: {"id":"chatcmpl-1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"role":"assistant"},"finish_reason":null}]}

        data: {"id":"chatcmpl-1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"read_file","arguments":"{\\"path\\""}}]},"finish_reason":null}]}

        data: {"id":"chatcmpl-1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":":\\"README.md\\"}"}}]},"finish_reason":null}]}

        data: {"id":"chatcmpl-1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

        data: [DONE]

        """

        let converted = ProtocolConverter.openAItoAnthropicStreamingResponse(
            data: Data(openAIStream.utf8),
            messageID: "msg_tool",
            model: "gpt-4o"
        )

        var parser = SSEParser()
        let events = parser.parse(converted)
        XCTAssertEqual(events.map(\.event), [
            "message_start",
            "content_block_start",
            "content_block_delta",
            "content_block_delta",
            "content_block_stop",
            "message_delta",
            "message_stop",
        ])

        let blockStart = try XCTUnwrap(jsonObject(from: events[1].data))
        let contentBlock = try XCTUnwrap(blockStart["content_block"] as? [String: Any])
        XCTAssertEqual(blockStart["index"] as? Int, 0)
        XCTAssertEqual(contentBlock["type"] as? String, "tool_use")
        XCTAssertEqual(contentBlock["id"] as? String, "call_1")
        XCTAssertEqual(contentBlock["name"] as? String, "read_file")

        let firstDelta = try XCTUnwrap(jsonObject(from: events[2].data))
        let firstDeltaBody = try XCTUnwrap(firstDelta["delta"] as? [String: Any])
        XCTAssertEqual(firstDeltaBody["type"] as? String, "input_json_delta")
        XCTAssertEqual(firstDeltaBody["partial_json"] as? String, "{\"path\"")

        let stop = try XCTUnwrap(jsonObject(from: events[5].data))
        let stopDelta = try XCTUnwrap(stop["delta"] as? [String: Any])
        XCTAssertEqual(stopDelta["stop_reason"] as? String, "tool_use")
    }

    func testParseMultipleEvents() {
        var parser = SSEParser()
        let chunk = "event: message_start\ndata: {\"type\":\"message_start\"}\n\nevent: content_block_start\ndata: {\"type\":\"content_block_start\"}\n\n".data(using: .utf8)!

        let events = parser.parse(chunk)
        XCTAssertEqual(events.count, 2)

        XCTAssertEqual(events.first?.event, "message_start")
        XCTAssertEqual(events.first?.data, "{\"type\":\"message_start\"}")

        XCTAssertEqual(events.last?.event, "content_block_start")
        XCTAssertEqual(events.last?.data, "{\"type\":\"content_block_start\"}")
    }

    func testParseEventWithId() {
        var parser = SSEParser()
        let chunk = "id: 123\ndata: test\n\n".data(using: .utf8)!

        let events = parser.parse(chunk)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.id, "123")
        XCTAssertEqual(events.first?.data, "test")
    }

    func testParseMultilineData() {
        var parser = SSEParser()
        let chunk = "data: line1\ndata: line2\n\n".data(using: .utf8)!

        let events = parser.parse(chunk)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.data, "line1\nline2")
    }

    func testParseIncompleteChunk() {
        var parser = SSEParser()
        let chunk1 = "data: hello\n".data(using: .utf8)!  // Missing final \n\n
        let chunk2 = "\n".data(using: .utf8)!

        let events1 = parser.parse(chunk1)
        XCTAssertEqual(events1.count, 0)  // Not complete yet

        let events2 = parser.parse(chunk2)
        XCTAssertEqual(events2.count, 1)
        XCTAssertEqual(events2.first?.data, "hello")
    }

    func testParseErrorEvent() {
        // Anthropic spec: error event
        var parser = SSEParser()
        let chunk = "event: error\ndata: {\"type\":\"error\",\"error\":{\"type\":\"overloaded_error\",\"message\":\"Overloaded\"}}\n\n".data(using: .utf8)!

        let events = parser.parse(chunk)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.event, "error")
        XCTAssertTrue(events.first?.data.contains("error") ?? false)
    }

    func testSSEEncoding() {
        let encoded = SSEEncoder.encode(event: "message", data: "{\"text\":\"hi\"}", id: "abc")

        XCTAssertTrue(encoded.contains("event: message"))
        XCTAssertTrue(encoded.contains("id: abc"))
        XCTAssertTrue(encoded.contains("data: {\"text\":\"hi\"}"))
        XCTAssertTrue(encoded.hasSuffix("\n"))
    }

    func testSSEEncodingMultilineData() {
        let encoded = SSEEncoder.encode(data: "line1\nline2")

        XCTAssertTrue(encoded.contains("data: line1"))
        XCTAssertTrue(encoded.contains("data: line2"))
    }

    func testSSEEncodingNoEvent() {
        let encoded = SSEEncoder.encode(data: "{\"content\":\"test\"}")

        XCTAssertFalse(encoded.contains("event:"))
        XCTAssertTrue(encoded.contains("data: {\"content\":\"test\"}"))
    }

    private func jsonObject(from text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
