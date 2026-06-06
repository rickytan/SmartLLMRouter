import XCTest
@testable import SmartLLMRouter

/// Tests for `ChannelExportService.importChannels` — the new contract
/// returns an `ImportResult` instead of an `Int`, so duplicates and
/// failures are surfaced to the UI rather than silently logged.
///
/// The keychain-based tests touch the real macOS Keychain because
/// `KeychainManager` is a singleton. We use a unique per-test
/// `channelID` namespace and clean up in `tearDown` so we don't
/// pollute the host app's keychain entries.
@MainActor
final class ChannelExportImportTests: XCTestCase {

    var isolated: IsolatedChannelStore!
    var restore: (() -> Void)!

    override func setUp() async throws {
        try await super.setUp()
        let (iso, restoreFn) = ChannelStoreTestSupport.installAsShared()
        isolated = iso
        restore = restoreFn
        // Make sure no leftover state from a previous run.
        try? KeychainManager.shared.clearAll()
    }

    override func tearDown() async throws {
        try? KeychainManager.shared.clearAll()
        restore()
        isolated = nil
        restore = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeExportedChannel(name: String,
                                     baseURL: String,
                                     apiKey: String = "test-key") -> ChannelExportService.ExportedChannel {
        ChannelExportService.ExportedChannel(
            name: name,
            baseURL: baseURL,
            protocolType: APIProtocol.openai.rawValue,
            priority: 1,
            models: [],
            apiKey: apiKey
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

        let result = ChannelExportService.shared.importChannels(exported, exportFile: file)

        XCTAssertEqual(result.total, 1)
        XCTAssertEqual(result.imported, 1)
        XCTAssertTrue(result.skipped.isEmpty, "Unexpected skipped: \(result.skipped)")
        XCTAssertTrue(result.failed.isEmpty, "Unexpected failed: \(result.failed)")
        XCTAssertFalse(result.hasIssues)
        XCTAssertEqual(isolated.store.channels.count, 1)
        XCTAssertEqual(isolated.store.channels[0].name, "DeepSeek")
        XCTAssertEqual(isolated.store.channels[0].baseURL, "https://api.deepseek.com")
    }

    func testImportMultipleChannelsAllSucceed() {
        let exported = [
            makeExportedChannel(name: "DeepSeek", baseURL: "https://api.deepseek.com"),
            makeExportedChannel(name: "Doubao", baseURL: "https://ark.cn-beijing.volces.com/api/coding"),
            makeExportedChannel(name: "Shang", baseURL: "https://token.sensenova.cn/v1")
        ]
        let file = makeExportFile(channels: exported)

        let result = ChannelExportService.shared.importChannels(exported, exportFile: file)

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

        let result = ChannelExportService.shared.importChannels(exported, exportFile: file)

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

        let result = ChannelExportService.shared.importChannels(exported, exportFile: file)

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

        let result = ChannelExportService.shared.importChannels(exported, exportFile: file, password: nil)

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

        let result = ChannelExportService.shared.importChannels(exported, exportFile: file)

        // Previous contract: returned Int = 2. The 3rd was silently dropped.
        // New contract: returns total/imported/skipped/failed so the user
        // can see "1 skipped".
        XCTAssertEqual(result.total, 3)
        XCTAssertEqual(result.imported, 2)
        XCTAssertEqual(result.skipped.count, 1)
        XCTAssertTrue(result.failed.isEmpty)
    }
}
