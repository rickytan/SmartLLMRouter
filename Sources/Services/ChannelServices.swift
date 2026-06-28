import Foundation

/// Dependency boundary for channel-related services.
///
/// This keeps channel storage, API keys, and cooldown state behind one
/// domain-level entry point instead of scattering direct singleton access
/// through model fetching, switching, and connection testing code.
@MainActor
final class ChannelServices {
    let store: ChannelStore
    let keychain: KeychainManager
    let cooldownEngine: CooldownEngine

    init(
        store: ChannelStore,
        keychain: KeychainManager,
        cooldownEngine: CooldownEngine? = nil
    ) {
        self.store = store
        self.keychain = keychain
        self.cooldownEngine = cooldownEngine ?? CooldownEngine(channelStore: store)
    }

    var channels: [Channel] {
        store.channels
    }

    var enabledChannels: [Channel] {
        store.enabledChannels
    }

    var activeChannel: Channel? {
        store.activeChannel
    }

    var nextPriority: Int {
        store.channels.count + 1
    }

    func apiKey(for channelID: String) -> String? {
        keychain.getAPIKey(for: channelID)
    }

    func apiKeys(for channelID: String) -> [String] {
        keychain.getAPIKeys(for: channelID)
    }

    func setAPIKey(_ apiKey: String, for channelID: String) throws {
        try keychain.setAPIKey(apiKey, for: channelID)
    }

    func setAPIKeys(_ apiKeys: [String], for channelID: String) throws {
        try keychain.setAPIKeys(apiKeys, for: channelID)
    }

    func removeAPIKey(for channelID: String) throws {
        try keychain.removeAPIKey(for: channelID)
    }

    func addChannel(_ channel: Channel) {
        store.addChannel(channel)
    }

    func updateChannel(_ channel: Channel) {
        store.updateChannel(channel)
    }

    func updateModels(_ models: [ModelEntry], for channelID: String) {
        guard let index = store.channels.firstIndex(where: { $0.id == channelID }) else {
            return
        }
        store.channels[index].models = models
    }

    func saveChannels() {
        store.saveChannels()
    }

    func isCoolingDown(channelID: String) -> Bool {
        cooldownEngine.isCoolingDown(channelID: channelID)
    }
}
