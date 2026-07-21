import XCTest
@testable import SmartLLMRouter

@MainActor
final class ConfigurationManagerTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConfigurationManagerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
        try await super.tearDown()
    }

    func testShellConfigurationIsIdempotent() async throws {
        let shellFile = temporaryDirectory.appendingPathComponent(".zshenv")
        let manager = ShellConfigManager(shellFile: shellFile)

        _ = await manager.configure(port: 1897)
        let firstContent = try String(contentsOf: shellFile, encoding: .utf8)
        _ = await manager.configure(port: 1897)
        let secondContent = try String(contentsOf: shellFile, encoding: .utf8)

        XCTAssertEqual(secondContent, firstContent)
        XCTAssertEqual(secondContent.components(separatedBy: "# SmartLLM Router - Auto-generated").count - 1, 1)
        XCTAssertTrue(secondContent.contains("export OPENAI_BASE_URL=http://localhost:1897/v1"))
        XCTAssertTrue(secondContent.contains("export ANTHROPIC_BASE_URL=http://localhost:1897\n"))
        XCTAssertFalse(secondContent.contains("ANTHROPIC_BASE_URL=http://localhost:1897/v1"))
    }

    func testShellConfigurationRecognizesExistingManualExports() async throws {
        let shellFile = temporaryDirectory.appendingPathComponent(".zshenv")
        let original = """
        export OPENAI_BASE_URL=http://localhost:1897/v1
        export ANTHROPIC_BASE_URL=http://localhost:1897
        export SMARTLLM_ROUTER_PORT=1897
        """
        try original.write(to: shellFile, atomically: true, encoding: .utf8)
        let manager = ShellConfigManager(shellFile: shellFile)

        _ = await manager.configure(port: 1897)

        XCTAssertEqual(try String(contentsOf: shellFile, encoding: .utf8), original)
        XCTAssertTrue(manager.isConfigured)
    }

    func testShellConfigurationReplacesManagedBlockWhenPortChanges() async throws {
        let shellFile = temporaryDirectory.appendingPathComponent(".zshenv")
        let manager = ShellConfigManager(shellFile: shellFile)
        _ = await manager.configure(port: 1897)
        var content = try String(contentsOf: shellFile, encoding: .utf8)
        content = "export PATH=/opt/homebrew/bin:$PATH\n\n" + content
        try content.write(to: shellFile, atomically: true, encoding: .utf8)

        manager.checkConfigurationStatus(port: 4242)
        XCTAssertEqual(manager.configurationStatus, .needsUpdate)
        XCTAssertFalse(manager.isConfigured)

        _ = await manager.configure(port: 4242)
        let updated = try String(contentsOf: shellFile, encoding: .utf8)

        XCTAssertTrue(updated.contains("export PATH=/opt/homebrew/bin:$PATH"))
        XCTAssertTrue(updated.contains("export ANTHROPIC_BASE_URL=http://localhost:4242"))
        XCTAssertFalse(updated.contains("localhost:1897"))
        XCTAssertEqual(updated.components(separatedBy: "# SmartLLM Router - Auto-generated").count - 1, 1)
        XCTAssertEqual(manager.configurationStatus, .configured)
    }

    func testShellConfigurationReplacesLegacyAnthropicURLWithV1Suffix() async throws {
        let shellFile = temporaryDirectory.appendingPathComponent(".zshenv")
        let legacy = """
        # SmartLLM Router - Auto-generated
        # Set proxy URLs for LLM API clients
        export OPENAI_BASE_URL=http://localhost:1897/v1
        export ANTHROPIC_BASE_URL=http://localhost:1897/v1
        export SMARTLLM_ROUTER_PORT=1897

        """
        try legacy.write(to: shellFile, atomically: true, encoding: .utf8)
        let manager = ShellConfigManager(shellFile: shellFile)

        _ = await manager.configure(port: 1897)
        let updated = try String(contentsOf: shellFile, encoding: .utf8)

        XCTAssertTrue(updated.contains("export ANTHROPIC_BASE_URL=http://localhost:1897\n"))
        XCTAssertFalse(updated.contains("ANTHROPIC_BASE_URL=http://localhost:1897/v1"))
    }

    func testClaudeTakeoverUpdatesNestedEnvironmentAndPreservesOtherSettings() throws {
        let configDirectory = temporaryDirectory.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        let configFile = configDirectory.appendingPathComponent("settings.json")
        let original: [String: Any] = [
            "model": "glm-5.2",
            "url": "http://127.0.0.1:1897",
            "env": [
                "ANTHROPIC_BASE_URL": "https://example.com/api/coding",
                "ANTHROPIC_AUTH_TOKEN": "test-token"
            ]
        ]
        try writeJSON(original, to: configFile)
        let manager = ClaudeCodeConfigManager(configDirectory: configDirectory)

        manager.toggleTakeover(enable: true, port: 4242)

        let updated = try readJSON(from: configFile)
        let env = try XCTUnwrap(updated["env"] as? [String: Any])
        XCTAssertEqual(env["ANTHROPIC_BASE_URL"] as? String, "http://127.0.0.1:4242")
        XCTAssertEqual(env["ANTHROPIC_AUTH_TOKEN"] as? String, "test-token")
        XCTAssertEqual(updated["model"] as? String, "glm-5.2")
        XCTAssertNil(updated["url"])
        XCTAssertTrue(manager.isActive)
        XCTAssertEqual(manager.currentURL, "http://127.0.0.1:4242")
        XCTAssertTrue(FileManager.default.fileExists(atPath: configDirectory.appendingPathComponent("settings.json.bak").path))

        let rawContent = try String(contentsOf: configFile, encoding: .utf8)
        XCTAssertTrue(rawContent.contains(#""ANTHROPIC_BASE_URL" : "http://127.0.0.1:4242""#))
        XCTAssertFalse(rawContent.contains(#"http:\/\/127.0.0.1"#))
    }

    func testClaudeTakeoverRestoreReturnsNestedEnvironmentToPreviousValue() throws {
        let configDirectory = temporaryDirectory.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        let configFile = configDirectory.appendingPathComponent("settings.json")
        try writeJSON([
            "env": ["ANTHROPIC_BASE_URL": "https://example.com/api/coding"],
            "theme": "dark"
        ], to: configFile)
        let manager = ClaudeCodeConfigManager(configDirectory: configDirectory)

        manager.toggleTakeover(enable: true, port: 1897)
        var active = try readJSON(from: configFile)
        active["theme"] = "light"
        try writeJSON(active, to: configFile)
        manager.toggleTakeover(enable: false, port: 1897)

        let restored = try readJSON(from: configFile)
        let env = try XCTUnwrap(restored["env"] as? [String: Any])
        XCTAssertEqual(env["ANTHROPIC_BASE_URL"] as? String, "https://example.com/api/coding")
        XCTAssertEqual(restored["theme"] as? String, "light")
        XCTAssertFalse(manager.isActive)

        let rawContent = try String(contentsOf: configFile, encoding: .utf8)
        XCTAssertTrue(rawContent.contains(#""ANTHROPIC_BASE_URL" : "https://example.com/api/coding""#))
        XCTAssertFalse(rawContent.contains(#"https:\/\/example.com"#))
    }

    func testClaudeTakeoverCanDeactivateConfigCreatedFromScratch() throws {
        let configDirectory = temporaryDirectory.appendingPathComponent(".claude", isDirectory: true)
        let configFile = configDirectory.appendingPathComponent("settings.json")
        let manager = ClaudeCodeConfigManager(configDirectory: configDirectory)

        manager.toggleTakeover(enable: true, port: 1897)
        manager.toggleTakeover(enable: false, port: 1897)

        let restored = try readJSON(from: configFile)
        XCTAssertNil(restored["env"])
        XCTAssertFalse(manager.isActive)
    }

    func testClaudeTakeoverDoesNotOverwriteInvalidJSON() throws {
        let configDirectory = temporaryDirectory.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        let configFile = configDirectory.appendingPathComponent("settings.json")
        try "not-json".write(to: configFile, atomically: true, encoding: .utf8)
        let manager = ClaudeCodeConfigManager(configDirectory: configDirectory)

        manager.toggleTakeover(enable: true, port: 1897)

        XCTAssertEqual(try String(contentsOf: configFile, encoding: .utf8), "not-json")
        XCTAssertNotNil(manager.lastError)
        XCTAssertFalse(manager.isActive)
    }

    func testOpenCodeTakeoverAddsProviderAndPreservesExistingProviders() throws {
        let configDirectory = temporaryDirectory.appendingPathComponent(".config/opencode", isDirectory: true)
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        let configFile = configDirectory.appendingPathComponent("opencode.json")
        try writeJSON([
            "provider": [
                "huoshan": [
                    "name": "Volcengine",
                    "npm": "@ai-sdk/openai-compatible",
                    "options": [
                        "baseURL": "https://ark.cn-beijing.volces.com/api/coding",
                        "apiKey": "existing-key"
                    ]
                ]
            ],
            "enabled_providers": ["huoshan"],
            "disabled_providers": ["smartllmrouter"]
        ], to: configFile)
        let manager = OpenCodeConfigManager(configDirectory: configDirectory)

        manager.toggleTakeover(enable: true, port: 4242)

        let updated = try readJSON(from: configFile)
        let providers = try XCTUnwrap(updated["provider"] as? [String: Any])
        XCTAssertNotNil(providers["huoshan"])
        let smartProvider = try XCTUnwrap(providers["smartllmrouter"] as? [String: Any])
        let options = try XCTUnwrap(smartProvider["options"] as? [String: Any])
        XCTAssertEqual(smartProvider["name"] as? String, "SmartLLM Router")
        XCTAssertEqual(smartProvider["npm"] as? String, "@ai-sdk/openai-compatible")
        XCTAssertEqual(options["baseURL"] as? String, "http://127.0.0.1:4242/v1")
        XCTAssertEqual(options["apiKey"] as? String, "smartllmrouter")
        XCTAssertEqual(updated["enabled_providers"] as? [String], ["huoshan", "smartllmrouter"])
        XCTAssertEqual(updated["disabled_providers"] as? [String], [])
        XCTAssertTrue(manager.isActive)
        XCTAssertEqual(manager.currentURL, "http://127.0.0.1:4242/v1")
        XCTAssertTrue(FileManager.default.fileExists(atPath: configDirectory.appendingPathComponent("opencode.json.bak").path))

        let rawContent = try String(contentsOf: configFile, encoding: .utf8)
        XCTAssertTrue(rawContent.contains(#""baseURL" : "http://127.0.0.1:4242/v1""#))
        XCTAssertFalse(rawContent.contains(#"http:\/\/127.0.0.1"#))
    }

    func testOpenCodeTakeoverRestoreRemovesSmartProviderWhenItDidNotExistBefore() throws {
        let configDirectory = temporaryDirectory.appendingPathComponent(".config/opencode", isDirectory: true)
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        let configFile = configDirectory.appendingPathComponent("opencode.json")
        try writeJSON([
            "theme": "dark",
            "provider": [
                "huoshan": [
                    "name": "Volcengine",
                    "options": ["baseURL": "https://ark.cn-beijing.volces.com/api/coding"]
                ]
            ],
            "enabled_providers": ["huoshan"]
        ], to: configFile)
        let manager = OpenCodeConfigManager(configDirectory: configDirectory)

        manager.toggleTakeover(enable: true, port: 1897)
        var active = try readJSON(from: configFile)
        active["theme"] = "light"
        try writeJSON(active, to: configFile)
        manager.toggleTakeover(enable: false, port: 1897)

        let restored = try readJSON(from: configFile)
        let providers = try XCTUnwrap(restored["provider"] as? [String: Any])
        XCTAssertNotNil(providers["huoshan"])
        XCTAssertNil(providers["smartllmrouter"])
        XCTAssertEqual(restored["theme"] as? String, "light")
        XCTAssertEqual(restored["enabled_providers"] as? [String], ["huoshan"])
        XCTAssertFalse(manager.isActive)
    }

    func testCodexTakeoverAddsChatProviderAndRestoresPreviousProvider() throws {
        let configDirectory = temporaryDirectory.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        let configFile = configDirectory.appendingPathComponent("config.toml")
        let original = """
        model = "gpt-5.5"
        model_provider = "openai"

        [mcp_servers.node]
        command = "node"
        """
        try original.write(to: configFile, atomically: true, encoding: .utf8)
        let manager = CodexConfigManager(configDirectory: configDirectory)

        manager.toggleTakeover(enable: true, port: 4242)

        let active = try String(contentsOf: configFile, encoding: .utf8)
        XCTAssertTrue(active.contains(#"model_provider = "smartllmrouter""#))
        XCTAssertTrue(active.contains("[model_providers.smartllmrouter]"))
        XCTAssertTrue(active.contains(#"base_url = "http://127.0.0.1:4242/v1""#))
        XCTAssertTrue(active.contains(#"wire_api = "chat""#))
        XCTAssertTrue(active.contains("requires_openai_auth = false"))
        XCTAssertTrue(active.contains("[mcp_servers.node]"))
        XCTAssertFalse(active.contains(#"http:\/\/127.0.0.1"#))
        XCTAssertTrue(manager.isActive)
        XCTAssertEqual(manager.currentURL, "http://127.0.0.1:4242/v1")
        XCTAssertTrue(FileManager.default.fileExists(atPath: configDirectory.appendingPathComponent("config.toml.bak").path))

        let userEditedActive = active.replacingOccurrences(of: #"model = "gpt-5.5""#, with: #"model = "glm-5.2""#)
        try userEditedActive.write(to: configFile, atomically: true, encoding: .utf8)
        manager.toggleTakeover(enable: false, port: 4242)

        let restored = try String(contentsOf: configFile, encoding: .utf8)
        XCTAssertTrue(restored.contains(#"model = "glm-5.2""#))
        XCTAssertTrue(restored.contains(#"model_provider = "openai""#))
        XCTAssertFalse(restored.contains("[model_providers.smartllmrouter]"))
        XCTAssertTrue(restored.contains("[mcp_servers.node]"))
        XCTAssertFalse(manager.isActive)
    }

    func testCodexTakeoverCanDeactivateConfigCreatedFromScratch() throws {
        let configDirectory = temporaryDirectory.appendingPathComponent(".codex", isDirectory: true)
        let configFile = configDirectory.appendingPathComponent("config.toml")
        let manager = CodexConfigManager(configDirectory: configDirectory)

        manager.toggleTakeover(enable: true, port: 1897)
        manager.toggleTakeover(enable: false, port: 1897)

        let restored = try String(contentsOf: configFile, encoding: .utf8)
        XCTAssertFalse(restored.contains("model_provider"))
        XCTAssertFalse(restored.contains("[model_providers.smartllmrouter]"))
        XCTAssertFalse(manager.isActive)
    }

    private func writeJSON(_ json: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url)
    }

    private func readJSON(from url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
