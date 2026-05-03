import SwiftUI
import Sparkle

@main
struct SmartLLMRouterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var proxy = ProxyServer.shared
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var channelStore = ChannelStore.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Settings window
        Settings {
            SettingsView()
        }

        // Onboarding window (hidden until opened)
        Window(L10n.Onboarding.title, id: "onboarding") {
            OnboardingView(onComplete: {
                appState.completeOnboarding()
                Self.closeOnboardingWindow()
            })
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        // Menu Bar Extra - default .menu style works on macOS 13+
        MenuBarExtra {
            MenuView()
                .onAppear {
                    autoStartProxy()
                    if !appState.onboardingCompleted {
                        openWindow(id: "onboarding")
                    }
                }
        } label: {
            Image(systemName: proxy.isRunning ? "network" : "wifi.slash")
        }
    }

    private func autoStartProxy() {
        guard !proxy.isRunning else { return }
        proxy.start(port: appState.port)
    }

    /// macOS 13-safe window close: find the onboarding window by scene identifier and close it.
    private static func closeOnboardingWindow() {
        NSApp.windows.first { $0.identifier?.rawValue == "onboarding" }?.close()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var updaterController: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }()

    func applicationDidFinishLaunching(_: Notification) {
        // Set accessory policy: no Dock icon, stays alive without windows
        NSApp.setActivationPolicy(.accessory)

        // Initialize logger
        LoggerManager.setup()

        // Start proxy server immediately
        Task { @MainActor in
            guard !ProxyServer.shared.isRunning else { return }
            ProxyServer.shared.start(port: AppState.shared.port)
            Log.info("Proxy server started on port \(AppState.shared.port)")
        }

        // Show onboarding if not completed
        if !AppState.shared.onboardingCompleted {
            Task { @MainActor in
                // Small delay to ensure windows are ready
                try? await Task.sleep(nanoseconds: 500_000_000)
                if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "onboarding" }) {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }

        // Sparkle is already started via lazy property above
        _ = updaterController
    }
}
