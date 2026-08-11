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

    // WebKit creates one fullscreen NSWindow for a WKWebView and reuses it across
    // later fullscreen sessions. Capture that public NSWindow while the WebView is
    // fullscreen so, after exit, it can be pre-positioned onto the next target
    // display before WebKit re-enters fullscreen.
    private weak var reusableFullscreenWindow: NSWindow?

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

    /// An explicit global summon during own fullscreen is different from the
    /// automatic fullscreen transition. The shell may temporarily join the
    /// fullscreen Space only after the user asks for it.
    override func makeKeyAndOrderFront(_ sender: Any?) {
        if isOwnElementFullscreenActive && !isPresentationPinned {
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
    /// would make the shell follow the fullscreen display, coupling two things
    /// that must stay independent. Freeze programmatic frame changes until the
    /// fullscreen owner exits; user-initiated movement uses `setFrameOrigin`.
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
            // A reused WebKit fullscreen window can remain associated with the
            // display/Space from the previous session even after it is ordered
            // out. Before a new request is generated, move that hidden standard
            // NSWindow onto the display containing this interaction. WebKit will
            // still own the actual enter/exit transition.
            prepareReusableFullscreenWindowForPotentialRequest(
                webView: webView,
                mouseLocation: NSEvent.mouseLocation
            )
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

    static func shouldPrepositionReusableFullscreenWindow(
        fullscreenState: WKWebView.FullscreenState,
        isSameWebView: Bool,
        windowIsVisible: Bool
    ) -> Bool {
        fullscreenState == .notInFullscreen && isSameWebView && !windowIsVisible
    }

    static func targetScreenIndex(
        mouseLocation: NSPoint,
        screenFrames: [NSRect]
    ) -> Int? {
        screenFrames.firstIndex { NSMouseInRect(mouseLocation, $0, false) }
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

    private func prepareReusableFullscreenWindowForPotentialRequest(
        webView: WKWebView,
        mouseLocation: NSPoint
    ) {
        guard Self.shouldPrepositionReusableFullscreenWindow(
            fullscreenState: ownElementFullscreenState,
            isSameWebView: fullscreenObservedWebView === webView,
            windowIsVisible: reusableFullscreenWindow?.isVisible ?? true
        ), let reusableFullscreenWindow else {
            return
        }

        let screens = NSScreen.screens
        guard let index = Self.targetScreenIndex(
            mouseLocation: mouseLocation,
            screenFrames: screens.map(\.frame)
        ) else {
            return
        }
        let targetScreen = screens[index]

        FloatTabsDiagnostics.record(
            "reusable_fullscreen_window_preposition_before",
            fields: [
                "window_number": String(reusableFullscreenWindow.windowNumber),
                "window_visible": String(reusableFullscreenWindow.isVisible),
                "window_active_space": String(reusableFullscreenWindow.isOnActiveSpace),
                "window_frame": NSStringFromRect(reusableFullscreenWindow.frame),
                "window_screen_frame": reusableFullscreenWindow.screen.map { NSStringFromRect($0.frame) } ?? "nil",
                "target_screen_frame": NSStringFromRect(targetScreen.frame),
            ]
        )

        // Use only public NSWindow/NSScreen API. The window remains hidden; this
        // updates its AppKit screen association before WebKit calls
        // `enterFullScreenMode` again on the same reused window.
        reusableFullscreenWindow.setFrame(targetScreen.frame, display: false)

        FloatTabsDiagnostics.record(
            "reusable_fullscreen_window_preposition_after",
            fields: [
                "window_number": String(reusableFullscreenWindow.windowNumber),
                "window_visible": String(reusableFullscreenWindow.isVisible),
                "window_active_space": String(reusableFullscreenWindow.isOnActiveSpace),
                "window_frame": NSStringFromRect(reusableFullscreenWindow.frame),
                "window_screen_frame": reusableFullscreenWindow.screen.map { NSStringFromRect($0.frame) } ?? "nil",
                "target_screen_frame": NSStringFromRect(targetScreen.frame),
            ]
        )
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
        reusableFullscreenWindow = nil
        ownElementFullscreenState = webView.fullscreenState
        FloatTabsDiagnostics.record(
            "webkit_fullscreen_observation_started",
            fields: [
                "state": String(describing: ownElementFullscreenState),
                "webview_window_number": webView.window.map { String($0.windowNumber) } ?? "nil",
                "webview_window_frame": webView.window.map { NSStringFromRect($0.frame) } ?? "nil",
            ]
        )
        synchronizeFullscreenPresentationState(for: webView)

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

                let wasActive = self.isOwnElementFullscreenActive
                self.ownElementFullscreenState = state
                let currentWindow = webView.window
                FloatTabsDiagnostics.record(
                    "webkit_fullscreen_state",
                    fields: [
                        "state": String(describing: state),
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

                if !wasActive && WebViewPool.isActiveFullscreenState(state) {
                    // Every new fullscreen session starts passive. Pin is the only
                    // persistent overlay policy; an old explicit summon must not
                    // leak into the next session.
                    self.explicitFullscreenOverlay = false
                    FloatTabsFullscreenPresentation.shellExplicitlySummoned = false
                    self.restoreShellWorkItem?.cancel()
                    self.restoreShellWorkItem = nil
                }

                if state == .inFullscreen,
                   let fullscreenWindow = webView.window,
                   fullscreenWindow !== self {
                    self.reusableFullscreenWindow = fullscreenWindow
                    FloatTabsDiagnostics.record(
                        "reusable_fullscreen_window_captured",
                        fields: [
                            "window_number": String(fullscreenWindow.windowNumber),
                            "window_visible": String(fullscreenWindow.isVisible),
                            "window_active_space": String(fullscreenWindow.isOnActiveSpace),
                            "window_frame": NSStringFromRect(fullscreenWindow.frame),
                            "window_screen_frame": fullscreenWindow.screen.map { NSStringFromRect($0.frame) } ?? "nil",
                            "window_behavior": String(fullscreenWindow.collectionBehavior.rawValue),
                        ]
                    )
                }

                if !WebViewPool.isActiveFullscreenState(state) {
                    self.explicitFullscreenOverlay = false
                    FloatTabsFullscreenPresentation.shellExplicitlySummoned = false
                }

                self.synchronizeFullscreenPresentationState(for: webView)
            }
        }
    }

    private func synchronizeFullscreenPresentationState(for webView: WKWebView) {
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
