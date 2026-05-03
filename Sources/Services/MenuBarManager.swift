import AppKit

/// Manages the native macOS menu bar using NSStatusItem (AppKit).
/// More reliable than SwiftUI's MenuBarExtra on macOS 13.
/// The statusItem is a strong property that keeps the app alive even when all windows are closed.
@MainActor
final class MenuBarManager: NSObject {
    static let shared = MenuBarManager()

    /// Strong reference — this keeps the status item (and the app) alive
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    private override init() {
        super.init()
        setup()
    }

    private func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "network.slash", accessibilityDescription: "SmartLLMRouter")
        statusItem.highlightMode = true

        menu = NSMenu()
        statusItem.menu = menu
    }

    /// Update the menu bar icon based on proxy status
    func updateIcon(isRunning: Bool) {
        let imageName = isRunning ? "network" : "network.slash"
        statusItem.button?.image = NSImage(systemSymbolName: imageName, accessibilityDescription: "SmartLLMRouter")
    }

    /// Build a complete menu with items
    func buildMenu(isRunning: Bool, port: Int) {
        menu.removeAllItems()

        // Status
        let statusItem = NSMenuItem()
        statusItem.title = isRunning ? "● Running" : "○ Stopped"
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        let portItem = NSMenuItem()
        portItem.title = "Port: \(port)"
        portItem.isEnabled = false
        menu.addItem(portItem)

        menu.addItem(NSMenuItem.separator())

        // Copy Env
        let copyItem = NSMenuItem(title: "📋 Copy Env Variables", action: #selector(copyEnv), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)

        // Settings
        let settingsItem = NSMenuItem(title: "⚙️ Settings...", action: #selector(showSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func copyEnv() {
        let port = ProxyServer.shared.port
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            "export OPENAI_BASE_URL=http://localhost:\(port)/v1\nexport ANTHROPIC_BASE_URL=http://localhost:\(port)/v1",
            forType: .string
        )
    }

    @objc private func showSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
