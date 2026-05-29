import Foundation

/// Supported input types for models
enum InputType: String, Codable, CaseIterable {
    case text = "text"
    case image = "image"
    case video = "video"
    case audio = "audio"
}

/// Represents a model entry within a channel
struct ModelEntry: Identifiable, Codable, Equatable {
    let id: String
    var identifier: String
    var displayName: String
    var contextLength: Int?
    var inputPricePer1M: Double?
    var outputPricePer1M: Double?
    var isEnabled: Bool
    var inputTypes: [String]

    init(
        id: String,
        identifier: String,
        displayName: String,
        contextLength: Int? = nil,
        inputPricePer1M: Double? = nil,
        outputPricePer1M: Double? = nil,
        isEnabled: Bool = true,
        inputTypes: [String] = ["text"]
    ) {
        self.id = id
        self.identifier = identifier
        self.displayName = displayName
        self.contextLength = contextLength
        self.inputPricePer1M = inputPricePer1M
        self.outputPricePer1M = outputPricePer1M
        self.isEnabled = isEnabled
        self.inputTypes = inputTypes
    }

    /// Backward compatibility: decode old supportsVision field
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        identifier = try container.decode(String.self, forKey: .identifier)
        displayName = try container.decode(String.self, forKey: .displayName)
        contextLength = try container.decodeIfPresent(Int.self, forKey: .contextLength)
        inputPricePer1M = try container.decodeIfPresent(Double.self, forKey: .inputPricePer1M)
        outputPricePer1M = try container.decodeIfPresent(Double.self, forKey: .outputPricePer1M)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true

        // Try new format first, fall back to old supportsVision
        if let types = try container.decodeIfPresent([String].self, forKey: .inputTypes) {
            inputTypes = types
        } else if let supportsVision = try container.decodeIfPresent(Bool.self, forKey: .supportsVision) {
            inputTypes = supportsVision ? ["text", "image"] : ["text"]
        } else {
            inputTypes = ["text"]
        }
    }

    /// Custom coding keys to handle backward compatibility
    enum CodingKeys: String, CodingKey {
        case id, identifier, displayName, contextLength
        case inputPricePer1M, outputPricePer1M, isEnabled
        case inputTypes, supportsVision
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(identifier, forKey: .identifier)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(contextLength, forKey: .contextLength)
        try container.encodeIfPresent(inputPricePer1M, forKey: .inputPricePer1M)
        try container.encodeIfPresent(outputPricePer1M, forKey: .outputPricePer1M)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(inputTypes, forKey: .inputTypes)
    }

    /// Check if model supports a specific input type
    func supports(_ type: InputType) -> Bool {
        inputTypes.contains(type.rawValue)
    }

    /// Check if model supports image input (backward compatibility)
    var supportsVision: Bool {
        supports(.image)
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
