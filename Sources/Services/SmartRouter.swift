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

/// Smart routing engine for channel selection and failover
@MainActor
final class SmartRouter: ObservableObject {
    static let shared = SmartRouter()

    @Published var mode: RoutingMode = .auto
    @Published var maxRetries: Int = 3
    @Published var cooldown429Minutes: Int = 30
    @Published var cooldown5xxMinutes: Int = 10
    @Published var cooldown401Hours: Int = 24

    // Smart Model Fallback settings
    @Published var smartFallbackEnabled: Bool = false
    @Published var maxFallbackCost: Double = 2.0

    private var retryCounter: [String: Int] = [:]
    private var requestToChannel: [String: String] = [:]

    /// Circuit breaker instance (replaces CooldownEngine)
    private var circuitBreaker: CircuitBreaker { CircuitBreaker.shared }

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

        // Smart Fallback settings
        smartFallbackEnabled = UserDefaults.standard.bool(forKey: "smartllm_smart_fallback_enabled")
        let savedCost = UserDefaults.standard.double(forKey: "smartllm_max_fallback_cost")
        maxFallbackCost = savedCost > 0 ? savedCost : 2.0
    }

    func saveSettings() {
        UserDefaults.standard.set(mode.rawValue, forKey: "smartllm_router_mode")
        UserDefaults.standard.set(maxRetries, forKey: "smartllm_router_max_retries")
        UserDefaults.standard.set(cooldown429Minutes, forKey: "smartllm_router_cooldown_429")
        UserDefaults.standard.set(cooldown5xxMinutes, forKey: "smartllm_router_cooldown_5xx")
        UserDefaults.standard.set(cooldown401Hours, forKey: "smartllm_router_cooldown_401")
        UserDefaults.standard.set(smartFallbackEnabled, forKey: "smartllm_smart_fallback_enabled")
        UserDefaults.standard.set(maxFallbackCost, forKey: "smartllm_max_fallback_cost")
    }

    // MARK: - Routing Logic

    /// Select the best available channel for a request
    func selectChannel(requestID: String, modelName: String? = nil) -> RoutingDecision? {
        let channels = ChannelStore.shared.channels

        let sortedChannels = channels.sorted { $0.priority < $1.priority }

        // Use CircuitBreaker instead of CooldownEngine
        let availableChannels = sortedChannels.filter { channel in
            circuitBreaker.isAvailable(channelID: channel.id)
        }

        let compatibleChannels: [Channel] = if let model = modelName {
            availableChannels.filter { channel in
                channel.models.contains { $0.isEnabled && ($0.identifier == model || $0.displayName == model) }
            }
        } else {
            availableChannels
        }

        let selectedChannel: Channel?
        if let model = modelName, compatibleChannels.isEmpty {
            // Pass-through for models that are not in local metadata yet.
            // This keeps the proxy usable when providers add new model IDs before providers.json is updated.
            selectedChannel = availableChannels.first
            if let selectedChannel {
                Log.info("No exact channel match for model '\(model)'; pass-through via \(selectedChannel.name)")
            }
        } else {
            selectedChannel = compatibleChannels.first
        }

        guard let selectedChannel else {
            Log.warn("No available channels for routing")
            return nil
        }

        requestToChannel[requestID] = selectedChannel.id

        return RoutingDecision(
            channel: selectedChannel,
            isRetry: false,
            previousChannelID: nil,
            retryCount: 0,
            originalModel: modelName,
            effectiveModel: modelName
        )
    }

    /// Handle an error and decide if we should retry with another channel
    func handleError(requestID: String, statusCode: Int, modelName: String? = nil, errorBody: Data? = nil, requestProtocol: RequestForwarder.RequestProtocol? = nil) -> RoutingDecision? {
        let errorType = RouterErrorType(statusCode: statusCode, errorBody: errorBody)

        Log.info("Handling error \(statusCode) for request \(requestID)")

        if mode == .manual {
            Log.info("Manual mode - no retry")
            return nil
        }

        // For 401/403: no fallback — credential issue, changing model won't help
        if errorType == .authError401 || errorType == .forbidden403 {
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

        // Use SwitchLock to prevent race conditions in state changes
        SwitchLock.shared.execute {
            if let prevID = previousChannelID {
                self.circuitBreaker.recordFailure(channelID: prevID)
            }
        }

        retryCounter[requestID] = currentRetryCount + 1

        let channels = ChannelStore.shared.channels

        let sortedChannels = channels.sorted { $0.priority < $1.priority }
        let availableChannels = sortedChannels.filter { channel in
            channel.id != previousChannelID &&
                circuitBreaker.isAvailable(channelID: channel.id)
        }

        let compatibleChannels: [Channel] = if let model = modelName {
            availableChannels.filter { channel in
                channel.models.contains { $0.identifier == model || $0.displayName == model }
            }
        } else {
            availableChannels
        }

        // For context_length_exceeded: first try same-model channel downgrade, then smart fallback
        if errorType == .contextLengthExceeded {
            // Step 1: Try standard downgrade — find same model on another available channel
            if let nextChannel = compatibleChannels.first {
                requestToChannel[requestID] = nextChannel.id

                Log.info("Retrying with channel \(nextChannel.name) for context_length_exceeded (retry #\(currentRetryCount + 1))")

                return RoutingDecision(
                    channel: nextChannel,
                    isRetry: true,
                    previousChannelID: previousChannelID,
                    retryCount: currentRetryCount + 1,
                    originalModel: modelName,
                    effectiveModel: modelName
                )
            }

            // Step 2: No same-model channel — try smart fallback (only if enabled)
            if smartFallbackEnabled {
                let actualTokensUsed = parseActualTokensUsed(from: errorBody, modelName: modelName) ?? 0
                let protocolType = resolveRequestProtocol(requestProtocol: requestProtocol)

                if let fallback = selectFallbackModel(
                    requestID: requestID,
                    originalModel: modelName ?? "unknown",
                    actualTokensUsed: actualTokensUsed,
                    errorType: errorType,
                    apiProtocol: protocolType,
                    excludedChannelID: previousChannelID
                ) {
                    Log.info("[INFO] SmartRouter: Fallback triggered for request \(requestID)")
                    Log.info("  Original model: \(fallback.originalModel) (Channel: \(fallback.previousChannel.name), Error: \(errorType))")
                    Log.info("  Fallback model: \(fallback.fallbackModel) (Channel: \(fallback.channel.name), Context: \(fallback.channel.models.first(where: { $0.identifier == fallback.fallbackModel })?.contextLength.map(formatContextLength) ?? "N/A"))")
                    Log.info("  Protocol: \(protocolLabel(protocolType)) (same protocol)")
                    Log.info("  Estimated cost: $\(String(format: "%.3f", fallback.estimatedCost)) (limit: $\(String(format: "%.2f", maxFallbackCost)))")
                    Log.info("  Retry attempt: \(currentRetryCount + 1)/\(maxRetries)")

                    requestToChannel[requestID] = fallback.channel.id

                    return RoutingDecision(
                        channel: fallback.channel,
                        isRetry: true,
                        previousChannelID: previousChannelID,
                        retryCount: currentRetryCount + 1,
                        originalModel: fallback.originalModel,
                        effectiveModel: fallback.fallbackModel
                    )
                }
            }

            // Step 3: Both standard downgrade and smart fallback failed
            Log.warn("No suitable channel or fallback for context_length_exceeded on request \(requestID)")
            return nil
        }

        // For 429/5xx: first try same-model channel, then fallback
        if let nextChannel = compatibleChannels.first {
            requestToChannel[requestID] = nextChannel.id

            Log.info("Retrying with channel \(nextChannel.name) (retry #\(currentRetryCount + 1))")

            return RoutingDecision(
                channel: nextChannel,
                isRetry: true,
                previousChannelID: previousChannelID,
                retryCount: currentRetryCount + 1,
                originalModel: modelName,
                effectiveModel: modelName
            )
        }

        // No same-model channel available — try smart fallback
        if smartFallbackEnabled {
            let actualTokensUsed = parseActualTokensUsed(from: errorBody, modelName: modelName) ?? 0
            let protocolType = resolveRequestProtocol(requestProtocol: requestProtocol)

            if let fallback = selectFallbackModel(
                requestID: requestID,
                originalModel: modelName ?? "unknown",
                actualTokensUsed: actualTokensUsed,
                errorType: errorType,
                apiProtocol: protocolType,
                excludedChannelID: previousChannelID
            ) {
                Log.info("[INFO] SmartRouter: Fallback triggered for request \(requestID)")
                Log.info("  Original model: \(fallback.originalModel) (Channel: \(fallback.previousChannel.name), Error: \(errorType))")
                Log.info("  Fallback model: \(fallback.fallbackModel) (Channel: \(fallback.channel.name), Context: \(fallback.channel.models.first(where: { $0.identifier == fallback.fallbackModel })?.contextLength.map(formatContextLength) ?? "N/A"))")
                Log.info("  Protocol: \(protocolLabel(protocolType)) (same protocol)")
                Log.info("  Estimated cost: $\(String(format: "%.3f", fallback.estimatedCost)) (limit: $\(String(format: "%.2f", maxFallbackCost)))")
                Log.info("  Retry attempt: \(currentRetryCount + 1)/\(maxRetries)")

                requestToChannel[requestID] = fallback.channel.id

                return RoutingDecision(
                    channel: fallback.channel,
                    isRetry: true,
                    previousChannelID: previousChannelID,
                    retryCount: currentRetryCount + 1,
                    originalModel: fallback.originalModel,
                    effectiveModel: fallback.fallbackModel
                )
            }
        }

        Log.warn("No alternative channels available for retry")
        return nil
    }

    // MARK: - Smart Fallback

    /// Result of a fallback decision
    struct FallbackDecision {
        let channel: Channel
        let previousChannel: Channel
        let originalModel: String
        let fallbackModel: String
        let estimatedCost: Double
    }

    /// Select the best fallback model based on constraints
    func selectFallbackModel(
        requestID: String,
        originalModel: String,
        actualTokensUsed: Int,
        errorType: RouterErrorType,
        apiProtocol: RequestForwarder.RequestProtocol,
        excludedChannelID: String?
    ) -> FallbackDecision? {
        let channels = ChannelStore.shared.channels

        // 1. Get all channels NOT in circuit open state and NOT the excluded channel
        let availableChannels = channels.filter { channel in
            channel.id != excludedChannelID &&
                circuitBreaker.isAvailable(channelID: channel.id)
        }

        // 2. Build candidate list
        var candidates: [(channel: Channel, model: ModelEntry)] = []

        for channel in availableChannels {
            for model in channel.models where model.isEnabled {
                // Must have context length info
                guard let contextLength = model.contextLength else { continue }

                // 2a. Protocol consistency check
                let modelProtocol: RequestForwarder.RequestProtocol = switch channel.protocol {
                case .openai: .openai
                case .anthropic: .anthropic
                case .auto: .openai // .auto defaults to OpenAI
                }

                if modelProtocol != apiProtocol { continue }

                // 2b. Larger context check
                if contextLength <= actualTokensUsed { continue }

                // 2c. Cost check
                let pricePer1M = model.outputPricePer1M ?? model.inputPricePer1M ?? 0.0
                let cost = estimatedFallbackCost(
                    inputTokens: actualTokensUsed,
                    outputTokensEstimate: 5000,
                    pricePer1M: pricePer1M
                )

                if cost > maxFallbackCost { continue }

                candidates.append((channel: channel, model: model))
            }
        }

        // 3. Sort by context length descending (largest context first)
        candidates.sort { $0.model.contextLength! > $1.model.contextLength! }

        guard let best = candidates.first else {
            Log.warn("No suitable fallback model found for request \(requestID)")
            return nil
        }

        // Get the previous channel for logging
        let prevChannel = channels.first { $0.id == excludedChannelID } ?? Channel(name: "Unknown", baseURL: "")

        return FallbackDecision(
            channel: best.channel,
            previousChannel: prevChannel,
            originalModel: originalModel,
            fallbackModel: best.model.identifier,
            estimatedCost: estimatedFallbackCost(
                inputTokens: actualTokensUsed,
                outputTokensEstimate: 5000,
                pricePer1M: best.model.outputPricePer1M ?? best.model.inputPricePer1M ?? 0.0
            )
        )
    }

    /// Estimate the cost of a fallback request
    func estimatedFallbackCost(inputTokens: Int, outputTokensEstimate: Int, pricePer1M: Double) -> Double {
        return Double(inputTokens + outputTokensEstimate) * pricePer1M / 1_000_000.0
    }

    /// Parse actual tokens used from error response body
    private func parseActualTokensUsed(from body: Data?, modelName: String?) -> Int? {
        guard let body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            return estimateTokensFromModel(modelName)
        }

        // Anthropic: response.usage.input_tokens
        if let usage = json["usage"] as? [String: Any] {
            if let inputTokens = usage["input_tokens"] as? Int {
                return inputTokens
            }
            // OpenAI: response.usage.prompt_tokens
            if let promptTokens = usage["prompt_tokens"] as? Int {
                return promptTokens
            }
        }

        // Nested error body: check if usage is inside error object
        if let error = json["error"] as? [String: Any],
           let usage = error["usage"] as? [String: Any] {
            if let inputTokens = usage["input_tokens"] as? Int {
                return inputTokens
            }
            if let promptTokens = usage["prompt_tokens"] as? Int {
                return promptTokens
            }
        }

        return estimateTokensFromModel(modelName)
    }

    /// Estimate tokens based on original model's context length (fallback guess)
    private func estimateTokensFromModel(_ modelName: String?) -> Int? {
        guard let modelName else { return nil }
        let channels = ChannelStore.shared.channels
        for channel in channels {
            for model in channel.models where model.identifier == modelName || model.displayName == modelName {
                if let contextLength = model.contextLength {
                    // Use 80% of context as estimate
                    return Int(Double(contextLength) * 0.8)
                }
            }
        }
        return nil
    }

    /// Resolve the request protocol from the proxy's target protocol
    private func resolveRequestProtocol(requestProtocol: RequestForwarder.RequestProtocol?) -> RequestForwarder.RequestProtocol {
        guard let requestProtocol else { return .openai }
        return requestProtocol
    }

    /// Format context length for display
    private func formatContextLength(_ length: Int) -> String {
        if length >= 1_000_000 {
            return "\(length / 1_000_000)M tokens"
        } else if length >= 1_000 {
            return "\(length / 1_000)K tokens"
        }
        return "\(length) tokens"
    }

    /// Convert RequestProtocol to human-readable label
    private func protocolLabel(_ p: RequestForwarder.RequestProtocol) -> String {
        switch p {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .unknown: return "Unknown"
        }
    }

    /// Record a successful request for the channel (closes circuit if half-open)
    func recordSuccess(channelID: String) {
        circuitBreaker.recordSuccess(channelID: channelID)
    }

    /// Start cooldown for a channel based on error type (now uses CircuitBreaker)
    private func startCooldown(channelID: String, errorType _: RouterErrorType) {
        // CircuitBreaker handles state internally via recordFailure
        // This method is kept for backward compatibility
        circuitBreaker.recordFailure(channelID: channelID)
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
