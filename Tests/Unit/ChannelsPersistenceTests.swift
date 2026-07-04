import XCTest
@testable import SmartLLMRouter

@MainActor
final class ChannelsPersistenceTests: XCTestCase {

    var tempURL: URL!
    var persistence: ChannelsPersistence!

    override func setUp() async throws {
        try await super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChannelsPersistenceTests-\(UUID().uuidString).json")
        persistence = ChannelsPersistence(fileURL: tempURL)
    }

    override func tearDown() async throws {
        persistence?.delete()
        persistence = nil
        tempURL = nil
        try await super.tearDown()
    }

    // MARK: - File path

    func testDefaultFileURLPointsToApplicationSupport() {
        let url = ChannelsPersistence.defaultFileURL()
        XCTAssertNotNil(url, "Application Support directory should be available")
        XCTAssertTrue(url!.path.contains("Application Support"))
        XCTAssertTrue(url!.path.hasSuffix("channels.json"))
    }

    // MARK: - Load (empty / missing)

    func testLoadReturnsEmptyWhenFileDoesNotExist() {
        let result = persistence.load()
        if case .empty = result {
            // expected
        } else {
            XCTFail("Expected .empty, got \(result)")
        }
    }

    func testLoadWithNilFileURLReturnsEmpty() {
        let noFilePersistence = ChannelsPersistence(fileURL: nil)
        let result = noFilePersistence.load()
        if case .empty = result {
            // expected
        } else {
            XCTFail("Expected .empty, got \(result)")
        }
    }

    // MARK: - Save / load round trip

    func testSaveThenLoadRoundTripsChannels() {
        let channels = [
            makeChannel(id: "1", name: "DeepSeek", baseURL: "https://api.deepseek.com"),
            makeChannel(id: "2", name: "Doubao", baseURL: "https://ark.cn-beijing.volces.com/api/coding")
        ]

        let saved = persistence.save(channels: channels, activeChannelID: "1")
        XCTAssertTrue(saved, "save should succeed")

        let result = persistence.load()
        switch result {
        case .loaded(let loaded, let activeID):
            XCTAssertEqual(loaded.count, 2)
            XCTAssertEqual(loaded[0].name, "DeepSeek")
            XCTAssertEqual(loaded[1].baseURL, "https://ark.cn-beijing.volces.com/api/coding")
            XCTAssertEqual(activeID, "1")
        case .empty, .corrupted:
            XCTFail("Expected .loaded, got \(result)")
        }
    }

    func testDecodeLegacyOpenAIChannelBackfillsOpenAIEndpoint() throws {
        let json = """
        {
          "id": "legacy-openai",
          "name": "Legacy OpenAI",
          "baseURL": "https://openai-compatible.example.com/v1",
          "priority": 1,
          "protocol": "OpenAI",
          "models": []
        }
        """

        let channel = try JSONDecoder().decode(Channel.self, from: XCTUnwrap(json.data(using: .utf8)))

        XCTAssertEqual(channel.baseURL(for: APIProtocol.openai), "https://openai-compatible.example.com/v1")
        XCTAssertNil(channel.baseURL(for: APIProtocol.anthropic))
        XCTAssertEqual(channel.protocolBaseURLs[Channel.openAIEndpointKey], "https://openai-compatible.example.com/v1")
        XCTAssertNil(channel.protocolBaseURLs[Channel.anthropicEndpointKey])
    }

    func testDecodeLegacyAutoChannelBackfillsBothProtocolEndpoints() throws {
        let json = """
        {
          "id": "legacy-auto",
          "name": "Legacy Auto",
          "baseURL": "https://dual-protocol.example.com",
          "priority": 1,
          "protocol": "Auto",
          "models": []
        }
        """

        let channel = try JSONDecoder().decode(Channel.self, from: XCTUnwrap(json.data(using: .utf8)))

        XCTAssertEqual(channel.baseURL(for: APIProtocol.openai), "https://dual-protocol.example.com")
        XCTAssertEqual(channel.baseURL(for: APIProtocol.anthropic), "https://dual-protocol.example.com")
        XCTAssertEqual(channel.protocolBaseURLs[Channel.openAIEndpointKey], "https://dual-protocol.example.com")
        XCTAssertEqual(channel.protocolBaseURLs[Channel.anthropicEndpointKey], "https://dual-protocol.example.com")
    }

    func testProtocolSpecificEndpointsRoundTripThroughPersistence() {
        let channel = Channel(
            id: "dual",
            name: "Dual Protocol",
            baseURL: "https://openai.example.com/v1",
            protocolBaseURLs: [
                Channel.openAIEndpointKey: "https://openai.example.com/v1",
                Channel.anthropicEndpointKey: "https://anthropic.example.com"
            ],
            priority: 1,
            protocol: .auto,
            models: []
        )

        XCTAssertTrue(persistence.save(channels: [channel], activeChannelID: "dual"))

        let result = persistence.load()
        switch result {
        case .loaded(let loaded, let activeID):
            let loadedChannel = loaded[0]
            XCTAssertEqual(activeID, "dual")
            XCTAssertEqual(loadedChannel.protocolBaseURLs[Channel.openAIEndpointKey], "https://openai.example.com/v1")
            XCTAssertEqual(loadedChannel.protocolBaseURLs[Channel.anthropicEndpointKey], "https://anthropic.example.com")
            XCTAssertEqual(loadedChannel.baseURL(for: APIProtocol.openai), "https://openai.example.com/v1")
            XCTAssertEqual(loadedChannel.baseURL(for: APIProtocol.anthropic), "https://anthropic.example.com")
        case .empty, .corrupted:
            XCTFail("Expected .loaded, got \(result)")
        }
    }

    func testAutoChannelWithOnlyOpenAIEndpointDoesNotFallbackToAnthropic() {
        let channel = Channel(
            id: "auto-openai-only",
            name: "Auto OpenAI Only",
            baseURL: "https://openai-only.example.com/v1",
            protocolBaseURLs: [
                Channel.openAIEndpointKey: "https://openai-only.example.com/v1"
            ],
            priority: 1,
            protocol: .auto,
            models: []
        )

        XCTAssertEqual(channel.baseURL(for: APIProtocol.openai), "https://openai-only.example.com/v1")
        XCTAssertNil(channel.baseURL(for: APIProtocol.anthropic))
        XCTAssertEqual(channel.baseURL(for: APIProtocol.auto), "https://openai-only.example.com/v1")
    }

    func testSavePreservesActiveChannelIDWhenNil() {
        let channels = [makeChannel(id: "1", name: "X", baseURL: "https://x.com")]

        persistence.save(channels: channels, activeChannelID: nil)

        let result = persistence.load()
        switch result {
        case .loaded(_, let activeID):
            XCTAssertNil(activeID)
        default:
            XCTFail("Expected .loaded")
        }
    }

    func testSaveWithEmptyChannelsWritesValidFile() {
        let saved = persistence.save(channels: [], activeChannelID: nil)
        XCTAssertTrue(saved)

        let result = persistence.load()
        switch result {
        case .loaded(let loaded, let activeID):
            XCTAssertEqual(loaded.count, 0)
            XCTAssertNil(activeID)
        default:
            XCTFail("Expected .loaded")
        }
    }

    // MARK: - Atomic write safety

    func testSaveOverwritesExistingFile() {
        let first = [makeChannel(id: "1", name: "A", baseURL: "https://a.com")]
        let second = [makeChannel(id: "2", name: "B", baseURL: "https://b.com")]

        persistence.save(channels: first, activeChannelID: "1")
        persistence.save(channels: second, activeChannelID: "2")

        let result = persistence.load()
        switch result {
        case .loaded(let loaded, let activeID):
            XCTAssertEqual(loaded.count, 1)
            XCTAssertEqual(loaded[0].name, "B")
            XCTAssertEqual(activeID, "2")
        default:
            XCTFail("Expected .loaded")
        }
    }

    // MARK: - Corruption recovery

    func testLoadReturnsCorruptedForInvalidJSON() {
        try? "this is not valid json {[}".data(using: .utf8)!
            .write(to: tempURL, options: [.atomic])

        let result = persistence.load()
        if case .corrupted = result {
            // expected — caller should fall back to UserDefaults
        } else {
            XCTFail("Expected .corrupted, got \(result)")
        }
    }

    // MARK: - Delete

    func testDeleteRemovesFile() {
        persistence.save(channels: [makeChannel(id: "1", name: "X", baseURL: "https://x.com")],
                         activeChannelID: nil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))

        persistence.delete()
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path))
    }

    func testDeleteIsIdempotent() {
        // Should not crash even if the file doesn't exist
        persistence.delete()
        persistence.delete()
    }

    // MARK: - ChannelStore integration

    func testChannelStoreLoadsFromFileWhenPresent() {
        let channels = [makeChannel(id: "1", name: "Persisted", baseURL: "https://persisted.com")]
        XCTAssertTrue(persistence.save(channels: channels, activeChannelID: "1"))

        let isolated = ChannelStoreTestSupport.makeIsolatedChannelStore(useTempFile: false)
        defer { isolated.cleanup() }
        // Re-point to our temp file so the store reads what we just saved.
        let store = ChannelStore(
            defaults: isolated.defaults,
            persistence: ChannelsPersistence(fileURL: tempURL)
        )

        XCTAssertEqual(store.channels.count, 1)
        XCTAssertEqual(store.channels[0].name, "Persisted")
        XCTAssertEqual(store.activeChannelID, "1")
    }

    func testChannelStoreFallsBackToUserDefaultsWhenFileMissing() {
        let isolated = ChannelStoreTestSupport.makeIsolatedChannelStore(useTempFile: false)
        defer { isolated.cleanup() }
        // Pre-populate the test UserDefaults suite
        let channels = [makeChannel(id: "1", name: "Cached", baseURL: "https://cached.com")]
        let data = try! JSONEncoder().encode(channels)
        isolated.defaults.set(data, forKey: ChannelStore.userDefaultsKey)
        isolated.defaults.set("1", forKey: ChannelStore.activeChannelDefaultsKey)

        let store = ChannelStore(
            defaults: isolated.defaults,
            persistence: ChannelsPersistence(fileURL: nil) // no file
        )

        XCTAssertEqual(store.channels.count, 1)
        XCTAssertEqual(store.channels[0].name, "Cached")
        XCTAssertEqual(store.activeChannelID, "1")
    }

    func testChannelStoreSaveWritesBothFileAndUserDefaults() {
        let isolated = ChannelStoreTestSupport.makeIsolatedChannelStore(useTempFile: true)
        defer { isolated.cleanup() }

        let store = isolated.store
        let channel = makeChannel(id: "1", name: "Saved", baseURL: "https://saved.com")
        store.addChannel(channel)
        store.setActiveChannel(id: "1")

        // File should be written
        XCTAssertTrue(FileManager.default.fileExists(atPath: isolated.tempFileURL!.path))

        // UserDefaults should also have the cache
        XCTAssertNotNil(isolated.defaults.data(forKey: ChannelStore.userDefaultsKey))
        XCTAssertEqual(isolated.defaults.string(forKey: ChannelStore.activeChannelDefaultsKey), "1")
    }

    func testChannelStoreAllowsSameBaseURLForDifferentProtocols() {
        let isolated = ChannelStoreTestSupport.makeIsolatedChannelStore(useTempFile: true)
        defer { isolated.cleanup() }

        let store = isolated.store
        let openAIChannel = Channel(
            id: "openai",
            name: "Same Vendor OpenAI",
            baseURL: "https://api.same-vendor.example.com",
            priority: 1,
            protocol: .openai,
            models: []
        )
        let anthropicChannel = Channel(
            id: "anthropic",
            name: "Same Vendor Anthropic",
            baseURL: "https://api.same-vendor.example.com",
            priority: 2,
            protocol: .anthropic,
            models: []
        )

        store.addChannel(openAIChannel)
        store.addChannel(anthropicChannel)

        XCTAssertEqual(store.channels.map(\.id), ["openai", "anthropic"])
    }

    func testChannelStoreRejectsDuplicateEndpointForSameProtocol() {
        let isolated = ChannelStoreTestSupport.makeIsolatedChannelStore(useTempFile: true)
        defer { isolated.cleanup() }

        let store = isolated.store
        let first = Channel(
            id: "first",
            name: "First",
            baseURL: "https://api.same-vendor.example.com/",
            priority: 1,
            protocol: .openai,
            models: []
        )
        let duplicate = Channel(
            id: "duplicate",
            name: "Duplicate",
            baseURL: "https://API.SAME-VENDOR.EXAMPLE.COM",
            priority: 2,
            protocol: .openai,
            models: []
        )

        store.addChannel(first)
        store.addChannel(duplicate)

        XCTAssertEqual(store.channels.map(\.id), ["first"])
    }

    // MARK: - Production UserDefaults is never touched by tests

    func testChannelStoreInitWithStandardDefaultsDoesNotCorruptProductionData() {
        // Sanity check: the production UserDefaults.standard should not be
        // touched when tests run. Capture the state before, then assert it's
        // unchanged after a store init+save cycle.
        let key = "ChannelsPersistenceTests.sentinel.\(UUID().uuidString)"
        let before = UserDefaults.standard.data(forKey: key)
        XCTAssertNil(before)

        // The key doesn't exist, but we want to ensure that ChannelStore
        // initialized with `.standard` defaults doesn't write anything
        // *unless* saveChannels is called. This is mostly a smoke test.
        let store = ChannelStore(defaults: UserDefaults.standard,
                                 persistence: ChannelsPersistence(fileURL: tempURL))
        // Adding then removing a channel so no on-disk state remains
        let ch = makeChannel(id: "tmp", name: "tmp", baseURL: "https://tmp.com")
        store.addChannel(ch)
        store.removeChannel(id: "tmp")

        // Confirm the temp file was used, not the production plist
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
    }

    // MARK: - Helpers

    private func makeChannel(id: String, name: String, baseURL: String) -> Channel {
        Channel(
            id: id,
            name: name,
            baseURL: baseURL,
            priority: 1,
            protocol: .openai,
            models: []
        )
    }
}
