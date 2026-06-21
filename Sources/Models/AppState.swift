import Foundation

/// Global application state
@MainActor
final class AppState: ObservableObject {
    @Published var isProxyRunning: Bool = false
    @Published var port: Int = 1897
    @Published var autoFailover: Bool = true
    @Published var isLoading: Bool = false
    @Published var launchAtLogin: Bool = false
    @Published var onboardingCompleted: Bool = false

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        onboardingCompleted = defaults.bool(forKey: "smartllm_onboarding_completed")
        port = defaults.integer(forKey: "smartllm_port")
        if port <= 0 || port > 65535 {
            port = 1897
            defaults.set(port, forKey: "smartllm_port")
        }
        autoFailover = defaults.object(forKey: "smartllm_auto_failover") as? Bool ?? true
        launchAtLogin = defaults.object(forKey: "smartllm_launch_at_login") as? Bool ?? false
    }

    func completeOnboarding() {
        onboardingCompleted = true
        defaults.set(true, forKey: "smartllm_onboarding_completed")
    }

    func resetOnboarding() {
        onboardingCompleted = false
        defaults.set(false, forKey: "smartllm_onboarding_completed")
    }

    func savePort(_ newPort: Int) {
        guard newPort > 0, newPort <= 65535 else { return }
        port = newPort
        defaults.set(port, forKey: "smartllm_port")
    }

    func toggleAutoFailover() {
        autoFailover.toggle()
        defaults.set(autoFailover, forKey: "smartllm_auto_failover")
    }

    func toggleLaunchAtLogin() {
        launchAtLogin.toggle()
        defaults.set(launchAtLogin, forKey: "smartllm_launch_at_login")
        // TODO: Actually register with SMLoginItemSetEnabled
    }
}
