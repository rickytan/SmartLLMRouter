import AppKit
import SwiftUI

/// Manages the native macOS menu bar using NSStatusItem with a SwiftUI popover.
/// Uses MenuView as the popover content for rich UI.
@MainActor
final class MenuBarManager: NSObject {
    private let services: AppServices

    /// Strong reference — this keeps the status item (and the app) alive
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var popoverHostingView: NSHostingView<MenuView>!
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var closePopoverObserver: NSObjectProtocol?

    init(services: AppServices) {
        self.services = services
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
        popoverHostingView = NSHostingView(rootView: MenuView(services: services))
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = popoverHostingView

        closePopoverObserver = NotificationCenter.default.addObserver(
            forName: .closeMenuBarPopover,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.closePopover()
            }
        }
    }

    deinit {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }

        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
        }

        if let closePopoverObserver {
            NotificationCenter.default.removeObserver(closePopoverObserver)
        }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    /// Show the popover (programmatically)
    func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        installEventMonitors()
    }

    /// Update the menu bar icon based on proxy status
    func updateIcon(isRunning: Bool) {
        statusItem.button?.image = statusBarImage(isRunning: isRunning)
    }

    /// Refresh the popover content (called when state changes)
    func refreshPopoverContent() {
        popoverHostingView = NSHostingView(rootView: MenuView(services: services))
        popover.contentViewController?.view = popoverHostingView
    }

    /// Build menu - kept for compatibility but popover uses MenuView
    func buildMenu(isRunning: Bool, port: Int) {
        updateIcon(isRunning: isRunning)
        refreshPopoverContent()
    }

    private func installEventMonitors() {
        removeEventMonitors()

        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.closePopoverIfClickIsOutside(event)
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            Task { @MainActor in
                self?.closePopover()
            }
        }
    }

    private func removeEventMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }

        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }

    private func closePopoverIfClickIsOutside(_ event: NSEvent) {
        guard popover.isShown else {
            removeEventMonitors()
            return
        }

        if event.window === popover.contentViewController?.view.window {
            return
        }

        closePopover()
    }

    private func closePopover() {
        guard popover.isShown else {
            removeEventMonitors()
            return
        }

        popover.performClose(nil)
        removeEventMonitors()
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

extension Notification.Name {
    static let closeMenuBarPopover = Notification.Name("SmartLLMRouter.closeMenuBarPopover")
}
