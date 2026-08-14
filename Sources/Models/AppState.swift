import Foundation
import ServiceManagement

enum LaunchAtLoginRegistrationStatus: Equatable {
    case disabled
    case enabled
    case requiresApproval
}

protocol LaunchAtLoginManaging: AnyObject {
    var status: LaunchAtLoginRegistrationStatus { get }
    func register() throws
    func unregister() throws
}

final class SystemLaunchAtLoginManager: LaunchAtLoginManaging {
    var status: LaunchAtLoginRegistrationStatus {
        switch SMAppService.mainApp.status {
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notRegistered, .notFound:
            .disabled
        @unknown default:
            .disabled
        }
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}

/// Global application state
@MainActor
final class AppState: ObservableObject {
    @Published var isProxyRunning: Bool = false
    @Published var port: Int = 1897
    @Published var isLoading: Bool = false
    @Published private(set) var launchAtLogin: Bool = false
    @Published private(set) var launchAtLoginRequiresApproval: Bool = false
    @Published private(set) var launchAtLoginError: String?
    @Published var onboardingCompleted: Bool = false
    @Published var showTokenSpeed: Bool = false {
        didSet {
            defaults.set(showTokenSpeed, forKey: "smartllm_show_token_speed")
        }
    }

    private let defaults: UserDefaults
    private let launchAtLoginManager: LaunchAtLoginManaging

    init(
        defaults: UserDefaults = .standard,
        launchAtLoginManager: LaunchAtLoginManaging = SystemLaunchAtLoginManager()
    ) {
        self.defaults = defaults
        self.launchAtLoginManager = launchAtLoginManager
        onboardingCompleted = defaults.bool(forKey: "smartllm_onboarding_completed")
        port = defaults.integer(forKey: "smartllm_port")
        if port <= 0 || port > 65535 {
            port = 1897
            defaults.set(port, forKey: "smartllm_port")
        }
        showTokenSpeed = defaults.object(forKey: "smartllm_show_token_speed") as? Bool ?? false
        refreshLaunchAtLoginStatus()
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

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            if enabled {
                try launchAtLoginManager.register()
            } else {
                try launchAtLoginManager.unregister()
            }
        } catch {
            launchAtLoginError = error.localizedDescription
            Log.error("Failed to update launch at login: \(error.localizedDescription)")
        }
        refreshLaunchAtLoginStatus()
    }

    func refreshLaunchAtLoginStatus() {
        let status = launchAtLoginManager.status
        launchAtLogin = status != .disabled
        launchAtLoginRequiresApproval = status == .requiresApproval
    }
}
