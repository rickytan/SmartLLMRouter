import Foundation

@MainActor
final class ChannelStore: ObservableObject {
    /// Default `UserDefaults` key for the channel-data cache.
    static let userDefaultsKey = "smartllm_channels"
    static let activeChannelDefaultsKey = "smartllm_active_channel"

    /// Production singleton. Tests must NOT use this directly — they should
    /// construct their own `ChannelStore` with an in-memory `UserDefaults`
    /// suite and a temporary file URL (or `nil` for `fileURL` to skip disk
    /// entirely), then call `setSharedForTesting` to install it.
    static let productionShared = ChannelStore()

    /// Test seam. Replaces the shared instance for the duration of a test
    /// process. Production code must not call this.
    static func setSharedForTesting(_ store: ChannelStore?) {
        _sharedOverride = store
    }

    private static var _sharedOverride: ChannelStore?

    /// The currently-active shared instance. Returns the test override if
    /// set, otherwise the production singleton. All production code paths
    /// should use this so test isolation works.
    static var shared: ChannelStore {
        _sharedOverride ?? productionShared
    }

    @Published var channels: [Channel] = []
    @Published var activeChannelID: String?

    var enabledChannels: [Channel] {
        channels.filter(\.isEnabled)
    }

    var activeChannel: Channel? {
        guard let id = activeChannelID else { return enabledChannels.first }
        return channels.first { $0.id == id && $0.isEnabled } ?? enabledChannels.first
    }

    let defaults: UserDefaults
    let persistence: ChannelsPersistence
    private let runtimeState: RouterRuntimeState
    var invalidateModelCache: (() -> Void)?
    var validateModelSelection: (() -> Void)?

    /// Designated initializer.
    /// - Parameters:
    ///   - defaults: `UserDefaults` instance to use as a write-through cache.
    ///     Defaults to `.standard` for production; tests should inject a
    ///     dedicated suite so they cannot pollute real user data.
    ///   - persistence: File-backed storage. Defaults to a real on-disk
    ///     instance; tests can inject a temporary file URL or `nil` (no file).
    init(
        defaults: UserDefaults = .standard,
        persistence: ChannelsPersistence = ChannelsPersistence(),
        runtimeState: RouterRuntimeState = .shared
    ) {
        self.defaults = defaults
        self.persistence = persistence
        self.runtimeState = runtimeState
        loadChannels()
    }

    func saveChannels() {
        let channelsSnapshot = channels
        let activeSnapshot = activeChannelID
        runtimeState.updateChannels(channelsSnapshot, activeChannelID: activeSnapshot)

        // 1. File is the source of truth — write it first. If it fails we
        //    still try the UserDefaults cache so the data is at least in
        //    memory next launch under the same bundle ID.
        let fileOK = persistence.save(
            channels: channelsSnapshot,
            activeChannelID: activeSnapshot
        )
        if !fileOK {
            Log.warn("[ChannelStore] File persistence failed; falling back to UserDefaults cache only")
        }

        // 2. UserDefaults cache (for fast reads; not durable across bundle
        //    ID changes).
        do {
            let data = try JSONEncoder().encode(channelsSnapshot)
            defaults.set(data, forKey: Self.userDefaultsKey)
            defaults.set(activeSnapshot, forKey: Self.activeChannelDefaultsKey)
        } catch {
            Log.error("Failed to encode channels for UserDefaults cache: \(error.localizedDescription)")
        }
    }

    func loadChannels() {
        // 1. File-backed storage (source of truth, independent of bundle ID).
        switch persistence.load() {
        case .loaded(let decoded, let activeID):
            channels = decoded
            activeChannelID = activeID
            runtimeState.updateChannels(decoded, activeChannelID: activeID)
            Log.info("[ChannelStore] Loaded \(decoded.count) channels from file")
            return
        case .corrupted(let reason):
            Log.warn("[ChannelStore] File corrupted (\(reason)) — trying UserDefaults")
        case .empty:
            break
        }

        // 2. Current UserDefaults (cache, scoped to bundle ID).
        if loadFromDefaults(defaults) { return }

        runtimeState.updateChannels(channels, activeChannelID: activeChannelID)
        Log.info("[ChannelStore] No channel data found in any source")
    }

    /// Attempt to decode from a specific `UserDefaults` instance.
    /// - Returns: `true` if data was loaded.
    @discardableResult
    private func loadFromDefaults(_ source: UserDefaults) -> Bool {
        guard let data = source.data(forKey: Self.userDefaultsKey),
              let decoded = try? JSONDecoder().decode([Channel].self, from: data)
        else { return false }
        channels = decoded
        activeChannelID = source.string(forKey: Self.activeChannelDefaultsKey)
        runtimeState.updateChannels(channels, activeChannelID: activeChannelID)
        return true
    }

    func addChannel(_ channel: Channel) {
        // Prevent adding duplicate base URLs
        if channels.contains(where: { $0.baseURL.lowercased() == channel.baseURL.lowercased() }) {
            Log.info("[ChannelStore] Skipping duplicate channel: \\(channel.baseURL)")
            return
        }

        channels.append(channel)
        if activeChannelID == nil, channel.isEnabled { activeChannelID = channel.id }
        invalidateModelCache?()
        saveChannels()
    }

    func removeChannel(id: String) {
        channels.removeAll { $0.id == id }
        if activeChannelID == id { activeChannelID = enabledChannels.first?.id }
        invalidateModelCache?()
        saveChannels()
    }

    func updateChannel(_ channel: Channel) {
        if let index = channels.firstIndex(where: { $0.id == channel.id }) {
            let previousChannel = channels[index]
            channels[index] = channel
            if previousChannel.isEnabled != channel.isEnabled || previousChannel.models != channel.models {
                invalidateModelCache?()
            }
            saveChannels()
        }
    }

    func setActiveChannel(id: String) {
        guard channels.contains(where: { $0.id == id && $0.isEnabled }) else {
            return
        }
        activeChannelID = id
        saveChannels()
    }

    func setChannelEnabled(id: String, isEnabled: Bool) {
        guard let index = channels.firstIndex(where: { $0.id == id }) else {
            return
        }

        channels[index].isEnabled = isEnabled
        if !isEnabled, activeChannelID == id {
            activeChannelID = enabledChannels.first?.id
        } else if isEnabled, activeChannelID == nil {
            activeChannelID = id
        }
        invalidateModelCache?()
        validateModelSelection?()
        saveChannels()
    }

    func moveChannel(from source: IndexSet, to destination: Int) {
        channels.move(fromOffsets: source, toOffset: destination)
        // Update priority based on new order
        for index in channels.indices {
            channels[index].priority = index + 1
        }
        saveChannels()
    }
}
