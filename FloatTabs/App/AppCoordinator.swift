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
        let webView: WKWebView
        let rootView: NSView
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
    private var retiredWebContents: [RetiredWebContent] = []
    private var fullscreenObservation: NSKeyValueObservation?
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

    override init() {
        super.init()
        configureStatusItem()
        configureMenu()
    }

    func start() {
        let now = ISO8601DateFormatter().string(from: Date())
        let header = """
        FloatTabs Fullscreen Repeatable Cross-Screen Recovery Lab
        =========================================================
        Baseline commit: \(baselineCommit)
        Started: \(now)
        OS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        PID: \(ProcessInfo.processInfo.processIdentifier)
        Report: \(reportWriter.url.path)

        Repair hypothesis
        -----------------
        Every successful native fullscreen where shell screen != context/main screen can leave
        THAT WKWebView fullscreen controller in a poisoned state. Recovery must therefore be
        repeatable: after EACH successful CROSS-SCREEN fullscreen exits, retire the current
        WKWebView and install a fresh WKWebView in the SAME FloatingPanel, restoring the URL.

        Recommended repeatability sequence
        ----------------------------------
        1. SAME-SCREEN CONTROL: A active, shell A, fullscreen A, exit.
        2. CROSS-SCREEN #1: B active, shell A, fullscreen B, exit.
        3. Wait for RECOVERY_READY #1 and page reload; then A/A fullscreen must PASS.
        4. CROSS-SCREEN #2: B active, shell A, fullscreen B, exit.
        5. Wait for RECOVERY_READY #2 and page reload; then A/A fullscreen must PASS.
        6. Optionally repeat once more to prove W1 -> W2 -> W3 -> W4 stability.

        Classification rule
        -------------------
        Every attempt is classified from its CURRENT screen context.
        context/main != shell is always CROSS-SCREEN, even after prior recoveries.
        A same-screen attempt on the newest recovered WKWebView is POST-RECOVERY.

        Repair constraints
        ------------------
        One FloatingPanel for the entire process.
        Native WKWebView fullscreen is untouched.
        No mouse event monitor, no NSWindow.sendEvent override, no injected JavaScript,
        no requestFullscreen/exitFullscreen wrapping, no closeAllMediaPresentations,
        no app-owned fullscreen, and no WebKit-owned fullscreen-window mutation.
        Retired WKWebViews remain strongly retained to avoid synchronous WebKit teardown.

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
        updateStatusItemTitle()
        reportWriter.append("Available displays: \(NSScreen.screens.map(screenSummary).joined(separator: " || "))\n")
    }

    func stop() {
        captureCurrentURL()
        fullscreenObservation = nil
        window?.orderOut(nil)
        enabled = false
        updateStatusItemTitle()
        reportWriter.flush()
    }

    func toggleOnCurrentDisplay() {
        guard enabled else { return }
        let targetScreen = screenAtMouse() ?? NSScreen.main ?? NSScreen.screens.first
        guard let targetScreen else { return }

        if let window, window.isVisible {
            let currentNumber = screenNumber(window.screen)
            let targetNumber = screenNumber(targetScreen)
            if currentNumber == targetNumber {
                window.orderOut(nil)
                reportWriter.append(
                    "lab_window_hidden shell={\(screenSummary(window.screen))} "
                        + "main={\(screenSummary(NSScreen.main))} pointer={\(screenSummary(screenAtMouse()))} "
                        + "webview=\(webViewIdentity(webView)) recovery_count=\(recoveryCount)"
                )
                return
            }
        }

        show(on: targetScreen)
    }

    func revealReport() {
        reportWriter.flush()
        NSWorkspace.shared.activateFileViewerSelecting([reportWriter.url])
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "rectangle.3.group",
            accessibilityDescription: "Fullscreen Repeatable Cross-Screen Recovery Lab"
        )
        button.image?.isTemplate = true
        button.imagePosition = .imageLeading
        updateStatusItemTitle()
        statusItem.menu = menu
    }

    private func configureMenu() {
        let titleItem = NSMenuItem(title: "Fullscreen Repeatable Recovery Lab", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        let enableItem = NSMenuItem(
            title: "Enable Repeatable Recovery Experiment",
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
            title: "Log Current Repair Context",
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
        captureCurrentURL()
        enabled = false
        window?.orderOut(nil)
        activeAttempt = nil
        updateStatusItemTitle()
        reportWriter.append("\nLAB HIDDEN/DISABLED — panel and current WKWebView retained.\n")
        reportWriter.flush()
    }

    @objc private func showLabHere() {
        guard enabled else { return }
        let targetScreen = screenAtMouse() ?? NSScreen.main ?? NSScreen.screens.first
        if let targetScreen {
            show(on: targetScreen)
        }
    }

    @objc private func logCurrentContext() {
        reportWriter.append(
            "REPAIR_CONTEXT main={\(screenSummary(NSScreen.main))} "
                + "shell={\(screenSummary(window?.screen))} pointer={\(screenSummary(screenAtMouse()))} "
                + "webview=\(webViewIdentity(webView)) recovery_scheduled=\(recoveryScheduled) "
                + "recovery_applied=\(recoveryApplied) recovery_count=\(recoveryCount) "
                + "verified_recoveries=\(verifiedRecoveryWebViews.count) key_window={\(windowSummary(NSApp.keyWindow))}"
        )
        reportWriter.flush()
    }

    @objc private func revealDesktopReport() {
        revealReport()
    }

    @objc private func resetDesktopReport() {
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
        installFreshWebView(in: newWindow, reason: "initial_environment")
        reportWriter.append(
            "SINGLE_PANEL_CREATED window={\(windowSummary(newWindow))} "
                + "webview=\(webViewIdentity(webView))"
        )
    }

    private func installFreshWebView(in window: NSWindow, reason: String) {
        let newWebView = WebViewFactory.makeWebView()
        newWebView.navigationDelegate = nil
        let root = PanelRootView(webView: newWebView)
        window.contentView = root

        webView = newWebView
        rootView = root
        observedFullscreenState = fullscreenStateName(newWebView.fullscreenState)
        attachFullscreenObservation(to: newWebView)
        newWebView.load(URLRequest(url: sourceURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 60))

        reportWriter.append(
            "WEBVIEW_INSTALLED reason=\(reason) webview=\(webViewIdentity(newWebView)) "
                + "url=\(sourceURL.absoluteString)"
        )
    }

    private func scheduleCrossScreenRecovery(retiring webView: WKWebView) {
        guard !recoveryScheduled, self.webView === webView else { return }
        recoveryScheduled = true
        recoveryApplied = false
        captureCurrentURL()
        let oldIdentity = webViewIdentity(webView)
        recoveryOldWebViewIdentity = oldIdentity
        recoveryNewWebViewIdentity = nil
        updateStatusItemTitle()

        reportWriter.append(
            "CROSS_SCREEN_RECOVERY_SCHEDULED next_recovery=\(recoveryCount + 1) "
                + "old_webview=\(oldIdentity) url=\(sourceURL.absoluteString) delay_ms=350"
        )
        reportWriter.flush()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak webView] in
            guard let self, let webView, self.webView === webView else { return }
            self.applyCrossScreenRecovery(retiring: webView)
        }
    }

    private func applyCrossScreenRecovery(retiring oldWebView: WKWebView) {
        guard let window, let oldRoot = rootView, webView === oldWebView else {
            recoveryScheduled = false
            updateStatusItemTitle()
            reportWriter.append("CROSS_SCREEN_RECOVERY_FAILED reason=missing_window_root_or_webview_changed")
            reportWriter.flush()
            return
        }

        captureCurrentURL()
        fullscreenObservation = nil
        let oldIdentity = webViewIdentity(oldWebView)
        retiredWebContents.append(RetiredWebContent(webView: oldWebView, rootView: oldRoot))

        webView = nil
        rootView = nil
        installFreshWebView(in: window, reason: "post_cross_screen_recovery")

        recoveryScheduled = false
        recoveryApplied = true
        recoveryCount += 1
        recoveryOldWebViewIdentity = oldIdentity
        recoveryNewWebViewIdentity = webViewIdentity(webView)

        if window.isVisible, let webView {
            window.makeFirstResponder(webView)
        }

        reportWriter.append(
            "CROSS_SCREEN_RECOVERY_APPLIED recovery=\(recoveryCount) same_panel_window=\(window.windowNumber) "
                + "old_webview=\(oldIdentity) new_webview=\(webViewIdentity(webView)) "
                + "retired_count=\(retiredWebContents.count) url=\(sourceURL.absoluteString)"
        )
        reportWriter.append("RECOVERY_READY #\(recoveryCount) · wait for page load before the next fullscreen attempt")
        updateStatusItemTitle()
        reportWriter.flush()
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
            reportWriter.append(
                "  recovery_state scheduled=\(recoveryScheduled) applied=\(recoveryApplied) "
                    + "count=\(recoveryCount) old=\(recoveryOldWebViewIdentity ?? "none") "
                    + "new=\(recoveryNewWebViewIdentity ?? "none") verified=\(verifiedRecoveryWebViews.count)"
            )
            if kind == .crossScreen {
                reportWriter.append("  CROSS-SCREEN CONDITION CONFIRMED · current shell and context/main differ")
            }
        }

        reportWriter.append(
            "  fullscreen_state \(oldState) -> \(newState) "
                + "webview_window={\(windowSummary(webView.window))} "
                + "main_now={\(screenSummary(NSScreen.main))}"
        )

        guard var attempt = activeAttempt else { return }

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
            if matchesContext {
                reportWriter.append("  TARGET MATCH · actual fullscreen follows context/main screen")
            } else {
                reportWriter.append(
                    "  TARGET MISMATCH · context/main={\(attempt.contextScreenSummary)} "
                        + "actual={\(screenSummary(actualScreen))}"
                )
            }
            return
        }

        if newState == "exitingFullscreen", !attempt.reachedFullscreen {
            attempt.failedBeforeFullscreen = true
            activeAttempt = attempt
            reportWriter.append("  FAILURE SIGNAL · WebKit exited before reaching inFullscreen")
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
                    + "kind=\(attempt.kind.rawValue) webview=\(attempt.webViewIdentity)"
            )

            if attempt.kind == .crossScreen, success {
                reportWriter.append(
                    "CROSS-SCREEN SUCCESS · current WKWebView becomes poisoned candidate; scheduling recovery every time"
                )
                scheduleCrossScreenRecovery(retiring: webView)
            }

            if attempt.kind == .postRecovery {
                let postRecoverySameScreen = attempt.contextScreenNumber != nil
                    && attempt.shellScreenNumber != nil
                    && attempt.contextScreenNumber == attempt.shellScreenNumber
                let belongsToLatestRecovery = recoveryApplied
                    && recoveryNewWebViewIdentity == attempt.webViewIdentity

                if belongsToLatestRecovery && postRecoverySameScreen && success {
                    verifiedRecoveryWebViews.insert(attempt.webViewIdentity)
                }

                reportWriter.append("\n================ REPEATABLE RECOVERY VERDICT ================")
                reportWriter.append("Latest recovery number: \(recoveryCount)")
                reportWriter.append("Attempt uses latest recovered WKWebView: \(belongsToLatestRecovery ? "YES" : "NO")")
                reportWriter.append("Post-recovery context and shell are same screen: \(postRecoverySameScreen ? "YES" : "NO")")
                reportWriter.append("Post-recovery fullscreen result: \(success ? "PASS" : "FAIL")")
                reportWriter.append("Verified recovered WKWebViews: \(verifiedRecoveryWebViews.count) / \(recoveryCount)")
                if belongsToLatestRecovery && postRecoverySameScreen && success {
                    reportWriter.append("LATEST CROSS-SCREEN WKWEBVIEW RECOVERY = PASS")
                } else if belongsToLatestRecovery && postRecoverySameScreen && !success {
                    reportWriter.append("LATEST CROSS-SCREEN WKWEBVIEW RECOVERY = FAIL")
                } else {
                    reportWriter.append("LATEST CROSS-SCREEN WKWEBVIEW RECOVERY = INCONCLUSIVE")
                }
                if recoveryCount >= 2 && verifiedRecoveryWebViews.count >= 2 {
                    reportWriter.append("REPEATABLE CROSS-SCREEN RECOVERY EXPERIMENT = PASS (2+ independent recoveries verified)")
                } else {
                    reportWriter.append("REPEATABLE CROSS-SCREEN RECOVERY EXPERIMENT = PENDING (need 2 independent recovered WKWebViews verified)")
                }
                reportWriter.append("=============================================================\n")
            }
            reportWriter.flush()
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
        return "class=\(String(describing: type(of: window))),number=\(window.windowNumber),visible=\(window.isVisible),key=\(window.isKeyWindow),frame=\(NSStringFromRect(window.frame)),screen={\(screenSummary(window.screen))},collection=\(window.collectionBehavior.rawValue)"
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

    private func updateStatusItemTitle() {
        guard let button = statusItem.button else { return }
        if enabled {
            if recoveryScheduled {
                button.title = "FS Repair ↻"
            } else if recoveryCount > 0 {
                button.title = "FS Repair ✓\(recoveryCount)"
            } else {
                button.title = "FS Repair"
            }
            button.toolTip = "Fullscreen repeatable cross-screen recovery experiment"
        } else {
            button.title = "FS Lab Off"
            button.toolTip = "FloatTabs Fullscreen Repeatable Cross-Screen Recovery Lab"
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
