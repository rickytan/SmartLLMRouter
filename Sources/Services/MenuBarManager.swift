import AppKit
import SwiftUI

/// Manages the native macOS menu bar using NSStatusItem with a SwiftUI popover.
/// Uses MenuView as the popover content for rich UI.
@MainActor
final class MenuBarManager: NSObject {
    static let shared = MenuBarManager()

    /// Strong reference — this keeps the status item (and the app) alive
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var popoverHostingView: NSHostingView<MenuView>!

    private override init() {
        super.init()
        setup()
    }

    private func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = statusBarImage(isRunning: false)
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.target = self

        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 520)
        popover.behavior = .transient
        popover.animates = true

        // Create hosting view with MenuView
        popoverHostingView = NSHostingView(rootView: MenuView())
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = popoverHostingView
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    /// Show the popover (programmatically)
    func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    /// Update the menu bar icon based on proxy status
    func updateIcon(isRunning: Bool) {
        statusItem.button?.image = statusBarImage(isRunning: isRunning)
    }

    /// Refresh the popover content (called when state changes)
    func refreshPopoverContent() {
        popoverHostingView = NSHostingView(rootView: MenuView())
        popover.contentViewController?.view = popoverHostingView
    }

    /// Build menu - kept for compatibility but popover uses MenuView
    func buildMenu(isRunning: Bool, port: Int) {
        updateIcon(isRunning: isRunning)
        refreshPopoverContent()
    }

    private func statusBarImage(isRunning: Bool) -> NSImage? {
        let symbolCandidates = isRunning
            ? ["point.3.connected.trianglepath.dotted", "arrow.triangle.branch", "arrow.triangle.2.circlepath"]
            : ["point.3.filled.connected.trianglepath.dotted", "arrow.triangle.branch", "arrow.triangle.2.circlepath"]

        let image = symbolCandidates
            .compactMap { NSImage(systemSymbolName: $0, accessibilityDescription: "SmartLLMRouter") }
            .first

        image?.isTemplate = true
        return image
    }
}
