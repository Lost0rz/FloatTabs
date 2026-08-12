import AppKit

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [
            .canJoinAllSpaces,
            .canJoinAllApplications,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]

        // A non-activating panel can receive the first pointer interaction while
        // another application is frontmost. The explicit show path still calls
        // NSApp.activate() before focusing the active WKWebView, so keyboard input
        // keeps the accepted Stage 0 behavior.
        becomesKeyOnlyIfNeeded = true
        acceptsMouseMovedEvents = true

        // The native resizable style is intentionally disabled. Stage 2 owns a
        // single bottom-right resize handle so edge movement and resizing cannot
        // compete for the same pointer hit.
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovableByWindowBackground = false

        contentMinSize = PanelMetrics.minimumPanelSize
        minSize = PanelMetrics.minimumPanelSize
    }

    override func sendEvent(_ event: NSEvent) {
        FullscreenDiagnostics.shared.recordPanelInput(event: event, panel: self)
        super.sendEvent(event)
    }
}
