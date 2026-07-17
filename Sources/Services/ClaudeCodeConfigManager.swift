import Foundation

/// Manages Claude Code configuration (~/.claude/settings.json).
@MainActor
final class ClaudeCodeConfigManager: ObservableObject {
    @Published private(set) var isActive: Bool = false
    @Published private(set) var currentURL: String = ""
    @Published private(set) var configExists: Bool = false
    @Published private(set) var lastError: String?

    private let configDirectory: URL
    private let configFile: URL
    private let envKey = "env"
    private let anthropicBaseURLKey = "ANTHROPIC_BASE_URL"
    private let jsonWritingOptions: JSONSerialization.WritingOptions = [
        .prettyPrinted,
        .sortedKeys,
        .withoutEscapingSlashes
    ]

    init(configDirectory: URL? = nil) {
        let directory = configDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        self.configDirectory = directory
        configFile = directory.appendingPathComponent("settings.json")
        loadState(port: 1897)
    }

    // MARK: - Public API

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

    // MARK: - Private

    private func proxyURL(port: Int) -> String {
        "http://127.0.0.1:\(port)"
    }

    private func loadState(port: Int) {
        let fm = FileManager.default
        configExists = fm.fileExists(atPath: configFile.path)

        guard configExists,
              let data = try? Data(contentsOf: configFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let env = json[envKey] as? [String: Any]
        else {
            currentURL = ""
            isActive = false
            return
        }

        currentURL = env[anthropicBaseURLKey] as? String ?? ""
        isActive = currentURL == proxyURL(port: port)
    }

    private func activateTakeover(port: Int) {
        lastError = nil

        let fm = FileManager.default
        if !fm.fileExists(atPath: configDirectory.path) {
            do {
                try fm.createDirectory(at: configDirectory, withIntermediateDirectories: true)
            } catch {
                setError("Failed to create ~/.claude directory: \(error.localizedDescription)")
                return
            }
        }

        var json: [String: Any] = [:]
        if fm.fileExists(atPath: configFile.path) {
            do {
                let data = try Data(contentsOf: configFile)
                guard let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    setError("Claude Code settings root must be a JSON object")
                    return
                }
                json = existing
            } catch {
                setError("Failed to read config: \(error.localizedDescription)")
                return
            }

            do {
                try backupConfigFile()
            } catch {
                setError("Failed to backup config: \(error.localizedDescription)")
                return
            }
        }

        var env = json[envKey] as? [String: Any] ?? [:]
        let url = proxyURL(port: port)
        env[anthropicBaseURLKey] = url
        json[envKey] = env

        // Remove the unsupported key written by older SmartLLM Router versions.
        if let legacyURL = json["url"] as? String,
           legacyURL.hasPrefix("http://127.0.0.1:") || legacyURL.hasPrefix("http://localhost:") {
            json.removeValue(forKey: "url")
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: json, options: jsonWritingOptions)
            try data.write(to: configFile, options: .atomic)
            configExists = true
            currentURL = url
            isActive = true
            Log.info("Claude Code config takeover activated: env.\(anthropicBaseURLKey) set to \(url)")
        } catch {
            setError("Failed to write config: \(error.localizedDescription)")
        }
    }

    private func deactivateTakeover(port: Int) {
        lastError = nil

        do {
            let currentData = try Data(contentsOf: configFile)
            guard var currentJSON = try JSONSerialization.jsonObject(with: currentData) as? [String: Any] else {
                setError("Claude Code settings root must be a JSON object")
                return
            }

            var previousURL: String?
            if let backupURL = findLatestBackup() {
                let backupData = try Data(contentsOf: backupURL)
                guard let backupJSON = try JSONSerialization.jsonObject(with: backupData) as? [String: Any] else {
                    setError("Backup file is not valid JSON")
                    return
                }
                previousURL = (backupJSON[envKey] as? [String: Any])?[anthropicBaseURLKey] as? String
            }

            var env = currentJSON[envKey] as? [String: Any] ?? [:]
            if let previousURL {
                env[anthropicBaseURLKey] = previousURL
            } else {
                env.removeValue(forKey: anthropicBaseURLKey)
            }
            if env.isEmpty {
                currentJSON.removeValue(forKey: envKey)
            } else {
                currentJSON[envKey] = env
            }

            let restoredData = try JSONSerialization.data(
                withJSONObject: currentJSON,
                options: jsonWritingOptions
            )
            try restoredData.write(to: configFile, options: .atomic)
            loadState(port: port)
            Log.info("Claude Code env.\(anthropicBaseURLKey) restored")
        } catch {
            setError("Failed to restore config: \(error.localizedDescription)")
        }
    }

    private func setError(_ message: String) {
        lastError = message
        Log.error(message)
    }

    /// Backup ~/.claude/settings.json with an incrementing suffix.
    private func backupConfigFile() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: configFile.path) else { return }

        var backupURL = configDirectory.appendingPathComponent("settings.json.bak")
        if fm.fileExists(atPath: backupURL.path) {
            var counter = 1
            repeat {
                backupURL = configDirectory.appendingPathComponent("settings.json.bak.\(counter)")
                counter += 1
            } while fm.fileExists(atPath: backupURL.path)
        }

        try fm.copyItem(at: configFile, to: backupURL)
        Log.info("Backed up Claude Code config to \(backupURL.lastPathComponent)")
    }

    private func findLatestBackup() -> URL? {
        let fm = FileManager.default
        var candidates: [(url: URL, number: Int)] = []

        let backupURL = configDirectory.appendingPathComponent("settings.json.bak")
        if fm.fileExists(atPath: backupURL.path) {
            candidates.append((backupURL, 0))
        }

        var counter = 1
        while counter < 100 {
            let numberedBackup = configDirectory.appendingPathComponent("settings.json.bak.\(counter)")
            if fm.fileExists(atPath: numberedBackup.path) {
                candidates.append((numberedBackup, counter))
            } else {
                break
            }
            counter += 1
        }

        return candidates.max(by: { $0.number < $1.number })?.url
    }
}
