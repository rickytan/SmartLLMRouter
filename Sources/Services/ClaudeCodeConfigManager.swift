import Foundation

/// Manages Claude Code configuration (~/.claude/settings.json)
/// Allows one-click takeover to route Claude Code through the SmartLLM Router proxy.
@MainActor
final class ClaudeCodeConfigManager: ObservableObject {
    static let shared = ClaudeCodeConfigManager()

    @Published private(set) var isActive: Bool = false
    @Published private(set) var currentURL: String = ""
    @Published private(set) var configExists: Bool = false
    @Published private(set) var lastError: String?

    private let proxyURL = "http://127.0.0.1:1897"
    private let urlKey = "url"

    private var configDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    }

    private var configFile: URL {
        configDirectory.appendingPathComponent("settings.json")
    }

    private init() {
        loadState()
    }

    // MARK: - Public API

    /// Refresh the current state from disk
    func refresh() {
        loadState()
    }

    /// Toggle the takeover on or off
    func toggleTakeover(enable: Bool) {
        if enable {
            activateTakeover()
        } else {
            deactivateTakeover()
        }
    }

    // MARK: - Private

    private func loadState() {
        let fm = FileManager.default
        configExists = fm.fileExists(atPath: configFile.path)

        guard configExists,
              let data = try? Data(contentsOf: configFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            currentURL = ""
            isActive = false
            return
        }

        if let url = json[urlKey] as? String {
            currentURL = url
            isActive = (url == proxyURL)
        } else {
            currentURL = ""
            isActive = false
        }
    }

    private func activateTakeover() {
        lastError = nil

        // Ensure directory exists
        let fm = FileManager.default
        if !fm.fileExists(atPath: configDirectory.path) {
            do {
                try fm.createDirectory(at: configDirectory, withIntermediateDirectories: true)
            } catch {
                lastError = "Failed to create ~/.claude directory: \(error.localizedDescription)"
                Log.error(lastError!)
                return
            }
        }

        // Read existing config or start fresh
        var json: [String: Any] = [:]
        if fm.fileExists(atPath: configFile.path) {
            // Backup first
            backupConfigFile()

            if let data = try? Data(contentsOf: configFile),
               let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                json = existing
            }
        }

        // Set the url
        json[urlKey] = proxyURL

        // Write back
        do {
            let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: configFile, options: .atomic)
            isActive = true
            currentURL = proxyURL
            configExists = true
            Log.info("Claude Code config takeover activated: url set to \(proxyURL)")
        } catch {
            lastError = "Failed to write config: \(error.localizedDescription)"
            Log.error(lastError!)
        }
    }

    private func deactivateTakeover() {
        lastError = nil

        // Find the latest backup
        guard let backupURL = findLatestBackup() else {
            lastError = "No backup found to restore from"
            Log.warn(lastError!)
            return
        }

        do {
            let backupData = try Data(contentsOf: backupURL)
            // Validate it's valid JSON
            guard let _ = try? JSONSerialization.jsonObject(with: backupData) else {
                lastError = "Backup file is not valid JSON"
                Log.error(lastError!)
                return
            }
            try backupData.write(to: configFile, options: .atomic)
            isActive = false
            loadState()
            Log.info("Claude Code config restored from backup: \(backupURL.lastPathComponent)")
        } catch {
            lastError = "Failed to restore backup: \(error.localizedDescription)"
            Log.error(lastError!)
        }
    }

    /// Backup ~/.claude/settings.json with incrementing suffix
    private func backupConfigFile() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: configFile.path) else { return }

        // Find the next available backup name
        var backupURL = configDirectory.appendingPathComponent("settings.json.bak")
        if fm.fileExists(atPath: backupURL.path) {
            var counter = 1
            repeat {
                backupURL = configDirectory.appendingPathComponent("settings.json.bak.\(counter)")
                counter += 1
            } while fm.fileExists(atPath: backupURL.path)
        }

        do {
            try fm.copyItem(at: configFile, to: backupURL)
            Log.info("Backed up Claude Code config to \(backupURL.lastPathComponent)")
        } catch {
            Log.error("Failed to backup config: \(error.localizedDescription)")
        }
    }

    /// Find the most recent backup file (settings.json.bak or highest .bak.N)
    private func findLatestBackup() -> URL? {
        let fm = FileManager.default
        let dir = configDirectory

        // Check for .bak files
        var candidates: [(url: URL, number: Int)] = []

        let bakURL = dir.appendingPathComponent("settings.json.bak")
        if fm.fileExists(atPath: bakURL.path) {
            candidates.append((bakURL, 0))
        }

        // Check .bak.1, .bak.2, etc.
        var counter = 1
        while counter < 100 { // Safety limit
            let numberedBak = dir.appendingPathComponent("settings.json.bak.\(counter)")
            if fm.fileExists(atPath: numberedBak.path) {
                candidates.append((numberedBak, counter))
            } else {
                break // No more sequential backups
            }
            counter += 1
        }

        // Return the one with highest number (most recent)
        return candidates.max(by: { $0.number < $1.number })?.url
    }
}
