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
    private var shellRestoreGeneration = 0

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
        shellRestoreGeneration &+= 1
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
            cancelDeferredShellRestore()
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
            cancelDeferredShellRestore()
            // Do not orderOut the source panel here. Removing the source window
            // during WebKit fullscreen can strand fullscreen teardown/Spaces.
            // Instead, stop the shell/Tab rail from joining or floating above the
            // WebKit-owned fullscreen Space.
            collectionBehavior = Self.nativeFullscreenCollectionBehavior
            level = .normal

        case .exitingFullscreen:
            cancelDeferredShellRestore()
            // Keep the shell out of the fullscreen Space until WebKit has fully
            // returned the WKWebView to its source window.
            break

        case .notInFullscreen:
            // fullscreenState can reach notInFullscreen while WebKit's native
            // fullscreen window/Space is still visible for a short period. If we
            // restore .fullScreenAuxiliary + .floating immediately, the shell can
            // rejoin that dying fullscreen Space and leave Dock/Space presentation
            // stranded. Restore only after the WebCore fullscreen window is gone.
            restoreOrdinaryShellPresentationWhenFullscreenWindowIsGone()

        case .enteringFullscreen:
            cancelDeferredShellRestore()
            // Preserve the source-window characteristics while WebKit constructs
            // its native fullscreen presentation. The shell is demoted only once
            // WebKit reports stable inFullscreen.
            break

        @unknown default:
            break
        }
    }

    private func cancelDeferredShellRestore() {
        shellRestoreGeneration &+= 1
    }

    private func restoreOrdinaryShellPresentationWhenFullscreenWindowIsGone() {
        shellRestoreGeneration &+= 1
        let generation = shellRestoreGeneration
        pollForFullscreenWindowExit(generation: generation, attemptsRemaining: 200)
    }

    private func pollForFullscreenWindowExit(generation: Int, attemptsRemaining: Int) {
        guard generation == shellRestoreGeneration else { return }
        guard let observed = fullscreenObservedWebView,
              observed.fullscreenState == .notInFullscreen else { return }

        if !hasVisibleWebCoreFullscreenWindow() {
            restoreOrdinaryShellPresentation()
            return
        }

        // Ten seconds is intentionally generous. If WebKit still owns a visible
        // fullscreen window after that, keep the shell demoted rather than forcing
        // it back into the stale fullscreen Space. A later show/state refresh will
        // re-evaluate this safely.
        guard attemptsRemaining > 0 else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.pollForFullscreenWindowExit(
                generation: generation,
                attemptsRemaining: attemptsRemaining - 1
            )
        }
    }

    private func hasVisibleWebCoreFullscreenWindow() -> Bool {
        NSApp.windows.contains { window in
            guard window.isVisible else { return false }
            return String(describing: type(of: window)).contains("WebCoreFullScreenWindow")
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
