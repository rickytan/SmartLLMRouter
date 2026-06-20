import Foundation

/// Manages shell environment configuration for zsh/bash
@MainActor
final class ShellConfigManager: ObservableObject {
    static let shared = ShellConfigManager()
    
    @Published private(set) var isConfigured: Bool = false
    @Published private(set) var configurationStatus: ConfigurationStatus = .notConfigured
    
    enum ConfigurationStatus: String {
        case notConfigured = "未配置"
        case configured = "已配置"
        case needsUpdate = "需要更新"
        case error = "配置错误"
    }
    
    private let envVarName = "SMARTLLM_ROUTER_PORT"
    private let openaiBaseURL = "OPENAI_BASE_URL"
    private let anthropicBaseURL = "ANTHROPIC_BASE_URL"
    
    init() {
        checkConfigurationStatus()
    }
    
    // MARK: - Public API
    
    /// Check if shell environment is already configured
    func checkConfigurationStatus() {
        let shellFile = getShellConfigFile()
        guard let filePath = shellFile?.path else {
            configurationStatus = .error
            isConfigured = false
            return
        }
        
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: filePath) else {
            configurationStatus = .notConfigured
            isConfigured = false
            return
        }
        
        do {
            let content = try String(contentsOfFile: filePath, encoding: .utf8)
            if content.contains(envVarName) && content.contains(openaiBaseURL) {
                isConfigured = true
                configurationStatus = .configured
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
    
    /// Configure shell environment by adding exports to .zshrc
    func configure(port: Int = 1897) async -> Result<String, Error> {
        let shellFile = getShellConfigFile()
        guard let filePath = shellFile?.path else {
            let error = NSError(
                domain: "ShellConfig",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "未找到 shell 配置文件"]
            )
            return .failure(error)
        }
        
        let fileManager = FileManager.default
        
        // Create file if it doesn't exist
        if !fileManager.fileExists(atPath: filePath) {
            do {
                try "".write(toFile: filePath, atomically: true, encoding: .utf8)
                Log.info("Created shell config file: \(filePath)")
            } catch {
                Log.error("Failed to create config file: \(error.localizedDescription)")
                return .failure(error)
            }
        }
        
        // Read current content
        guard let currentContent = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            let error = NSError(
                domain: "ShellConfig",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "无法读取配置文件"]
            )
            return .failure(error)
        }
        
        // Check if already configured
        if currentContent.contains("# SmartLLM Router") {
            // Remove old configuration first
            let cleanedContent = removeOldConfig(from: currentContent)
            do {
                try cleanedContent.write(toFile: filePath, atomically: true, encoding: .utf8)
            } catch {
                return .failure(error)
            }
        }
        
        // Add new configuration
        let configBlock = generateConfigBlock(port: port)
        let newContent = currentContent + "\n" + configBlock
        
        do {
            try newContent.write(toFile: filePath, atomically: true, encoding: .utf8)
            isConfigured = true
            configurationStatus = .configured
            
            Log.info("Shell environment configured with port \(port)")
            return .success("✅ 环境变量已写入 \(filePath)")
        } catch {
            Log.error("Failed to write config: \(error.localizedDescription)")
            return .failure(error)
        }
    }
    
    /// Remove SmartLLM Router configuration from shell file
    func removeConfiguration() -> Result<String, Error> {
        let shellFile = getShellConfigFile()
        guard let filePath = shellFile?.path else {
            return .failure(NSError(domain: "ShellConfig", code: 1, userInfo: nil))
        }
        
        guard let currentContent = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return .failure(NSError(domain: "ShellConfig", code: 2, userInfo: nil))
        }
        
        let cleanedContent = removeOldConfig(from: currentContent)
        
        do {
            try cleanedContent.write(toFile: filePath, atomically: true, encoding: .utf8)
            isConfigured = false
            configurationStatus = .notConfigured
            return .success("✅ 环境变量已移除")
        } catch {
            return .failure(error)
        }
    }
    
    /// Get the export commands for current port
    func getExportCommands(port: Int = 1897) -> String {
        generateConfigBlock(port: port)
    }
    
    // MARK: - Private
    
    private func getShellConfigFile() -> URL? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        // Use .zshenv because it is sourced for ALL shell invocations (interactive, non-interactive, scripts, IDEs)
        // .zshrc is only for interactive shells and often misses tools like Claude Code, CI scripts, etc.
        return homeDir.appendingPathComponent(".zshenv")
    }
    
    private func generateConfigBlock(port: Int) -> String {
        """
        
        # SmartLLM Router - Auto-generated
        # Set proxy URLs for LLM API clients
        export \(openaiBaseURL)=http://localhost:\(port)/v1
        export \(anthropicBaseURL)=http://localhost:\(port)/v1
        export \(envVarName)=\(port)
        
        """
    }
    
    private func removeOldConfig(from content: String) -> String {
        var lines = content.components(separatedBy: "\n")
        var inConfigBlock = false
        var cleanedLines: [String] = []
        
        for line in lines {
            if line.contains("# SmartLLM Router - Auto-generated") {
                inConfigBlock = true
                continue
            }
            
            if inConfigBlock {
                if line.trimmingCharacters(in: .whitespaces).isEmpty || 
                   line.contains("# End SmartLLM Router") {
                    inConfigBlock = false
                    continue
                }
                // Skip lines in the config block
                continue
            }
            
            cleanedLines.append(line)
        }
        
        return cleanedLines.joined(separator: "\n")
    }
}
