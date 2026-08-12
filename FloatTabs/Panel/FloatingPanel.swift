import AppKit
import Foundation
import WebKit

@MainActor
enum FloatTabsFullscreenPresentation {
    /// True while the FloatTabs page currently observed by the panel is in any
    /// WebKit element-fullscreen transition.
    static var isActive = false

    /// Tracks only an explicit user summon of the shell during own fullscreen.
    /// `NSWindow.isVisible` is not reliable enough across Spaces to implement the
    /// fullscreen shortcut as a toggle by itself.
    static var shellExplicitlySummoned = false
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private(set) var isPresentationPinned = false
    private weak var fullscreenObservedWebView: WKWebView?
    private var fullscreenStateObservation: NSKeyValueObservation?
    private var ownElementFullscreenState: WKWebView.FullscreenState = .notInFullscreen

    // Shell presentation is independent from WebKit's fullscreen presentation.
    private var explicitFullscreenOverlay = false
    private var shellAutoSuppressedForOwnFullscreen = false
    private var restoreShellWorkItem: DispatchWorkItem?

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
        collectionBehavior = Self.presentationCollectionBehavior(
            isPinned: false,
            fullscreenState: .notInFullscreen,
            explicitFullscreenOverlay: false
        )

        // A non-activating panel is allowed to become key without activating the
        // owning app. Let every real click establish this panel as the key window
        // instead of relying on `needsPanelToBecomeKey` from the hit subview.
        becomesKeyOnlyIfNeeded = false
        acceptsMouseMovedEvents = true

        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovableByWindowBackground = false

        contentMinSize = PanelMetrics.minimumPanelSize
        minSize = PanelMetrics.minimumPanelSize
    }

    var isOwnElementFullscreenActive: Bool {
        WebViewPool.isActiveFullscreenState(ownElementFullscreenState)
    }

    func setPresentationPinned(_ pinned: Bool) {
        guard isPresentationPinned != pinned else { return }
        isPresentationPinned = pinned
        FloatTabsDiagnostics.record(
            "shell_pin_changed",
            fields: ["pinned": String(pinned)]
        )
        applyPresentationPolicy()
        synchronizeShellVisibilityForFullscreen()
    }

    /// During WebKit enter/exit transitions the shell must not take key status.
    /// For a deliberate summon while native element fullscreen is stable, order
    /// the auxiliary shell without making it key. This keeps the fullscreen
    /// owner in control of its native Space; a later real click may make the
    /// non-activating panel key through normal AppKit interaction.
    override func makeKeyAndOrderFront(_ sender: Any?) {
        if Self.shouldDeferKeyAndOrderFront(fullscreenState: ownElementFullscreenState) {
            FloatTabsDiagnostics.record(
                "fullscreen_shell_show_deferred_during_transition",
                fields: [
                    "panel_window_number": String(windowNumber),
                    "state": String(describing: ownElementFullscreenState),
                    "panel_visible": String(isVisible),
                ]
            )
            return
        }

        if Self.shouldTreatShowAsExplicitFullscreenSummon(
            isPinned: isPresentationPinned,
            fullscreenState: ownElementFullscreenState,
            panelIsVisible: isVisible
        ) {
            restoreShellWorkItem?.cancel()
            restoreShellWorkItem = nil
            shellAutoSuppressedForOwnFullscreen = false
            explicitFullscreenOverlay = true
            FloatTabsFullscreenPresentation.shellExplicitlySummoned = true
            FloatTabsDiagnostics.record(
                "fullscreen_shell_explicit_summon",
                fields: ["panel_window_number": String(windowNumber)]
            )
            applyPresentationPolicy()
            super.orderFrontRegardless()
            return
        }

        super.makeKeyAndOrderFront(sender)
    }

    override func orderOut(_ sender: Any?) {
        if explicitFullscreenOverlay {
            explicitFullscreenOverlay = false
            FloatTabsFullscreenPresentation.shellExplicitlySummoned = false
            FloatTabsDiagnostics.record(
                "fullscreen_shell_explicit_hide",
                fields: ["panel_window_number": String(windowNumber)]
            )
            applyPresentationPolicy()
        }
        super.orderOut(sender)
    }

    /// PanelController normally repositions the shell toward the current target
    /// screen each time it is summoned. During a WebKit fullscreen session that
    /// would couple the shell geometry to the fullscreen Space, so programmatic
    /// frame writes stay frozen until WebKit returns ownership.
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        guard !Self.shouldFreezeShellFrame(fullscreenState: ownElementFullscreenState) else {
            return
        }
        super.setFrame(frameRect, display: flag)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool, animate animateFlag: Bool) {
        guard !Self.shouldFreezeShellFrame(fullscreenState: ownElementFullscreenState) else {
            return
        }
        super.setFrame(frameRect, display: flag, animate: animateFlag)
    }

    override func sendEvent(_ event: NSEvent) {
        if Self.isMouseDown(event.type),
           let webView = webViewHit(by: event) {
            observeFullscreenStateIfNeeded(for: webView)
        }

        if Self.shouldAnchorKeyboardFocus(
            eventType: event.type,
            isKeyWindow: isKeyWindow,
            fullscreenState: ownElementFullscreenState
        ) {
            // `.nonactivatingPanel` keeps this from broadly activating the app,
            // while refreshing NSScreen.main for WebKit's next fullscreen request.
            makeKey()
            FloatTabsDiagnostics.record(
                "fullscreen_focus_anchor",
                fields: [
                    "panel_window_number": String(windowNumber),
                    "panel_frame": NSStringFromRect(frame),
                    "panel_screen_frame": screen.map { NSStringFromRect($0.frame) } ?? "nil",
                    "main_screen_frame": NSScreen.main.map { NSStringFromRect($0.frame) } ?? "nil",
                ]
            )
        }

        super.sendEvent(event)

        if let panelController = delegate as? PanelController {
            setPresentationPinned(panelController.isPinned)
        }
    }

    static func presentationCollectionBehavior(
        isPinned: Bool,
        fullscreenState: WKWebView.FullscreenState,
        explicitFullscreenOverlay: Bool = false
    ) -> NSWindow.CollectionBehavior {
        let ownFullscreen = WebViewPool.isActiveFullscreenState(fullscreenState)

        if ownFullscreen && !isPinned && !explicitFullscreenOverlay {
            return [.fullScreenNone, .ignoresCycle]
        }

        return [
            .canJoinAllSpaces,
            .canJoinAllApplications,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
    }

    static func shouldAutoSuppressShell(
        isPinned: Bool,
        fullscreenState: WKWebView.FullscreenState,
        explicitFullscreenOverlay: Bool
    ) -> Bool {
        guard !isPinned, !explicitFullscreenOverlay else { return false }
        switch fullscreenState {
        case .inFullscreen:
            return true
        case .notInFullscreen, .enteringFullscreen, .exitingFullscreen:
            return false
        @unknown default:
            return true
        }
    }

    static func shouldDeferKeyAndOrderFront(
        fullscreenState: WKWebView.FullscreenState
    ) -> Bool {
        switch fullscreenState {
        case .enteringFullscreen, .exitingFullscreen:
            return true
        case .notInFullscreen, .inFullscreen:
            return false
        @unknown default:
            return true
        }
    }

    static func shouldTreatShowAsExplicitFullscreenSummon(
        isPinned: Bool,
        fullscreenState: WKWebView.FullscreenState,
        panelIsVisible: Bool
    ) -> Bool {
        !isPinned && fullscreenState == .inFullscreen && !panelIsVisible
    }

    static func shouldFreezeShellFrame(
        fullscreenState: WKWebView.FullscreenState
    ) -> Bool {
        WebViewPool.isActiveFullscreenState(fullscreenState)
    }

    static func shouldKeepObservedFullscreenOwner(
        currentState: WKWebView.FullscreenState,
        isSameWebView: Bool
    ) -> Bool {
        !isSameWebView && WebViewPool.isActiveFullscreenState(currentState)
    }

    static func shouldAnchorKeyboardFocus(
        eventType: NSEvent.EventType,
        isKeyWindow: Bool,
        fullscreenState: WKWebView.FullscreenState
    ) -> Bool {
        guard !isKeyWindow,
              !WebViewPool.isActiveFullscreenState(fullscreenState) else {
            return false
        }
        return isMouseDown(eventType)
    }

    private static func isMouseDown(_ eventType: NSEvent.EventType) -> Bool {
        switch eventType {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return true
        default:
            return false
        }
    }

    private func webViewHit(by event: NSEvent) -> WKWebView? {
        guard let contentView else { return nil }
        let point = contentView.convert(event.locationInWindow, from: nil)
        var candidate = contentView.hitTest(point)

        while let view = candidate {
            if let webView = view as? WKWebView {
                return webView
            }
            candidate = view.superview
        }
        return nil
    }

    private func observeFullscreenStateIfNeeded(for webView: WKWebView) {
        let isSameWebView = fullscreenObservedWebView === webView
        if Self.shouldKeepObservedFullscreenOwner(
            currentState: ownElementFullscreenState,
            isSameWebView: isSameWebView
        ) {
            return
        }
        guard !isSameWebView else { return }

        fullscreenStateObservation?.invalidate()
        fullscreenObservedWebView = webView
        ownElementFullscreenState = webView.fullscreenState
        FloatTabsDiagnostics.record(
            "webkit_fullscreen_observation_started",
            fields: [
                "state": String(describing: ownElementFullscreenState),
                "webview_window_number": webView.window.map { String($0.windowNumber) } ?? "nil",
                "webview_window_frame": webView.window.map { NSStringFromRect($0.frame) } ?? "nil",
            ]
        )
        synchronizeFullscreenPresentationState()

        fullscreenStateObservation = webView.observe(
            \.fullscreenState,
            options: [.initial, .new]
        ) { [weak self, weak webView] observedWebView, change in
            let state = change.newValue ?? observedWebView.fullscreenState
            Task { @MainActor [weak self, weak webView] in
                guard let self,
                      let webView,
                      self.fullscreenObservedWebView === webView else {
                    return
                }

                let previousState = self.ownElementFullscreenState
                let wasActive = self.isOwnElementFullscreenActive
                self.ownElementFullscreenState = state
                let currentWindow = webView.window

                FloatTabsDiagnostics.record(
                    "webkit_fullscreen_state",
                    fields: [
                        "state": String(describing: state),
                        "previous_state": String(describing: previousState),
                        "was_active": String(wasActive),
                        "webview_window_number": currentWindow.map { String($0.windowNumber) } ?? "nil",
                        "webview_window_visible": currentWindow.map { String($0.isVisible) } ?? "nil",
                        "webview_window_active_space": currentWindow.map { String($0.isOnActiveSpace) } ?? "nil",
                        "webview_window_frame": currentWindow.map { NSStringFromRect($0.frame) } ?? "nil",
                        "webview_window_screen_frame": currentWindow?.screen.map { NSStringFromRect($0.frame) } ?? "nil",
                        "panel_window_number": String(self.windowNumber),
                        "panel_visible": String(self.isVisible),
                        "panel_active_space": String(self.isOnActiveSpace),
                    ]
                )

                if previousState == .notInFullscreen,
                   WebViewPool.isActiveFullscreenState(state) {
                    // Every new fullscreen attempt starts with a clean shell
                    // presentation state. Pin is the only persistent overlay rule.
                    self.explicitFullscreenOverlay = false
                    FloatTabsFullscreenPresentation.shellExplicitlySummoned = false
                    self.restoreShellWorkItem?.cancel()
                    self.restoreShellWorkItem = nil
                }

                NativeFullscreenSessionResetCoordinator.shared.handleObservedFullscreenTransition(
                    for: webView,
                    previousState: previousState,
                    currentState: state,
                    window: currentWindow
                )

                if state == .inFullscreen,
                   let fullscreenWindow = currentWindow,
                   fullscreenWindow !== self {
                    FloatTabsDiagnostics.record(
                        "fullscreen_transition_completed",
                        fields: [
                            "window_number": String(fullscreenWindow.windowNumber),
                            "window_visible": String(fullscreenWindow.isVisible),
                            "window_active_space": String(fullscreenWindow.isOnActiveSpace),
                            "window_frame": NSStringFromRect(fullscreenWindow.frame),
                            "window_screen_frame": fullscreenWindow.screen.map { NSStringFromRect($0.frame) } ?? "nil",
                        ]
                    )
                    FloatTabsDiagnostics.markFullscreenReachedStableState(fullscreenWindow)
                }

                if state == .notInFullscreen,
                   previousState != .notInFullscreen {
                    FloatTabsDiagnostics.record(
                        "fullscreen_transition_ended",
                        fields: [
                            "previous_state": String(describing: previousState),
                            "webview_window_number": currentWindow.map { String($0.windowNumber) } ?? "nil",
                        ]
                    )
                }

                if !WebViewPool.isActiveFullscreenState(state) {
                    self.explicitFullscreenOverlay = false
                    FloatTabsFullscreenPresentation.shellExplicitlySummoned = false
                }

                self.synchronizeFullscreenPresentationState()
            }
        }
    }

    private func synchronizeFullscreenPresentationState() {
        FloatTabsFullscreenPresentation.isActive = isOwnElementFullscreenActive
        applyPresentationPolicy()
        synchronizeShellVisibilityForFullscreen()
    }

    private func synchronizeShellVisibilityForFullscreen() {
        if Self.shouldAutoSuppressShell(
            isPinned: isPresentationPinned,
            fullscreenState: ownElementFullscreenState,
            explicitFullscreenOverlay: explicitFullscreenOverlay
        ) {
            autoSuppressShellForOwnFullscreenIfNeeded()
            return
        }

        if isPresentationPinned && shellAutoSuppressedForOwnFullscreen {
            restoreAutoSuppressedShellImmediately()
            return
        }

        if !isOwnElementFullscreenActive {
            restoreAutoSuppressedShellAfterFullscreenIfNeeded()
        }
    }

    private func autoSuppressShellForOwnFullscreenIfNeeded() {
        restoreShellWorkItem?.cancel()
        restoreShellWorkItem = nil
        guard !shellAutoSuppressedForOwnFullscreen else { return }

        shellAutoSuppressedForOwnFullscreen = true
        FloatTabsFullscreenPresentation.shellExplicitlySummoned = false
        FloatTabsDiagnostics.record(
            "fullscreen_shell_auto_suppressed",
            fields: [
                "panel_window_number": String(windowNumber),
                "panel_visible_before": String(isVisible),
            ]
        )
        if isVisible {
            super.orderOut(nil)
        }
    }

    private func restoreAutoSuppressedShellImmediately() {
        restoreShellWorkItem?.cancel()
        restoreShellWorkItem = nil
        guard shellAutoSuppressedForOwnFullscreen else { return }

        shellAutoSuppressedForOwnFullscreen = false
        FloatTabsDiagnostics.record(
            "fullscreen_shell_restore_immediate",
            fields: ["panel_window_number": String(windowNumber)]
        )
        super.orderFront(nil)
    }

    private func restoreAutoSuppressedShellAfterFullscreenIfNeeded() {
        guard shellAutoSuppressedForOwnFullscreen else { return }
        restoreShellWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.shellAutoSuppressedForOwnFullscreen,
                  !self.isOwnElementFullscreenActive else {
                return
            }
            self.shellAutoSuppressedForOwnFullscreen = false
            self.restoreShellWorkItem = nil
            FloatTabsDiagnostics.record(
                "fullscreen_shell_restored_after_exit",
                fields: ["panel_window_number": String(self.windowNumber)]
            )
            self.orderFront(nil)
        }
        restoreShellWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }

    private func applyPresentationPolicy() {
        let targetBehavior = Self.presentationCollectionBehavior(
            isPinned: isPresentationPinned,
            fullscreenState: ownElementFullscreenState,
            explicitFullscreenOverlay: explicitFullscreenOverlay
        )

        if level != .floating {
            level = .floating
        }
        if collectionBehavior != targetBehavior {
            collectionBehavior = targetBehavior
        }
    }
}
