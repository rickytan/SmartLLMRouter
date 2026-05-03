import XCTest
import SwiftUI

// MARK: - Channel Model Tests

final class ChannelModelTests: XCTestCase {
    
    func testChannelDefaultValues() {
        let channel = ChannelTest(name: "Test", baseURL: "https://api.test.com")
        
        XCTAssertEqual(channel.priority, 1)
        XCTAssertEqual(channel.protocol, .auto)
        XCTAssertTrue(channel.models.isEmpty)
        XCTAssertFalse(channel.isCoolingDown)
        XCTAssertNil(channel.cooldownUntil)
        XCTAssertEqual(channel.lastLatencyMs, 0.0)
    }
    
    func testChannelEquatable() {
        let c1 = ChannelTest(id: "abc", name: "A", baseURL: "https://a.com")
        let c2 = ChannelTest(id: "abc", name: "B", baseURL: "https://b.com")
        let c3 = ChannelTest(id: "xyz", name: "A", baseURL: "https://a.com")
        
        XCTAssertEqual(c1, c2)
        XCTAssertNotEqual(c1, c3)
    }
    
    func testModelEntryCreation() {
        let model = ModelEntryTest(
            id: "m1",
            identifier: "gpt-4o",
            displayName: "GPT-4o",
            contextLength: 128_000,
            inputPricePer1M: 5.0,
            outputPricePer1M: 15.0,
            isEnabled: true
        )
        
        XCTAssertEqual(model.identifier, "gpt-4o")
        XCTAssertEqual(model.contextLength, 128_000)
        XCTAssertEqual(model.inputPricePer1M, 5.0)
        XCTAssertTrue(model.isEnabled)
    }
    
    func testAPIProtocolEnum() {
        XCTAssertEqual(APIProtocolTest.openai.rawValue, "OpenAI")
        XCTAssertEqual(APIProtocolTest.anthropic.rawValue, "Anthropic")
        XCTAssertEqual(APIProtocolTest.allCases.count, 3)
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
    
    private func latencyEmoji(for ms: TimeInterval) -> String {
        if ms < 300 { return "🟢" }
        else if ms < 800 { return "🟡" }
        else { return "🔴" }
    }
}

// MARK: - Color Tests

final class ColorTests: XCTestCase {
    func testStatusColors() {
        let green = Color.green
        let red = Color.red
        XCTAssertNotEqual(green, red)
    }
}
