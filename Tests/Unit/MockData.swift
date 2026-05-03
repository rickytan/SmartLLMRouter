import Foundation
@testable import SmartLLMRouter

// MARK: - Mock Data for Tests

enum MockData {
    
    static func makeChannel(
        id: String = UUID().uuidString,
        name: String = "Test Channel",
        providerId: String? = "openai",
        baseURL: String = "https://api.openai.com/v1",
        priority: Int = 1,
        protocol: APIProtocol = .auto,
        models: [ModelEntry] = defaultModels,
        latency: Double = 150.0
    ) -> Channel {
        Channel(
            id: id,
            name: name,
            providerId: providerId,
            baseURL: baseURL,
            priority: priority,
            protocol: `protocol`,
            models: models,
            createdAt: Date()
        )
    }
    
    static let defaultModels: [ModelEntry] = [
        ModelEntry(id: "m1", identifier: "gpt-4o", displayName: "GPT-4o", contextLength: 128_000, inputPricePer1M: 5.0, outputPricePer1M: 15.0),
        ModelEntry(id: "m2", identifier: "gpt-4o-mini", displayName: "Mini", contextLength: 128_000, inputPricePer1M: 0.5, outputPricePer1M: 1.5)
    ]
    
    static let anthropicModels: [ModelEntry] = [
        ModelEntry(id: "m3", identifier: "claude-sonnet-4-20250514", displayName: "Sonnet 4", contextLength: 200_000, inputPricePer1M: 3.0, outputPricePer1M: 15.0),
        ModelEntry(id: "m4", identifier: "claude-opus-4-20250514", displayName: "Opus 4", contextLength: 200_000, inputPricePer1M: 15.0, outputPricePer1M: 75.0)
    ]
    
    static var channelList: [Channel] {
        [
            makeChannel(id: "deepseek", name: "DeepSeek", baseURL: "https://api.deepseek.com", priority: 1, models: defaultModels, latency: 142),
            makeChannel(id: "openai", name: "OpenAI", baseURL: "https://api.openai.com/v1", priority: 2, models: defaultModels, latency: 389),
            makeChannel(id: "anthropic", name: "Anthropic", baseURL: "https://api.anthropic.com", priority: 3, models: anthropicModels, latency: 520)
        ]
    }
    
    static var providersJSON: String {
        """
        {
          "version": "1.1.0",
          "providers": [
            {
              "id": "openai",
              "name_en": "OpenAI",
              "name_zh": "OpenAI",
              "base_url": "https://api.openai.com/v1",
              "supports_protocols": ["openai"],
              "default_models": [
                {"model": "gpt-4o", "protocol": "openai", "context_length": 128000, "input_price": 5.00, "output_price": 15.00}
              ]
            },
            {
              "id": "anthropic",
              "name_en": "Anthropic",
              "name_zh": "Anthropic",
              "base_url": "https://api.anthropic.com",
              "supports_protocols": ["anthropic"],
              "default_models": [
                {"model": "claude-sonnet-4", "protocol": "anthropic", "context_length": 200000, "input_price": 3.00, "output_price": 15.00}
              ]
            }
          ]
        }
        """
    }
}
