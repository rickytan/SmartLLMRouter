import Foundation

/// Error types that trigger cooldown/failover
enum RouterErrorType: CustomStringConvertible {
    case rateLimit429
    case serverError5xx
    case authError401
    case timeout
    case clientError400
    case contextLengthExceeded
    case forbidden403
    case unknown

    var description: String {
        switch self {
        case .rateLimit429: "rateLimit429"
        case .serverError5xx: "serverError5xx"
        case .authError401: "authError401"
        case .timeout: "timeout"
        case .clientError400: "clientError400"
        case .contextLengthExceeded: "contextLengthExceeded"
        case .forbidden403: "forbidden403"
        case .unknown: "unknown"
        }
    }

    init(statusCode: Int, errorBody: Data? = nil) {
        // Check for context_length_exceeded in 400 responses
        if statusCode == 400, let errorBody {
            if let errorType = Self.parseErrorType(from: errorBody) {
                self = errorType
                return
            }
        }

        switch statusCode {
        case 429:
            self = .rateLimit429
        case 401:
            self = .authError401
        case 403:
            self = .forbidden403
        case 408:
            self = .timeout
        case 400 ..< 500:
            self = .clientError400
        case 500 ..< 600:
            self = .serverError5xx
        default:
            self = .unknown
        }
    }

    /// Parse error type from response body (detects context_length_exceeded)
    private static func parseErrorType(from body: Data) -> RouterErrorType? {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }

        // OpenAI-style: { "error": { "type": "invalid_request_error", "message": "...", "code": "context_length_exceeded" } }
        if let error = json["error"] as? [String: Any] {
            if let code = error["code"] as? String, code == "context_length_exceeded" {
                return .contextLengthExceeded
            }
            if let message = error["message"] as? String, message.localizedCaseInsensitiveContains("context") && message.localizedCaseInsensitiveContains("exceed") {
                return .contextLengthExceeded
            }
        }

        // Anthropic-style: { "type": "error", "error": { "type": "context_length_exceeded" } }
        if let error = json["error"] as? [String: Any],
           let type = error["type"] as? String,
           type == "context_length_exceeded" {
            return .contextLengthExceeded
        }

        // Direct check
        if let type = json["type"] as? String, type == "context_length_exceeded" {
            return .contextLengthExceeded
        }

        return nil
    }

    /// Whether this error type should trigger a failover
    var shouldFailover: Bool {
        switch self {
        case .rateLimit429, .serverError5xx, .authError401, .timeout, .contextLengthExceeded:
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
    /// The original model name the client requested (for transparency)
    let originalModel: String?
    /// The actual model to use (may differ from original if fallback was applied)
    let effectiveModel: String?

    init(
        channel: Channel,
        isRetry: Bool = false,
        previousChannelID: String? = nil,
        retryCount: Int = 0,
        originalModel: String? = nil,
        effectiveModel: String? = nil
    ) {
        self.channel = channel
        self.isRetry = isRetry
        self.previousChannelID = previousChannelID
        self.retryCount = retryCount
        self.originalModel = originalModel
        self.effectiveModel = effectiveModel
    }
}

final class RouterRuntimeState {
    private let lock = NSRecursiveLock()
    private var maxRetries: Int = 3
    private var smartFallbackEnabled: Bool = false
    private var maxFallbackCost: Double = 2.0
    private var retryCounter: [String: Int] = [:]
    private var requestToChannel: [String: String] = [:]
    private var requestAttemptedChannels: [String: Set<String>] = [:]
    private var channels: [Channel] = []
    private var activeChannelID: String?
    private var rateLimitedChannels: [String: Date] = [:]
    private let circuitBreaker: CircuitBreaker
    private let switchLock: SwitchLock

    init(
        circuitBreaker: CircuitBreaker = CircuitBreaker(),
        switchLock: SwitchLock = SwitchLock()
    ) {
        self.circuitBreaker = circuitBreaker
        self.switchLock = switchLock
        let defaults = UserDefaults.standard
        let savedMaxRetries = defaults.integer(forKey: "smartllm_router_max_retries")
        maxRetries = savedMaxRetries == 0 ? 3 : savedMaxRetries
        smartFallbackEnabled = defaults.bool(forKey: "smartllm_smart_fallback_enabled")
        let savedMaxFallbackCost = defaults.double(forKey: "smartllm_max_fallback_cost")
        maxFallbackCost = savedMaxFallbackCost > 0 ? savedMaxFallbackCost : 2.0
    }

    func updateSettings(maxRetries: Int, smartFallbackEnabled: Bool, maxFallbackCost: Double) {
        lock.lock()
        self.maxRetries = maxRetries
        self.smartFallbackEnabled = smartFallbackEnabled
        self.maxFallbackCost = maxFallbackCost
        lock.unlock()
    }

    func updateChannels(_ channels: [Channel], activeChannelID: String?) {
        lock.lock()
        self.channels = channels
        self.activeChannelID = activeChannelID
        lock.unlock()
    }

    func channelsSnapshot() -> [Channel] {
        lock.lock()
        defer { lock.unlock() }
        return channels
    }

    func enabledChannelsSnapshot() -> [Channel] {
        lock.lock()
        defer { lock.unlock() }
        return channels.filter(\.isEnabled)
    }

    func availableChannelsSnapshot() -> [Channel] {
        lock.lock()
        defer { lock.unlock() }
        return channelCandidateGroupsLocked().available
    }

    func markChannelRateLimited(channelID: String, until: Date) {
        lock.lock()
        rateLimitedChannels[channelID] = until
        lock.unlock()
        Log.warn("Channel \(channelID) rate-limited until \(until) because all API keys are cooling down")
    }

    func isChannelRateLimited(channelID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let until = rateLimitedChannels[channelID] else { return false }
        if until > Date() { return true }
        rateLimitedChannels.removeValue(forKey: channelID)
        return false
    }

    func activeChannelSnapshot() -> Channel? {
        lock.lock()
        defer { lock.unlock() }
        let enabled = channels.filter(\.isEnabled)
        guard let activeChannelID else { return enabled.first }
        return channels.first { $0.id == activeChannelID && $0.isEnabled } ?? enabled.first
    }

    func selectChannel(
        requestID: String,
        modelName: String? = nil,
        requestProtocol: RequestForwarder.RequestProtocol? = nil
    ) -> RoutingDecision? {
        lock.lock()
        defer { lock.unlock() }

        let channelGroups = channelCandidateGroupsLocked()

        let selectedChannel: Channel?
        var effectiveModel = modelName

        if let model = modelName {
            if let match = bestModelMatch(in: channelGroups.available, requestedModel: model) {
                selectedChannel = match.channel
                effectiveModel = match.model.identifier
            } else if let match = bestModelMatch(in: channelGroups.cooling, requestedModel: model) {
                let fallbackProtocol = resolvedRequestProtocol(
                    requestProtocol,
                    fallbackChannel: match.channel
                )
                if smartFallbackEnabled,
                   let fallback = fallbackModelCandidateLocked(
                       actualTokensUsed: 0,
                       apiProtocol: fallbackProtocol,
                       excludedChannelIDs: []
                   ) {
                    selectedChannel = fallback.channel
                    effectiveModel = fallback.model.identifier
                    Log.warn(
                        "All channels matching model '\(model)' are cooling down; "
                            + "smart fallback selected \(fallback.model.identifier) via \(fallback.channel.name)"
                    )
                } else {
                    selectedChannel = match.channel
                    effectiveModel = match.model.identifier
                    Log.warn("All channels matching model '\(model)' are cooling down; probing \(match.channel.name)")
                }
            } else {
                selectedChannel = nil
                Log.warn("No configured channel supports model '\(model)'")
            }
        } else {
            selectedChannel = channelGroups.available.first
        }

        guard let selectedChannel else {
            Log.warn("No available channels for routing")
            return nil
        }

        requestToChannel[requestID] = selectedChannel.id
        requestAttemptedChannels[requestID] = [selectedChannel.id]

        return RoutingDecision(
            channel: selectedChannel,
            isRetry: false,
            previousChannelID: nil,
            retryCount: 0,
            originalModel: modelName,
            effectiveModel: effectiveModel
        )
    }

    func handleError(requestID: String, statusCode: Int, modelName: String? = nil, errorBody: Data? = nil, requestProtocol: RequestForwarder.RequestProtocol? = nil) -> RoutingDecision? {
        lock.lock()
        defer { lock.unlock() }

        let errorType = RouterErrorType(statusCode: statusCode, errorBody: errorBody)
        Log.info("Handling error \(statusCode) for request \(requestID)")

        if errorType == .forbidden403 {
            Log.info("Error type \(errorType) does not trigger failover")
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
        var attemptedChannelIDs = requestAttemptedChannels[requestID] ?? []
        // On the first timeout, retry the SAME channel before failing over - it may be a
        // transient hiccup. selectChannel already seeded attemptedChannelIDs with this channel,
        // so we must REMOVE it to make it selectable again; and we skip recordFailure so the
        // circuit breaker isn't tripped for a single transient timeout. Subsequent timeouts
        // (and all other retryable errors) fail over to another channel normally.
        let retrySameChannel = (errorType == .timeout && currentRetryCount == 0)
        if let previousChannelID {
            if retrySameChannel {
                attemptedChannelIDs.remove(previousChannelID)
            } else {
                attemptedChannelIDs.insert(previousChannelID)
                _ = switchLock.execute {
                    self.circuitBreaker.recordFailure(channelID: previousChannelID)
                }
            }
        }
        requestAttemptedChannels[requestID] = attemptedChannelIDs

        retryCounter[requestID] = currentRetryCount + 1

        let channelGroups = channelCandidateGroupsLocked(excluding: attemptedChannelIDs)
        let actualTokensUsed = parseActualTokensUsedLocked(from: errorBody, modelName: modelName) ?? 0
        let minimumContextLength = errorType == .contextLengthExceeded && actualTokensUsed > 0
            ? actualTokensUsed
            : nil
        let availableMatch = modelName.flatMap { model in
            bestModelMatch(
                in: channelGroups.available,
                requestedModel: model,
                minimumContextLength: minimumContextLength
            )
        }
        let coolingMatch = modelName.flatMap { model in
            bestModelMatch(
                in: channelGroups.cooling,
                requestedModel: model,
                minimumContextLength: minimumContextLength
            )
        }
        let availableChannel = availableMatch?.channel ?? (modelName == nil ? channelGroups.available.first : nil)
        let availableModel = availableMatch?.model.identifier ?? modelName

        if let nextChannel = availableChannel {
            requestToChannel[requestID] = nextChannel.id
            requestAttemptedChannels[requestID, default: []].insert(nextChannel.id)
            let reason = errorType == .contextLengthExceeded ? " for context_length_exceeded" : ""
            Log.info("Retrying with channel \(nextChannel.name)\(reason) (retry #\(currentRetryCount + 1))")
            return RoutingDecision(
                channel: nextChannel,
                isRetry: true,
                previousChannelID: previousChannelID,
                retryCount: currentRetryCount + 1,
                originalModel: modelName,
                effectiveModel: availableModel
            )
        }

        if smartFallbackEnabled,
           let fallback = selectFallbackModelLocked(
               requestID: requestID,
               originalModel: modelName ?? "unknown",
               actualTokensUsed: actualTokensUsed,
               errorType: errorType,
               apiProtocol: requestProtocol ?? .openai,
               excludedChannelIDs: attemptedChannelIDs,
               retryCount: currentRetryCount + 1
           ) {
            return fallback
        }

        if let coolingMatch {
            requestToChannel[requestID] = coolingMatch.channel.id
            requestAttemptedChannels[requestID, default: []].insert(coolingMatch.channel.id)
            Log.warn(
                "No healthy channel matching model '\(modelName ?? "unknown")'; "
                    + "probing cooling channel \(coolingMatch.channel.name) (retry #\(currentRetryCount + 1))"
            )
            return RoutingDecision(
                channel: coolingMatch.channel,
                isRetry: true,
                previousChannelID: previousChannelID,
                retryCount: currentRetryCount + 1,
                originalModel: modelName,
                effectiveModel: coolingMatch.model.identifier
            )
        }

        Log.warn(errorType == .contextLengthExceeded ? "No suitable channel or fallback for context_length_exceeded on request \(requestID)" : "No alternative channels available for retry")
        return nil
    }

    private func bestModelMatch(
        in availableChannels: [Channel],
        requestedModel: String,
        minimumContextLength: Int? = nil
    ) -> (channel: Channel, model: ModelEntry)? {
        var bestScore = ModelSwitcher.ModelMatchScore.none
        var bestMatch: (channel: Channel, model: ModelEntry)?

        // Channels are priority-sorted by callers. Strict score improvement keeps
        // the first (highest-priority) channel when match quality is tied.
        for channel in availableChannels {
            for model in channel.models where model.isEnabled {
                if let minimumContextLength,
                   model.contextLength.map({ $0 > minimumContextLength }) != true {
                    continue
                }
                let score = ModelSwitcher.modelMatchScore(
                    requested: requestedModel,
                    stored: model.identifier
                )
                if score > bestScore {
                    bestScore = score
                    bestMatch = (channel, model)
                }
            }
        }
        return bestMatch
    }

    func recordSuccess(channelID: String) {
        circuitBreaker.recordSuccess(channelID: channelID)
    }

    func completeRequest(requestID: String) {
        lock.lock()
        retryCounter.removeValue(forKey: requestID)
        requestToChannel.removeValue(forKey: requestID)
        requestAttemptedChannels.removeValue(forKey: requestID)
        lock.unlock()
    }

    private func selectFallbackModelLocked(
        requestID: String,
        originalModel: String,
        actualTokensUsed: Int,
        errorType: RouterErrorType,
        apiProtocol: RequestForwarder.RequestProtocol,
        excludedChannelIDs: Set<String>,
        retryCount: Int
    ) -> RoutingDecision? {
        guard let best = fallbackModelCandidateLocked(
            actualTokensUsed: actualTokensUsed,
            apiProtocol: apiProtocol,
            excludedChannelIDs: excludedChannelIDs
        ) else {
            Log.warn("No suitable fallback model found for request \(requestID)")
            return nil
        }

        let previousChannel = channels.first { excludedChannelIDs.contains($0.id) } ?? Channel(name: "Unknown", baseURL: "")
        let cost = Double(actualTokensUsed + 5000) * (best.model.outputPricePer1M ?? best.model.inputPricePer1M ?? 0.0) / 1_000_000.0

        Log.info("[INFO] SmartRouter: Fallback triggered for request \(requestID)")
        Log.info("  Original model: \(originalModel) (Channel: \(previousChannel.name), Error: \(errorType))")
        Log.info("  Fallback model: \(best.model.identifier) (Channel: \(best.channel.name), Context: \(formatContextLength(best.model.contextLength ?? 0)))")
        Log.info("  Protocol: \(protocolLabel(apiProtocol)) (same protocol)")
        Log.info("  Estimated cost: $\(String(format: "%.3f", cost)) (limit: $\(String(format: "%.2f", maxFallbackCost)))")
        Log.info("  Retry attempt: \(retryCount)/\(maxRetries)")

        requestToChannel[requestID] = best.channel.id
        requestAttemptedChannels[requestID, default: []].insert(best.channel.id)
        return RoutingDecision(channel: best.channel, isRetry: true, previousChannelID: excludedChannelIDs.first, retryCount: retryCount, originalModel: originalModel, effectiveModel: best.model.identifier)
    }

    private func fallbackModelCandidateLocked(
        actualTokensUsed: Int,
        apiProtocol: RequestForwarder.RequestProtocol,
        excludedChannelIDs: Set<String>
    ) -> (channel: Channel, model: ModelEntry)? {
        let availableChannels = channels.filter { channel in
            !excludedChannelIDs.contains(channel.id) && pruneAndCheckChannelAvailableLocked(channel)
        }

        var candidates: [(channel: Channel, model: ModelEntry)] = []
        for channel in availableChannels {
            for model in channel.models where model.isEnabled {
                guard let contextLength = model.contextLength,
                      isProtocolCompatible(channel.protocol, with: apiProtocol),
                      contextLength > actualTokensUsed
                else {
                    continue
                }
                let pricePer1M = model.outputPricePer1M ?? model.inputPricePer1M ?? 0.0
                let cost = Double(actualTokensUsed + 5000) * pricePer1M / 1_000_000.0
                if cost <= maxFallbackCost {
                    candidates.append((channel: channel, model: model))
                }
            }
        }

        return candidates.sorted { lhs, rhs in
            let lhsContext = lhs.model.contextLength ?? 0
            let rhsContext = rhs.model.contextLength ?? 0
            if lhsContext != rhsContext { return lhsContext > rhsContext }
            return lhs.channel.priority < rhs.channel.priority
        }.first
    }

    private func parseActualTokensUsedLocked(from body: Data?, modelName: String?) -> Int? {
        guard let body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            return estimateTokensFromModelLocked(modelName)
        }

        if let usage = json["usage"] as? [String: Any] {
            return RequestForwarder.totalInputTokens(from: usage)
        }

        if let error = json["error"] as? [String: Any],
           let usage = error["usage"] as? [String: Any] {
            return RequestForwarder.totalInputTokens(from: usage)
        }

        return estimateTokensFromModelLocked(modelName)
    }

    private func estimateTokensFromModelLocked(_ modelName: String?) -> Int? {
        guard let modelName else { return nil }
        for channel in channels where channel.isEnabled {
            for model in channel.models where ModelSwitcher.modelMatches(requested: modelName, stored: model.identifier) {
                if let contextLength = model.contextLength {
                    return Int(Double(contextLength) * 0.8)
                }
            }
        }
        return nil
    }

    private func pruneAndCheckChannelAvailableLocked(_ channel: Channel) -> Bool {
        isChannelEligibleLocked(channel) && !isChannelCoolingLocked(channel)
    }

    private func channelCandidateGroupsLocked(
        excluding excludedChannelIDs: Set<String> = []
    ) -> (available: [Channel], cooling: [Channel]) {
        var available: [Channel] = []
        var cooling: [Channel] = []
        let sortedChannels = channels.sorted { $0.priority < $1.priority }

        for channel in sortedChannels where !excludedChannelIDs.contains(channel.id) {
            guard isChannelEligibleLocked(channel) else { continue }
            if isChannelCoolingLocked(channel) {
                cooling.append(channel)
            } else {
                available.append(channel)
            }
        }
        return (available, cooling)
    }

    private func isChannelEligibleLocked(_ channel: Channel) -> Bool {
        channel.isEnabled && circuitBreaker.isAvailable(channelID: channel.id)
    }

    private func isChannelCoolingLocked(_ channel: Channel) -> Bool {
        let currentDate = Date()
        if let until = rateLimitedChannels[channel.id] {
            if until > currentDate { return true }
            rateLimitedChannels.removeValue(forKey: channel.id)
        }

        return channel.isCoolingDown
            && channel.cooldownUntil.map { $0 > currentDate } == true
    }

    private func formatContextLength(_ length: Int) -> String {
        if length >= 1_000_000 { return "\(length / 1_000_000)M tokens" }
        if length >= 1_000 { return "\(length / 1_000)K tokens" }
        return "\(length) tokens"
    }

    private func protocolLabel(_ p: RequestForwarder.RequestProtocol) -> String {
        switch p {
        case .openai: "OpenAI"
        case .anthropic: "Anthropic"
        case .unknown: "Unknown"
        }
    }

    private func resolvedRequestProtocol(
        _ requestProtocol: RequestForwarder.RequestProtocol?,
        fallbackChannel: Channel
    ) -> RequestForwarder.RequestProtocol {
        if let requestProtocol, requestProtocol != .unknown {
            return requestProtocol
        }
        return defaultRequestProtocol(for: fallbackChannel)
    }

    private func defaultRequestProtocol(for channel: Channel) -> RequestForwarder.RequestProtocol {
        switch channel.protocol {
        case .openai, .auto: .openai
        case .anthropic: .anthropic
        }
    }

    private func isProtocolCompatible(
        _ channelProtocol: APIProtocol,
        with requestProtocol: RequestForwarder.RequestProtocol
    ) -> Bool {
        switch channelProtocol {
        case .auto:
            true
        case .openai:
            requestProtocol == .openai
        case .anthropic:
            requestProtocol == .anthropic
        }
    }

}

final class ModelOverrideRuntimeState {
    private let lock = NSLock()
    private var selectedModelID: String?

    init() {}

    func update(selectedModelID: String?) {
        lock.lock()
        self.selectedModelID = selectedModelID
        lock.unlock()
    }

    func snapshot() -> (hasOverride: Bool, selectedModelID: String?) {
        lock.lock()
        defer { lock.unlock() }
        return (selectedModelID != nil, selectedModelID)
    }
}

/// Smart routing engine for channel selection and failover
@MainActor
final class SmartRouter: ObservableObject {
    static let defaultCircuitBreakerFailureThreshold = 5
    static let circuitBreakerFailureThresholdRange = 1...10
    static let cooldown429MinutesRange = 1...1440

    @Published var maxRetries: Int = 3
    @Published var cooldown429Minutes: Int = 30
    @Published var cooldown5xxMinutes: Int = 10
    @Published var cooldown401Hours: Int = 24
    @Published var circuitBreakerFailureThreshold: Int = defaultCircuitBreakerFailureThreshold

    // Smart Model Fallback settings
    @Published var smartFallbackEnabled: Bool = false
    @Published var maxFallbackCost: Double = 2.0

    private let services: RouterServices
    private let defaults: UserDefaults

    init(services: RouterServices, defaults: UserDefaults = .standard) {
        self.services = services
        self.defaults = defaults
        loadSettings()
        syncRuntimeSettings()
    }

    // MARK: - Settings

    private func loadSettings() {
        maxRetries = defaults.integer(forKey: "smartllm_router_max_retries")
        if maxRetries == 0 { maxRetries = 3 }

        cooldown429Minutes = defaults.integer(forKey: "smartllm_router_cooldown_429")
        if !Self.cooldown429MinutesRange.contains(cooldown429Minutes) {
            cooldown429Minutes = 30
        }

        cooldown5xxMinutes = defaults.integer(forKey: "smartllm_router_cooldown_5xx")
        if cooldown5xxMinutes == 0 { cooldown5xxMinutes = 10 }

        cooldown401Hours = defaults.integer(forKey: "smartllm_router_cooldown_401")
        if cooldown401Hours == 0 { cooldown401Hours = 24 }

        let savedFailureThreshold = defaults.integer(forKey: "smartllm_circuit_breaker_failure_threshold")
        circuitBreakerFailureThreshold = Self.circuitBreakerFailureThresholdRange.contains(savedFailureThreshold)
            ? savedFailureThreshold
            : Self.defaultCircuitBreakerFailureThreshold

        // Smart Fallback settings
        smartFallbackEnabled = defaults.bool(forKey: "smartllm_smart_fallback_enabled")
        let savedCost = defaults.double(forKey: "smartllm_max_fallback_cost")
        maxFallbackCost = savedCost > 0 ? savedCost : 2.0
    }

    func saveSettings() {
        defaults.set(maxRetries, forKey: "smartllm_router_max_retries")
        defaults.set(cooldown429Minutes, forKey: "smartllm_router_cooldown_429")
        defaults.set(cooldown5xxMinutes, forKey: "smartllm_router_cooldown_5xx")
        defaults.set(cooldown401Hours, forKey: "smartllm_router_cooldown_401")
        defaults.set(circuitBreakerFailureThreshold, forKey: "smartllm_circuit_breaker_failure_threshold")
        defaults.set(smartFallbackEnabled, forKey: "smartllm_smart_fallback_enabled")
        defaults.set(maxFallbackCost, forKey: "smartllm_max_fallback_cost")
        syncRuntimeSettings()
    }

    private func syncRuntimeSettings() {
        services.circuitBreaker.updateConsecutiveFailureThreshold(circuitBreakerFailureThreshold)
        services.apiKeyAvailabilityStore.updateRateLimitCooldown(Double(cooldown429Minutes) * 60)
        services.runtimeState.updateChannels(
            services.channelServices.channels,
            activeChannelID: services.channelServices.store.activeChannelID
        )
        services.runtimeState.updateSettings(
            maxRetries: maxRetries,
            smartFallbackEnabled: smartFallbackEnabled,
            maxFallbackCost: maxFallbackCost
        )
    }

    // MARK: - Routing Logic

    /// Select the best available channel for a request
    func selectChannel(
        requestID: String,
        modelName: String? = nil,
        requestProtocol: RequestForwarder.RequestProtocol? = nil
    ) -> RoutingDecision? {
        syncRuntimeSettings()
        return services.runtimeState.selectChannel(
            requestID: requestID,
            modelName: modelName,
            requestProtocol: requestProtocol
        )
    }

    /// Handle an error and decide if we should retry with another channel
    func handleError(requestID: String, statusCode: Int, modelName: String? = nil, errorBody: Data? = nil, requestProtocol: RequestForwarder.RequestProtocol? = nil) -> RoutingDecision? {
        syncRuntimeSettings()
        return services.runtimeState.handleError(
            requestID: requestID,
            statusCode: statusCode,
            modelName: modelName,
            errorBody: errorBody,
            requestProtocol: requestProtocol
        )
    }

    /// Record a successful request for the channel (closes circuit if half-open)
    func recordSuccess(channelID: String) {
        services.runtimeState.recordSuccess(channelID: channelID)
    }

    /// Clear retry tracking for a completed request
    func completeRequest(requestID: String) {
        services.runtimeState.completeRequest(requestID: requestID)
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
            cooldown429Minutes = min(
                max(m, Self.cooldown429MinutesRange.lowerBound),
                Self.cooldown429MinutesRange.upperBound
            )
        }
        if let m = min5xx {
            cooldown5xxMinutes = m
        }
        if let h = hrs401 {
            cooldown401Hours = h
        }
        saveSettings()
    }

    /// Update max retries
    func setMaxRetries(_ count: Int) {
        maxRetries = max(0, min(10, count))
        saveSettings()
    }

    /// Update how many consecutive failed requests trip a channel's circuit.
    func setCircuitBreakerFailureThreshold(_ count: Int) {
        circuitBreakerFailureThreshold = min(
            max(count, Self.circuitBreakerFailureThresholdRange.lowerBound),
            Self.circuitBreakerFailureThresholdRange.upperBound
        )
        saveSettings()
    }
}
