import AppKit
import WebKit

/// Passive fullscreen diagnostics for the baseline reproduction branch.
///
/// Important constraints:
/// - does not intercept NSWindow.sendEvent
/// - does not install local/global mouse monitors
/// - does not inject JavaScript into pages or iframes
/// - does not call any fullscreen/media API
/// - does not mutate WKWebView/window hierarchy or geometry
final class FullscreenDiagnostics: NSObject {
    static let shared = FullscreenDiagnostics()

    private struct AttemptState {
        let id: Int
        var reachedInFullscreen = false
        var lastState = "notInFullscreen"
    }

    private let logURL: URL
    private let logQueue = DispatchQueue(label: "FloatTabs.FullscreenDiagnostics.Log")
    private var observerTokens: [NSObjectProtocol] = []
    private var fullscreenObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private var frameObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private var slotIDs: [ObjectIdentifier: UUID] = [:]
    private var attempts: [ObjectIdentifier: AttemptState] = [:]
    private var nextAttemptID = 1

    private override init() {
        let logsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/FloatTabs", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: logsDirectory,
            withIntermediateDirectories: true
        )
        logURL = logsDirectory.appendingPathComponent("fullscreen-baseline-debug.log")
        super.init()
        try? Data().write(to: logURL, options: .atomic)
    }

    @MainActor
    func startApplicationTracing() {
        let center = NotificationCenter.default
        let workspaceCenter = NSWorkspace.shared.notificationCenter

        let windowNotifications: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didResignMainNotification,
            NSWindow.didMoveNotification,
            NSWindow.didResizeNotification,
            NSWindow.didChangeScreenNotification,
            NSWindow.didChangeScreenProfileNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
            NSWindow.willEnterFullScreenNotification,
            NSWindow.willExitFullScreenNotification,
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.willCloseNotification,
        ]

        for name in windowNotifications {
            observerTokens.append(center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      let window = notification.object as? NSWindow else { return }
                self.log(
                    "window_notification",
                    fields: [
                        "name": name.rawValue,
                        "window": self.windowSummary(window),
                    ]
                )
            })
        }

        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            observerTokens.append(center.addObserver(
                forName: name,
                object: NSApp,
                queue: .main
            ) { [weak self] notification in
                guard let self else { return }
                self.log(
                    "application_activity",
                    fields: [
                        "name": notification.name.rawValue,
                        "active": String(NSApp.isActive),
                        "key_window": self.windowSummary(NSApp.keyWindow),
                        "main_window": self.windowSummary(NSApp.mainWindow),
                    ]
                )
            })
        }

        observerTokens.append(workspaceCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.log("active_space_changed", fields: self.globalScreenFields())
            self.logAllWindows(reason: "active_space_changed")
        })

        log(
            "diagnostics_started",
            fields: [
                "mode": "passive_only",
                "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "pid": String(ProcessInfo.processInfo.processIdentifier),
                "screens": screenInventory(),
            ]
        )
        logAllWindows(reason: "launch")
    }

    @MainActor
    func attach(webView: WKWebView, slotID: UUID) {
        let objectID = ObjectIdentifier(webView)
        guard fullscreenObservations[objectID] == nil else { return }
        slotIDs[objectID] = slotID

        fullscreenObservations[objectID] = webView.observe(
            \.fullscreenState,
            options: [.initial, .old, .new]
        ) { [weak self, weak webView] _, change in
            DispatchQueue.main.async {
                guard let self, let webView else { return }
                self.handleFullscreenStateChange(webView: webView, change: change)
            }
        }

        frameObservations[objectID] = webView.observe(
            \.frame,
            options: [.old, .new]
        ) { [weak self, weak webView] _, change in
            DispatchQueue.main.async {
                guard let self, let webView,
                      let oldFrame = change.oldValue,
                      let newFrame = change.newValue,
                      oldFrame != newFrame else { return }

                let state = self.fullscreenStateName(webView.fullscreenState)
                let windowClass = webView.window.map { String(describing: type(of: $0)) } ?? "nil"
                let suspicious = state != "notInFullscreen"
                    || windowClass.localizedCaseInsensitiveContains("fullscreen")
                    || windowClass.localizedCaseInsensitiveContains("webcore")

                self.log(
                    suspicious ? "webview_frame_changed_during_fullscreen" : "webview_frame_changed",
                    fields: [
                        "slot": self.slotID(for: webView),
                        "webview": self.objectAddress(webView),
                        "state": state,
                        "old": NSStringFromRect(oldFrame),
                        "new": NSStringFromRect(newFrame),
                        "window": self.windowSummary(webView.window),
                        "superview": self.viewSummary(webView.superview),
                    ]
                )
            }
        }

        log("webview_observation_started", fields: webViewFields(webView))
    }

    @MainActor
    private func handleFullscreenStateChange(
        webView: WKWebView,
        change: NSKeyValueObservedChange<WKWebView.FullscreenState>
    ) {
        let objectID = ObjectIdentifier(webView)
        let oldState = change.oldValue.map(fullscreenStateName) ?? "unknown"
        let newState = change.newValue.map(fullscreenStateName)
            ?? fullscreenStateName(webView.fullscreenState)

        if newState == "enteringFullscreen" {
            let attemptID = nextAttemptID
            nextAttemptID += 1
            attempts[objectID] = AttemptState(
                id: attemptID,
                reachedInFullscreen: false,
                lastState: newState
            )
            var fields = webViewFields(webView)
            fields["attempt"] = String(attemptID)
            fields["from"] = oldState
            fields["to"] = newState
            fields["current_event"] = currentEventSummary()
            fields.merge(globalScreenFields()) { current, _ in current }
            log("attempt_started", fields: fields)
        } else if var attempt = attempts[objectID] {
            if newState == "inFullscreen" {
                attempt.reachedInFullscreen = true
                attempt.lastState = newState
                attempts[objectID] = attempt
                log(
                    "attempt_succeeded",
                    fields: [
                        "attempt": String(attempt.id),
                        "slot": slotID(for: webView),
                    ]
                )
            } else if newState == "exitingFullscreen" && !attempt.reachedInFullscreen {
                attempt.lastState = newState
                attempts[objectID] = attempt
                log(
                    "attempt_enter_aborted",
                    fields: [
                        "attempt": String(attempt.id),
                        "slot": slotID(for: webView),
                        "transition": "\(oldState)->\(newState)",
                    ]
                )
            } else if newState == "notInFullscreen" {
                log(
                    attempt.reachedInFullscreen ? "attempt_completed" : "attempt_failed",
                    fields: [
                        "attempt": String(attempt.id),
                        "slot": slotID(for: webView),
                        "last_state": attempt.lastState,
                        "transition": "\(oldState)->\(newState)",
                    ]
                )
                attempts.removeValue(forKey: objectID)
            } else {
                attempt.lastState = newState
                attempts[objectID] = attempt
            }
        }

        var fields = webViewFields(webView)
        fields["old_state"] = oldState
        fields["new_state"] = newState
        fields["current_event"] = currentEventSummary()
        fields.merge(globalScreenFields()) { current, _ in current }
        log("webkit_fullscreen_state", fields: fields)
        logAllWindows(reason: "webkit_fullscreen_state_\(newState)")
    }

    @MainActor
    private func webViewFields(_ webView: WKWebView) -> [String: String] {
        [
            "slot": slotID(for: webView),
            "webview": objectAddress(webView),
            "state": fullscreenStateName(webView.fullscreenState),
            "frame": NSStringFromRect(webView.frame),
            "bounds": NSStringFromRect(webView.bounds),
            "superview": viewSummary(webView.superview),
            "window": windowSummary(webView.window),
            "url": webView.url?.absoluteString ?? "nil",
        ]
    }

    @MainActor
    private func logAllWindows(reason: String) {
        let windows = NSApp.windows.sorted { $0.windowNumber < $1.windowNumber }
        log(
            "windows_snapshot",
            fields: [
                "reason": reason,
                "count": String(windows.count),
                "windows": windows.map(windowSummary).joined(separator: " || "),
            ]
        )
    }

    @MainActor
    private func globalScreenFields() -> [String: String] {
        let mouse = NSEvent.mouseLocation
        let mouseScreen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
        return [
            "mouse": NSStringFromPoint(mouse),
            "mouse_screen": screenSummary(mouseScreen),
            "main_screen": screenSummary(NSScreen.main),
            "key_window": windowSummary(NSApp.keyWindow),
            "main_window": windowSummary(NSApp.mainWindow),
        ]
    }

    @MainActor
    private func screenInventory() -> String {
        NSScreen.screens.map(screenSummary).joined(separator: " || ")
    }

    @MainActor
    private func currentEventSummary() -> String {
        guard let event = NSApp.currentEvent else { return "nil" }
        return [
            "type=\(String(describing: event.type))",
            "clickCount=\(event.clickCount)",
            "location=\(NSStringFromPoint(event.locationInWindow))",
            "windowNumber=\(event.windowNumber)",
        ].joined(separator: ",")
    }

    @MainActor
    private func windowSummary(_ window: NSWindow?) -> String {
        guard let window else { return "nil" }
        return [
            "class=\(String(describing: type(of: window)))",
            "number=\(window.windowNumber)",
            "visible=\(window.isVisible)",
            "key=\(window.isKeyWindow)",
            "main=\(window.isMainWindow)",
            "level=\(window.level.rawValue)",
            "frame=\(NSStringFromRect(window.frame))",
            "screen={\(screenSummary(window.screen))}",
            "collection=\(window.collectionBehavior.rawValue)",
        ].joined(separator: ",")
    }

    @MainActor
    private func screenSummary(_ screen: NSScreen?) -> String {
        guard let screen else { return "nil" }
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            .map { String(describing: $0) } ?? "nil"
        return "name=\(screen.localizedName),number=\(number),frame=\(NSStringFromRect(screen.frame)),visible=\(NSStringFromRect(screen.visibleFrame))"
    }

    @MainActor
    private func viewSummary(_ view: NSView?) -> String {
        guard let view else { return "nil" }
        return "class=\(String(describing: type(of: view))),address=\(objectAddress(view)),frame=\(NSStringFromRect(view.frame)),bounds=\(NSStringFromRect(view.bounds))"
    }

    private func slotID(for webView: WKWebView) -> String {
        slotIDs[ObjectIdentifier(webView)]?.uuidString ?? "unknown"
    }

    private func objectAddress(_ object: AnyObject) -> String {
        String(describing: Unmanaged.passUnretained(object).toOpaque())
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

    private func log(_ event: String, fields: [String: String] = [:]) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let details = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(Self.sanitize($0.value))" }
            .joined(separator: " ")
        let line = "\(timestamp) event=\(event) \(details)\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = logURL

        logQueue.async {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        }
    }

    private static func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        FullscreenDiagnostics.shared.startApplicationTracing()

        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.prepareForTermination()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
