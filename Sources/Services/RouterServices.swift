import Foundation

/// Dependency boundary for routing and proxy runtime services.
///
/// This groups the runtime state and adjacent services used by proxy request
/// handling so routing code does not directly reach into unrelated singletons.
@MainActor
final class RouterServices {
    static let shared = RouterServices()

    let runtimeState: RouterRuntimeState
    let modelOverrideState: ModelOverrideRuntimeState
    let circuitBreaker: CircuitBreaker
    let switchLock: SwitchLock
    let modelAggregator: ModelAggregator
    let modelSwitcher: ModelSwitcher
    let usageTracker: UsageTracker

    private init() {
        runtimeState = .shared
        modelOverrideState = .shared
        circuitBreaker = .shared
        switchLock = .shared
        modelAggregator = .shared
        modelSwitcher = .shared
        usageTracker = .shared
    }

    var channelServices: ChannelServices {
        .shared
    }
}
