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
    @Published private(set) var records: [UsageRecord] = []
    @Published private(set) var displayRecords: [UsageRecord] = []
    @Published private(set) var todayStats = UsageStats.zero
    @Published private(set) var weekStats = UsageStats.zero
    @Published private(set) var monthStats = UsageStats.zero

    private let userDefaultsKey = "smartllm_router_usage_records"
    private let maxRecordsCount = 10000
    private let defaults: UserDefaults
    /// Serial queue for thread-safe record mutations
    private let queue = DispatchQueue(label: "cn.rickytan.smartLLMRouter.usage-tracker", qos: .utility)
    /// Source of truth for mutations. `records` is a main-thread UI projection
    /// and may lag behind this queue while multiple requests complete quickly.
    private var storedRecords: [UsageRecord] = []
    private var inFlightRecords: [String: UsageRecord] = [:]

    private struct Projection {
        let records: [UsageRecord]
        let displayRecords: [UsageRecord]
        let today: UsageStats
        let week: UsageStats
        let month: UsageStats
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadRecords()
    }

    // MARK: - Public API (thread-safe, can be called from any thread)

    func recordUsage(
        requestID: String? = nil,
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
            var localRecords = self.storedRecords
            localRecords.append(record)

            // Trim old records
            if localRecords.count > self.maxRecordsCount {
                localRecords.removeFirst(localRecords.count - self.maxRecordsCount)
            }

            self.storedRecords = localRecords
            if let requestID {
                self.inFlightRecords.removeValue(forKey: requestID)
            }
            self.saveRecords(localRecords)
            let projection = self.computeProjection(records: localRecords, inFlight: self.inFlightRecords)

            DispatchQueue.main.async {
                self.publishProjection(projection)
            }
        }
    }

    func updateInFlightUsage(
        requestID: String,
        channelID: String,
        channelName: String,
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        estimatedCost: Double,
        latency: TimeInterval,
        statusCode: Int = 200,
        isError: Bool = false
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            let timestamp = self.inFlightRecords[requestID]?.timestamp ?? Date()
            self.inFlightRecords[requestID] = UsageRecord(
                timestamp: timestamp,
                channelID: channelID,
                channelName: channelName,
                model: model,
                inputTokens: max(0, inputTokens),
                outputTokens: max(0, outputTokens),
                totalTokens: max(0, inputTokens) + max(0, outputTokens),
                estimatedCost: max(0, estimatedCost),
                latency: max(0, latency),
                statusCode: statusCode,
                isError: isError
            )

            let projection = self.computeProjection(records: self.storedRecords, inFlight: self.inFlightRecords)
            DispatchQueue.main.async {
                self.publishProjection(projection)
            }
        }
    }

    func finishInFlightUsage(requestID: String) {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.inFlightRecords.removeValue(forKey: requestID) != nil else { return }

            let projection = self.computeProjection(records: self.storedRecords, inFlight: self.inFlightRecords)
            DispatchQueue.main.async {
                self.publishProjection(projection)
            }
        }
    }

    func clearHistory() {
        queue.async { [weak self] in
            guard let self else { return }
            self.storedRecords = []
            self.inFlightRecords = [:]
            self.saveRecords([])
            let projection = self.computeProjection(records: [], inFlight: [:])

            DispatchQueue.main.async {
                self.publishProjection(projection)
            }
        }
    }

    // MARK: - Private

    private func loadRecords() {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                guard let data = self.defaults.data(forKey: self.userDefaultsKey) else {
                    return
                }
                let decoded = try JSONDecoder().decode([UsageRecord].self, from: data)
                self.storedRecords = decoded
                let projection = self.computeProjection(records: decoded, inFlight: self.inFlightRecords)

                DispatchQueue.main.async {
                    self.publishProjection(projection)
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
            defaults.set(encoded, forKey: userDefaultsKey)
        } catch {
            Log.error("Failed to save usage records: \(error.localizedDescription)")
        }
    }

    private func computeProjection(
        records: [UsageRecord],
        inFlight: [String: UsageRecord]
    ) -> Projection {
        let displayRecords = records + inFlight.values.sorted { $0.timestamp < $1.timestamp }
        let stats = computeStats(from: displayRecords)
        return Projection(
            records: records,
            displayRecords: displayRecords,
            today: stats.today,
            week: stats.week,
            month: stats.month
        )
    }

    @MainActor
    private func publishProjection(_ projection: Projection) {
        records = projection.records
        displayRecords = projection.displayRecords
        todayStats = projection.today
        weekStats = projection.week
        monthStats = projection.month
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
