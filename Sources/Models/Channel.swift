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
    var protocolBaseURLs: [String: String]
    var priority: Int
    var `protocol`: APIProtocol
    var models: [ModelEntry]
    var isEnabled: Bool = true
    var isCoolingDown: Bool = false
    var cooldownUntil: Date?
    var lastLatencyMs: Double = 0.0
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        providerId: String? = nil,
        baseURL: String,
        protocolBaseURLs: [String: String] = [:],
        priority: Int = 1,
        protocol: APIProtocol = .auto,
        models: [ModelEntry] = [],
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.providerId = providerId
        self.baseURL = baseURL
        self.protocolBaseURLs = Self.normalizedProtocolBaseURLs(
            protocolBaseURLs,
            legacyBaseURL: baseURL,
            legacyProtocol: `protocol`
        )
        self.priority = priority
        self.protocol = `protocol`
        self.models = models
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, providerId, baseURL, protocolBaseURLs, priority
        case `protocol`, models, isEnabled
        case isCoolingDown, cooldownUntil, lastLatencyMs, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        providerId = try container.decodeIfPresent(String.self, forKey: .providerId)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        priority = try container.decode(Int.self, forKey: .priority)
        self.protocol = try container.decode(APIProtocol.self, forKey: .protocol)
        let decodedProtocolBaseURLs = try container.decodeIfPresent([String: String].self, forKey: .protocolBaseURLs) ?? [:]
        protocolBaseURLs = Self.normalizedProtocolBaseURLs(
            decodedProtocolBaseURLs,
            legacyBaseURL: baseURL,
            legacyProtocol: self.protocol
        )
        if baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let firstEndpoint = Self.firstEndpointURL(in: protocolBaseURLs) {
            baseURL = firstEndpoint
        }
        models = try container.decode([ModelEntry].self, forKey: .models)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        isCoolingDown = try container.decodeIfPresent(Bool.self, forKey: .isCoolingDown) ?? false
        cooldownUntil = try container.decodeIfPresent(Date.self, forKey: .cooldownUntil)
        lastLatencyMs = try container.decodeIfPresent(Double.self, forKey: .lastLatencyMs) ?? 0.0
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    // MARK: - Equatable

    static func == (lhs: Channel, rhs: Channel) -> Bool {
        lhs.id == rhs.id
    }
}

extension Channel {
    static let openAIEndpointKey = "openai"
    static let anthropicEndpointKey = "anthropic"

    var displayEndpointSummary: String {
        let endpoints = endpointDisplayPairs()
        guard !endpoints.isEmpty else { return baseURL }
        return endpoints
            .map { "\($0.label): \($0.url)" }
            .joined(separator: "  ")
    }

    func baseURL(for apiProtocol: APIProtocol) -> String? {
        switch apiProtocol {
        case .openai:
            return endpointURL(forKey: Self.openAIEndpointKey) ?? legacyBaseURLFallback(for: .openai)
        case .anthropic:
            return endpointURL(forKey: Self.anthropicEndpointKey) ?? legacyBaseURLFallback(for: .anthropic)
        case .auto:
            return endpointURL(forKey: Self.openAIEndpointKey)
                ?? endpointURL(forKey: Self.anthropicEndpointKey)
                ?? nonEmpty(baseURL)
        }
    }

    func baseURL(for requestProtocol: RequestForwarder.RequestProtocol) -> String? {
        switch requestProtocol {
        case .openai:
            return baseURL(for: APIProtocol.openai)
        case .anthropic:
            return baseURL(for: APIProtocol.anthropic)
        case .unknown:
            return baseURL(for: APIProtocol.auto)
        }
    }

    mutating func setBaseURL(_ url: String, for apiProtocol: APIProtocol) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        switch apiProtocol {
        case .openai:
            setEndpointURL(trimmed, forKey: Self.openAIEndpointKey)
        case .anthropic:
            setEndpointURL(trimmed, forKey: Self.anthropicEndpointKey)
        case .auto:
            baseURL = trimmed
        }

        if nonEmpty(baseURL) == nil || self.protocol == apiProtocol {
            baseURL = trimmed
        }
    }

    func endpointSignatures() -> Set<String> {
        var signatures = Set<String>()
        for (key, url) in normalizedEndpointMap() {
            if let normalizedURL = Self.normalizedEndpointURL(url) {
                signatures.insert("\(key)|\(normalizedURL)")
            }
        }

        if signatures.isEmpty, let normalizedURL = Self.normalizedEndpointURL(baseURL) {
            let keys: [String] = switch self.protocol {
            case .openai:
                [Self.openAIEndpointKey]
            case .anthropic:
                [Self.anthropicEndpointKey]
            case .auto:
                [Self.openAIEndpointKey, Self.anthropicEndpointKey]
            }
            keys.forEach { signatures.insert("\($0)|\(normalizedURL)") }
        }

        return signatures
    }

    func hasOverlappingEndpoint(with other: Channel) -> Bool {
        !endpointSignatures().isDisjoint(with: other.endpointSignatures())
    }

    static func normalizedEndpointURL(_ url: String) -> String? {
        var trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed.isEmpty ? nil : trimmed
    }

    static func endpointKey(for apiProtocol: APIProtocol) -> String? {
        switch apiProtocol {
        case .openai:
            openAIEndpointKey
        case .anthropic:
            anthropicEndpointKey
        case .auto:
            nil
        }
    }

    private func endpointDisplayPairs() -> [(label: String, url: String)] {
        var pairs: [(String, String)] = []
        if let url = endpointURL(forKey: Self.openAIEndpointKey) {
            pairs.append(("OpenAI", url))
        }
        if let url = endpointURL(forKey: Self.anthropicEndpointKey),
           url != pairs.first?.1 {
            pairs.append(("Anthropic", url))
        }
        return pairs
    }

    private func normalizedEndpointMap() -> [String: String] {
        Self.normalizedProtocolBaseURLs(protocolBaseURLs, legacyBaseURL: baseURL, legacyProtocol: self.protocol)
    }

    private func endpointURL(forKey key: String) -> String? {
        nonEmpty(protocolBaseURLs[key])
    }

    private mutating func setEndpointURL(_ url: String, forKey key: String) {
        if url.isEmpty {
            protocolBaseURLs.removeValue(forKey: key)
        } else {
            protocolBaseURLs[key] = url
        }
    }

    private func legacyBaseURLFallback(for apiProtocol: APIProtocol) -> String? {
        guard protocolBaseURLs.isEmpty, let fallback = nonEmpty(baseURL) else { return nil }
        if self.protocol == apiProtocol || self.protocol == .auto {
            return fallback
        }
        return nil
    }

    private func nonEmpty(_ url: String?) -> String? {
        guard let trimmed = url?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func normalizedProtocolBaseURLs(
        _ urls: [String: String],
        legacyBaseURL: String,
        legacyProtocol: APIProtocol
    ) -> [String: String] {
        var normalized: [String: String] = [:]
        for (key, value) in urls {
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard [openAIEndpointKey, anthropicEndpointKey].contains(normalizedKey) else { continue }
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedValue.isEmpty else { continue }
            normalized[normalizedKey] = trimmedValue
        }

        let legacy = legacyBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !legacy.isEmpty {
            switch legacyProtocol {
            case .openai:
                normalized[openAIEndpointKey, default: legacy] = normalized[openAIEndpointKey] ?? legacy
            case .anthropic:
                normalized[anthropicEndpointKey, default: legacy] = normalized[anthropicEndpointKey] ?? legacy
            case .auto:
                if normalized.isEmpty {
                    normalized[openAIEndpointKey] = legacy
                    normalized[anthropicEndpointKey] = legacy
                }
            }
        }

        return normalized
    }

    private static func firstEndpointURL(in urls: [String: String]) -> String? {
        urls[openAIEndpointKey] ?? urls[anthropicEndpointKey] ?? urls.values.first
    }
}
