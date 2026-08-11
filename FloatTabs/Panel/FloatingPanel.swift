import AppKit
import Foundation
import WebKit

@MainActor
enum FloatTabsFullscreenPresentation {
    /// True while the FloatTabs page currently observed by the panel is in any
    /// WebKit element-fullscreen transition. This does not block the shell; it
    /// lets the global shortcut treat fullscreen as an explicit summon instead
    /// of relying on NSWindow.isVisible across Spaces.
    static var isActive = false
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private(set) var isPresentationPinned = false
    private weak var fullscreenObservedWebView: WKWebView?
    private var fullscreenStateObservation: NSKeyValueObservation?
    private var ownElementFullscreenState: WKWebView.FullscreenState = .notInFullscreen
    private var explicitFullscreenOverlay = false

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
        // instead of relying on `needsPanelToBecomeKey` from the hit subview. This
        // matters for WebKit element fullscreen because WebKit chooses its target
        // display from `NSScreen.main`, i.e. the screen containing the key window.
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

    var isOwnElementFullscreenActive: Bool {
        WebViewPool.isActiveFullscreenState(ownElementFullscreenState)
    }

    /// FloatTabs is always a real floating utility window during ordinary use.
    /// Pin controls persistence. It is not required merely to summon the shell
    /// while one FloatTabs page is fullscreen.
    func setPresentationPinned(_ pinned: Bool) {
        guard isPresentationPinned != pinned else { return }
        isPresentationPinned = pinned
        applyPresentationPolicy()
    }

    /// An explicit global summon during own fullscreen is different from the
    /// automatic fullscreen transition. The shell is allowed to join the current
    /// fullscreen Space only after the user asks for it. This keeps an existing
    /// shell on display A from automatically following fullscreen content to B.
    override func makeKeyAndOrderFront(_ sender: Any?) {
        if isOwnElementFullscreenActive && !isPresentationPinned {
            explicitFullscreenOverlay = true
            applyPresentationPolicy()
        }
        super.makeKeyAndOrderFront(sender)
    }

    override func orderOut(_ sender: Any?) {
        if explicitFullscreenOverlay {
            explicitFullscreenOverlay = false
            applyPresentationPolicy()
        }
        super.orderOut(sender)
    }

    /// PanelController normally repositions the shell toward the current target
    /// screen each time it is summoned. During a WebKit fullscreen session that
    /// would make the shell follow the fullscreen display, coupling two things
    /// that must stay independent. Freeze programmatic frame changes until the
    /// fullscreen owner exits; user-initiated window movement still uses
    /// `setFrameOrigin` and remains intentional.
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

    /// WebKit documents `fullscreenState` as KVO-compliant and temporarily owns
    /// the live WKWebView hierarchy during element fullscreen. Keep observing the
    /// fullscreen owner even when the user summons the shell and clicks another
    /// Slot; otherwise clicking ChatGPT would replace the observation and make
    /// FloatTabs forget that YouTube is still fullscreen.
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
            // Making the panel key refreshes NSScreen.main for each new fullscreen
            // request so display routing does not remain stuck on an old screen.
            makeKey()
        }

        super.sendEvent(event)

        // PanelController remains the single owner of Pin state.
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
            // The fullscreen page and the shell are independent presentations.
            // Do not automatically drag the shell into the fullscreen Space. On
            // multi-display Macs this leaves the shell on its original display;
            // on one display the fullscreen Space naturally covers it until the
            // user explicitly summons FloatTabs.
            return [.fullScreenNone, .ignoresCycle]
        }

        // Ordinary global summon, Pin, or an explicit summon over own fullscreen.
        return [
            .canJoinAllSpaces,
            .canJoinAllApplications,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
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
                self.ownElementFullscreenState = state
                if !WebViewPool.isActiveFullscreenState(state) {
                    self.explicitFullscreenOverlay = false
                }
                self.synchronizeFullscreenPresentationState()
            }
        }
    }

    private func synchronizeFullscreenPresentationState() {
        FloatTabsFullscreenPresentation.isActive = isOwnElementFullscreenActive
        applyPresentationPolicy()
    }

    private func applyPresentationPolicy() {
        let targetBehavior = Self.presentationCollectionBehavior(
            isPinned: isPresentationPinned,
            fullscreenState: ownElementFullscreenState,
            explicitFullscreenOverlay: explicitFullscreenOverlay
        )

        // FloatTabs must remain above ordinary application windows even when Pin
        // is off. Fullscreen yielding is controlled by Space participation only;
        // the fullscreen WKWebView never owns or relocates the shell itself.
        if level != .floating {
            level = .floating
        }
        if collectionBehavior != targetBehavior {
            collectionBehavior = targetBehavior
        }
    }
}
