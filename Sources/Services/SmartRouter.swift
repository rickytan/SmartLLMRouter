import Foundation

/// Routing mode for the SmartRouter
enum RoutingMode: String, Codable, CaseIterable {
    case manual = "Manual"
    case auto = "Auto"
}

/// Error types that trigger cooldown/failover
enum RouterErrorType: CustomStringConvertible {
    case rateLimit429
    case serverError5xx
    case authError401
    case timeout
    case clientError400
    case forbidden403
    case unknown

    var description: String {
        switch self {
        case .rateLimit429: "rateLimit429"
        case .serverError5xx: "serverError5xx"
        case .authError401: "authError401"
        case .timeout: "timeout"
        case .clientError400: "clientError400"
        case .forbidden403: "forbidden403"
        case .unknown: "unknown"
        }
    }

    init(statusCode: Int) {
        switch statusCode {
        case 429:
            self = .rateLimit429
        case 401:
            self = .authError401
        case 403:
            self = .forbidden403
        case 400 ..< 500:
            self = .clientError400
        case 500 ..< 600:
            self = .serverError5xx
        default:
            self = .unknown
        }
    }

    /// Whether this error type should trigger a failover
    var shouldFailover: Bool {
        switch self {
        case .rateLimit429, .serverError5xx, .authError401, .timeout:
            true
        case .clientError400, .forbidden403, .unknown:
            false
        }
    }
}

/// Result of a routing decision
struct RoutingDecision {
    let channel: Channel
    let isRetry: Bool
    let previousChannelID: String?
    let retryCount: Int
}

/// Smart routing engine for channel selection and failover
@MainActor
final class SmartRouter: ObservableObject {
    static let shared = SmartRouter()

    @Published var mode: RoutingMode = .auto
    @Published var maxRetries: Int = 3
    @Published var cooldown429Minutes: Int = 30
    @Published var cooldown5xxMinutes: Int = 10
    @Published var cooldown401Hours: Int = 24

    private var retryCounter: [String: Int] = [:]
    private var requestToChannel: [String: String] = [:]

    private init() {
        loadSettings()
    }

    // MARK: - Settings

    private func loadSettings() {
        mode = RoutingMode(rawValue: UserDefaults.standard.string(forKey: "smartllm_router_mode") ?? "Auto") ?? .auto
        maxRetries = UserDefaults.standard.integer(forKey: "smartllm_router_max_retries")
        if maxRetries == 0 { maxRetries = 3 }

        cooldown429Minutes = UserDefaults.standard.integer(forKey: "smartllm_router_cooldown_429")
        if cooldown429Minutes == 0 { cooldown429Minutes = 30 }

        cooldown5xxMinutes = UserDefaults.standard.integer(forKey: "smartllm_router_cooldown_5xx")
        if cooldown5xxMinutes == 0 { cooldown5xxMinutes = 10 }

        cooldown401Hours = UserDefaults.standard.integer(forKey: "smartllm_router_cooldown_401")
        if cooldown401Hours == 0 { cooldown401Hours = 24 }
    }

    func saveSettings() {
        UserDefaults.standard.set(mode.rawValue, forKey: "smartllm_router_mode")
        UserDefaults.standard.set(maxRetries, forKey: "smartllm_router_max_retries")
        UserDefaults.standard.set(cooldown429Minutes, forKey: "smartllm_router_cooldown_429")
        UserDefaults.standard.set(cooldown5xxMinutes, forKey: "smartllm_router_cooldown_5xx")
        UserDefaults.standard.set(cooldown401Hours, forKey: "smartllm_router_cooldown_401")
    }

    // MARK: - Routing Logic

    /// Select the best available channel for a request
    func selectChannel(requestID: String, modelName: String? = nil) -> RoutingDecision? {
        let channels = ChannelStore.shared.channels
        let cooldownEngine = CooldownEngine.shared

        let sortedChannels = channels.sorted { $0.priority < $1.priority }

        let availableChannels = sortedChannels.filter { channel in
            !cooldownEngine.isCoolingDown(channelID: channel.id)
        }

        let compatibleChannels: [Channel] = if let model = modelName {
            availableChannels.filter { channel in
                channel.models.contains { $0.identifier == model || $0.displayName == model }
            }
        } else {
            availableChannels
        }

        guard let selectedChannel = compatibleChannels.first else {
            Log.warn("No available channels for routing")
            return nil
        }

        requestToChannel[requestID] = selectedChannel.id

        return RoutingDecision(
            channel: selectedChannel,
            isRetry: false,
            previousChannelID: nil,
            retryCount: 0
        )
    }

    /// Handle an error and decide if we should retry with another channel
    func handleError(requestID: String, statusCode: Int, modelName: String? = nil) -> RoutingDecision? {
        let errorType = RouterErrorType(statusCode: statusCode)

        Log.info("Handling error \(statusCode) for request \(requestID)")

        if mode == .manual {
            Log.info("Manual mode - no retry")
            return nil
        }

        if !errorType.shouldFailover {
            Log.info("Error type \(errorType) does not trigger failover")
            return nil
        }

        let currentRetryCount = retryCounter[requestID] ?? 0

        if currentRetryCount >= maxRetries {
            Log.warn("Max retries exceeded for request \(requestID)")
            return nil
        }

        let previousChannelID = requestToChannel[requestID]

        if let prevID = previousChannelID {
            startCooldown(channelID: prevID, errorType: errorType)
        }

        retryCounter[requestID] = currentRetryCount + 1

        let channels = ChannelStore.shared.channels
        let cooldownEngine = CooldownEngine.shared

        let sortedChannels = channels.sorted { $0.priority < $1.priority }
        let availableChannels = sortedChannels.filter { channel in
            channel.id != previousChannelID &&
                !cooldownEngine.isCoolingDown(channelID: channel.id)
        }

        let compatibleChannels: [Channel] = if let model = modelName {
            availableChannels.filter { channel in
                channel.models.contains { $0.identifier == model || $0.displayName == model }
            }
        } else {
            availableChannels
        }

        guard let nextChannel = compatibleChannels.first else {
            Log.warn("No alternative channels available for retry")
            return nil
        }

        requestToChannel[requestID] = nextChannel.id

        Log.info("Retrying with channel \(nextChannel.name) (retry #\(currentRetryCount + 1))")

        return RoutingDecision(
            channel: nextChannel,
            isRetry: true,
            previousChannelID: previousChannelID,
            retryCount: currentRetryCount + 1
        )
    }

    /// Start cooldown for a channel based on error type
    private func startCooldown(channelID: String, errorType: RouterErrorType) {
        let cooldownEngine = CooldownEngine.shared
        let duration: TimeInterval = switch errorType {
        case .rateLimit429:
            Double(cooldown429Minutes) * 60.0
        case .serverError5xx:
            Double(cooldown5xxMinutes) * 60.0
        case .authError401:
            Double(cooldown401Hours) * 3600.0
        default:
            60.0
        }

        cooldownEngine.startCooldown(channelID: channelID, duration: duration)
        Log.info("Started cooldown for channel \(channelID) - \(duration)s")
    }

    /// Clear retry tracking for a completed request
    func completeRequest(requestID: String) {
        retryCounter.removeValue(forKey: requestID)
        requestToChannel.removeValue(forKey: requestID)
    }

    /// Get cooldown duration for an error type
    func cooldownDuration(for errorType: RouterErrorType) -> TimeInterval {
        switch errorType {
        case .rateLimit429:
            Double(cooldown429Minutes) * 60.0
        case .serverError5xx:
            Double(cooldown5xxMinutes) * 60.0
        case .authError401:
            Double(cooldown401Hours) * 3600.0
        default:
            60.0
        }
    }

    /// Update cooldown settings
    func updateCooldownSettings(min429: Int? = nil, min5xx: Int? = nil, hrs401: Int? = nil) {
        if let m = min429 {
            cooldown429Minutes = m
        }
        if let m = min5xx {
            cooldown5xxMinutes = m
        }
        if let h = hrs401 {
            cooldown401Hours = h
        }
        saveSettings()
    }

    /// Update routing mode
    func setMode(_ newMode: RoutingMode) {
        mode = newMode
        saveSettings()
    }

    /// Update max retries
    func setMaxRetries(_ count: Int) {
        maxRetries = max(0, min(10, count))
        saveSettings()
    }
}
