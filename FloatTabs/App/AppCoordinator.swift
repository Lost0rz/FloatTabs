import AppKit
import Foundation
import KeyboardShortcuts
import WebKit

private final class FullscreenLabReportWriter {
    let url: URL
    private let queue = DispatchQueue(label: "com.lost0rz.FloatTabs.fullscreenLabReport")

    init() {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
        url = desktop.appendingPathComponent("FloatTabs-Fullscreen-Lab-Report.txt")
    }

    func reset(header: String) {
        queue.sync {
            try? header.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func append(_ text: String) {
        let payload = text.hasSuffix("\n") ? text : text + "\n"
        queue.async { [url] in
            guard let data = payload.data(using: .utf8) else { return }
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }

    func flush() {
        queue.sync {}
    }
}

@MainActor
final class FullscreenLabController: NSObject {
    private enum AttemptKind: String {
        case sameScreenControl = "SAME-SCREEN CONTROL"
        case crossScreen = "CROSS-SCREEN"
        case postRecovery = "POST-RECOVERY"
        case unknown = "UNKNOWN"
    }

    private struct AttemptResult {
        let number: Int
        let kind: AttemptKind
        let contextScreenNumber: UInt32?
        let contextScreenSummary: String
        let shellScreenNumber: UInt32?
        let shellScreenSummary: String
        let pointerScreenSummary: String
        let webViewIdentity: String
        let sourceWindowSummary: String
        var reachedFullscreen: Bool
        var failedBeforeFullscreen: Bool
        var fullscreenScreenNumber: UInt32?
        var fullscreenScreenSummary: String?
        var fullscreenMatchedContext: Bool?
    }

    private struct RetiredWebContent {
        let identity: String
        let webView: WKWebView
        let rootView: NSView
    }

    private struct PendingToggle {
        let targetScreenNumber: UInt32?
        let desiredVisible: Bool
    }

    var onWillEnable: (() -> Void)?

    private let baselineCommit = "dad0ee79e6b70d07e659814aefde6d4f4701e221"
    private let reportWriter = FullscreenLabReportWriter()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private var enabled = false
    private var window: NSWindow?
    private var webView: WKWebView?
    private var rootView: NSView?

    // A WKWebView that has owned cross-display native fullscreen is deliberately
    // quarantined for the rest of this experimental process. Its media is suspended
    // and it is detached from the visible hierarchy, but we do not force WebKit's
    // fullscreen controller to deallocate on an arbitrary timer.
    private var retiredWebContents: [RetiredWebContent] = []

    private var fullscreenObservation: NSKeyValueObservation?
    private var stagedProgressObservation: NSKeyValueObservation?
    private var stagedWebView: WKWebView?
    private var stagedRootView: NSView?
    private var stagedReadyCommitScheduled = false
    private var recoveryRetiringWebView: WKWebView?
    private var pendingToggle: PendingToggle?

    private var observedFullscreenState = "notInFullscreen"
    private var sourceURL = URL(string: "https://www.youtube.com/")!
    private var activeAttempt: AttemptResult?
    private var completedAttempts: [AttemptResult] = []

    private var recoveryScheduled = false
    private var recoveryApplied = false
    private var recoveryCount = 0
    private var recoveryOldWebViewIdentity: String?
    private var recoveryNewWebViewIdentity: String?
    private var verifiedRecoveryWebViews: Set<String> = []

    var isEnabled: Bool { enabled }
    var isVisible: Bool { window?.isVisible ?? false }
    var reportURL: URL { reportWriter.url }

    private var lifecycleLocked: Bool {
        observedFullscreenState != "notInFullscreen"
            || recoveryScheduled
            || stagedWebView != nil
    }

    override init() {
        super.init()
        configureStatusItem()
        configureMenu()
    }

    func start() {
        let now = ISO8601DateFormatter().string(from: Date())
        let header = """
        FloatTabs Fullscreen Refined Recovery Lab
        =========================================
        Baseline commit: \(baselineCommit)
        Started: \(now)
        OS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        PID: \(ProcessInfo.processInfo.processIdentifier)
        Report: \(reportWriter.url.path)

        Current experiment
        ------------------
        1. Native WKWebView element fullscreen remains WebKit-owned.
        2. Shell show/hide/move requests are serialized with fullscreen/recovery instead of dropped.
        3. A replacement WKWebView is laid out at the real panel viewport size before navigation starts.
        4. Replacement swap waits for a nearly-complete load plus a short layout-stability interval.
        5. Retiring media is suspended before replacement loading, preventing duplicate audio.
        6. Retired fullscreen-owning WKWebViews are quarantined for this process instead of force-released.
        7. The FloatingPanel separately removes its shell/Tab rail from stable native fullscreen presentation.

        Guardrails
        ----------
        No mouse event monitor, no NSWindow.sendEvent override, no injected JavaScript,
        no requestFullscreen/exitFullscreen wrapping, no closeAllMediaPresentations,
        no app-owned fullscreen, and no WebKit-owned fullscreen-window mutation.

        """

        reportWriter.reset(header: header)
        completedAttempts.removeAll()
        activeAttempt = nil
        recoveryScheduled = false
        recoveryApplied = false
        recoveryCount = 0
        recoveryOldWebViewIdentity = nil
        recoveryNewWebViewIdentity = nil
        verifiedRecoveryWebViews.removeAll()
        stagedProgressObservation = nil
        stagedWebView?.stopLoading()
        stagedWebView = nil
        stagedRootView = nil
        stagedReadyCommitScheduled = false
        recoveryRetiringWebView = nil
        pendingToggle = nil
        updateStatusItemTitle()
        reportWriter.append("Available displays: \(NSScreen.screens.map(screenSummary).joined(separator: " || "))")
        reportWriter.append("Existing quarantined retired WKWebViews: \(retiredWebContents.count)\n")
    }

    func stop() {
        captureCurrentURL()
        fullscreenObservation = nil
        stagedProgressObservation = nil
        stagedWebView?.stopLoading()
        stagedWebView = nil
        stagedRootView = nil
        recoveryRetiringWebView = nil
        pendingToggle = nil
        if observedFullscreenState == "notInFullscreen" {
            window?.orderOut(nil)
        }
        enabled = false
        updateStatusItemTitle()
        reportWriter.flush()
    }

    func toggleOnCurrentDisplay() {
        guard enabled else { return }

        let targetScreen = screenAtMouse() ?? NSScreen.main ?? NSScreen.screens.first
        let desiredVisible = !(window?.isVisible ?? false)

        if lifecycleLocked {
            pendingToggle = PendingToggle(
                targetScreenNumber: screenNumber(targetScreen),
                desiredVisible: desiredVisible
            )
            reportWriter.append(
                "TOGGLE_QUEUED desired_visible=\(desiredVisible) target={\(screenSummary(targetScreen))} "
                    + "fullscreen_state=\(observedFullscreenState) recovery_scheduled=\(recoveryScheduled) "
                    + "staged=\(webViewIdentity(stagedWebView))"
            )
            reportWriter.flush()
            return
        }

        performToggle(targetScreen: targetScreen, desiredVisible: desiredVisible, source: "immediate")
    }

    func revealReport() {
        reportWriter.flush()
        NSWorkspace.shared.activateFileViewerSelecting([reportWriter.url])
    }

    private func performToggle(targetScreen: NSScreen?, desiredVisible: Bool, source: String) {
        guard let targetScreen = targetScreen ?? NSScreen.main ?? NSScreen.screens.first else { return }

        if desiredVisible {
            show(on: targetScreen)
            reportWriter.append("TOGGLE_APPLIED source=\(source) action=show target={\(screenSummary(targetScreen))}")
            reportWriter.flush()
            return
        }

        if let window, window.isVisible {
            window.orderOut(nil)
            reportWriter.append(
                "TOGGLE_APPLIED source=\(source) action=hide shell={\(screenSummary(window.screen))} "
                    + "main={\(screenSummary(NSScreen.main))} pointer={\(screenSummary(screenAtMouse()))} "
                    + "webview=\(webViewIdentity(webView)) recovery_count=\(recoveryCount)"
            )
            reportWriter.flush()
        }
    }

    private func schedulePendingToggleDrain() {
        DispatchQueue.main.async { [weak self] in
            self?.drainPendingToggleIfUnlocked()
        }
    }

    private func drainPendingToggleIfUnlocked() {
        guard enabled, !lifecycleLocked, let pendingToggle else { return }
        self.pendingToggle = nil
        let target = screen(withNumber: pendingToggle.targetScreenNumber)
            ?? screenAtMouse()
            ?? NSScreen.main
            ?? NSScreen.screens.first
        reportWriter.append(
            "TOGGLE_DRAINED desired_visible=\(pendingToggle.desiredVisible) target={\(screenSummary(target))}"
        )
        performToggle(targetScreen: target, desiredVisible: pendingToggle.desiredVisible, source: "queued")
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "rectangle.3.group",
            accessibilityDescription: "Fullscreen Refined Recovery Lab"
        )
        button.image?.isTemplate = true
        button.imagePosition = .imageLeading
        updateStatusItemTitle()
        statusItem.menu = menu
    }

    private func configureMenu() {
        let titleItem = NSMenuItem(title: "Fullscreen Refined Recovery Lab", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        let enableItem = NSMenuItem(
            title: "Enable Refined Recovery Experiment",
            action: #selector(enableLab),
            keyEquivalent: ""
        )
        enableItem.target = self
        menu.addItem(enableItem)

        let disableItem = NSMenuItem(
            title: "Disable / Hide Lab",
            action: #selector(disableLab),
            keyEquivalent: ""
        )
        disableItem.target = self
        menu.addItem(disableItem)

        menu.addItem(.separator())

        let showItem = NSMenuItem(
            title: "Show / Move Single Lab Here",
            action: #selector(showLabHere),
            keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)

        let snapshotItem = NSMenuItem(
            title: "Log Current Recovery Context",
            action: #selector(logCurrentContext),
            keyEquivalent: ""
        )
        snapshotItem.target = self
        menu.addItem(snapshotItem)

        menu.addItem(.separator())

        let reportItem = NSMenuItem(
            title: "Reveal Desktop Report",
            action: #selector(revealDesktopReport),
            keyEquivalent: ""
        )
        reportItem.target = self
        menu.addItem(reportItem)

        let resetItem = NSMenuItem(
            title: "Reset Report / Counters",
            action: #selector(resetDesktopReport),
            keyEquivalent: ""
        )
        resetItem.target = self
        menu.addItem(resetItem)
    }

    @objc private func enableLab() {
        onWillEnable?()
        enabled = true
        updateStatusItemTitle()
        let targetScreen = screenAtMouse() ?? NSScreen.main ?? NSScreen.screens.first
        if let targetScreen {
            show(on: targetScreen)
        }
    }

    @objc private func disableLab() {
        guard !lifecycleLocked else {
            reportWriter.append(
                "DISABLE_BLOCKED lifecycle_locked=true fullscreen_state=\(observedFullscreenState) "
                    + "recovery_scheduled=\(recoveryScheduled)"
            )
            reportWriter.flush()
            return
        }
        captureCurrentURL()
        enabled = false
        window?.orderOut(nil)
        activeAttempt = nil
        pendingToggle = nil
        updateStatusItemTitle()
        reportWriter.append("\nLAB HIDDEN/DISABLED — stable current WKWebView retained.\n")
        reportWriter.flush()
    }

    @objc private func showLabHere() {
        guard enabled else { return }
        if lifecycleLocked {
            let targetScreen = screenAtMouse() ?? NSScreen.main ?? NSScreen.screens.first
            pendingToggle = PendingToggle(
                targetScreenNumber: screenNumber(targetScreen),
                desiredVisible: true
            )
            reportWriter.append(
                "SHOW_MOVE_QUEUED target={\(screenSummary(targetScreen))} fullscreen_state=\(observedFullscreenState)"
            )
            reportWriter.flush()
            return
        }
        let targetScreen = screenAtMouse() ?? NSScreen.main ?? NSScreen.screens.first
        if let targetScreen {
            show(on: targetScreen)
        }
    }

    @objc private func logCurrentContext() {
        reportWriter.append(
            "RECOVERY_CONTEXT main={\(screenSummary(NSScreen.main))} "
                + "shell={\(screenSummary(window?.screen))} pointer={\(screenSummary(screenAtMouse()))} "
                + "webview=\(webViewIdentity(webView)) state=\(observedFullscreenState) "
                + "recovery_scheduled=\(recoveryScheduled) recovery_count=\(recoveryCount) "
                + "staged=\(webViewIdentity(stagedWebView)) quarantined=\(retiredWebContents.count) "
                + "pending_toggle=\(pendingToggle != nil) visible_webcore=\(visibleWebCoreFullscreenWindowsSummary())"
        )
        reportWriter.flush()
    }

    @objc private func revealDesktopReport() {
        revealReport()
    }

    @objc private func resetDesktopReport() {
        guard !lifecycleLocked else {
            reportWriter.append("RESET_BLOCKED lifecycle_locked=true")
            reportWriter.flush()
            return
        }
        start()
        reportWriter.append("Reset performed with current WKWebView retained: \(webViewIdentity(webView))")
        reportWriter.flush()
    }

    private func show(on targetScreen: NSScreen) {
        let mainBeforeShow = NSScreen.main
        let pointerBeforeShow = screenAtMouse()

        if window == nil {
            createEnvironment(on: targetScreen)
        } else {
            window?.setFrame(frame(for: targetScreen), display: false)
        }

        reportWriter.append(
            "LAB_SHOW shell_target={\(screenSummary(targetScreen))} "
                + "main_before_show={\(screenSummary(mainBeforeShow))} "
                + "pointer_before_show={\(screenSummary(pointerBeforeShow))} "
                + "webview=\(webViewIdentity(webView)) recovery_count=\(recoveryCount)"
        )

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if let webView {
            window?.makeFirstResponder(webView)
        }

        reportWriter.append(
            "LAB_SHOWN shell={\(screenSummary(window?.screen))} "
                + "main_after_show={\(screenSummary(NSScreen.main))} "
                + "pointer_after_show={\(screenSummary(screenAtMouse()))} "
                + "window={\(windowSummary(window))} webview=\(webViewIdentity(webView))"
        )
        reportWriter.flush()
    }

    private func createEnvironment(on targetScreen: NSScreen) {
        let newWindow = FloatingPanel(contentRect: frame(for: targetScreen))
        window = newWindow
        installInitialWebView(in: newWindow)
        reportWriter.append(
            "SINGLE_PANEL_CREATED window={\(windowSummary(newWindow))} webview=\(webViewIdentity(webView))"
        )
    }

    private func installInitialWebView(in window: NSWindow) {
        let newWebView = WebViewFactory.makeWebView()
        let root = PanelRootView(webView: newWebView)
        window.contentView = root
        webView = newWebView
        rootView = root
        observedFullscreenState = fullscreenStateName(newWebView.fullscreenState)
        attachFullscreenObservation(to: newWebView)
        newWebView.load(URLRequest(url: sourceURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 60))
        reportWriter.append(
            "WEBVIEW_INSTALLED reason=initial_environment webview=\(webViewIdentity(newWebView)) "
                + "frame=\(NSStringFromRect(newWebView.frame)) url=\(sourceURL.absoluteString)"
        )
    }

    private func scheduleCrossScreenRecovery(retiring oldWebView: WKWebView) {
        guard !recoveryScheduled, self.webView === oldWebView else { return }
        recoveryScheduled = true
        recoveryApplied = false
        recoveryRetiringWebView = oldWebView
        captureCurrentURL()
        recoveryOldWebViewIdentity = webViewIdentity(oldWebView)
        recoveryNewWebViewIdentity = nil
        updateStatusItemTitle()

        reportWriter.append(
            "CROSS_SCREEN_RECOVERY_SCHEDULED next_recovery=\(recoveryCount + 1) "
                + "old_webview=\(webViewIdentity(oldWebView)) url=\(sourceURL.absoluteString) "
                + "strategy=stable_source_then_sized_preload_swap_quarantine"
        )
        reportWriter.flush()

        waitForStableSourceReturn(retiring: oldWebView, consecutiveStableChecks: 0, attemptsRemaining: 40)
    }

    private func waitForStableSourceReturn(
        retiring oldWebView: WKWebView,
        consecutiveStableChecks: Int,
        attemptsRemaining: Int
    ) {
        guard recoveryScheduled, self.webView === oldWebView, recoveryRetiringWebView === oldWebView else {
            return
        }
        guard let window, let oldRoot = rootView else {
            abortRecovery(retiring: oldWebView, reason: "missing_window_or_root")
            return
        }

        let stable = fullscreenStateName(oldWebView.fullscreenState) == "notInFullscreen"
            && oldWebView.window === window
            && window.contentView === oldRoot
        let nextStableChecks = stable ? consecutiveStableChecks + 1 : 0

        reportWriter.append(
            "RECOVERY_SOURCE_STABILITY stable=\(stable) consecutive=\(nextStableChecks) remaining=\(attemptsRemaining) "
                + "webview_window={\(windowSummary(oldWebView.window))} source_window={\(windowSummary(window))} "
                + "visible_webcore=\(visibleWebCoreFullscreenWindowsSummary())"
        )

        // Require a longer stable return interval than the prior experiment. This
        // leaves WebKit/AppKit time to finish the native fullscreen transition before
        // we touch the source hierarchy.
        if nextStableChecks >= 5 {
            beginRecoveryPreload(retiring: oldWebView)
            return
        }

        guard attemptsRemaining > 0 else {
            abortRecovery(retiring: oldWebView, reason: "source_never_stabilized")
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self, weak oldWebView] in
            guard let self, let oldWebView else { return }
            self.waitForStableSourceReturn(
                retiring: oldWebView,
                consecutiveStableChecks: nextStableChecks,
                attemptsRemaining: attemptsRemaining - 1
            )
        }
    }

    private func beginRecoveryPreload(retiring oldWebView: WKWebView) {
        guard recoveryScheduled,
              self.webView === oldWebView,
              recoveryRetiringWebView === oldWebView,
              stagedWebView == nil,
              let window,
              let oldRoot = rootView else { return }

        captureCurrentURL()
        oldWebView.setAllMediaPlaybackSuspended(true, completionHandler: nil)
        reportWriter.append(
            "RETIRING_MEDIA_SUSPENDED old_webview=\(webViewIdentity(oldWebView)) url=\(sourceURL.absoluteString)"
        )

        let candidate = WebViewFactory.makeWebView()
        let candidateRoot = PanelRootView(webView: candidate)

        // Give the staged page the exact viewport it will receive after the swap.
        // Loading a detached zero-sized WKWebView can send responsive sites down a
        // different layout/player initialization path.
        let stagingBounds = oldRoot.bounds.width > 1 && oldRoot.bounds.height > 1
            ? oldRoot.bounds
            : NSRect(origin: .zero, size: window.contentView?.bounds.size ?? window.contentLayoutRect.size)
        candidateRoot.frame = stagingBounds
        candidateRoot.autoresizingMask = [.width, .height]
        candidateRoot.layoutSubtreeIfNeeded()

        candidate.setAllMediaPlaybackSuspended(true, completionHandler: nil)
        stagedWebView = candidate
        stagedRootView = candidateRoot
        stagedReadyCommitScheduled = false

        stagedProgressObservation = candidate.observe(\.estimatedProgress, options: [.new]) { [weak self, weak candidate, weak oldWebView] _, _ in
            DispatchQueue.main.async {
                guard let self,
                      let candidate,
                      let oldWebView,
                      self.stagedWebView === candidate,
                      self.recoveryRetiringWebView === oldWebView else { return }

                let progress = candidate.estimatedProgress
                guard progress >= 0.99,
                      candidate.url != nil,
                      !self.stagedReadyCommitScheduled else { return }

                self.stagedReadyCommitScheduled = true
                self.reportWriter.append(
                    "REPLACEMENT_PRELOAD_READY staged_webview=\(self.webViewIdentity(candidate)) "
                        + "progress=\(String(format: "%.2f", progress)) frame=\(NSStringFromRect(candidate.frame)) "
                        + "stabilize_ms=350"
                )
                self.reportWriter.flush()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak oldWebView, weak candidate] in
                    guard let self, let oldWebView, let candidate, self.stagedWebView === candidate else { return }
                    self.commitStagedRecovery(retiring: oldWebView, staged: candidate, reason: "loaded_and_layout_stable")
                }
            }
        }

        reportWriter.append(
            "REPLACEMENT_PRELOAD_STARTED staged_webview=\(webViewIdentity(candidate)) "
                + "root_frame=\(NSStringFromRect(candidateRoot.frame)) webview_frame=\(NSStringFromRect(candidate.frame)) "
                + "old_page_remains_visible=true media_suspended=true url=\(sourceURL.absoluteString)"
        )
        candidate.load(URLRequest(url: sourceURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 60))

        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self, weak oldWebView, weak candidate] in
            guard let self,
                  let oldWebView,
                  let candidate,
                  self.stagedWebView === candidate,
                  !self.stagedReadyCommitScheduled else { return }
            if candidate.url != nil, candidate.estimatedProgress >= 0.75 {
                self.stagedReadyCommitScheduled = true
                self.commitStagedRecovery(retiring: oldWebView, staged: candidate, reason: "preload_timeout_fallback")
            } else {
                self.abortRecovery(retiring: oldWebView, reason: "replacement_preload_timeout")
            }
        }
    }

    private func commitStagedRecovery(retiring oldWebView: WKWebView, staged candidate: WKWebView, reason: String) {
        guard recoveryScheduled,
              self.webView === oldWebView,
              recoveryRetiringWebView === oldWebView,
              stagedWebView === candidate,
              let candidateRoot = stagedRootView,
              let window,
              let oldRoot = rootView else { return }

        guard fullscreenStateName(oldWebView.fullscreenState) == "notInFullscreen",
              oldWebView.window === window,
              window.contentView === oldRoot else {
            stagedReadyCommitScheduled = false
            reportWriter.append("RECOVERY_SWAP_DEFERRED reason=source_no_longer_stable")
            reportWriter.flush()
            waitForStableSourceReturn(retiring: oldWebView, consecutiveStableChecks: 0, attemptsRemaining: 30)
            return
        }

        let oldIdentity = webViewIdentity(oldWebView)
        let newIdentity = webViewIdentity(candidate)

        stagedProgressObservation = nil
        fullscreenObservation = nil

        retiredWebContents.append(
            RetiredWebContent(identity: oldIdentity, webView: oldWebView, rootView: oldRoot)
        )

        candidateRoot.frame = oldRoot.bounds
        candidateRoot.layoutSubtreeIfNeeded()
        window.contentView = candidateRoot
        webView = candidate
        rootView = candidateRoot
        stagedWebView = nil
        stagedRootView = nil
        stagedReadyCommitScheduled = false
        recoveryRetiringWebView = nil
        observedFullscreenState = fullscreenStateName(candidate.fullscreenState)
        attachFullscreenObservation(to: candidate)
        candidate.setAllMediaPlaybackSuspended(false, completionHandler: nil)

        recoveryScheduled = false
        recoveryApplied = true
        recoveryCount += 1
        recoveryOldWebViewIdentity = oldIdentity
        recoveryNewWebViewIdentity = newIdentity

        if window.isVisible {
            window.makeFirstResponder(candidate)
        }

        oldWebView.stopLoading()

        reportWriter.append(
            "CROSS_SCREEN_RECOVERY_APPLIED recovery=\(recoveryCount) reason=\(reason) "
                + "same_panel_window=\(window.windowNumber) old_webview=\(oldIdentity) new_webview=\(newIdentity) "
                + "preload_progress=\(String(format: "%.2f", candidate.estimatedProgress)) "
                + "candidate_frame=\(NSStringFromRect(candidate.frame)) quarantined_count=\(retiredWebContents.count) "
                + "url=\(sourceURL.absoluteString)"
        )
        reportWriter.append(
            "RETIRED_WEBVIEW_QUARANTINED old_webview=\(oldIdentity) media_suspended=true "
                + "force_release=false quarantined_count=\(retiredWebContents.count)"
        )
        reportWriter.append(
            "RECOVERY_READY #\(recoveryCount) · sized replacement loaded before swap; queued toggle may now drain"
        )
        updateStatusItemTitle()
        reportWriter.flush()
        schedulePendingToggleDrain()
    }

    private func abortRecovery(retiring oldWebView: WKWebView, reason: String) {
        stagedProgressObservation = nil
        stagedWebView?.stopLoading()
        stagedWebView = nil
        stagedRootView = nil
        stagedReadyCommitScheduled = false
        if self.webView === oldWebView {
            oldWebView.setAllMediaPlaybackSuspended(false, completionHandler: nil)
        }
        recoveryRetiringWebView = nil
        recoveryScheduled = false
        recoveryApplied = false
        updateStatusItemTitle()
        reportWriter.append(
            "CROSS_SCREEN_RECOVERY_ABORTED reason=\(reason) current_webview=\(webViewIdentity(webView)) "
                + "quarantined_count=\(retiredWebContents.count)"
        )
        reportWriter.flush()
        schedulePendingToggleDrain()
    }

    private func attachFullscreenObservation(to webView: WKWebView) {
        fullscreenObservation = webView.observe(\.fullscreenState, options: [.new]) { [weak self, weak webView] _, _ in
            DispatchQueue.main.async {
                guard let self, let webView, self.webView === webView else { return }
                self.handleFullscreenStateChange(for: webView)
            }
        }
    }

    private func handleFullscreenStateChange(for webView: WKWebView) {
        let oldState = observedFullscreenState
        let newState = fullscreenStateName(webView.fullscreenState)
        observedFullscreenState = newState
        updateStatusItemTitle()

        if newState == "enteringFullscreen" {
            let contextScreen = NSScreen.main
            let shellScreen = window?.screen
            let pointerScreen = screenAtMouse()
            let contextNumber = screenNumber(contextScreen)
            let shellNumber = screenNumber(shellScreen)
            let currentWebViewIdentity = webViewIdentity(webView)

            let kind: AttemptKind
            if let contextNumber, let shellNumber, contextNumber != shellNumber {
                kind = .crossScreen
            } else if recoveryApplied,
                      recoveryNewWebViewIdentity == currentWebViewIdentity,
                      contextNumber != nil,
                      shellNumber != nil,
                      contextNumber == shellNumber {
                kind = .postRecovery
            } else if let contextNumber, let shellNumber, contextNumber == shellNumber {
                kind = .sameScreenControl
            } else {
                kind = .unknown
            }

            let attempt = AttemptResult(
                number: completedAttempts.count + 1,
                kind: kind,
                contextScreenNumber: contextNumber,
                contextScreenSummary: screenSummary(contextScreen),
                shellScreenNumber: shellNumber,
                shellScreenSummary: screenSummary(shellScreen),
                pointerScreenSummary: screenSummary(pointerScreen),
                webViewIdentity: currentWebViewIdentity,
                sourceWindowSummary: windowSummary(window),
                reachedFullscreen: false,
                failedBeforeFullscreen: false,
                fullscreenScreenNumber: nil,
                fullscreenScreenSummary: nil,
                fullscreenMatchedContext: nil
            )
            activeAttempt = attempt

            reportWriter.append("\nATTEMPT \(attempt.number) START · \(kind.rawValue)")
            reportWriter.append("  context/main={\(attempt.contextScreenSummary)}")
            reportWriter.append("  shell={\(attempt.shellScreenSummary)}")
            reportWriter.append("  pointer={\(attempt.pointerScreenSummary)}")
            reportWriter.append("  source_window={\(attempt.sourceWindowSummary)}")
            reportWriter.append("  webview=\(attempt.webViewIdentity)")
            if kind == .crossScreen {
                reportWriter.append("  CROSS-SCREEN CONDITION CONFIRMED · current shell and context/main differ")
            }
        }

        reportWriter.append(
            "  fullscreen_state \(oldState) -> \(newState) "
                + "webview_window={\(windowSummary(webView.window))} "
                + "main_now={\(screenSummary(NSScreen.main))}"
        )

        guard var attempt = activeAttempt else {
            reportWriter.flush()
            if newState == "notInFullscreen" {
                schedulePendingToggleDrain()
            }
            return
        }

        if newState == "inFullscreen" {
            attempt.reachedFullscreen = true
            let actualScreen = webView.window?.screen
            let actualNumber = screenNumber(actualScreen)
            let matchesContext = actualNumber != nil
                && attempt.contextScreenNumber != nil
                && actualNumber == attempt.contextScreenNumber
            attempt.fullscreenScreenNumber = actualNumber
            attempt.fullscreenScreenSummary = screenSummary(actualScreen)
            attempt.fullscreenMatchedContext = matchesContext
            activeAttempt = attempt

            reportWriter.append(
                "  REACHED inFullscreen · actual={\(screenSummary(actualScreen))} "
                    + "fullscreen_window={\(windowSummary(webView.window))}"
            )
            reportWriter.flush()
            return
        }

        if newState == "exitingFullscreen", !attempt.reachedFullscreen {
            attempt.failedBeforeFullscreen = true
            activeAttempt = attempt
            reportWriter.append("  FAILURE SIGNAL · WebKit exited before reaching inFullscreen")
            reportWriter.flush()
            return
        }

        if newState == "notInFullscreen" {
            activeAttempt = nil
            completedAttempts.append(attempt)
            let success = attempt.reachedFullscreen
                && !attempt.failedBeforeFullscreen
                && attempt.fullscreenMatchedContext == true

            reportWriter.append(
                "ATTEMPT \(attempt.number) RESULT = \(success ? "PASS" : "FAIL") "
                    + "kind=\(attempt.kind.rawValue) webview=\(attempt.webViewIdentity) "
                    + "source_return={\(windowSummary(webView.window))}"
            )

            if attempt.kind == .crossScreen, success {
                reportWriter.append(
                    "CROSS-SCREEN SUCCESS · scheduling serialized recovery after stable source return"
                )
                scheduleCrossScreenRecovery(retiring: webView)
            }

            if attempt.kind == .postRecovery {
                let sameScreen = attempt.contextScreenNumber != nil
                    && attempt.shellScreenNumber != nil
                    && attempt.contextScreenNumber == attempt.shellScreenNumber
                let belongsToLatestRecovery = recoveryApplied
                    && recoveryNewWebViewIdentity == attempt.webViewIdentity

                if belongsToLatestRecovery && sameScreen && success {
                    verifiedRecoveryWebViews.insert(attempt.webViewIdentity)
                }

                reportWriter.append("\n================ REFINED RECOVERY VERDICT ================")
                reportWriter.append("Latest recovery number: \(recoveryCount)")
                reportWriter.append("Post-recovery fullscreen result: \(success ? "PASS" : "FAIL")")
                reportWriter.append("Verified recovered WKWebViews: \(verifiedRecoveryWebViews.count) / \(recoveryCount)")
                reportWriter.append("Quarantined retired WKWebViews: \(retiredWebContents.count)")
                if recoveryCount >= 2 && verifiedRecoveryWebViews.count >= 2 {
                    reportWriter.append("REPEATABLE REFINED RECOVERY = PASS")
                } else {
                    reportWriter.append("REPEATABLE REFINED RECOVERY = PENDING")
                }
                reportWriter.append("==========================================================\n")
            }
            reportWriter.flush()
            schedulePendingToggleDrain()
        }
    }

    private func captureCurrentURL() {
        guard let candidate = webView?.url,
              candidate.scheme == "http" || candidate.scheme == "https" else { return }
        sourceURL = candidate
    }

    private func frame(for screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let width = min(CGFloat(1000), max(CGFloat(640), visible.width - 40))
        let height = min(CGFloat(700), max(CGFloat(500), visible.height - 40))
        let x = visible.midX - width / 2
        let y = visible.midY - height / 2
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func screenAtMouse() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(point) }
    }

    private func screen(withNumber number: UInt32?) -> NSScreen? {
        guard let number else { return nil }
        return NSScreen.screens.first { screenNumber($0) == number }
    }

    private func screenNumber(_ screen: NSScreen?) -> UInt32? {
        guard let screen,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return number.uint32Value
    }

    private func screenSummary(_ screen: NSScreen?) -> String {
        guard let screen else { return "nil" }
        let number = screenNumber(screen).map(String.init) ?? "nil"
        return "name=\(screen.localizedName),number=\(number),frame=\(NSStringFromRect(screen.frame)),visible=\(NSStringFromRect(screen.visibleFrame))"
    }

    private func windowSummary(_ window: NSWindow?) -> String {
        guard let window else { return "nil" }
        return "class=\(String(describing: type(of: window))),number=\(window.windowNumber),visible=\(window.isVisible),key=\(window.isKeyWindow),frame=\(NSStringFromRect(window.frame)),screen={\(screenSummary(window.screen))},collection=\(window.collectionBehavior.rawValue),level=\(window.level.rawValue)"
    }

    private func webViewIdentity(_ webView: WKWebView?) -> String {
        guard let webView else { return "nil" }
        return String(describing: Unmanaged.passUnretained(webView).toOpaque())
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

    private func visibleWebCoreFullscreenWindowsSummary() -> String {
        let windows = NSApp.windows.filter {
            String(describing: type(of: $0)).contains("WebCoreFullScreenWindow") && $0.isVisible
        }
        if windows.isEmpty { return "none" }
        return windows.map(windowSummary).joined(separator: " || ")
    }

    private func updateStatusItemTitle() {
        guard let button = statusItem.button else { return }
        if enabled {
            if observedFullscreenState != "notInFullscreen" {
                button.title = "FS Native"
            } else if recoveryScheduled {
                button.title = "FS Repair ↻"
            } else if recoveryCount > 0 {
                button.title = "FS Repair ✓\(recoveryCount)"
            } else {
                button.title = "FS Repair"
            }
            button.toolTip = pendingToggle == nil
                ? "Fullscreen refined recovery experiment"
                : "Fullscreen refined recovery experiment · one toggle queued"
        } else {
            button.title = "FS Lab Off"
            button.toolTip = "FloatTabs Fullscreen Refined Recovery Lab"
        }
    }
}

@MainActor
final class AppCoordinator {
    private let panelController: PanelController
    private let fullscreenLabController: FullscreenLabController
    private var statusItemController: StatusItemController?
    private var globalHotkeyController: GlobalHotkeyController?
    private var appCommandController: AppCommandController?
    private let preferencesStore: AppPreferencesStore
    private let backupService: FloatTabsBackupService
    private var globalSettingsController: GlobalSettingsController?
#if DEBUG
    private var benchmarkControlServer: BenchmarkControlServer?
#endif

    init(
        panelController: PanelController? = nil,
        preferencesStore: AppPreferencesStore? = nil,
        backupService: FloatTabsBackupService = FloatTabsBackupService()
    ) {
        let resolvedPreferencesStore = preferencesStore ?? AppPreferencesStore()
        self.preferencesStore = resolvedPreferencesStore
        self.backupService = backupService
        self.fullscreenLabController = FullscreenLabController()

        if let panelController {
            self.panelController = panelController
        } else {
            let tabStore = TabStore(repository: ProfileRepository())
            let webViewPool = WebViewPool(
                onURLChange: { slotID, url in
                    tabStore.updateCurrentURL(id: slotID, url: url)
                },
                isSlotActive: { slotID in
                    tabStore.activeTabID == slotID
                }
            )
            self.panelController = PanelController(
                tabStore: tabStore,
                webViewPool: webViewPool,
                preferencesStore: resolvedPreferencesStore
            )
        }
    }

    func start() {
        preferencesStore.applyStoredAppearance()
        globalSettingsController = GlobalSettingsController(
            preferencesStore: preferencesStore,
            onExportBackup: { [weak self] url in
                guard let self else { throw FloatTabsBackupError.restoreFailed }
                try self.exportBackup(to: url)
            },
            onRestoreBackup: { [weak self] url in
                guard let self else { throw FloatTabsBackupError.restoreFailed }
                return try self.restoreBackup(from: url)
            }
        )
        panelController.onOpenGlobalSettings = { [weak self] in
            self?.showGlobalSettings()
        }

        fullscreenLabController.onWillEnable = { [weak self] in
            guard let self else { return }
            if self.panelController.isVisible {
                self.panelController.hideFloatTabs()
            }
        }
        fullscreenLabController.start()

        statusItemController = StatusItemController(
            onToggle: { [weak self] in self?.toggleFloatTabs() },
            isVisible: { [weak self] in
                guard let self else { return false }
                if self.fullscreenLabController.isEnabled {
                    return self.fullscreenLabController.isVisible
                }
                return self.panelController.isVisible
            },
            onSettings: { [weak self] in self?.showGlobalSettings() },
            onQuit: { NSApp.terminate(nil) }
        )
        statusItemController?.setActiveWebApp(
            name: panelController.selectedSlotName,
            homeURL: panelController.selectedSlotHomeURL
        )
        panelController.onSelectedSlotPresentationChange = { [weak self] name, homeURL in
            self?.statusItemController?.setActiveWebApp(name: name, homeURL: homeURL)
        }

        globalHotkeyController = GlobalHotkeyController(
            onToggle: { [weak self] in self?.toggleFloatTabs() }
        )

        appCommandController = AppCommandController(
            isEnabled: { [weak self] in
                NSApp.isActive
                    && !(self?.fullscreenLabController.isEnabled ?? false)
                    && (self?.panelController.isVisible ?? false)
            },
            onCommand: { [weak self] command in
                guard let self else { return }
                if command == .settings {
                    self.showGlobalSettings()
                } else {
                    self.panelController.handle(command)
                }
            }
        )

        try? backupService.writeAutomaticVersionSnapshot(makeBackupDocument())

#if DEBUG
        let benchmarkControlServer = BenchmarkControlServer { [weak self] request in
            self?.handleBenchmarkControl(request) ?? ["ok": false, "error": "coordinator_unavailable"]
        }
        self.benchmarkControlServer = benchmarkControlServer
        try? benchmarkControlServer.start()
#endif
    }

    func prepareForTermination() {
#if DEBUG
        benchmarkControlServer?.stop()
#endif
        fullscreenLabController.stop()
        panelController.prepareForTermination()
        try? backupService.writeAutomaticVersionSnapshot(makeBackupDocument())
    }

#if DEBUG
    private func handleBenchmarkControl(_ request: [String: Any]) -> [String: Any] {
        guard let action = request["action"] as? String else {
            return ["ok": false, "error": "missing_action"]
        }

        switch action {
        case "status", "ping":
            return ["ok": true, "status": panelController.benchmarkControlSnapshot()]

        case "configure":
            guard let slotIDs = request["slot_ids"] as? [String] else {
                return ["ok": false, "error": "missing_slot_ids"]
            }
            let succeeded = panelController.benchmarkSetResourcePolicy(
                slotIDStrings: slotIDs,
                residencyRawValue: request["residency"] as? String,
                backgroundMediaRawValue: request["background_media"] as? String
            )
            return succeeded
                ? ["ok": true, "status": panelController.benchmarkControlSnapshot()]
                : ["ok": false, "error": "configure_failed"]

        case "activate":
            guard let slotID = request["slot_id"] as? String,
                  panelController.benchmarkSelect(slotIDString: slotID) else {
                return ["ok": false, "error": "activate_failed"]
            }
            return ["ok": true, "status": panelController.benchmarkControlSnapshot()]

        case "show":
            if !panelController.isVisible {
                panelController.showFloatTabs()
            }
            return ["ok": true, "status": panelController.benchmarkControlSnapshot()]

        case "hide":
            if panelController.isVisible {
                panelController.hideFloatTabs()
            }
            return ["ok": true, "status": panelController.benchmarkControlSnapshot()]

        default:
            return ["ok": false, "error": "unknown_action"]
        }
    }
#endif

    private func makeBackupDocument(now: Date = Date()) -> FloatTabsBackupDocument {
        let shortcut = KeyboardShortcuts.getShortcut(for: .toggleFloatTabs)
        let shortcutBackup = shortcut.map {
            FloatTabsBackupShortcut(
                carbonKeyCode: $0.carbonKeyCode,
                carbonModifiers: $0.carbonModifiers
            )
        }
        let appVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "unknown"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "unknown"

        return FloatTabsBackupDocument(
            schemaVersion: FloatTabsBackupDocument.currentSchemaVersion,
            createdAt: now,
            sourceAppVersion: appVersion,
            sourceBuild: build,
            webAppState: panelController.storedWebAppStateSnapshot(),
            globalPreferences: FloatTabsBackupPreferences(
                appearanceMode: preferencesStore.appearanceMode,
                followPreferredSize: preferencesStore.followPreferredSize,
                borderTheme: preferencesStore.borderTheme,
                customBorderColorHex: preferencesStore.customBorderColorHex,
                fixedViewportWidth: Double(preferencesStore.fixedViewportSize.width),
                fixedViewportHeight: Double(preferencesStore.fixedViewportSize.height)
            ),
            globalShowHideShortcut: shortcutBackup
        )
    }

    private func exportBackup(to url: URL) throws {
        try backupService.write(makeBackupDocument(), to: url)
    }

    private func restoreBackup(from url: URL) throws -> URL {
        let imported = try backupService.load(from: url)
        let rollbackURL = try backupService.writeRollback(makeBackupDocument())

        guard panelController.restoreStoredWebAppState(imported.webAppState) else {
            throw FloatTabsBackupError.restoreFailed
        }

        preferencesStore.followPreferredSize = imported.globalPreferences.followPreferredSize
        preferencesStore.appearanceMode = imported.globalPreferences.appearanceMode
        preferencesStore.customBorderColorHex = imported.globalPreferences.customBorderColorHex
            ?? AppPreferencesStore.defaultCustomBorderColorHex
        preferencesStore.borderTheme = imported.globalPreferences.borderTheme ?? .rainbow
        if let width = imported.globalPreferences.fixedViewportWidth,
           let height = imported.globalPreferences.fixedViewportHeight {
            preferencesStore.fixedViewportSize = CGSize(width: width, height: height)
        }

        let shortcut = imported.globalShowHideShortcut.map {
            KeyboardShortcuts.Shortcut(
                carbonKeyCode: $0.carbonKeyCode,
                carbonModifiers: $0.carbonModifiers
            )
        }
        KeyboardShortcuts.setShortcut(shortcut, for: .toggleFloatTabs)
        return rollbackURL
    }

    private func showGlobalSettings() {
        globalSettingsController?.show()
    }

    private func toggleFloatTabs() {
        if fullscreenLabController.isEnabled {
            fullscreenLabController.toggleOnCurrentDisplay()
            return
        }

        if panelController.isVisible {
            panelController.hideFloatTabs()
        } else {
            panelController.showFloatTabs()
        }
    }
}
