import Foundation
import AppKit
import CryptoKit
import CommonCrypto

/// Service for exporting and importing channel configurations
@MainActor
final class ChannelExportService {
    static let shared = ChannelExportService(channelServices: .shared)
    private let channelServices: ChannelServices

    init(channelServices: ChannelServices) {
        self.channelServices = channelServices
    }

    // MARK: - Import Result

    /// Outcome of an import attempt. Surfaces the silent failures that
    /// the previous `Int` return value dropped on the floor — duplicate
    /// base URLs, keychain write errors, decryption errors. The UI uses
    /// this to show a complete success/failure report so the user knows
    /// whether everything actually made it in.
    struct ImportResult {
        struct Issue: Equatable {
            let channelName: String
            let reason: String
        }
        let total: Int
        let imported: Int
        let skipped: [Issue]
        let failed: [Issue]

        var hasIssues: Bool { !skipped.isEmpty || !failed.isEmpty }
    }

    // MARK: - Export Format

    struct ExportFile: Codable {
        let format: String
        let version: Int
        let exportedAt: Date
        let appVersion: String
        let channels: [ExportedChannel]
        let encrypted: Bool
        let encryptionSalt: String?  // Base64-encoded salt for key derivation
        let encryptionNonce: String? // Base64-encoded nonce for AES-GCM
    }

    struct ExportedChannel: Codable {
        let name: String
        let baseURL: String
        let protocolType: String
        let priority: Int
        let models: [ExportedModel]
        let apiKey: String // Plain text or encrypted (base64)

        enum CodingKeys: String, CodingKey {
            case name, baseURL, `protocol`, priority, models, apiKey
        }

        init(name: String, baseURL: String, protocolType: String, priority: Int, models: [ExportedModel], apiKey: String) {
            self.name = name
            self.baseURL = baseURL
            self.protocolType = protocolType
            self.priority = priority
            self.models = models
            self.apiKey = apiKey
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            baseURL = try container.decode(String.self, forKey: .baseURL)
            protocolType = try container.decode(String.self, forKey: .`protocol`)
            priority = try container.decode(Int.self, forKey: .priority)
            models = try container.decode([ExportedModel].self, forKey: .models)
            apiKey = try container.decode(String.self, forKey: .apiKey)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(baseURL, forKey: .baseURL)
            try container.encode(protocolType, forKey: .`protocol`)
            try container.encode(priority, forKey: .priority)
            try container.encode(models, forKey: .models)
            try container.encode(apiKey, forKey: .apiKey)
        }
    }

    struct ExportedModel: Codable {
        let identifier: String
        let displayName: String
        let contextLength: Int?
        let inputPricePer1M: Double?
        let outputPricePer1M: Double?
        let isEnabled: Bool
        let inputTypes: [String]

        enum CodingKeys: String, CodingKey {
            case identifier, displayName, contextLength
            case inputPricePer1M, outputPricePer1M, isEnabled
            case inputTypes, supportsVision
        }

        init(identifier: String, displayName: String, contextLength: Int? = nil,
             inputPricePer1M: Double? = nil, outputPricePer1M: Double? = nil,
             isEnabled: Bool = true, inputTypes: [String] = ["text"]) {
            self.identifier = identifier
            self.displayName = displayName
            self.contextLength = contextLength
            self.inputPricePer1M = inputPricePer1M
            self.outputPricePer1M = outputPricePer1M
            self.isEnabled = isEnabled
            self.inputTypes = inputTypes
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            identifier = try container.decode(String.self, forKey: .identifier)
            displayName = try container.decode(String.self, forKey: .displayName)
            contextLength = try container.decodeIfPresent(Int.self, forKey: .contextLength)
            inputPricePer1M = try container.decodeIfPresent(Double.self, forKey: .inputPricePer1M)
            outputPricePer1M = try container.decodeIfPresent(Double.self, forKey: .outputPricePer1M)
            isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true

            // Try new format first, fall back to old supportsVision
            if let types = try container.decodeIfPresent([String].self, forKey: .inputTypes) {
                inputTypes = types
            } else if let supportsVision = try container.decodeIfPresent(Bool.self, forKey: .supportsVision) {
                inputTypes = supportsVision ? ["text", "image"] : ["text"]
            } else {
                inputTypes = ["text"]
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(identifier, forKey: .identifier)
            try container.encode(displayName, forKey: .displayName)
            try container.encodeIfPresent(contextLength, forKey: .contextLength)
            try container.encodeIfPresent(inputPricePer1M, forKey: .inputPricePer1M)
            try container.encodeIfPresent(outputPricePer1M, forKey: .outputPricePer1M)
            try container.encode(isEnabled, forKey: .isEnabled)
            try container.encode(inputTypes, forKey: .inputTypes)
        }
    }

    // MARK: - Export

    /// Show export options dialog
    func showExportOptions(channels: [Channel]) {
        // Step 1: Ask if user wants to encrypt
        let encryptAlert = NSAlert()
        encryptAlert.messageText = L10n.ChannelExport.exportChannels
        encryptAlert.informativeText = L10n.ChannelExport.encryptOptionDetail
        encryptAlert.alertStyle = .informational
        encryptAlert.addButton(withTitle: L10n.ChannelExport.exportChannels) // Export without encryption
        encryptAlert.addButton(withTitle: L10n.ChannelExport.encryptOption)  // Export with encryption
        encryptAlert.addButton(withTitle: L10n.Onboarding.cancel)

        let response = encryptAlert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            // Export without encryption
            exportChannelsWithPanel(channels, password: nil)

        case .alertSecondButtonReturn:
            // Step 2: Get password
            let passwordAlert = NSAlert()
            passwordAlert.messageText = L10n.ChannelExport.encryptOption
            passwordAlert.informativeText = L10n.ChannelExport.passwordPlaceholder
            passwordAlert.alertStyle = .informational
            passwordAlert.addButton(withTitle: L10n.ChannelExport.exportChannels)
            passwordAlert.addButton(withTitle: L10n.Onboarding.cancel)

            let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
            passwordField.placeholderString = L10n.ChannelExport.passwordPlaceholder
            passwordAlert.accessoryView = passwordField

            let passwordResponse = passwordAlert.runModal()
            guard passwordResponse == .alertFirstButtonReturn else { return }

            let password = passwordField.stringValue
            guard !password.isEmpty else {
                showAlert(title: L10n.ChannelExport.exportFailed, message: L10n.ChannelExport.passwordPlaceholder)
                return
            }
            exportChannelsWithPanel(channels, password: password)

        default:
            break
        }
    }

    /// Export selected channels to a JSON file
    func exportChannels(_ channels: [Channel], password: String? = nil) throws -> Data {
        var exportedChannels: [ExportedChannel] = []
        let useEncryption = password != nil && !(password?.isEmpty ?? true)

        // Generate encryption parameters if needed
        var salt: Data?
        var nonce: Data?
        var symmetricKey: SymmetricKey?

        if useEncryption {
            salt = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
            nonce = Data((0..<12).map { _ in UInt8.random(in: 0...255) })
            symmetricKey = deriveKey(from: password!, salt: salt!)
        }

        for channel in channels {
            guard let apiKey = channelServices.apiKey(for: channel.id) else {
                Log.warn("[ChannelExport] No API key for channel \(channel.name), skipping")
                continue
            }

            // Encrypt API key if needed
            let exportedApiKey: String
            if useEncryption, let key = symmetricKey, let nonceData = nonce {
                let encrypted = try encryptAPIKey(apiKey, key: key, nonce: nonceData)
                exportedApiKey = encrypted
            } else {
                exportedApiKey = apiKey
            }

            let exportedModels = channel.models.map { model in
                ExportedModel(
                    identifier: model.identifier,
                    displayName: model.displayName,
                    contextLength: model.contextLength,
                    inputPricePer1M: model.inputPricePer1M,
                    outputPricePer1M: model.outputPricePer1M,
                    isEnabled: model.isEnabled,
                    inputTypes: model.inputTypes
                )
            }

            let exportedChannel = ExportedChannel(
                name: channel.name,
                baseURL: channel.baseURL,
                protocolType: channel.protocol.rawValue,
                priority: channel.priority,
                models: exportedModels,
                apiKey: exportedApiKey
            )
            exportedChannels.append(exportedChannel)
        }

        let exportFile = ExportFile(
            format: "smartllmrouter/channels",
            version: 1,
            exportedAt: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
            channels: exportedChannels,
            encrypted: useEncryption,
            encryptionSalt: salt?.base64EncodedString(),
            encryptionNonce: nonce?.base64EncodedString()
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(exportFile)
    }

    /// Show save panel and export channels
    func exportChannelsWithPanel(_ channels: [Channel], password: String? = nil) {
        do {
            let data = try exportChannels(channels, password: password)

            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "smartllmrouter-channels.slmr.json"
            panel.message = L10n.ChannelExport.saveMessage
            panel.canCreateDirectories = true

            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }

                do {
                    try data.write(to: url)
                    Log.info("[ChannelExport] Exported \(channels.count) channels to \(url.path)")
                    DispatchQueue.main.async {
                        self.showAlert(
                            title: L10n.ChannelExport.exportSuccess,
                            message: L10n.ChannelExport.exportSuccessDetail(channels.count)
                        )
                    }
                } catch {
                    Log.error("[ChannelExport] Failed to write file: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.showAlert(
                            title: L10n.ChannelExport.exportFailed,
                            message: error.localizedDescription
                        )
                    }
                }
            }
        } catch {
            Log.error("[ChannelExport] Failed to encode channels: \(error.localizedDescription)")
            showAlert(
                title: L10n.ChannelExport.exportFailed,
                message: error.localizedDescription
            )
        }
    }

    // MARK: - Import

    /// Parse imported channels from data
    func parseImportData(_ data: Data) throws -> (ExportFile, [ExportedChannel]) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let exportFile = try decoder.decode(ExportFile.self, from: data)

        guard exportFile.format == "smartllmrouter/channels" else {
            throw ImportError.invalidFormat
        }

        guard exportFile.version >= 1 else {
            throw ImportError.unsupportedVersion(exportFile.version)
        }

        return (exportFile, exportFile.channels)
    }

    /// Import channels from exported data.
    /// - Returns: A `ImportResult` describing what happened to every channel.
    ///   The previous signature returned `Int` and silently dropped duplicates
    ///   and keychain/decryption failures — users would see "Imported 4
    ///   channels" when only 2 actually made it in.
    func importChannels(_ exportedChannels: [ExportedChannel], exportFile: ExportFile, password: String? = nil) -> ImportResult {
        var imported = 0
        var skipped: [ImportResult.Issue] = []
        var failed: [ImportResult.Issue] = []
        var symmetricKey: SymmetricKey?

        // Decrypt API keys if needed
        if exportFile.encrypted {
            guard let password = password,
                  let saltBase64 = exportFile.encryptionSalt,
                  let salt = Data(base64Encoded: saltBase64) else {
                Log.error("[ChannelExport] Missing encryption parameters")
                return ImportResult(total: exportedChannels.count, imported: 0,
                                    skipped: [], failed: [ImportResult.Issue(
                                        channelName: "—",
                                        reason: L10n.ChannelExport.importFailedKeychain("file", "Missing encryption parameters")
                                    )])
            }
            symmetricKey = deriveKey(from: password, salt: salt)
        }

        for exported in exportedChannels {
            // Check for duplicate baseURL
            if channelServices.channels.contains(where: { $0.baseURL.lowercased() == exported.baseURL.lowercased() }) {
                Log.info("[ChannelExport] Skipping duplicate channel: \(exported.baseURL)")
                skipped.append(ImportResult.Issue(
                    channelName: exported.name,
                    reason: L10n.ChannelExport.importSkippedDuplicate(exported.baseURL)
                ))
                continue
            }

            // Decrypt API key if needed
            let apiKey: String
            if exportFile.encrypted, let key = symmetricKey, let nonceBase64 = exportFile.encryptionNonce, let nonce = Data(base64Encoded: nonceBase64) {
                do {
                    apiKey = try decryptAPIKey(exported.apiKey, key: key, nonce: nonce)
                } catch {
                    Log.error("[ChannelExport] Failed to decrypt API key for \(exported.name): \(error.localizedDescription)")
                    failed.append(ImportResult.Issue(
                        channelName: exported.name,
                        reason: L10n.ChannelExport.importFailedDecrypt(exported.name, error.localizedDescription)
                    ))
                    continue
                }
            } else {
                apiKey = exported.apiKey
            }

            // Parse protocol
            let protocolType = APIProtocol(rawValue: exported.protocolType) ?? .auto

            // Convert models
            let models = exported.models.map { model in
                ModelEntry(
                    id: UUID().uuidString,
                    identifier: model.identifier,
                    displayName: model.displayName,
                    contextLength: model.contextLength,
                    inputPricePer1M: model.inputPricePer1M,
                    outputPricePer1M: model.outputPricePer1M,
                    isEnabled: model.isEnabled,
                    inputTypes: model.inputTypes
                )
            }

            // Create channel
            let channel = Channel(
                id: UUID().uuidString,
                name: exported.name,
                baseURL: exported.baseURL,
                priority: exported.priority,
                protocol: protocolType,
                models: models
            )

            // Save API key
            do {
                try channelServices.setAPIKey(apiKey, for: channel.id)
            } catch {
                Log.error("[ChannelExport] Failed to save API key for \(exported.name): \(error.localizedDescription)")
                failed.append(ImportResult.Issue(
                    channelName: exported.name,
                    reason: L10n.ChannelExport.importFailedKeychain(exported.name, error.localizedDescription)
                ))
                continue
            }

            // Add channel
            channelServices.addChannel(channel)
            imported += 1
        }

        return ImportResult(
            total: exportedChannels.count,
            imported: imported,
            skipped: skipped,
            failed: failed
        )
    }

    /// Show open panel and import channels
    func importChannelsWithPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = L10n.ChannelExport.openMessage

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            do {
                let data = try Data(contentsOf: url)
                let (exportFile, exportedChannels) = try self.parseImportData(data)

                DispatchQueue.main.async {
                    if exportFile.encrypted {
                        self.showPasswordPrompt(exportFile: exportFile, channels: exportedChannels)
                    } else {
                        self.showImportPreview(exportFile: exportFile, channels: exportedChannels)
                    }
                }
            } catch {
                Log.error("[ChannelExport] Failed to read import file: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.showAlert(
                        title: L10n.ChannelExport.importFailed,
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    /// Show password prompt for encrypted files
    private func showPasswordPrompt(exportFile: ExportFile, channels: [ExportedChannel]) {
        let alert = NSAlert()
        alert.messageText = L10n.ChannelExport.decryptPrompt
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.ConfigImporter.ok)
        alert.addButton(withTitle: L10n.Onboarding.cancel)

        let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        passwordField.placeholderString = L10n.ChannelExport.passwordPrompt
        alert.accessoryView = passwordField

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let password = passwordField.stringValue
        guard !password.isEmpty else {
            showAlert(title: L10n.ChannelExport.importFailed, message: L10n.ChannelExport.passwordPlaceholder)
            return
        }

        // Try to decrypt to verify password
        if let saltBase64 = exportFile.encryptionSalt,
           let salt = Data(base64Encoded: saltBase64),
           let nonceBase64 = exportFile.encryptionNonce,
           let nonce = Data(base64Encoded: nonceBase64) {
            let key = deriveKey(from: password, salt: salt)
            // Try decrypting first channel's API key to verify
            if let firstChannel = channels.first {
                do {
                    _ = try decryptAPIKey(firstChannel.apiKey, key: key, nonce: nonce)
                } catch {
                    showAlert(title: L10n.ChannelExport.importFailed, message: L10n.ChannelExport.decryptFailed)
                    return
                }
            }
        }

        showImportPreview(exportFile: exportFile, channels: channels, password: password)
    }

    /// Show import preview dialog
    private func showImportPreview(exportFile: ExportFile, channels: [ExportedChannel], password: String? = nil) {
        let alert = NSAlert()
        alert.messageText = L10n.ChannelExport.importPreview
        alert.informativeText = L10n.ChannelExport.importPreviewDetail(channels.count)
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.ChannelExport.importAll)
        alert.addButton(withTitle: L10n.Onboarding.cancel)

        // Add accessory view with channel list
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        var previewText = ""
        if exportFile.encrypted {
            previewText += "🔒 \(L10n.ChannelExport.encryptOption)\n\n"
        }
        for (index, channel) in channels.enumerated() {
            previewText += "\(index + 1). \(channel.name)\n"
            previewText += "   URL: \(channel.baseURL)\n"
            previewText += "   Protocol: \(channel.protocolType)\n"
            previewText += "   Models: \(channel.models.count)\n"
            if exportFile.encrypted {
                previewText += "   API Key: 🔒 encrypted\n"
            } else {
                previewText += "   API Key: \(channel.apiKey.prefix(8))...\n"
            }
            previewText += "\n"
        }
        textView.string = previewText

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        alert.accessoryView = scrollView

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let result = importChannels(channels, exportFile: exportFile, password: password)
            showImportResult(result)
        }
    }

    /// Show the result of an import. Surfaces skipped duplicates and
    /// keychain / decryption failures that the previous design silently
    /// logged. If everything went well, the success detail is the same
    /// as before; if anything was skipped or failed, the user sees a
    /// short report so they know whether the file actually imported.
    private func showImportResult(_ result: ImportResult) {
        let alert = NSAlert()
        if result.imported == result.total && !result.hasIssues {
            // Clean success
            alert.messageText = L10n.ChannelExport.importSuccess
            alert.informativeText = L10n.ChannelExport.importSuccessDetail(result.imported)
            alert.alertStyle = .informational
        } else if result.imported == 0 {
            // Total failure
            alert.messageText = L10n.ChannelExport.importFailed
            alert.informativeText = L10n.ChannelExport.importNoneDetail
            alert.alertStyle = .critical
        } else {
            // Partial success
            alert.messageText = L10n.ChannelExport.importSuccess
            alert.informativeText = L10n.ChannelExport.importSuccessPartialDetail(
                result.imported, result.total,
                result.skipped.count, result.failed.count
            )
            alert.alertStyle = .warning
        }
        alert.addButton(withTitle: L10n.ConfigImporter.ok)

        if result.hasIssues {
            // Build a details accessory view so the user can see exactly
            // which channels were skipped or failed and why.
            let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 160))
            let textView = NSTextView(frame: scrollView.bounds)
            textView.isEditable = false
            textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            textView.textContainerInset = NSSize(width: 8, height: 8)

            var detail = L10n.ChannelExport.importDetailsHeader + "\n\n"
            for issue in result.skipped {
                detail += "• \(issue.reason)\n"
            }
            for issue in result.failed {
                detail += "• \(issue.reason)\n"
            }
            textView.string = detail

            scrollView.documentView = textView
            scrollView.hasVerticalScroller = true
            alert.accessoryView = scrollView
        }

        alert.runModal()
    }

    // MARK: - Encryption Helpers

    /// Derive a symmetric key from password and salt using PBKDF2
    private func deriveKey(from password: String, salt: Data) -> SymmetricKey {
        let passwordData = password.data(using: .utf8)!
        let keyData = pbkdf2(password: passwordData, salt: salt, iterations: 100_000, keyLength: 32)
        return SymmetricKey(data: keyData)
    }

    /// PBKDF2 key derivation
    private func pbkdf2(password: Data, salt: Data, iterations: Int, keyLength: Int) -> Data {
        var derivedKey = Data(count: keyLength)
        let result = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                password.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        password.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyLength
                    )
                }
            }
        }
        guard result == kCCSuccess else {
            Log.error("[ChannelExport] PBKDF2 failed with status: \(result)")
            return Data(count: keyLength)
        }
        return derivedKey
    }

    /// Encrypt API key using AES-GCM
    private func encryptAPIKey(_ apiKey: String, key: SymmetricKey, nonce: Data) throws -> String {
        let data = apiKey.data(using: .utf8)!
        let aesNonce = try AES.GCM.Nonce(data: nonce)
        let sealedBox = try AES.GCM.seal(data, using: key, nonce: aesNonce)
        return sealedBox.combined!.base64EncodedString()
    }

    /// Decrypt API key using AES-GCM
    private func decryptAPIKey(_ encryptedBase64: String, key: SymmetricKey, nonce: Data) throws -> String {
        guard let data = Data(base64Encoded: encryptedBase64) else {
            throw EncryptionError.invalidData
        }
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)
        return String(data: decryptedData, encoding: .utf8) ?? ""
    }

    // MARK: - Helpers

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }

    // MARK: - Errors

    enum ImportError: LocalizedError {
        case invalidFormat
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                return L10n.ChannelExport.invalidFormat
            case .unsupportedVersion(let version):
                return L10n.ChannelExport.unsupportedVersion(version)
            }
        }
    }

    enum EncryptionError: LocalizedError {
        case invalidData

        var errorDescription: String? {
            switch self {
            case .invalidData:
                return L10n.ChannelExport.decryptFailed
            }
        }
    }
}
