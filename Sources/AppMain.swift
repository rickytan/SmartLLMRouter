import SwiftUI
import Sparkle

@main
struct SmartLLMRouterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings scene — provides the standard macOS settings window with
        // proper tab bar layout. Shown via NSApp.sendAction("showSettingsWindow:")
        Settings {
            SettingsView()
        }
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

    private var onboardingWindow: NSWindow?

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

        // Show onboarding if not completed — via NSWindow, no SwiftUI Window scene
        if !AppState.shared.onboardingCompleted {
            showOnboardingWindow()
        }

        // Sparkle is already started via lazy property above
        _ = updaterController
    }

    // Prevent app from quitting when all windows are closed
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    @MainActor
    private func showOnboardingWindow() {
        let hostingView = NSHostingView(rootView: OnboardingView(onComplete: { [weak self] in
            Task { @MainActor in
                AppState.shared.completeOnboarding()
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    MenuBarManager.shared.showPopover()
                }
            }
        }))

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = L10n.Onboarding.title
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.center()

        // Activate app to bring window to front
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        onboardingWindow = window
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
