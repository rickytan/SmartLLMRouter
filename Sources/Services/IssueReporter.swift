import AppKit
import Foundation

enum IssueReporter {
    struct Metadata: Equatable {
        let version: String
        let build: String
        let operatingSystem: String
        let architecture: String

        static var current: Metadata {
            Metadata(
                version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                architecture: currentArchitecture
            )
        }

        private static var currentArchitecture: String {
            #if arch(arm64)
                return "arm64"
            #elseif arch(x86_64)
                return "x86_64"
            #else
                return "unknown"
            #endif
        }
    }

    static func issueURL(metadata: Metadata = .current) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/rickytan/SmartLLMRouter/issues/new"
        components.queryItems = [
            URLQueryItem(name: "title", value: "[Bug] "),
            URLQueryItem(name: "body", value: issueBody(metadata: metadata))
        ]
        return components.url
    }

    static func openIssue(metadata: Metadata = .current) {
        guard let url = issueURL(metadata: metadata) else { return }
        NSWorkspace.shared.open(url)
    }

    static func exportDiagnostics(
        to destinationURL: URL,
        logFileURLs: [URL] = LoggerManager.logFileURLs(),
        metadata: Metadata = .current
    ) throws {
        let diagnostics = try diagnosticsText(logFileURLs: logFileURLs, metadata: metadata)
        try diagnostics.write(to: destinationURL, atomically: true, encoding: .utf8)
    }

    static func diagnosticsText(logFileURLs: [URL], metadata: Metadata) throws -> String {
        var sections = [diagnosticsHeader(metadata: metadata)]

        if logFileURLs.isEmpty {
            sections.append("No local log files were available.")
        } else {
            for url in logFileURLs {
                let contents = try String(contentsOf: url, encoding: .utf8)
                sections.append("--- \(url.lastPathComponent) ---\n\(LoggerManager.redact(contents))")
            }
        }

        return sections.joined(separator: "\n\n") + "\n"
    }

    private static func issueBody(metadata: Metadata) -> String {
        """
        ## Problem

        Describe what happened and what you expected.

        ## Steps to reproduce

        1.
        2.
        3.

        ## Environment

        - SmartLLMRouter: \(metadata.version) (\(metadata.build))
        - macOS: \(metadata.operatingSystem)
        - Architecture: \(metadata.architecture)

        ## Diagnostics

        If you exported diagnostics, drag the generated text file here after reviewing it.
        """
    }

    private static func diagnosticsHeader(metadata: Metadata) -> String {
        """
        SmartLLMRouter Diagnostics
        Version: \(metadata.version) (\(metadata.build))
        macOS: \(metadata.operatingSystem)
        Architecture: \(metadata.architecture)
        Exported: \(ISO8601DateFormatter().string(from: Date()))

        Logs are automatically redacted, but review this file before attaching it to a public issue.
        """
    }
}
