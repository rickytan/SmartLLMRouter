import Foundation
import KeychainAccess

/// Secure wrapper for API Keys using macOS Keychain
final class KeychainManager {
    static let shared = KeychainManager()

    private let keychain: Keychain
    private let storageKey = "smartllm.apikeys"
    private let legacyServicePrefix = "smartllm.apikey."
    private let lock = NSLock()
    private var apiKeysCache: [String: String]?

    private init() {
        // .afterFirstUnlock: accessible after user unlocks login keychain once per boot.
        // Avoids the deprecated .always which triggers password prompts on macOS 12+.
        keychain = Keychain(service: "com.smartllmrouter.keys")
            .accessibility(.afterFirstUnlock)
    }

    /// Store an API key for a channel
    func setAPIKey(_ key: String, for channelID: String) throws {
        lock.lock()
        defer { lock.unlock() }

        var apiKeys = loadAPIKeysLocked()
        apiKeys[channelID] = key
        try saveAPIKeysLocked(apiKeys)
    }

    /// Retrieve an API key for a channel
    func getAPIKey(for channelID: String) -> String? {
        lock.lock()
        defer { lock.unlock() }

        var apiKeys = loadAPIKeysLocked()
        if let apiKey = apiKeys[channelID] {
            return apiKey
        }

        guard let legacyAPIKey = getLegacyAPIKeyLocked(for: channelID) else {
            return nil
        }

        do {
            apiKeys[channelID] = legacyAPIKey
            try saveAPIKeysLocked(apiKeys)
            try? keychain.remove(legacyServicePrefix + channelID)
        } catch {
            Log.error("Failed to migrate API key for channel \(channelID): \(error.localizedDescription)")
        }

        return legacyAPIKey
    }

    /// Remove an API key for a channel
    func removeAPIKey(for channelID: String) throws {
        lock.lock()
        defer { lock.unlock() }

        var apiKeys = loadAPIKeysLocked()
        apiKeys.removeValue(forKey: channelID)
        try saveAPIKeysLocked(apiKeys)
        try? keychain.remove(legacyServicePrefix + channelID)
    }

    /// Clear all stored keys
    func clearAll() throws {
        lock.lock()
        defer { lock.unlock() }

        apiKeysCache = [:]
        try keychain.removeAll()
    }

    /// Check if a key exists for a channel
    func hasAPIKey(for channelID: String) -> Bool {
        getAPIKey(for: channelID) != nil
    }

    private func loadAPIKeysLocked() -> [String: String] {
        if let apiKeysCache {
            return apiKeysCache
        }

        guard let json = try? keychain.getString(storageKey),
              let data = json.data(using: .utf8)
        else {
            apiKeysCache = [:]
            return [:]
        }

        do {
            let apiKeys = try JSONDecoder().decode([String: String].self, from: data)
            apiKeysCache = apiKeys
            return apiKeys
        } catch {
            Log.error("Failed to load API keys: \(error.localizedDescription)")
            apiKeysCache = [:]
            return [:]
        }
    }

    private func saveAPIKeysLocked(_ apiKeys: [String: String]) throws {
        let data = try JSONEncoder().encode(apiKeys)
        guard let json = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "KeychainManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to encode API keys"]
            )
        }

        try keychain.set(json, key: storageKey)
        apiKeysCache = apiKeys
    }

    private func getLegacyAPIKeyLocked(for channelID: String) -> String? {
        try? keychain.getString(legacyServicePrefix + channelID)
    }
}
