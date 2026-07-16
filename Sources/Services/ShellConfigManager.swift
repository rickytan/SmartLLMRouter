import Foundation

/// Manages shell environment configuration for zsh/bash.
@MainActor
final class ShellConfigManager: ObservableObject {
    @Published private(set) var isConfigured: Bool = false
    @Published private(set) var configurationStatus: ConfigurationStatus = .notConfigured

    enum ConfigurationStatus: String {
        case notConfigured = "未配置"
        case configured = "已配置"
        case needsUpdate = "需要更新"
        case error = "配置错误"
    }

    private let envVarName = "SMARTLLM_ROUTER_PORT"
    private let openAIBaseURL = "OPENAI_BASE_URL"
    private let anthropicBaseURL = "ANTHROPIC_BASE_URL"
    private let blockStart = "# SmartLLM Router - Auto-generated"
    private let blockEnd = "# End SmartLLM Router"
    private let shellFile: URL

    init(shellFile: URL? = nil) {
        self.shellFile = shellFile
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zshenv")
        checkConfigurationStatus()
    }

    // MARK: - Public API

    /// Check if all shell variables required by SmartLLM Router are present.
    func checkConfigurationStatus(port: Int = 1897) {
        guard FileManager.default.fileExists(atPath: shellFile.path) else {
            configurationStatus = .notConfigured
            isConfigured = false
            return
        }

        do {
            let content = try String(contentsOf: shellFile, encoding: .utf8)
            if containsConfiguration(in: content, port: port) {
                isConfigured = true
                configurationStatus = .configured
            } else if containsRequiredVariables(in: content) {
                isConfigured = false
                configurationStatus = .needsUpdate
            } else {
                isConfigured = false
                configurationStatus = .notConfigured
            }
        } catch {
            configurationStatus = .error
            isConfigured = false
            Log.error("Failed to read shell config: \(error.localizedDescription)")
        }
    }

    /// Add or update the managed shell environment block.
    func configure(port: Int = 1897) async -> Result<String, Error> {
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: shellFile.path) {
            do {
                try "".write(to: shellFile, atomically: true, encoding: .utf8)
                Log.info("Created shell config file: \(shellFile.path)")
            } catch {
                Log.error("Failed to create config file: \(error.localizedDescription)")
                return .failure(error)
            }
        }

        let currentContent: String
        do {
            currentContent = try String(contentsOf: shellFile, encoding: .utf8)
        } catch {
            Log.error("Failed to read shell config: \(error.localizedDescription)")
            return .failure(error)
        }

        let configBlock = generateConfigBlock(port: port)
        if containsConfiguration(in: currentContent, port: port) {
            isConfigured = true
            configurationStatus = .configured
            return .success("环境变量已经配置，无需重复更新")
        }

        let cleanedContent = removeOldConfig(from: currentContent)
            .trimmingCharacters(in: .newlines)
        let newContent = cleanedContent.isEmpty
            ? "\(configBlock)\n"
            : "\(cleanedContent)\n\n\(configBlock)\n"

        do {
            try newContent.write(to: shellFile, atomically: true, encoding: .utf8)
            isConfigured = true
            configurationStatus = .configured
            Log.info("Shell environment configured with port \(port)")
            return .success("环境变量已写入 \(shellFile.path)")
        } catch {
            Log.error("Failed to write config: \(error.localizedDescription)")
            return .failure(error)
        }
    }

    /// Remove SmartLLM Router configuration from the shell file.
    func removeConfiguration() -> Result<String, Error> {
        guard let currentContent = try? String(contentsOf: shellFile, encoding: .utf8) else {
            return .failure(NSError(domain: "ShellConfig", code: 2, userInfo: nil))
        }

        let cleanedContent = removeOldConfig(from: currentContent)

        do {
            try cleanedContent.write(to: shellFile, atomically: true, encoding: .utf8)
            isConfigured = false
            configurationStatus = .notConfigured
            return .success("环境变量已移除")
        } catch {
            return .failure(error)
        }
    }

    /// Get the export commands for the current port.
    func getExportCommands(port: Int = 1897) -> String {
        generateConfigBlock(port: port)
    }

    // MARK: - Private

    private func generateConfigBlock(port: Int) -> String {
        """
        \(blockStart)
        # Set proxy URLs for LLM API clients
        export \(openAIBaseURL)=http://localhost:\(port)/v1
        export \(anthropicBaseURL)=http://localhost:\(port)
        export \(envVarName)=\(port)
        \(blockEnd)
        """
    }

    private func containsRequiredVariables(in content: String) -> Bool {
        content.contains(openAIBaseURL)
            && content.contains(anthropicBaseURL)
            && content.contains(envVarName)
    }

    private func containsConfiguration(in content: String, port: Int) -> Bool {
        let lines = Set(content.components(separatedBy: .newlines).map {
            $0.trimmingCharacters(in: .whitespaces)
        })
        return lines.contains("export \(openAIBaseURL)=http://localhost:\(port)/v1")
            && lines.contains("export \(anthropicBaseURL)=http://localhost:\(port)")
            && lines.contains("export \(envVarName)=\(port)")
    }

    private func removeOldConfig(from content: String) -> String {
        let lines = content.components(separatedBy: "\n")
        var inConfigBlock = false
        var cleanedLines: [String] = []

        for line in lines {
            if line.contains(blockStart) {
                inConfigBlock = true
                continue
            }

            if inConfigBlock {
                if line.contains(blockEnd) {
                    inConfigBlock = false
                } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    // Legacy generated blocks did not include an explicit end marker.
                    inConfigBlock = false
                }
                continue
            }

            cleanedLines.append(line)
        }

        return cleanedLines.joined(separator: "\n")
    }
}
