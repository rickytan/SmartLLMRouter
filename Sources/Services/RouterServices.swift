import Foundation

/// Dependency boundary for routing and proxy runtime services.
///
/// This groups the runtime state and adjacent services used by proxy request
/// handling so routing code does not directly reach into unrelated singletons.
@MainActor
final class RouterServices {
    let channelServices: ChannelServices
    let runtimeState: RouterRuntimeState
    let modelOverrideState: ModelOverrideRuntimeState
    let circuitBreaker: CircuitBreaker
    let switchLock: SwitchLock
    let apiKeyAvailabilityStore: APIKeyAvailabilityStore
    let modelAggregator: ModelAggregator
    let modelSwitcher: ModelSwitcher
    let usageTracker: UsageTracker

    init(
        channelServices: ChannelServices,
        runtimeState: RouterRuntimeState,
        modelOverrideState: ModelOverrideRuntimeState,
        circuitBreaker: CircuitBreaker,
        switchLock: SwitchLock,
        apiKeyAvailabilityStore: APIKeyAvailabilityStore,
        modelAggregator: ModelAggregator,
        modelSwitcher: ModelSwitcher,
        usageTracker: UsageTracker
    ) {
        self.channelServices = channelServices
        self.runtimeState = runtimeState
        self.modelOverrideState = modelOverrideState
        self.circuitBreaker = circuitBreaker
        self.switchLock = switchLock
        self.apiKeyAvailabilityStore = apiKeyAvailabilityStore
        self.modelAggregator = modelAggregator
        self.modelSwitcher = modelSwitcher
        self.usageTracker = usageTracker

        let cooldownEngine = channelServices.cooldownEngine
        apiKeyAvailabilityStore.setChannelRateLimitHandler { [weak runtimeState, weak cooldownEngine] channelID, until in
            runtimeState?.markChannelRateLimited(channelID: channelID, until: until)
            Task { @MainActor [weak cooldownEngine] in
                cooldownEngine?.startCooldown(
                    channelID: channelID,
                    until: until,
                    reason: "429: all API keys rate-limited"
                )
            }
        }
    }
}
