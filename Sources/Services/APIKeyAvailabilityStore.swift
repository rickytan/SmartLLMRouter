import Foundation

/// Tracks API keys that should be skipped for the current app session.
///
/// A 401 response means the upstream rejected the credential itself. Retrying
/// the same key on later requests wastes time and can hide healthy keys behind
/// a bad one. A 429 response is recoverable, so it receives an expiring cooldown.
final class APIKeyAvailabilityStore {
    private struct KeyScope: Hashable {
        let channelID: String
        let apiKey: String
    }

    private let lock = NSLock()
    private let now: () -> Date
    private var unauthorizedKeys: [KeyScope: Date] = [:]
    private var rateLimitedKeys: [KeyScope: Date] = [:]
    private var notifiedChannelRateLimits: [String: Date] = [:]
    private var rateLimitCooldown: TimeInterval = 30 * 60
    private var channelRateLimitHandler: ((String, Date) -> Void)?

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func updateRateLimitCooldown(_ duration: TimeInterval) {
        lock.lock()
        rateLimitCooldown = max(1, duration)
        lock.unlock()
    }

    func setChannelRateLimitHandler(_ handler: @escaping (String, Date) -> Void) {
        lock.lock()
        channelRateLimitHandler = handler
        lock.unlock()
    }

    func availableKeys(for channelID: String, apiKeys: [String]) -> [(index: Int, key: String)] {
        lock.lock()
        defer { lock.unlock() }

        removeExpiredRateLimitsLocked()

        return categorizedKeysLocked(for: channelID, apiKeys: apiKeys).available
    }

    /// Returns healthy keys when any exist; otherwise returns rate-limited keys
    /// in configured order as a last-resort probe set.
    func attemptKeys(for channelID: String, apiKeys: [String]) -> [(index: Int, key: String)] {
        lock.lock()
        defer { lock.unlock() }

        removeExpiredRateLimitsLocked()
        let keys = categorizedKeysLocked(for: channelID, apiKeys: apiKeys)
        return keys.available.isEmpty ? keys.rateLimited : keys.available
    }

    private func categorizedKeysLocked(
        for channelID: String,
        apiKeys: [String]
    ) -> (available: [(index: Int, key: String)], rateLimited: [(index: Int, key: String)]) {
        var available: [(index: Int, key: String)] = []
        var rateLimited: [(index: Int, key: String)] = []

        for (index, key) in apiKeys.enumerated() {
            let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty else { continue }
            let scope = KeyScope(channelID: channelID, apiKey: trimmedKey)
            guard unauthorizedKeys[scope] == nil else { continue }
            let entry = (index: index, key: trimmedKey)
            if rateLimitedKeys[scope] == nil {
                available.append(entry)
            } else {
                rateLimited.append(entry)
            }
        }
        return (available, rateLimited)
    }

    /// Cool down one key after a 429. If every otherwise usable key is cooling,
    /// notify the router with the earliest time at which the channel can recover.
    @discardableResult
    func markRateLimited(channelID: String, apiKey: String, allAPIKeys: [String]) -> Date? {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !channelID.isEmpty, !trimmedKey.isEmpty else { return nil }

        lock.lock()
        let currentDate = now()
        removeExpiredRateLimitsLocked(referenceDate: currentDate)
        let keyExpiration = currentDate.addingTimeInterval(rateLimitCooldown)
        rateLimitedKeys[KeyScope(channelID: channelID, apiKey: trimmedKey)] = keyExpiration
        let channelExpiration = channelRateLimitUntilLocked(
            channelID: channelID,
            apiKeys: allAPIKeys,
            referenceDate: currentDate
        )
        let handler = channelRateLimitHandler
        let notificationExpiration: Date?
        if let channelExpiration,
           notifiedChannelRateLimits[channelID] != channelExpiration {
            notifiedChannelRateLimits[channelID] = channelExpiration
            notificationExpiration = channelExpiration
        } else {
            notificationExpiration = nil
        }
        lock.unlock()

        if let notificationExpiration {
            handler?(channelID, notificationExpiration)
        }
        return keyExpiration
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

    func isRateLimited(channelID: String, apiKey: String) -> Bool {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        defer { lock.unlock() }
        removeExpiredRateLimitsLocked()
        return rateLimitedKeys[KeyScope(channelID: channelID, apiKey: trimmedKey)] != nil
    }

    func rateLimitExpiration(channelID: String, apiKey: String) -> Date? {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        defer { lock.unlock() }
        removeExpiredRateLimitsLocked()
        return rateLimitedKeys[KeyScope(channelID: channelID, apiKey: trimmedKey)]
    }

    func clear(channelID: String) {
        lock.lock()
        unauthorizedKeys = unauthorizedKeys.filter { $0.key.channelID != channelID }
        rateLimitedKeys = rateLimitedKeys.filter { $0.key.channelID != channelID }
        notifiedChannelRateLimits.removeValue(forKey: channelID)
        lock.unlock()
    }

    func clearAll() {
        lock.lock()
        unauthorizedKeys.removeAll()
        rateLimitedKeys.removeAll()
        notifiedChannelRateLimits.removeAll()
        lock.unlock()
    }

    private func removeExpiredRateLimitsLocked(referenceDate: Date? = nil) {
        let currentDate = referenceDate ?? now()
        rateLimitedKeys = rateLimitedKeys.filter { $0.value > currentDate }
        notifiedChannelRateLimits = notifiedChannelRateLimits.filter { $0.value > currentDate }
    }

    private func channelRateLimitUntilLocked(
        channelID: String,
        apiKeys: [String],
        referenceDate: Date
    ) -> Date? {
        let usableScopes = Set(apiKeys.compactMap { key -> KeyScope? in
            let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty else { return nil }
            let scope = KeyScope(channelID: channelID, apiKey: trimmedKey)
            return unauthorizedKeys[scope] == nil ? scope : nil
        })
        guard !usableScopes.isEmpty else { return nil }

        let expirations = usableScopes.compactMap { rateLimitedKeys[$0] }
        guard expirations.count == usableScopes.count,
              expirations.allSatisfy({ $0 > referenceDate })
        else {
            return nil
        }
        return expirations.min()
    }
}
