import Foundation

/// Represents a cooldown period for a channel
struct CooldownEntry: Codable, Identifiable {
    let id: String
    let channelID: String
    let startTime: Date
    let duration: TimeInterval // seconds
    let reason: String

    var endTime: Date {
        startTime.addingTimeInterval(duration)
    }

    var remainingTime: TimeInterval {
        let remaining = endTime.timeIntervalSince(Date())
        return max(0, remaining)
    }

    var isActive: Bool {
        remainingTime > 0
    }

    /// Human-readable remaining time
    var remainingDescription: String {
        let remaining = remainingTime
        if remaining <= 0 {
            return "Expired"
        } else if remaining < 60 {
            return "\(Int(remaining))s"
        } else if remaining < 3600 {
            let minutes = Int(remaining / 60)
            return "\(minutes)m"
        } else {
            let hours = Int(remaining / 3600)
            let minutes = Int((remaining.truncatingRemainder(dividingBy: 3600)) / 60)
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            }
            return "\(hours)h"
        }
    }
}

/// Manages cooldown periods for channels after errors
@MainActor
final class CooldownEngine: ObservableObject {
    private let userDefaultsKey = "smartllm_router_cooldowns"

    @Published private(set) var cooldowns: [CooldownEntry] = []

    private var cleanupTimer: Timer?
    private let channelStore: ChannelStore

    init(channelStore: ChannelStore) {
        self.channelStore = channelStore
        loadCooldowns()
        startCleanupTimer()
    }

    // MARK: - Public API

    /// Check if a channel is currently in cooldown
    func isCoolingDown(channelID: String) -> Bool {
        let entry = getCooldown(channelID: channelID)
        return entry?.isActive ?? false
    }

    /// Get cooldown entry for a channel
    func getCooldown(channelID: String) -> CooldownEntry? {
        cooldowns.first { $0.channelID == channelID && $0.isActive }
    }

    /// Get all active cooldowns
    func activeCooldowns() -> [CooldownEntry] {
        cooldowns.filter(\.isActive)
    }

    /// Start a cooldown for a channel
    func startCooldown(channelID: String, duration: TimeInterval, reason: String = "Error") {
        startCooldown(
            channelID: channelID,
            until: Date().addingTimeInterval(duration),
            reason: reason
        )
    }

    /// Start a cooldown ending at an absolute time shared with key-level state.
    func startCooldown(channelID: String, until: Date, reason: String = "Error") {
        // Remove any existing cooldown for this channel
        cooldowns.removeAll { $0.channelID == channelID }

        // Create new cooldown entry
        let entry = CooldownEntry(
            id: UUID().uuidString,
            channelID: channelID,
            startTime: Date(),
            duration: max(0, until.timeIntervalSinceNow),
            reason: reason
        )

        cooldowns.append(entry)
        saveCooldowns()

        Log.info("Cooldown started for channel \(channelID) until \(until) (\(reason))")

        // Update ChannelStore's cooldown flags
        updateChannelCooldownFlags()
    }

    /// Manually clear a cooldown
    func clearCooldown(channelID: String) {
        cooldowns.removeAll { $0.channelID == channelID }
        saveCooldowns()
        updateChannelCooldownFlags()
        Log.info("Cooldown cleared for channel \(channelID)")
    }

    /// Clear all cooldowns
    func clearAllCooldowns() {
        cooldowns.removeAll()
        saveCooldowns()
        updateChannelCooldownFlags()
        Log.info("All cooldowns cleared")
    }

    /// Get remaining cooldown time for a channel
    func remainingTime(channelID: String) -> TimeInterval {
        let entry = getCooldown(channelID: channelID)
        return entry?.remainingTime ?? 0
    }

    /// Get cooldown reason for a channel
    func cooldownReason(channelID: String) -> String? {
        let entry = getCooldown(channelID: channelID)
        return entry?.reason
    }

    // MARK: - Private

    private func loadCooldowns() {
        guard let data = channelStore.defaults.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([CooldownEntry].self, from: data)
        else {
            cooldowns = []
            return
        }

        // Filter out expired cooldowns on load
        cooldowns = decoded.filter(\.isActive)
        saveCooldowns()
    }

    private func saveCooldowns() {
        // Only save active cooldowns
        let active = cooldowns.filter(\.isActive)
        do {
            let encoded = try JSONEncoder().encode(active)
            channelStore.defaults.set(encoded, forKey: userDefaultsKey)
        } catch {
            Log.error("Failed to save cooldowns: \(error.localizedDescription)")
        }
    }

    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.cleanupExpiredCooldowns()
        }
    }

    private func cleanupExpiredCooldowns() {
        let hadExpired = cooldowns.contains { !$0.isActive }

        if hadExpired {
            cooldowns.removeAll { !$0.isActive }
            saveCooldowns()
            updateChannelCooldownFlags()
            Log.debug("Cleaned up expired cooldowns")
        }
    }

    /// Update ChannelStore's channel cooldown flags
    private func updateChannelCooldownFlags() {
        let channels = channelStore.channels
        for channel in channels {
            let isCooling = isCoolingDown(channelID: channel.id)
            let cooldownEnd = getCooldown(channelID: channel.id)?.endTime

            // Only update if state changed
            if channel.isCoolingDown != isCooling || channel.cooldownUntil != cooldownEnd {
                var updatedChannel = channel
                updatedChannel.isCoolingDown = isCooling
                updatedChannel.cooldownUntil = cooldownEnd
                channelStore.updateChannel(updatedChannel)
            }
        }
    }

    deinit {
        cleanupTimer?.invalidate()
    }
}

// MARK: - CooldownEntry Extensions

extension CooldownEntry: Equatable {
    static func == (lhs: CooldownEntry, rhs: CooldownEntry) -> Bool {
        lhs.id == rhs.id
    }
}

extension CooldownEntry: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
