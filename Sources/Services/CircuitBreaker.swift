import Foundation

// MARK: - Circuit Breaker State

/// State machine for the circuit breaker pattern
enum CircuitState: Equatable {
    /// Normal operation — requests pass through
    case closed
    /// Channel is tripped — requests are rejected immediately
    case open(until: Date)
    /// Testing recovery — allows one probe request
    case halfOpen

    var label: String {
        switch self {
        case .closed: "Closed"
        case .open: "Open"
        case .halfOpen: "Half-Open"
        }
    }
}

// MARK: - Circuit Breaker

/// Circuit breaker that tracks consecutive failures and failure rates per channel.
/// Replaces the simple CooldownEngine with a more robust state machine.
/// Thread-safe via internal serial queue.
final class CircuitBreaker {
    // Configuration
    private let consecutiveFailureThreshold: Int
    private let failureRateThreshold: Double
    private let rollingWindowSize: Int
    private let openTimeout: TimeInterval

    // Per-channel state
    private var states: [String: CircuitState] = [:]
    private var consecutiveFailures: [String: Int] = [:]
    private var requestHistory: [String: [Bool]] = [:] // true = success, false = failure

    // Lock for thread safety
    private let lock = NSRecursiveLock()

    init(
        consecutiveFailureThreshold: Int = 5,
        failureRateThreshold: Double = 0.6,
        rollingWindowSize: Int = 10,
        openTimeout: TimeInterval = 60.0
    ) {
        self.consecutiveFailureThreshold = consecutiveFailureThreshold
        self.failureRateThreshold = failureRateThreshold
        self.rollingWindowSize = rollingWindowSize
        self.openTimeout = openTimeout
    }

    // MARK: - Public API

    /// Check if a channel is available (circuit not open)
    func isAvailable(channelID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let state = states[channelID] else {
            return true // No history = closed
        }

        switch state {
        case .closed:
            return true
        case .open(let until):
            if Date() >= until {
                // Timeout expired — transition to half-open
                states[channelID] = .halfOpen
                Log.info("[CircuitBreaker] Channel \\(channelID) transitioned to Half-Open (recovery test)")
                return true // Allow probe request
            }
            return false
        case .halfOpen:
            return true // Allow one probe request
        }
    }

    /// Record a successful request
    func recordSuccess(channelID: String) {
        lock.lock()
        defer { lock.unlock() }

        let currentState = states[channelID] ?? .closed

        switch currentState {
        case .closed:
            resetFailures(for: channelID)
        case .open:
            // Success during open state (shouldn't happen normally since we block)
            break
        case .halfOpen:
            // Success in half-open — close the circuit!
            states[channelID] = .closed
            resetFailures(for: channelID)
            Log.info("[CircuitBreaker] Channel \\(channelID) recovered — circuit Closed")
        }
    }

    /// Record a failed request. Returns the new state.
    @discardableResult
    func recordFailure(channelID: String) -> CircuitState {
        lock.lock()
        defer { lock.unlock() }

        let currentState = states[channelID] ?? .closed

        switch currentState {
        case .closed:
            // Track failure
            let failures = (consecutiveFailures[channelID] ?? 0) + 1
            consecutiveFailures[channelID] = failures

            // Add to rolling window
            var history = requestHistory[channelID] ?? []
            history.append(false) // false = failure
            if history.count > rollingWindowSize {
                history.removeFirst(history.count - rollingWindowSize)
            }
            requestHistory[channelID] = history

            // Check if we should trip
            if shouldTrip(consecutiveFailures: failures, history: history) {
                let until = Date().addingTimeInterval(openTimeout)
                states[channelID] = .open(until: until)
                Log.warn("[CircuitBreaker] Channel \\(channelID) tripped — circuit Open (until \\(formatTime(until)))")
                return .open(until: until)
            }
            return .closed

        case .open:
            // Shouldn't get failures while open (requests are blocked)
            // But if it happens (e.g., half-open probe), reset timeout
            let until = Date().addingTimeInterval(openTimeout)
            states[channelID] = .open(until: until)
            Log.warn("[CircuitBreaker] Channel \\(channelID) probe failed — circuit remains Open")
            return .open(until: until)

        case .halfOpen:
            // Probe failed — reopen with fresh timeout
            let until = Date().addingTimeInterval(openTimeout)
            states[channelID] = .open(until: until)
            Log.warn("[CircuitBreaker] Channel \\(channelID) recovery failed — circuit re-Opened")
            return .open(until: until)
        }
    }

    /// Manually reset circuit for a channel (e.g., user intervention)
    func reset(channelID: String) {
        lock.lock()
        defer { lock.unlock() }
        resetFailuresLocked(for: channelID)
        states[channelID] = .closed
        Log.info("[CircuitBreaker] Channel \\(channelID) manually reset — circuit Closed")
    }

    /// Get current state for a channel
    func state(for channelID: String) -> CircuitState {
        lock.lock()
        defer { lock.unlock() }
        return states[channelID] ?? .closed
    }

    /// Get remaining open timeout (0 if not open)
    func remainingOpenTime(channelID: String) -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }

        guard case .open(let until) = states[channelID] else {
            return 0
        }
        return max(0, until.timeIntervalSince(Date()))
    }

    /// Get all channel states for UI display
    func allStates() -> [String: CircuitState] {
        lock.lock()
        defer { lock.unlock() }
        return states
    }

    // MARK: - Private

    private func shouldTrip(consecutiveFailures: Int, history: [Bool]) -> Bool {
        // Trip on consecutive failures
        if consecutiveFailures >= consecutiveFailureThreshold {
            return true
        }

        // Trip on failure rate in rolling window
        if history.count >= rollingWindowSize {
            let failureCount = history.filter { !$0 }.count
            let rate = Double(failureCount) / Double(history.count)
            if rate >= failureRateThreshold {
                return true
            }
        }

        return false
    }

    private func resetFailures(for channelID: String) {
        resetFailuresLocked(for: channelID)
    }

    private func resetFailuresLocked(for channelID: String) {
        consecutiveFailures[channelID] = 0
        requestHistory[channelID] = []
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
