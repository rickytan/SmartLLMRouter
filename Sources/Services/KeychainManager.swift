import Foundation
import KeychainAccess

/// Secure wrapper for API Keys using macOS Keychain
final class KeychainManager {
    static let shared = KeychainManager()

    private let keychain: Keychain
    private let servicePrefix = "smartllm.apikey."

    private init() {
        // Use .always accessibility so the app can access keys without prompting
        // since the user explicitly stores these keys through the app itself
        keychain = Keychain(service: "com.smartllmrouter.keys")
            .accessibility(.always)
    }

    /// Store an API key for a channel
    func setAPIKey(_ key: String, for channelID: String) throws {
        try keychain.set(key, key: servicePrefix + channelID)
    }

    /// Retrieve an API key for a channel
    func getAPIKey(for channelID: String) -> String? {
        try? keychain.getString(servicePrefix + channelID)
    }

    /// Remove an API key for a channel
    func removeAPIKey(for channelID: String) throws {
        try keychain.remove(servicePrefix + channelID)
    }

    /// Clear all stored keys
    func clearAll() throws {
        try keychain.removeAll()
    }

    /// Check if a key exists for a channel
    func hasAPIKey(for channelID: String) -> Bool {
        getAPIKey(for: channelID) != nil
    }
}
