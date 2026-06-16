import Foundation

/// Central dependency container for app-level services.
///
/// This is a transition layer: services can still expose their existing
/// singletons while UI and app entry points move to one explicit dependency
/// source.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let appState: AppState
    let proxyServer: ProxyServer
    let channelServices: ChannelServices
    let routerServices: RouterServices
    let channelStore: ChannelStore
    let channelManager: ChannelManager
    let modelSwitcher: ModelSwitcher
    let usageTracker: UsageTracker
    let smartRouter: SmartRouter
    let circuitBreaker: CircuitBreaker
    let channelExportService: ChannelExportService
    let shellConfigManager: ShellConfigManager
    let claudeCodeConfigManager: ClaudeCodeConfigManager
    lazy var menuBarManager: MenuBarManager = .shared

    private init() {
        appState = .shared
        proxyServer = .shared
        channelServices = .shared
        routerServices = .shared
        channelStore = .shared
        channelManager = .shared
        modelSwitcher = .shared
        usageTracker = .shared
        smartRouter = .shared
        circuitBreaker = .shared
        channelExportService = .shared
        shellConfigManager = .shared
        claudeCodeConfigManager = .shared
    }
}
