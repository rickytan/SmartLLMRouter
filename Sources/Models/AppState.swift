import Foundation

/// Global application state
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isProxyRunning: Bool = false
    @Published var port: Int = 1897
    @Published var autoFailover: Bool = true
    @Published var isLoading: Bool = false
    @Published var launchAtLogin: Bool = false
    @Published var onboardingCompleted: Bool = false

    init() {
        onboardingCompleted = UserDefaults.standard.bool(forKey: "smartllm_onboarding_completed")
        port = UserDefaults.standard.integer(forKey: "smartllm_port")
        if port <= 0 || port > 65535 {
            port = 1897
            UserDefaults.standard.set(port, forKey: "smartllm_port")
        }
        autoFailover = UserDefaults.standard.object(forKey: "smartllm_auto_failover") as? Bool ?? true
        launchAtLogin = UserDefaults.standard.object(forKey: "smartllm_launch_at_login") as? Bool ?? false
    }

    func completeOnboarding() {
        onboardingCompleted = true
        UserDefaults.standard.set(true, forKey: "smartllm_onboarding_completed")
    }

    func resetOnboarding() {
        onboardingCompleted = false
        UserDefaults.standard.set(false, forKey: "smartllm_onboarding_completed")
    }

    func savePort(_ newPort: Int) {
        guard newPort > 0, newPort <= 65535 else { return }
        port = newPort
        UserDefaults.standard.set(port, forKey: "smartllm_port")
    }

    func toggleAutoFailover() {
        autoFailover.toggle()
        UserDefaults.standard.set(autoFailover, forKey: "smartllm_auto_failover")
    }

    func toggleLaunchAtLogin() {
        launchAtLogin.toggle()
        UserDefaults.standard.set(launchAtLogin, forKey: "smartllm_launch_at_login")
        // TODO: Actually register with SMLoginItemSetEnabled
    }
}
