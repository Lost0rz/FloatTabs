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
        guard bounds.contains(point) else { return nil }
        return Self.dragRects(in: bounds).contains(where: { $0.contains(point) }) ? self : nil
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

/// Keeps the normal WebKit restore path unchanged while bounding the one failure
/// mode that previously polled at 20 Hz forever: WebKit reports that fullscreen
/// ended but never puts the source view back into FloatTabs' public hierarchy.
struct FullscreenRestoreWatchdog {
    static let pollInterval: TimeInterval = 0.05
    static let sourceRebuildTimeout: TimeInterval = 10
    static let requiredStableChecks = 3

    static func decision(
        elapsed: TimeInterval,
        isBackInSourceHierarchy: Bool,
        stableChecks: Int
    ) -> FullscreenRestoreWatchdogDecision {
        if isBackInSourceHierarchy {
            let nextStableChecks = stableChecks + 1
            return nextStableChecks >= requiredStableChecks
                ? .restored
                : .poll(stableChecks: nextStableChecks, delay: pollInterval)
        }

        if elapsed >= sourceRebuildTimeout {
            return .rebuildSource
        }

        return .poll(stableChecks: 0, delay: pollInterval)
    }
}

/// Owns the stable, ordinary source window used by every normal WKWebView.
///
/// The host frame, ordering and active WebView are frozen from the first
/// enteringFullscreen notification until WebKit has publicly reported
/// notInFullscreen *and* put the same WebView back in this source hierarchy.
@MainActor
final class FullscreenSourceHostController {
    static let sourceWindowCollectionBehavior: NSWindow.CollectionBehavior = [
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
    private var fullscreenObservation: NSKeyValueObservation?
    private var restoreGeneration = 0
    private var restoreStartedAtUptime: TimeInterval?
    private(set) var sessionState: FullscreenSourceSessionState = .idle

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

    func synchronizeFrame(with shellWindow: NSWindow, display: Bool) {
        guard !isSessionLocked else { return }
        let target = Self.sourceFrame(forShellFrame: shellWindow.frame)
        guard !Self.approximatelyEqual(window.frame, target) else { return }
        window.setFrame(target, display: display)
    }

    func orderFrontAndFocus(_ webView: WKWebView?) {
        guard !isSessionLocked else { return }
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
            WebViewFocus.focus(webView, in: window)
        }
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

    static func sourceFrame(forShellFrame frame: NSRect) -> NSRect {
        let gutter = PanelMetrics.outerInteractionGutter
        let controlWidth = PanelMetrics.externalControlZoneWidth
        return NSRect(
            x: frame.minX + controlWidth,
            y: frame.minY + gutter,
            width: max(frame.width - controlWidth - gutter, 1),
            height: max(frame.height - 2 * gutter, 1)
        )
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
            // In ordinary presentation the source is a child of the shell so
            // Mission Control treats the rail, outline and Web surface as one
            // window group. Detach before hiding the shell: WebKit must keep
            // its source window independently ordered throughout fullscreen.
            detachSourceWindowFromShell()
            window.collectionBehavior = Self.sourceWindowCollectionBehavior
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

        let elapsed = ProcessInfo.processInfo.systemUptime
            - (restoreStartedAtUptime ?? ProcessInfo.processInfo.systemUptime)
        let decision = FullscreenRestoreWatchdog.decision(
            elapsed: elapsed,
            isBackInSourceHierarchy: isBackInSourceHierarchy,
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
        window.alphaValue = 1
        window.ignoresMouseEvents = false
        if rebuildSource {
            onSourceRebuildRequired?()
        }
        fullscreenExperimentLog(
            "FULLSCREEN_RESTORED source=\(window.windowNumber) "
                + "screen=\(fullscreenExperimentScreenID(window.screen))"
        )
        onSessionLockChange?(false)
        // The callback has rebuilt/repositioned the normal hierarchy. Restore
        // the parent-child relationship only after that atomic presentation.
        attachSourceWindowToShell()
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
