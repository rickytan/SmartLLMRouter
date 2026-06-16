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
    var source: String // e.g., "cc-switch", "claude"
    var isSelected: Bool = false
}

// MARK: - Config Importer

/// Scans common LLM proxy config locations and extracts channel configurations.
/// Supports:
///   - CC Switch: `~/.cc-switch/cc-switch.db` (SQLite)
///   - CC Switch Legacy: `~/.cc-switch/config.json`
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

    /// Scan paths for CC Switch and Claude configs
    static var scanPaths: [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/.cc-switch/cc-switch.db", // CC Switch (SQLite)
            "\(home)/.cc-switch/config.json",  // CC Switch (Legacy JSON)
            "\(home)/.claude/settings.json",   // Claude Desktop
        ]
    }

    // MARK: - Public API

    /// Scan all known config paths and return discovered channels
    static func scanAll() async -> [ImportedChannel] {
        var allChannels: [ImportedChannel] = []

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
        let channelServices = ChannelServices.shared
        var importedCount = 0

        for imported in channels where imported.isSelected {
            let existing = channelServices.channels.first { channel in
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

            channelServices.addChannel(channel)

            if !imported.apiKey.isEmpty {
                try channelServices.setAPIKey(imported.apiKey, for: channel.id)
            }

            importedCount += 1
            Log.info("[ConfigImporter] Imported channel: \(imported.name) from \(imported.source)")
        }

        return importedCount
    }

    // MARK: - SQLite Scanner (CC Switch)

    /// Parse SQLite database using system libsqlite3
    private static func scanSQLite(path: String) -> [ImportedChannel] {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let db = db else {
            Log.error("[ConfigImporter] Failed to open SQLite database at \(path)")
            return []
        }
        defer { sqlite3_close(db) }

        // 1. Check if this is a cc-switch database
        var stmt: OpaquePointer?
        let checkTableSql = "SELECT name FROM sqlite_master WHERE type='table' AND name='providers';"
        var isCCSwitch = false
        if sqlite3_prepare_v2(db, checkTableSql, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                isCCSwitch = true
            }
        }
        sqlite3_finalize(stmt)

        if isCCSwitch {
            return extractCCSwitchChannels(db: db)
        } else {
            return extractGenericChannels(db: db)
        }
    }

    /// Extract channels specifically from CC Switch schema
    private static func extractCCSwitchChannels(db: OpaquePointer) -> [ImportedChannel] {
        var channels: [ImportedChannel] = []
        var stmt: OpaquePointer?
        
        // Query providers and their most recently added endpoint
        let sql = """
        SELECT p.id, p.name, p.app_type, p.settings_config, 
               (SELECT e.url FROM provider_endpoints e 
                WHERE e.provider_id = p.id AND e.app_type = p.app_type 
                ORDER BY e.added_at DESC LIMIT 1) as last_endpoint
        FROM providers p
        """
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let namePtr = sqlite3_column_text(stmt, 1),
                      let appTypePtr = sqlite3_column_text(stmt, 2),
                      let settingsPtr = sqlite3_column_text(stmt, 3) else {
                    continue
                }
                
                let providerName = String(cString: namePtr)
                let appType = String(cString: appTypePtr).lowercased()
                let settingsJsonStr = String(cString: settingsPtr)
                
                var endpointUrl: String? = nil
                if let urlPtr = sqlite3_column_text(stmt, 4) {
                    endpointUrl = String(cString: urlPtr)
                }
                
                if let data = settingsJsonStr.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    
                    let apiKey = extractAPIKey(from: json)
                    var baseUrl = extractBaseURL(from: json)
                    
                    if baseUrl.isEmpty {
                        baseUrl = endpointUrl ?? defaultBaseURL(for: appType)
                    }
                    
                    guard !baseUrl.isEmpty else { continue }
                    
                    let proto = inferProtocol(from: appType, url: baseUrl)
                    channels.append(ImportedChannel(
                        name: providerName,
                        baseURL: baseUrl,
                        apiKey: apiKey,
                        protocol: proto,
                        source: "cc-switch (\(appType))"
                    ))
                }
            }
        }
        sqlite3_finalize(stmt)
        return channels
    }

    /// Extract API Key from CC Switch settings_config JSON
    /// Priority: apiKey -> api_key -> env.ANTHROPIC_AUTH_TOKEN -> env.ANTHROPIC_API_KEY -> env.OPENAI_API_KEY
    private static func extractAPIKey(from json: [String: Any]) -> String {
        if let key = json["apiKey"] as? String, !key.isEmpty { return key }
        if let key = json["api_key"] as? String, !key.isEmpty { return key }

        if let env = json["env"] as? [String: String] {
            if let key = env["ANTHROPIC_AUTH_TOKEN"], !key.isEmpty { return key }
            if let key = env["ANTHROPIC_API_KEY"], !key.isEmpty { return key }
            if let key = env["OPENAI_API_KEY"], !key.isEmpty { return key }
            if let key = env["GOOGLE_API_KEY"], !key.isEmpty { return key }
        }
        return ""
    }

    /// Extract Base URL from CC Switch settings_config JSON
    /// Priority: base_url -> baseURL -> apiEndpoint -> env.ANTHROPIC_BASE_URL
    private static func extractBaseURL(from json: [String: Any]) -> String {
        if let url = json["base_url"] as? String, !url.isEmpty { return url }
        if let url = json["baseURL"] as? String, !url.isEmpty { return url }
        if let url = json["apiEndpoint"] as? String, !url.isEmpty { return url }
        
        if let env = json["env"] as? [String: String] {
            if let url = env["ANTHROPIC_BASE_URL"], !url.isEmpty { return url }
            if let url = env["OPENAI_BASE_URL"], !url.isEmpty { return url }
            if let url = env["GOOGLE_GEMINI_BASE_URL"], !url.isEmpty { return url }
        }
        return ""
    }

    private static func defaultBaseURL(for appType: String) -> String {
        switch appType {
        case "claude": return "https://api.anthropic.com"
        case "codex", "openai": return "https://api.openai.com"
        case "gemini", "google": return "https://generativelanguage.googleapis.com"
        default: return "https://api.openai.com"
        }
    }

    /// Generic heuristic extractor for unknown SQLite databases
    private static func extractGenericChannels(db: OpaquePointer) -> [ImportedChannel] {
        var channels: [ImportedChannel] = []
        var stmt: OpaquePointer?
        
        let tableSql = "SELECT name FROM sqlite_master WHERE type='table';"
        if sqlite3_prepare_v2(db, tableSql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let tableName = sqlite3_column_text(stmt, 0) {
                    let name = String(cString: tableName)
                    if !name.hasPrefix("sqlite_") {
                        let discovered = inspectTable(db: db, tableName: name)
                        channels.append(contentsOf: discovered)
                    }
                }
            }
        }
        sqlite3_finalize(stmt)
        
        // Deduplicate
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
        
        if sqlite3_prepare_v2(db, "PRAGMA table_info(\(tableName));", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let colName = sqlite3_column_text(stmt, 1) {
                    columns.append(String(cString: colName).lowercased())
                }
            }
        }
        sqlite3_finalize(stmt)

        let urlCol = columns.first { $0.contains("url") || $0.contains("base") || $0.contains("endpoint") }
        let keyCol = columns.first { $0.contains("key") || $0.contains("token") || $0.contains("secret") }
        
        guard let urlCol = urlCol else { return [] }
        
        return extractFromTable(db: db, tableName: tableName, urlColumn: urlCol, keyColumn: keyCol)
    }

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
                        if keyColumn != nil, let keyText = sqlite3_column_text(stmt, 1) {
                            apiKey = String(cString: keyText)
                        }
                        
                        channels.append(ImportedChannel(
                            name: inferProviderName(from: url),
                            baseURL: url,
                            apiKey: apiKey,
                            protocol: inferProtocol(from: "", url: url),
                            source: "sqlite (generic)"
                        ))
                    }
                }
            }
        }
        sqlite3_finalize(stmt)
        return channels
    }

    // MARK: - JSON Scanner

    private static func scanJSON(path: String) -> [ImportedChannel] {
        guard FileManager.default.fileExists(atPath: path) else {
            return []
        }

        do {
            let fileURL = URL(fileURLWithPath: path)
            let data = try Data(contentsOf: fileURL)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            if path.contains(".cc-switch") {
                return parseCCSwitchJSON(json: json)
            } else {
                return parseClaudeJSON(json: json)
            }
        } catch {
            Log.error("[ConfigImporter] Failed to read JSON at \(path): \(error.localizedDescription)")
            return []
        }
    }

    /// Parse CC Switch legacy JSON config
    private static func parseCCSwitchJSON(json: [String: Any]?) -> [ImportedChannel] {
        guard let json else { return [] }
        var channels: [ImportedChannel] = []
        
        if let apps = json["apps"] as? [String: Any] {
            for (appType, appDataObj) in apps {
                guard let appData = appDataObj as? [String: Any] else { continue }
                if let providers = appData["providers"] as? [String: Any] {
                    for (_, providerData) in providers {
                        if let p = providerData as? [String: Any],
                           let name = p["name"] as? String {
                            let apiKey = extractAPIKey(from: p)
                            var baseUrl = extractBaseURL(from: p)
                            if baseUrl.isEmpty {
                                baseUrl = defaultBaseURL(for: appType)
                            }
                            
                            channels.append(ImportedChannel(
                                name: name,
                                baseURL: baseUrl,
                                apiKey: apiKey,
                                protocol: inferProtocol(from: appType, url: baseUrl),
                                source: "cc-switch-legacy (\(appType))"
                            ))
                        }
                    }
                }
            }
        }
        return channels
    }

    /// Parse Claude Desktop settings JSON
    private static func parseClaudeJSON(json: [String: Any]?) -> [ImportedChannel] {
        guard let json else { return [] }
        var channels: [ImportedChannel] = []

        if let apiKey = json["apiKey"] as? String, !apiKey.isEmpty {
            channels.append(ImportedChannel(
                name: "Claude (Anthropic)",
                baseURL: "https://api.anthropic.com",
                apiKey: apiKey,
                protocol: .anthropic,
                source: "claude"
            ))
        }

        if let env = json["env"] as? [String: String] {
            // Claude Code uses ANTHROPIC_AUTH_TOKEN, old Claude Desktop uses ANTHROPIC_API_KEY
            let anthropicKey = env["ANTHROPIC_AUTH_TOKEN"] ?? env["ANTHROPIC_API_KEY"]
            if let key = anthropicKey, !key.isEmpty {
                channels.append(ImportedChannel(
                    name: "Claude (Anthropic)",
                    baseURL: env["ANTHROPIC_BASE_URL"] ?? "https://api.anthropic.com",
                    apiKey: key,
                    protocol: .anthropic,
                    source: "claude"
                ))
            }
            if let key = env["OPENAI_API_KEY"], !key.isEmpty {
                channels.append(ImportedChannel(
                    name: "OpenAI",
                    baseURL: env["OPENAI_BASE_URL"] ?? "https://api.openai.com",
                    apiKey: key,
                    protocol: .openai,
                    source: "claude"
                ))
            }
        }

        if let providers = json["providers"] as? [[String: Any]] {
            for provider in providers {
                if let name = provider["name"] as? String,
                   let apiKey = provider["apiKey"] as? String,
                   !apiKey.isEmpty {
                    let baseURL = provider["baseUrl"] as? String ?? "https://api.openai.com"
                    channels.append(ImportedChannel(
                        name: name,
                        baseURL: baseURL,
                        apiKey: apiKey,
                        protocol: inferProtocol(from: "", url: baseURL),
                        source: "claude"
                    ))
                }
            }
        }
        return channels
    }

    // MARK: - Helpers

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

        if let urlObj = URL(string: url), let host = urlObj.host {
            let components = host.split(separator: ".")
            if components.count >= 2 {
                return String(components[components.count - 2]).capitalized
            }
        }
        return "Imported Provider"
    }

    private static func inferProtocol(from appType: String, url: String) -> APIProtocol {
        if appType.lowercased() == "claude" || appType.lowercased() == "anthropic" {
            return .anthropic
        }
        let lowerUrl = url.lowercased()
        if lowerUrl.contains("anthropic") || lowerUrl.contains("/v1/messages") {
            return .anthropic
        }
        return .openai
    }

    /// Backward-compatible overload for URL-only inference
    private static func inferProtocol(from url: String) -> APIProtocol {
        inferProtocol(from: "", url: url)
    }
}
