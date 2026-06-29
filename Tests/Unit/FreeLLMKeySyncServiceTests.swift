import XCTest
@testable import SmartLLMRouter

@MainActor
final class FreeLLMKeySyncServiceTests: XCTestCase {
    private var isolatedStore: IsolatedChannelStore!
    private var isolatedKeychain: IsolatedKeychainManager!
    private var channelServices: ChannelServices!

    override func setUp() async throws {
        try await super.setUp()
        isolatedStore = ChannelStoreTestSupport.makeIsolatedChannelStore(useTempFile: false)
        isolatedKeychain = KeychainManagerTestSupport.makeIsolatedKeychainManager()
        channelServices = ChannelServices(
            store: isolatedStore.store,
            keychain: isolatedKeychain.manager,
            cooldownEngine: CooldownEngine(channelStore: isolatedStore.store)
        )
    }

    override func tearDown() async throws {
        channelServices = nil
        isolatedKeychain.cleanup()
        isolatedKeychain = nil
        isolatedStore.cleanup()
        isolatedStore = nil
        try await super.tearDown()
    }

    func testParseREADMEKeepsOnlyUnexpiredKeysAndAddsModelAliases() throws {
        let markdown = """
        | API Key | Model | Status | Rate Limit | Budget | Expires |
        | --- | --- | --- | --- | --- | --- |
        | `sk-free-a` | `openai/gpt-5.5` | New | 60 req/min | $1 | 2099-01-01 |
        | `sk-free-b` | `deepseek/deepseek-v4-flash` | New | 60 req/min | $1 | 2099-01-02 |
        | `sk-expired` | `openai/old-model` | New | 60 req/min | $1 | 2020-01-01 |
        | `sk-status-expired` | `openai/expired-model` | Expired | 60 req/min | $1 | 2099-01-01 |
        """

        let snapshot = FreeLLMKeySyncService.parseREADME(
            markdown,
            referenceDate: try XCTUnwrap(Self.date("2026-06-28"))
        )

        XCTAssertEqual(snapshot.apiKeys, ["sk-free-a", "sk-free-b"])
        XCTAssertEqual(snapshot.modelIdentifiers, [
            "openai/gpt-5.5",
            "gpt-5.5",
            "deepseek/deepseek-v4-flash",
            "deepseek-v4-flash",
        ])
    }

    func testParseREADMEParsesCurrentFreeLLMRepositoryTableFormat() throws {
        let markdown = [
            "### Claude Opus | Key | Model | Status | Budget | Rate Limit | Expires | Description |",
            "|-----|-------|--------|--------|------------|---------|-------------|",
            "| `sk-realistic-a` | claude-opus-4-7 | New | $20.00 | 5 RPM | 2099-01-01 | Free rotating key |",
            "--- ### Gemini | Key | Model | Status | Budget | Rate Limit | Expires | Description |",
            "|-----|-------|--------|--------|------------|---------|-------------|",
            "| `sk-realistic-b` | google/gemini-3.5-flash | New | $20.00 | 10 RPM | 2099-01-02 | Live key |",
            "| `sk-realistic-expired` | openai/old-model | Expired | $0.00 | 1 RPM | 2099-01-03 | Expired row |",
        ].joined(separator: " ")

        let snapshot = FreeLLMKeySyncService.parseREADME(
            markdown,
            referenceDate: try XCTUnwrap(Self.date("2026-06-30"))
        )

        XCTAssertEqual(snapshot.apiKeys, ["sk-realistic-a", "sk-realistic-b"])
        XCTAssertEqual(snapshot.modelIdentifiers, [
            "claude-opus-4-7",
            "google/gemini-3.5-flash",
            "gemini-3.5-flash",
        ])
    }

    func testApplyCreatesFreeKeyChannelAndPreservesKeyOrder() throws {
        let service = FreeLLMKeySyncService(
            channelServices: channelServices,
            defaults: UserDefaults(suiteName: "FreeLLMKeySyncServiceTests.\(UUID().uuidString)")!
        )
        let snapshot = FreeLLMKeySyncService.Snapshot(entries: [
            FreeLLMKeySyncService.Entry(
                apiKey: "sk-free-a",
                model: "openai/gpt-5.5",
                status: "New",
                expiresAt: Self.date("2099-01-01")
            ),
            FreeLLMKeySyncService.Entry(
                apiKey: "sk-free-b",
                model: "deepseek/deepseek-v4-flash",
                status: "New",
                expiresAt: Self.date("2099-01-02")
            ),
        ])

        let result = try service.apply(snapshot: snapshot)
        let channel = try XCTUnwrap(isolatedStore.store.channels.first)

        XCTAssertTrue(result.addedChannel)
        XCTAssertEqual(channel.providerId, FreeLLMKeySyncService.providerID)
        XCTAssertEqual(channel.baseURL, FreeLLMKeySyncService.baseURL)
        XCTAssertEqual(channel.protocol, .openai)
        XCTAssertEqual(isolatedKeychain.manager.getAPIKeys(for: channel.id), ["sk-free-a", "sk-free-b"])
        XCTAssertEqual(channel.models.map(\.identifier), [
            "openai/gpt-5.5",
            "gpt-5.5",
            "deepseek/deepseek-v4-flash",
            "deepseek-v4-flash",
        ])
    }

    private static func date(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}
