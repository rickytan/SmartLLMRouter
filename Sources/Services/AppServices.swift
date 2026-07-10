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
    lazy var menuBarManager: MenuBarManager = MenuBarManager(services: self)

    convenience init() {
        self.init(
            appState: AppState(),
            keychainManager: KeychainManager(),
            usageTracker: UsageTracker(),
            circuitBreaker: CircuitBreaker(),
            switchLock: SwitchLock(),
            shellConfigManager: ShellConfigManager(),
            claudeCodeConfigManager: ClaudeCodeConfigManager()
        )
    }

    init(
        appState: AppState,
        keychainManager: KeychainManager,
        usageTracker: UsageTracker,
        circuitBreaker: CircuitBreaker,
        switchLock: SwitchLock,
        shellConfigManager: ShellConfigManager,
        claudeCodeConfigManager: ClaudeCodeConfigManager,
        channelExportService: ChannelExportService? = nil
    ) {
        self.appState = appState
        self.usageTracker = usageTracker
        self.circuitBreaker = circuitBreaker
        self.shellConfigManager = shellConfigManager
        self.claudeCodeConfigManager = claudeCodeConfigManager

        let runtimeState = RouterRuntimeState(
            circuitBreaker: circuitBreaker,
            switchLock: switchLock
        )
        let apiKeyAvailabilityStore = APIKeyAvailabilityStore()
        let modelOverrideState = ModelOverrideRuntimeState()
        let store = ChannelStore(runtimeState: runtimeState)
        let cooldownEngine = CooldownEngine(channelStore: store)
        let channels = ChannelServices(
            store: store,
            keychain: keychainManager,
            cooldownEngine: cooldownEngine
        )
        let aggregator = ModelAggregator(channelServices: channels)
        let switcher = ModelSwitcher(
            channelServices: channels,
            modelOverrideState: modelOverrideState
        )
        store.invalidateModelCache = { aggregator.invalidateCache() }
        store.validateModelSelection = { switcher.validateSelection() }

        let routing = RouterServices(
            channelServices: channels,
            runtimeState: runtimeState,
            modelOverrideState: modelOverrideState,
            circuitBreaker: circuitBreaker,
            switchLock: switchLock,
            apiKeyAvailabilityStore: apiKeyAvailabilityStore,
            modelAggregator: aggregator,
            modelSwitcher: switcher,
            usageTracker: usageTracker
        )

        channelStore = store
        channelServices = channels
        self.channelExportService = channelExportService ?? ChannelExportService(channelServices: channels)
        modelSwitcher = switcher
        channelManager = ChannelManager(channelServices: channels)
        routerServices = routing
        smartRouter = SmartRouter(services: routing)
        proxyServer = ProxyServer(services: routing)
    }
}
