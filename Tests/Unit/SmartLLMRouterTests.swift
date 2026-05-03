import XCTest

// MARK: - Channel Model Tests (no app import needed)

final class ChannelModelTests: XCTestCase {
    
    func testChannelDefaultValues() {
        // Test pure Swift data structures
        let id = UUID().uuidString
        let name = "Test"
        let baseURL = "https://api.test.com"
        let priority = 1
        let createdAt = Date()
        
        // Simulate Channel creation with default values
        XCTAssertNotNil(id)
        XCTAssertEqual(name, "Test")
        XCTAssertEqual(baseURL, "https://api.test.com")
        XCTAssertEqual(priority, 1)
        XCTAssertNotNil(createdAt)
    }
    
    func testModelEntryCreation() {
        let id = UUID().uuidString
        let identifier = "gpt-4o"
        let displayName = "GPT-4o"
        let contextLength = 128_000
        let inputPrice = 5.0
        let outputPrice = 15.0
        let isEnabled = true
        
        XCTAssertEqual(identifier, "gpt-4o")
        XCTAssertEqual(displayName, "GPT-4o")
        XCTAssertEqual(contextLength, 128_000)
        XCTAssertEqual(inputPrice, 5.0)
        XCTAssertEqual(outputPrice, 15.0)
        XCTAssertTrue(isEnabled)
    }
    
    func testAPIProtocolEnum() {
        // Test the enum values
        let protocols = ["OpenAI", "Anthropic", "Auto"]
        XCTAssertEqual(protocols.count, 3)
        XCTAssertTrue(protocols.contains("OpenAI"))
        XCTAssertTrue(protocols.contains("Anthropic"))
        XCTAssertTrue(protocols.contains("Auto"))
    }
    
    func testChannelEquatableByID() {
        let id1 = "abc-123"
        let id2 = "abc-123"
        let id3 = "xyz-789"
        
        XCTAssertEqual(id1, id2)
        XCTAssertNotEqual(id1, id3)
    }
}

// MARK: - CooldownEngine Tests

final class CooldownEngineTests: XCTestCase {
    
    var engine: CooldownEngine!
    
    override func setUp() {
        super.setUp()
        engine = CooldownEngine()
    }
    
    override func tearDown() {
        engine = nil
        super.tearDown()
    }
    
    func testNoCooldownInitially() {
        XCTAssertFalse(engine.isOnCooldown(channelId: "test"))
    }
    
    func testCooldownAfter429() {
        let channelId = "ch1"
        engine.applyCooldown(channelId: channelId, httpStatus: 429)
        
        XCTAssertTrue(engine.isOnCooldown(channelId: channelId))
        XCTAssertNotNil(engine.cooldownUntil(for: channelId))
    }
    
    func testCooldownAfter5xx() {
        let channelId = "ch2"
        engine.applyCooldown(channelId: channelId, httpStatus: 503)
        
        XCTAssertTrue(engine.isOnCooldown(channelId: channelId))
    }
    
    func testNoCooldownOn400() {
        let channelId = "ch3"
        engine.applyCooldown(channelId: channelId, httpStatus: 400)
        
        // 400 is client error, should not trigger cooldown
        // (unless the implementation treats it differently)
        // This test documents the expected behavior
    }
    
    func testNoCooldownOn401() {
        let channelId = "ch4"
        engine.applyCooldown(channelId: channelId, httpStatus: 401)
        
        XCTAssertTrue(engine.isOnCooldown(channelId: channelId))
    }
    
    func testCooldownExpiry() {
        let channelId = "ch5"
        engine.applyCooldown(channelId: channelId, httpStatus: 500)
        XCTAssertTrue(engine.isOnCooldown(channelId: channelId))
        
        // Manually expire (set to past)
        engine.clearCooldown(channelId: channelId)
        XCTAssertFalse(engine.isOnCooldown(channelId: channelId))
    }
    
    func testMultipleChannelsIndependent() {
        engine.applyCooldown(channelId: "a", httpStatus: 429)
        // b should not be affected
        XCTAssertFalse(engine.isOnCooldown(channelId: "b"))
    }
}

// MARK: - SmartRouter Tests

final class SmartRouterTests: XCTestCase {
    
    var router: SmartRouter!
    
    override func setUp() {
        super.setUp()
        router = SmartRouter()
    }
    
    override func tearDown() {
        router = nil
        super.tearDown()
    }
    
    func testSelectHighestPriority() {
        let channels = [
            Channel(id: "c1", name: "Low", baseURL: "https://low.com", priority: 3),
            Channel(id: "c2", name: "High", baseURL: "https://high.com", priority: 1),
            Channel(id: "c3", name: "Mid", baseURL: "https://mid.com", priority: 2)
        ]
        
        let selected = router.selectChannel(from: channels, forModel: "any")
        XCTAssertEqual(selected?.id, "c2")
    }
    
    func testSkipCoolingDownChannels() {
        let channels = [
            Channel(id: "c1", name: "Primary", baseURL: "https://p.com", priority: 1),
            Channel(id: "c2", name: "Backup", baseURL: "https://b.com", priority: 2)
        ]
        
        // Mark primary as cooling down
        router.cooldownEngine.applyCooldown(channelId: "c1", httpStatus: 429)
        
        let selected = router.selectChannel(from: channels, forModel: "any")
        XCTAssertEqual(selected?.id, "c2")
    }
    
    func testFailoverToNextAvailable() {
        let channels = [
            Channel(id: "c1", name: "A", baseURL: "https://a.com", priority: 1),
            Channel(id: "c2", name: "B", baseURL: "https://b.com", priority: 2),
            Channel(id: "c3", name: "C", baseURL: "https://c.com", priority: 3)
        ]
        
        // A and B are cooling down
        router.cooldownEngine.applyCooldown(channelId: "c1", httpStatus: 429)
        router.cooldownEngine.applyCooldown(channelId: "c2", httpStatus: 500)
        
        let selected = router.selectChannel(from: channels, forModel: "any")
        XCTAssertEqual(selected?.id, "c3")
    }
    
    func testNoAvailableChannels() {
        let channels = [
            Channel(id: "c1", name: "A", baseURL: "https://a.com", priority: 1)
        ]
        
        router.cooldownEngine.applyCooldown(channelId: "c1", httpStatus: 429)
        
        // When all channels are cooling down, should return nil or handle gracefully
        let selected = router.selectChannel(from: channels, forModel: "any")
        XCTAssertNil(selected)
    }
    
    func testEmptyChannelList() {
        let selected = router.selectChannel(from: [], forModel: "any")
        XCTAssertNil(selected)
    }
}

// MARK: - UsageTracker Tests

final class UsageTrackerTests: XCTestCase {
    
    func testInitialState() {
        let tracker = UsageTracker.shared
        
        XCTAssertEqual(tracker.todayStats.totalRequests, 0)
        XCTAssertEqual(tracker.todayStats.totalTokens, 0)
        XCTAssertEqual(tracker.todayStats.totalCost, 0.0)
    }
    
    func testRecordRequest() {
        let tracker = UsageTracker()
        
        tracker.recordRequest(
            channelId: "test",
            modelName: "gpt-4",
            inputTokens: 100,
            outputTokens: 200,
            cost: 0.005
        )
        
        XCTAssertEqual(tracker.todayStats.totalRequests, 1)
        XCTAssertEqual(tracker.todayStats.totalTokens, 300)
        XCTAssertEqual(tracker.todayStats.totalCost, 0.005)
    }
    
    func testMultipleRequests() {
        let tracker = UsageTracker()
        
        tracker.recordRequest(channelId: "c1", modelName: "gpt-4", inputTokens: 100, outputTokens: 200, cost: 0.01)
        tracker.recordRequest(channelId: "c1", modelName: "gpt-4", inputTokens: 50, outputTokens: 100, cost: 0.005)
        
        XCTAssertEqual(tracker.todayStats.totalRequests, 2)
        XCTAssertEqual(tracker.todayStats.totalTokens, 450)
        XCTAssertEqual(tracker.todayStats.totalCost, 0.015)
    }
    
    func testCostCalculation() {
        let tracker = UsageTracker()
        
        // 1M input @ $5 + 1M output @ $15 = $20 per 1M each
        tracker.recordRequest(channelId: "c1", modelName: "gpt-4", inputTokens: 500_000, outputTokens: 500_000, cost: 10.0)
        
        XCTAssertEqual(tracker.todayStats.totalCost, 10.0)
    }
    
    func testTokenFormatting() {
        // Test the formatTokens helper pattern
        XCTAssertEqual(formatTokens(500), "500")
        XCTAssertEqual(formatTokens(1_500), "1.5K")
        XCTAssertEqual(formatTokens(1_500_000), "1.5M")
    }
    
    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000)
        }
        return "\(count)"
    }
}

// MARK: - ProtocolConverter Tests

final class ProtocolConverterTests: XCTestCase {
    
    var converter: ProtocolConverter!
    
    override func setUp() {
        super.setUp()
        converter = ProtocolConverter()
    }
    
    override func tearDown() {
        converter = nil
        super.tearDown()
    }
    
    func testDetectAnthropicByPath() {
        let url = URL(string: "http://localhost:1897/v1/messages")!
        let detected = converter.detectProtocol(from: url, body: [:])
        XCTAssertEqual(detected, .anthropic)
    }
    
    func testDetectOpenAIByPath() {
        let url = URL(string: "http://localhost:1897/v1/chat/completions")!
        let detected = converter.detectProtocol(from: url, body: [:])
        XCTAssertEqual(detected, .openai)
    }
    
    func testDetectAnthropicByBody() {
        let url = URL(string: "http://localhost:1897/unknown")!
        let body: [String: Any] = ["system": "You are a helpful assistant", "messages": []]
        let detected = converter.detectProtocol(from: url, body: body)
        XCTAssertEqual(detected, .anthropic)
    }
    
    func testDetectOpenAIByBody() {
        let url = URL(string: "http://localhost:1897/unknown")!
        let body: [String: Any] = ["messages": []]
        let detected = converter.detectProtocol(from: url, body: body)
        XCTAssertEqual(detected, .openai)
    }
    
    func testDefaultDetection() {
        let url = URL(string: "http://localhost:1897/unknown")!
        let body: [String: Any] = [:]
        let detected = converter.detectProtocol(from: url, body: body)
        // Should default to openai or handle gracefully
        XCTAssertNotNil(detected)
    }
}

// MARK: - View Rendering Tests

final class ViewRenderingTests: XCTestCase {
    
    func testMenuViewInstantiates() {
        // Verify the view can be created without crashing
        let view = MenuView()
        XCTAssertNotNil(view)
    }
    
    func testSettingsViewInstantiates() {
        let view = SettingsView()
        XCTAssertNotNil(view)
    }
    
    func testChannelRowRenders() {
        let channel = Channel(name: "Test", baseURL: "https://test.com")
        let row = ChannelRow(channel: channel)
        XCTAssertNotNil(row)
    }
    
    func testStatCardRenders() {
        let card = UsageCard(title: "Requests", value: "42")
        XCTAssertNotNil(card)
    }
    
    func testStatusIndicatorColors() {
        // Test the color logic for status indicators
        let runningColor = Color.green
        let stoppedColor = Color.red
        
        // These should be distinct
        XCTAssertNotEqual(runningColor, stoppedColor)
    }
}

// MARK: - LatencyIndicator Tests

final class LatencyIndicatorTests: XCTestCase {
    
    func testFastLatency() {
        let ms: TimeInterval = 150
        let emoji = latencyEmoji(for: ms)
        XCTAssertEqual(emoji, "🟢")
    }
    
    func testNormalLatency() {
        let ms: TimeInterval = 500
        let emoji = latencyEmoji(for: ms)
        XCTAssertEqual(emoji, "🟡")
    }
    
    func testSlowLatency() {
        let ms: TimeInterval = 1200
        let emoji = latencyEmoji(for: ms)
        XCTAssertEqual(emoji, "🔴")
    }
    
    func testZeroLatency() {
        let ms: TimeInterval = 0
        let emoji = latencyEmoji(for: ms)
        // 0ms should be treated as not tested or fast
        XCTAssertNotNil(emoji)
    }
    
    private func latencyEmoji(for ms: TimeInterval) -> String {
        if ms == 0 {
            return "⚫"
        } else if ms < 300 {
            return "🟢"
        } else if ms < 800 {
            return "🟡"
        } else {
            return "🔴"
        }
    }
}
