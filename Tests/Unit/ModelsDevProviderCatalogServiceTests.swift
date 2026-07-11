import XCTest
@testable import SmartLLMRouter

final class ModelsDevProviderCatalogServiceTests: XCTestCase {
    func testParseTemplatesConvertsOpenAICompatibleProvider() throws {
        let json = """
        {
          "deepseek": {
            "id": "deepseek",
            "name": "DeepSeek",
            "npm": "@ai-sdk/openai-compatible",
            "api": "https://api.deepseek.com",
            "models": {
              "deepseek/deepseek-chat": {
                "id": "deepseek/deepseek-chat",
                "limit": { "context": 64000 },
                "cost": { "input": 0.14, "output": 0.28 },
                "modalities": { "input": ["text", "image", "pdf"] }
              }
            }
          }
        }
        """.data(using: .utf8)!

        let templates = try ModelsDevProviderCatalogService.parseTemplates(from: json)

        XCTAssertEqual(templates.count, 1)
        XCTAssertEqual(templates[0].id, "deepseek")
        XCTAssertEqual(templates[0].baseURL(for: Channel.openAIEndpointKey), "https://api.deepseek.com")
        XCTAssertEqual(templates[0].supportsProtocols, [Channel.openAIEndpointKey])
        XCTAssertEqual(templates[0].defaultModels.count, 1)
        XCTAssertEqual(templates[0].defaultModels[0].model, "deepseek/deepseek-chat")
        XCTAssertEqual(templates[0].defaultModels[0].contextLength, 64000)
        XCTAssertEqual(templates[0].defaultModels[0].inputPrice, 0.14)
        XCTAssertEqual(templates[0].defaultModels[0].outputPrice, 0.28)
        XCTAssertEqual(templates[0].defaultModels[0].inputTypes, ["text", "image"])
    }

    func testParseTemplatesConvertsAnthropicProvider() throws {
        let json = """
        {
          "anthropic-proxy": {
            "id": "anthropic-proxy",
            "name": "Anthropic Proxy",
            "npm": "@ai-sdk/anthropic",
            "api": "https://anthropic.example.com",
            "models": {
              "claude-test": {
                "id": "claude-test",
                "limit": { "context": 200000 },
                "cost": { "input": 3, "output": 15 },
                "modalities": { "input": ["text"] }
              }
            }
          }
        }
        """.data(using: .utf8)!

        let templates = try ModelsDevProviderCatalogService.parseTemplates(from: json)

        XCTAssertEqual(templates.count, 1)
        XCTAssertEqual(templates[0].id, "anthropic-proxy")
        XCTAssertEqual(templates[0].baseURL(for: Channel.anthropicEndpointKey), "https://anthropic.example.com")
        XCTAssertEqual(templates[0].supportsProtocols, [Channel.anthropicEndpointKey])
        XCTAssertEqual(templates[0].defaultModels.map(\.model), ["claude-test"])
        XCTAssertEqual(templates[0].defaultModels[0].protocol, Channel.anthropicEndpointKey)
    }

    func testParseTemplatesToleratesMissingOptionalModelFieldsAndUnknownFields() throws {
        let json = """
        {
          "minimal": {
            "id": "minimal",
            "name": "Minimal Provider",
            "npm": "@ai-sdk/openai-compatible",
            "api": "https://minimal.example.com/v1",
            "homepage": "https://example.com/ignored",
            "models": {
              "minimal-model": {
                "id": "minimal-model",
                "name": "Ignored Model Name",
                "attachment": true
              }
            }
          }
        }
        """.data(using: .utf8)!

        let templates = try ModelsDevProviderCatalogService.parseTemplates(from: json)

        XCTAssertEqual(templates.count, 1)
        XCTAssertEqual(templates[0].defaultModels.count, 1)
        XCTAssertEqual(templates[0].defaultModels[0].contextLength, 0)
        XCTAssertEqual(templates[0].defaultModels[0].inputPrice, 0)
        XCTAssertEqual(templates[0].defaultModels[0].outputPrice, 0)
        XCTAssertEqual(templates[0].defaultModels[0].inputTypes, ["text"])
    }

    func testParseTemplatesFallsBackToTextWhenModalitiesAreMissingOrUnsupported() throws {
        let json = """
        {
          "modalities": {
            "id": "modalities",
            "name": "Modalities",
            "npm": "@ai-sdk/openai-compatible",
            "api": "https://modalities.example.com/v1",
            "models": {
              "no-modalities": {
                "id": "no-modalities"
              },
              "unsupported-modalities": {
                "id": "unsupported-modalities",
                "modalities": { "input": ["binary", "spreadsheet"] }
              }
            }
          }
        }
        """.data(using: .utf8)!

        let templates = try ModelsDevProviderCatalogService.parseTemplates(from: json)
        let modelsByID = Dictionary(uniqueKeysWithValues: templates[0].defaultModels.map { ($0.model, $0) })

        XCTAssertEqual(modelsByID["no-modalities"]?.inputTypes, ["text"])
        XCTAssertEqual(modelsByID["unsupported-modalities"]?.inputTypes, ["text"])
    }

    func testParseTemplatesSkipsProvidersWithoutUsableBaseURL() throws {
        let json = """
        {
          "openai": {
            "id": "openai",
            "name": "OpenAI",
            "npm": "@ai-sdk/openai",
            "models": {}
          },
          "cloudflare": {
            "id": "cloudflare",
            "name": "Cloudflare Workers AI",
            "npm": "@ai-sdk/openai-compatible",
            "api": "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/ai/v1",
            "models": {}
          }
        }
        """.data(using: .utf8)!

        let templates = try ModelsDevProviderCatalogService.parseTemplates(from: json)

        XCTAssertTrue(templates.isEmpty)
    }

    func testParseTemplatesSkipsUnsupportedProviderPackages() throws {
        let json = """
        {
          "google": {
            "id": "google",
            "name": "Google",
            "npm": "@ai-sdk/google",
            "api": "https://google.example.com/v1",
            "models": {
              "gemini-test": { "id": "gemini-test" }
            }
          }
        }
        """.data(using: .utf8)!

        let templates = try ModelsDevProviderCatalogService.parseTemplates(from: json)

        XCTAssertTrue(templates.isEmpty)
    }

    func testCacheTemplatesRoundTripsProviderTemplates() throws {
        let suiteName = "ModelsDevProviderCatalogServiceTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let service = ModelsDevProviderCatalogService(userDefaults: userDefaults)
        let templates = [
            ProviderTemplate(
                id: "cached",
                nameEn: "Cached",
                nameZh: "Cached",
                baseURL: "https://cached.example.com/v1",
                supportsProtocols: [Channel.openAIEndpointKey],
                defaultModels: [
                    ProviderModel(
                        model: "cached-model",
                        protocol: Channel.openAIEndpointKey,
                        contextLength: 123,
                        inputPrice: 0.1,
                        outputPrice: 0.2,
                        inputTypes: ["text"]
                    ),
                ]
            ),
        ]

        service.cacheTemplates(templates)
        let cached = try XCTUnwrap(service.loadCachedTemplates())

        XCTAssertEqual(cached.count, 1)
        XCTAssertEqual(cached[0].id, "cached")
        XCTAssertEqual(cached[0].baseURL(for: Channel.openAIEndpointKey), "https://cached.example.com/v1")
        XCTAssertEqual(cached[0].defaultModels.map(\.model), ["cached-model"])
    }

    func testAutoRefreshIsAllowedWhenNoAttemptWasRecorded() throws {
        let suiteName = "ModelsDevProviderCatalogServiceTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let service = ModelsDevProviderCatalogService(userDefaults: userDefaults)
        let calendar = gregorianCalendar

        XCTAssertTrue(service.shouldAutoRefreshTemplates(now: date(year: 2026, month: 7, day: 11), calendar: calendar))
    }

    func testAutoRefreshIsSkippedAfterSameDayAttempt() throws {
        let suiteName = "ModelsDevProviderCatalogServiceTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let service = ModelsDevProviderCatalogService(userDefaults: userDefaults)
        let calendar = gregorianCalendar
        service.markAutoRefreshAttempted(now: date(year: 2026, month: 7, day: 11, hour: 9))

        XCTAssertFalse(service.shouldAutoRefreshTemplates(now: date(year: 2026, month: 7, day: 11, hour: 18), calendar: calendar))
    }

    func testAutoRefreshIsAllowedOnNextDay() throws {
        let suiteName = "ModelsDevProviderCatalogServiceTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let service = ModelsDevProviderCatalogService(userDefaults: userDefaults)
        let calendar = gregorianCalendar
        service.markAutoRefreshAttempted(now: date(year: 2026, month: 7, day: 11, hour: 23))

        XCTAssertTrue(service.shouldAutoRefreshTemplates(now: date(year: 2026, month: 7, day: 12, hour: 1), calendar: calendar))
    }

    @MainActor
    func testMergeProviderTemplatesKeepsBuiltInEndpointWhenRemoteOnlyUpdatesModels() {
        let builtIn = ProviderTemplate(
            id: "openai",
            nameEn: "OpenAI",
            nameZh: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            supportsProtocols: [Channel.openAIEndpointKey],
            defaultModels: [
                ProviderModel(
                    model: "gpt-old",
                    protocol: Channel.openAIEndpointKey,
                    contextLength: 1000,
                    inputPrice: 1,
                    outputPrice: 2,
                    inputTypes: ["text"]
                ),
            ]
        )
        let remote = ProviderTemplate(
            id: "openai",
            nameEn: "OpenAI",
            nameZh: "OpenAI",
            supportsProtocols: [Channel.openAIEndpointKey],
            defaultModels: [
                ProviderModel(
                    model: "gpt-new",
                    protocol: Channel.openAIEndpointKey,
                    contextLength: 2000,
                    inputPrice: 3,
                    outputPrice: 4,
                    inputTypes: ["text"]
                ),
            ]
        )

        let merged = ChannelManager.mergeProviderTemplates(base: [builtIn], updates: [remote])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].baseURL(for: Channel.openAIEndpointKey), "https://api.openai.com/v1")
        XCTAssertEqual(merged[0].defaultModels.map(\.model), ["gpt-new"])
    }

    private var gregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        DateComponents(
            calendar: gregorianCalendar,
            timeZone: TimeZone(secondsFromGMT: 0),
            year: year,
            month: month,
            day: day,
            hour: hour
        ).date!
    }
}
