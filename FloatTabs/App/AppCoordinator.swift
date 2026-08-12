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
        case postCross = "POST-CROSS"
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

    var onWillEnable: (() -> Void)?

    private let baselineCommit = "dad0ee79e6b70d07e659814aefde6d4f4701e221"
    private let reportWriter = FullscreenLabReportWriter()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private var enabled = false
    private var window: NSWindow?
    private var webView: WKWebView?
    private var rootView: NSView?
    private var fullscreenObservation: NSKeyValueObservation?
    private var observedFullscreenState = "notInFullscreen"
    private var sourceURL = URL(string: "https://www.youtube.com/")!
    private var activeAttempt: AttemptResult?
    private var completedAttempts: [AttemptResult] = []
    private var completedCrossScreenAttempt = false

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
        FloatTabs Fullscreen Screen-Context Lab
        =======================================
        Baseline commit: \(baselineCommit)
        Started: \(now)
        OS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        PID: \(ProcessInfo.processInfo.processIdentifier)
        Report: \(reportWriter.url.path)

        Root-cause contract
        -------------------
        We now distinguish three displays for every fullscreen attempt:
          1. context/main screen: the screen WebKit/macOS currently treats as the active target
          2. shell screen: the screen that physically hosts the FloatTabs WKWebView
          3. actual fullscreen screen: the screen used by WebCoreFullScreenWindow

        A CROSS-SCREEN attempt (context != shell) is NOT automatically a failure.
        It is correct when actual fullscreen follows context/main.
        The primary regression under test is whether a successful CROSS-SCREEN attempt
        poisons the SAME WKWebView so that the next same-screen fullscreen aborts or mis-targets.

        Recommended sequence
        --------------------
        Attempt 1: SAME-SCREEN CONTROL (activate A, shell A, fullscreen A, exit)
        Attempt 2: CROSS-SCREEN (activate B, move pointer to A, summon shell A, fullscreen should go B, exit)
        Attempt 3: POST-CROSS (activate A, shell A, fullscreen A)

        Safety constraints
        ------------------
        One FloatingPanel and one persistent WKWebView for the entire process.
        No mode switching, no extra experiment windows, no mouse event monitor,
        no NSWindow.sendEvent override, no injected JavaScript, no fullscreen API wrapping,
        no closeAllMediaPresentations, and no WebKit-owned fullscreen-window mutation.

        """
        reportWriter.reset(header: header)
        completedAttempts.removeAll()
        activeAttempt = nil
        completedCrossScreenAttempt = false
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
                        + "main={\(screenSummary(NSScreen.main))} pointer={\(screenSummary(screenAtMouse()))}"
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
            accessibilityDescription: "Fullscreen Screen Context Lab"
        )
        button.image?.isTemplate = true
        button.imagePosition = .imageLeading
        updateStatusItemTitle()
        statusItem.menu = menu
    }

    private func configureMenu() {
        let titleItem = NSMenuItem(title: "Fullscreen Screen-Context Lab", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        let enableItem = NSMenuItem(
            title: "Enable Single Baseline Lab",
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
            title: "Log Current Screen Context",
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
            title: "Reset Report / Attempts (same WKWebView)",
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
        reportWriter.append("\nLAB HIDDEN/DISABLED — WKWebView retained; no new window created.\n")
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
            "CONTEXT_SNAPSHOT main={\(screenSummary(NSScreen.main))} "
                + "shell={\(screenSummary(window?.screen))} pointer={\(screenSummary(screenAtMouse()))} "
                + "key_window={\(windowSummary(NSApp.keyWindow))} lab_window={\(windowSummary(window))}"
        )
        reportWriter.flush()
    }

    @objc private func revealDesktopReport() {
        revealReport()
    }

    @objc private func resetDesktopReport() {
        start()
        reportWriter.append("Reset performed with SAME WKWebView retained: \(webViewIdentity(webView))")
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
                + "webview=\(webViewIdentity(webView))"
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
                + "window={\(windowSummary(window))}"
        )
        reportWriter.flush()
    }

    private func createEnvironment(on targetScreen: NSScreen) {
        let newWindow = FloatingPanel(contentRect: frame(for: targetScreen))
        let newWebView = WebViewFactory.makeWebView()
        newWebView.navigationDelegate = nil
        let root = PanelRootView(webView: newWebView)
        newWindow.contentView = root

        window = newWindow
        webView = newWebView
        rootView = root
        observedFullscreenState = fullscreenStateName(newWebView.fullscreenState)
        attachFullscreenObservation(to: newWebView)
        newWebView.load(URLRequest(url: sourceURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 60))

        reportWriter.append(
            "SINGLE_ENVIRONMENT_CREATED window={\(windowSummary(newWindow))} "
                + "webview=\(webViewIdentity(newWebView))"
        )
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

            let kind: AttemptKind
            if completedCrossScreenAttempt {
                kind = .postCross
            } else if let contextNumber, let shellNumber, contextNumber == shellNumber {
                kind = .sameScreenControl
            } else if contextNumber != nil, shellNumber != nil {
                kind = .crossScreen
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
                webViewIdentity: webViewIdentity(webView),
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
                reportWriter.append("  CROSS-SCREEN CONDITION CONFIRMED · shell and context/main differ")
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
                    + "kind=\(attempt.kind.rawValue)"
            )

            if attempt.kind == .crossScreen, success {
                completedCrossScreenAttempt = true
                reportWriter.append(
                    "CROSS-SCREEN PRIMER COMPLETE · next fullscreen attempt will be classified POST-CROSS"
                )
            }

            if attempt.kind == .postCross {
                let postCrossSameScreen = attempt.contextScreenNumber != nil
                    && attempt.shellScreenNumber != nil
                    && attempt.contextScreenNumber == attempt.shellScreenNumber
                reportWriter.append("\n================ POST-CROSS VERDICT ================")
                reportWriter.append("Post-cross context and shell are same screen: \(postCrossSameScreen ? "YES" : "NO")")
                reportWriter.append("Post-cross fullscreen result: \(success ? "PASS" : "FAIL")")
                if postCrossSameScreen && !success {
                    reportWriter.append("POST-CROSS REGRESSION REPRODUCED = YES")
                } else if postCrossSameScreen && success {
                    reportWriter.append("POST-CROSS REGRESSION REPRODUCED = NO")
                } else {
                    reportWriter.append("POST-CROSS REGRESSION REPRODUCED = INCONCLUSIVE (post-cross attempt was not same-screen)")
                }
                reportWriter.append("====================================================\n")
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
            button.title = "FS Context"
            button.toolTip = "Fullscreen Screen-Context Lab · single persistent WKWebView"
        } else {
            button.title = "FS Lab Off"
            button.toolTip = "FloatTabs Fullscreen Screen-Context Lab"
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
