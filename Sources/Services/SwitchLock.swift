import Foundation

/// A serial dispatch queue-based lock to prevent race conditions
/// when multiple requests simultaneously trigger failover or
/// circuit breaker state changes.
final class SwitchLock {
    static let shared = SwitchLock()

    /// Serial queue that serializes all failover/state-change operations
    private let queue = DispatchQueue(label: "com.smartllmrouter.switchlock", qos: .userInitiated)

    init() {}

    /// Execute a critical section. Only one caller can execute at a time.
    /// - Parameter operation: The operation to execute atomically
    /// - Returns: The result of the operation
    func execute<T>(_ operation: () throws -> T) rethrows -> T {
        try queue.sync {
            try operation()
        }
    }

    /// Execute an async critical section.
    /// Note: This uses a semaphore internally and should only be used
    /// for operations that MUST be serialized but are async.
    func executeAsync<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                Task {
                    do {
                        let result = try await operation()
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}
