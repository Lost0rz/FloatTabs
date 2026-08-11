import AppKit
import KeyboardShortcuts

@MainActor
enum FloatTabsDiagnostics {
#if DEBUG
    private static let sessionID = String(UUID().uuidString.prefix(8))
    private static let writeQueue = DispatchQueue(label: "com.floattabs.fullscreen-diagnostics")
    private static var sequence = 0
    private static var started = false
    private static var observerTokens: [NSObjectProtocol] = []
    private static var localMouseMonitor: Any?
    private static var snapshotTimer: Timer?
    private static var lastWindowFingerprint: String?
    private static var pendingDoubleClickCandidateID: String?
    private static var pendingDoubleClickStartedAt: Date?
    private static var candidateWatchdog: DispatchWorkItem?

    static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/FloatTabs", isDirectory: true)
            .appendingPathComponent("fullscreen-debug.log", isDirectory: false)
    }
#endif

    static func start() {
#if DEBUG
        guard !started else { return }
        started = true
        prepareLogFile(at: logURL)
        record("session_start", fields: globalFields())

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observerTokens.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    record("active_space_changed", fields: globalFields())
                    captureWindowSnapshotIfChanged(force: true)
                }
            }
        )
        observerTokens.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { notification in
                Task { @MainActor in
                    let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication
                    record(
                        "frontmost_application_changed",
                        fields: globalFields().merging([
                            "bundle_id": application?.bundleIdentifier ?? "nil",
                            "pid": application.map { String($0.processIdentifier) } ?? "nil",
                        ]) { _, new in new }
                    )
                }
            }
        )

        let windowNotifications: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didMoveNotification,
            NSWindow.didChangeScreenNotification,
            NSWindow.willEnterFullScreenNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.willExitFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
        ]
        for name in windowNotifications {
            observerTokens.append(
                NotificationCenter.default.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { notification in
                    Task { @MainActor in
                        guard let window = notification.object as? NSWindow else { return }
                        record(
                            "window_notification",
                            fields: [
                                "notification": name.rawValue,
                                "window": windowSummary(window),
                            ].merging(globalFields()) { _, new in new }
                        )
                        captureWindowSnapshotIfChanged(force: true)
                    }
                }
            )
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { event in
            Task { @MainActor in
                handleLocalMouseDown(event)
            }
            return event
        }

        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 0.20, repeats: true) { _ in
            Task { @MainActor in
                captureWindowSnapshotIfChanged()
            }
        }
        captureWindowSnapshotIfChanged(force: true)
#endif
    }

    static func record(_ event: String, fields: [String: String] = [:]) {
#if DEBUG
        sequence += 1
        var payload = fields
        payload["event"] = event
        payload["seq"] = String(sequence)
        payload["session"] = sessionID
        payload["time"] = ISO8601DateFormatter().string(from: Date())

        guard JSONSerialization.isValidJSONObject(payload),
              let json = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            return
        }
        var line = json
        line.append(0x0A)
        let url = logURL
        writeQueue.async {
            append(line, to: url)
        }
#endif
    }

    static func markFullscreenReachedStableState(_ window: NSWindow) {
#if DEBUG
        guard let candidateID = pendingDoubleClickCandidateID else { return }
        candidateWatchdog?.cancel()
        candidateWatchdog = nil
        let elapsed = pendingDoubleClickStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        record(
            "fullscreen_candidate_success",
            fields: [
                "candidate": candidateID,
                "elapsed_ms": String(Int(elapsed * 1000)),
                "reason": "webkit_fullscreen_state_reached_inFullscreen",
                "fullscreen_window": windowSummary(window),
                "windows": allWindowSummary(),
            ].merging(globalFields()) { _, new in new }
        )
        pendingDoubleClickCandidateID = nil
        pendingDoubleClickStartedAt = nil
#endif
    }

    static func stop() {
#if DEBUG
        record("session_end", fields: globalFields())
        candidateWatchdog?.cancel()
        candidateWatchdog = nil
        snapshotTimer?.invalidate()
        snapshotTimer = nil
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        observerTokens.removeAll()
#endif
    }

#if DEBUG
    private static func handleLocalMouseDown(_ event: NSEvent) {
        let window = NSApp.windows.first(where: { $0.windowNumber == event.windowNumber })
        var fields = globalFields()
        fields["event_type"] = String(event.type.rawValue)
        fields["click_count"] = String(event.clickCount)
        fields["window"] = window.map(windowSummary) ?? "nil"
        record("local_mouse_down", fields: fields)

        guard event.type == .leftMouseDown,
              event.clickCount >= 2,
              window is FloatingPanel else {
            return
        }

        candidateWatchdog?.cancel()
        let candidateID = String(UUID().uuidString.prefix(8))
        pendingDoubleClickCandidateID = candidateID
        pendingDoubleClickStartedAt = Date()
        record(
            "fullscreen_candidate_started",
            fields: [
                "candidate": candidateID,
                "source_window": window.map(windowSummary) ?? "nil",
                "windows": allWindowSummary(),
            ].merging(globalFields()) { _, new in new }
        )

        let workItem = DispatchWorkItem {
            Task { @MainActor in
                guard pendingDoubleClickCandidateID == candidateID else { return }
                let elapsed = pendingDoubleClickStartedAt.map { Date().timeIntervalSince($0) } ?? 0
                record(
                    "fullscreen_candidate_failed",
                    fields: [
                        "candidate": candidateID,
                        "elapsed_ms": String(Int(elapsed * 1000)),
                        "reason": "webkit_fullscreen_state_never_reached_inFullscreen_within_2500ms",
                        "windows": allWindowSummary(),
                    ].merging(globalFields()) { _, new in new }
                )
                pendingDoubleClickCandidateID = nil
                pendingDoubleClickStartedAt = nil
                candidateWatchdog = nil
            }
        }
        candidateWatchdog = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: workItem)
    }

    private static func captureWindowSnapshotIfChanged(force: Bool = false) {
        let fingerprint = allWindowSummary()
        guard force || fingerprint != lastWindowFingerprint else { return }
        lastWindowFingerprint = fingerprint

        record(
            "window_snapshot",
            fields: ["windows": fingerprint].merging(globalFields()) { _, new in new }
        )
    }

    private static func globalFields() -> [String: String] {
        let mouseLocation = NSEvent.mouseLocation
        let mouseScreen = screenContaining(mouseLocation)
        return [
            "app_active": String(NSApp.isActive),
            "main_screen": screenID(NSScreen.main),
            "mouse_screen": screenID(mouseScreen),
            "mouse_x": String(format: "%.1f", mouseLocation.x),
            "mouse_y": String(format: "%.1f", mouseLocation.y),
            "key_window": NSApp.keyWindow.map { String($0.windowNumber) } ?? "nil",
            "main_window": NSApp.mainWindow.map { String($0.windowNumber) } ?? "nil",
        ]
    }

    private static func allWindowSummary() -> String {
        NSApp.windows
            .sorted { $0.windowNumber < $1.windowNumber }
            .map(windowSummary)
            .joined(separator: " || ")
    }

    private static func windowSummary(_ window: NSWindow) -> String {
        let frame = window.frame
        let frameDescription = String(
            format: "%.0f,%.0f,%.0f,%.0f",
            frame.origin.x,
            frame.origin.y,
            frame.size.width,
            frame.size.height
        )
        return [
            "class=\(String(describing: type(of: window)))",
            "num=\(window.windowNumber)",
            "visible=\(window.isVisible)",
            "key=\(window.isKeyWindow)",
            "main=\(window.isMainWindow)",
            "activeSpace=\(window.isOnActiveSpace)",
            "screen=\(screenID(window.screen))",
            "frame=\(frameDescription)",
            "level=\(window.level.rawValue)",
            "behavior=\(window.collectionBehavior.rawValue)",
        ].joined(separator: ",")
    }

    private static func screenContaining(_ point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    private static func screenID(_ screen: NSScreen?) -> String {
        guard let screen else { return "nil" }
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        let number = (screen.deviceDescription[key] as? NSNumber)?.uint32Value
        let frame = screen.frame
        let id = number.map(String.init) ?? "unknown"
        let frameDescription = String(
            format: "%.0f,%.0f,%.0f,%.0f",
            frame.origin.x,
            frame.origin.y,
            frame.size.width,
            frame.size.height
        )
        return "\(id)@\(frameDescription)"
    }

    private static func prepareLogFile(at url: URL) {
        let manager = FileManager.default
        try? manager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if let attributes = try? manager.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? NSNumber,
           size.intValue > 5 * 1024 * 1024 {
            let previous = url.deletingPathExtension().appendingPathExtension("previous.log")
            try? manager.removeItem(at: previous)
            try? manager.moveItem(at: url, to: previous)
        }
    }

    nonisolated private static func append(_ data: Data, to url: URL) {
        let manager = FileManager.default
        if !manager.fileExists(atPath: url.path) {
            _ = manager.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            try? handle.close()
        }
    }
#endif
}

@MainActor
final class AppCoordinator {
    private let panelController: PanelController
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
        FloatTabsDiagnostics.start()
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

        statusItemController = StatusItemController(
            onToggle: { [weak self] in self?.toggleFloatTabs() },
            isVisible: { [weak self] in self?.panelController.isVisible ?? false },
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
                NSApp.isActive && (self?.panelController.isVisible ?? false)
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
        FloatTabsDiagnostics.stop()
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
        FloatTabsDiagnostics.record(
            "global_shortcut_toggle",
            fields: [
                "fullscreen_active": String(FloatTabsFullscreenPresentation.isActive),
                "shell_explicitly_summoned": String(FloatTabsFullscreenPresentation.shellExplicitlySummoned),
                "panel_visible": String(panelController.isVisible),
            ]
        )

        // Own fullscreen and shell presentation are independent. The first press
        // explicitly summons the shell; the second press hides exactly that
        // explicit overlay. Do not use NSWindow.isVisible alone across Spaces.
        if FloatTabsFullscreenPresentation.isActive {
            if FloatTabsFullscreenPresentation.shellExplicitlySummoned {
                FloatTabsDiagnostics.record("global_shortcut_action", fields: ["action": "hide_fullscreen_shell"])
                panelController.hideFloatTabs()
            } else {
                FloatTabsDiagnostics.record("global_shortcut_action", fields: ["action": "show_fullscreen_shell"])
                panelController.showFloatTabs()
            }
            return
        }

        if panelController.isVisible {
            FloatTabsDiagnostics.record("global_shortcut_action", fields: ["action": "hide_shell"])
            panelController.hideFloatTabs()
        } else {
            FloatTabsDiagnostics.record("global_shortcut_action", fields: ["action": "show_shell"])
            panelController.showFloatTabs()
        }
    }
}
