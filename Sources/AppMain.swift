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
                // macOS 13-safe: find and close the onboarding window by its scene identifier
                Self.closeOnboardingWindow()
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

    /// macOS 13-safe window close: find the onboarding window by scene identifier and close it.
    /// Uses `NSApp.windows` instead of the deprecated `NSApplication.shared.windows`.
    private static func closeOnboardingWindow() {
        NSApp.windows.first { $0.identifier?.rawValue == "onboarding" }?.close()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    // Sparkle updater controller — starts automatically and handles background checks
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

        // Initialize logger only — proxy starts from MenuBarExtra.onAppear
        LoggerManager.setup()

        // Sparkle is already started via lazy property above
        // It will automatically check for updates based on the feed URL in Info.plist
        _ = updaterController
    }
}
