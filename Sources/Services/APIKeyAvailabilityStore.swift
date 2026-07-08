import Foundation

/// Tracks API keys that should be skipped for the current app session.
///
/// A 401 response means the upstream rejected the credential itself. Retrying
/// the same key on later requests wastes time and can hide healthy keys behind
/// a bad one, so this store keeps per-channel key failures in memory only.
final class APIKeyAvailabilityStore {
    private struct KeyScope: Hashable {
        let channelID: String
        let apiKey: String
    }

    private let lock = NSLock()
    private var unauthorizedKeys: [KeyScope: Date] = [:]

    func availableKeys(for channelID: String, apiKeys: [String]) -> [(index: Int, key: String)] {
        lock.lock()
        defer { lock.unlock() }

        return apiKeys.enumerated().compactMap { index, key in
            let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty else { return nil }
            let scope = KeyScope(channelID: channelID, apiKey: trimmedKey)
            return unauthorizedKeys[scope] == nil ? (index, trimmedKey) : nil
        }
    }

    func markUnauthorized(channelID: String, apiKey: String) {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !channelID.isEmpty, !trimmedKey.isEmpty else { return }

        lock.lock()
        unauthorizedKeys[KeyScope(channelID: channelID, apiKey: trimmedKey)] = Date()
        lock.unlock()
    }

    func isUnauthorized(channelID: String, apiKey: String) -> Bool {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        defer { lock.unlock() }
        return unauthorizedKeys[KeyScope(channelID: channelID, apiKey: trimmedKey)] != nil
    }

    func clear(channelID: String) {
        lock.lock()
        unauthorizedKeys = unauthorizedKeys.filter { $0.key.channelID != channelID }
        lock.unlock()
    }

    func clearAll() {
        lock.lock()
        unauthorizedKeys.removeAll()
        lock.unlock()
    }
}
