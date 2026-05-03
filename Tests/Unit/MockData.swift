import Foundation
import SwiftUI

// MARK: - Local Types for Testing (Mirrors Sources/Models)

enum APIProtocolTest: String, Codable, CaseIterable {
    case openai = "OpenAI"
    case anthropic = "Anthropic"
    case auto = "Auto"
}

struct ModelEntryTest: Identifiable, Codable, Equatable {
    let id: String
    var identifier: String
    var displayName: String
    var contextLength: Int?
    var inputPricePer1M: Double?
    var outputPricePer1M: Double?
    var isEnabled: Bool
}

struct ChannelTest: Identifiable, Codable {
    let id: String
    var name: String
    var providerId: String?
    var baseURL: String
    var priority: Int
    var `protocol`: APIProtocolTest
    var models: [ModelEntryTest]
    var isCoolingDown: Bool
    var cooldownUntil: Date?
    var lastLatencyMs: Double
    var createdAt: Date
    
    init(
        id: String = UUID().uuidString,
        name: String,
        providerId: String? = nil,
        baseURL: String,
        priority: Int = 1,
        protocol: APIProtocolTest = .auto,
        models: [ModelEntryTest] = [],
        isCoolingDown: Bool = false,
        cooldownUntil: Date? = nil,
        lastLatencyMs: Double = 0.0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.providerId = providerId
        self.baseURL = baseURL
        self.priority = priority
        self.protocol = `protocol`
        self.models = models
        self.isCoolingDown = isCoolingDown
        self.cooldownUntil = cooldownUntil
        self.lastLatencyMs = lastLatencyMs
        self.createdAt = createdAt
    }
}

extension ChannelTest: Equatable {
    static func == (lhs: ChannelTest, rhs: ChannelTest) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Mock Data

enum MockData {
    
    static func makeChannel(
        id: String = UUID().uuidString,
        name: String = "Test Channel",
        providerId: String? = "openai",
        baseURL: String = "https://api.openai.com/v1",
        priority: Int = 1,
        protocol: APIProtocolTest = .auto,
        models: [ModelEntryTest] = defaultModels,
        latency: Double = 150.0
    ) -> ChannelTest {
        ChannelTest(
            id: id,
            name: name,
            providerId: providerId,
            baseURL: baseURL,
            priority: priority,
            protocol: `protocol`,
            models: models,
            lastLatencyMs: latency
        )
    }
    
    static let defaultModels: [ModelEntryTest] = [
        ModelEntryTest(id: "m1", identifier: "gpt-4o", displayName: "GPT-4o", contextLength: 128_000, inputPricePer1M: 5.0, outputPricePer1M: 15.0, isEnabled: true),
        ModelEntryTest(id: "m2", identifier: "gpt-4o-mini", displayName: "Mini", contextLength: 128_000, inputPricePer1M: 0.5, outputPricePer1M: 1.5, isEnabled: true)
    ]
    
    static var channelList: [ChannelTest] {
        [
            makeChannel(id: "deepseek", name: "DeepSeek", baseURL: "https://api.deepseek.com", priority: 1, latency: 142),
            makeChannel(id: "openai", name: "OpenAI", baseURL: "https://api.openai.com/v1", priority: 2, latency: 389),
            makeChannel(id: "anthropic", name: "Anthropic", baseURL: "https://api.anthropic.com", priority: 3, latency: 520)
        ]
    }
}
