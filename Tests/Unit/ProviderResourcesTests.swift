import XCTest
@testable import SmartLLMRouter

final class ProviderResourcesTests: XCTestCase {
    func testBundledProvidersExposeCurrentAnthropicBaseURLs() throws {
        let file = try loadProvidersFile()

        XCTAssertEqual(file.version, "1.5.0")
        XCTAssertEqual(
            try provider("dashscope", in: file).baseURL(for: Channel.anthropicEndpointKey),
            "https://dashscope.aliyuncs.com/apps/anthropic"
        )
        XCTAssertEqual(
            try provider("dashscope_international", in: file).baseURL(for: Channel.anthropicEndpointKey),
            "https://dashscope-intl.aliyuncs.com/apps/anthropic"
        )
        XCTAssertEqual(
            try provider("minimax", in: file).baseURL(for: Channel.anthropicEndpointKey),
            "https://api.minimaxi.com/anthropic"
        )
        XCTAssertEqual(
            try provider("kimi_for_coding", in: file).baseURL(for: Channel.anthropicEndpointKey),
            "https://api.kimi.com/coding/"
        )
        XCTAssertEqual(
            try provider("zhipu", in: file).baseURL(for: Channel.anthropicEndpointKey),
            "https://open.bigmodel.cn/api/anthropic"
        )
        XCTAssertEqual(
            try provider("zai_coding_plan", in: file).baseURL(for: Channel.anthropicEndpointKey),
            "https://api.z.ai/api/anthropic"
        )
    }

    func testDualProtocolProviderTemplatesIncludeAnthropicModels() throws {
        let file = try loadProvidersFile()
        let providerIDs = [
            "dashscope",
            "dashscope_international",
            "minimax",
            "zhipu",
            "zai_coding_plan",
            "xiaomi_mimo",
            "kimi_for_coding"
        ]

        for providerID in providerIDs {
            let template = try provider(providerID, in: file)
            XCTAssertTrue(
                template.supportsProtocols.contains(Channel.anthropicEndpointKey),
                "\(providerID) should declare Anthropic protocol support"
            )
            XCTAssertNotNil(
                template.baseURL(for: Channel.anthropicEndpointKey),
                "\(providerID) should define an Anthropic base URL"
            )
            XCTAssertTrue(
                template.defaultModels.contains { $0.protocol == Channel.anthropicEndpointKey },
                "\(providerID) should include at least one Anthropic default model"
            )
        }
    }

    func testProviderAnthropicBaseURLsBuildExpectedMessagesEndpoints() throws {
        let file = try loadProvidersFile()
        let expectations = [
            "minimax": "https://api.minimaxi.com/anthropic/v1/messages",
            "kimi_for_coding": "https://api.kimi.com/coding/v1/messages",
            "dashscope": "https://dashscope.aliyuncs.com/apps/anthropic/v1/messages"
        ]

        for (providerID, expectedURL) in expectations {
            let baseURL = try XCTUnwrap(try provider(providerID, in: file).baseURL(for: Channel.anthropicEndpointKey))
            let upstreamURL = URLBuilder.buildUpstreamURL(baseURL: baseURL, protocol: .anthropic)
            XCTAssertEqual(upstreamURL?.absoluteString, expectedURL)
        }
    }

    private func loadProvidersFile() throws -> ProvidersFile {
        let fileURL = URL(fileURLWithPath: #filePath)
        let repositoryRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let providersURL = repositoryRoot.appendingPathComponent("Resources/providers.json")
        let data = try Data(contentsOf: providersURL)
        return try JSONDecoder().decode(ProvidersFile.self, from: data)
    }

    private func provider(_ id: String, in file: ProvidersFile) throws -> ProviderTemplate {
        try XCTUnwrap(file.providers.first { $0.id == id }, "Missing provider template: \(id)")
    }
}
