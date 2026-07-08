import XCTest
@testable import SmartLLMRouter

// MARK: - Proxy Performance Tests

@MainActor
final class ProxyPerformanceTests: XCTestCase {

    // MARK: - Protocol Conversion Performance

    func testAnthropicToOpenAIConversionPerformance() throws {
        let anthropicBody: [String: Any] = [
            "model": "claude-3-opus-20240229",
            "max_tokens": 4096,
            "system": "You are a helpful assistant that speaks in JSON.",
            "messages": [
                ["role": "user", "content": "Say hello"],
                ["role": "assistant", "content": "Hello! How can I help?"],
                ["role": "user", "content": "Tell me a joke about AI."]
            ],
            "tools": [
                [
                    "name": "search_db",
                    "description": "Search the database",
                    "input_schema": [
                        "type": "object",
                        "properties": ["query": ["type": "string"]]
                    ]
                ]
            ]
        ]

        measure {
            for _ in 0..<100 {
                _ = try? ProtocolConverter.anthropicToOpenAI(body: anthropicBody)
            }
        }
    }

    func testOpenAItoAnthropicConversionPerformance() throws {
        let openaiBody: [String: Any] = [
            "model": "gpt-4o",
            "max_completion_tokens": 4096,
            "messages": [
                ["role": "system", "content": "You are a helpful assistant."],
                ["role": "user", "content": "Say hello"],
                ["role": "assistant", "content": "Hello! How can I help?"],
                ["role": "user", "content": "Tell me a joke about AI."]
            ],
            "tools": [
                [
                    "type": "function",
                    "function": [
                        "name": "search_db",
                        "description": "Search the database",
                        "parameters": [
                            "type": "object",
                            "properties": ["query": ["type": "string"]]
                        ]
                    ]
                ]
            ]
        ]

        measure {
            for _ in 0..<100 {
                _ = try? ProtocolConverter.openAItoAnthropic(body: openaiBody)
            }
        }
    }

    // MARK: - Smart Router Selection Performance

    func testSmartRouterSelectionPerformance() {
        let circuitBreaker = CircuitBreaker()
        let switchLock = SwitchLock()
        let runtimeState = RouterRuntimeState(
            circuitBreaker: circuitBreaker,
            switchLock: switchLock
        )
        let isolatedStore = ChannelStoreTestSupport.makeIsolatedChannelStore(
            useTempFile: false,
            runtimeState: runtimeState
        )
        let isolatedKeychain = KeychainManagerTestSupport.makeIsolatedKeychainManager()
        defer {
            isolatedStore.cleanup()
            isolatedKeychain.cleanup()
        }

        let channelServices = ChannelServices(
            store: isolatedStore.store,
            keychain: isolatedKeychain.manager,
            cooldownEngine: CooldownEngine(channelStore: isolatedStore.store)
        )
        let overrideState = ModelOverrideRuntimeState()
        let aggregator = ModelAggregator(channelServices: channelServices)
        let switcher = ModelSwitcher(
            channelServices: channelServices,
            modelOverrideState: overrideState,
            defaults: isolatedStore.defaults
        )
        let router = SmartRouter(services: RouterServices(
            channelServices: channelServices,
            runtimeState: runtimeState,
            modelOverrideState: overrideState,
            circuitBreaker: circuitBreaker,
            switchLock: switchLock,
            apiKeyAvailabilityStore: APIKeyAvailabilityStore(),
            modelAggregator: aggregator,
            modelSwitcher: switcher,
            usageTracker: UsageTracker(defaults: isolatedStore.defaults)
        ))
        let channelStore = isolatedStore.store
        let models = [
            ModelEntry(id: UUID().uuidString, identifier: "gpt-4o", displayName: "GPT-4o", contextLength: 128000, inputPricePer1M: 5.0, outputPricePer1M: 15.0, isEnabled: true)
        ]
        
        let perfChannels = channelStore.channels.filter { $0.name.hasPrefix("PerfTest-") }
        for channel in perfChannels {
            channelStore.removeChannel(id: channel.id)
        }

        for i in 1...5 {
            let channel = Channel(
                id: UUID().uuidString,
                name: "PerfTest-Channel-\(i)",
                providerId: "openai",
                baseURL: "https://api.openai.com",
                priority: i,
                protocol: .openai,
                models: models
            )
            channelStore.addChannel(channel)
        }

        measure {
            for _ in 0..<100 {
                _ = router.selectChannel(requestID: "perf-\(UUID().uuidString)", modelName: "gpt-4o")
            }
        }

        let cleanupChannels = channelStore.channels.filter { $0.name.hasPrefix("PerfTest-") }
        for channel in cleanupChannels {
            channelStore.removeChannel(id: channel.id)
        }
    }

    // MARK: - Request Model Parsing Performance

    func testModelExtractionPerformance() {
        let body = """
        {
            "model": "claude-3-5-sonnet-20240620",
            "max_tokens": 8192,
            "messages": [{"role": "user", "content": "Hello"}]
        }
        """.data(using: .utf8)!

        // Helper to extract model name from JSON Data
        func extractModel(from jsonData: Data) -> String? {
            guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return nil }
            return json["model"] as? String
        }

        measure {
            for _ in 0..<100 {
                _ = extractModel(from: body)
            }
        }
    }

    func testProtocolDetectionPerformance() {
        let anthropicBody = """
        {"model":"claude-3-opus","max_tokens":100,"system":"Be helpful","messages":[{"role":"user","content":"Hi"}]}
        """.data(using: .utf8)!

        let openaiBody = """
        {"model":"gpt-4o","messages":[{"role":"user","content":"Hi"}],"max_completion_tokens":100}
        """.data(using: .utf8)!

        measure {
            for _ in 0..<100 {
                _ = RequestForwarder.detectProtocol(path: "/v1/messages", body: anthropicBody)
                _ = RequestForwarder.detectProtocol(path: "/v1/chat/completions", body: openaiBody)
            }
        }
    }

    // MARK: - Usage Parsing Performance

    func testUsageExtractionPerformance() {
        let anthropicResponse = """
        {
            "id": "msg_123",
            "type": "message",
            "role": "assistant",
            "model": "claude-3-opus",
            "content": [{"type": "text", "text": "Hello"}],
            "stop_reason": "end_turn",
            "usage": {"input_tokens": 50, "output_tokens": 100}
        }
        """.data(using: .utf8)!

        let openaiResponse = """
        {
            "id": "chatcmpl-123",
            "object": "chat.completion",
            "choices": [{"message": {"role": "assistant", "content": "Hello"}, "finish_reason": "stop"}],
            "usage": {"prompt_tokens": 50, "completion_tokens": 100, "total_tokens": 150}
        }
        """.data(using: .utf8)!

        measure {
            for _ in 0..<100 {
                _ = RequestForwarder.parseUsage(from: anthropicResponse, isAnthropic: true)
                _ = RequestForwarder.parseUsage(from: openaiResponse, isAnthropic: false)
            }
        }
    }
}
