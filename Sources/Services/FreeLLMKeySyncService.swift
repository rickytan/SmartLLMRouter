import Foundation

@MainActor
final class FreeLLMKeySyncService: ObservableObject {
    struct Entry: Equatable {
        let apiKey: String
        let model: String
        let status: String
        let expiresAt: Date?
    }

    struct Snapshot: Equatable {
        let entries: [Entry]

        var apiKeys: [String] {
            unique(entries.map(\.apiKey))
        }

        var modelIdentifiers: [String] {
            unique(entries.flatMap { modelAliases(for: $0.model) })
        }

        private static func unique(_ values: [String]) -> [String] {
            var seen = Set<String>()
            return values.compactMap { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !seen.contains(trimmed) else { return nil }
                seen.insert(trimmed)
                return trimmed
            }
        }

        private static func modelAliases(for model: String) -> [String] {
            let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "`"))
            guard !trimmed.isEmpty else { return [] }

            if let slash = trimmed.lastIndex(of: "/") {
                let suffix = String(trimmed[trimmed.index(after: slash)...])
                return [trimmed, suffix]
            }
            return [trimmed]
        }
    }

    struct SyncResult: Equatable {
        let channelID: String
        let keyCount: Int
        let modelCount: Int
        let addedChannel: Bool
    }

    enum SyncError: LocalizedError {
        case invalidSource
        case invalidResponse
        case noUsableKeys

        var errorDescription: String? {
            switch self {
            case .invalidSource:
                L10n.AddChannel.freeKeysInvalidSource
            case .invalidResponse:
                L10n.AddChannel.freeKeysInvalidResponse
            case .noUsableKeys:
                L10n.AddChannel.freeKeysNoUsableKeys
            }
        }
    }

    static let providerID = "free-llm-api-keys"
    static let channelName = "Free LLM API Keys"
    static let baseURL = "https://aiapiv2.pekpik.com/v1"
    static let repositoryURL = URL(string: "https://github.com/alistaitsacle/free-llm-api-keys")!
    static let sourceURL = URL(string: "https://raw.githubusercontent.com/alistaitsacle/free-llm-api-keys/main/README.md")!

    private static let autoSyncEnabledKey = "freeLLMKeys.autoSyncEnabled"
    private static let lastSyncAtKey = "freeLLMKeys.lastSyncAt"
    private static let syncInterval: TimeInterval = 24 * 60 * 60

    @Published var isSyncing = false
    @Published var autoSyncEnabled: Bool {
        didSet {
            defaults.set(autoSyncEnabled, forKey: Self.autoSyncEnabledKey)
            configureTimer()
            if autoSyncEnabled {
                Task { await syncIfNeeded() }
            }
        }
    }
    @Published private(set) var lastSyncAt: Date?

    private let channelServices: ChannelServices
    private let defaults: UserDefaults
    private let sourceURL: URL
    private var timer: Timer?

    init(
        channelServices: ChannelServices,
        defaults: UserDefaults = .standard,
        sourceURL: URL = FreeLLMKeySyncService.sourceURL
    ) {
        self.channelServices = channelServices
        self.defaults = defaults
        self.sourceURL = sourceURL
        autoSyncEnabled = defaults.bool(forKey: Self.autoSyncEnabledKey)
        lastSyncAt = defaults.object(forKey: Self.lastSyncAtKey) as? Date
    }

    func start() {
        configureTimer()
        if autoSyncEnabled {
            Task { await syncIfNeeded() }
        }
    }

    func syncIfNeeded() async {
        guard autoSyncEnabled else { return }
        if let lastSyncAt, Date().timeIntervalSince(lastSyncAt) < Self.syncInterval {
            return
        }

        do {
            _ = try await syncNow()
        } catch {
            Log.warn("[FreeLLMKeySync] Daily sync failed: \(error.localizedDescription)")
        }
    }

    func syncNow() async throws -> SyncResult {
        guard sourceURL.scheme == "https" else {
            throw SyncError.invalidSource
        }

        isSyncing = true
        defer { isSyncing = false }

        var request = URLRequest(url: sourceURL)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let markdown = String(data: data, encoding: .utf8) else {
            throw SyncError.invalidResponse
        }

        let snapshot = Self.parseREADME(markdown, referenceDate: Date())
        let result = try apply(snapshot: snapshot)
        markSynced()
        return result
    }

    func apply(snapshot: Snapshot) throws -> SyncResult {
        let apiKeys = snapshot.apiKeys
        guard !apiKeys.isEmpty else {
            throw SyncError.noUsableKeys
        }

        let models = snapshot.modelIdentifiers.map { identifier in
            ModelEntry(
                id: UUID().uuidString,
                identifier: identifier,
                displayName: identifier,
                isEnabled: true,
                inputTypes: ["text"]
            )
        }

        if let existing = channelServices.channels.first(where: {
            $0.providerId == Self.providerID || $0.baseURL.lowercased() == Self.baseURL.lowercased()
        }) {
            var updated = existing
            updated.name = Self.channelName
            updated.providerId = Self.providerID
            updated.baseURL = Self.baseURL
            updated.protocol = .openai
            updated.models = models
            try channelServices.setAPIKeys(apiKeys, for: updated.id)
            channelServices.updateChannel(updated)
            return SyncResult(channelID: updated.id, keyCount: apiKeys.count, modelCount: models.count, addedChannel: false)
        }

        let channel = Channel(
            id: UUID().uuidString,
            name: Self.channelName,
            providerId: Self.providerID,
            baseURL: Self.baseURL,
            priority: channelServices.nextPriority,
            protocol: .openai,
            models: models
        )
        try channelServices.setAPIKeys(apiKeys, for: channel.id)
        channelServices.addChannel(channel)
        return SyncResult(channelID: channel.id, keyCount: apiKeys.count, modelCount: models.count, addedChannel: true)
    }

    nonisolated static func parseREADME(_ markdown: String, referenceDate: Date = Date()) -> Snapshot {
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let calendar = Calendar(identifier: .gregorian)
        let referenceStart = calendar.startOfDay(for: referenceDate)
        let lines = markdown.components(separatedBy: .newlines)
        let entries = lines.compactMap { line -> Entry? in
            guard line.contains("|"),
                  line.contains("sk-"),
                  !line.localizedCaseInsensitiveContains("---") else {
                return nil
            }

            let columns = line
                .split(separator: "|", omittingEmptySubsequences: false)
                .dropFirst()
                .dropLast()
                .map { cleanMarkdownCell(String($0)) }

            guard columns.count >= 6 else { return nil }
            let apiKey = columns[0]
            let model = columns[1]
            let status = columns[2]
            let expiresAt = dateFormatter.date(from: columns[5])

            guard apiKey.hasPrefix("sk-"),
                  !model.isEmpty,
                  !status.localizedCaseInsensitiveContains("expired") else {
                return nil
            }

            if let expiresAt, expiresAt < referenceStart {
                return nil
            }

            return Entry(apiKey: apiKey, model: model, status: status, expiresAt: expiresAt)
        }

        return Snapshot(entries: entries)
    }

    nonisolated private static func cleanMarkdownCell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func markSynced() {
        let now = Date()
        lastSyncAt = now
        defaults.set(now, forKey: Self.lastSyncAtKey)
    }

    private func configureTimer() {
        timer?.invalidate()
        timer = nil

        guard autoSyncEnabled else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.syncIfNeeded()
            }
        }
    }
}
