import AppKit
import WebKit

final class FullscreenDiagnostics: NSObject, WKScriptMessageHandler {
    static let shared = FullscreenDiagnostics()
    static let messageHandlerName = "floatTabsFullscreenDiagnostics"

    private struct AttemptState {
        let id: Int
        var reachedInFullscreen = false
        var lastState = "notInFullscreen"
    }

    private let lock = NSLock()
    private let logURL: URL
    private var observerTokens: [NSObjectProtocol] = []
    private var fullscreenObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private var frameObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private var slotIDs: [ObjectIdentifier: UUID] = [:]
    private var attempts: [ObjectIdentifier: AttemptState] = [:]
    private var nextAttemptID = 1
    private var sequence: UInt64 = 0

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
                self?.log(
                    "application_activity",
                    fields: [
                        "name": notification.name.rawValue,
                        "active": String(NSApp.isActive),
                        "key_window": self?.windowSummary(NSApp.keyWindow) ?? "nil",
                        "main_window": self?.windowSummary(NSApp.mainWindow) ?? "nil",
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

        let controller = webView.configuration.userContentController
        controller.add(self, name: Self.messageHandlerName)
        controller.addUserScript(WKUserScript(
            source: Self.domDiagnosticScript(slotID: slotID),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))

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

                let windowClass = webView.window.map { String(describing: type(of: $0)) } ?? "nil"
                let state = self.fullscreenStateName(webView.fullscreenState)
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
                        "call_stack": suspicious ? Thread.callStackSymbols.joined(separator: " <- ") : "",
                    ]
                )
            }
        }

        log(
            "webview_attached_to_diagnostics",
            fields: webViewFields(webView)
        )
    }

    @MainActor
    func recordPanelInput(event: NSEvent, panel: NSPanel) {
        guard event.type == .leftMouseDown
                || event.type == .rightMouseDown
                || event.type == .otherMouseDown
                || event.type == .keyDown else { return }

        var fields = globalScreenFields()
        fields["event"] = String(describing: event.type)
        fields["key_code"] = String(event.keyCode)
        fields["characters"] = event.charactersIgnoringModifiers ?? ""
        fields["panel"] = windowSummary(panel)
        log("panel_input", fields: fields)
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.messageHandlerName,
              let body = message.body as? [String: Any] else { return }

        var fields: [String: String] = [:]
        for (key, value) in body {
            fields[key] = String(describing: value)
        }
        fields["is_main_frame"] = String(message.frameInfo.isMainFrame)
        fields["frame_url"] = message.frameInfo.request.url?.absoluteString ?? "nil"
        log("dom_fullscreen_event", fields: fields)
    }

    @MainActor
    private func handleFullscreenStateChange(
        webView: WKWebView,
        change: NSKeyValueObservedChange<WKWebView.FullscreenState>
    ) {
        let objectID = ObjectIdentifier(webView)
        let oldState = change.oldValue.map(fullscreenStateName) ?? "unknown"
        let newState = change.newValue.map(fullscreenStateName) ?? fullscreenStateName(webView.fullscreenState)

        if newState == "enteringFullscreen" {
            let attemptID = nextAttemptID
            nextAttemptID += 1
            attempts[objectID] = AttemptState(id: attemptID, reachedInFullscreen: false, lastState: newState)
            log(
                "attempt_started",
                fields: [
                    "attempt": String(attemptID),
                    "slot": slotID(for: webView),
                    "webview": objectAddress(webView),
                    "from": oldState,
                    "to": newState,
                ]
            )
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
        lock.lock()
        defer { lock.unlock() }

        sequence &+= 1
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let details = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(sanitize($0.value))" }
            .joined(separator: " ")
        let line = "\(timestamp) seq=\(sequence) event=\(event) \(details)\n"
        guard let data = line.data(using: .utf8) else { return }

        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }

    private func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private static func domDiagnosticScript(slotID: UUID) -> String {
        """
        (() => {
          if (window.__floatTabsFullscreenDiagnosticsInstalled) return;
          window.__floatTabsFullscreenDiagnosticsInstalled = true;
          const slot = '\(slotID.uuidString)';
          const elementDescription = (element) => {
            if (!element) return 'nil';
            const id = element.id ? `#${element.id}` : '';
            const cls = typeof element.className === 'string' && element.className
              ? `.${element.className.trim().replace(/\\s+/g, '.')}`
              : '';
            return `${element.tagName || 'unknown'}${id}${cls}`;
          };
          const send = (event, extra = {}) => {
            try {
              const fs = document.fullscreenElement || document.webkitFullscreenElement || null;
              window.webkit.messageHandlers.\(messageHandlerName).postMessage({
                slot,
                event,
                href: location.href,
                readyState: document.readyState,
                visibilityState: document.visibilityState,
                fullscreenElement: elementDescription(fs),
                userActivationActive: navigator.userActivation ? navigator.userActivation.isActive : 'unsupported',
                userActivationEver: navigator.userActivation ? navigator.userActivation.hasBeenActive : 'unsupported',
                ...extra,
              });
            } catch (_) {}
          };
          document.addEventListener('fullscreenchange', () => send('fullscreenchange'), true);
          document.addEventListener('webkitfullscreenchange', () => send('webkitfullscreenchange'), true);
          document.addEventListener('fullscreenerror', (e) => send('fullscreenerror', { errorType: e.type }), true);
          document.addEventListener('webkitfullscreenerror', (e) => send('webkitfullscreenerror', { errorType: e.type }), true);
          document.addEventListener('dblclick', (e) => send('dblclick', { target: elementDescription(e.target) }), true);
          document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape') send('escape_keydown');
          }, true);
          window.addEventListener('pagehide', () => send('pagehide'), true);
          window.addEventListener('pageshow', () => send('pageshow'), true);
          send('diagnostics_script_ready');
        })();
        """
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
