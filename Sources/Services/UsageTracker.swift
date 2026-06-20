import Foundation
import Combine

// MARK: - UsageRecord

/// Tracks token usage and estimated costs per channel
struct UsageRecord: Codable {
    let timestamp: Date
    let channelID: String
    let channelName: String
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let totalTokens: Int
    let estimatedCost: Double // in USD
    let latency: TimeInterval // ms
    let statusCode: Int
    let isError: Bool
}

// MARK: - UsageStats

/// Aggregated usage statistics
struct UsageStats {
    let totalRequests: Int
    let totalInputTokens: Int
    let totalOutputTokens: Int
    let totalTokens: Int
    let totalCost: Double
    let averageLatency: TimeInterval
    let errorRate: Double
}

// MARK: - UsageTracker

/// Tracks API usage records with thread-safe access.
/// All @Published updates are dispatched to main thread to avoid background-publish warnings.
final class UsageTracker: ObservableObject {
    static let shared = UsageTracker()

    @Published private(set) var records: [UsageRecord] = []
    @Published private(set) var todayStats = UsageStats.zero
    @Published private(set) var weekStats = UsageStats.zero
    @Published private(set) var monthStats = UsageStats.zero

    private let userDefaultsKey = "smartllm_router_usage_records"
    private let maxRecordsCount = 10000
    /// Serial queue for thread-safe record mutations
    private let queue = DispatchQueue(label: "cn.rickytan.smartLLMRouter.usage-tracker", qos: .utility)

    init() {
        loadRecords()
    }

    // MARK: - Public API (thread-safe, can be called from any thread)

    func recordUsage(
        channelID: String,
        channelName: String,
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        estimatedCost: Double,
        latency: TimeInterval,
        statusCode: Int,
        isError: Bool
    ) {
        let record = UsageRecord(
            timestamp: Date(),
            channelID: channelID,
            channelName: channelName,
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            totalTokens: inputTokens + outputTokens,
            estimatedCost: estimatedCost,
            latency: latency,
            statusCode: statusCode,
            isError: isError
        )

        queue.async { [weak self] in
            guard let self else { return }
            // Work with local copy inside the queue — never touch @Published from background
            var localRecords = self.records
            localRecords.append(record)

            // Trim old records
            if localRecords.count > self.maxRecordsCount {
                localRecords.removeFirst(localRecords.count - self.maxRecordsCount)
            }

            self.saveRecords(Array(localRecords))
            let stats = self.computeStats(from: localRecords)

            DispatchQueue.main.async {
                self.records = localRecords
                self.todayStats = stats.today
                self.weekStats = stats.week
                self.monthStats = stats.month
            }
        }
    }

    func clearHistory() {
        queue.async { [weak self] in
            guard let self else { return }
            self.saveRecords([])

            DispatchQueue.main.async {
                self.records = []
                self.todayStats = .zero
                self.weekStats = .zero
                self.monthStats = .zero
            }
        }
    }

    // MARK: - Private

    private func loadRecords() {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                guard let data = UserDefaults.standard.data(forKey: self.userDefaultsKey) else {
                    return
                }
                let decoded = try JSONDecoder().decode([UsageRecord].self, from: data)
                let stats = self.computeStats(from: decoded)

                DispatchQueue.main.async {
                    self.records = decoded
                    self.todayStats = stats.today
                    self.weekStats = stats.week
                    self.monthStats = stats.month
                }
                Log.debug("Loaded \(decoded.count) usage records")
            } catch {
                Log.error("Failed to load usage records: \(error.localizedDescription)")
            }
        }
    }

    private func saveRecords(_ records: [UsageRecord]) {
        do {
            let encoded = try JSONEncoder().encode(records)
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        } catch {
            Log.error("Failed to save usage records: \(error.localizedDescription)")
        }
    }

    private func computeStats(from allRecords: [UsageRecord]) -> (today: UsageStats, week: UsageStats, month: UsageStats) {
        let calendar = Calendar.current
        let now = Date()

        let todayStart = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -7, to: now)!
        let monthStart = calendar.date(byAdding: .month, value: -1, to: now)!

        return (
            today: computeStats(for: allRecords.filter { $0.timestamp >= todayStart }),
            week: computeStats(for: allRecords.filter { $0.timestamp >= weekStart }),
            month: computeStats(for: allRecords.filter { $0.timestamp >= monthStart })
        )
    }

    private func computeStats(for subset: [UsageRecord]) -> UsageStats {
        guard !subset.isEmpty else { return .zero }

        let totalRequests = subset.count
        let totalInput = subset.reduce(0) { $0 + $1.inputTokens }
        let totalOutput = subset.reduce(0) { $0 + $1.outputTokens }
        let totalCost = subset.reduce(0.0) { $0 + $1.estimatedCost }
        let totalLatency = subset.reduce(0.0) { $0 + $1.latency }
        let errors = subset.filter(\.isError).count

        return UsageStats(
            totalRequests: totalRequests,
            totalInputTokens: totalInput,
            totalOutputTokens: totalOutput,
            totalTokens: totalInput + totalOutput,
            totalCost: totalCost,
            averageLatency: totalLatency / Double(totalRequests),
            errorRate: Double(errors) / Double(totalRequests)
        )
    }
}

extension UsageStats {
    static let zero = UsageStats(
        totalRequests: 0,
        totalInputTokens: 0,
        totalOutputTokens: 0,
        totalTokens: 0,
        totalCost: 0.0,
        averageLatency: 0,
        errorRate: 0
    )
}
