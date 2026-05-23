import SwiftUI
import Sparkle

@main
struct SmartLLMRouterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Settings window
        Settings {
            SettingsView()
        }

        // Onboarding window (hidden until opened)
        Window(L10n.Onboarding.title, id: "onboarding") {
            OnboardingView(onComplete: {
                AppState.shared.completeOnboarding()
                Self.closeOnboardingWindow()
                // Show menu bar popover once on first launch
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    MenuBarManager.shared.showPopover()
                }
            })
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
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

    @MainActor
    func applicationDidFinishLaunching(_: Notification) {
        // Set accessory policy: no Dock icon, stays alive without windows
        NSApp.setActivationPolicy(.accessory)

        // Initialize logger
        LoggerManager.setup()

        // Setup menu bar using native NSStatusItem (reliable on macOS 13)
        // The strong reference to statusItem keeps the app alive after all windows close
        MenuBarManager.shared.updateIcon(isRunning: false)
        MenuBarManager.shared.buildMenu(isRunning: false, port: AppState.shared.port)

        // Start proxy server
        startProxy()

        // Show onboarding if not completed
        if !AppState.shared.onboardingCompleted {
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "onboarding" }) {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }

        // Sparkle is already started via lazy property above
        _ = updaterController
    }

    // Prevent app from quitting when all windows are closed
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    @MainActor
    private func startProxy() {
        guard !ProxyServer.shared.isRunning else { return }
        let port = AppState.shared.port
        ProxyServer.shared.start(port: port)
        Log.info("Proxy server started on port \(port)")
        MenuBarManager.shared.updateIcon(isRunning: true)
        MenuBarManager.shared.buildMenu(isRunning: true, port: port)
    }
}
