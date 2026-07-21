import Foundation

struct ModelsDevProviderCatalogService {
    private static let cacheKey = "modelsDev.providerTemplates.cache.v1"
    private static let lastAutoRefreshAttemptKey = "modelsDev.providerTemplates.lastAutoRefreshAttempt.v1"

    var endpoint: URL
    var session: URLSession
    var userDefaults: UserDefaults

    init(
        endpoint: URL = URL(string: "https://models.dev/api.json")!,
        session: URLSession = .shared,
        userDefaults: UserDefaults = .standard
    ) {
        self.endpoint = endpoint
        self.session = session
        self.userDefaults = userDefaults
    }

    func fetchTemplates() async throws -> [ProviderTemplate] {
        let (data, response) = try await session.data(from: endpoint)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try Self.parseTemplates(from: data)
    }

    func loadCachedTemplates() -> [ProviderTemplate]? {
        guard let data = userDefaults.data(forKey: Self.cacheKey) else { return nil }
        return try? JSONDecoder().decode([ProviderTemplate].self, from: data)
    }

    func cacheTemplates(_ templates: [ProviderTemplate]) {
        guard let data = try? JSONEncoder().encode(templates) else { return }
        userDefaults.set(data, forKey: Self.cacheKey)
    }

    func shouldAutoRefreshTemplates(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let lastAttempt = userDefaults.object(forKey: Self.lastAutoRefreshAttemptKey) as? Date else {
            return true
        }
        return !calendar.isDate(lastAttempt, inSameDayAs: now)
    }

    func markAutoRefreshAttempted(now: Date = Date()) {
        userDefaults.set(now, forKey: Self.lastAutoRefreshAttemptKey)
    }

    static func parseTemplates(from data: Data) throws -> [ProviderTemplate] {
        let providers = try JSONDecoder().decode([String: ModelsDevProvider].self, from: data)
        let templates = providers.values.compactMap(makeTemplate(from:))
        return deduplicatedTemplates(templates).sorted {
            $0.nameEn.localizedCaseInsensitiveCompare($1.nameEn) == .orderedAscending
        }
    }

    private static func makeTemplate(from provider: ModelsDevProvider) -> ProviderTemplate? {
        let endpoints = endpointMap(for: provider)
        guard !endpoints.isEmpty else { return nil }

        let protocols = endpoints.keys.sorted()
        let models = provider.models.values
            .sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
            .flatMap { model in
                protocols.map { apiProtocol in
                    ProviderModel(
                        model: model.id,
                        protocol: apiProtocol,
                        contextLength: model.limit?.context ?? 0,
                        inputPrice: model.cost?.input ?? 0,
                        outputPrice: model.cost?.output ?? 0,
                        inputTypes: normalizedInputTypes(model.modalities?.input)
                    )
                }
            }

        return ProviderTemplate(
            id: provider.id,
            nameEn: provider.name,
            nameZh: provider.name,
            baseUrls: endpoints,
            baseURL: endpoints[Channel.openAIEndpointKey] ?? endpoints[Channel.anthropicEndpointKey],
            supportsProtocols: protocols,
            defaultModels: models
        )
    }

    private static func endpointMap(for provider: ModelsDevProvider) -> [String: String] {
        let trimmedAPI = provider.api?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let api = trimmedAPI, !api.isEmpty, !api.contains("${") else { return [:] }

        let npm = provider.npm?.lowercased() ?? ""
        if npm.contains("anthropic") {
            return [Channel.anthropicEndpointKey: api]
        }
        if npm.contains("openai") || npm.contains("openai-compatible") {
            return [Channel.openAIEndpointKey: api]
        }
        return [:]
    }

    private static func normalizedInputTypes(_ input: [String]?) -> [String] {
        let allowed = Set(InputType.allCases.map(\.rawValue))
        let values = (input ?? ["text"]).filter { allowed.contains($0) }
        var seen = Set<String>()
        let uniqueValues = values.filter { seen.insert($0).inserted }
        return uniqueValues.isEmpty ? ["text"] : uniqueValues
    }

    private static func deduplicatedTemplates(_ templates: [ProviderTemplate]) -> [ProviderTemplate] {
        var result: [ProviderTemplate] = []
        for template in templates.sorted(by: shouldSortBeforeForDeduplication) {
            guard let index = result.firstIndex(where: { sharesEndpoint($0, template) }) else {
                result.append(template)
                continue
            }
            result[index] = mergedTemplate(preferred: result[index], duplicate: template)
        }
        return result
    }

    private static func shouldSortBeforeForDeduplication(_ lhs: ProviderTemplate, _ rhs: ProviderTemplate) -> Bool {
        let lhsScore = duplicatePenalty(lhs)
        let rhsScore = duplicatePenalty(rhs)
        if lhsScore != rhsScore { return lhsScore < rhsScore }
        return lhs.nameEn.localizedCaseInsensitiveCompare(rhs.nameEn) == .orderedAscending
    }

    private static func duplicatePenalty(_ template: ProviderTemplate) -> Int {
        let searchable = "\(template.id) \(template.nameEn)".lowercased()
        var penalty = 0
        if searchable.contains("coding plan") || searchable.contains("coding-plan") { penalty += 10 }
        if searchable.contains("token plan") || searchable.contains("token-plan") { penalty += 10 }
        return penalty
    }

    private static func sharesEndpoint(_ lhs: ProviderTemplate, _ rhs: ProviderTemplate) -> Bool {
        !Set(endpointKeys(for: lhs)).isDisjoint(with: endpointKeys(for: rhs))
    }

    private static func endpointKeys(for template: ProviderTemplate) -> [String] {
        template.protocolBaseURLMap().compactMap { proto, url in
            let normalizedURL = url
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .lowercased()
            guard !normalizedURL.isEmpty else { return nil }
            return "\(proto.lowercased())|\(normalizedURL)"
        }
    }

    private static func mergedTemplate(preferred: ProviderTemplate, duplicate: ProviderTemplate) -> ProviderTemplate {
        var endpoints = preferred.protocolBaseURLMap()
        for (key, value) in duplicate.protocolBaseURLMap() where endpoints[key] == nil {
            endpoints[key] = value
        }

        return ProviderTemplate(
            id: preferred.id,
            nameEn: preferred.nameEn,
            nameZh: preferred.nameZh,
            baseUrls: endpoints.isEmpty ? preferred.baseUrls : endpoints,
            baseURL: preferred.baseURL ?? duplicate.baseURL,
            supportsProtocols: mergedProtocols(preferred.supportsProtocols, duplicate.supportsProtocols),
            defaultModels: mergedModels(preferred.defaultModels, duplicate.defaultModels)
        )
    }

    private static func mergedProtocols(_ primary: [String], _ secondary: [String]) -> [String] {
        var seen = Set<String>()
        return (primary + secondary).filter { seen.insert($0).inserted }
    }

    private static func mergedModels(_ primary: [ProviderModel], _ secondary: [ProviderModel]) -> [ProviderModel] {
        var seen = Set<String>()
        return (primary + secondary)
            .filter { seen.insert("\($0.protocol)|\($0.model)").inserted }
            .sorted {
                if $0.protocol != $1.protocol { return $0.protocol < $1.protocol }
                return $0.model.localizedCaseInsensitiveCompare($1.model) == .orderedAscending
            }
    }
}

private struct ModelsDevProvider: Decodable {
    let id: String
    let name: String
    let npm: String?
    let api: String?
    let models: [String: ModelsDevModel]
}

private struct ModelsDevModel: Decodable {
    let id: String
    let limit: ModelsDevLimit?
    let cost: ModelsDevCost?
    let modalities: ModelsDevModalities?
}

private struct ModelsDevLimit: Decodable {
    let context: Int?
}

private struct ModelsDevCost: Decodable {
    let input: Double?
    let output: Double?
}

private struct ModelsDevModalities: Decodable {
    let input: [String]?
}
