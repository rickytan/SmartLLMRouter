import Foundation

/// Global application state
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isProxyRunning: Bool = false
    @Published var port: Int = 1897
    @Published var autoFailover: Bool = true
    @Published var isLoading: Bool = false

    private init() {
        port = UserDefaults.standard.integer(forKey: "smartllm_port")
        if port <= 0 || port > 65535 {
            port = 1897
            UserDefaults.standard.set(port, forKey: "smartllm_port")
        }
        autoFailover = UserDefaults.standard.object(forKey: "smartllm_auto_failover") as? Bool ?? true
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
}
