import Foundation

/// Represents a model entry within a channel
struct ModelEntry: Identifiable, Codable, Equatable {
    let id: String
    var identifier: String
    var displayName: String
    var contextLength: Int?
    var inputPricePer1M: Double?
    var outputPricePer1M: Double?
    var isEnabled: Bool
    var supportsVision: Bool = false

    init(
        id: String,
        identifier: String,
        displayName: String,
        contextLength: Int? = nil,
        inputPricePer1M: Double? = nil,
        outputPricePer1M: Double? = nil,
        isEnabled: Bool = true,
        supportsVision: Bool = false
    ) {
        self.id = id
        self.identifier = identifier
        self.displayName = displayName
        self.contextLength = contextLength
        self.inputPricePer1M = inputPricePer1M
        self.outputPricePer1M = outputPricePer1M
        self.isEnabled = isEnabled
    }
}

/// Supported API protocols
enum APIProtocol: String, Codable, CaseIterable {
    case openai = "OpenAI"
    case anthropic = "Anthropic"
    case auto = "Auto"
}

/// Represents an upstream API channel/provider configuration.
struct Channel: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var providerId: String?
    var baseURL: String
    var priority: Int
    var `protocol`: APIProtocol
    var models: [ModelEntry]
    var isCoolingDown: Bool = false
    var cooldownUntil: Date?
    var lastLatencyMs: Double = 0.0
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        providerId: String? = nil,
        baseURL: String,
        priority: Int = 1,
        protocol: APIProtocol = .auto,
        models: [ModelEntry] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.providerId = providerId
        self.baseURL = baseURL
        self.priority = priority
        self.protocol = `protocol`
        self.models = models
        self.createdAt = createdAt
    }

    // MARK: - Equatable

    static func == (lhs: Channel, rhs: Channel) -> Bool {
        lhs.id == rhs.id
    }
}
