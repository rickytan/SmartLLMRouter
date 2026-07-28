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
        let launchAtLogin = MockLaunchAtLoginManager()
        let state = AppState(defaults: defaults, launchAtLoginManager: launchAtLogin)

        XCTAssertEqual(state.port, 1897)
        XCTAssertFalse(state.showTokenSpeed)
        state.savePort(4242)
        state.savePort(0)
        state.showTokenSpeed = true
        state.completeOnboarding()

        XCTAssertEqual(state.port, 4242)
        XCTAssertTrue(state.onboardingCompleted)

        let reloaded = AppState(defaults: defaults, launchAtLoginManager: launchAtLogin)
        XCTAssertEqual(reloaded.port, 4242)
        XCTAssertTrue(reloaded.onboardingCompleted)
        XCTAssertTrue(reloaded.showTokenSpeed)
    }

    func testAppStateRegistersAndUnregistersSystemLaunchAtLogin() {
        let manager = MockLaunchAtLoginManager()
        let state = AppState(defaults: defaults, launchAtLoginManager: manager)

        XCTAssertFalse(state.launchAtLogin)

        state.setLaunchAtLogin(true)
        XCTAssertEqual(manager.registerCallCount, 1)
        XCTAssertTrue(state.launchAtLogin)
        XCTAssertFalse(state.launchAtLoginRequiresApproval)

        state.setLaunchAtLogin(false)
        XCTAssertEqual(manager.unregisterCallCount, 1)
        XCTAssertFalse(state.launchAtLogin)
    }

    func testAppStateReflectsLaunchAtLoginApprovalAndRegistrationFailure() {
        let manager = MockLaunchAtLoginManager(status: .requiresApproval)
        let state = AppState(defaults: defaults, launchAtLoginManager: manager)

        XCTAssertTrue(state.launchAtLogin)
        XCTAssertTrue(state.launchAtLoginRequiresApproval)

        manager.status = .disabled
        manager.registerError = LaunchAtLoginTestError.registrationFailed
        state.setLaunchAtLogin(true)

        XCTAssertFalse(state.launchAtLogin)
        XCTAssertFalse(state.launchAtLoginRequiresApproval)
        XCTAssertEqual(state.launchAtLoginError, "Registration failed")
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

    func testMoveChannelByIDUpdatesPriorityOrder() {
        let isolated = ChannelStoreTestSupport.makeIsolatedChannelStore(useTempFile: false)
        defer { isolated.cleanup() }

        let first = makeChannel(id: "first", name: "First", priority: 1)
        let second = makeChannel(id: "second", name: "Second", priority: 2)
        let third = makeChannel(id: "third", name: "Third", priority: 3)
        isolated.store.addChannel(first)
        isolated.store.addChannel(second)
        isolated.store.addChannel(third)

        isolated.store.moveChannel(id: "first", to: "third")

        XCTAssertEqual(isolated.store.channels.map(\.id), ["second", "third", "first"])
        XCTAssertEqual(isolated.store.channels.map(\.priority), [1, 2, 3])

        isolated.store.moveChannel(id: "first", to: "second")

        XCTAssertEqual(isolated.store.channels.map(\.id), ["first", "second", "third"])
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
        XCTAssertNil(tracker.currentTokenSpeed)
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
        XCTAssertEqual(tracker.currentTokenSpeed ?? 0, 250.0 / 1.2, accuracy: 0.001)

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
        XCTAssertEqual(tracker.currentTokenSpeed ?? 0, 200, accuracy: 0.001)
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

private final class MockLaunchAtLoginManager: LaunchAtLoginManaging {
    var status: LaunchAtLoginRegistrationStatus
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    init(status: LaunchAtLoginRegistrationStatus = .disabled) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
        if let registerError {
            throw registerError
        }
        status = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError {
            throw unregisterError
        }
        status = .disabled
    }
}

private enum LaunchAtLoginTestError: LocalizedError {
    case registrationFailed

    var errorDescription: String? {
        "Registration failed"
    }
}
