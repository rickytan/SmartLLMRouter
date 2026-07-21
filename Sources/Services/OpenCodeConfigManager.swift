import Foundation

/// Manages OpenCode configuration (~/.config/opencode/opencode.json).
@MainActor
final class OpenCodeConfigManager: ObservableObject {
    @Published private(set) var isActive: Bool = false
    @Published private(set) var currentURL: String = ""
    @Published private(set) var configExists: Bool = false
    @Published private(set) var lastError: String?

    private let configDirectory: URL
    private let configFile: URL
    private let providerID = "smartllmrouter"
    private let providerKey = "provider"
    private let enabledProvidersKey = "enabled_providers"
    private let disabledProvidersKey = "disabled_providers"
    private let jsonWritingOptions: JSONSerialization.WritingOptions = [
        .prettyPrinted,
        .sortedKeys,
        .withoutEscapingSlashes
    ]

    init(configDirectory: URL? = nil) {
        let directory = configDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/opencode", isDirectory: true)
        self.configDirectory = directory
        self.configFile = directory.appendingPathComponent("opencode.json")
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
              let json = try? readConfig(),
              let provider = providerConfig(in: json),
              let options = provider["options"] as? [String: Any],
              let baseURL = options["baseURL"] as? String
        else {
            currentURL = ""
            isActive = false
            return
        }

        currentURL = baseURL
        isActive = baseURL == proxyURL(port: port)
    }

    private func activateTakeover(port: Int) {
        lastError = nil

        let fm = FileManager.default
        do {
            if !fm.fileExists(atPath: configDirectory.path) {
                try fm.createDirectory(at: configDirectory, withIntermediateDirectories: true)
            }

            var json = try fm.fileExists(atPath: configFile.path) ? readConfig() : [:]
            if fm.fileExists(atPath: configFile.path) {
                try backupConfigFile()
            }

            var providers = json[providerKey] as? [String: Any] ?? [:]
            providers[providerID] = smartLLMRouterProvider(port: port)
            json[providerKey] = providers

            if var enabledProviders = json[enabledProvidersKey] as? [String], !enabledProviders.contains(providerID) {
                enabledProviders.append(providerID)
                json[enabledProvidersKey] = enabledProviders
            }
            if var disabledProviders = json[disabledProvidersKey] as? [String] {
                disabledProviders.removeAll { $0 == providerID }
                json[disabledProvidersKey] = disabledProviders
            }

            try writeConfig(json)
            configExists = true
            currentURL = proxyURL(port: port)
            isActive = true
            Log.info("OpenCode config takeover activated: provider.\(providerID).options.baseURL set")
        } catch {
            setError("Failed to update OpenCode config: \(error.localizedDescription)")
        }
    }

    private func deactivateTakeover(port: Int) {
        lastError = nil

        do {
            var json = try readConfig()
            let backupJSON = try findLatestBackup().map { try readConfig(from: $0) }
            let previousProvider = backupJSON.flatMap { providerConfig(in: $0) }

            var providers = json[providerKey] as? [String: Any] ?? [:]
            if let previousProvider {
                providers[providerID] = previousProvider
            } else {
                providers.removeValue(forKey: providerID)
            }

            if providers.isEmpty {
                json.removeValue(forKey: providerKey)
            } else {
                json[providerKey] = providers
            }

            if let previousEnabledProviders = backupJSON?[enabledProvidersKey] as? [String] {
                json[enabledProvidersKey] = previousEnabledProviders
            } else if var enabledProviders = json[enabledProvidersKey] as? [String] {
                enabledProviders.removeAll { $0 == providerID }
                if enabledProviders.isEmpty {
                    json.removeValue(forKey: enabledProvidersKey)
                } else {
                    json[enabledProvidersKey] = enabledProviders
                }
            }

            if let previousDisabledProviders = backupJSON?[disabledProvidersKey] as? [String] {
                json[disabledProvidersKey] = previousDisabledProviders
            }

            try writeConfig(json)
            loadState(port: port)
            Log.info("OpenCode provider.\(providerID) restored")
        } catch {
            setError("Failed to restore OpenCode config: \(error.localizedDescription)")
        }
    }

    private func smartLLMRouterProvider(port: Int) -> [String: Any] {
        [
            "name": "SmartLLM Router",
            "npm": "@ai-sdk/openai-compatible",
            "options": [
                "baseURL": proxyURL(port: port),
                "apiKey": "smartllmrouter"
            ]
        ]
    }

    private func providerConfig(in json: [String: Any]) -> [String: Any]? {
        (json[providerKey] as? [String: Any])?[providerID] as? [String: Any]
    }

    private func readConfig() throws -> [String: Any] {
        try readConfig(from: configFile)
    }

    private func readConfig(from url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConfigError.invalidRoot
        }
        return json
    }

    private func writeConfig(_ json: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: json, options: jsonWritingOptions)
        try data.write(to: configFile, options: .atomic)
    }

    private func backupConfigFile() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: configFile.path) else { return }

        var backupURL = configDirectory.appendingPathComponent("opencode.json.bak")
        if fm.fileExists(atPath: backupURL.path) {
            var counter = 1
            repeat {
                backupURL = configDirectory.appendingPathComponent("opencode.json.bak.\(counter)")
                counter += 1
            } while fm.fileExists(atPath: backupURL.path)
        }

        try fm.copyItem(at: configFile, to: backupURL)
        Log.info("Backed up OpenCode config to \(backupURL.lastPathComponent)")
    }

    private func findLatestBackup() -> URL? {
        let fm = FileManager.default
        var candidates: [(url: URL, number: Int)] = []

        let backupURL = configDirectory.appendingPathComponent("opencode.json.bak")
        if fm.fileExists(atPath: backupURL.path) {
            candidates.append((backupURL, 0))
        }

        var counter = 1
        while counter < 100 {
            let numberedBackup = configDirectory.appendingPathComponent("opencode.json.bak.\(counter)")
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

    private enum ConfigError: LocalizedError {
        case invalidRoot

        var errorDescription: String? {
            "OpenCode config root must be a JSON object"
        }
    }
}
