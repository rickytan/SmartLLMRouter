import Foundation

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

@MainActor
final class UsageTracker: ObservableObject {
    static let shared = UsageTracker()

    @Published private(set) var records: [UsageRecord] = []
    @Published private(set) var todayStats = UsageStats.zero
    @Published private(set) var weekStats = UsageStats.zero
    @Published private(set) var monthStats = UsageStats.zero

    private let userDefaultsKey = "smartllm_router_usage_records"
    private let maxRecordsCount = 10000

    private init() {
        loadRecords()
        computeStats()
    }

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

        records.append(record)

        // Trim old records
        if records.count > maxRecordsCount {
            records.removeFirst(records.count - maxRecordsCount)
        }

        saveRecords()
        computeStats()
    }

    func clearHistory() {
        records.removeAll()
        saveRecords()
        computeStats()
    }

    // MARK: - Private

    private func loadRecords() {
        do {
            guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
                records = []
                return
            }
            records = try JSONDecoder().decode([UsageRecord].self, from: data)
            Log.debug("Loaded \(records.count) usage records")
        } catch {
            Log.error("Failed to load usage records: \(error.localizedDescription)")
            records = []
        }
    }

    private func saveRecords() {
        do {
            let encoded = try JSONEncoder().encode(records)
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        } catch {
            Log.error("Failed to save usage records: \(error.localizedDescription)")
        }
    }

    private func computeStats() {
        let calendar = Calendar.current
        let now = Date()

        let todayStart = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -7, to: now)!
        let monthStart = calendar.date(byAdding: .month, value: -1, to: now)!

        todayStats = computeStats(for: records.filter { $0.timestamp >= todayStart })
        weekStats = computeStats(for: records.filter { $0.timestamp >= weekStart })
        monthStats = computeStats(for: records.filter { $0.timestamp >= monthStart })
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
