import XCTest
@testable import SmartLLMRouter

@MainActor
final class ServiceStateTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "ServiceStateTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    func testAppStatePersistsValidatedSettings() {
        let state = AppState(defaults: defaults)

        XCTAssertEqual(state.port, 1897)
        state.savePort(4242)
        state.savePort(0)
        state.toggleLaunchAtLogin()
        state.completeOnboarding()

        XCTAssertEqual(state.port, 4242)
        XCTAssertTrue(state.launchAtLogin)
        XCTAssertTrue(state.onboardingCompleted)

        let reloaded = AppState(defaults: defaults)
        XCTAssertEqual(reloaded.port, 4242)
        XCTAssertTrue(reloaded.launchAtLogin)
        XCTAssertTrue(reloaded.onboardingCompleted)
    }

    func testCooldownEnginePersistsInChannelStoreInjectedDefaults() {
        let isolated = ChannelStoreTestSupport.makeIsolatedChannelStore(useTempFile: false)
        defer { isolated.cleanup() }
        let channelID = "cooldown-channel"

        let firstEngine = CooldownEngine(channelStore: isolated.store)
        firstEngine.startCooldown(channelID: channelID, duration: 120, reason: "test")
        let reloadedEngine = CooldownEngine(channelStore: isolated.store)

        XCTAssertTrue(reloadedEngine.isCoolingDown(channelID: channelID))
        XCTAssertEqual(reloadedEngine.cooldownReason(channelID: channelID), "test")
    }

    func testDisablingActiveChannelMovesSelectionAndInvalidatesDependentState() {
        let isolated = ChannelStoreTestSupport.makeIsolatedChannelStore(useTempFile: false)
        defer { isolated.cleanup() }

        let first = makeChannel(id: "first", name: "First", priority: 1)
        let second = makeChannel(id: "second", name: "Second", priority: 2)
        isolated.store.addChannel(first)
        isolated.store.addChannel(second)

        var invalidated = 0
        var validated = 0
        isolated.store.invalidateModelCache = { invalidated += 1 }
        isolated.store.validateModelSelection = { validated += 1 }

        isolated.store.setChannelEnabled(id: first.id, isEnabled: false)

        XCTAssertEqual(isolated.store.activeChannelID, second.id)
        XCTAssertEqual(isolated.store.enabledChannels.map(\.id), [second.id])
        XCTAssertEqual(invalidated, 1)
        XCTAssertEqual(validated, 1)

        isolated.store.setActiveChannel(id: first.id)
        XCTAssertEqual(isolated.store.activeChannelID, second.id)
    }

    func testSortChannelsByLatencyPrioritizesMeasuredFastestChannels() {
        let isolated = ChannelStoreTestSupport.makeIsolatedChannelStore(useTempFile: false)
        defer { isolated.cleanup() }

        var unmeasured = makeChannel(id: "unmeasured", name: "Unmeasured", priority: 1)
        unmeasured.lastLatencyMs = 0
        var slow = makeChannel(id: "slow", name: "Slow", priority: 2)
        slow.lastLatencyMs = 800
        var fast = makeChannel(id: "fast", name: "Fast", priority: 3)
        fast.lastLatencyMs = 42

        isolated.store.addChannel(unmeasured)
        isolated.store.addChannel(slow)
        isolated.store.addChannel(fast)

        isolated.store.sortChannelsByLatency()

        XCTAssertEqual(isolated.store.channels.map(\.id), ["fast", "slow", "unmeasured"])
        XCTAssertEqual(isolated.store.channels.map(\.priority), [1, 2, 3])
    }

    func testModelSwitcherExcludesDisabledChannelsAndClearsInvalidSelection() {
        let isolatedStore = ChannelStoreTestSupport.makeIsolatedChannelStore(useTempFile: false)
        let isolatedKeychain = KeychainManagerTestSupport.makeIsolatedKeychainManager()
        defer {
            isolatedStore.cleanup()
            isolatedKeychain.cleanup()
        }

        let alpha = ModelEntry(id: "alpha", identifier: "alpha", displayName: "Alpha")
        let beta = ModelEntry(id: "beta", identifier: "beta", displayName: "Beta")
        let first = makeChannel(id: "first", name: "First", priority: 1, models: [alpha])
        let second = makeChannel(id: "second", name: "Second", priority: 2, models: [beta])
        isolatedStore.store.addChannel(first)
        isolatedStore.store.addChannel(second)

        let services = ChannelServices(
            store: isolatedStore.store,
            keychain: isolatedKeychain.manager,
            cooldownEngine: CooldownEngine(channelStore: isolatedStore.store)
        )
        let switcher = ModelSwitcher(
            channelServices: services,
            modelOverrideState: ModelOverrideRuntimeState(),
            defaults: defaults
        )

        XCTAssertEqual(switcher.compatibleModels.map(\.identifier), ["alpha", "beta"])
        switcher.selectModel("beta")

        isolatedStore.store.setChannelEnabled(id: second.id, isEnabled: false)
        switcher.validateSelection()

        XCTAssertEqual(switcher.compatibleModels.map(\.identifier), ["alpha"])
        XCTAssertNil(switcher.selectedModelID)
        XCTAssertNil(defaults.string(forKey: "smartllm_selected_model"))
    }

    func testUsageTrackerWritesStatsAndClearsHistoryInInjectedDefaults() async throws {
        let tracker = UsageTracker(defaults: defaults)
        tracker.recordUsage(
            channelID: "first",
            channelName: "First",
            model: "alpha",
            inputTokens: 10,
            outputTokens: 20,
            estimatedCost: 0.01,
            latency: 100,
            statusCode: 200,
            isError: false
        )
        tracker.recordUsage(
            channelID: "second",
            channelName: "Second",
            model: "beta",
            inputTokens: 30,
            outputTokens: 40,
            estimatedCost: 0.02,
            latency: 300,
            statusCode: 500,
            isError: true
        )

        try await waitUntil { tracker.records.count == 2 }
        XCTAssertEqual(tracker.todayStats.totalRequests, 2)
        XCTAssertEqual(tracker.todayStats.totalTokens, 100)
        XCTAssertEqual(tracker.todayStats.totalCost, 0.03, accuracy: 0.000_001)
        XCTAssertEqual(tracker.todayStats.averageLatency, 200, accuracy: 0.000_001)
        XCTAssertEqual(tracker.todayStats.errorRate, 0.5, accuracy: 0.000_001)

        tracker.clearHistory()
        try await waitUntil { tracker.records.isEmpty }
        XCTAssertEqual(tracker.monthStats.totalRequests, 0)
    }

    func testUsageTrackerIncludesInFlightUsageInStatsWithoutPersistingIt() async throws {
        let tracker = UsageTracker(defaults: defaults)

        tracker.updateInFlightUsage(
            requestID: "req-stream",
            channelID: "stream",
            channelName: "Stream",
            model: "glm-5.2",
            inputTokens: 100,
            outputTokens: 250,
            estimatedCost: 0.03,
            latency: 1_200
        )

        try await waitUntil { tracker.displayRecords.count == 1 }
        XCTAssertTrue(tracker.records.isEmpty)
        XCTAssertEqual(tracker.todayStats.totalRequests, 1)
        XCTAssertEqual(tracker.todayStats.totalInputTokens, 100)
        XCTAssertEqual(tracker.todayStats.totalOutputTokens, 250)

        let reloaded = UsageTracker(defaults: defaults)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(reloaded.records.isEmpty)
        XCTAssertTrue(reloaded.displayRecords.isEmpty)
    }

    func testUsageTrackerReplacesInFlightUsageWithFinalRecord() async throws {
        let tracker = UsageTracker(defaults: defaults)

        tracker.updateInFlightUsage(
            requestID: "req-stream",
            channelID: "stream",
            channelName: "Stream",
            model: "glm-5.2",
            inputTokens: 100,
            outputTokens: 250,
            estimatedCost: 0.03,
            latency: 1_200
        )
        try await waitUntil { tracker.displayRecords.count == 1 }

        tracker.recordUsage(
            requestID: "req-stream",
            channelID: "stream",
            channelName: "Stream",
            model: "glm-5.2",
            inputTokens: 120,
            outputTokens: 300,
            estimatedCost: 0.04,
            latency: 1_500,
            statusCode: 200,
            isError: false
        )

        try await waitUntil { tracker.records.count == 1 && tracker.displayRecords.count == 1 }
        XCTAssertEqual(tracker.records.first?.inputTokens, 120)
        XCTAssertEqual(tracker.records.first?.outputTokens, 300)
        XCTAssertEqual(tracker.todayStats.totalRequests, 1)
        XCTAssertEqual(tracker.todayStats.totalTokens, 420)
    }

    private func makeChannel(
        id: String,
        name: String,
        priority: Int,
        models: [ModelEntry] = []
    ) -> Channel {
        Channel(
            id: id,
            name: name,
            baseURL: "https://\(id).example.com",
            priority: priority,
            protocol: .openai,
            models: models
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timed out waiting for asynchronous state")
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
