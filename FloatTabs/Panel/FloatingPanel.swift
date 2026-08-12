import AppKit
import WebKit

private final class WebContentHostWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

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
    private var fullscreenWindowScreenObservation: NSObjectProtocol?
    private var webHostWindow: WebContentHostWindow?
    private var shellRestoreGeneration = 0

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

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
        // NSApp.activate() before focusing the active WKWebView.
        becomesKeyOnlyIfNeeded = true
        acceptsMouseMovedEvents = true

        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovableByWindowBackground = false

        contentMinSize = PanelMetrics.minimumPanelSize
        minSize = PanelMetrics.minimumPanelSize

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shellGeometryDidChange(_:)),
            name: NSWindow.didMoveNotification,
            object: self
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shellGeometryDidChange(_:)),
            name: NSWindow.didResizeNotification,
            object: self
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shellGeometryDidChange(_:)),
            name: NSWindow.didChangeScreenNotification,
            object: self
        )

        resetHostReport()
        appendHostReport(
            "START baseline=dad0ee79e6b70d07e659814aefde6d4f4701e221 "
                + "mode=normal_tabs_ordinary_web_host_no_rebuild_no_reload"
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        fullscreenObservation?.invalidate()
        removeFullscreenWindowScreenObservation()
        webHostWindow?.orderOut(nil)
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        installWebHostIfNeeded()

        if isNativeFullscreenSessionActive {
            // A stable fullscreen WebView keeps its ordinary source host frozen.
            // The shell may still be summoned on another display, but it must not
            // pull the source host or steal focus from WebKit fullscreen.
            super.orderFront(sender)
            appendHostReport(
                "SHELL_SUMMON_DURING_FULLSCREEN shell_screen={\(screenSummary(screen))} "
                    + "host_screen={\(screenSummary(webHostWindow?.screen))}"
            )
            return
        }

        synchronizeWebHostFrameIfSafe(trigger: "show")
        super.orderFront(sender)

        if let webHostWindow {
            webHostWindow.orderFront(nil)
            appendHostReport(
                "SHOW shell_screen={\(screenSummary(screen))} "
                    + "host_screen={\(screenSummary(webHostWindow.screen))} "
                    + "host_frame=\(NSStringFromRect(webHostWindow.frame))"
            )
        }
    }

    override func orderOut(_ sender: Any?) {
        if !isNativeFullscreenSessionActive {
            webHostWindow?.orderOut(nil)
        }
        super.orderOut(sender)
    }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        installWebHostIfNeeded()

        guard let webView = responder as? WKWebView else {
            return super.makeFirstResponder(responder)
        }

        observeFullscreenState(of: webView)

        guard webView.fullscreenState == .notInFullscreen,
              let webHostWindow,
              webView.window === webHostWindow else {
            appendHostReport(
                "FOCUS_SKIPPED webview=\(identity(webView)) "
                    + "state=\(fullscreenStateName(webView.fullscreenState)) "
                    + "webview_window=\(windowClassName(webView.window))"
            )
            return false
        }

        synchronizeWebHostFrameIfSafe(trigger: "focus")
        webHostWindow.makeKeyAndOrderFront(nil)
        let accepted = webHostWindow.makeFirstResponder(webView)
        appendHostReport(
            "FOCUS webview=\(identity(webView)) accepted=\(accepted) "
                + "host_key=\(webHostWindow.isKeyWindow) host_main=\(webHostWindow.isMainWindow) "
                + "host_screen={\(screenSummary(webHostWindow.screen))}"
        )
        return accepted
    }

    @objc private func shellGeometryDidChange(_ notification: Notification) {
        synchronizeWebHostFrameIfSafe(trigger: "shell_geometry")
    }

    private var isNativeFullscreenSessionActive: Bool {
        guard let fullscreenObservedWebView else { return false }
        return fullscreenObservedWebView.fullscreenState != .notInFullscreen
    }

    /// The normal product WebPanelContainerView is detached from the NSPanel and
    /// hosted by a plain borderless NSWindow. The same persistent WKWebView stays
    /// inside that container; no reload/rebuild/recovery path is introduced.
    private func installWebHostIfNeeded() {
        guard webHostWindow == nil,
              let rootView = contentView as? PanelRootView else {
            return
        }

        rootView.layoutSubtreeIfNeeded()
        let container = rootView.webPanelContainerView
        guard container.superview != nil else { return }

        let hostFrame = desiredWebHostFrame()
        container.removeFromSuperview()
        container.translatesAutoresizingMaskIntoConstraints = true
        container.autoresizingMask = [.width, .height]

        let host = WebContentHostWindow(
            contentRect: hostFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        host.isReleasedWhenClosed = false
        host.hidesOnDeactivate = false
        host.backgroundColor = .windowBackgroundColor
        host.isOpaque = true
        host.hasShadow = false
        // Keep the host at the same ordinary product presentation level for this
        // narrow experiment, but it is an NSWindow rather than NSPanel and it does
        // not opt into fullScreenAuxiliary.
        host.level = .floating
        host.collectionBehavior = [
            .canJoinAllSpaces,
            .canJoinAllApplications,
            .ignoresCycle,
        ]
        host.contentMinSize = NSSize(width: 1, height: 1)
        host.contentView = container
        container.frame = NSRect(origin: .zero, size: host.contentLayoutRect.size)

        webHostWindow = host
        rootView.needsLayout = true
        rootView.layoutSubtreeIfNeeded()

        appendHostReport(
            "WEB_HOST_INSTALLED class=\(windowClassName(host)) "
                + "shell_frame=\(NSStringFromRect(frame)) host_frame=\(NSStringFromRect(host.frame)) "
                + "shell_screen={\(screenSummary(screen))} host_screen={\(screenSummary(host.screen))}"
        )
    }

    private func desiredWebHostFrame() -> NSRect {
        let outer = PanelMetrics.outerInteractionGutter
        let left = PanelMetrics.externalControlZoneWidth
        return NSRect(
            x: frame.minX + left,
            y: frame.minY + outer,
            width: max(frame.width - left - outer, 1),
            height: max(frame.height - 2 * outer, 1)
        )
    }

    private func synchronizeWebHostFrameIfSafe(trigger: String) {
        guard let webHostWindow else { return }
        guard !isNativeFullscreenSessionActive else {
            appendHostReport(
                "HOST_MOVE_FROZEN trigger=\(trigger) shell_screen={\(screenSummary(screen))} "
                    + "host_screen={\(screenSummary(webHostWindow.screen))}"
            )
            return
        }

        let target = desiredWebHostFrame()
        if !rectApproximatelyEqual(webHostWindow.frame, target) {
            let oldFrame = webHostWindow.frame
            webHostWindow.setFrame(target, display: false)
            appendHostReport(
                "HOST_MOVED trigger=\(trigger) old_frame=\(NSStringFromRect(oldFrame)) "
                    + "new_frame=\(NSStringFromRect(target)) "
                    + "shell_screen={\(screenSummary(screen))} host_screen={\(screenSummary(webHostWindow.screen))}"
            )
        }
    }

    private func rectApproximatelyEqual(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < 0.5
            && abs(lhs.origin.y - rhs.origin.y) < 0.5
            && abs(lhs.size.width - rhs.size.width) < 0.5
            && abs(lhs.size.height - rhs.size.height) < 0.5
    }

    private func observeFullscreenState(of webView: WKWebView) {
        if fullscreenObservedWebView === webView { return }

        if let current = fullscreenObservedWebView,
           current.fullscreenState != .notInFullscreen {
            appendHostReport(
                "OBSERVATION_SWITCH_DEFERRED current=\(identity(current)) "
                    + "state=\(fullscreenStateName(current.fullscreenState)) requested=\(identity(webView))"
            )
            return
        }

        fullscreenObservation?.invalidate()
        removeFullscreenWindowScreenObservation()
        fullscreenObservedWebView = webView

        appendHostReport(
            "OBSERVE webview=\(identity(webView)) state=\(fullscreenStateName(webView.fullscreenState)) "
                + "host_screen={\(screenSummary(webHostWindow?.screen))} "
                + "host_key=\(webHostWindow?.isKeyWindow ?? false) "
                + "host_main=\(webHostWindow?.isMainWindow ?? false)"
        )

        fullscreenObservation = webView.observe(\.fullscreenState, options: [.new]) { [weak self, weak webView] _, _ in
            DispatchQueue.main.async {
                guard let self, let webView, self.fullscreenObservedWebView === webView else { return }
                self.handleFullscreenStateChange(of: webView)
            }
        }
    }

    private func handleFullscreenStateChange(of webView: WKWebView) {
        let state = webView.fullscreenState
        let actualWindow = webView.window
        let hostScreen = webHostWindow?.screen
        let actualScreen = actualWindow?.screen

        appendHostReport(
            "FULLSCREEN_STATE state=\(fullscreenStateName(state)) webview=\(identity(webView)) "
                + "host_screen={\(screenSummary(hostScreen))} "
                + "actual_window=\(windowClassName(actualWindow)) "
                + "actual_screen={\(screenSummary(actualScreen))} "
                + "shell_screen={\(screenSummary(screen))}"
        )

        switch state {
        case .enteringFullscreen:
            cancelDeferredShellRestore()
            // Freeze source-host geometry for the complete native fullscreen
            // session. No host reparent/move is allowed from this point onward.

        case .inFullscreen:
            cancelDeferredShellRestore()
            collectionBehavior = Self.nativeFullscreenCollectionBehavior
            level = .normal

            if let actualWindow,
               String(describing: type(of: actualWindow)).contains("WebCoreFullScreenWindow") {
                installFullscreenWindowScreenObservation(actualWindow, webView: webView)
            }

            if screenNumber(hostScreen) == screenNumber(actualScreen) {
                appendHostReport(
                    "SAME_DISPLAY_FULLSCREEN_PASS screen={\(screenSummary(actualScreen))}"
                )
            } else {
                appendHostReport(
                    "CROSS_DISPLAY_FULLSCREEN_DETECTED host={\(screenSummary(hostScreen))} "
                        + "actual={\(screenSummary(actualScreen))}"
                )
            }

        case .exitingFullscreen:
            cancelDeferredShellRestore()

        case .notInFullscreen:
            removeFullscreenWindowScreenObservation()
            restoreOrdinaryPresentationWhenFullscreenWindowIsGone(webView: webView)

        @unknown default:
            break
        }
    }

    private func installFullscreenWindowScreenObservation(_ fullscreenWindow: NSWindow, webView: WKWebView) {
        removeFullscreenWindowScreenObservation()
        fullscreenWindowScreenObservation = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: fullscreenWindow,
            queue: .main
        ) { [weak self, weak webView, weak fullscreenWindow] _ in
            guard let self, let webView, let fullscreenWindow,
                  self.fullscreenObservedWebView === webView,
                  webView.fullscreenState == .inFullscreen else {
                return
            }
            self.appendHostReport(
                "FULLSCREEN_SCREEN_CHANGED webview=\(self.identity(webView)) "
                    + "host={\(self.screenSummary(self.webHostWindow?.screen))} "
                    + "actual={\(self.screenSummary(fullscreenWindow.screen))}"
            )
        }
    }

    private func removeFullscreenWindowScreenObservation() {
        if let fullscreenWindowScreenObservation {
            NotificationCenter.default.removeObserver(fullscreenWindowScreenObservation)
            self.fullscreenWindowScreenObservation = nil
        }
    }

    private func cancelDeferredShellRestore() {
        shellRestoreGeneration &+= 1
    }

    private func restoreOrdinaryPresentationWhenFullscreenWindowIsGone(webView: WKWebView) {
        shellRestoreGeneration &+= 1
        let generation = shellRestoreGeneration
        pollForFullscreenWindowExit(
            generation: generation,
            attemptsRemaining: 200,
            webView: webView
        )
    }

    private func pollForFullscreenWindowExit(
        generation: Int,
        attemptsRemaining: Int,
        webView: WKWebView
    ) {
        guard generation == shellRestoreGeneration,
              fullscreenObservedWebView === webView,
              webView.fullscreenState == .notInFullscreen else {
            return
        }

        if !hasVisibleWebCoreFullscreenWindow() {
            collectionBehavior = Self.ordinaryCollectionBehavior
            level = .floating
            synchronizeWebHostFrameIfSafe(trigger: "fullscreen_exit")

            if isVisible {
                webHostWindow?.orderFront(nil)
            } else {
                webHostWindow?.orderOut(nil)
            }

            appendHostReport(
                "FULLSCREEN_EXIT_STABLE webview=\(identity(webView)) "
                    + "shell_screen={\(screenSummary(screen))} "
                    + "host_screen={\(screenSummary(webHostWindow?.screen))}"
            )
            return
        }

        guard attemptsRemaining > 0 else {
            appendHostReport(
                "FULLSCREEN_EXIT_WAIT_EXHAUSTED webview=\(identity(webView))"
            )
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak webView] in
            guard let self, let webView else { return }
            self.pollForFullscreenWindowExit(
                generation: generation,
                attemptsRemaining: attemptsRemaining - 1,
                webView: webView
            )
        }
    }

    private func hasVisibleWebCoreFullscreenWindow() -> Bool {
        NSApp.windows.contains { candidate in
            candidate.isVisible
                && String(describing: type(of: candidate)).contains("WebCoreFullScreenWindow")
        }
    }

    private func fullscreenStateName(_ state: WKWebView.FullscreenState) -> String {
        switch state {
        case .notInFullscreen: return "notInFullscreen"
        case .enteringFullscreen: return "enteringFullscreen"
        case .inFullscreen: return "inFullscreen"
        case .exitingFullscreen: return "exitingFullscreen"
        @unknown default: return "unknown"
        }
    }

    private func identity(_ webView: WKWebView) -> String {
        String(format: "%p", Int(bitPattern: Unmanaged.passUnretained(webView).toOpaque()))
    }

    private func windowClassName(_ window: NSWindow?) -> String {
        guard let window else { return "nil" }
        return String(describing: type(of: window))
    }

    private func screenNumber(_ screen: NSScreen?) -> UInt32? {
        guard let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return number.uint32Value
    }

    private func screenSummary(_ screen: NSScreen?) -> String {
        guard let screen else { return "nil" }
        return "name=\(screen.localizedName),number=\(screenNumber(screen).map(String.init) ?? "nil"),frame=\(NSStringFromRect(screen.frame))"
    }

    private var hostReportURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .appendingPathComponent("FloatTabs-Ordinary-WebHost-Report.txt")
    }

    private func resetHostReport() {
        let header = """
        FloatTabs Ordinary Web Host Fullscreen Test
        ============================================
        Baseline: dad0ee79e6b70d07e659814aefde6d4f4701e221
        Path: normal production Tabs / persistent WKWebView
        Shell: NSPanel
        Web content source: ordinary borderless NSWindow
        Repair/rebuild/reload: none
        WebCore fullscreen-window mutation: none

        """
        try? header.write(to: hostReportURL, atomically: true, encoding: .utf8)
    }

    private func appendHostReport(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: hostReportURL.path) {
            FileManager.default.createFile(atPath: hostReportURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: hostReportURL) else { return }
        defer { try? handle.close() }
        try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}
