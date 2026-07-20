import XCTest
import CryptoKit
@testable import SmartLLMRouter

// MARK: - ChannelExportService Tests

@MainActor
final class ChannelExportServiceTests: XCTestCase {

    // MARK: - Test Isolation

    private var isolatedStore: IsolatedChannelStore!
    private var isolatedKeychain: IsolatedKeychainManager!
    private var service: ChannelExportService!

    override func setUp() async throws {
        try await super.setUp()
        isolatedStore = ChannelStoreTestSupport.makeIsolatedChannelStore(useTempFile: false)
        isolatedKeychain = KeychainManagerTestSupport.makeIsolatedKeychainManager()
        let channelServices = ChannelServices(
            store: isolatedStore.store,
            keychain: isolatedKeychain.manager,
            cooldownEngine: CooldownEngine(channelStore: isolatedStore.store)
        )
        service = ChannelExportService(channelServices: channelServices)
    }

    override func tearDown() async throws {
        isolatedStore.cleanup()
        isolatedKeychain.cleanup()
        service = nil
        isolatedStore = nil
        isolatedKeychain = nil
        try await super.tearDown()
    }

    // MARK: - Test Helpers

    private func createTestChannel(
        id: String = UUID().uuidString,
        name: String = "Test Channel",
        baseURL: String = "https://api.test.com/v1",
        protocolBaseURLs: [String: String] = [:],
        protocolType: APIProtocol = .openai,
        models: [ModelEntry] = []
    ) -> Channel {
        Channel(
            id: id,
            name: name,
            baseURL: baseURL,
            protocolBaseURLs: protocolBaseURLs,
            priority: 1,
            protocol: protocolType,
            models: models
        )
    }

    private func createTestModel(
        id: String = UUID().uuidString,
        identifier: String = "gpt-4o",
        inputTypes: [String] = ["text"]
    ) -> ModelEntry {
        ModelEntry(
            id: id,
            identifier: identifier,
            displayName: identifier,
            contextLength: 128000,
            inputPricePer1M: 2.5,
            outputPricePer1M: 10.0,
            isEnabled: true,
            inputTypes: inputTypes
        )
    }

    // MARK: - Export Format Tests

    func testExportFileStructure() async throws {
        let channel = createTestChannel(
            models: [createTestModel()]
        )

        // Set API key in keychain
        try isolatedKeychain.manager.setAPIKey("sk-test-key-12345", for: channel.id)

        defer {
            try? isolatedKeychain.manager.removeAPIKey(for: channel.id)
        }

                let data = try await service.exportChannels([channel])

        // Verify it's valid JSON
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)

        // Verify format field
        XCTAssertEqual(json?["format"] as? String, "smartllmrouter/channels")

        // Verify version field
        XCTAssertEqual(json?["version"] as? Int, 1)

        // Verify channels array
        let channels = json?["channels"] as? [[String: Any]]
        XCTAssertEqual(channels?.count, 1)

        // Verify channel fields
        let firstChannel = channels?.first
        XCTAssertEqual(firstChannel?["name"] as? String, "Test Channel")
        XCTAssertEqual(firstChannel?["baseURL"] as? String, "https://api.test.com/v1")
        XCTAssertEqual(firstChannel?["protocol"] as? String, "OpenAI")
        XCTAssertEqual(firstChannel?["apiKey"] as? String, "sk-test-key-12345")
        XCTAssertEqual(firstChannel?["apiKeys"] as? [String], ["sk-test-key-12345"])

        // Verify models
        let models = firstChannel?["models"] as? [[String: Any]]
        XCTAssertEqual(models?.count, 1)
        XCTAssertEqual(models?.first?["identifier"] as? String, "gpt-4o")
        XCTAssertEqual(models?.first?["inputTypes"] as? [String], ["text"])
    }

    func testExportIncludesProtocolSpecificBaseURLs() async throws {
        let endpoints = [
            Channel.openAIEndpointKey: "https://openai.example.com/v1",
            Channel.anthropicEndpointKey: "https://anthropic.example.com"
        ]
        let channel = createTestChannel(
            id: "dual-channel",
            name: "Dual Protocol",
            baseURL: "https://openai.example.com/v1",
            protocolBaseURLs: endpoints,
            protocolType: .auto
        )
        try isolatedKeychain.manager.setAPIKey("dual-key", for: channel.id)

        let data = try await service.exportChannels([channel])
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let channels = json?["channels"] as? [[String: Any]]
        let exported = try XCTUnwrap(channels?.first)

        XCTAssertEqual(exported["protocol"] as? String, "Auto")
        XCTAssertEqual(exported["protocolBaseURLs"] as? [String: String], endpoints)

        let (_, parsedChannels) = try await service.parseImportData(data)
        XCTAssertEqual(parsedChannels.first?.protocolBaseURLs, endpoints)
    }

    func testExportJSONDoesNotEscapeSlashesInURLs() async throws {
        let endpoints = [
            Channel.openAIEndpointKey: "https://openai.example.com/v1",
            Channel.anthropicEndpointKey: "https://anthropic.example.com/v1/messages"
        ]
        let channel = createTestChannel(
            id: "url-channel",
            baseURL: "https://openai.example.com/v1",
            protocolBaseURLs: endpoints,
            protocolType: .auto
        )
        try isolatedKeychain.manager.setAPIKey("url-key", for: channel.id)

        let data = try await service.exportChannels([channel])
        let jsonText = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(jsonText.contains(#""baseURL" : "https://openai.example.com/v1""#))
        XCTAssertTrue(jsonText.contains(#""anthropic" : "https://anthropic.example.com/v1/messages""#))
        XCTAssertFalse(jsonText.contains(#"https:\/\/"#))
    }

    func testExportIncludesMultipleAPIKeys() async throws {
        let channel = createTestChannel()
        try isolatedKeychain.manager.setAPIKeys(["key-a", "key-b"], for: channel.id)

        let data = try await service.exportChannels([channel])
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let channels = json?["channels"] as? [[String: Any]]
        let firstChannel = channels?.first

        XCTAssertEqual(firstChannel?["apiKey"] as? String, "key-a")
        XCTAssertEqual(firstChannel?["apiKeys"] as? [String], ["key-a", "key-b"])
    }

    func testExportThenImportPreservesEncryptedMultipleAPIKeys() async throws {
        let channel = createTestChannel()
        try isolatedKeychain.manager.setAPIKeys(["key-a", "key-b"], for: channel.id)

        let data = try await service.exportChannels([channel], password: "password")
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let channelsJSON = json?["channels"] as? [[String: Any]]
        let exportedAPIKeys = try XCTUnwrap(channelsJSON?.first?["apiKeys"] as? [String])
        XCTAssertNotEqual(exportedAPIKeys, ["key-a", "key-b"])

        let (exportFile, exportedChannels) = try service.parseImportData(data)
        let result = service.importChannels(exportedChannels, exportFile: exportFile, password: "password")
        let importedChannelID = try XCTUnwrap(isolatedStore.store.channels.first?.id)

        XCTAssertEqual(result.imported, 1)
        XCTAssertEqual(isolatedKeychain.manager.getAPIKeys(for: importedChannelID), ["key-a", "key-b"])
    }

    func testExportWithMultipleChannels() async throws {
        let channel1 = createTestChannel(
            id: "ch1",
            name: "Channel 1",
            baseURL: "https://api1.test.com/v1"
        )
        let channel2 = createTestChannel(
            id: "ch2",
            name: "Channel 2",
            baseURL: "https://api2.test.com/v1",
            protocolType: .anthropic
        )

        try isolatedKeychain.manager.setAPIKey("key1", for: "ch1")
        try isolatedKeychain.manager.setAPIKey("key2", for: "ch2")

        defer {
            try? isolatedKeychain.manager.removeAPIKey(for: "ch1")
            try? isolatedKeychain.manager.removeAPIKey(for: "ch2")
        }

                let data = try await service.exportChannels([channel1, channel2])

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let channels = json?["channels"] as? [[String: Any]]
        XCTAssertEqual(channels?.count, 2)
    }

    func testExportSkipsChannelWithoutAPIKey() async throws {
        let channel = createTestChannel(id: "no-key-channel")

        // Don't set API key
                let data = try await service.exportChannels([channel])

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let channels = json?["channels"] as? [[String: Any]]
        XCTAssertEqual(channels?.count, 0)
    }

    // MARK: - InputTypes Tests

    func testExportWithInputTypes() async throws {
        let model = createTestModel(inputTypes: ["text", "image", "audio"])
        let channel = createTestChannel(models: [model])

        try isolatedKeychain.manager.setAPIKey("test-key", for: channel.id)
        defer { try? isolatedKeychain.manager.removeAPIKey(for: channel.id) }

                let data = try await service.exportChannels([channel])

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let channels = json?["channels"] as? [[String: Any]]
        let models = channels?.first?["models"] as? [[String: Any]]
        let inputTypes = models?.first?["inputTypes"] as? [String]

        XCTAssertEqual(inputTypes?.sorted(), ["audio", "image", "text"])
    }

    // MARK: - Import Tests

    func testImportValidFile() async throws {
        let json: [String: Any] = [
            "format": "smartllmrouter/channels",
            "version": 1,
            "exportedAt": "2026-05-29T22:00:00Z",
            "appVersion": "1.0.0",
            "encrypted": false,
            "channels": [
                [
                    "name": "Imported Channel",
                    "baseURL": "https://imported.test.com/v1",
                    "protocol": "OpenAI",
                    "priority": 1,
                    "apiKey": "imported-key-12345",
                    "models": [
                        [
                            "identifier": "gpt-4o",
                            "displayName": "GPT-4o",
                            "contextLength": 128000,
                            "inputPricePer1M": 2.5,
                            "outputPricePer1M": 10.0,
                            "isEnabled": true,
                            "inputTypes": ["text", "image"]
                        ]
                    ]
                ]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
                let (exportFile, channels) = try await service.parseImportData(data)

        XCTAssertEqual(exportFile.format, "smartllmrouter/channels")
        XCTAssertEqual(exportFile.version, 1)
        XCTAssertFalse(exportFile.encrypted)
        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels.first?.name, "Imported Channel")
        XCTAssertEqual(channels.first?.apiKey, "imported-key-12345")
        XCTAssertEqual(channels.first?.models.first?.inputTypes, ["text", "image"])
    }

    func testImportInvalidFormat() async {
        let json: [String: Any] = [
            "format": "invalid/format",
            "version": 1,
            "exportedAt": "2026-05-29T22:00:00Z",
            "appVersion": "1.0.0",
            "encrypted": false,
            "channels": []
        ]

        let data = try! JSONSerialization.data(withJSONObject: json)

        do {
            _ = try await service.parseImportData(data)
            XCTFail("Expected error")
        } catch let error as ChannelExportService.ImportError {
            if case .invalidFormat = error {
                // Expected
            } else {
                XCTFail("Expected invalidFormat error")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testImportUnsupportedVersion() async {
        let json: [String: Any] = [
            "format": "smartllmrouter/channels",
            "version": 0,
            "exportedAt": "2026-05-29T22:00:00Z",
            "appVersion": "1.0.0",
            "encrypted": false,
            "channels": []
        ]

        let data = try! JSONSerialization.data(withJSONObject: json)

        do {
            _ = try await service.parseImportData(data)
            XCTFail("Expected error")
        } catch let error as ChannelExportService.ImportError {
            if case .unsupportedVersion(let version) = error {
                XCTAssertEqual(version, 0)
            } else {
                XCTFail("Expected unsupportedVersion error")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Encryption Tests

    func testExportWithEncryption() async throws {
        let channel = createTestChannel()
        try isolatedKeychain.manager.setAPIKey("secret-api-key", for: channel.id)
        defer { try? isolatedKeychain.manager.removeAPIKey(for: channel.id) }

                let password = "test-password-123"
        let data = try await service.exportChannels([channel], password: password)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // Verify encryption metadata
        XCTAssertEqual(json?["encrypted"] as? Bool, true)
        XCTAssertNotNil(json?["encryptionSalt"])
        XCTAssertNotNil(json?["encryptionNonce"])

        // Verify API key is encrypted (not plain text)
        let channels = json?["channels"] as? [[String: Any]]
        let apiKey = channels?.first?["apiKey"] as? String
        XCTAssertNotEqual(apiKey, "secret-api-key")
        XCTAssertTrue(apiKey?.isEmpty == false)
    }

    func testExportWithoutEncryption() async throws {
        let channel = createTestChannel()
        try isolatedKeychain.manager.setAPIKey("plain-key", for: channel.id)
        defer { try? isolatedKeychain.manager.removeAPIKey(for: channel.id) }

                let data = try await service.exportChannels([channel], password: nil)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // Verify no encryption
        XCTAssertEqual(json?["encrypted"] as? Bool, false)
        XCTAssertNil(json?["encryptionSalt"])
        XCTAssertNil(json?["encryptionNonce"])

        // Verify API key is plain text
        let channels = json?["channels"] as? [[String: Any]]
        let apiKey = channels?.first?["apiKey"] as? String
        XCTAssertEqual(apiKey, "plain-key")
    }

    func testExportWithEmptyPassword() async throws {
        let channel = createTestChannel()
        try isolatedKeychain.manager.setAPIKey("test-key", for: channel.id)
        defer { try? isolatedKeychain.manager.removeAPIKey(for: channel.id) }

                let data = try await service.exportChannels([channel], password: "")

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // Empty password should not encrypt
        XCTAssertEqual(json?["encrypted"] as? Bool, false)
    }

    // MARK: - Round-trip Tests

    func testExportThenImport() async throws {
        // Create and export
        let originalModel = createTestModel(inputTypes: ["text", "image"])
        let originalChannel = createTestChannel(
            id: "original-id",
            name: "Original Channel",
            models: [originalModel]
        )
        try isolatedKeychain.manager.setAPIKey("original-key", for: "original-id")
        defer { try? isolatedKeychain.manager.removeAPIKey(for: "original-id") }

                let data = try await service.exportChannels([originalChannel])

        // Parse import
        let (exportFile, channels) = try await service.parseImportData(data)

        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels.first?.name, "Original Channel")
        XCTAssertEqual(channels.first?.apiKey, "original-key")
        XCTAssertEqual(channels.first?.models.first?.inputTypes, ["text", "image"])
    }

    func testExportThenImportWithEncryption() async throws {
        // Create and export with encryption
        let originalChannel = createTestChannel()
        try isolatedKeychain.manager.setAPIKey("secret-key", for: originalChannel.id)
        defer { try? isolatedKeychain.manager.removeAPIKey(for: originalChannel.id) }

                let password = "strong-password-123"
        let data = try await service.exportChannels([originalChannel], password: password)

        // Parse import
        let (exportFile, channels) = try await service.parseImportData(data)

        XCTAssertTrue(exportFile.encrypted)
        XCTAssertNotNil(exportFile.encryptionSalt)
        XCTAssertNotNil(exportFile.encryptionNonce)

        // Encrypted key should not be the original
        XCTAssertNotEqual(channels.first?.apiKey, "secret-key")
    }

    // MARK: - Backward Compatibility Tests

    func testImportOldFormatWithSupportsVision() async throws {
        // Simulate old format with supportsVision field
        let json: [String: Any] = [
            "format": "smartllmrouter/channels",
            "version": 1,
            "exportedAt": "2026-05-29T22:00:00Z",
            "appVersion": "1.0.0",
            "encrypted": false,
            "channels": [
                [
                    "name": "Old Format Channel",
                    "baseURL": "https://old.test.com/v1",
                    "protocol": "OpenAI",
                    "priority": 1,
                    "apiKey": "old-key",
                    "models": [
                        [
                            "identifier": "gpt-4-vision",
                            "displayName": "GPT-4 Vision",
                            "isEnabled": true,
                            "supportsVision": true
                        ]
                    ]
                ]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
                let (exportFile, channels) = try await service.parseImportData(data)

        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels.first?.name, "Old Format Channel")
    }

    // MARK: - Edge Cases

    func testExportEmptyChannelsArray() async throws {
                let data = try await service.exportChannels([])

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let channels = json?["channels"] as? [[String: Any]]
        XCTAssertEqual(channels?.count, 0)
    }

    func testExportChannelWithEmptyModels() async throws {
        let channel = createTestChannel(models: [])
        try isolatedKeychain.manager.setAPIKey("test-key", for: channel.id)
        defer { try? isolatedKeychain.manager.removeAPIKey(for: channel.id) }

                let data = try await service.exportChannels([channel])

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let channels = json?["channels"] as? [[String: Any]]
        let models = channels?.first?["models"] as? [[String: Any]]
        XCTAssertEqual(models?.count, 0)
    }

    func testExportPreservesModelMetadata() async throws {
        let model = ModelEntry(
            id: "test-model-id",
            identifier: "gpt-4o",
            displayName: "GPT-4o",
            contextLength: 128000,
            inputPricePer1M: 2.5,
            outputPricePer1M: 10.0,
            isEnabled: false,
            inputTypes: ["text", "image", "video"]
        )
        let channel = createTestChannel(models: [model])
        try isolatedKeychain.manager.setAPIKey("test-key", for: channel.id)
        defer { try? isolatedKeychain.manager.removeAPIKey(for: channel.id) }

                let data = try await service.exportChannels([channel])

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let channels = json?["channels"] as? [[String: Any]]
        let exportedModel = channels?.first?["models"] as? [[String: Any]]

        XCTAssertEqual(exportedModel?.first?["identifier"] as? String, "gpt-4o")
        XCTAssertEqual(exportedModel?.first?["displayName"] as? String, "GPT-4o")
        XCTAssertEqual(exportedModel?.first?["contextLength"] as? Int, 128000)
        XCTAssertEqual(exportedModel?.first?["inputPricePer1M"] as? Double, 2.5)
        XCTAssertEqual(exportedModel?.first?["outputPricePer1M"] as? Double, 10.0)
        XCTAssertEqual(exportedModel?.first?["isEnabled"] as? Bool, false)
        XCTAssertEqual(exportedModel?.first?["inputTypes"] as? [String], ["text", "image", "video"])
    }
}

// MARK: - ModelEntry InputTypes Tests

final class ModelEntryInputTypesTests: XCTestCase {

    func testDefaultInputTypes() {
        let model = ModelEntry(
            id: "test",
            identifier: "test-model",
            displayName: "Test Model"
        )
        XCTAssertEqual(model.inputTypes, ["text"])
    }

    func testCustomInputTypes() {
        let model = ModelEntry(
            id: "test",
            identifier: "test-model",
            displayName: "Test Model",
            inputTypes: ["text", "image", "audio"]
        )
        XCTAssertEqual(model.inputTypes, ["text", "image", "audio"])
    }

    func testSupportsVisionComputedProperty() {
        let modelWithImage = ModelEntry(
            id: "test",
            identifier: "test",
            displayName: "test",
            inputTypes: ["text", "image"]
        )
        XCTAssertTrue(modelWithImage.supportsVision)

        let modelWithoutImage = ModelEntry(
            id: "test2",
            identifier: "test2",
            displayName: "test2",
            inputTypes: ["text"]
        )
        XCTAssertFalse(modelWithoutImage.supportsVision)
    }

    func testSupportsMethod() {
        let model = ModelEntry(
            id: "test",
            identifier: "test",
            displayName: "test",
            inputTypes: ["text", "image", "audio"]
        )

        XCTAssertTrue(model.supports(.text))
        XCTAssertTrue(model.supports(.image))
        XCTAssertTrue(model.supports(.audio))
        XCTAssertFalse(model.supports(.video))
    }

    func testInputTypeEnum() {
        XCTAssertEqual(InputType.text.rawValue, "text")
        XCTAssertEqual(InputType.image.rawValue, "image")
        XCTAssertEqual(InputType.video.rawValue, "video")
        XCTAssertEqual(InputType.audio.rawValue, "audio")
        XCTAssertEqual(InputType.allCases.count, 4)
    }

    // MARK: - Backward Compatibility

    func testDecodeOldSupportsVisionTrue() throws {
        let json = """
        {
            "id": "test",
            "identifier": "gpt-4-vision",
            "displayName": "GPT-4 Vision",
            "isEnabled": true,
            "supportsVision": true
        }
        """

        let data = json.data(using: .utf8)!
        let model = try JSONDecoder().decode(ModelEntry.self, from: data)

        XCTAssertEqual(model.inputTypes, ["text", "image"])
        XCTAssertTrue(model.supportsVision)
    }

    func testDecodeOldSupportsVisionFalse() throws {
        let json = """
        {
            "id": "test",
            "identifier": "gpt-4",
            "displayName": "GPT-4",
            "isEnabled": true,
            "supportsVision": false
        }
        """

        let data = json.data(using: .utf8)!
        let model = try JSONDecoder().decode(ModelEntry.self, from: data)

        XCTAssertEqual(model.inputTypes, ["text"])
        XCTAssertFalse(model.supportsVision)
    }

    func testDecodeNewInputTypesFormat() throws {
        let json = """
        {
            "id": "test",
            "identifier": "mimo-v2-tts",
            "displayName": "MiMo v2 TTS",
            "isEnabled": true,
            "inputTypes": ["text", "audio"]
        }
        """

        let data = json.data(using: .utf8)!
        let model = try JSONDecoder().decode(ModelEntry.self, from: data)

        XCTAssertEqual(model.inputTypes, ["text", "audio"])
    }

    func testDecodePrefersInputTypesOverSupportsVision() throws {
        // When both fields present, inputTypes should take precedence
        let json = """
        {
            "id": "test",
            "identifier": "test-model",
            "displayName": "Test",
            "isEnabled": true,
            "supportsVision": false,
            "inputTypes": ["text", "image", "video"]
        }
        """

        let data = json.data(using: .utf8)!
        let model = try JSONDecoder().decode(ModelEntry.self, from: data)

        XCTAssertEqual(model.inputTypes, ["text", "image", "video"])
    }

    func testEncodeProducesInputTypes() throws {
        let model = ModelEntry(
            id: "test",
            identifier: "test-model",
            displayName: "Test",
            inputTypes: ["text", "image"]
        )

        let data = try JSONEncoder().encode(model)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json?["inputTypes"])
        XCTAssertNil(json?["supportsVision"])
        XCTAssertEqual(json?["inputTypes"] as? [String], ["text", "image"])
    }
}
