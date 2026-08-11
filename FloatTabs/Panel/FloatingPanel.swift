import AppKit

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private(set) var isPresentationPinned = false

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
        level = .normal
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

    /// Pin is a presentation policy, not just an auto-hide flag. An unpinned
    /// FloatTabs window should yield to WebKit's own full-screen presentation,
    /// while a pinned panel deliberately stays above other application content.
    func setPresentationPinned(_ pinned: Bool) {
        let targetLevel: NSWindow.Level = pinned ? .floating : .normal
        guard isPresentationPinned != pinned || level != targetLevel else { return }
        isPresentationPinned = pinned
        level = targetLevel
    }

    /// WebKit's macOS element-fullscreen controller currently chooses
    /// `NSScreen.main`, which is the screen containing the window with keyboard
    /// focus. FloatTabs is a non-activating panel, so the previously focused
    /// display can otherwise leak into the full-screen decision. Anchor keyboard
    /// focus to this panel before dispatching a mouse-down into web content.
    override func sendEvent(_ event: NSEvent) {
        if Self.shouldAnchorKeyboardFocus(
            eventType: event.type,
            isKeyWindow: isKeyWindow
        ) {
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                _ = NSRunningApplication.current.activate(options: [])
            }
            makeKey()
        }

        super.sendEvent(event)

        // PanelController is the single owner of Pin state. Synchronize after the
        // event so both the rail button and the keyboard command update window
        // level without introducing a second Pin state machine.
        if let panelController = delegate as? PanelController {
            setPresentationPinned(panelController.isPinned)
        }
    }

    static func shouldAnchorKeyboardFocus(
        eventType: NSEvent.EventType,
        isKeyWindow: Bool
    ) -> Bool {
        guard !isKeyWindow else { return false }
        switch eventType {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return true
        default:
            return false
        }
    }
}
