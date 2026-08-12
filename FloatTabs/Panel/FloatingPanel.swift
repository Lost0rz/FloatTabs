import AppKit
import Foundation
import WebKit

final class FloatingPanel: NSPanel {
    private static let fullscreenGatePollDelay: TimeInterval = 0.05
    private static let fullscreenGateRequiredStableChecks = 6
    private static let fullscreenGateMaximumChecks = 40

    private weak var fullscreenCandidateWebView: WKWebView?
    private var fullscreenObservation: NSKeyValueObservation?
    private var fullscreenGateObservers: [NSObjectProtocol] = []
    private var fullscreenGateGeneration = 0
    private var fullscreenGateStableChecks = 0

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
        collectionBehavior = [
            .canJoinAllSpaces,
            .canJoinAllApplications,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]

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

        installFullscreenGateObservers()
        resetFullscreenGateReport()
        appendFullscreenGateReport(
            "START baseline=dad0ee79e6b70d07e659814aefde6d4f4701e221 "
                + "mode=normal_tabs_same_display_gate"
        )
    }

    deinit {
        fullscreenObservation?.invalidate()
        for observer in fullscreenGateObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let webView = responder as? WKWebView
        if let webView {
            observeFullscreenState(of: webView)
            closeFullscreenGate(reason: "focus_transition")
        }

        let accepted = super.makeFirstResponder(responder)

        if accepted, webView != nil {
            restartFullscreenGate(reason: "webview_focused")
        }
        return accepted
    }

    private func installFullscreenGateObservers() {
        let center = NotificationCenter.default

        fullscreenGateObservers.append(
            center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: self,
                queue: .main
            ) { [weak self] _ in
                self?.restartFullscreenGate(reason: "did_become_key")
            }
        )

        fullscreenGateObservers.append(
            center.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: self,
                queue: .main
            ) { [weak self] _ in
                self?.closeFullscreenGate(reason: "did_resign_key")
            }
        )

        for name in [
            NSWindow.didMoveNotification,
            NSWindow.didResizeNotification,
            NSWindow.didChangeScreenNotification,
        ] {
            fullscreenGateObservers.append(
                center.addObserver(
                    forName: name,
                    object: self,
                    queue: .main
                ) { [weak self] notification in
                    self?.restartFullscreenGate(reason: notification.name.rawValue)
                }
            )
        }
    }

    /// Native element fullscreen remains entirely WebKit-owned. The only safety
    /// policy here is whether the page is temporarily eligible to request it.
    /// Every summon/move/focus transition closes the gate first. It reopens only
    /// after the FloatTabs panel and AppKit keyboard-focus screen agree for a
    /// short, continuous stability window.
    private func restartFullscreenGate(reason: String) {
        guard let webView = fullscreenCandidateWebView else { return }
        guard webView.fullscreenState == .notInFullscreen else { return }

        fullscreenGateGeneration &+= 1
        let generation = fullscreenGateGeneration
        fullscreenGateStableChecks = 0
        setElementFullscreenEnabled(false, on: webView, reason: "gate_closed:\(reason)")

        appendFullscreenGateReport(
            "GATE_RESTART reason=\(reason) shell={\(screenSummary(screen))} "
                + "main={\(screenSummary(NSScreen.main))} key=\(isKeyWindow)"
        )

        pollFullscreenGate(
            generation: generation,
            attemptsRemaining: Self.fullscreenGateMaximumChecks
        )
    }

    private func closeFullscreenGate(reason: String) {
        fullscreenGateGeneration &+= 1
        fullscreenGateStableChecks = 0

        guard let webView = fullscreenCandidateWebView,
              webView.fullscreenState == .notInFullscreen else {
            return
        }
        setElementFullscreenEnabled(false, on: webView, reason: "gate_closed:\(reason)")
    }

    private func pollFullscreenGate(generation: Int, attemptsRemaining: Int) {
        guard generation == fullscreenGateGeneration,
              let webView = fullscreenCandidateWebView,
              webView.fullscreenState == .notInFullscreen else {
            return
        }

        let shellScreen = screen
        let keyboardScreen = NSScreen.main
        let sameScreen = sameDisplay(shellScreen, keyboardScreen)
        let webViewStillHostedHere = webView.window === self
        let eligibleNow = isVisible
            && isKeyWindow
            && sameScreen
            && webViewStillHostedHere

        if eligibleNow {
            fullscreenGateStableChecks += 1
        } else {
            fullscreenGateStableChecks = 0
        }

        if fullscreenGateStableChecks >= Self.fullscreenGateRequiredStableChecks {
            setElementFullscreenEnabled(true, on: webView, reason: "gate_open_stable_same_display")
            appendFullscreenGateReport(
                "GATE_OPEN shell={\(screenSummary(shellScreen))} "
                    + "main={\(screenSummary(keyboardScreen))} "
                    + "stable_checks=\(fullscreenGateStableChecks)"
            )
            return
        }

        guard attemptsRemaining > 0 else {
            setElementFullscreenEnabled(false, on: webView, reason: "gate_timeout")
            appendFullscreenGateReport(
                "GATE_BLOCKED timeout shell={\(screenSummary(shellScreen))} "
                    + "main={\(screenSummary(keyboardScreen))} "
                    + "key=\(isKeyWindow) hosted=\(webViewStillHostedHere)"
            )
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fullscreenGatePollDelay) { [weak self] in
            self?.pollFullscreenGate(
                generation: generation,
                attemptsRemaining: attemptsRemaining - 1
            )
        }
    }

    private func observeFullscreenState(of webView: WKWebView) {
        guard fullscreenCandidateWebView !== webView else { return }

        fullscreenObservation?.invalidate()
        fullscreenCandidateWebView = webView
        setElementFullscreenEnabled(false, on: webView, reason: "new_candidate")

        fullscreenObservation = webView.observe(\.fullscreenState, options: [.new]) { [weak self, weak webView] _, _ in
            DispatchQueue.main.async {
                guard let self, let webView, self.fullscreenCandidateWebView === webView else { return }
                self.handleFullscreenStateChange(of: webView)
            }
        }
    }

    private func handleFullscreenStateChange(of webView: WKWebView) {
        let state = webView.fullscreenState
        let actualScreen = webView.window?.screen
        appendFullscreenGateReport(
            "FULLSCREEN_STATE state=\(fullscreenStateName(state)) "
                + "shell={\(screenSummary(screen))} actual={\(screenSummary(actualScreen))}"
        )

        switch state {
        case .enteringFullscreen, .inFullscreen, .exitingFullscreen:
            // Do not change WKPreferences while WebKit owns an active transition.
            // We only observe whether the pre-entry gate succeeded.
            if state == .inFullscreen, !sameDisplay(screen, actualScreen) {
                appendFullscreenGateReport(
                    "CROSS_DISPLAY_GATE_ESCAPE shell={\(screenSummary(screen))} "
                        + "actual={\(screenSummary(actualScreen))}"
                )
            }

        case .notInFullscreen:
            restartFullscreenGate(reason: "fullscreen_exit")

        @unknown default:
            break
        }
    }

    private func setElementFullscreenEnabled(_ enabled: Bool, on webView: WKWebView, reason: String) {
        guard webView.fullscreenState == .notInFullscreen else { return }
        let preferences = webView.configuration.preferences
        guard preferences.isElementFullscreenEnabled != enabled else { return }
        preferences.isElementFullscreenEnabled = enabled
        appendFullscreenGateReport(
            "GATE_SET enabled=\(enabled) reason=\(reason) shell={\(screenSummary(screen))} "
                + "main={\(screenSummary(NSScreen.main))} key=\(isKeyWindow)"
        )
    }

    private func sameDisplay(_ lhs: NSScreen?, _ rhs: NSScreen?) -> Bool {
        guard let lhs = screenNumber(lhs), let rhs = screenNumber(rhs) else { return false }
        return lhs == rhs
    }

    private func screenNumber(_ screen: NSScreen?) -> UInt32? {
        guard let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return number.uint32Value
    }

    private func screenSummary(_ screen: NSScreen?) -> String {
        guard let screen else { return "nil" }
        return "name=\(screen.localizedName),number=\(screenNumber(screen).map(String.init) ?? "nil")"
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

    private var fullscreenGateReportURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .appendingPathComponent("FloatTabs-Fullscreen-Gate-Report.txt")
    }

    private func resetFullscreenGateReport() {
        let header = """
        FloatTabs Same-Display Fullscreen Gate Test
        ===========================================
        Baseline: dad0ee79e6b70d07e659814aefde6d4f4701e221
        Path: normal production Tabs / original NSPanel host
        Layout/window architecture changes: none
        Repair/rebuild/reload: none

        """
        try? header.write(to: fullscreenGateReportURL, atomically: true, encoding: .utf8)
    }

    private func appendFullscreenGateReport(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: fullscreenGateReportURL.path) {
            FileManager.default.createFile(atPath: fullscreenGateReportURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: fullscreenGateReportURL) else { return }
        defer { try? handle.close() }
        try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}
