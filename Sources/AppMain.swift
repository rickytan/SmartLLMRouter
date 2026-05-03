import SwiftUI

@main
struct SmartLLMRouterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var proxy = ProxyServer.shared
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var channelStore = ChannelStore.shared

    var body: some Scene {
        // Settings window
        Settings {
            SettingsView()
        }

        // Menu Bar Extra
        MenuBarExtra {
            MenuView()
                .onAppear {
                    autoStartProxy()
                }
        } label: {
            Image(systemName: proxy.isRunning ? "network" : "network.slash")
        }
        .menuBarExtraStyle(.window)
    }

    private func autoStartProxy() {
        guard !proxy.isRunning else { return }
        proxy.start(port: appState.port)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        // Initialize logger
        LoggerManager.setup()

        // Ensure proxy starts
        Task { @MainActor in
            ProxyServer.shared.start(port: AppState.shared.port)
        }
    }
}
