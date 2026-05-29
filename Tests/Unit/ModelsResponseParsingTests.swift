import XCTest
@testable import SmartLLMRouter

/// Tests for parsing /v1/models API responses
/// Verifies that input_modalities, context_length, pricing etc. are correctly extracted
@MainActor
final class ModelsResponseParsingTests: XCTestCase {

    // MARK: - Test Helpers

    /// Create a mock /v1/models response JSON
    private func createModelsResponse(models: [[String: Any]]) -> Data {
        let response: [String: Any] = ["data": models]
        return try! JSONSerialization.data(withJSONObject: response)
    }

    // MARK: - Input Modalities Parsing Tests

    func testParseInputModalities_TextOnly() {
        let input = ["text"]
        let result = ChannelManager.parseInputTypes(from: input)
        XCTAssertEqual(result, ["text"])
    }

    func testParseInputModalities_TextAndImage() {
        let input = ["text", "image"]
        let result = ChannelManager.parseInputTypes(from: input)
        XCTAssertEqual(result, ["text", "image"])
    }

    func testParseInputModalities_AllTypes() {
        let input = ["text", "image", "audio", "video"]
        let result = ChannelManager.parseInputTypes(from: input)
        XCTAssertEqual(result, ["text", "image", "audio", "video"])
    }

    func testParseInputModalities_UnknownTypesIgnored() {
        let input = ["text", "3d", "hologram"]
        let result = ChannelManager.parseInputTypes(from: input)
        XCTAssertEqual(result, ["text"])
    }

    func testParseInputModalities_NilInput() {
        let result = ChannelManager.parseInputTypes(from: nil)
        XCTAssertEqual(result, ["text"])
    }

    func testParseInputModalities_EmptyArray() {
        let result = ChannelManager.parseInputTypes(from: [])
        XCTAssertEqual(result, ["text"])
    }

    // MARK: - Pricing Parsing Tests

    func testParsePricingValue_StringNumber() {
        XCTAssertEqual(ChannelManager.parsePricingValue("2.5"), 2.5)
        XCTAssertEqual(ChannelManager.parsePricingValue("0"), 0)
        XCTAssertEqual(ChannelManager.parsePricingValue("10.99"), 10.99)
    }

    func testParsePricingValue_Double() {
        XCTAssertEqual(ChannelManager.parsePricingValue(2.5), 2.5)
        XCTAssertEqual(ChannelManager.parsePricingValue(0.0), 0)
    }

    func testParsePricingValue_Int() {
        XCTAssertEqual(ChannelManager.parsePricingValue(5), 5.0)
    }

    func testParsePricingValue_Nil() {
        XCTAssertNil(ChannelManager.parsePricingValue(nil))
    }

    func testParsePricingValue_InvalidString() {
        XCTAssertNil(ChannelManager.parsePricingValue("free"))
        XCTAssertNil(ChannelManager.parsePricingValue(""))
    }

    // MARK: - Full Response Structure Tests

    func testParseFullResponse_WithAllFields() throws {
        let modelJSON: [String: Any] = [
            "id": "gpt-4o",
            "name": "GPT-4o",
            "context_length": 128000,
            "input_modalities": ["text", "image"],
            "output_modalities": ["text"],
            "pricing": [
                "prompt": "2.5",
                "completion": "10.0"
            ]
        ]

        let data = createModelsResponse(models: [modelJSON])
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let models = parsed?["data"] as? [[String: Any]]
        let firstModel = models?.first

        XCTAssertEqual(firstModel?["id"] as? String, "gpt-4o")
        XCTAssertEqual(firstModel?["context_length"] as? Int, 128000)

        let inputModalities = firstModel?["input_modalities"] as? [String]
        XCTAssertEqual(inputModalities, ["text", "image"])

        let pricing = firstModel?["pricing"] as? [String: String]
        XCTAssertEqual(pricing?["prompt"], "2.5")
        XCTAssertEqual(pricing?["completion"], "10.0")
    }

    func testParseResponse_MinimalFields() throws {
        let modelJSON: [String: Any] = [
            "id": "deepseek-v4-flash"
        ]

        let data = createModelsResponse(models: [modelJSON])
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let models = parsed?["data"] as? [[String: Any]]
        let firstModel = models?.first

        XCTAssertEqual(firstModel?["id"] as? String, "deepseek-v4-flash")
        XCTAssertNil(firstModel?["context_length"])
        XCTAssertNil(firstModel?["input_modalities"])
        XCTAssertNil(firstModel?["pricing"])
    }

    func testParseResponse_OpenRouterFormat() throws {
        // Based on actual OpenRouter response - architecture.input_modalities
        let modelJSON: [String: Any] = [
            "id": "stepfun/step-3.7-flash",
            "name": "StepFun: Step 3.7 Flash",
            "context_length": 256000,
            "architecture": [
                "modality": "text+image+video->text",
                "input_modalities": ["text", "image", "video"],
                "output_modalities": ["text"]
            ],
            "pricing": [
                "prompt": "0.0000002",
                "completion": "0.00000115"
            ]
        ]

        let data = createModelsResponse(models: [modelJSON])
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let models = parsed?["data"] as? [[String: Any]]
        let firstModel = models?.first

        XCTAssertEqual(firstModel?["id"] as? String, "stepfun/step-3.7-flash")
        XCTAssertEqual(firstModel?["context_length"] as? Int, 256000)

        // Verify architecture.input_modalities
        let architecture = firstModel?["architecture"] as? [String: Any]
        let inputModalities = architecture?["input_modalities"] as? [String]
        XCTAssertEqual(inputModalities, ["text", "image", "video"])

        let pricing = firstModel?["pricing"] as? [String: Any]
        XCTAssertEqual(ChannelManager.parsePricingValue(pricing?["prompt"]), 0.0000002)
    }

    func testParseResponse_SenseNovaFormat() throws {
        // Based on SenseNova format - top-level input_modalities
        let modelJSON: [String: Any] = [
            "id": "sensenova-6.7-flash-lite",
            "name": "sensenova-6.7-flash-lite",
            "context_length": 262144,
            "input_modalities": ["text", "image"],
            "output_modalities": ["text"],
            "pricing": [
                "prompt": "0",
                "completion": "0"
            ]
        ]

        let data = createModelsResponse(models: [modelJSON])
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let models = parsed?["data"] as? [[String: Any]]
        let firstModel = models?.first

        XCTAssertEqual(firstModel?["id"] as? String, "sensenova-6.7-flash-lite")

        // Verify top-level input_modalities
        let inputModalities = firstModel?["input_modalities"] as? [String]
        XCTAssertEqual(inputModalities, ["text", "image"])
    }

    // MARK: - Edge Cases

    func testParseResponse_EmptyDataArray() throws {
        let data = createModelsResponse(models: [])
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let models = parsed?["data"] as? [[String: Any]]
        XCTAssertEqual(models?.count, 0)
    }

    func testParseResponse_MissingDataKey() throws {
        let response: [String: Any] = ["models": []]
        let data = try JSONSerialization.data(withJSONObject: response)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNil(parsed?["data"])
    }

    func testParseResponse_InvalidJSON() {
        let data = "not json".data(using: .utf8)!
        XCTAssertThrowsError(try JSONSerialization.jsonObject(with: data))
    }
}
