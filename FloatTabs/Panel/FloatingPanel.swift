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
    private var fullscreenWindowScreenObservation: NSObjectProtocol?
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

        resetAffinityReport()
        appendAffinityReport(
            "START baseline=dad0ee79e6b70d07e659814aefde6d4f4701e221 "
                + "mode=normal_tabs_no_rebuild_no_reload"
        )
    }

    deinit {
        fullscreenObservation?.invalidate()
        removeFullscreenWindowScreenObservation()
    }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        if let webView = responder as? WKWebView {
            observeFullscreenState(of: webView)
        }
        return super.makeFirstResponder(responder)
    }

    /// This experiment keeps the normal production Tab/WebView path intact.
    /// A successful native fullscreen may land on a different display than the
    /// source panel. Once WebKit reaches stable native fullscreen, move only the
    /// source panel's ordinary return location to the actual fullscreen display.
    /// The WKWebView remains WebKit-owned throughout the fullscreen session.
    private func observeFullscreenState(of webView: WKWebView) {
        if fullscreenObservedWebView === webView {
            return
        }

        if let current = fullscreenObservedWebView,
           current.fullscreenState != .notInFullscreen {
            appendAffinityReport(
                "OBSERVATION_SWITCH_DEFERRED current=\(identity(current)) "
                    + "state=\(fullscreenStateName(current.fullscreenState)) "
                    + "requested=\(identity(webView))"
            )
            return
        }

        fullscreenObservation?.invalidate()
        removeFullscreenWindowScreenObservation()
        fullscreenObservedWebView = webView
        appendAffinityReport(
            "OBSERVE webview=\(identity(webView)) source_screen={\(screenSummary(screen))} "
                + "state=\(fullscreenStateName(webView.fullscreenState))"
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
        let fullscreenWindow = webView.window
        appendAffinityReport(
            "FULLSCREEN_STATE state=\(fullscreenStateName(state)) "
                + "webview=\(identity(webView)) source_screen={\(screenSummary(screen))} "
                + "webview_window=\(String(describing: type(of: fullscreenWindow))) "
                + "actual_screen={\(screenSummary(fullscreenWindow?.screen))}"
        )

        switch state {
        case .enteringFullscreen:
            cancelDeferredShellRestore()
            // Do not move the source while WebKit is constructing its fullscreen
            // presentation. The actual target screen is authoritative only after
            // WebKit reports stable inFullscreen.

        case .inFullscreen:
            cancelDeferredShellRestore()
            collectionBehavior = Self.nativeFullscreenCollectionBehavior
            level = .normal

            if let fullscreenWindow,
               String(describing: type(of: fullscreenWindow)).contains("WebCoreFullScreenWindow") {
                installFullscreenWindowScreenObservation(fullscreenWindow, webView: webView)
            }

            if let actualScreen = fullscreenWindow?.screen {
                followFullscreenDisplay(actualScreen, trigger: "entered")
            }

        case .exitingFullscreen:
            cancelDeferredShellRestore()
            // Keep the source panel on its current affinity display and keep the
            // shell out of the dying fullscreen Space until WebKit has finished.

        case .notInFullscreen:
            removeFullscreenWindowScreenObservation()
            restoreOrdinaryShellPresentationWhenFullscreenWindowIsGone()

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
                  webView.fullscreenState == .inFullscreen,
                  let actualScreen = fullscreenWindow.screen else {
                return
            }
            self.appendAffinityReport(
                "FULLSCREEN_SCREEN_CHANGED webview=\(self.identity(webView)) "
                    + "actual_screen={\(self.screenSummary(actualScreen))}"
            )
            self.followFullscreenDisplay(actualScreen, trigger: "screen_changed")
        }
    }

    private func removeFullscreenWindowScreenObservation() {
        if let fullscreenWindowScreenObservation {
            NotificationCenter.default.removeObserver(fullscreenWindowScreenObservation)
            self.fullscreenWindowScreenObservation = nil
        }
    }

    /// Move only the normal source panel. Never move, resize, hide, order out,
    /// or otherwise steer WebKit's WebCoreFullScreenWindow.
    private func followFullscreenDisplay(_ targetScreen: NSScreen, trigger: String) {
        let targetNumber = screenNumber(targetScreen)
        let sourceNumber = screenNumber(screen)
        guard targetNumber != nil, targetNumber != sourceNumber else {
            appendAffinityReport(
                "SOURCE_AFFINITY_UNCHANGED trigger=\(trigger) screen={\(screenSummary(targetScreen))}"
            )
            return
        }

        let oldFrame = frame
        let sourceFrame = screen?.visibleFrame ?? oldFrame
        let targetFrame = targetScreen.visibleFrame

        let relativeX = sourceFrame.width > 1
            ? (oldFrame.midX - sourceFrame.minX) / sourceFrame.width
            : 0.5
        let relativeY = sourceFrame.height > 1
            ? (oldFrame.midY - sourceFrame.minY) / sourceFrame.height
            : 0.5

        let proposed = NSRect(
            x: targetFrame.minX + relativeX * targetFrame.width - oldFrame.width / 2,
            y: targetFrame.minY + relativeY * targetFrame.height - oldFrame.height / 2,
            width: oldFrame.width,
            height: oldFrame.height
        )
        let destination = ScreenPositioning.clampedFrame(proposed, to: targetFrame)

        setFrame(destination, display: false)
        appendAffinityReport(
            "SOURCE_AFFINITY_MOVED trigger=\(trigger) "
                + "from={\(screenSummaryForNumber(sourceNumber))} "
                + "to={\(screenSummary(targetScreen))} "
                + "old_frame=\(NSStringFromRect(oldFrame)) new_frame=\(NSStringFromRect(destination))"
        )
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
              observed.fullscreenState == .notInFullscreen else {
            return
        }

        if !hasVisibleWebCoreFullscreenWindow() {
            collectionBehavior = Self.ordinaryCollectionBehavior
            level = .floating
            appendAffinityReport(
                "SOURCE_RETURN_STABLE screen={\(screenSummary(screen))} "
                    + "webview=\(identity(observed))"
            )
            return
        }

        guard attemptsRemaining > 0 else {
            appendAffinityReport(
                "SOURCE_RETURN_WAIT_EXHAUSTED screen={\(screenSummary(screen))} "
                    + "webview=\(identity(observed))"
            )
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.pollForFullscreenWindowExit(
                generation: generation,
                attemptsRemaining: attemptsRemaining - 1
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

    private func screenSummaryForNumber(_ number: UInt32?) -> String {
        guard let number,
              let matched = NSScreen.screens.first(where: { screenNumber($0) == number }) else {
            return "number=\(number.map(String.init) ?? "nil")"
        }
        return screenSummary(matched)
    }

    private var affinityReportURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .appendingPathComponent("FloatTabs-Fullscreen-Affinity-Report.txt")
    }

    private func resetAffinityReport() {
        let header = """
        FloatTabs Native Fullscreen Source Affinity Test
        ================================================
        Baseline: dad0ee79e6b70d07e659814aefde6d4f4701e221
        Path: normal production Tabs / persistent WKWebView
        Repair/rebuild/reload: none
        WebCore fullscreen-window mutation: none

        """
        try? header.write(to: affinityReportURL, atomically: true, encoding: .utf8)
    }

    private func appendAffinityReport(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: affinityReportURL.path) {
            FileManager.default.createFile(atPath: affinityReportURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: affinityReportURL) else { return }
        defer { try? handle.close() }
        try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}