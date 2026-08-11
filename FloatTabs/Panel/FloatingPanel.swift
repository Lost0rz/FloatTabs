import AppKit
import Foundation
import WebKit

@MainActor
enum FloatTabsFullscreenPresentation {
    private(set) static var isWebKitActive = false

    /// Unified presentation state used by the global shortcut and Shell. Native
    /// WebKit fullscreen remains a diagnostic fallback; production WebViews use
    /// the app-owned one-shot window coordinator.
    static var isActive: Bool {
        isWebKitActive || AppOwnedFullscreenPresentation.isActive
    }

    /// Tracks only an explicit user summon of the shell during own fullscreen.
    /// `NSWindow.isVisible` is not reliable enough across Spaces to implement the
    /// fullscreen shortcut as a toggle by itself.
    static var shellExplicitlySummoned = false

    static func updateWebKitState(isActive: Bool) {
        isWebKitActive = isActive
    }
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

    // Track the WebKit-owned fullscreen window across enter/exit attempts. WebKit
    // may reuse the same NSWindow for later sessions.
    private weak var reusableFullscreenWindow: NSWindow?
    private weak var transitionFullscreenWindow: NSWindow?
    private var staleFullscreenRecoveryWorkItem: DispatchWorkItem?
    private var didReachInFullscreenThisSession = false

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

    /// `makeKeyAndOrderFront` is used by several ordinary show/focus paths, so it
    /// cannot by itself prove that the user explicitly summoned FloatTabs. During
    /// WebKit's enter/exit transitions, never let the shell take key status back
    /// from the fullscreen window. Once `.inFullscreen` is stable, a hidden
    /// unpinned shell may be explicitly summoned by the global shortcut.
    override func makeKeyAndOrderFront(_ sender: Any?) {
        if Self.shouldDeferKeyAndOrderFront(
            fullscreenState: ownElementFullscreenState,
            appOwnedPhase: AppOwnedFullscreenPresentation.phase
        ) {
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
            appOwnedPhase: AppOwnedFullscreenPresentation.phase,
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
        }
        super.makeKeyAndOrderFront(sender)
    }

    override func orderOut(_ sender: Any?) {
        if explicitFullscreenOverlay {
            AppOwnedFullscreenCoordinator.shared.shellWasExplicitlyHidden()
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
        guard !Self.shouldFreezeShellFrame(
            fullscreenState: ownElementFullscreenState,
            appOwnedPhase: AppOwnedFullscreenPresentation.phase
        ) else {
            return
        }
        super.setFrame(frameRect, display: flag)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool, animate animateFlag: Bool) {
        guard !Self.shouldFreezeShellFrame(
            fullscreenState: ownElementFullscreenState,
            appOwnedPhase: AppOwnedFullscreenPresentation.phase
        ) else {
            return
        }
        super.setFrame(frameRect, display: flag, animate: animateFlag)
    }

    override func sendEvent(_ event: NSEvent) {
        if Self.isMouseDown(event.type),
           let webView = webViewHit(by: event) {
            // Do not move WebKit's reusable fullscreen NSWindow ourselves.
            // Physical multi-display diagnostics proved WebKit re-selects the
            // fullscreen display from NSScreen.main on every entry and can move
            // this same hidden window itself. Mutating its frame between sessions
            // risks carrying stale fullscreen-Space affiliation into the next
            // enter. Observe it for diagnostics, but leave ownership to WebKit.
            prepareReusableFullscreenWindowForPotentialRequest(
                webView: webView,
                mouseLocation: NSEvent.mouseLocation
            )
            observeFullscreenStateIfNeeded(for: webView)
        }

        if Self.shouldAnchorKeyboardFocus(
            eventType: event.type,
            isKeyWindow: isKeyWindow,
            fullscreenState: ownElementFullscreenState,
            appOwnedPhase: AppOwnedFullscreenPresentation.phase
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
        appOwnedPhase: AppOwnedFullscreenPresentation.Phase = .idle,
        explicitFullscreenOverlay: Bool = false
    ) -> NSWindow.CollectionBehavior {
        let ownFullscreen = WebViewPool.isActiveFullscreenState(fullscreenState)
            || appOwnedPhase != .idle

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
        fullscreenState: WKWebView.FullscreenState,
        appOwnedPhase: AppOwnedFullscreenPresentation.Phase = .idle
    ) -> Bool {
        if appOwnedPhase == .entering || appOwnedPhase == .exiting {
            return true
        }
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
        appOwnedPhase: AppOwnedFullscreenPresentation.Phase = .idle,
        panelIsVisible: Bool
    ) -> Bool {
        let stableFullscreen = fullscreenState == .inFullscreen || appOwnedPhase == .active
        return !isPinned && stableFullscreen && !panelIsVisible
    }

    static func shouldRecoverStaleFullscreenWindow(
        previousState: WKWebView.FullscreenState,
        currentState: WKWebView.FullscreenState,
        didReachInFullscreen: Bool,
        windowIsVisible: Bool
    ) -> Bool {
        previousState != .notInFullscreen
            && currentState == .notInFullscreen
            && !didReachInFullscreen
            && windowIsVisible
    }

    static func shouldFreezeShellFrame(
        fullscreenState: WKWebView.FullscreenState,
        appOwnedPhase: AppOwnedFullscreenPresentation.Phase = .idle
    ) -> Bool {
        WebViewPool.isActiveFullscreenState(fullscreenState) || appOwnedPhase != .idle
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
        fullscreenState: WKWebView.FullscreenState,
        appOwnedPhase: AppOwnedFullscreenPresentation.Phase = .idle
    ) -> Bool {
        guard !isKeyWindow,
              !WebViewPool.isActiveFullscreenState(fullscreenState),
              appOwnedPhase == .idle else {
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
        let mouseScreen = Self.targetScreenIndex(
            mouseLocation: mouseLocation,
            screenFrames: screens.map(\.frame)
        ).map { screens[$0] }

        FloatTabsDiagnostics.record(
            "reusable_fullscreen_window_left_to_webkit",
            fields: [
                "window_number": String(reusableFullscreenWindow.windowNumber),
                "window_visible": String(reusableFullscreenWindow.isVisible),
                "window_active_space": String(reusableFullscreenWindow.isOnActiveSpace),
                "window_frame": NSStringFromRect(reusableFullscreenWindow.frame),
                "window_screen_frame": reusableFullscreenWindow.screen.map { NSStringFromRect($0.frame) } ?? "nil",
                "main_screen_frame": NSScreen.main.map { NSStringFromRect($0.frame) } ?? "nil",
                "mouse_screen_frame": mouseScreen.map { NSStringFromRect($0.frame) } ?? "nil",
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
        transitionFullscreenWindow = nil
        staleFullscreenRecoveryWorkItem?.cancel()
        staleFullscreenRecoveryWorkItem = nil
        didReachInFullscreenThisSession = false
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
                        "did_reach_in_fullscreen": String(self.didReachInFullscreenThisSession),
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
                    // Every new fullscreen attempt starts passive. Pin is the only
                    // persistent overlay policy; an old explicit summon must not
                    // leak into the next session.
                    self.didReachInFullscreenThisSession = false
                    self.transitionFullscreenWindow = nil
                    self.staleFullscreenRecoveryWorkItem?.cancel()
                    self.staleFullscreenRecoveryWorkItem = nil
                    self.explicitFullscreenOverlay = false
                    FloatTabsFullscreenPresentation.shellExplicitlySummoned = false
                    self.restoreShellWorkItem?.cancel()
                    self.restoreShellWorkItem = nil
                }

                if WebViewPool.isActiveFullscreenState(state),
                   let fullscreenWindow = currentWindow,
                   fullscreenWindow !== self {
                    self.transitionFullscreenWindow = fullscreenWindow
                }

                if state == .inFullscreen,
                   let fullscreenWindow = currentWindow,
                   fullscreenWindow !== self {
                    self.didReachInFullscreenThisSession = true
                    self.reusableFullscreenWindow = fullscreenWindow
                    self.transitionFullscreenWindow = fullscreenWindow
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

                let staleWindow = self.transitionFullscreenWindow ?? self.reusableFullscreenWindow
                let aborted = Self.shouldRecoverStaleFullscreenWindow(
                    previousState: previousState,
                    currentState: state,
                    didReachInFullscreen: self.didReachInFullscreenThisSession,
                    windowIsVisible: staleWindow?.isVisible ?? false
                )

                if state == .notInFullscreen,
                   previousState != .notInFullscreen,
                   !self.didReachInFullscreenThisSession {
                    FloatTabsDiagnostics.record(
                        "fullscreen_transition_aborted",
                        fields: [
                            "previous_state": String(describing: previousState),
                            "stale_window_number": staleWindow.map { String($0.windowNumber) } ?? "nil",
                            "stale_window_visible": staleWindow.map { String($0.isVisible) } ?? "nil",
                            "stale_window_active_space": staleWindow.map { String($0.isOnActiveSpace) } ?? "nil",
                        ]
                    )
                }

                if aborted, let staleWindow {
                    self.scheduleStaleFullscreenWindowRecovery(staleWindow)
                }

                if !WebViewPool.isActiveFullscreenState(state) {
                    self.explicitFullscreenOverlay = false
                    FloatTabsFullscreenPresentation.shellExplicitlySummoned = false
                    if self.didReachInFullscreenThisSession {
                        self.didReachInFullscreenThisSession = false
                    }
                    self.transitionFullscreenWindow = nil
                }

                self.synchronizeFullscreenPresentationState(for: webView)
            }
        }
    }

    private func scheduleStaleFullscreenWindowRecovery(_ staleWindow: NSWindow) {
        staleFullscreenRecoveryWorkItem?.cancel()

        FloatTabsDiagnostics.record(
            "stale_fullscreen_window_recovery_scheduled",
            fields: [
                "window_number": String(staleWindow.windowNumber),
                "window_visible": String(staleWindow.isVisible),
                "window_active_space": String(staleWindow.isOnActiveSpace),
                "window_frame": NSStringFromRect(staleWindow.frame),
            ]
        )

        let workItem = DispatchWorkItem { [weak self, weak staleWindow] in
            guard let self,
                  let staleWindow,
                  self.ownElementFullscreenState == .notInFullscreen,
                  staleWindow !== self,
                  staleWindow.isVisible,
                  staleWindow.collectionBehavior.contains(.fullScreenPrimary) else {
                return
            }

            FloatTabsDiagnostics.record(
                "stale_fullscreen_window_recovery_before",
                fields: [
                    "window_number": String(staleWindow.windowNumber),
                    "window_visible": String(staleWindow.isVisible),
                    "window_active_space": String(staleWindow.isOnActiveSpace),
                    "window_frame": NSStringFromRect(staleWindow.frame),
                ]
            )

            staleWindow.orderOut(nil)
            self.staleFullscreenRecoveryWorkItem = nil

            FloatTabsDiagnostics.record(
                "stale_fullscreen_window_recovery_after",
                fields: [
                    "window_number": String(staleWindow.windowNumber),
                    "window_visible": String(staleWindow.isVisible),
                    "window_active_space": String(staleWindow.isOnActiveSpace),
                    "window_frame": NSStringFromRect(staleWindow.frame),
                ]
            )
        }
        staleFullscreenRecoveryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10, execute: workItem)
    }

    private func synchronizeFullscreenPresentationState(for webView: WKWebView) {
        FloatTabsFullscreenPresentation.updateWebKitState(
            isActive: isOwnElementFullscreenActive
        )
        applyPresentationPolicy()
        synchronizeShellVisibilityForFullscreen()
    }

    func appOwnedFullscreenPhaseDidChange() {
        if !AppOwnedFullscreenPresentation.isActive && !isOwnElementFullscreenActive {
            explicitFullscreenOverlay = false
            FloatTabsFullscreenPresentation.shellExplicitlySummoned = false
        }
        applyPresentationPolicy()
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
            appOwnedPhase: AppOwnedFullscreenPresentation.phase,
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
