import XCTest
@testable import SmartLLMRouter

final class IssueReporterTests: XCTestCase {
    private let metadata = IssueReporter.Metadata(
        version: "1.2.3",
        build: "abc123",
        operatingSystem: "macOS 15.0",
        architecture: "arm64"
    )

    func testIssueURLPrefillsEnvironmentWithoutLogs() throws {
        let url = try XCTUnwrap(IssueReporter.issueURL(metadata: metadata))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: try XCTUnwrap(components.queryItems).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(components.path, "/rickytan/SmartLLMRouter/issues/new")
        XCTAssertEqual(query["title"], "[Bug] ")
        XCTAssertTrue(query["body"]?.contains("SmartLLMRouter: 1.2.3 (abc123)") == true)
        XCTAssertFalse(query["body"]?.contains("API key") == true)
    }

    func testDiagnosticsCombinesAndRedactsRetainedLogs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let logURL = directory.appendingPathComponent("router.log")
        try "Authorization: Bearer sk-test-123456789012345678901234\nrequest completed".write(
            to: logURL,
            atomically: true,
            encoding: .utf8
        )

        let diagnostics = try IssueReporter.diagnosticsText(logFileURLs: [logURL], metadata: metadata)

        XCTAssertTrue(diagnostics.contains("Version: 1.2.3 (abc123)"))
        XCTAssertTrue(diagnostics.contains("--- router.log ---"))
        XCTAssertTrue(diagnostics.contains("[REDACTED]"))
        XCTAssertFalse(diagnostics.contains("123456789012345678901234"))
        XCTAssertTrue(diagnostics.contains("request completed"))
    }

    func testDiagnosticsExplainsWhenNoLogsExist() throws {
        let diagnostics = try IssueReporter.diagnosticsText(logFileURLs: [], metadata: metadata)
        XCTAssertTrue(diagnostics.contains("No local log files were available."))
    }

    func testRedactionPreservesModelNamesWhileRemovingUnlabelledSecrets() {
        let modelLog = "model=deepseek-v4-pro-260425"
        XCTAssertEqual(LoggerManager.redact(modelLog), modelLog)
        XCTAssertEqual(
            LoggerManager.redact("secret=abcdefghijklmnopqrstuvwx"),
            "secret=[REDACTED]"
        )
    }
}
