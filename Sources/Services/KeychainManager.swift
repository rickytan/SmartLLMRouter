import Foundation
import KeychainAccess

/// Secure wrapper for API Keys using macOS Keychain
final class KeychainManager {
    /// The default Keychain service for production. The unit-test target
    /// uses `TEST_HOST`/`BUNDLE_LOADER` to inject itself into the host
    /// app's process, so it inherits the production bundle ID and
    /// therefore has the same access rights to the production keychain.
    /// If a test instantiated this class with the default service and
    /// called `clearAll()`, it would wipe the user's real API keys.
    /// Tests MUST instantiate with a unique service (see
    /// `KeychainManagerTestSupport`).
    static let defaultService = "com.smartllmrouter.keys"

    let keychain: Keychain
    private let storageKey = "smartllm.apikeys"
    private let legacyServicePrefix = "smartllm.apikey."
    private let lock = NSLock()
    private var apiKeysCache: [String: [String]]?

    init(service: String = KeychainManager.defaultService) {
        // .afterFirstUnlock: accessible after user unlocks login keychain once per boot.
        // Avoids the deprecated .always which triggers password prompts on macOS 12+.
        keychain = Keychain(service: service)
            .accessibility(.afterFirstUnlock)
    }

    /// Store an API key for a channel
    func setAPIKey(_ key: String, for channelID: String) throws {
        try setAPIKeys([key], for: channelID)
    }

    /// Store API keys for a channel. Empty keys are dropped and order is preserved.
    func setAPIKeys(_ keys: [String], for channelID: String) throws {
        lock.lock()
        defer { lock.unlock() }

        var apiKeys = loadAPIKeysLocked()
        let sanitizedKeys = sanitizeAPIKeys(keys)
        if sanitizedKeys.isEmpty {
            apiKeys.removeValue(forKey: channelID)
        } else {
            apiKeys[channelID] = sanitizedKeys
        }
        try saveAPIKeysLocked(apiKeys)
    }

    /// Retrieve an API key for a channel
    func getAPIKey(for channelID: String) -> String? {
        getAPIKeys(for: channelID).first
    }

    /// Retrieve all API keys for a channel
    func getAPIKeys(for channelID: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }

        var apiKeys = loadAPIKeysLocked()
        if let channelKeys = apiKeys[channelID], !channelKeys.isEmpty {
            return channelKeys
        }

        guard let legacyAPIKey = getLegacyAPIKeyLocked(for: channelID) else {
            return []
        }

        do {
            apiKeys[channelID] = sanitizeAPIKeys([legacyAPIKey])
            try saveAPIKeysLocked(apiKeys)
            try? keychain.remove(legacyServicePrefix + channelID)
        } catch {
            Log.error("Failed to migrate API key for channel \(channelID): \(error.localizedDescription)")
        }

        return sanitizeAPIKeys([legacyAPIKey])
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

    /// Test-only. Drops the in-memory cache so the next read goes back
    /// to the keychain. Production code should not call this; use
    /// `clearAll` if you need to wipe both the cache and storage.
    func resetCache() {
        lock.lock()
        defer { lock.unlock() }
        apiKeysCache = nil
    }

    /// Check if a key exists for a channel
    func hasAPIKey(for channelID: String) -> Bool {
        !getAPIKeys(for: channelID).isEmpty
    }

    private func loadAPIKeysLocked() -> [String: [String]] {
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
            let apiKeys = try JSONDecoder().decode([String: [String]].self, from: data)
            apiKeysCache = apiKeys
            return apiKeys
        } catch {
            do {
                let legacyAPIKeys = try JSONDecoder().decode([String: String].self, from: data)
                let migrated = legacyAPIKeys.reduce(into: [String: [String]]()) { result, pair in
                    let keys = sanitizeAPIKeys([pair.value])
                    if !keys.isEmpty {
                        result[pair.key] = keys
                    }
                }
                try saveAPIKeysLocked(migrated)
                Log.info("Migrated API key storage to multi-key format")
                return migrated
            } catch {
                Log.error("Failed to load API keys: \(error.localizedDescription)")
                apiKeysCache = [:]
                return [:]
            }
        }
    }

    private func saveAPIKeysLocked(_ apiKeys: [String: [String]]) throws {
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

    private func sanitizeAPIKeys(_ keys: [String]) -> [String] {
        var seen = Set<String>()
        return keys.compactMap { key in
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else {
                return nil
            }
            seen.insert(trimmed)
            return trimmed
        }
    }
}
