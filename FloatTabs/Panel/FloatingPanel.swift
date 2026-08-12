import AppKit

enum FloatTabsWindowLevel {
    static func presentation(isPinned: Bool) -> NSWindow.Level {
        isPinned ? .floating : .normal
    }
}

final class FloatingPanel: NSPanel {
    private static let ordinaryCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .canJoinAllApplications,
        .ignoresCycle,
    ]

    private static let fullscreenCompanionCollectionBehavior: NSWindow.CollectionBehavior = [
        .moveToActiveSpace,
        .fullScreenAuxiliary,
        .ignoresCycle,
    ]

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
        // Experiment: keep the shell and the ordinary Web source host at the
        // same normal level so the source host can be ordered above the shell.
        // The shell remains a separate NSPanel and keeps its cross-Space flags.
        level = .normal
        collectionBehavior = Self.ordinaryCollectionBehavior

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

    func setFullscreenCompanionPresentation(_ enabled: Bool) {
        collectionBehavior = enabled
            ? Self.fullscreenCompanionCollectionBehavior
            : Self.ordinaryCollectionBehavior
    }

    func setPinnedPresentation(_ isPinned: Bool) {
        level = FloatTabsWindowLevel.presentation(isPinned: isPinned)
    }
}
