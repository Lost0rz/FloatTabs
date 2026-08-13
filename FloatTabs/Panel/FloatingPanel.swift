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
            styleMask: [.borderless],
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

        // Showing FloatTabs is an explicit user request. Keep the shell
        // activating so AppKit can transfer both frontmost ownership and the
        // key-window chain to the separately hosted WKWebView.
        becomesKeyOnlyIfNeeded = false
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
