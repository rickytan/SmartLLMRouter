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

    private func writeJSON(_ json: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    private func readJSON(from url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
