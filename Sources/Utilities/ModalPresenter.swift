import SwiftUI
import AppKit

// MARK: - ModalPresenter

/// macOS-only utility to present a SwiftUI view as a native modal sheet via NSWindow.
/// Works even when the parent view is already presented as a sheet (unlike SwiftUI .sheet).
enum ModalPresenter {

    /// Present a SwiftUI view as a native NSWindow sheet attached to the key window.
    /// - Parameters:
    ///   - content: The SwiftUI view to present.
    ///   - size: The window content size.
    ///   - title: Optional window title (hidden by default for sheet-style).
    ///   - onDismiss: Called when the window closes.
    static func presentSheet<Content: View>(
        content: Content,
        size: CGSize = CGSize(width: 360, height: 320),
        title: String = "",
        onDismiss: @escaping () -> Void = {}
    ) {
        guard let parentWindow = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) else {
            return
        }

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
        panel.isReleasedWhenClosed = false
        panel.center()

        // Store reference to prevent premature deallocation
        _activePanel = panel

        parentWindow.beginSheet(panel) { _ in
            _activePanel = nil
            onDismiss()
        }
    }

    /// Dismiss the currently active modal sheet.
    static func dismissSheet() {
        guard let panel = _activePanel, let parentWindow = panel.sheetParent else { return }
        parentWindow.endSheet(panel)
        _activePanel = nil
    }

    // Strong reference to keep the panel alive
    private static var _activePanel: NSPanel?
}
