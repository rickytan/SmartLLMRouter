import XCTest
@testable import SmartLLMRouter

/// Tests for `ChannelExportService.importChannels` — the new contract
/// returns an `ImportResult` instead of an `Int`, so duplicates and
/// failures are surfaced to the UI rather than silently logged.
///
/// Both `ChannelStore` and `KeychainManager` are isolated per-test via
/// dedicated test-support helpers. The unit-test target runs inside
/// the host app's process (TEST_HOST/BUNDLE_LOADER), so any test that
/// used the production Keychain service (`com.smartllmrouter.keys`) could
/// delete the user's real API keys.
/// `KeychainManagerTestSupport` gives every test a UUID-scoped keychain
/// service so the production keychain is never touched.
@MainActor
final class ChannelExportImportTests: XCTestCase {

    var isolated: IsolatedChannelStore!
    var isolatedKeychain: IsolatedKeychainManager!
    var service: ChannelExportService!

    override func setUp() async throws {
        try await super.setUp()
        isolated = ChannelStoreTestSupport.makeIsolatedChannelStore(useTempFile: false)
        isolatedKeychain = KeychainManagerTestSupport.makeIsolatedKeychainManager()
        let channelServices = ChannelServices(
            store: isolated.store,
            keychain: isolatedKeychain.manager,
            cooldownEngine: CooldownEngine(channelStore: isolated.store)
        )
        service = ChannelExportService(channelServices: channelServices)
    }

    override func tearDown() async throws {
        service = nil
        isolatedKeychain.cleanup()
        isolatedKeychain = nil
        isolated.cleanup()
        isolated = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeExportedChannel(name: String,
                                     baseURL: String,
                                     protocolBaseURLs: [String: String] = [:],
                                     protocolType: String = APIProtocol.openai.rawValue,
                                     apiKey: String = "test-key") -> ChannelExportService.ExportedChannel {
        ChannelExportService.ExportedChannel(
            name: name,
            baseURL: baseURL,
            protocolBaseURLs: protocolBaseURLs,
            protocolType: protocolType,
            priority: 1,
            models: [],
            apiKeys: [apiKey]
        )
    }

    private func makeExportFile(channels: [ChannelExportService.ExportedChannel],
                                encrypted: Bool = false) -> ChannelExportService.ExportFile {
        ChannelExportService.ExportFile(
            format: "smartllm-channels",
            version: 1,
            exportedAt: Date(),
            appVersion: "1.0.0",
            channels: channels,
            encrypted: encrypted,
            encryptionSalt: nil,
            encryptionNonce: nil
        )
    }

    // MARK: - Happy path

    func testImportSingleChannelReturnsSuccess() {
        let exported = [makeExportedChannel(name: "DeepSeek", baseURL: "https://api.deepseek.com")]
        let file = makeExportFile(channels: exported)

        let result = service.importChannels(exported, exportFile: file)

        XCTAssertEqual(result.total, 1)
        XCTAssertEqual(result.imported, 1)
        XCTAssertTrue(result.skipped.isEmpty, "Unexpected skipped: \(result.skipped)")
        XCTAssertTrue(result.failed.isEmpty, "Unexpected failed: \(result.failed)")
        XCTAssertFalse(result.hasIssues)
        XCTAssertEqual(isolated.store.channels.count, 1)
        XCTAssertEqual(isolated.store.channels[0].name, "DeepSeek")
        XCTAssertEqual(isolated.store.channels[0].baseURL, "https://api.deepseek.com")
    }

    func testImportPreservesMultipleAPIKeys() throws {
        let exported = [
            ChannelExportService.ExportedChannel(
                name: "DeepSeek",
                baseURL: "https://api.deepseek.com",
                protocolType: APIProtocol.openai.rawValue,
                priority: 1,
                models: [],
                apiKeys: ["key-a", "key-b"]
            )
        ]
        let file = makeExportFile(channels: exported)

        let result = service.importChannels(exported, exportFile: file)
        let channelID = isolated.store.channels.first?.id

        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(isolatedKeychain.manager.getAPIKeys(for: try XCTUnwrap(channelID)), ["key-a", "key-b"])
    }

    func testImportPreservesProtocolSpecificBaseURLs() throws {
        let endpoints = [
            Channel.openAIEndpointKey: "https://openai.example.com/v1",
            Channel.anthropicEndpointKey: "https://anthropic.example.com"
        ]
        let exported = [
            makeExportedChannel(
                name: "Dual Protocol",
                baseURL: "https://openai.example.com/v1",
                protocolBaseURLs: endpoints,
                protocolType: APIProtocol.auto.rawValue
            )
        ]
        let file = makeExportFile(channels: exported)

        let result = service.importChannels(exported, exportFile: file)
        let channel = try XCTUnwrap(isolated.store.channels.first)

        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(channel.protocol, .auto)
        XCTAssertEqual(channel.protocolBaseURLs, endpoints)
        XCTAssertEqual(channel.baseURL(for: APIProtocol.openai), "https://openai.example.com/v1")
        XCTAssertEqual(channel.baseURL(for: APIProtocol.anthropic), "https://anthropic.example.com")
    }

    func testImportLegacySingleAPIKeyFileUpgradesToMultiKeyStorage() throws {
        let json: [String: Any] = [
            "format": "smartllmrouter/channels",
            "version": 1,
            "exportedAt": "2026-05-29T22:00:00Z",
            "appVersion": "1.0.0",
            "encrypted": false,
            "channels": [
                [
                    "name": "Legacy Channel",
                    "baseURL": "https://legacy.example.com/v1",
                    "protocol": "OpenAI",
                    "priority": 1,
                    "apiKey": "legacy-key",
                    "models": []
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let (exportFile, exportedChannels) = try service.parseImportData(data)

        XCTAssertEqual(exportedChannels.first?.apiKey, "legacy-key")
        XCTAssertEqual(exportedChannels.first?.apiKeys, ["legacy-key"])

        let result = service.importChannels(exportedChannels, exportFile: exportFile)
        let channelID = isolated.store.channels.first?.id

        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(isolatedKeychain.manager.getAPIKeys(for: try XCTUnwrap(channelID)), ["legacy-key"])
    }

    func testImportMultipleChannelsAllSucceed() {
        let exported = [
            makeExportedChannel(name: "DeepSeek", baseURL: "https://api.deepseek.com"),
            makeExportedChannel(name: "Doubao", baseURL: "https://ark.cn-beijing.volces.com/api/coding"),
            makeExportedChannel(name: "Shang", baseURL: "https://token.sensenova.cn/v1")
        ]
        let file = makeExportFile(channels: exported)

        let result = service.importChannels(exported, exportFile: file)

        XCTAssertEqual(result.total, 3)
        XCTAssertEqual(result.imported, 3)
        XCTAssertTrue(result.skipped.isEmpty)
        XCTAssertTrue(result.failed.isEmpty)
    }

    // MARK: - Duplicates are surfaced, not silently dropped

    func testImportSkipsDuplicateBaseURLAndSurfacesIt() {
        // Pre-populate the store with a channel that has the same baseURL.
        let existing = Channel(
            id: "existing-1",
            name: "DeepSeek (old)",
            baseURL: "https://api.deepseek.com",
            priority: 1,
            protocol: .openai,
            models: []
        )
        isolated.store.addChannel(existing)

        // Try to import a new channel with the same baseURL but a
        // different name.
        let exported = [makeExportedChannel(name: "DeepSeek (new)", baseURL: "https://api.deepseek.com")]
        let file = makeExportFile(channels: exported)

        let result = service.importChannels(exported, exportFile: file)

        XCTAssertEqual(result.total, 1)
        XCTAssertEqual(result.imported, 0, "Duplicate should not be imported")
        XCTAssertEqual(result.skipped.count, 1, "Duplicate must be reported in skipped, not silently dropped")
        XCTAssertTrue(result.failed.isEmpty)
        XCTAssertTrue(result.hasIssues)
        XCTAssertEqual(result.skipped[0].channelName, "DeepSeek (new)")
        XCTAssertTrue(result.skipped[0].reason.contains("api.deepseek.com"),
                      "Reason should mention the duplicate URL: \(result.skipped[0].reason)")

        // Store state should be unchanged
        XCTAssertEqual(isolated.store.channels.count, 1)
        XCTAssertEqual(isolated.store.channels[0].id, "existing-1")
    }

    func testImportAllowsSameBaseURLWhenProtocolDoesNotOverlap() {
        let existing = Channel(
            id: "existing-anthropic",
            name: "Same Vendor Anthropic",
            baseURL: "https://api.same-vendor.example.com",
            priority: 1,
            protocol: .anthropic,
            models: []
        )
        isolated.store.addChannel(existing)

        let exported = [
            makeExportedChannel(
                name: "Same Vendor OpenAI",
                baseURL: "https://api.same-vendor.example.com",
                protocolType: APIProtocol.openai.rawValue
            )
        ]
        let file = makeExportFile(channels: exported)

        let result = service.importChannels(exported, exportFile: file)

        XCTAssertEqual(result.total, 1)
        XCTAssertEqual(result.imported, 1)
        XCTAssertTrue(result.skipped.isEmpty, "Different protocol endpoint should not be treated as duplicate")
        XCTAssertEqual(isolated.store.channels.count, 2)
        XCTAssertEqual(isolated.store.channels[0].id, "existing-anthropic")
        XCTAssertEqual(isolated.store.channels[1].protocol, .openai)
        XCTAssertEqual(isolated.store.channels[1].baseURL(for: APIProtocol.openai), "https://api.same-vendor.example.com")
    }

    func testImportMixedSuccessAndDuplicateAndFailure() throws {
        // Pre-populate a duplicate
        let existing = Channel(
            id: "existing-1",
            name: "Old Doubao",
            baseURL: "https://ark.cn-beijing.volces.com/api/coding",
            priority: 1,
            protocol: .openai,
            models: []
        )
        isolated.store.addChannel(existing)

        let exported = [
            // Should succeed
            makeExportedChannel(name: "DeepSeek", baseURL: "https://api.deepseek.com"),
            // Should be skipped (duplicate baseURL)
            makeExportedChannel(name: "New Doubao", baseURL: "https://ark.cn-beijing.volces.com/api/coding"),
            // Should succeed
            makeExportedChannel(name: "Shang", baseURL: "https://token.sensenova.cn/v1")
        ]
        let file = makeExportFile(channels: exported)

        let result = service.importChannels(exported, exportFile: file)

        XCTAssertEqual(result.total, 3)
        XCTAssertEqual(result.imported, 2)
        XCTAssertEqual(result.skipped.count, 1)
        XCTAssertTrue(result.failed.isEmpty)
        XCTAssertTrue(result.hasIssues)
        XCTAssertEqual(isolated.store.channels.count, 3) // 1 pre-existing + 2 new
    }

    // MARK: - Encryption parameter missing

    func testImportEncryptedFileWithoutPasswordFailsCleanly() {
        let exported = [makeExportedChannel(name: "DeepSeek", baseURL: "https://api.deepseek.com")]
        // Mark as encrypted but provide no salt/nonce and no password.
        let file = makeExportFile(channels: exported, encrypted: true)

        let result = service.importChannels(exported, exportFile: file, password: nil)

        XCTAssertEqual(result.total, 1)
        XCTAssertEqual(result.imported, 0)
        XCTAssertTrue(result.skipped.isEmpty)
        XCTAssertEqual(result.failed.count, 1, "Missing encryption params must be reported, not silently return 0")
        XCTAssertTrue(result.hasIssues)
        XCTAssertTrue(result.failed[0].reason.contains("Missing encryption parameters"))
    }

    // MARK: - The previous bug: silent Int count

    func testImportResultReportsAllOutcomesNotJustCount() {
        // This is the regression test for the original bug. Pre-fix, the
        // import returned Int and "Imported 1 of 3" was shown to the user
        // even when 2 were silently skipped. After the fix, the result
        // surfaces the exact skip/fail reasons.

        let exported = [
            makeExportedChannel(name: "A", baseURL: "https://a.com"),
            makeExportedChannel(name: "B", baseURL: "https://b.com"),
            makeExportedChannel(name: "A", baseURL: "https://a.com")  // duplicate of #1
        ]
        let file = makeExportFile(channels: exported)

        let result = service.importChannels(exported, exportFile: file)

        // Previous contract: returned Int = 2. The 3rd was silently dropped.
        // New contract: returns total/imported/skipped/failed so the user
        // can see "1 skipped".
        XCTAssertEqual(result.total, 3)
        XCTAssertEqual(result.imported, 2)
        XCTAssertEqual(result.skipped.count, 1)
        XCTAssertTrue(result.failed.isEmpty)
    }
}
