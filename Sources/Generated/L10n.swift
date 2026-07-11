// swiftlint:disable all
// Generated using SwiftGen — https://github.com/SwiftGen/SwiftGen

import Foundation

// swiftlint:disable superfluous_disable_command file_length implicit_return prefer_self_in_static_references

// MARK: - Strings

// swiftlint:disable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:disable nesting type_body_length type_name vertical_whitespace_opening_braces
internal enum L10n {
  internal enum About {
    /// SmartLLM Router
    internal static var appName: String {
      L10n.tr("Localizable", "about.appName", fallback: "SmartLLM Router")
    }
  }
  internal enum AddChannel {
    /// Add API Key
    internal static var addApiKey: String {
      L10n.tr("Localizable", "addchannel.addApiKey", fallback: "Add API Key")
    }
    /// Add Channel
    internal static var addChannel: String {
      L10n.tr("Localizable", "addchannel.addChannel", fallback: "Add Channel")
    }
    /// Add Model
    internal static var addModel: String {
      L10n.tr("Localizable", "addchannel.addModel", fallback: "Add Model")
    }
    /// Copy model name
    internal static var copyModelName: String {
      L10n.tr("Localizable", "addchannel.copyModelName", fallback: "Copy model name")
    }
    /// sk-...
    internal static var apiKeyPlaceholder: String {
      L10n.tr("Localizable", "addchannel.apiKeyPlaceholder", fallback: "sk-...")
    }
    /// API Keys
    internal static var apiKeys: String {
      L10n.tr("Localizable", "addchannel.apiKeys", fallback: "API Keys")
    }
    /// https://api.example.com/v1
    internal static var baseUrlPlaceholder: String {
      L10n.tr("Localizable", "addchannel.baseUrlPlaceholder", fallback: "https://api.example.com/v1")
    }
    /// Cancel
    internal static var cancel: String {
      L10n.tr("Localizable", "addchannel.cancel", fallback: "Cancel")
    }
    /// Custom / Local
    internal static var customProvider: String {
      L10n.tr("Localizable", "addchannel.customProvider", fallback: "Custom / Local")
    }
    /// Delete
    internal static var delete: String {
      L10n.tr("Localizable", "addchannel.delete", fallback: "Delete")
    }
    /// Fetch Models
    internal static var fetchModels: String {
      L10n.tr("Localizable", "addchannel.fetchModels", fallback: "Fetch Models")
    }
    /// e.g. gpt-4, llama3
    internal static var modelNamePlaceholder: String {
      L10n.tr("Localizable", "addchannel.modelNamePlaceholder", fallback: "e.g. gpt-4, llama3")
    }
    /// Model ID
    internal static var modelPlaceholder: String {
      L10n.tr("Localizable", "addchannel.modelPlaceholder", fallback: "Model ID")
    }
    /// Models
    internal static var models: String {
      L10n.tr("Localizable", "addchannel.models", fallback: "Models")
    }
    /// Move API Key Down
    internal static var moveApiKeyDown: String {
      L10n.tr("Localizable", "addchannel.moveApiKeyDown", fallback: "Move API Key Down")
    }
    /// Move API Key Up
    internal static var moveApiKeyUp: String {
      L10n.tr("Localizable", "addchannel.moveApiKeyUp", fallback: "Move API Key Up")
    }
    /// No models added
    internal static var noModels: String {
      L10n.tr("Localizable", "addchannel.noModels", fallback: "No models added")
    }
    /// Priority
    internal static var priority: String {
      L10n.tr("Localizable", "addchannel.priority", fallback: "Priority")
    }
    /// Protocol
    internal static var `protocol`: String {
      L10n.tr("Localizable", "addchannel.protocol", fallback: "Protocol")
    }
    /// Provider Name
    internal static var providerName: String {
      L10n.tr("Localizable", "addchannel.providerName", fallback: "Provider Name")
    }
    /// e.g. Local Ollama
    internal static var providerNamePlaceholder: String {
      L10n.tr("Localizable", "addchannel.providerNamePlaceholder", fallback: "e.g. Local Ollama")
    }
    /// models.dev
    internal static var refreshProviders: String {
      L10n.tr("Localizable", "addchannel.refreshProviders", fallback: "models.dev")
    }
    /// models.dev update failed
    internal static var refreshProvidersFailed: String {
      L10n.tr("Localizable", "addchannel.refreshProvidersFailed", fallback: "models.dev update failed")
    }
    /// Refresh providers from models.dev
    internal static var refreshProvidersHelp: String {
      L10n.tr("Localizable", "addchannel.refreshProvidersHelp", fallback: "Refresh providers from models.dev")
    }
    /// Updated %lld providers from models.dev
    internal static func refreshProvidersSuccess(_ p1: Int) -> String {
      return L10n.tr("Localizable", "addchannel.refreshProvidersSuccess", p1, fallback: "Updated %lld providers from models.dev")
    }
    /// Remove API Key
    internal static var removeApiKey: String {
      L10n.tr("Localizable", "addchannel.removeApiKey", fallback: "Remove API Key")
    }
    /// Remove Model
    internal static var removeModel: String {
      L10n.tr("Localizable", "addchannel.removeModel", fallback: "Remove Model")
    }
    /// Search...
    internal static var search: String {
      L10n.tr("Localizable", "addchannel.search", fallback: "Search...")
    }
    /// Search providers...
    internal static var searchPlaceholder: String {
      L10n.tr("Localizable", "addchannel.searchPlaceholder", fallback: "Search providers...")
    }
    /// Update
    internal static var update: String {
      L10n.tr("Localizable", "addchannel.update", fallback: "Update")
    }
  }
  internal enum App {
    /// SmartLLM Router
    internal static var name: String {
      L10n.tr("Localizable", "app.name", fallback: "SmartLLM Router")
    }
    /// Error
    internal static var statusError: String {
      L10n.tr("Localizable", "app.status.error", fallback: "Error")
    }
    /// Running
    internal static var statusRunning: String {
      L10n.tr("Localizable", "app.status.running", fallback: "Running")
    }
    /// Starting...
    internal static var statusStarting: String {
      L10n.tr("Localizable", "app.status.starting", fallback: "Starting...")
    }
    /// Stopped
    internal static var statusStopped: String {
      L10n.tr("Localizable", "app.status.stopped", fallback: "Stopped")
    }
  }
  internal enum ChannelExport {
    /// Failed to decrypt. Wrong password?
    internal static var decryptFailed: String {
      L10n.tr("Localizable", "channelExport.decryptFailed", fallback: "Failed to decrypt. Wrong password?")
    }
    /// This file contains encrypted API keys. Enter password to decrypt.
    internal static var decryptPrompt: String {
      L10n.tr("Localizable", "channelExport.decryptPrompt", fallback: "This file contains encrypted API keys. Enter password to decrypt.")
    }
    /// Encrypt API Keys
    internal static var encryptOption: String {
      L10n.tr("Localizable", "channelExport.encryptOption", fallback: "Encrypt API Keys")
    }
    /// Protect exported API keys with a password
    internal static var encryptOptionDetail: String {
      L10n.tr("Localizable", "channelExport.encryptOptionDetail", fallback: "Protect exported API keys with a password")
    }
    /// Export Channels
    internal static var exportChannels: String {
      L10n.tr("Localizable", "channelExport.exportChannels", fallback: "Export Channels")
    }
    /// Export channel configurations and API keys to share with others
    internal static var exportDescription: String {
      L10n.tr("Localizable", "channelExport.exportDescription", fallback: "Export channel configurations and API keys to share with others")
    }
    /// Export Failed
    internal static var exportFailed: String {
      L10n.tr("Localizable", "channelExport.exportFailed", fallback: "Export Failed")
    }
    /// Export Successful
    internal static var exportSuccess: String {
      L10n.tr("Localizable", "channelExport.exportSuccess", fallback: "Export Successful")
    }
    /// Successfully exported %d channels
    internal static func exportSuccessDetail(_ p1: Int) -> String {
      return L10n.tr("Localizable", "channelExport.exportSuccessDetail", p1, fallback: "Successfully exported %d channels")
    }
    /// Import All
    internal static var importAll: String {
      L10n.tr("Localizable", "channelExport.importAll", fallback: "Import All")
    }
    /// Import Channels
    internal static var importChannels: String {
      L10n.tr("Localizable", "channelExport.importChannels", fallback: "Import Channels")
    }
    /// Import channel configurations from a .slmr.json file
    internal static var importDescription: String {
      L10n.tr("Localizable", "channelExport.importDescription", fallback: "Import channel configurations from a .slmr.json file")
    }
    /// Issues encountered:
    internal static var importDetailsHeader: String {
      L10n.tr("Localizable", "channelExport.importDetailsHeader", fallback: "Issues encountered:")
    }
    /// Import Failed
    internal static var importFailed: String {
      L10n.tr("Localizable", "channelExport.importFailed", fallback: "Import Failed")
    }
    /// Decryption error for %@: %@
    internal static func importFailedDecrypt(_ p1: Any, _ p2: Any) -> String {
      return L10n.tr("Localizable", "channelExport.importFailedDecrypt", String(describing: p1), String(describing: p2), fallback: "Decryption error for %@: %@")
    }
    /// Keychain error for %@: %@
    internal static func importFailedKeychain(_ p1: Any, _ p2: Any) -> String {
      return L10n.tr("Localizable", "channelExport.importFailedKeychain", String(describing: p1), String(describing: p2), fallback: "Keychain error for %@: %@")
    }
    /// No channels were imported. See the items below for details.
    internal static var importNoneDetail: String {
      L10n.tr("Localizable", "channelExport.importNoneDetail", fallback: "No channels were imported. See the items below for details.")
    }
    /// Import Preview
    internal static var importPreview: String {
      L10n.tr("Localizable", "channelExport.importPreview", fallback: "Import Preview")
    }
    /// Found %d channels in the file. Review the details below:
    internal static func importPreviewDetail(_ p1: Int) -> String {
      return L10n.tr("Localizable", "channelExport.importPreviewDetail", p1, fallback: "Found %d channels in the file. Review the details below:")
    }
    /// Skipped duplicate channel: %@
    internal static func importSkippedDuplicate(_ p1: Any) -> String {
      return L10n.tr("Localizable", "channelExport.importSkippedDuplicate", String(describing: p1), fallback: "Skipped duplicate channel: %@")
    }
    /// Import Successful
    internal static var importSuccess: String {
      L10n.tr("Localizable", "channelExport.importSuccess", fallback: "Import Successful")
    }
    /// Successfully imported %d channels
    internal static func importSuccessDetail(_ p1: Int) -> String {
      return L10n.tr("Localizable", "channelExport.importSuccessDetail", p1, fallback: "Successfully imported %d channels")
    }
    /// Imported %d of %d channels. %d skipped, %d failed.
    internal static func importSuccessPartialDetail(_ p1: Int, _ p2: Int, _ p3: Int, _ p4: Int) -> String {
      return L10n.tr("Localizable", "channelExport.importSuccessPartialDetail", p1, p2, p3, p4, fallback: "Imported %d of %d channels. %d skipped, %d failed.")
    }
    /// Invalid file format. Expected a SmartLLMRouter channels file.
    internal static var invalidFormat: String {
      L10n.tr("Localizable", "channelExport.invalidFormat", fallback: "Invalid file format. Expected a SmartLLMRouter channels file.")
    }
    /// Select a .slmr.json file to import
    internal static var openMessage: String {
      L10n.tr("Localizable", "channelExport.openMessage", fallback: "Select a .slmr.json file to import")
    }
    /// Passwords do not match
    internal static var passwordMismatch: String {
      L10n.tr("Localizable", "channelExport.passwordMismatch", fallback: "Passwords do not match")
    }
    /// Password (leave empty for no encryption)
    internal static var passwordPlaceholder: String {
      L10n.tr("Localizable", "channelExport.passwordPlaceholder", fallback: "Password (leave empty for no encryption)")
    }
    /// Enter encryption password
    internal static var passwordPrompt: String {
      L10n.tr("Localizable", "channelExport.passwordPrompt", fallback: "Enter encryption password")
    }
    /// Choose where to save the exported channels file
    internal static var saveMessage: String {
      L10n.tr("Localizable", "channelExport.saveMessage", fallback: "Choose where to save the exported channels file")
    }
    /// Security Warning
    internal static var securityWarning: String {
      L10n.tr("Localizable", "channelExport.securityWarning", fallback: "Security Warning")
    }
    /// The exported file contains API keys in plain text. Please handle with care and share only with trusted parties.
    internal static var securityWarningDetail: String {
      L10n.tr("Localizable", "channelExport.securityWarningDetail", fallback: "The exported file contains API keys in plain text. Please handle with care and share only with trusted parties.")
    }
    /// Unsupported file version: %d. Please update SmartLLMRouter.
    internal static func unsupportedVersion(_ p1: Int) -> String {
      return L10n.tr("Localizable", "channelExport.unsupportedVersion", p1, fallback: "Unsupported file version: %d. Please update SmartLLMRouter.")
    }
  }
  internal enum CircuitBreaker {
    /// Consecutive Failures
    internal static var consecutiveFailures: String {
      L10n.tr("Localizable", "circuitbreaker.consecutiveFailures", fallback: "Consecutive Failures")
    }
    /// Automatically disable channels after consecutive failures
    internal static var description: String {
      L10n.tr("Localizable", "circuitbreaker.description", fallback: "Automatically disable channels after consecutive failures")
    }
    /// Enabled
    internal static var enabled: String {
      L10n.tr("Localizable", "circuitbreaker.enabled", fallback: "Enabled")
    }
    /// Failure Rate
    internal static var failureRate: String {
      L10n.tr("Localizable", "circuitbreaker.failureRate", fallback: "Failure Rate")
    }
    /// Recovery Timeout
    internal static var recoveryTimeout: String {
      L10n.tr("Localizable", "circuitbreaker.recoveryTimeout", fallback: "Recovery Timeout")
    }
    /// Remaining: %@
    internal static func remainingTime(_ p1: Any) -> String {
      return L10n.tr("Localizable", "circuitbreaker.remainingTime", String(describing: p1), fallback: "Remaining: %@")
    }
    /// Reset All
    internal static var resetAll: String {
      L10n.tr("Localizable", "circuitbreaker.resetAll", fallback: "Reset All")
    }
    /// Circuit Breaker
    internal static var title: String {
      L10n.tr("Localizable", "circuitbreaker.title", fallback: "Circuit Breaker")
    }
    /// Closed
    internal static var stateClosed: String {
      L10n.tr("Localizable", "circuitbreaker.state.closed", fallback: "Closed")
    }
    /// Half-Open
    internal static var stateHalfOpen: String {
      L10n.tr("Localizable", "circuitbreaker.state.halfOpen", fallback: "Half-Open")
    }
    /// Open
    internal static var stateOpen: String {
      L10n.tr("Localizable", "circuitbreaker.state.open", fallback: "Open")
    }
  }
  internal enum ClaudeCode {
    /// Backup created
    internal static var backupCreated: String {
      L10n.tr("Localizable", "claudecode.backupCreated", fallback: "Backup created")
    }
    /// Config file not found at ~/.claude/settings.json
    internal static var configNotFound: String {
      L10n.tr("Localizable", "claudecode.configNotFound", fallback: "Config file not found at ~/.claude/settings.json")
    }
    /// Current URL: %@
    internal static func currentUrl(_ p1: Any) -> String {
      return L10n.tr("Localizable", "claudecode.currentUrl", String(describing: p1), fallback: "Current URL: %@")
    }
    /// URL: not set
    internal static var currentUrlNotSet: String {
      L10n.tr("Localizable", "claudecode.currentUrlNotSet", fallback: "URL: not set")
    }
    /// Config restored from backup
    internal static var restored: String {
      L10n.tr("Localizable", "claudecode.restored", fallback: "Config restored from backup")
    }
    /// Claude Code Integration
    internal static var sectionTitle: String {
      L10n.tr("Localizable", "claudecode.sectionTitle", fallback: "Claude Code Integration")
    }
    /// Redirect Claude Code API requests through SmartLLM Router by modifying ~/.claude/settings.json. A backup is created automatically before any change.
    internal static var takeoverDescription: String {
      L10n.tr("Localizable", "claudecode.takeoverDescription", fallback: "Redirect Claude Code API requests through SmartLLM Router by modifying ~/.claude/settings.json. A backup is created automatically before any change.")
    }
    /// Take over Claude Code config
    internal static var takeoverToggle: String {
      L10n.tr("Localizable", "claudecode.takeoverToggle", fallback: "Take over Claude Code config")
    }
  }
  internal enum ConfigImporter {
    /// Deselect All
    internal static var deselectAll: String {
      L10n.tr("Localizable", "configimporter.deselectAll", fallback: "Deselect All")
    }
    /// Found %d providers
    internal static func foundChannels(_ p1: Int) -> String {
      return L10n.tr("Localizable", "configimporter.foundChannels", p1, fallback: "Found %d providers")
    }
    /// Import Complete
    internal static var importComplete: String {
      L10n.tr("Localizable", "configimporter.importComplete", fallback: "Import Complete")
    }
    /// Import Selected
    internal static var importSelected: String {
      L10n.tr("Localizable", "configimporter.importSelected", fallback: "Import Selected")
    }
    /// Successfully imported %d providers
    internal static func importSuccess(_ p1: Int) -> String {
      return L10n.tr("Localizable", "configimporter.importSuccess", p1, fallback: "Successfully imported %d providers")
    }
    /// No providers found
    internal static var noResults: String {
      L10n.tr("Localizable", "configimporter.noResults", fallback: "No providers found")
    }
    /// Try adding providers manually or check your configuration files
    internal static var noResultsDescription: String {
      L10n.tr("Localizable", "configimporter.noResultsDescription", fallback: "Try adding providers manually or check your configuration files")
    }
    /// OK
    internal static var ok: String {
      L10n.tr("Localizable", "configimporter.ok", fallback: "OK")
    }
    /// Scan
    internal static var scan: String {
      L10n.tr("Localizable", "configimporter.scan", fallback: "Scan")
    }
    /// Scanning...
    internal static var scanning: String {
      L10n.tr("Localizable", "configimporter.scanning", fallback: "Scanning...")
    }
    /// Select All
    internal static var selectAll: String {
      L10n.tr("Localizable", "configimporter.selectAll", fallback: "Select All")
    }
    /// Scan for existing provider configurations
    internal static var subtitle: String {
      L10n.tr("Localizable", "configimporter.subtitle", fallback: "Scan for existing provider configurations")
    }
    /// Import API Providers
    internal static var title: String {
      L10n.tr("Localizable", "configimporter.title", fallback: "Import API Providers")
    }
  }
  internal enum Error {
    /// Authentication Failed
    internal static var auth: String {
      L10n.tr("Localizable", "error.auth", fallback: "Authentication Failed")
    }
    /// All channels unavailable
    internal static var channelUnavailable: String {
      L10n.tr("Localizable", "error.channel_unavailable", fallback: "All channels unavailable")
    }
    /// Context length exceeded
    internal static var contextExceeded: String {
      L10n.tr("Localizable", "error.contextExceeded", fallback: "Context length exceeded")
    }
    /// Invalid port number
    internal static var invalidPort: String {
      L10n.tr("Localizable", "error.invalid_port", fallback: "Invalid port number")
    }
    /// Invalid Request
    internal static var invalidRequest: String {
      L10n.tr("Localizable", "error.invalid_request", fallback: "Invalid Request")
    }
    /// Network Error: %@
    internal static func network(_ p1: Any) -> String {
      return L10n.tr("Localizable", "error.network", String(describing: p1), fallback: "Network Error: %@")
    }
    /// No API key configured
    internal static var noApiKey: String {
      L10n.tr("Localizable", "error.no_api_key", fallback: "No API key configured")
    }
    /// Rate Limit Exceeded
    internal static var rateLimit: String {
      L10n.tr("Localizable", "error.rate_limit", fallback: "Rate Limit Exceeded")
    }
    /// Server Error
    internal static var server: String {
      L10n.tr("Localizable", "error.server", fallback: "Server Error")
    }
    /// Unknown Error
    internal static var unknown: String {
      L10n.tr("Localizable", "error.unknown", fallback: "Unknown Error")
    }
  }
  internal enum Menu {
    /// Quit
    internal static var quit: String {
      L10n.tr("Localizable", "menu.quit", fallback: "Quit")
    }
    /// Settings...
    internal static var settings: String {
      L10n.tr("Localizable", "menu.settings", fallback: "Settings...")
    }
    /// Speed: %lldms
    internal static func speed(_ p1: Int) -> String {
      return L10n.tr("Localizable", "menu.speed", p1, fallback: "Speed: %lldms")
    }
    /// Copy Config
    internal static var copyConfig: String {
      L10n.tr("Localizable", "menu.copy.config", fallback: "Copy Config")
    }
    /// Copy Env Config
    internal static var copyEnv: String {
      L10n.tr("Localizable", "menu.copy.env", fallback: "Copy Env Config")
    }
    /// Auto-Failover
    internal static var failoverAuto: String {
      L10n.tr("Localizable", "menu.failover.auto", fallback: "Auto-Failover")
    }
    /// Manual Mode
    internal static var failoverManual: String {
      L10n.tr("Localizable", "menu.failover.manual", fallback: "Manual Mode")
    }
    /// Skip failed channels after 429 / 5xx / 401
    internal static var failoverSubtitle: String {
      L10n.tr("Localizable", "menu.failover.subtitle", fallback: "Skip failed channels after 429 / 5xx / 401")
    }
    /// Pause
    internal static var proxyPause: String {
      L10n.tr("Localizable", "menu.proxy.pause", fallback: "Pause")
    }
    /// Start
    internal static var proxyStart: String {
      L10n.tr("Localizable", "menu.proxy.start", fallback: "Start")
    }
    /// Listening for local requests
    internal static var proxyRunningSubtitle: String {
      L10n.tr("Localizable", "menu.proxy.running.subtitle", fallback: "Listening for local requests")
    }
    /// Proxy paused. App stays open.
    internal static var proxyStoppedSubtitle: String {
      L10n.tr("Localizable", "menu.proxy.stopped.subtitle", fallback: "Proxy paused. App stays open.")
    }
    /// %s · %s · %s
    internal static func requestEntry(_ p1: UnsafePointer<CChar>, _ p2: UnsafePointer<CChar>, _ p3: UnsafePointer<CChar>) -> String {
      return L10n.tr("Localizable", "menu.request.entry", p1, p2, p3, fallback: "%s · %s · %s")
    }
    /// %lld items
    internal static func requestsCount(_ p1: Int) -> String {
      return L10n.tr("Localizable", "menu.requests.count", p1, fallback: "%lld items")
    }
    /// No recent requests
    internal static var requestsNone: String {
      L10n.tr("Localizable", "menu.requests.none", fallback: "No recent requests")
    }
    /// Recent Requests
    internal static var requestsRecent: String {
      L10n.tr("Localizable", "menu.requests.recent", fallback: "Recent Requests")
    }
    /// OpenAI / Anthropic
    internal static var routingProtocols: String {
      L10n.tr("Localizable", "menu.routing.protocols", fallback: "OpenAI / Anthropic")
    }
    /// Routing
    internal static var routingTitle: String {
      L10n.tr("Localizable", "menu.routing.title", fallback: "Routing")
    }
    /// Auto-route by requested model
    internal static var routingDefaultSubtitle: String {
      L10n.tr("Localizable", "menu.routing.default.subtitle", fallback: "Auto-route by requested model")
    }
    /// Force this model for client requests
    internal static var routingOverrideSubtitle: String {
      L10n.tr("Localizable", "menu.routing.override.subtitle", fallback: "Force this model for client requests")
    }
    /// Requests: %lld
    internal static func statsRequests(_ p1: Int) -> String {
      return L10n.tr("Localizable", "menu.stats.requests", p1, fallback: "Requests: %lld")
    }
    /// %lld requests · %lld tokens
    internal static func statsSummary(_ p1: Int, _ p2: Int) -> String {
      return L10n.tr("Localizable", "menu.stats.summary", p1, p2, fallback: "%lld requests · %lld tokens")
    }
    /// Tokens: %lld
    internal static func statsTokens(_ p1: Int) -> String {
      return L10n.tr("Localizable", "menu.stats.tokens", p1, fallback: "Tokens: %lld")
    }
    /// Requests today
    internal static var statsRequestsLabel: String {
      L10n.tr("Localizable", "menu.stats.requests.label", fallback: "Requests today")
    }
    /// Tokens
    internal static var statsTokensLabel: String {
      L10n.tr("Localizable", "menu.stats.tokens.label", fallback: "Tokens")
    }
    /// Test Channels
    internal static var testChannels: String {
      L10n.tr("Localizable", "menu.test.channels", fallback: "Test Channels")
    }
    /// Test Channels
    internal static var testKey: String {
      L10n.tr("Localizable", "menu.test.key", fallback: "Test Channels")
    }
    /// %dh ago
    internal static func timeHours(_ p1: Int) -> String {
      return L10n.tr("Localizable", "menu.time.hours", p1, fallback: "%dh ago")
    }
    /// %dd %dh ago
    internal static func timeDaysHours(_ p1: Int, _ p2: Int) -> String {
      return L10n.tr("Localizable", "menu.time.daysHours", p1, p2, fallback: "%dd %dh ago")
    }
    /// %dm ago
    internal static func timeMinutes(_ p1: Int) -> String {
      return L10n.tr("Localizable", "menu.time.minutes", p1, fallback: "%dm ago")
    }
    /// %ds ago
    internal static func timeSeconds(_ p1: Int) -> String {
      return L10n.tr("Localizable", "menu.time.seconds", p1, fallback: "%ds ago")
    }
  }
  internal enum Model {
    /// Active: %@
    internal static func active(_ p1: Any) -> String {
      return L10n.tr("Localizable", "model.active", String(describing: p1), fallback: "Active: %@")
    }
    /// Default (Passthrough)
    internal static var defaultPassthrough: String {
      L10n.tr("Localizable", "model.default.passthrough", fallback: "Default (Passthrough)")
    }
    /// No models available
    internal static var noModelsAvailable: String {
      L10n.tr("Localizable", "model.no.models.available", fallback: "No models available")
    }
    /// Protocol incompatible
    internal static var protocolIncompatible: String {
      L10n.tr("Localizable", "model.protocol.incompatible", fallback: "Protocol incompatible")
    }
    /// Model
    internal static var selectorLabel: String {
      L10n.tr("Localizable", "model.selector.label", fallback: "Model")
    }
  }
  internal enum ModelEditor {
    /// Cancel
    internal static var cancel: String {
      L10n.tr("Localizable", "modelEditor.cancel", fallback: "Cancel")
    }
    /// Close
    internal static var close: String {
      L10n.tr("Localizable", "modelEditor.close", fallback: "Close")
    }
    /// Context Length
    internal static var contextLength: String {
      L10n.tr("Localizable", "modelEditor.contextLength", fallback: "Context Length")
    }
    /// Context Length (tokens)
    internal static var contextLengthLabel: String {
      L10n.tr("Localizable", "modelEditor.contextLengthLabel", fallback: "Context Length (tokens)")
    }
    /// 128000
    internal static var contextLengthPlaceholder: String {
      L10n.tr("Localizable", "modelEditor.contextLengthPlaceholder", fallback: "128000")
    }
    /// Edit
    internal static var edit: String {
      L10n.tr("Localizable", "modelEditor.edit", fallback: "Edit")
    }
    /// Edit Model: %@
    internal static func editModel(_ p1: Any) -> String {
      return L10n.tr("Localizable", "modelEditor.editModel", String(describing: p1), fallback: "Edit Model: %@")
    }
    /// Input Price ($/1M tokens)
    internal static var inputPrice: String {
      L10n.tr("Localizable", "modelEditor.inputPrice", fallback: "Input Price ($/1M tokens)")
    }
    /// Input Price ($/1M tokens)
    internal static var inputPriceLabel: String {
      L10n.tr("Localizable", "modelEditor.inputPriceLabel", fallback: "Input Price ($/1M tokens)")
    }
    /// 5.00
    internal static var inputPricePlaceholder: String {
      L10n.tr("Localizable", "modelEditor.inputPricePlaceholder", fallback: "5.00")
    }
    /// Output Price ($/1M tokens)
    internal static var outputPrice: String {
      L10n.tr("Localizable", "modelEditor.outputPrice", fallback: "Output Price ($/1M tokens)")
    }
    /// Output Price ($/1M tokens)
    internal static var outputPriceLabel: String {
      L10n.tr("Localizable", "modelEditor.outputPriceLabel", fallback: "Output Price ($/1M tokens)")
    }
    /// 15.00
    internal static var outputPricePlaceholder: String {
      L10n.tr("Localizable", "modelEditor.outputPricePlaceholder", fallback: "15.00")
    }
    /// Save
    internal static var save: String {
      L10n.tr("Localizable", "modelEditor.save", fallback: "Save")
    }
  }
  internal enum Onboarding {
    /// Add your first channel
    internal static var addChannel: String {
      L10n.tr("Localizable", "onboarding.add_channel", fallback: "Add your first channel")
    }
    /// Enter your API key
    internal static var apiKeyPlaceholder: String {
      L10n.tr("Localizable", "onboarding.api_key_placeholder", fallback: "Enter your API key")
    }
    /// API Protocol
    internal static var apiProtocol: String {
      L10n.tr("Localizable", "onboarding.apiProtocol", fallback: "API Protocol")
    }
    /// Back
    internal static var back: String {
      L10n.tr("Localizable", "onboarding.back", fallback: "Back")
    }
    /// Base URL
    internal static var baseUrl: String {
      L10n.tr("Localizable", "onboarding.baseUrl", fallback: "Base URL")
    }
    /// Cancel
    internal static var cancel: String {
      L10n.tr("Localizable", "onboarding.cancel", fallback: "Cancel")
    }
    /// Connected
    internal static var connected: String {
      L10n.tr("Localizable", "onboarding.connected", fallback: "Connected")
    }
    /// Connection failed
    internal static var connectionFailed: String {
      L10n.tr("Localizable", "onboarding.connectionFailed", fallback: "Connection failed")
    }
    /// You're All Set!
    internal static var done: String {
      L10n.tr("Localizable", "onboarding.done", fallback: "You're All Set!")
    }
    /// SmartLLM Router is ready. Start sending requests to localhost:1897
    internal static var doneDescription: String {
      L10n.tr("Localizable", "onboarding.done_description", fallback: "SmartLLM Router is ready. Start sending requests to localhost:1897")
    }
    /// Automatic failover between API keys
    internal static var featureFailover: String {
      L10n.tr("Localizable", "onboarding.feature_failover", fallback: "Automatic failover between API keys")
    }
    /// Multi-provider key management
    internal static var featureMultiKey: String {
      L10n.tr("Localizable", "onboarding.feature_multi_key", fallback: "Multi-provider key management")
    }
    /// 100%% local — your keys never leave your Mac
    internal static var featurePrivacy: String {
      L10n.tr("Localizable", "onboarding.feature_privacy", fallback: "100%% local — your keys never leave your Mac")
    }
    /// Finish
    internal static var finish: String {
      L10n.tr("Localizable", "onboarding.finish", fallback: "Finish")
    }
    /// Launch App
    internal static var launch: String {
      L10n.tr("Localizable", "onboarding.launch", fallback: "Launch App")
    }
    /// Next
    internal static var next: String {
      L10n.tr("Localizable", "onboarding.next", fallback: "Next")
    }
    /// Provider Name
    internal static var providerName: String {
      L10n.tr("Localizable", "onboarding.providerName", fallback: "Provider Name")
    }
    /// Set Up Now
    internal static var setup: String {
      L10n.tr("Localizable", "onboarding.setup", fallback: "Set Up Now")
    }
    /// Configure Shell Environment
    internal static var shellConfig: String {
      L10n.tr("Localizable", "onboarding.shell_config", fallback: "Configure Shell Environment")
    }
    /// SmartLLM Router adds environment variables to ~/.zshenv so all shell sessions (including Claude Code, scripts, IDEs) use the proxy automatically
    internal static var shellConfigDescription: String {
      L10n.tr("Localizable", "onboarding.shell_config_description", fallback: "SmartLLM Router adds environment variables to ~/.zshenv so all shell sessions (including Claude Code, scripts, IDEs) use the proxy automatically")
    }
    /// You can configure this later in Settings
    internal static var shellConfigSkipped: String {
      L10n.tr("Localizable", "onboarding.shell_config_skipped", fallback: "You can configure this later in Settings")
    }
    /// Environment variables added successfully
    internal static var shellConfigSuccess: String {
      L10n.tr("Localizable", "onboarding.shell_config_success", fallback: "Environment variables added successfully")
    }
    /// Target file:
    internal static var shellConfigTargetFile: String {
      L10n.tr("Localizable", "onboarding.shell_config_target_file", fallback: "Target file:")
    }
    /// Will add:
    internal static var shellConfigWillAdd: String {
      L10n.tr("Localizable", "onboarding.shell_config_will_add", fallback: "Will add:")
    }
    /// Write to ~/.zshenv
    internal static var shellConfigure: String {
      L10n.tr("Localizable", "onboarding.shell_configure", fallback: "Write to ~/.zshenv")
    }
    /// Shell Configured ✓
    internal static var shellConfigured: String {
      L10n.tr("Localizable", "onboarding.shell_configured", fallback: "Shell Configured ✓")
    }
    /// Set Up Later
    internal static var skip: String {
      L10n.tr("Localizable", "onboarding.skip", fallback: "Set Up Later")
    }
    /// Your local LLM proxy and router
    internal static var subtitle: String {
      L10n.tr("Localizable", "onboarding.subtitle", fallback: "Your local LLM proxy and router")
    }
    /// Test your connection
    internal static var testConnection: String {
      L10n.tr("Localizable", "onboarding.test_connection", fallback: "Test your connection")
    }
    /// Test & Add
    internal static var testAndAdd: String {
      L10n.tr("Localizable", "onboarding.testAndAdd", fallback: "Test & Add")
    }
    /// Welcome to SmartLLM Router
    internal static var title: String {
      L10n.tr("Localizable", "onboarding.title", fallback: "Welcome to SmartLLM Router")
    }
    /// Add Channel
    internal static var addChannelAdd: String {
      L10n.tr("Localizable", "onboarding.addChannel.add", fallback: "Add Channel")
    }
    /// Add at least one channel to continue
    internal static var addChannelSubtitle: String {
      L10n.tr("Localizable", "onboarding.addChannel.subtitle", fallback: "Add at least one channel to continue")
    }
    /// Add Channels
    internal static var addChannelTitle: String {
      L10n.tr("Localizable", "onboarding.addChannel.title", fallback: "Add Channels")
    }
    /// Added Channels (%d)
    internal static func addedChannelsCount(_ p1: Int) -> String {
      return L10n.tr("Localizable", "onboarding.addedChannels.count", p1, fallback: "Added Channels (%d)")
    }
    /// Found %d models
    internal static func modelsFetched(_ p1: Int) -> String {
      return L10n.tr("Localizable", "onboarding.models.fetched", p1, fallback: "Found %d models")
    }
    /// Models fetch failed, you can fetch later in Settings
    internal static var modelsFetchFailed: String {
      L10n.tr("Localizable", "onboarding.models.fetchFailed", fallback: "Models fetch failed, you can fetch later in Settings")
    }
    /// Fetching models...
    internal static var modelsFetching: String {
      L10n.tr("Localizable", "onboarding.models.fetching", fallback: "Fetching models...")
    }
    /// Next → (%d channels)
    internal static func nextWithCount(_ p1: Int) -> String {
      return L10n.tr("Localizable", "onboarding.next.withCount", p1, fallback: "Next → (%d channels)")
    }
  }
  internal enum Rectifier {
    /// Stream error: buffering response
    internal static var streamErrorBuffering: String {
      L10n.tr("Localizable", "rectifier.streamErrorBuffering", fallback: "Stream error: buffering response")
    }
    /// Budget reduced to %@ tokens
    internal static func thinkingBudgetReduced(_ p1: Any) -> String {
      return L10n.tr("Localizable", "rectifier.thinkingBudget.reduced", String(describing: p1), fallback: "Budget reduced to %@ tokens")
    }
    /// Thinking Budget Adjusted
    internal static var thinkingBudgetTitle: String {
      L10n.tr("Localizable", "rectifier.thinkingBudget.title", fallback: "Thinking Budget Adjusted")
    }
  }
  internal enum Router {
    /// Fallback cost limit exceeded
    internal static var fallbackCostExceeded: String {
      L10n.tr("Localizable", "router.fallbackCostExceeded", fallback: "Fallback cost limit exceeded")
    }
    /// Estimated cost
    internal static var fallbackEstimatedCost: String {
      L10n.tr("Localizable", "router.fallbackEstimatedCost", fallback: "Estimated cost")
    }
    /// Fallback model
    internal static var fallbackModel: String {
      L10n.tr("Localizable", "router.fallbackModel", fallback: "Fallback model")
    }
    /// No suitable fallback model found
    internal static var fallbackNoCandidate: String {
      L10n.tr("Localizable", "router.fallbackNoCandidate", fallback: "No suitable fallback model found")
    }
    /// Original model
    internal static var fallbackOriginalModel: String {
      L10n.tr("Localizable", "router.fallbackOriginalModel", fallback: "Original model")
    }
    /// Fallback triggered for request %@
    internal static func fallbackTriggered(_ p1: Any) -> String {
      return L10n.tr("Localizable", "router.fallbackTriggered", String(describing: p1), fallback: "Fallback triggered for request %@")
    }
  }
  internal enum Settings {
    /// About
    internal static var about: String {
      L10n.tr("Localizable", "settings.about", fallback: "About")
    }
    /// Advanced
    internal static var advanced: String {
      L10n.tr("Localizable", "settings.advanced", fallback: "Advanced")
    }
    /// Channels
    internal static var channels: String {
      L10n.tr("Localizable", "settings.channels", fallback: "Channels")
    }
    /// General
    internal static var general: String {
      L10n.tr("Localizable", "settings.general", fallback: "General")
    }
    /// Settings
    internal static var title: String {
      L10n.tr("Localizable", "settings.title", fallback: "Settings")
    }
    /// Usage
    internal static var usage: String {
      L10n.tr("Localizable", "settings.usage", fallback: "Usage")
    }
    /// Check for Updates
    internal static var aboutCheckUpdate: String {
      L10n.tr("Localizable", "settings.about.check_update", fallback: "Check for Updates")
    }
    /// GitHub Repository
    internal static var aboutGithub: String {
      L10n.tr("Localizable", "settings.about.github", fallback: "GitHub Repository")
    }
    /// License
    internal static var aboutLicense: String {
      L10n.tr("Localizable", "settings.about.license", fallback: "License")
    }
    /// Version %@
    internal static func aboutVersion(_ p1: Any) -> String {
      return L10n.tr("Localizable", "settings.about.version", String(describing: p1), fallback: "Version %@")
    }
    /// Cooldown Period
    internal static var advancedCooldown: String {
      L10n.tr("Localizable", "settings.advanced.cooldown", fallback: "Cooldown Period")
    }
    /// Auto-Failover
    internal static var advancedFailover: String {
      L10n.tr("Localizable", "settings.advanced.failover", fallback: "Auto-Failover")
    }
    /// Max Fallback Cost
    internal static var advancedMaxFallbackCost: String {
      L10n.tr("Localizable", "settings.advanced.maxFallbackCost", fallback: "Max Fallback Cost")
    }
    /// per request
    internal static var advancedMaxFallbackCostHint: String {
      L10n.tr("Localizable", "settings.advanced.maxFallbackCostHint", fallback: "per request")
    }
    /// Configure failover, smart model fallback, and circuit breaker policies.
    internal static var advancedSubtitle: String {
      L10n.tr("Localizable", "settings.advanced.subtitle", fallback: "Configure failover, smart model fallback, and circuit breaker policies.")
    }
    /// Max Retries
    internal static var advancedRetryCount: String {
      L10n.tr("Localizable", "settings.advanced.retry_count", fallback: "Max Retries")
    }
    /// Smart Model Fallback
    internal static var advancedSmartFallback: String {
      L10n.tr("Localizable", "settings.advanced.smartFallback", fallback: "Smart Model Fallback")
    }
    /// When enabled, the proxy will automatically retry failed requests with a larger-context model from another provider. Your client will see the original model name, but the actual model may differ. Tool calling compatibility is not guaranteed across different models.
    internal static var advancedSmartFallbackWarning: String {
      L10n.tr("Localizable", "settings.advanced.smartFallbackWarning", fallback: "When enabled, the proxy will automatically retry failed requests with a larger-context model from another provider. Your client will see the original model name, but the actual model may differ. Tool calling compatibility is not guaranteed across different models.")
    }
    /// Request Timeout (seconds)
    internal static var advancedTimeout: String {
      L10n.tr("Localizable", "settings.advanced.timeout", fallback: "Request Timeout (seconds)")
    }
    /// Auth Error (401)
    internal static var advancedCooldown401: String {
      L10n.tr("Localizable", "settings.advanced.cooldown.401", fallback: "Auth Error (401)")
    }
    /// Rate Limit (429)
    internal static var advancedCooldown429: String {
      L10n.tr("Localizable", "settings.advanced.cooldown.429", fallback: "Rate Limit (429)")
    }
    /// Server Error (5xx)
    internal static var advancedCooldown5xx: String {
      L10n.tr("Localizable", "settings.advanced.cooldown.5xx", fallback: "Server Error (5xx)")
    }
    /// Add Channel
    internal static var channelsAdd: String {
      L10n.tr("Localizable", "settings.channels.add", fallback: "Add Channel")
    }
    /// API Key
    internal static var channelsApiKey: String {
      L10n.tr("Localizable", "settings.channels.api_key", fallback: "API Key")
    }
    /// Base URL
    internal static var channelsBaseUrl: String {
      L10n.tr("Localizable", "settings.channels.base_url", fallback: "Base URL")
    }
    /// %lld channels
    internal static func channelsCount(_ p1: Int) -> String {
      return L10n.tr("Localizable", "settings.channels.count", p1, fallback: "%lld channels")
    }
    /// Delete
    internal static var channelsDelete: String {
      L10n.tr("Localizable", "settings.channels.delete", fallback: "Delete")
    }
    /// Disable
    internal static var channelsDisable: String {
      L10n.tr("Localizable", "settings.channels.disable", fallback: "Disable")
    }
    /// Edit Channel
    internal static var channelsEdit: String {
      L10n.tr("Localizable", "settings.channels.edit", fallback: "Edit Channel")
    }
    /// Add one to get started
    internal static var channelsEmptySubtitle: String {
      L10n.tr("Localizable", "settings.channels.emptySubtitle", fallback: "Add one to get started")
    }
    /// No channels configured
    internal static var channelsEmptyTitle: String {
      L10n.tr("Localizable", "settings.channels.emptyTitle", fallback: "No channels configured")
    }
    /// Enable
    internal static var channelsEnable: String {
      L10n.tr("Localizable", "settings.channels.enable", fallback: "Enable")
    }
    /// Fetch Models
    internal static var channelsFetchModels: String {
      L10n.tr("Localizable", "settings.channels.fetch_models", fallback: "Fetch Models")
    }
    /// All
    internal static var channelsFilterAll: String {
      L10n.tr("Localizable", "settings.channels.filterAll", fallback: "All")
    }
    /// Disabled
    internal static var channelsFilterDisabled: String {
      L10n.tr("Localizable", "settings.channels.filterDisabled", fallback: "Disabled")
    }
    /// %lld/%lld
    internal static func channelsFilteredCount(_ p1: Int, _ p2: Int) -> String {
      return L10n.tr("Localizable", "settings.channels.filteredCount", p1, p2, fallback: "%lld/%lld")
    }
    /// Enabled
    internal static var channelsFilterEnabled: String {
      L10n.tr("Localizable", "settings.channels.filterEnabled", fallback: "Enabled")
    }
    /// Models
    internal static var channelsModels: String {
      L10n.tr("Localizable", "settings.channels.models", fallback: "Models")
    }
    /// Name
    internal static var channelsName: String {
      L10n.tr("Localizable", "settings.channels.name", fallback: "Name")
    }
    /// Try another search term or filter.
    internal static var channelsNoMatchesSubtitle: String {
      L10n.tr("Localizable", "settings.channels.noMatchesSubtitle", fallback: "Try another search term or filter.")
    }
    /// No matching channels
    internal static var channelsNoMatchesTitle: String {
      L10n.tr("Localizable", "settings.channels.noMatchesTitle", fallback: "No matching channels")
    }
    /// Priority
    internal static var channelsPriority: String {
      L10n.tr("Localizable", "settings.channels.priority", fallback: "Priority")
    }
    /// Protocol
    internal static var channelsProtocol: String {
      L10n.tr("Localizable", "settings.channels.protocol", fallback: "Protocol")
    }
    /// Clear search/filter to adjust priority
    internal static var channelsReorderFilteredHint: String {
      L10n.tr("Localizable", "settings.channels.reorderFilteredHint", fallback: "Clear search/filter to adjust priority")
    }
    /// Reorder: drag using ⠿ handle on left
    internal static var channelsReorderHint: String {
      L10n.tr("Localizable", "settings.channels.reorderHint", fallback: "Reorder: drag using ⠿ handle on left")
    }
    /// Search channels or models
    internal static var channelsSearchPlaceholder: String {
      L10n.tr("Localizable", "settings.channels.searchPlaceholder", fallback: "Search channels or models")
    }
    /// Sort by speed
    internal static var channelsSortBySpeed: String {
      L10n.tr("Localizable", "settings.channels.sortBySpeed", fallback: "Sort by speed")
    }
    /// Sort
    internal static var channelsSortBySpeedConfirm: String {
      L10n.tr("Localizable", "settings.channels.sortBySpeedConfirm", fallback: "Sort")
    }
    /// Channels with speed test results will be sorted from fastest to slowest. Channels without results will stay after measured channels. This changes routing priority.
    internal static var channelsSortBySpeedConfirmMessage: String {
      L10n.tr("Localizable", "settings.channels.sortBySpeedConfirmMessage", fallback: "Channels with speed test results will be sorted from fastest to slowest. Channels without results will stay after measured channels. This changes routing priority.")
    }
    /// Sort channels by speed?
    internal static var channelsSortBySpeedConfirmTitle: String {
      L10n.tr("Localizable", "settings.channels.sortBySpeedConfirmTitle", fallback: "Sort channels by speed?")
    }
    /// Manage providers, API keys, and model routing priority.
    internal static var channelsSubtitle: String {
      L10n.tr("Localizable", "settings.channels.subtitle", fallback: "Manage providers, API keys, and model routing priority.")
    }
    /// Test Connection
    internal static var channelsTestConnection: String {
      L10n.tr("Localizable", "settings.channels.test_connection", fallback: "Test Connection")
    }
    /// Test All
    internal static var channelsTestAll: String {
      L10n.tr("Localizable", "settings.channels.testAll", fallback: "Test All")
    }
    /// Testing...
    internal static var channelsTesting: String {
      L10n.tr("Localizable", "settings.channels.testing", fallback: "Testing...")
    }
    /// Auto-start at login
    internal static var generalAutoStart: String {
      L10n.tr("Localizable", "settings.general.auto_start", fallback: "Auto-start at login")
    }
    /// Dark mode
    internal static var generalDarkMode: String {
      L10n.tr("Localizable", "settings.general.dark_mode", fallback: "Dark mode")
    }
    /// Default Protocol
    internal static var generalDefaultProtocol: String {
      L10n.tr("Localizable", "settings.general.default_protocol", fallback: "Default Protocol")
    }
    /// Language
    internal static var generalLanguage: String {
      L10n.tr("Localizable", "settings.general.language", fallback: "Language")
    }
    /// Not configured
    internal static var generalNotConfigured: String {
      L10n.tr("Localizable", "settings.general.notConfigured", fallback: "Not configured")
    }
    /// Manage the local proxy, launch behavior, and developer tool integration.
    internal static var generalSubtitle: String {
      L10n.tr("Localizable", "settings.general.subtitle", fallback: "Manage the local proxy, launch behavior, and developer tool integration.")
    }
    /// Service running
    internal static var generalServiceRunning: String {
      L10n.tr("Localizable", "settings.general.serviceRunning", fallback: "Service running")
    }
    /// Proxy Service
    internal static var generalSectionProxy: String {
      L10n.tr("Localizable", "settings.general.section.proxy", fallback: "Proxy Service")
    }
    /// Local port the proxy service listens on
    internal static var generalPortHint: String {
      L10n.tr("Localizable", "settings.general.port.hint", fallback: "Local port the proxy service listens on")
    }
    /// Launch SmartLLMRouter automatically after signing in to macOS
    internal static var generalAutoStartHint: String {
      L10n.tr("Localizable", "settings.general.auto_start.hint", fallback: "Launch SmartLLMRouter automatically after signing in to macOS")
    }
    /// Developer Tools
    internal static var generalIntegrations: String {
      L10n.tr("Localizable", "settings.general.integrations", fallback: "Developer Tools")
    }
    /// Supports zsh, bash
    internal static var generalShellSupportHint: String {
      L10n.tr("Localizable", "settings.general.shell.supportHint", fallback: "Supports zsh, bash")
    }
    /// Configured
    internal static var generalShellConfiguredLabel: String {
      L10n.tr("Localizable", "settings.general.shell.configured", fallback: "Configured")
    }
    /// API keys are stored in the system Keychain; configuration changes apply only to this Mac.
    internal static var generalPrivacyHint: String {
      L10n.tr("Localizable", "settings.general.privacyHint", fallback: "API keys are stored in the system Keychain; configuration changes apply only to this Mac.")
    }
    /// Port
    internal static var generalPort: String {
      L10n.tr("Localizable", "settings.general.port", fallback: "Port")
    }
    /// Running on port %d
    internal static func generalRunningOnPort(_ p1: Int) -> String {
      return L10n.tr("Localizable", "settings.general.runningOnPort", p1, fallback: "Running on port %d")
    }
    /// Service
    internal static var generalService: String {
      L10n.tr("Localizable", "settings.general.service", fallback: "Service")
    }
    /// Service stopped
    internal static var generalServiceStopped: String {
      L10n.tr("Localizable", "settings.general.serviceStopped", fallback: "Service stopped")
    }
    /// Setup Shell Environment
    internal static var generalSetupShellEnv: String {
      L10n.tr("Localizable", "settings.general.setupShellEnv", fallback: "Setup Shell Environment")
    }
    /// Variables already added to ~/.zshenv
    internal static var generalShellConfigured: String {
      L10n.tr("Localizable", "settings.general.shellConfigured", fallback: "Variables already added to ~/.zshenv")
    }
    /// Shell Environment
    internal static var generalShellEnv: String {
      L10n.tr("Localizable", "settings.general.shellEnv", fallback: "Shell Environment")
    }
    /// Start Service
    internal static var generalStartService: String {
      L10n.tr("Localizable", "settings.general.startService", fallback: "Start Service")
    }
    /// Stop Service
    internal static var generalStopService: String {
      L10n.tr("Localizable", "settings.general.stopService", fallback: "Stop Service")
    }
    /// Update Shell Config
    internal static var generalUpdateShellConfig: String {
      L10n.tr("Localizable", "settings.general.updateShellConfig", fallback: "Update Shell Config")
    }
    /// 1897
    internal static var generalPortPlaceholder: String {
      L10n.tr("Localizable", "settings.general.port.placeholder", fallback: "1897")
    }
    /// Anthropic
    internal static var generalProtocolAnthropic: String {
      L10n.tr("Localizable", "settings.general.protocol.anthropic", fallback: "Anthropic")
    }
    /// Auto-detect
    internal static var generalProtocolAuto: String {
      L10n.tr("Localizable", "settings.general.protocol.auto", fallback: "Auto-detect")
    }
    /// OpenAI
    internal static var generalProtocolOpenai: String {
      L10n.tr("Localizable", "settings.general.protocol.openai", fallback: "OpenAI")
    }
    /// Channel Statistics
    internal static var usageChannelStats: String {
      L10n.tr("Localizable", "settings.usage.channelStats", fallback: "Channel Statistics")
    }
    /// 30-Day Usage
    internal static var usageChartTitle: String {
      L10n.tr("Localizable", "settings.usage.chartTitle", fallback: "30-Day Usage")
    }
    /// Clear History
    internal static var usageClearHistory: String {
      L10n.tr("Localizable", "settings.usage.clear_history", fallback: "Clear History")
    }
    /// Cost
    internal static var usageCost: String {
      L10n.tr("Localizable", "settings.usage.cost", fallback: "Cost")
    }
    /// Input Tokens
    internal static var usageInputTokens: String {
      L10n.tr("Localizable", "settings.usage.input_tokens", fallback: "Input Tokens")
    }
    /// No usage data yet
    internal static var usageNoData: String {
      L10n.tr("Localizable", "settings.usage.noData", fallback: "No usage data yet")
    }
    /// Output Tokens
    internal static var usageOutputTokens: String {
      L10n.tr("Localizable", "settings.usage.output_tokens", fallback: "Output Tokens")
    }
    /// Requests
    internal static var usageRequests: String {
      L10n.tr("Localizable", "settings.usage.requests", fallback: "Requests")
    }
    /// This Month
    internal static var usageThisMonth: String {
      L10n.tr("Localizable", "settings.usage.this_month", fallback: "This Month")
    }
    /// This Week
    internal static var usageThisWeek: String {
      L10n.tr("Localizable", "settings.usage.this_week", fallback: "This Week")
    }
    /// Today
    internal static var usageToday: String {
      L10n.tr("Localizable", "settings.usage.today", fallback: "Today")
    }
    /// Tokens
    internal static var usageTokens: String {
      L10n.tr("Localizable", "settings.usage.tokens", fallback: "Tokens")
    }
    /// Estimated Cost
    internal static var usageTotalCost: String {
      L10n.tr("Localizable", "settings.usage.total_cost", fallback: "Estimated Cost")
    }
    /// Total Requests
    internal static var usageTotalRequests: String {
      L10n.tr("Localizable", "settings.usage.total_requests", fallback: "Total Requests")
    }
    /// Total Tokens
    internal static var usageTotalTokens: String {
      L10n.tr("Localizable", "settings.usage.total_tokens", fallback: "Total Tokens")
    }
  }
  internal enum Status {
    /// Connected
    internal static var connected: String {
      L10n.tr("Localizable", "status.connected", fallback: "Connected")
    }
    /// Copied to clipboard
    internal static var copied: String {
      L10n.tr("Localizable", "status.copied", fallback: "Copied to clipboard")
    }
    /// Disconnected
    internal static var disconnected: String {
      L10n.tr("Localizable", "status.disconnected", fallback: "Disconnected")
    }
    /// Fetching models...
    internal static var fetchingModels: String {
      L10n.tr("Localizable", "status.fetching_models", fallback: "Fetching models...")
    }
    /// Models fetched successfully
    internal static var modelsFetched: String {
      L10n.tr("Localizable", "status.models_fetched", fallback: "Models fetched successfully")
    }
    /// Saved successfully
    internal static var saved: String {
      L10n.tr("Localizable", "status.saved", fallback: "Saved successfully")
    }
    /// Saving...
    internal static var saving: String {
      L10n.tr("Localizable", "status.saving", fallback: "Saving...")
    }
    /// Testing connection...
    internal static var testing: String {
      L10n.tr("Localizable", "status.testing", fallback: "Testing connection...")
    }
  }
}
// swiftlint:enable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:enable nesting type_body_length type_name vertical_whitespace_opening_braces

// MARK: - Implementation Details

extension L10n {
  private static func tr(_ table: String, _ key: String, _ args: CVarArg..., fallback value: String) -> String {
    let format = BundleToken.bundle.localizedString(forKey: key, value: value, table: table)
    return String(format: format, locale: Locale.current, arguments: args)
  }
}

// swiftlint:disable convenience_type
private final class BundleToken {
  static let bundle: Bundle = {
    #if SWIFT_PACKAGE
    return Bundle.module
    #else
    return Bundle(for: BundleToken.self)
    #endif
  }()
}
// swiftlint:enable convenience_type
