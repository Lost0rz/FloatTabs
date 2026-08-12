import AppKit
import WebKit

final class FloatingPanel: NSPanel {
    private static let ordinaryCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .canJoinAllApplications,
        .fullScreenAuxiliary,
        .ignoresCycle,
    ]

    private static let nativeFullscreenCollectionBehavior: NSWindow.CollectionBehavior = [
        .fullScreenNone,
        .ignoresCycle,
    ]

    private weak var fullscreenObservedWebView: WKWebView?
    private var fullscreenObservation: NSKeyValueObservation?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override var contentView: NSView? {
        didSet {
            DispatchQueue.main.async { [weak self] in
                self?.refreshNativeFullscreenObservation()
            }
        }
    }

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

    deinit {
        fullscreenObservation?.invalidate()
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        refreshNativeFullscreenObservation()
        super.makeKeyAndOrderFront(sender)
    }

    /// The shell must not participate as a floating auxiliary window in the
    /// WebKit-owned fullscreen Space. We only change the FloatTabs shell's own
    /// presentation; the WKWebView and WebCore fullscreen window remain untouched.
    private func refreshNativeFullscreenObservation() {
        guard let candidate = firstWebView(in: contentView) else {
            fullscreenObservation?.invalidate()
            fullscreenObservation = nil
            fullscreenObservedWebView = nil
            restoreOrdinaryShellPresentation()
            return
        }

        if fullscreenObservedWebView === candidate {
            applyShellPresentation(for: candidate.fullscreenState)
            return
        }

        fullscreenObservation?.invalidate()
        fullscreenObservedWebView = candidate
        applyShellPresentation(for: candidate.fullscreenState)

        fullscreenObservation = candidate.observe(\.fullscreenState, options: [.initial, .new]) { [weak self, weak candidate] _, _ in
            DispatchQueue.main.async {
                guard let self, let candidate, self.fullscreenObservedWebView === candidate else { return }
                self.applyShellPresentation(for: candidate.fullscreenState)
            }
        }
    }

    private func applyShellPresentation(for state: WKWebView.FullscreenState) {
        switch state {
        case .inFullscreen:
            // Do not orderOut the source panel here. Removing the source window
            // during WebKit fullscreen can strand fullscreen teardown/Spaces.
            // Instead, stop the shell/Tab rail from joining or floating above the
            // WebKit-owned fullscreen Space.
            collectionBehavior = Self.nativeFullscreenCollectionBehavior
            level = .normal

        case .exitingFullscreen:
            // Keep the shell out of the fullscreen Space until WebKit has fully
            // returned the WKWebView to its source window.
            break

        case .notInFullscreen:
            restoreOrdinaryShellPresentation()

        case .enteringFullscreen:
            // Preserve the source-window characteristics while WebKit constructs
            // its native fullscreen presentation. The shell is demoted only once
            // WebKit reports stable inFullscreen.
            break

        @unknown default:
            break
        }
    }

    private func restoreOrdinaryShellPresentation() {
        collectionBehavior = Self.ordinaryCollectionBehavior
        level = .floating
    }

    private func firstWebView(in view: NSView?) -> WKWebView? {
        guard let view else { return nil }
        if let webView = view as? WKWebView {
            return webView
        }
        for child in view.subviews {
            if let webView = firstWebView(in: child) {
                return webView
            }
        }
        return nil
    }
}
