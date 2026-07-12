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
    @MainActor private let services = AppServices.shared

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
        // Initialize logger
        LoggerManager.setup()

        // Setup menu bar using native NSStatusItem (reliable on macOS 13)
        // The strong reference to statusItem keeps the app alive after all windows close
        services.menuBarManager.updateIcon(isRunning: false)
        services.menuBarManager.buildMenu(isRunning: false, port: services.appState.port)

        // Start proxy server
        startProxy()

        // Show onboarding if not completed — via NSWindow, no SwiftUI Window scene
        if !services.appState.onboardingCompleted {
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
                self?.services.appState.completeOnboarding()
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.services.menuBarManager.showPopover()
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

        // Bring onboarding to the front while preserving LSUIElement menu-bar mode.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        onboardingWindow = window
    }

    @MainActor
    private func startProxy() {
        guard !services.proxyServer.isRunning else { return }
        let port = services.appState.port
        if services.proxyServer.start(port: port) {
            Log.info("Proxy server started on port \(port)")
            services.menuBarManager.updateIcon(isRunning: true)
            services.menuBarManager.buildMenu(isRunning: true, port: port)
        } else {
            Log.error("Proxy server is not running on port \(port): \(services.proxyServer.lastError ?? "unknown error")")
            services.menuBarManager.updateIcon(isRunning: false)
            services.menuBarManager.buildMenu(isRunning: false, port: port)
        }
    }
}
