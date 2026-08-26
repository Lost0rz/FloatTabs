import AppKit
import WebKit

@MainActor
enum WebViewFocus {
    static func responderBelongsToWebView(
        _ responder: NSResponder?,
        webView: WKWebView,
        window: NSWindow
    ) -> Bool {
        guard let responderView = responder as? NSView,
              responderView.window === window,
              webView.window === window else {
            return false
        }
        return responderView === webView || responderView.isDescendant(of: webView)
    }

    /// Keep WebKit's private content/editor responder when it is already valid.
    /// Replacing it with the outer WKWebView can discard an active DOM input
    /// session even though the native window itself successfully became key.
    @discardableResult
    static func focus(_ webView: WKWebView, in window: NSWindow) -> Bool {
        if responderBelongsToWebView(
            window.firstResponder,
            webView: webView,
            window: window
        ) {
            return true
        }
        return window.makeFirstResponder(webView)
    }
}

func fullscreenExperimentLog(_ message: String) {
#if DEBUG
    NSLog("[FloatTabsFullscreenExperiment] %@", message)
#endif
}

func fullscreenExperimentScreenID(_ screen: NSScreen?) -> String {
    guard let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            as? NSNumber else {
        return "nil"
    }
    return number.stringValue
}

/// A deliberately ordinary AppKit window. WebKit uses this window as the
/// source/restore owner while it temporarily reparents the WKWebView into its
/// private fullscreen window.
final class FullscreenSourceWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Hosts the normal web surface plus only the controls that physically overlap
/// that surface. The outer rail/frame remain in the independent shell window.
private final class FullscreenSourceRootView: NSView {
    init(
        container: WebPanelContainerView,
        railFoldControl: RailFoldControl,
        resizeHandle: PanelResizeHandleView,
        resizeReadout: ResizeReadoutView,
        shellWindow: NSWindow
    ) {
        super.init(frame: .zero)

        let edgeDragView = WebSourceEdgeDragView(targetWindow: shellWindow)
        resizeHandle.resizeTargetWindow = shellWindow

        for view in [container, edgeDragView, railFoldControl, resizeHandle, resizeReadout] {
            view.removeFromSuperview()
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),

            edgeDragView.leadingAnchor.constraint(equalTo: leadingAnchor),
            edgeDragView.trailingAnchor.constraint(equalTo: trailingAnchor),
            edgeDragView.topAnchor.constraint(equalTo: topAnchor),
            edgeDragView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Mirror the bottom-right resize affordance: the rail fold is
            // acquired entirely inside the page's bottom-left corner.
            railFoldControl.leadingAnchor.constraint(equalTo: leadingAnchor),
            railFoldControl.bottomAnchor.constraint(equalTo: bottomAnchor),
            railFoldControl.widthAnchor.constraint(
                equalToConstant: PanelMetrics.resizeHandleSize
            ),
            railFoldControl.heightAnchor.constraint(
                equalToConstant: PanelMetrics.resizeHandleSize
            ),

            resizeHandle.trailingAnchor.constraint(equalTo: trailingAnchor),
            resizeHandle.bottomAnchor.constraint(equalTo: bottomAnchor),
            resizeHandle.widthAnchor.constraint(equalToConstant: PanelMetrics.resizeHandleSize),
            resizeHandle.heightAnchor.constraint(equalToConstant: PanelMetrics.resizeHandleSize),

            resizeReadout.trailingAnchor.constraint(
                equalTo: resizeHandle.leadingAnchor,
                constant: -8
            ),
            resizeReadout.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Owns the inner half of the uniform four-edge move target after splitting the
/// Web surface from the shell window. It always moves the shell; the host
/// follows through PanelController's window delegate while no fullscreen
/// session runs.
final class WebSourceEdgeDragView: NSView {
    private weak var targetWindow: NSWindow?
    private var startingMouseLocation: NSPoint?
    private var startingWindowOrigin: NSPoint?

    init(targetWindow: NSWindow) {
        self.targetWindow = targetWindow
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard frame.contains(point) else { return nil }
        let localPoint = convert(point, from: superview)
        return Self.dragRects(in: bounds).contains(where: { $0.contains(localPoint) }) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let targetWindow else { return }
        startingMouseLocation = NSEvent.mouseLocation
        startingWindowOrigin = targetWindow.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard let targetWindow,
              let startingMouseLocation,
              let startingWindowOrigin else {
            return
        }
        targetWindow.setFrameOrigin(
            NSPoint(
                x: startingWindowOrigin.x + NSEvent.mouseLocation.x - startingMouseLocation.x,
                y: startingWindowOrigin.y + NSEvent.mouseLocation.y - startingMouseLocation.y
            )
        )
    }

    override func mouseUp(with event: NSEvent) {
        startingMouseLocation = nil
        startingWindowOrigin = nil
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for rect in Self.dragRects(in: bounds) {
            addCursorRect(rect, cursor: PanelMoveCursor.cursor)
        }
    }

    static func dragRects(in bounds: NSRect) -> [NSRect] {
        PanelMovementGeometry.edgeBands(
            around: bounds,
            outerDepth: 0,
            innerDepth: PanelMetrics.innerMovementOverlap,
            clippingBounds: bounds,
            bottomRightExclusion: PanelMetrics.resizeHandleSize
        )
    }
}

enum FullscreenSourceSessionState: String, Equatable {
    case idle
    case entering
    case fullscreen
    case exiting
    case restoring

    var locksSourceHost: Bool { self != .idle }

    static func next(
        from current: FullscreenSourceSessionState,
        webKitState: WKWebView.FullscreenState
    ) -> FullscreenSourceSessionState {
        switch webKitState {
        case .enteringFullscreen:
            return .entering
        case .inFullscreen:
            return .fullscreen
        case .exitingFullscreen:
            return .exiting
        case .notInFullscreen:
            return current == .idle ? .idle : .restoring
        @unknown default:
            return current
        }
    }
}

enum FullscreenRestoreWatchdogDecision: Equatable {
    case poll(stableChecks: Int, delay: TimeInterval)
    case restored
    case rebuildSource
}

/// WebKit returns the WKWebView to the source hierarchy and exposes
/// `.notInFullscreen` before its fullscreen presentation is fully torn down.
/// Keep the source locked until both the public hierarchy and the WebKit-owned
/// fullscreen window have completed restoration, then require a few stable
/// checks to avoid racing the final presentation transaction.
struct FullscreenRestoreWatchdog {
    static let pollInterval: TimeInterval = 0.05
    static let sourceRebuildTimeout: TimeInterval = 10
    static let requiredStableChecks = 3

    static func decision(
        elapsed: TimeInterval,
        isBackInSourceHierarchy: Bool,
        isPresentationComplete: Bool,
        stableChecks: Int
    ) -> FullscreenRestoreWatchdogDecision {
        if isBackInSourceHierarchy, isPresentationComplete {
            let nextStableChecks = stableChecks + 1
            return nextStableChecks >= requiredStableChecks
                ? .restored
                : .poll(stableChecks: nextStableChecks, delay: pollInterval)
        }

        // Preserve the existing bounded recovery only for the original failure
        // mode: WebKit has left fullscreen but never returns the source view.
        // If the source hierarchy is already back while the fullscreen window is
        // still visible, rebuilding the WKWebView would race WebKit's own exit
        // teardown, so remain locked and keep polling instead.
        if elapsed >= sourceRebuildTimeout, !isBackInSourceHierarchy {
            return .rebuildSource
        }

        return .poll(stableChecks: 0, delay: pollInterval)
    }

    /// Compatibility seam for the existing hierarchy-only tests. Production
    /// restoration always calls the presentation-aware overload above.
    static func decision(
        elapsed: TimeInterval,
        isBackInSourceHierarchy: Bool,
        stableChecks: Int
    ) -> FullscreenRestoreWatchdogDecision {
        decision(
            elapsed: elapsed,
            isBackInSourceHierarchy: isBackInSourceHierarchy,
            isPresentationComplete: true,
            stableChecks: stableChecks
        )
    }
}

/// Owns the stable, ordinary source window used by every normal WKWebView.
///
/// The host frame, ordering and active WebView are frozen from the first
/// enteringFullscreen notification until WebKit has put the same WebView back
/// in this source hierarchy and its fullscreen presentation window is gone.
@MainActor
final class FullscreenSourceHostController {
    static let sourceWindowCollectionBehavior: NSWindow.CollectionBehavior = [
        .managed,
        // The source window carries the actual WKWebView. It must join the
        // shell when the host application enters a new full-screen Space after
        // FloatTabs is already visible; otherwise only the shell frame/rail is
        // composited in that Space while the page remains behind in the old one.
        .canJoinAllSpaces,
        .canJoinAllApplications,
    ]

    /// During WebKit element fullscreen the source window is hidden and kept
    /// only as WebKit's restore owner. Do not use this behavior for ordinary
    /// presentation: `fullScreenNone` describes a window that does not support
    /// fullscreen participation, while the normal source must join another
    /// application's fullscreen Space.
    static let webKitFullscreenSourceWindowCollectionBehavior: NSWindow.CollectionBehavior = [
        .managed,
        .fullScreenNone,
    ]

    let window: FullscreenSourceWindow
    let companionContainer = WebPanelContainerView()
    let railFoldControl = RailFoldControl()

    var transientUIContainerView: NSView {
        window.contentView!
    }

    private let container: WebPanelContainerView
    private weak var shellWindow: NSWindow?
    private weak var observedWebView: WKWebView?
    private weak var fullscreenPresentationWindow: NSWindow?
    private var fullscreenObservation: NSKeyValueObservation?
    private var restoreGeneration = 0
    private var restoreStartedAtUptime: TimeInterval?
    private(set) var sessionState: FullscreenSourceSessionState = .idle

    /// Rail collapse reclaims the rail's physical column without touching the
    /// shell frame: the source window shifts to the collapsed leading inset
    /// and widens by the reclaimed width. Like every other frame input it is
    /// frozen while a fullscreen session owns the source, and the post-restore
    /// sync reapplies it automatically.
    var railLeadingInset: CGFloat = PanelMetrics.externalControlZoneWidth

    var onSessionLockChange: ((Bool) -> Void)?
    var onSessionStateChange: ((FullscreenSourceSessionState) -> Void)?
    var onSourceRebuildRequired: (() -> Void)?

    var isSessionLocked: Bool {
        sessionState.locksSourceHost
    }

    init(
        container: WebPanelContainerView,
        resizeHandle: PanelResizeHandleView,
        resizeReadout: ResizeReadoutView,
        shellWindow: NSWindow
    ) {
        self.container = container
        self.shellWindow = shellWindow
        window = Self.makeSourceWindow(
            frame: NSRect(x: 0, y: 0, width: 1, height: 1)
        )
        window.contentView = FullscreenSourceRootView(
            container: container,
            railFoldControl: railFoldControl,
            resizeHandle: resizeHandle,
            resizeReadout: resizeReadout,
            shellWindow: shellWindow
        )
        attachSourceWindowToShell()
    }

    deinit {
        fullscreenObservation?.invalidate()
    }

    func synchronizeFrame(with shellWindow: NSWindow, display: Bool, animated: Bool = false) {
        guard !isSessionLocked else { return }
        let target = Self.sourceFrame(
            forShellFrame: shellWindow.frame,
            leadingInset: railLeadingInset
        )
        guard !Self.approximatelyEqual(window.frame, target) else { return }
        if animated {
            // The visible content lives in this window, so its frame change is
            // the user-visible half of the collapse animation. Match the rail
            // fade's duration and timing so page and rail move as one.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = ExternalTabMetrics.railFoldAnimationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(target, display: display)
            }
        } else {
            window.setFrame(target, display: display)
        }
    }

    func orderFrontAndFocus(
        _ webView: WKWebView?,
        makeSourceWindowMain: Bool = false
    ) {
        guard !isSessionLocked else { return }
        window.collectionBehavior = Self.sourceWindowCollectionBehavior
        attachSourceWindowToShell()
        window.alphaValue = 1
        window.ignoresMouseEvents = false
        // The shell and WebKit source are separate windows. Ordering only the
        // shell across applications can leave this actual hit-testing surface
        // behind the previously active app, making the page appear present but
        // unable to receive clicks or keyboard focus.
        window.orderFrontRegardless()
        if let webView {
            observeFullscreenState(of: webView)
            window.makeKeyAndOrderFront(nil)
            if makeSourceWindowMain {
                // WebKit chooses the element-fullscreen display from the
                // source window's AppKit main/key context. The source frame
                // has already been positioned by PanelController on the
                // user's invocation display. Limit makeMain to explicit user
                // presentation; restore callbacks must not change AppKit's
                // main-window transaction while WebKit tears down its Space.
                window.makeMain()
            }
            WebViewFocus.focus(webView, in: window)
        }
    }

    /// Reassert the source window after Mission Control creates or activates
    /// another application's fullscreen Space. AppKit normally applies the
    /// collection flags lazily, but a child window that was already ordered can
    /// remain tied to the previous Space. Reordering the actual WKWebView host
    /// (without activating FloatTabs) repairs that stale window membership.
    func reconcileVisiblePresentationAfterSpaceChange() {
        guard !isSessionLocked,
              window.isVisible,
              let shellWindow,
              shellWindow.isVisible else {
            return
        }

        let wasAttachedToShell = window.parent === shellWindow
        if wasAttachedToShell {
            shellWindow.removeChildWindow(window)
        }
        window.collectionBehavior = Self.sourceWindowCollectionBehavior
        window.orderFrontRegardless()
        if wasAttachedToShell {
            shellWindow.addChildWindow(window, ordered: .above)
        }

        fullscreenExperimentLog(
            "SPACE_RECONCILE shell=\(shellWindow.windowNumber) "
                + "source=\(window.windowNumber) "
                + "sourceScreen=\(fullscreenExperimentScreenID(window.screen))"
        )
    }

    /// Keep the separately hosted Web surface at the same application-level
    /// z-order as the shell. Changing WebKit's source window while it owns an
    /// element-fullscreen session is intentionally deferred until restoration.
    func setPinnedPresentation(_ isPinned: Bool) {
        guard !isSessionLocked else { return }
        window.level = FloatTabsWindowLevel.presentation(isPinned: isPinned)
    }

    func orderOutIfSafe() {
        guard !isSessionLocked else { return }
        window.alphaValue = 1
        window.ignoresMouseEvents = false
        window.collectionBehavior = Self.sourceWindowCollectionBehavior
        window.orderOut(nil)
    }

    func requestFullscreenExit() {
        guard isSessionLocked, let webView = observedWebView else { return }

        let script = """
        (() => {
            if (document.fullscreenElement && typeof document.exitFullscreen === 'function') {
                document.exitFullscreen();
                return true;
            }
            if (document.webkitFullscreenElement
                && typeof document.webkitExitFullscreen === 'function') {
                document.webkitExitFullscreen();
                return true;
            }
            return false;
        })()
        """
        webView.evaluateJavaScript(script) { [weak webView] result, _ in
            guard result as? Bool != true else { return }
            webView?.closeAllMediaPresentations(completionHandler: nil)
        }
    }

    func observeFullscreenState(of webView: WKWebView) {
        if observedWebView === webView { return }

        // Never swap the observation target while WebKit still owns the active
        // source view. Tab changes are queued by PanelController until restore.
        guard !isSessionLocked else { return }

        fullscreenObservation?.invalidate()
        observedWebView = webView
        fullscreenObservation = webView.observe(\.fullscreenState, options: [.new]) {
            [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, let webView = self.observedWebView else { return }
                self.handleFullscreenStateChange(of: webView)
            }
        }

        handleFullscreenStateChange(of: webView)
    }

    static func sourceFrame(
        forShellFrame frame: NSRect,
        leadingInset: CGFloat = PanelMetrics.externalControlZoneWidth
    ) -> NSRect {
        let gutter = PanelMetrics.outerInteractionGutter
        return NSRect(
            x: frame.minX + leadingInset,
            y: frame.minY + gutter,
            width: max(frame.width - leadingInset - gutter, 1),
            height: max(frame.height - 2 * gutter, 1)
        )
    }

    /// Prefer the exact fullscreen window observed while WebKit owns the WebView.
    /// The class-name scan is only a passive fallback for transitions where the
    /// KVO callback arrives before AppKit has exposed that window on `webView`.
    static func isWebKitFullscreenPresentationActive(
        capturedWindow: NSWindow?,
        applicationWindows: [NSWindow]
    ) -> Bool {
        if let capturedWindow, capturedWindow.isVisible {
            return true
        }
        return applicationWindows.contains { candidate in
            candidate.isVisible
                && String(describing: type(of: candidate)).contains("WebCoreFullScreenWindow")
        }
    }

    private static func makeSourceWindow(frame: NSRect) -> FullscreenSourceWindow {
        let sourceWindow = FullscreenSourceWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        sourceWindow.isReleasedWhenClosed = false
        sourceWindow.hidesOnDeactivate = false
        sourceWindow.level = .normal
        sourceWindow.collectionBehavior = sourceWindowCollectionBehavior
        sourceWindow.backgroundColor = .clear
        sourceWindow.isOpaque = false
        sourceWindow.hasShadow = false
        sourceWindow.contentMinSize = NSSize(width: 1, height: 1)
        return sourceWindow
    }

    private func handleFullscreenStateChange(of webView: WKWebView) {
        let previous = sessionState
        let next = FullscreenSourceSessionState.next(
            from: sessionState,
            webKitState: webView.fullscreenState
        )
        let wasLocked = isSessionLocked
        sessionState = next
        onSessionStateChange?(next)

        if !wasLocked, next.locksSourceHost {
            fullscreenPresentationWindow = nil
            // In ordinary presentation the source is a child of the shell so
            // Mission Control treats the rail, outline and Web surface as one
            // window group. Detach before hiding the shell: WebKit must keep
            // its source window independently ordered throughout fullscreen.
            detachSourceWindowFromShell()
            window.collectionBehavior = Self.webKitFullscreenSourceWindowCollectionBehavior
            // Preserve the ordered source and hierarchy WebKit needs for
            // restoration without exposing its tab-less placeholder window.
            window.alphaValue = 0
            window.ignoresMouseEvents = true
            restoreGeneration &+= 1
            fullscreenExperimentLog(
                "FULLSCREEN state=\(next.rawValue) source=\(window.windowNumber) "
                    + "screen=\(fullscreenExperimentScreenID(window.screen))"
            )
            onSessionLockChange?(true)
        }

        captureFullscreenPresentationWindowIfNeeded(for: webView)

        guard next == .restoring else { return }
        if previous != .restoring {
            restoreStartedAtUptime = ProcessInfo.processInfo.systemUptime
        }
        waitForPublicSourceRestoration(
            of: webView,
            generation: restoreGeneration,
            stableChecks: 0
        )
    }

    private func captureFullscreenPresentationWindowIfNeeded(for webView: WKWebView) {
        guard let actualWindow = webView.window,
              actualWindow !== window else {
            return
        }
        fullscreenPresentationWindow = actualWindow
    }

    private func waitForPublicSourceRestoration(
        of webView: WKWebView,
        generation: Int,
        stableChecks: Int
    ) {
        guard generation == restoreGeneration,
              observedWebView === webView,
              sessionState == .restoring else {
            return
        }

        let isBackInSourceHierarchy = webView.fullscreenState == .notInFullscreen
            && webView.window === window
            && container.window === window
            && webView.isDescendant(of: container)
        let isPresentationComplete = !Self.isWebKitFullscreenPresentationActive(
            capturedWindow: fullscreenPresentationWindow,
            applicationWindows: NSApp.windows
        )

        let elapsed = ProcessInfo.processInfo.systemUptime
            - (restoreStartedAtUptime ?? ProcessInfo.processInfo.systemUptime)
        let decision = FullscreenRestoreWatchdog.decision(
            elapsed: elapsed,
            isBackInSourceHierarchy: isBackInSourceHierarchy,
            isPresentationComplete: isPresentationComplete,
            stableChecks: stableChecks
        )

        switch decision {
        case let .poll(nextStableChecks, delay):
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.waitForPublicSourceRestoration(
                    of: webView,
                    generation: generation,
                    stableChecks: nextStableChecks
                )
            }
            return

        case .rebuildSource:
            fullscreenExperimentLog(
                "FULLSCREEN_RESTORE_TIMEOUT source=\(window.windowNumber) "
                    + "screen=\(fullscreenExperimentScreenID(window.screen))"
            )
            finishRestoration(rebuildSource: true)

        case .restored:
            finishRestoration(rebuildSource: false)
        }
    }

    private func finishRestoration(rebuildSource: Bool) {
        sessionState = .idle
        restoreStartedAtUptime = nil
        fullscreenPresentationWindow = nil
        window.collectionBehavior = Self.sourceWindowCollectionBehavior
        window.alphaValue = 1
        window.ignoresMouseEvents = false
        if rebuildSource {
            onSourceRebuildRequired?()
        }
        fullscreenExperimentLog(
            "FULLSCREEN_RESTORED source=\(window.windowNumber) "
                + "screen=\(fullscreenExperimentScreenID(window.screen))"
        )

        // PanelController owns the post-fullscreen presentation decision. A
        // hidden restore may order the source window out inside this callback;
        // reattaching it unconditionally afterwards can order that source above
        // the shell again and recreate a physical-visible/logical-hidden split.
        // Visible restores already reattach through orderFrontAndFocus().
        onSessionLockChange?(false)
    }

    private func attachSourceWindowToShell() {
        guard !isSessionLocked,
              let shellWindow,
              window.parent !== shellWindow else {
            return
        }
        window.parent?.removeChildWindow(window)
        shellWindow.addChildWindow(window, ordered: .above)
    }

    private func detachSourceWindowFromShell() {
        window.parent?.removeChildWindow(window)
    }

    private static func approximatelyEqual(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < 0.5
            && abs(lhs.origin.y - rhs.origin.y) < 0.5
            && abs(lhs.size.width - rhs.size.width) < 0.5
            && abs(lhs.size.height - rhs.size.height) < 0.5
    }
}
