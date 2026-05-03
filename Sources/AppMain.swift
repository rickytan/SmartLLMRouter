import SwiftUI

@main
struct SmartLLMRouterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var proxy = ProxyServer.shared
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var channelStore = ChannelStore.shared
    @Environment(\.openWindow) private var openWindow

    @State private var onboardingShown = false

    var body: some Scene {
        // Settings window
        Settings {
            SettingsView()
        }

        // Onboarding window (hidden until opened)
        Window(L10n.Onboarding.title, id: "onboarding") {
            OnboardingView(onComplete: {
                appState.completeOnboarding()
                // On macOS 13, we close by having the view dismiss itself
                NSApplication.shared.windows.first { $0.identifier?.rawValue == "onboarding" }?.close()
            })
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        // Menu Bar Extra
        MenuBarExtra {
            MenuView()
                .onAppear {
                    autoStartProxy()
                    if !appState.onboardingCompleted {
                        openWindow(id: "onboarding")
                    }
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
