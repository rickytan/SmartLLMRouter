import SwiftUI
import AppKit

// MARK: - ModalPresenter

/// macOS-only utility to present a SwiftUI view as a native modal sheet via NSWindow.
/// Works even when the parent view is already presented as a sheet (unlike SwiftUI .sheet).
enum ModalPresenter {

    /// Present a SwiftUI view as a native NSWindow sheet attached to the key window.
    static func presentSheet<Content: View>(
        content: Content,
        size: CGSize = CGSize(width: 360, height: 320),
        title: String = "",
        onDismiss: @escaping () -> Void = {}
    ) {
        guard let parentWindow = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) else {
            return
        }

        // Dismiss any existing sheet first
        dismissSheet()

        let hostingController = NSHostingController(rootView: content)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.contentViewController = hostingController
        panel.isReleasedWhenClosed = true
        panel.center()

        // Store reference to prevent premature deallocation
        _activePanel = panel
        _onDismiss = onDismiss

        // Set delegate to detect close via X button
        let delegate = PanelDelegate()
        panel.delegate = delegate
        _delegate = delegate

        parentWindow.beginSheet(panel) { _ in
            cleanup()
        }
    }

    /// Dismiss the currently active modal sheet.
    static func dismissSheet() {
        guard let panel = _activePanel, let parentWindow = panel.sheetParent else {
            // Panel may have been closed by X button; just clean up
            cleanup()
            return
        }
        parentWindow.endSheet(panel)
    }

    // MARK: - Private

    private static var _activePanel: NSPanel?
    private static var _onDismiss: (() -> Void)?
    private static var _delegate: PanelDelegate?

    private static func cleanup() {
        _activePanel?.delegate = nil
        _activePanel = nil
        _delegate = nil
        let dismiss = _onDismiss
        _onDismiss = nil
        dismiss?()
    }

    /// Delegate to detect when panel is closed via X button
    private class PanelDelegate: NSObject, NSWindowDelegate {
        func windowWillClose(_ notification: Notification) {
            // Panel closed by user (X button) — clean up immediately
            ModalPresenter.dismissSheet()
        }
    }
}
