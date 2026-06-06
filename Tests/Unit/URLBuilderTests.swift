import XCTest
@testable import SmartLLMRouter

// MARK: - URLBuilder Tests

final class URLBuilderTests: XCTestCase {

    // MARK: - buildUpstreamURL (OpenAI protocol)

    func testUpstreamURL_OpenAI_noPath() {
        let url = URLBuilder.buildUpstreamURL(baseURL: "https://api.deepseek.com", protocol: .openai)
        XCTAssertEqual(url?.absoluteString, "https://api.deepseek.com/v1/chat/completions")
    }

    func testUpstreamURL_OpenAI_pathWithV1() {
        let url = URLBuilder.buildUpstreamURL(baseURL: "https://integrate.api.nvidia.com/v1", protocol: .openai)
        XCTAssertEqual(url?.absoluteString, "https://integrate.api.nvidia.com/v1/chat/completions")
    }

    func testUpstreamURL_OpenAI_pathWithV3() {
        let url = URLBuilder.buildUpstreamURL(baseURL: "https://ark.cn-beijing.volces.com/api/coding/v3", protocol: .openai)
        XCTAssertEqual(url?.absoluteString, "https://ark.cn-beijing.volces.com/api/coding/v3/chat/completions")
    }

    func testUpstreamURL_OpenAI_pathWithoutVersion() {
        let url = URLBuilder.buildUpstreamURL(baseURL: "https://ark.cn-beijing.volces.com/api/coding", protocol: .openai)
        XCTAssertEqual(url?.absoluteString, "https://ark.cn-beijing.volces.com/api/coding/v1/chat/completions")
    }

    func testUpstreamURL_OpenAI_trailingSlash() {
        let url = URLBuilder.buildUpstreamURL(baseURL: "https://api.deepseek.com/", protocol: .openai)
        XCTAssertEqual(url?.absoluteString, "https://api.deepseek.com/v1/chat/completions")
    }

    func testUpstreamURL_OpenAI_pathWithV1TrailingSlash() {
        let url = URLBuilder.buildUpstreamURL(baseURL: "https://integrate.api.nvidia.com/v1/", protocol: .openai)
        XCTAssertEqual(url?.absoluteString, "https://integrate.api.nvidia.com/v1/chat/completions")
    }

    // MARK: - buildUpstreamURL (Anthropic protocol)

    func testUpstreamURL_Anthropic_noPath() {
        let url = URLBuilder.buildUpstreamURL(baseURL: "https://api.anthropic.com", protocol: .anthropic)
        XCTAssertEqual(url?.absoluteString, "https://api.anthropic.com/v1/messages")
    }

    func testUpstreamURL_Anthropic_pathWithV1() {
        let url = URLBuilder.buildUpstreamURL(baseURL: "https://api.anthropic.com/v1", protocol: .anthropic)
        XCTAssertEqual(url?.absoluteString, "https://api.anthropic.com/v1/messages")
    }

    func testUpstreamURL_Anthropic_pathWithoutVersion() {
        // Doubao Anthropic: /api/coding has no version → should add /v1
        let url = URLBuilder.buildUpstreamURL(baseURL: "https://ark.cn-beijing.volces.com/api/coding", protocol: .anthropic)
        XCTAssertEqual(url?.absoluteString, "https://ark.cn-beijing.volces.com/api/coding/v1/messages")
    }

    func testUpstreamURL_Anthropic_pathWithV3() {
        let url = URLBuilder.buildUpstreamURL(baseURL: "https://ark.cn-beijing.volces.com/api/coding/v3", protocol: .anthropic)
        XCTAssertEqual(url?.absoluteString, "https://ark.cn-beijing.volces.com/api/coding/v3/messages")
    }

    // MARK: - buildUpstreamURL (Auto protocol)

    func testUpstreamURL_Auto_noPath() {
        let url = URLBuilder.buildUpstreamURL(baseURL: "https://api.deepseek.com", protocol: .openai)
        XCTAssertEqual(url?.absoluteString, "https://api.deepseek.com/v1/chat/completions")
    }

    // MARK: - buildModelsURL

    func testModelsURL_noPath() {
        let url = URLBuilder.buildModelsURL(baseURL: "https://api.deepseek.com")
        XCTAssertEqual(url?.absoluteString, "https://api.deepseek.com/v1/models")
    }

    func testModelsURL_pathWithV1() {
        let url = URLBuilder.buildModelsURL(baseURL: "https://integrate.api.nvidia.com/v1")
        XCTAssertEqual(url?.absoluteString, "https://integrate.api.nvidia.com/v1/models")
    }

    func testModelsURL_pathWithV3() {
        let url = URLBuilder.buildModelsURL(baseURL: "https://ark.cn-beijing.volces.com/api/coding/v3")
        XCTAssertEqual(url?.absoluteString, "https://ark.cn-beijing.volces.com/api/coding/v3/models")
    }

    func testModelsURL_pathWithoutVersion() {
        let url = URLBuilder.buildModelsURL(baseURL: "https://ark.cn-beijing.volces.com/api/coding")
        XCTAssertEqual(url?.absoluteString, "https://ark.cn-beijing.volces.com/api/coding/v1/models")
    }

    func testModelsURL_trailingSlash() {
        let url = URLBuilder.buildModelsURL(baseURL: "https://api.deepseek.com/")
        XCTAssertEqual(url?.absoluteString, "https://api.deepseek.com/v1/models")
    }

    // MARK: - buildChatCompletionsURL

    func testChatCompletionsURL_OpenAI_noPath() {
        let url = URLBuilder.buildChatCompletionsURL(baseURL: "https://api.deepseek.com", isAnthropic: false)
        XCTAssertEqual(url?.absoluteString, "https://api.deepseek.com/v1/chat/completions")
    }

    func testChatCompletionsURL_OpenAI_pathWithV1() {
        let url = URLBuilder.buildChatCompletionsURL(baseURL: "https://integrate.api.nvidia.com/v1", isAnthropic: false)
        XCTAssertEqual(url?.absoluteString, "https://integrate.api.nvidia.com/v1/chat/completions")
    }

    func testChatCompletionsURL_OpenAI_pathWithV3() {
        let url = URLBuilder.buildChatCompletionsURL(baseURL: "https://ark.cn-beijing.volces.com/api/coding/v3", isAnthropic: false)
        XCTAssertEqual(url?.absoluteString, "https://ark.cn-beijing.volces.com/api/coding/v3/chat/completions")
    }

    func testChatCompletionsURL_OpenAI_pathWithoutVersion() {
        let url = URLBuilder.buildChatCompletionsURL(baseURL: "https://ark.cn-beijing.volces.com/api/coding", isAnthropic: false)
        XCTAssertEqual(url?.absoluteString, "https://ark.cn-beijing.volces.com/api/coding/v1/chat/completions")
    }

    func testChatCompletionsURL_Anthropic_noPath() {
        let url = URLBuilder.buildChatCompletionsURL(baseURL: "https://api.anthropic.com", isAnthropic: true)
        XCTAssertEqual(url?.absoluteString, "https://api.anthropic.com/v1/messages")
    }

    func testChatCompletionsURL_Anthropic_pathWithV1() {
        let url = URLBuilder.buildChatCompletionsURL(baseURL: "https://api.anthropic.com/v1", isAnthropic: true)
        XCTAssertEqual(url?.absoluteString, "https://api.anthropic.com/v1/messages")
    }

    func testChatCompletionsURL_Anthropic_pathWithoutVersion() {
        let url = URLBuilder.buildChatCompletionsURL(baseURL: "https://ark.cn-beijing.volces.com/api/coding", isAnthropic: true)
        XCTAssertEqual(url?.absoluteString, "https://ark.cn-beijing.volces.com/api/coding/v1/messages")
    }

    func testChatCompletionsURL_Anthropic_pathWithV3() {
        let url = URLBuilder.buildChatCompletionsURL(baseURL: "https://ark.cn-beijing.volces.com/api/coding/v3", isAnthropic: true)
        XCTAssertEqual(url?.absoluteString, "https://ark.cn-beijing.volces.com/api/coding/v3/messages")
    }

    // MARK: - Edge Cases

    func testURL_noScheme() {
        // Invalid URL should return nil
        let url = URLBuilder.buildUpstreamURL(baseURL: "", protocol: .openai)
        XCTAssertNil(url)
    }

    func testURL_localhost() {
        let url = URLBuilder.buildUpstreamURL(baseURL: "http://localhost:8080", protocol: .openai)
        XCTAssertEqual(url?.absoluteString, "http://localhost:8080/v1/chat/completions")
    }

    func testURL_localhostWithV1() {
        let url = URLBuilder.buildUpstreamURL(baseURL: "http://localhost:8080/v1", protocol: .openai)
        XCTAssertEqual(url?.absoluteString, "http://localhost:8080/v1/chat/completions")
    }

    func testURL_deepNestedPath() {
        let url = URLBuilder.buildModelsURL(baseURL: "https://example.com/api/v2/models")
        XCTAssertEqual(url?.absoluteString, "https://example.com/api/v2/models/v1/models")
    }
}
