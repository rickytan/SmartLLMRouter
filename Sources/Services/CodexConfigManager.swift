import Foundation

/// Manages Codex CLI configuration (~/.codex/config.toml).
@MainActor
final class CodexConfigManager: ObservableObject {
    @Published private(set) var isActive: Bool = false
    @Published private(set) var currentURL: String = ""
    @Published private(set) var configExists: Bool = false
    @Published private(set) var lastError: String?

    private let configDirectory: URL
    private let configFile: URL
    private let providerID = "smartllmrouter"
    private let providerKey = "model_provider"
    private let providerHeader = "[model_providers.smartllmrouter]"

    init(configDirectory: URL? = nil) {
        let directory = configDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        self.configDirectory = directory
        self.configFile = directory.appendingPathComponent("config.toml")
        loadState(port: 1897)
    }

    func refresh(port: Int = 1897) {
        loadState(port: port)
    }

    func toggleTakeover(enable: Bool, port: Int = 1897) {
        if enable {
            activateTakeover(port: port)
        } else {
            deactivateTakeover(port: port)
        }
    }

    private func proxyURL(port: Int) -> String {
        "http://127.0.0.1:\(port)/v1"
    }

    private func loadState(port: Int) {
        let fm = FileManager.default
        configExists = fm.fileExists(atPath: configFile.path)

        guard configExists,
              let content = try? String(contentsOf: configFile, encoding: .utf8)
        else {
            currentURL = ""
            isActive = false
            return
        }

        currentURL = modelProviderBaseURL(in: content) ?? ""
        isActive = topLevelValue(for: providerKey, in: content) == providerID
            && currentURL == proxyURL(port: port)
    }

    private func activateTakeover(port: Int) {
        lastError = nil

        let fm = FileManager.default
        do {
            if !fm.fileExists(atPath: configDirectory.path) {
                try fm.createDirectory(at: configDirectory, withIntermediateDirectories: true)
            }

            var content = fm.fileExists(atPath: configFile.path)
                ? try String(contentsOf: configFile, encoding: .utf8)
                : ""
            if fm.fileExists(atPath: configFile.path) {
                try backupConfigFile()
            }

            content = removeModelProviderSection(from: content)
            content = setTopLevelValue(providerID, for: providerKey, in: content)
            content = appendSmartLLMRouterProvider(to: content, port: port)
            try write(content)

            configExists = true
            currentURL = proxyURL(port: port)
            isActive = true
            Log.info("Codex config takeover activated: \(providerHeader).base_url set")
        } catch {
            setError("Failed to update Codex config: \(error.localizedDescription)")
        }
    }

    private func deactivateTakeover(port: Int) {
        lastError = nil

        do {
            var content = try String(contentsOf: configFile, encoding: .utf8)
            let backupContent = try findLatestBackup().map {
                try String(contentsOf: $0, encoding: .utf8)
            }

            content = removeModelProviderSection(from: content)
            if let previousProvider = backupContent.flatMap({ topLevelValue(for: providerKey, in: $0) }) {
                content = setTopLevelValue(previousProvider, for: providerKey, in: content)
            } else {
                content = removeTopLevelKey(providerKey, from: content)
            }

            try write(content)
            loadState(port: port)
            Log.info("Codex provider \(providerID) restored")
        } catch {
            setError("Failed to restore Codex config: \(error.localizedDescription)")
        }
    }

    private func appendSmartLLMRouterProvider(to content: String, port: Int) -> String {
        let block = """

        \(providerHeader)
        name = "SmartLLM Router"
        base_url = "\(proxyURL(port: port))"
        wire_api = "chat"
        requires_openai_auth = false

        """
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return block.trimmingCharacters(in: .newlines) + "\n" }
        return trimmed + "\n" + block
    }

    private func modelProviderBaseURL(in content: String) -> String? {
        var isInProviderSection = false
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == providerHeader {
                isInProviderSection = true
                continue
            }
            if isInProviderSection, trimmed.hasPrefix("[") {
                return nil
            }
            if isInProviderSection,
               let value = parseTOMLStringAssignment(line, key: "base_url") {
                return value
            }
        }
        return nil
    }

    private func removeModelProviderSection(from content: String) -> String {
        var lines: [String] = []
        var isSkipping = false

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == providerHeader {
                isSkipping = true
                continue
            }
            if isSkipping, trimmed.hasPrefix("[") {
                isSkipping = false
            }
            if !isSkipping {
                lines.append(line)
            }
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private func topLevelValue(for key: String, in content: String) -> String? {
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("[") { return nil }
            if let value = parseTOMLStringAssignment(line, key: key) {
                return value
            }
        }
        return nil
    }

    private func setTopLevelValue(_ value: String, for key: String, in content: String) -> String {
        var lines = content.components(separatedBy: .newlines)
        var insertIndex = lines.endIndex

        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("[") {
                insertIndex = index
                break
            }
            if parseTOMLStringAssignment(lines[index], key: key) != nil {
                lines[index] = "\(key) = \"\(escapedTOMLString(value))\""
                return lines.joined(separator: "\n")
            }
        }

        lines.insert("\(key) = \"\(escapedTOMLString(value))\"", at: insertIndex)
        return lines.joined(separator: "\n")
    }

    private func removeTopLevelKey(_ key: String, from content: String) -> String {
        var lines: [String] = []
        var isTopLevel = true

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("[") {
                isTopLevel = false
            }
            if isTopLevel, parseTOMLStringAssignment(line, key: key) != nil {
                continue
            }
            lines.append(line)
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private func parseTOMLStringAssignment(_ line: String, key: String) -> String? {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        let pattern = #"^\s*"# + escapedKey + #"\s*=\s*"((?:\\.|[^"\\])*)"\s*(?:#.*)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let valueRange = Range(match.range(at: 1), in: line)
        else {
            return nil
        }
        return unescapedTOMLString(String(line[valueRange]))
    }

    private func escapedTOMLString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func unescapedTOMLString(_ value: String) -> String {
        var result = ""
        var iterator = value.makeIterator()
        while let character = iterator.next() {
            if character == "\\", let next = iterator.next() {
                result.append(next)
            } else {
                result.append(character)
            }
        }
        return result
    }

    private func write(_ content: String) throws {
        try content.write(to: configFile, atomically: true, encoding: .utf8)
    }

    private func backupConfigFile() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: configFile.path) else { return }

        var backupURL = configDirectory.appendingPathComponent("config.toml.bak")
        if fm.fileExists(atPath: backupURL.path) {
            var counter = 1
            repeat {
                backupURL = configDirectory.appendingPathComponent("config.toml.bak.\(counter)")
                counter += 1
            } while fm.fileExists(atPath: backupURL.path)
        }

        try fm.copyItem(at: configFile, to: backupURL)
        Log.info("Backed up Codex config to \(backupURL.lastPathComponent)")
    }

    private func findLatestBackup() -> URL? {
        let fm = FileManager.default
        var candidates: [(url: URL, number: Int)] = []

        let backupURL = configDirectory.appendingPathComponent("config.toml.bak")
        if fm.fileExists(atPath: backupURL.path) {
            candidates.append((backupURL, 0))
        }

        var counter = 1
        while counter < 100 {
            let numberedBackup = configDirectory.appendingPathComponent("config.toml.bak.\(counter)")
            if fm.fileExists(atPath: numberedBackup.path) {
                candidates.append((numberedBackup, counter))
            } else {
                break
            }
            counter += 1
        }

        return candidates.max(by: { $0.number < $1.number })?.url
    }

    private func setError(_ message: String) {
        lastError = message
        Log.error(message)
    }
}
