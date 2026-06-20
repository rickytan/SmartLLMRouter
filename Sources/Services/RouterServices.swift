import Foundation

/// Dependency boundary for routing and proxy runtime services.
///
/// This groups the runtime state and adjacent services used by proxy request
/// handling so routing code does not directly reach into unrelated singletons.
@MainActor
final class RouterServices {
    static let shared: RouterServices = {
        let channelServices = ChannelServices.shared
        let modelOverrideState = ModelOverrideRuntimeState.shared
        return RouterServices(
            channelServices: channelServices,
            runtimeState: .shared,
            modelOverrideState: modelOverrideState,
            circuitBreaker: .shared,
            switchLock: .shared,
            modelAggregator: ModelAggregator.shared,
            modelSwitcher: ModelSwitcher(
                channelServices: channelServices,
                modelOverrideState: modelOverrideState
            ),
            usageTracker: .shared
        )
    }()

    let channelServices: ChannelServices
    let runtimeState: RouterRuntimeState
    let modelOverrideState: ModelOverrideRuntimeState
    let circuitBreaker: CircuitBreaker
    let switchLock: SwitchLock
    let modelAggregator: ModelAggregator
    let modelSwitcher: ModelSwitcher
    let usageTracker: UsageTracker

    init(
        channelServices: ChannelServices,
        runtimeState: RouterRuntimeState = .shared,
        modelOverrideState: ModelOverrideRuntimeState = .shared,
        circuitBreaker: CircuitBreaker = .shared,
        switchLock: SwitchLock = .shared,
        modelAggregator: ModelAggregator,
        modelSwitcher: ModelSwitcher,
        usageTracker: UsageTracker = .shared
    ) {
        self.channelServices = channelServices
        self.runtimeState = runtimeState
        self.modelOverrideState = modelOverrideState
        self.circuitBreaker = circuitBreaker
        self.switchLock = switchLock
        self.modelAggregator = modelAggregator
        self.modelSwitcher = modelSwitcher
        self.usageTracker = usageTracker
    }
}
