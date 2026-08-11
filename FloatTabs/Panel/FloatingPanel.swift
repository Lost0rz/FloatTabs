import AppKit
import Foundation
import WebKit

@MainActor
enum FloatTabsFullscreenGate {
    /// While an unpinned FloatTabs page owns WebKit element fullscreen, the
    /// global show/hide shortcut must not re-show the shell. Re-showing the same
    /// panel can cause AppKit layout to compete with WebKit for the live WKWebView.
    static var blocksSummon = false
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private(set) var isPresentationPinned = false
    private weak var fullscreenObservedWebView: WKWebView?
    private var fullscreenStateObservation: NSKeyValueObservation?
    private var ownElementFullscreenState: WKWebView.FullscreenState = .notInFullscreen
    private var shellSuppressedForOwnFullscreen = false
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
            fullscreenState: .notInFullscreen
        )

        // A non-activating panel is allowed to become key without activating the
        // owning app. Let every real click establish this panel as the key window
        // instead of relying on `needsPanelToBecomeKey` from the hit subview. This
        // matters for WebKit element fullscreen because WebKit chooses its target
        // display from `NSScreen.main`, i.e. the screen containing the key window.
        // Re-establishing key ownership on every panel interaction prevents a
        // previous fullscreen session on display A from leaving display A as the
        // stale fullscreen target after the user returns to FloatTabs on display B.
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

    /// FloatTabs is always a real floating utility window during ordinary use.
    /// Pin controls auto-hide and whether the shell is allowed to accompany its
    /// own WKWebView into element fullscreen; it does not demote the ordinary
    /// panel below normal application windows.
    func setPresentationPinned(_ pinned: Bool) {
        guard isPresentationPinned != pinned else { return }
        isPresentationPinned = pinned
        applyPresentationPolicy()
        synchronizeFullscreenShellSuppression()
    }

    /// WebKit documents `fullscreenState` as KVO-compliant and explicitly tells
    /// native clients to observe it while WebKit replaces the WKWebView with a
    /// placeholder and moves the live view into its fullscreen window. Observe
    /// the page the user is actually interacting with so the FloatTabs shell can
    /// yield without touching the WKWebView hierarchy.
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
            // `.nonactivatingPanel` keeps this from activating the entire app.
            // Making the panel key is nevertheless important: WebKit samples
            // `NSScreen.main` asynchronously when starting element fullscreen,
            // and `NSScreen.main` follows the key window rather than pointer
            // location. Do not gate this on `NSApp.isActive`; doing so leaves the
            // previous app/display as the fullscreen target after a screen switch.
            makeKey()
        }

        super.sendEvent(event)

        // PanelController remains the single owner of Pin state. Synchronize only
        // after the event so clicking the pin control updates presentation policy
        // without creating a second Pin state machine in the window subclass.
        if let panelController = delegate as? PanelController {
            setPresentationPinned(panelController.isPinned)
        }
    }

    static func presentationCollectionBehavior(
        isPinned: Bool,
        fullscreenState: WKWebView.FullscreenState
    ) -> NSWindow.CollectionBehavior {
        let ownFullscreen = WebViewPool.isActiveFullscreenState(fullscreenState)

        if ownFullscreen && !isPinned {
            // Keep the FloatTabs shell from joining WebKit's fullscreen Space.
            // The shell is also ordered out once WebKit reaches `inFullscreen`;
            // this behavior remains as a second defensive layer during the
            // transition and on macOS configurations where Space changes lag.
            return [.fullScreenNone, .ignoresCycle]
        }

        // Outside its own element fullscreen, FloatTabs keeps the accepted global
        // summon behavior, including the ability to appear above other apps and
        // above unrelated fullscreen applications.
        return [
            .canJoinAllSpaces,
            .canJoinAllApplications,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
    }

    static func shouldBlockSummon(
        isPinned: Bool,
        fullscreenState: WKWebView.FullscreenState
    ) -> Bool {
        !isPinned && WebViewPool.isActiveFullscreenState(fullscreenState)
    }

    static func shouldSuppressShell(
        isPinned: Bool,
        fullscreenState: WKWebView.FullscreenState
    ) -> Bool {
        guard !isPinned else { return false }
        switch fullscreenState {
        case .inFullscreen:
            return true
        case .notInFullscreen, .enteringFullscreen, .exitingFullscreen:
            return false
        @unknown default:
            return true
        }
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
        guard fullscreenObservedWebView !== webView else { return }

        fullscreenStateObservation?.invalidate()
        fullscreenObservedWebView = webView
        ownElementFullscreenState = webView.fullscreenState
        applyPresentationPolicy()
        synchronizeFullscreenShellSuppression()

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
                self.ownElementFullscreenState = state
                self.applyPresentationPolicy()
                self.synchronizeFullscreenShellSuppression()
            }
        }
    }

    private func synchronizeFullscreenShellSuppression() {
        let blockSummon = Self.shouldBlockSummon(
            isPinned: isPresentationPinned,
            fullscreenState: ownElementFullscreenState
        )
        FloatTabsFullscreenGate.blocksSummon = blockSummon

        if Self.shouldSuppressShell(
            isPinned: isPresentationPinned,
            fullscreenState: ownElementFullscreenState
        ) {
            suppressShellForOwnFullscreenIfNeeded()
            return
        }

        if !WebViewPool.isActiveFullscreenState(ownElementFullscreenState) {
            restoreShellAfterOwnFullscreenIfNeeded()
        } else if isPresentationPinned {
            restoreShellImmediatelyIfNeeded()
        }
    }

    /// Do not order the panel out during `enteringFullscreen`. WebKit is still
    /// moving the live WKWebView at that point. Wait until `inFullscreen`, then
    /// hide only the FloatTabs shell while the fullscreen window keeps running.
    private func suppressShellForOwnFullscreenIfNeeded() {
        restoreShellWorkItem?.cancel()
        restoreShellWorkItem = nil
        guard !shellSuppressedForOwnFullscreen else { return }
        shellSuppressedForOwnFullscreen = true
        if isVisible {
            orderOut(nil)
        }
    }

    /// `notInFullscreen` can arrive in the same run-loop turn in which WebKit is
    /// returning the WKWebView to its original hierarchy. Delay shell restoration
    /// slightly so FloatTabs never races that reparent operation with a layout.
    private func restoreShellAfterOwnFullscreenIfNeeded() {
        guard shellSuppressedForOwnFullscreen else { return }
        restoreShellWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.shellSuppressedForOwnFullscreen,
                  !WebViewPool.isActiveFullscreenState(self.ownElementFullscreenState),
                  !self.isPresentationPinned else {
                return
            }
            self.shellSuppressedForOwnFullscreen = false
            self.orderFront(nil)
        }
        restoreShellWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }

    private func restoreShellImmediatelyIfNeeded() {
        restoreShellWorkItem?.cancel()
        restoreShellWorkItem = nil
        guard shellSuppressedForOwnFullscreen else { return }
        shellSuppressedForOwnFullscreen = false
        orderFront(nil)
    }

    private func applyPresentationPolicy() {
        let targetBehavior = Self.presentationCollectionBehavior(
            isPinned: isPresentationPinned,
            fullscreenState: ownElementFullscreenState
        )

        // FloatTabs must remain above ordinary application windows even when Pin
        // is off. Fullscreen yielding is controlled by Space participation and
        // temporary shell suppression, never by demoting the panel level.
        if level != .floating {
            level = .floating
        }
        if collectionBehavior != targetBehavior {
            collectionBehavior = targetBehavior
        }
    }
}
