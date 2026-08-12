import AppKit
import Foundation
import WebKit

enum FullscreenLabMode: Int, CaseIterable {
    case baseline = 0
    case freshWebViewPerDisplay = 1
    case plainNSWindowHost = 2
    case stableAutoresizingHost = 3

    var menuTitle: String {
        switch self {
        case .baseline:
            return "Mode 0 — Baseline"
        case .freshWebViewPerDisplay:
            return "Mode 1 — Fresh WKWebView per Display"
        case .plainNSWindowHost:
            return "Mode 2 — Plain NSWindow Host"
        case .stableAutoresizingHost:
            return "Mode 3 — Stable Autoresizing Host"
        }
    }

    var reportTitle: String {
        switch self {
        case .baseline:
            return "Baseline · FloatingPanel + existing logical host + persistent WKWebView"
        case .freshWebViewPerDisplay:
            return "Fresh WKWebView per Display · baseline host, new WKWebView whenever target display changes"
        case .plainNSWindowHost:
            return "Plain NSWindow Host · existing logical host + persistent WKWebView"
        case .stableAutoresizingHost:
            return "Stable Autoresizing Host · FloatingPanel + direct frame/autoresizing WKWebView host"
        }
    }
}

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
    private struct AttemptResult {
        let number: Int
        let displayLabel: String
        let displaySummary: String
        let webViewIdentity: String
        let sourceWindowSummary: String
        var reachedFullscreen: Bool
        var failedBeforeFullscreen: Bool
    }

    var onWillEnable: (() -> Void)?

    private let baselineCommit = "dad0ee79e6b70d07e659814aefde6d4f4701e221"
    private let reportWriter = FullscreenLabReportWriter()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private var modeItems: [FullscreenLabMode: NSMenuItem] = [:]
    private var currentMode: FullscreenLabMode?
    private var window: NSWindow?
    private var webView: WKWebView?
    private var rootView: NSView?
    private var fullscreenObservation: NSKeyValueObservation?
    private var observedFullscreenState = "notInFullscreen"
    private var sourceURL = URL(string: "https://www.youtube.com/")!
    private var lastHostScreenNumber: UInt32?
    private var displayLabels: [UInt32: String] = [:]
    private var nextDisplayLabelIndex = 0
    private var activeAttempt: AttemptResult?
    private var completedAttempts: [AttemptResult] = []
    private var runSequenceEvaluated = false
    private var runNumber = 0

    var isEnabled: Bool { currentMode != nil }
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
        FloatTabs Fullscreen Lab Report
        ===============================
        Baseline commit: \(baselineCommit)
        Started: \(now)
        OS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        PID: \(ProcessInfo.processInfo.processIdentifier)
        Report: \(reportWriter.url.path)

        Test contract
        -------------
        For each mode: A fullscreen -> exit -> B fullscreen -> exit -> A fullscreen.
        PASS means all first three attempts reached WKWebView.FullscreenState.inFullscreen
        with an A -> B -> A source-display sequence.

        Safety constraints
        ------------------
        No mouse event monitor, no NSWindow.sendEvent override, no injected JavaScript,
        no requestFullscreen/exitFullscreen wrapping, no closeAllMediaPresentations,
        and no mutation of WebKit-owned fullscreen windows.

        """
        reportWriter.reset(header: header)
        reportWriter.append("Available displays: \(NSScreen.screens.map(screenSummary).joined(separator: " || "))\n")
    }

    func stop() {
        captureCurrentURL()
        fullscreenObservation = nil
        window?.orderOut(nil)
        window?.close()
        window = nil
        webView = nil
        rootView = nil
        currentMode = nil
        refreshMenuState()
        updateStatusItemTitle()
        reportWriter.flush()
    }

    func toggleOnCurrentDisplay() {
        guard let mode = currentMode else { return }
        let targetScreen = screenAtMouse() ?? NSScreen.main ?? NSScreen.screens.first
        guard let targetScreen else { return }

        if let window, window.isVisible {
            let currentNumber = screenNumber(window.screen)
            let targetNumber = screenNumber(targetScreen)
            if currentNumber == targetNumber {
                window.orderOut(nil)
                reportWriter.append("lab_window_hidden mode=\(mode.rawValue) screen=\(screenSummary(targetScreen))")
                return
            }
        }

        show(mode: mode, on: targetScreen)
    }

    func revealReport() {
        reportWriter.flush()
        NSWorkspace.shared.activateFileViewerSelecting([reportWriter.url])
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "rectangle.3.group",
            accessibilityDescription: "Fullscreen Lab"
        )
        button.image?.isTemplate = true
        button.imagePosition = .imageLeading
        button.title = "FS Lab Off"
        button.toolTip = "FloatTabs Fullscreen Lab"
        statusItem.menu = menu
    }

    private func configureMenu() {
        let titleItem = NSMenuItem(title: "Fullscreen Lab", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        let offItem = NSMenuItem(
            title: "Off — Normal FloatTabs",
            action: #selector(disableLab),
            keyEquivalent: ""
        )
        offItem.target = self
        offItem.tag = -1
        menu.addItem(offItem)

        for mode in FullscreenLabMode.allCases {
            let item = NSMenuItem(
                title: mode.menuTitle,
                action: #selector(selectMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = mode.rawValue
            modeItems[mode] = item
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let showItem = NSMenuItem(
            title: "Show / Move Lab Here",
            action: #selector(showLabHere),
            keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)

        let reportItem = NSMenuItem(
            title: "Reveal Desktop Report",
            action: #selector(revealDesktopReport),
            keyEquivalent: ""
        )
        reportItem.target = self
        menu.addItem(reportItem)

        let resetItem = NSMenuItem(
            title: "Reset Desktop Report",
            action: #selector(resetDesktopReport),
            keyEquivalent: ""
        )
        resetItem.target = self
        menu.addItem(resetItem)

        refreshMenuState()
    }

    @objc private func disableLab() {
        captureCurrentURL()
        fullscreenObservation = nil
        window?.orderOut(nil)
        window?.close()
        window = nil
        webView = nil
        rootView = nil
        if let currentMode {
            reportWriter.append("\nLAB DISABLED from mode \(currentMode.rawValue)\n")
        }
        currentMode = nil
        activeAttempt = nil
        refreshMenuState()
        updateStatusItemTitle()
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let mode = FullscreenLabMode(rawValue: sender.tag) else { return }
        onWillEnable?()
        switchToMode(mode)
    }

    @objc private func showLabHere() {
        guard currentMode != nil else { return }
        toggleOnCurrentDisplay()
    }

    @objc private func revealDesktopReport() {
        revealReport()
    }

    @objc private func resetDesktopReport() {
        start()
        if let currentMode {
            reportWriter.append("Report reset while mode \(currentMode.rawValue) remained selected.\n")
        }
    }

    private func switchToMode(_ mode: FullscreenLabMode) {
        captureCurrentURL()
        fullscreenObservation = nil
        window?.orderOut(nil)
        window?.close()
        window = nil
        webView = nil
        rootView = nil

        currentMode = mode
        lastHostScreenNumber = nil
        displayLabels.removeAll()
        nextDisplayLabelIndex = 0
        activeAttempt = nil
        completedAttempts.removeAll()
        runSequenceEvaluated = false
        runNumber += 1

        let targetScreen = screenAtMouse() ?? NSScreen.main ?? NSScreen.screens.first
        reportWriter.append("\n============================================================")
        reportWriter.append("RUN \(runNumber) · MODE \(mode.rawValue) · \(mode.reportTitle)")
        reportWriter.append("Selected at: \(ISO8601DateFormatter().string(from: Date()))")
        if let targetScreen {
            reportWriter.append("Initial target display: \(screenSummary(targetScreen))")
        }
        reportWriter.append("============================================================")

        refreshMenuState()
        updateStatusItemTitle()

        if let targetScreen {
            show(mode: mode, on: targetScreen)
        }
    }

    private func show(mode: FullscreenLabMode, on targetScreen: NSScreen) {
        let targetNumber = screenNumber(targetScreen)

        if window == nil {
            createEnvironment(mode: mode, targetScreen: targetScreen)
        } else if mode == .freshWebViewPerDisplay,
                  let lastHostScreenNumber,
                  let targetNumber,
                  lastHostScreenNumber != targetNumber {
            let newFrame = frame(for: targetScreen)
            window?.setFrame(newFrame, display: false)
            rebuildWebViewForFreshDisplay(targetScreen: targetScreen)
        } else {
            window?.setFrame(frame(for: targetScreen), display: false)
        }

        lastHostScreenNumber = targetNumber
        let label = displayLabel(for: targetScreen)
        reportWriter.append(
            "lab_window_shown mode=\(mode.rawValue) display=\(label) target={\(screenSummary(targetScreen))} "
                + "source_window={\(windowSummary(window))} webview=\(webViewIdentity(webView))"
        )

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if let webView {
            DispatchQueue.main.async { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.window?.makeFirstResponder(webView)
            }
        }
    }

    private func createEnvironment(mode: FullscreenLabMode, targetScreen: NSScreen) {
        let targetFrame = frame(for: targetScreen)
        let newWindow: NSWindow

        switch mode {
        case .plainNSWindowHost:
            let ordinaryWindow = NSWindow(
                contentRect: targetFrame,
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            ordinaryWindow.title = "FloatTabs Fullscreen Lab — Mode 2"
            ordinaryWindow.isReleasedWhenClosed = false
            ordinaryWindow.level = .normal
            ordinaryWindow.collectionBehavior = []
            newWindow = ordinaryWindow

        case .baseline, .freshWebViewPerDisplay, .stableAutoresizingHost:
            newWindow = FloatingPanel(contentRect: targetFrame)
        }

        window = newWindow
        installNewWebView(mode: mode, in: newWindow)
    }

    private func rebuildWebViewForFreshDisplay(targetScreen: NSScreen) {
        guard currentMode == .freshWebViewPerDisplay,
              let window else { return }
        captureCurrentURL()
        let oldIdentity = webViewIdentity(webView)
        fullscreenObservation = nil
        webView?.removeFromSuperview()
        webView = nil
        rootView = nil
        installNewWebView(mode: .freshWebViewPerDisplay, in: window)
        reportWriter.append(
            "fresh_webview_created_for_display old=\(oldIdentity) new=\(webViewIdentity(webView)) "
                + "target={\(screenSummary(targetScreen))}"
        )
    }

    private func installNewWebView(mode: FullscreenLabMode, in window: NSWindow) {
        let newWebView = WebViewFactory.makeWebView()
        newWebView.navigationDelegate = nil

        switch mode {
        case .baseline, .freshWebViewPerDisplay, .plainNSWindowHost:
            let root = PanelRootView(webView: newWebView)
            window.contentView = root
            rootView = root

        case .stableAutoresizingHost:
            let host = NSView(frame: NSRect(origin: .zero, size: window.contentView?.bounds.size ?? window.frame.size))
            host.wantsLayer = true
            host.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            host.autoresizingMask = [.width, .height]
            newWebView.translatesAutoresizingMaskIntoConstraints = true
            newWebView.autoresizingMask = [.width, .height]
            newWebView.frame = host.bounds
            host.addSubview(newWebView)
            window.contentView = host
            rootView = host
        }

        webView = newWebView
        observedFullscreenState = fullscreenStateName(newWebView.fullscreenState)
        attachFullscreenObservation(to: newWebView)
        newWebView.load(URLRequest(url: sourceURL, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 60))
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
        guard let mode = currentMode else { return }
        let oldState = observedFullscreenState
        let newState = fullscreenStateName(webView.fullscreenState)
        observedFullscreenState = newState

        if newState == "enteringFullscreen" {
            let screen = hostScreen() ?? screenAtMouse() ?? NSScreen.main
            let label = screen.map(displayLabel) ?? "?"
            let attempt = AttemptResult(
                number: completedAttempts.count + 1,
                displayLabel: label,
                displaySummary: screenSummary(screen),
                webViewIdentity: webViewIdentity(webView),
                sourceWindowSummary: windowSummary(window),
                reachedFullscreen: false,
                failedBeforeFullscreen: false
            )
            activeAttempt = attempt
            reportWriter.append("\nATTEMPT \(attempt.number) START · mode=\(mode.rawValue) display=\(label)")
            reportWriter.append("  source_display={\(attempt.displaySummary)}")
            reportWriter.append("  source_window={\(attempt.sourceWindowSummary)}")
            reportWriter.append("  webview=\(attempt.webViewIdentity)")
        }

        reportWriter.append(
            "  fullscreen_state \(oldState) -> \(newState) "
                + "webview_window={\(windowSummary(webView.window))} "
                + "main_screen={\(screenSummary(NSScreen.main))}"
        )

        guard var attempt = activeAttempt else { return }

        if newState == "inFullscreen" {
            attempt.reachedFullscreen = true
            activeAttempt = attempt
            reportWriter.append(
                "  REACHED inFullscreen · fullscreen_window={\(windowSummary(webView.window))}"
            )
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
            let success = attempt.reachedFullscreen && !attempt.failedBeforeFullscreen
            reportWriter.append(
                "ATTEMPT \(attempt.number) RESULT = \(success ? "PASS" : "FAIL") "
                    + "display=\(attempt.displayLabel) webview=\(attempt.webViewIdentity)"
            )
            evaluateRunIfReady(mode: mode)
        }
    }

    private func evaluateRunIfReady(mode: FullscreenLabMode) {
        guard !runSequenceEvaluated, completedAttempts.count >= 3 else { return }
        runSequenceEvaluated = true
        let firstThree = Array(completedAttempts.prefix(3))
        let sequence = firstThree.map(\.displayLabel)
        let allSucceeded = firstThree.allSatisfy {
            $0.reachedFullscreen && !$0.failedBeforeFullscreen
        }
        let sequenceIsABA = sequence.count == 3
            && sequence[0] == "A"
            && sequence[1] == "B"
            && sequence[2] == "A"
        let passed = allSucceeded && sequenceIsABA

        reportWriter.append("\n---------------- MODE \(mode.rawValue) SUMMARY ----------------")
        reportWriter.append("Observed sequence: \(sequence.joined(separator: " -> "))")
        reportWriter.append("Attempt results: \(firstThree.map { ($0.reachedFullscreen && !$0.failedBeforeFullscreen) ? "PASS" : "FAIL" }.joined(separator: ", "))")
        reportWriter.append("A -> B -> A RESULT = \(passed ? "PASS" : "FAIL")")
        if !sequenceIsABA {
            reportWriter.append("Reason: first three source displays were not A -> B -> A; repeat this mode after Reset Report if needed.")
        } else if !allSucceeded {
            let failed = firstThree.filter { !$0.reachedFullscreen || $0.failedBeforeFullscreen }.map { String($0.number) }
            reportWriter.append("Failed attempt(s): \(failed.joined(separator: ", "))")
        }
        reportWriter.append("------------------------------------------------------\n")
        reportWriter.flush()
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
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    private func hostScreen() -> NSScreen? {
        if let windowScreen = window?.screen {
            return windowScreen
        }
        if let lastHostScreenNumber {
            return NSScreen.screens.first { screenNumber($0) == lastHostScreenNumber }
        }
        return nil
    }

    private func displayLabel(for screen: NSScreen) -> String {
        guard let number = screenNumber(screen) else { return "?" }
        if let existing = displayLabels[number] { return existing }

        let label: String
        switch nextDisplayLabelIndex {
        case 0: label = "A"
        case 1: label = "B"
        default: label = "D\(nextDisplayLabelIndex + 1)"
        }
        nextDisplayLabelIndex += 1
        displayLabels[number] = label
        return label
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

    private func refreshMenuState() {
        for (mode, item) in modeItems {
            item.state = currentMode == mode ? .on : .off
        }
    }

    private func updateStatusItemTitle() {
        guard let button = statusItem.button else { return }
        if let currentMode {
            button.title = "FS\(currentMode.rawValue)"
            button.toolTip = "Fullscreen Lab · \(currentMode.menuTitle)"
        } else {
            button.title = "FS Lab Off"
            button.toolTip = "FloatTabs Fullscreen Lab"
        }
    }
}
