import Foundation

final class RequestIDGenerator {
    private var requestCount: Int64 = 0
    private let lock = NSLock()

    func next() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        requestCount += 1
        return requestCount
    }
}
