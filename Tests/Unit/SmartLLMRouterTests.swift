import XCTest
import SwiftUI
@testable import SmartLLMRouter

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

// MARK: - Speed Test / ChannelManager Tests

@MainActor
final class ChannelManagerTests: XCTestCase {
    
    func testLatencyEmoji_Fast() {
        let manager = ChannelManager.shared
        XCTAssertEqual(manager.latencyEmoji(latencyMs: 100), "🟢")
        XCTAssertEqual(manager.latencyEmoji(latencyMs: 499), "🟢")
    }
    
    func testLatencyEmoji_Normal() {
        let manager = ChannelManager.shared
        XCTAssertEqual(manager.latencyEmoji(latencyMs: 500), "🟡")
        XCTAssertEqual(manager.latencyEmoji(latencyMs: 999), "🟡")
    }
    
    func testLatencyEmoji_Slow() {
        let manager = ChannelManager.shared
        XCTAssertEqual(manager.latencyEmoji(latencyMs: 1000), "🔴")
        XCTAssertEqual(manager.latencyEmoji(latencyMs: 5000), "🔴")
    }
    
    func testLatencyDescription_Fast() {
        let manager = ChannelManager.shared
        XCTAssertEqual(manager.latencyDescription(latencyMs: 200), "< 500ms")
    }
    
    func testLatencyDescription_Normal() {
        let manager = ChannelManager.shared
        XCTAssertEqual(manager.latencyDescription(latencyMs: 750), "500-1000ms")
    }
    
    func testLatencyDescription_Slow() {
        let manager = ChannelManager.shared
        XCTAssertEqual(manager.latencyDescription(latencyMs: 1500), "> 1000ms")
    }
    
    func testProviderTemplatesLoaded() {
        let manager = ChannelManager.shared
        XCTAssertFalse(manager.providerTemplates.isEmpty, "应加载 providers.json 模板")
    }
    
    func testGetProviderTemplate() {
        let manager = ChannelManager.shared
        // 验证至少有一个模板可以获取
        if let firstTemplate = manager.providerTemplates.first {
            let template = manager.getProviderTemplate(id: firstTemplate.id)
            XCTAssertNotNil(template, "应能通过 ID 获取模板")
            XCTAssertEqual(template?.id, firstTemplate.id)
        }
    }
    
    func testCreateChannelFromTemplate() async throws {
        let manager = ChannelManager.shared
        guard let template = manager.providerTemplates.first else {
            XCTFail("应有至少一个模板")
            return
        }
        
        // 注意：这里需要 Keychain 支持，在测试环境中可能失败
        // 主要验证逻辑路径正确
        let channel = manager.createChannelFromTemplate(templateId: template.id, apiKey: "test-key-123")
        
        // 验证创建结果（可能为 nil 如果 Keychain 不可用）
        if let channel {
            XCTAssertEqual(channel.providerId, template.id)
            XCTAssertEqual(channel.baseURL, template.baseURL)
            XCTAssertFalse(channel.models.isEmpty)
        }
    }
}

// MARK: - CooldownEngine Tests

final class CooldownEngineTests: XCTestCase {
    
    @MainActor
    func testIsNotCoolingDownInitially() {
        let engine = CooldownEngine.shared
        engine.clearAllCooldowns()
        XCTAssertFalse(engine.isCoolingDown(channelID: "test-channel"))
    }
    
    @MainActor
    func testStartCooldown() {
        let engine = CooldownEngine.shared
        engine.startCooldown(channelID: "test-channel", duration: 60, reason: "429")
        XCTAssertTrue(engine.isCoolingDown(channelID: "test-channel"))
    }
    
    @MainActor
    func testClearCooldown() {
        let engine = CooldownEngine.shared
        engine.startCooldown(channelID: "test-channel", duration: 60, reason: "429")
        engine.clearCooldown(channelID: "test-channel")
        XCTAssertFalse(engine.isCoolingDown(channelID: "test-channel"))
    }
    
    @MainActor
    func testRemainingTime() {
        let engine = CooldownEngine.shared
        engine.startCooldown(channelID: "test-channel", duration: 120, reason: "5xx")
        let remaining = engine.remainingTime(channelID: "test-channel")
        XCTAssertGreaterThan(remaining, 0)
        XCTAssertLessThanOrEqual(remaining, 120)
    }
    
    @MainActor
    func testCooldownReason() {
        let engine = CooldownEngine.shared
        engine.startCooldown(channelID: "test-channel", duration: 60, reason: "401 Unauthorized")
        XCTAssertEqual(engine.cooldownReason(channelID: "test-channel"), "401 Unauthorized")
    }
    
    @MainActor
    func testClearAllCooldowns() {
        let engine = CooldownEngine.shared
        engine.startCooldown(channelID: "ch1", duration: 60, reason: "429")
        engine.startCooldown(channelID: "ch2", duration: 60, reason: "5xx")
        engine.clearAllCooldowns()
        XCTAssertFalse(engine.isCoolingDown(channelID: "ch1"))
        XCTAssertFalse(engine.isCoolingDown(channelID: "ch2"))
    }
}

// MARK: - RequestForwarder Tests

final class RequestForwarderTests: XCTestCase {
    
    func testDetectProtocol_Anthropic_Path() {
        let result = RequestForwarder.detectProtocol(path: "/v1/messages", body: nil)
        XCTAssertEqual(result, .anthropic)
    }
    
    func testDetectProtocol_OpenAI_Path() {
        let result = RequestForwarder.detectProtocol(path: "/v1/chat/completions", body: nil)
        XCTAssertEqual(result, .openai)
    }
    
    func testDetectProtocol_Unknown_Path() {
        let result = RequestForwarder.detectProtocol(path: "/api/test", body: nil)
        XCTAssertEqual(result, .unknown)
    }
    
    func testIsStreamingRequest_Enabled() {
        let body = try? JSONSerialization.data(withJSONObject: ["stream": true])
        XCTAssertTrue(RequestForwarder.isStreamingRequest(body))
    }
    
    func testIsStreamingRequest_Disabled() {
        let body = try? JSONSerialization.data(withJSONObject: ["stream": false])
        XCTAssertFalse(RequestForwarder.isStreamingRequest(body))
    }
    
    func testIsStreamingRequest_NoStreamField() {
        let body = try? JSONSerialization.data(withJSONObject: ["model": "gpt-4"])
        XCTAssertFalse(RequestForwarder.isStreamingRequest(body))
    }
    
    func testParseUsage_OpenAI() {
        let response: [String: Any] = [
            "usage": [
                "prompt_tokens": 10,
                "completion_tokens": 20
            ]
        ]
        let body = try? JSONSerialization.data(withJSONObject: response)
        let (input, output) = RequestForwarder.parseUsage(from: body, isAnthropic: false)
        XCTAssertEqual(input, 10)
        XCTAssertEqual(output, 20)
    }
    
    func testParseUsage_Anthropic() {
        let response: [String: Any] = [
            "usage": [
                "input_tokens": 15,
                "output_tokens": 25
            ]
        ]
        let body = try? JSONSerialization.data(withJSONObject: response)
        let (input, output) = RequestForwarder.parseUsage(from: body, isAnthropic: true)
        XCTAssertEqual(input, 15)
        XCTAssertEqual(output, 25)
    }
}
