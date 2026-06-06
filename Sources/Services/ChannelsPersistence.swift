import Foundation

/// File-backed persistence for channel configuration.
///
/// Channel data is critical — losing it means the user must re-add all their
/// API keys. We persist to a JSON file in Application Support (independent of
/// bundle ID, stable across rebuilds) and use UserDefaults only as a write-through
/// cache for fast reads.
///
/// File location: `~/Library/Application Support/SmartLLMRouter/channels.json`
///
/// Both the production path and a custom URL can be supplied — tests inject a
/// temporary file URL so they never touch real disk.
final class ChannelsPersistence {

    static let currentSchemaVersion = 1

    struct StorageFile: Codable {
        let schemaVersion: Int
        let channels: [Channel]
        let activeChannelID: String?
    }

    enum LoadResult {
        case loaded([Channel], activeID: String?)
        case empty
        case corrupted(reason: String)
    }

    let fileURL: URL?

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// - Parameter fileURL: Override the storage location. `nil` disables file
    ///   persistence entirely (used when persistence is impossible, e.g. in
    ///   some test setups). Default: `~/Library/Application Support/SmartLLMRouter/channels.json`.
    init(fileURL: URL? = ChannelsPersistence.defaultFileURL(),
         fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager

        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - File path

    static func defaultFileURL() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport
            .appendingPathComponent("SmartLLMRouter", isDirectory: true)
            .appendingPathComponent("channels.json", isDirectory: false)
    }

    // MARK: - Load

    /// Load channels from the persistence file.
    /// - Returns: `.loaded` on success, `.empty` if the file doesn't exist,
    ///   `.corrupted` if the file exists but can't be decoded (caller should
    ///   fall back to UserDefaults or other source).
    func load() -> LoadResult {
        guard let url = fileURL else { return .empty }
        guard fileManager.fileExists(atPath: url.path) else { return .empty }

        do {
            let data = try Data(contentsOf: url)

            // Try the versioned schema first
            if let file = try? decoder.decode(StorageFile.self, from: data) {
                return .loaded(file.channels, activeID: file.activeChannelID)
            }

            // Fall back to a raw [Channel] array (legacy / unversioned export)
            if let channels = try? decoder.decode([Channel].self, from: data) {
                return .loaded(channels, activeID: nil)
            }

            return .corrupted(reason: "Decode failed for both StorageFile and [Channel]")
        } catch {
            return .corrupted(reason: error.localizedDescription)
        }
    }

    // MARK: - Save

    /// Atomically write channels to the persistence file.
    /// - Returns: `true` on success, `false` if the write failed (e.g. disk
    ///   full, permission denied, no fileURL configured). The caller should
    ///   log the failure but not crash — UserDefaults is still updated.
    @discardableResult
    func save(channels: [Channel], activeChannelID: String?) -> Bool {
        guard let url = fileURL else { return false }

        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)

            let payload = StorageFile(
                schemaVersion: ChannelsPersistence.currentSchemaVersion,
                channels: channels,
                activeChannelID: activeChannelID
            )
            let data = try encoder.encode(payload)

            // Data.write with .atomic is implemented as write-to-temp +
            // rename, so a crash mid-write won't corrupt the file. macOS
            // guarantees the rename is atomic on the same volume.
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            Log.warn("[ChannelsPersistence] save failed: \(error.localizedDescription) (url: \(fileURL?.path ?? "nil"))")
            return false
        }
    }

    // MARK: - Delete

    /// Remove the persistence file. Used during tests and as part of "reset
    /// all data" UI flows. Safe to call when the file doesn't exist.
    func delete() {
        guard let url = fileURL else { return }
        try? fileManager.removeItem(at: url)
    }
}
