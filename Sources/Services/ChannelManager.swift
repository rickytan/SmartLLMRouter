import Foundation

/// Provider template from providers.json
struct ProviderTemplate: Codable, Identifiable {
    let id: String
    let nameEn: String
    let nameZh: String
    /// Per-protocol base URL mapping (e.g. "openai" → URL, "anthropic" → URL)
    let baseUrls: [String: String]?
    /// Fallback single base URL for backward compatibility (providers.json entries without base_urls)
    let baseURL: String?
    let supportsProtocols: [String]
    let defaultModels: [ProviderModel]

    enum CodingKeys: String, CodingKey {
        case id
        case nameEn = "name_en"
        case nameZh = "name_zh"
        case baseUrls = "base_urls"
        case baseURL = "base_url"
        case supportsProtocols = "supports_protocols"
        case defaultModels = "default_models"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        nameEn = try container.decode(String.self, forKey: .nameEn)
        nameZh = try container.decode(String.self, forKey: .nameZh)
        baseUrls = try container.decodeIfPresent([String: String].self, forKey: .baseUrls)
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL)
        supportsProtocols = try container.decode([String].self, forKey: .supportsProtocols)
        defaultModels = try container.decode([ProviderModel].self, forKey: .defaultModels)
    }

    /// Get the base URL for a specific protocol. Falls back to legacy single baseURL.
    func baseURL(for `protocol`: String) -> String? {
        if let urls = baseUrls, let url = urls[`protocol`] {
            return url
        }
        // Backward compatibility: single base_url
        return baseURL
    }
}

struct ProviderModel: Codable {
    let model: String
    let `protocol`: String
    let contextLength: Int
    let inputPrice: Double
    let outputPrice: Double

    enum CodingKeys: String, CodingKey {
        case model
        case `protocol`
        case contextLength = "context_length"
        case inputPrice = "input_price"
        case outputPrice = "output_price"
    }
}

/// Manages channels with templates, model fetching, and testing capabilities
@MainActor
final class ChannelManager: ObservableObject {
    static let shared = ChannelManager()

    @Published private(set) var providerTemplates: [ProviderTemplate] = []
    @Published var isLoadingModels: Bool = false
    @Published var isSpeedTesting: Bool = false
    @Published var lastSpeedTestResults: [String: TimeInterval] = [:]

    private init() {
        loadProviderTemplates()
    }

    // MARK: - Provider Templates

    /// Load provider templates from providers.json
    private func loadProviderTemplates() {
        guard let url = Bundle.main.url(forResource: "providers", withExtension: "json") else {
            Log.error("providers.json not found in bundle")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let json = try JSONDecoder().decode(ProvidersFile.self, from: data)
            providerTemplates = json.providers
            let count = providerTemplates.count
            Log.info("Loaded \(count) provider templates")
        } catch {
            Log.error("Failed to load providers.json: \(error.localizedDescription)")
        }
    }

    /// Get provider template by ID
    func getProviderTemplate(id: String) -> ProviderTemplate? {
        providerTemplates.first { $0.id == id }
    }

    /// Create a new channel from a provider template with a specific protocol
    func createChannelFromTemplate(templateId: String, apiKey: String, protocol: APIProtocol = .auto) -> Channel? {
        guard let template = getProviderTemplate(id: templateId) else {
            Log.warn("Template not found: \(templateId)")
            return nil
        }

        // Resolve the actual protocol
        let resolvedProtocol: APIProtocol
        if `protocol` != .auto {
            resolvedProtocol = `protocol`
        } else if template.supportsProtocols.count == 1,
                  let first = template.supportsProtocols.first {
            resolvedProtocol = APIProtocol(rawValue: first.capitalized) ?? .openai
        } else {
            // Default to OpenAI if multiple protocols supported
            resolvedProtocol = .openai
        }

        let protocolKey = resolvedProtocol.rawValue.lowercased()

        // Get the correct base URL for this protocol
        guard let baseURL = template.baseURL(for: protocolKey) else {
            Log.warn("No base URL for protocol '\(protocolKey)' in template \(templateId)")
            return nil
        }

        // Filter models for this protocol
        let models = template.defaultModels
            .filter { $0.protocol == protocolKey }
            .map { pm in
                ModelEntry(
                    id: UUID().uuidString,
                    identifier: pm.model,
                    displayName: pm.model,
                    contextLength: pm.contextLength,
                    inputPricePer1M: pm.inputPrice,
                    outputPricePer1M: pm.outputPrice,
                    isEnabled: true
                )
            }

        let channel = Channel(
            id: UUID().uuidString,
            name: template.nameEn,
            providerId: template.id,
            baseURL: baseURL,
            priority: ChannelStore.shared.channels.count + 1,
            protocol: resolvedProtocol,
            models: models
        )

        do {
            try KeychainManager.shared.setAPIKey(apiKey, for: channel.id)
        } catch {
            Log.error("Failed to save API key: \(error.localizedDescription)")
            return nil
        }

        return channel
    }

    // MARK: - Fetch Models

    /// Fetch available models from an upstream API
    func fetchModels(channel: Channel) async -> [ModelEntry] {
        guard let apiKey = KeychainManager.shared.getAPIKey(for: channel.id),
              !apiKey.isEmpty
        else {
            Log.warn("No API key for channel \(channel.id)")
            return []
        }

        isLoadingModels = true

        let baseURL = channel.baseURL
        var modelsURL: URL? = if baseURL.hasSuffix("/v1") || baseURL.hasSuffix("/v1/") {
            URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/models")
        } else {
            URL(string: baseURL + "/v1/models")
        }

        guard let url = modelsURL else {
            isLoadingModels = false
            return []
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        switch channel.protocol {
        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .openai, .auto:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            let httpResponse = response as? HTTPURLResponse
            let statusCode = httpResponse?.statusCode ?? 0

            if statusCode == 200 {
                let models = parseModelsResponse(data: data, channel: channel)
                isLoadingModels = false
                Log.info("Fetched \(models.count) models for channel \(channel.name)")
                return models
            } else {
                Log.error("Failed to fetch models: status \(statusCode)")
                isLoadingModels = false
                return []
            }
        } catch {
            Log.error("Fetch models error: \(error.localizedDescription)")
            isLoadingModels = false
            return []
        }
    }

    /// Parse OpenAI-style models response
    private func parseModelsResponse(data: Data, channel _: Channel) -> [ModelEntry] {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let modelList = json["data"] as? [[String: Any]]
            else {
                Log.warn("Invalid models response format from channel")
                return []
            }

            return modelList.compactMap { modelDict -> ModelEntry? in
                guard let modelId = modelDict["id"] as? String else { return nil }

                return ModelEntry(
                    id: UUID().uuidString,
                    identifier: modelId,
                    displayName: modelId,
                    contextLength: nil,
                    inputPricePer1M: nil,
                    outputPricePer1M: nil,
                    isEnabled: true
                )
            }
        } catch {
            Log.error("Failed to parse models response: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Test Connection

    /// Result of a connection test
    struct ConnectionTestResult: Equatable {
        let success: Bool
        let errorMessage: String?

        static func success() -> ConnectionTestResult {
            ConnectionTestResult(success: true, errorMessage: nil)
        }

        static func failure(_ message: String) -> ConnectionTestResult {
            ConnectionTestResult(success: false, errorMessage: message)
        }
    }

    /// Test connection to a channel by sending a minimal request
    func testConnection(channel: Channel) async -> ConnectionTestResult {
        guard let apiKey = KeychainManager.shared.getAPIKey(for: channel.id),
              !apiKey.isEmpty
        else {
            return .failure("API Key is empty")
        }

        let testModel = channel.models.first?.identifier ?? "gpt-4o-mini"

        var testURL: URL?
        let baseURL = channel.baseURL

        if channel.protocol == .anthropic || baseURL.contains("anthropic") {
            if baseURL.hasSuffix("/v1") || baseURL.hasSuffix("/v1/") {
                testURL = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/messages")
            } else {
                testURL = URL(string: baseURL + "/v1/messages")
            }
        } else {
            if baseURL.hasSuffix("/v1") || baseURL.hasSuffix("/v1/") {
                testURL = URL(string: baseURL
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions")
            } else {
                testURL = URL(string: baseURL + "/v1/chat/completions")
            }
        }

        guard let url = testURL else {
            return .failure("Invalid URL: \(baseURL)")
        }

        let testBody: [String: Any] = [
            "model": testModel,
            "messages": [["role": "user", "content": "Hi"]],
            "max_tokens": 1,
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if channel.protocol == .anthropic {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: testBody)
        if request.httpBody == nil {
            Log.error("Failed to serialize test request body for channel \(channel.name)")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            let statusCode = httpResponse?.statusCode ?? 0

            if statusCode == 200 {
                Log.info("Connection test for \(channel.name): success")
                return .success()
            } else if statusCode == 401 {
                // Try to extract error message from response
                let errorMsg = extractErrorMessage(data) ?? "Invalid API Key"
                return .failure("❌ Invalid API Key: \(errorMsg)")
            } else if statusCode == 403 {
                return .failure("❌ Access Denied: API Key lacks permission")
            } else if statusCode == 429 {
                return .failure("❌ Rate Limited: Too many requests")
            } else if statusCode >= 500 {
                return .failure("⚠️ Server Error (HTTP \(statusCode)): Provider may be down")
            } else if statusCode > 0 {
                let errorMsg = extractErrorMessage(data)
                return .failure("❌ HTTP \(statusCode): \(errorMsg ?? "Unknown error")")
            } else {
                return .failure("❌ No response from server")
            }
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return .failure("❌ No internet connection")
            case .cannotFindHost:
                return .failure("❌ Cannot resolve host: check Base URL")
            case .cannotConnectToHost:
                return .failure("❌ Cannot connect to host: check Base URL and port")
            case .timedOut:
                return .failure("❌ Connection timed out: server may be slow or unreachable")
            case .secureConnectionFailed:
                return .failure("❌ SSL/TLS error: check HTTPS configuration")
            default:
                return .failure("❌ Network error: \(urlError.localizedDescription)")
            }
        } catch {
            return .failure("❌ \(error.localizedDescription)")
        }
    }

    /// Extract error message from API response JSON
    private func extractErrorMessage(_ data: Data) -> String? {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                    return String(text.prefix(100))
                }
                return nil
            }

            // Common error field patterns
            if let error = json["error"] as? [String: Any] {
                if let message = error["message"] as? String { return message }
                if let type = error["type"] as? String { return type }
            }
            if let message = json["message"] as? String { return message }
            if let error = json["error"] as? String { return error }
            if let msg = json["msg"] as? String { return msg }

            return nil
        } catch {
            Log.error("Failed to extract error message from response: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Speed Test

    /// Run speed test (TTFT - Time to First Token) for a channel
    func speedTest(channel: Channel) async -> TimeInterval? {
        guard let apiKey = KeychainManager.shared.getAPIKey(for: channel.id),
              !apiKey.isEmpty
        else {
            Log.warn("No API key for speed test")
            return nil
        }

        isSpeedTesting = true
        let startTime = Date()

        let testModel = channel.models.first?.identifier ?? "gpt-4o-mini"

        var testURL: URL?
        let baseURL = channel.baseURL

        if channel.protocol == .anthropic || baseURL.contains("anthropic") {
            if baseURL.hasSuffix("/v1") || baseURL.hasSuffix("/v1/") {
                testURL = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/messages")
            } else {
                testURL = URL(string: baseURL + "/v1/messages")
            }
        } else {
            if baseURL.hasSuffix("/v1") || baseURL.hasSuffix("/v1/") {
                testURL = URL(string: baseURL
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions")
            } else {
                testURL = URL(string: baseURL + "/v1/chat/completions")
            }
        }

        guard let url = testURL else {
            isSpeedTesting = false
            return nil
        }

        let testBody: [String: Any] = [
            "model": testModel,
            "messages": [["role": "user", "content": "Hi"]],
            "max_tokens": 1,
            "stream": true,
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if channel.protocol == .anthropic {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: testBody)
        if request.httpBody == nil {
            Log.error("Failed to serialize test request body for channel \(channel.name)")
        }

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            let ttft = Date().timeIntervalSince(startTime) * 1000

            lastSpeedTestResults[channel.id] = ttft

            var updatedChannel = channel
            updatedChannel.lastLatencyMs = ttft
            ChannelStore.shared.updateChannel(updatedChannel)

            isSpeedTesting = false
            Log.info("Speed test for \(channel.name): \(ttft)ms")
            return ttft
        } catch {
            Log.error("Speed test failed: \(error.localizedDescription)")
            isSpeedTesting = false
            return nil
        }
    }

    /// Run speed test for all channels
    func speedTestAllChannels() async {
        let channels = ChannelStore.shared.channels

        for channel in channels {
            if !CooldownEngine.shared.isCoolingDown(channelID: channel.id) {
                _ = await speedTest(channel: channel)
            }
        }
    }

    /// Get latency indicator emoji based on ms
    func latencyEmoji(latencyMs: TimeInterval) -> String {
        if latencyMs < 500 {
            "🟢"
        } else if latencyMs < 1000 {
            "🟡"
        } else {
            "🔴"
        }
    }

    /// Get latency description
    func latencyDescription(latencyMs: TimeInterval) -> String {
        if latencyMs < 500 {
            "< 500ms"
        } else if latencyMs < 1000 {
            "500-1000ms"
        } else {
            "> 1000ms"
        }
    }
}

// MARK: - Supporting Types

struct ProvidersFile: Codable {
    let version: String
    let providers: [ProviderTemplate]
}
