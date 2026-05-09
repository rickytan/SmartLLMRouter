import Foundation
import SQLite3

// MARK: - Imported Channel

/// A channel discovered by the ConfigImporter
struct ImportedChannel: Identifiable {
    let id = UUID()
    var name: String
    var baseURL: String
    var apiKey: String
    var `protocol`: APIProtocol
    var source: String // e.g., "cc-load", "claude"
    var isSelected: Bool = false
}

// MARK: - Config Importer

/// Scans common LLM proxy config locations and extracts channel configurations.
/// Supports:
///   - CC Switch (LiteLLM): `~/.cc-load/data.db` (SQLite)
///   - Claude Desktop: `~/.claude/settings.json`
final class ConfigImporter {

    enum ImportError: Error, LocalizedError {
        case fileNotFound(String)
        case parseError(String)
        case sqliteError(String)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let path): "File not found: \(path)"
            case .parseError(let msg): "Parse error: \(msg)"
            case .sqliteError(let msg): "SQLite error: \(msg)"
            }
        }
    }

    /// Scan paths for CC Switch (LiteLLM) and Claude configs
    static var scanPaths: [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/.cc-load/data.db",
            "\(home)/.claude/settings.json",
        ]
    }

    // MARK: - Public API

    /// Scan all known config paths and return discovered channels
    static func scanAll() async -> [ImportedChannel] {
        var allChannels: [ImportedChannel] = []

        // Check each path
        for path in scanPaths {
            let discovered = await scan(path: path)
            allChannels.append(contentsOf: discovered)
        }

        return allChannels
    }

    /// Scan a specific path and return discovered channels
    static func scan(path: String) async -> [ImportedChannel] {
        if path.hasSuffix(".db") || path.hasSuffix(".sqlite") || path.hasSuffix(".sqlite3") {
            return scanSQLite(path: path)
        } else if path.hasSuffix(".json") {
            return scanJSON(path: path)
        }
        return []
    }

    /// Import channels into the ChannelStore
    @MainActor
    static func `import`(channels: [ImportedChannel]) throws -> Int {
        var importedCount = 0

        for imported in channels where imported.isSelected {
            // Check if channel with same baseURL already exists
            let existing = ChannelStore.shared.channels.first { channel in
                channel.baseURL == imported.baseURL
            }

            if existing != nil {
                Log.info("[ConfigImporter] Skipping duplicate channel: \(imported.name)")
                continue
            }

            let channel = Channel(
                name: imported.name,
                baseURL: imported.baseURL,
                protocol: imported.protocol
            )

            ChannelStore.shared.addChannel(channel)

            // Store API key in Keychain
            try KeychainManager.shared.setAPIKey(imported.apiKey, for: channel.id)

            importedCount += 1
            Log.info("[ConfigImporter] Imported channel: \(imported.name) from \(imported.source)")
        }

        return importedCount
    }

    // MARK: - SQLite Scanner (CC Switch / LiteLLM)

    /// Parse SQLite database using system libsqlite3
    private static func scanSQLite(path: String) -> [ImportedChannel] {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let db = db else {
            Log.error("[ConfigImporter] Failed to open SQLite database at \(path)")
            return []
        }
        defer { sqlite3_close(db) }

        var channels: [ImportedChannel] = []

        // 1. Discover tables
        var stmt: OpaquePointer?
        let tableSql = "SELECT name FROM sqlite_master WHERE type='table';"
        if sqlite3_prepare_v2(db, tableSql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let tableName = sqlite3_column_text(stmt, 0) {
                    let name = String(cString: tableName)
                    // Skip internal sqlite tables
                    if !name.hasPrefix("sqlite_") {
                        let discovered = inspectTable(db: db, tableName: name)
                        channels.append(contentsOf: discovered)
                    }
                }
            }
        }
        sqlite3_finalize(stmt)

        // Deduplicate by baseURL
        var seenURLs = Set<String>()
        return channels.filter {
            if seenURLs.contains($0.baseURL) { return false }
            seenURLs.insert($0.baseURL)
            return true
        }
    }

    /// Inspect a specific table to see if it contains channel configs
    private static func inspectTable(db: OpaquePointer, tableName: String) -> [ImportedChannel] {
        var columns: [String] = []
        var stmt: OpaquePointer?
        
        // Get column names via PRAGMA
        if sqlite3_prepare_v2(db, "PRAGMA table_info(\(tableName));", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let colName = sqlite3_column_text(stmt, 1) { // name is the 2nd column
                    columns.append(String(cString: colName).lowercased())
                }
            }
        }
        sqlite3_finalize(stmt)

        // Heuristic: Table must have a URL-like column to be relevant
        let urlCol = columns.first { $0.contains("url") || $0.contains("base") || $0.contains("endpoint") || $0.contains("host") }
        let keyCol = columns.first { $0.contains("key") || $0.contains("token") || $0.contains("secret") || $0.contains("password") }
        
        guard let urlCol = urlCol else { return [] }
        
        return extractFromTable(db: db, tableName: tableName, urlColumn: urlCol, keyColumn: keyCol)
    }

    /// Extract rows from a matching table
    private static func extractFromTable(db: OpaquePointer, tableName: String, urlColumn: String, keyColumn: String?) -> [ImportedChannel] {
        var channels: [ImportedChannel] = []
        var stmt: OpaquePointer?
        
        let query = "SELECT \"\(urlColumn)\", \(keyColumn != nil ? "\"\(keyColumn!)\"" : "NULL") FROM \"\(tableName)\";"
        
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let urlText = sqlite3_column_text(stmt, 0) {
                    let url = String(cString: urlText)
                    if isLLMURL(url) {
                        var apiKey = ""
                        // If we looked for a key column, read column 1. 
                        // If it was NULL in query, this will be null text (correct).
                        if keyColumn != nil, let keyText = sqlite3_column_text(stmt, 1) {
                            apiKey = String(cString: keyText)
                        }
                        
                        channels.append(ImportedChannel(
                            name: inferProviderName(from: url),
                            baseURL: url,
                            apiKey: apiKey,
                            protocol: inferProtocol(from: url),
                            source: "cc-switch (sqlite)"
                        ))
                    }
                }
            }
        }
        sqlite3_finalize(stmt)
        return channels
    }

    // MARK: - JSON Scanner (Claude Desktop)

    /// Parse Claude Desktop settings.json
    /// Format: { "env": { "ANTHROPIC_API_KEY": "sk-..." } } or similar
    private static func scanJSON(path: String) -> [ImportedChannel] {
        guard FileManager.default.fileExists(atPath: path) else {
            return []
        }

        do {
            let fileURL = URL(fileURLWithPath: path)
            let data = try Data(contentsOf: fileURL)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            return parseClaudeJSON(json: json)
        } catch {
            Log.error("[ConfigImporter] Failed to read JSON at \(path): \(error.localizedDescription)")
            return []
        }
    }

    /// Parse Claude Desktop settings JSON
    private static func parseClaudeJSON(json: [String: Any]?) -> [ImportedChannel] {
        guard let json else { return [] }

        var channels: [ImportedChannel] = []

        // Look for API keys in various locations
        // Claude settings typically have: env vars, or direct API key fields

        // Method 1: Check for direct API key
        if let apiKey = json["apiKey"] as? String, !apiKey.isEmpty {
            let channel = ImportedChannel(
                name: "Claude (Anthropic)",
                baseURL: "https://api.anthropic.com",
                apiKey: apiKey,
                protocol: .anthropic,
                source: "claude"
            )
            channels.append(channel)
        }

        // Method 2: Check env vars
        if let env = json["env"] as? [String: String] {
            // ANTHROPIC_API_KEY
            if let key = env["ANTHROPIC_API_KEY"], !key.isEmpty {
                let channel = ImportedChannel(
                    name: "Claude (Anthropic)",
                    baseURL: "https://api.anthropic.com",
                    apiKey: key,
                    protocol: .anthropic,
                    source: "claude"
                )
                if !channels.contains(where: { $0.apiKey == key }) {
                    channels.append(channel)
                }
            }

            // OPENAI_API_KEY
            if let key = env["OPENAI_API_KEY"], !key.isEmpty {
                let channel = ImportedChannel(
                    name: "OpenAI",
                    baseURL: "https://api.openai.com",
                    apiKey: key,
                    protocol: .openai,
                    source: "claude"
                )
                if !channels.contains(where: { $0.apiKey == key }) {
                    channels.append(channel)
                }
            }
        }

        // Method 3: Check for nested provider configs
        if let providers = json["providers"] as? [[String: Any]] {
            for provider in providers {
                if let name = provider["name"] as? String,
                   let apiKey = provider["apiKey"] as? String,
                   !apiKey.isEmpty {
                    let baseURL = provider["baseUrl"] as? String ?? "https://api.openai.com"
                    let proto = inferProtocol(from: baseURL)

                    let channel = ImportedChannel(
                        name: name,
                        baseURL: baseURL,
                        apiKey: apiKey,
                        protocol: proto,
                        source: "claude"
                    )
                    if !channels.contains(where: { $0.apiKey == apiKey && $0.baseURL == baseURL }) {
                        channels.append(channel)
                    }
                }
            }
        }

        // Method 4: Check for modelSettings with API keys
        if let modelSettings = json["modelSettings"] as? [String: Any] {
            if let apiKey = modelSettings["apiKey"] as? String, !apiKey.isEmpty {
                let channel = ImportedChannel(
                    name: "Claude (Anthropic)",
                    baseURL: "https://api.anthropic.com",
                    apiKey: apiKey,
                    protocol: .anthropic,
                    source: "claude"
                )
                if !channels.contains(where: { $0.apiKey == apiKey }) {
                    channels.append(channel)
                }
            }
        }

        return channels
    }

    // MARK: - Helpers

    /// Check if a URL looks like an LLM provider endpoint
    private static func isLLMURL(_ url: String) -> Bool {
        let llmPatterns = [
            "openai", "anthropic", "claude", "gemini", "google",
            "mistral", "groq", "deepseek", "together", "fireworks",
            "perplexity", "cohere", "anyscale", "replicate",
            "ollama", "localhost", "127.0.0.1",
            "api.", "v1/chat", "v1/messages", "v1/completions",
        ]
        let lower = url.lowercased()
        return llmPatterns.contains { lower.contains($0) }
    }

    /// Infer provider name from URL
    private static func inferProviderName(from url: String) -> String {
        let lower = url.lowercased()

        if lower.contains("anthropic") { return "Anthropic" }
        if lower.contains("openai") { return "OpenAI" }
        if lower.contains("gemini") || lower.contains("google") { return "Google" }
        if lower.contains("mistral") { return "Mistral" }
        if lower.contains("groq") { return "Groq" }
        if lower.contains("deepseek") { return "DeepSeek" }
        if lower.contains("together") { return "Together AI" }
        if lower.contains("fireworks") { return "Fireworks" }
        if lower.contains("perplexity") { return "Perplexity" }
        if lower.contains("cohere") { return "Cohere" }
        if lower.contains("ollama") { return "Ollama" }
        if lower.contains("localhost") || lower.contains("127.0.0.1") { return "Local Server" }

        // Try to extract domain
        if let urlObj = URL(string: url), let host = urlObj.host {
            let components = host.split(separator: ".")
            if components.count >= 2 {
                // Remove "api" prefix if present
                let mainName = components[components.count - 2]
                return String(mainName).capitalized
            }
        }

        return "Imported Provider"
    }

    /// Infer protocol from URL path
    private static func inferProtocol(from url: String) -> APIProtocol {
        let lower = url.lowercased()

        if lower.contains("anthropic") || lower.contains("claude") {
            return .anthropic
        }
        if lower.contains("/v1/messages") {
            return .anthropic
        }

        return .openai
    }
}
