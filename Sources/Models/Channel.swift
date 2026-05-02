import Foundation

/// Represents an upstream API channel/provider configuration.
struct Channel: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var providerId: String?
    var apiKey: String
    var baseURL: String
    var priority: Int
    var isCoolingDown: Bool = false
    var cooldownUntil: Date?
    var lastLatencyMs: Double = 0.0

    init(
        id: UUID = UUID(),
        name: String,
        providerId: String? = nil,
        apiKey: String,
        baseURL: String,
        priority: Int = 1
    ) {
        self.id = id
        self.name = name
        self.providerId = providerId
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.priority = priority
    }
}
