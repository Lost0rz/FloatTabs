import AppKit
import Foundation
import WebKit

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private(set) var isPresentationPinned = false
    private weak var fullscreenObservedWebView: WKWebView?
    private var fullscreenStateObservation: NSKeyValueObservation?
    private var ownElementFullscreenState: WKWebView.FullscreenState = .notInFullscreen

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

    /// FloatTabs is always a real floating utility window during ordinary use.
    /// Pin controls auto-hide and whether the shell is allowed to accompany its
    /// own WKWebView into element fullscreen; it does not demote the ordinary
    /// panel below normal application windows.
    func setPresentationPinned(_ pinned: Bool) {
        guard isPresentationPinned != pinned else { return }
        isPresentationPinned = pinned
        applyPresentationPolicy()
    }

    /// WebKit documents `fullscreenState` as KVO-compliant and explicitly tells
    /// native clients to observe it while WebKit replaces the WKWebView with a
    /// placeholder and moves the live view into its fullscreen window. Observe
    /// the page the user is actually interacting with so the FloatTabs shell can
    /// leave that fullscreen Space without touching the WKWebView hierarchy.
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
            // Ordinary show already activates FloatTabs and makes this panel key.
            // Only a pinned panel can legitimately remain visible while another
            // app is active; activate in that narrow case. Avoid repeatedly
            // activating an already-active app from inside sendEvent because that
            // can perturb WebKit's fullscreen transition state machine.
            if isPresentationPinned && !NSApp.isActive {
                if #available(macOS 14.0, *) {
                    NSApp.activate()
                } else {
                    _ = NSRunningApplication.current.activate(options: [])
                }
            }
            if NSApp.isActive {
                makeKey()
            }
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
            // Keep the FloatTabs shell on its original Space while WebKit moves
            // the live WKWebView to the dedicated fullscreen Space. In particular,
            // do not use canJoinAllSpaces/canJoinAllApplications/fullScreenAuxiliary
            // here; each of those can make the shell follow fullscreen content.
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
            }
        }
    }

    private func applyPresentationPolicy() {
        let targetBehavior = Self.presentationCollectionBehavior(
            isPinned: isPresentationPinned,
            fullscreenState: ownElementFullscreenState
        )

        // FloatTabs must remain above ordinary application windows even when Pin
        // is off. Fullscreen yielding is controlled by Space participation, not by
        // demoting the panel to NSWindow.Level.normal.
        if level != .floating {
            level = .floating
        }
        if collectionBehavior != targetBehavior {
            collectionBehavior = targetBehavior
        }
    }
}
