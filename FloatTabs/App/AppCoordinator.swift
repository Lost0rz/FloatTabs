import AppKit
import KeyboardShortcuts
import WebKit

@MainActor
final class AppCoordinator {
    private static let statusActivationMaxAttempts = 25
    private static let statusActivationRetryDelay: TimeInterval = 0.02
    private static let statusKeyWindowMaxAttempts = 15
    private static let statusKeyWindowRetryDelay: TimeInterval = 0.01

    private let panelController: PanelController
    private var statusItemController: StatusItemController?
    private var globalHotkeyController: GlobalHotkeyController?
    private var appCommandController: AppCommandController?
    private let preferencesStore: AppPreferencesStore
    private let backupService: FloatTabsBackupService
    private var globalSettingsController: GlobalSettingsController?
    private var statusActivationGeneration: UInt = 0
#if DEBUG
    private var benchmarkControlServer: BenchmarkControlServer?
#endif

    init(
        panelController: PanelController? = nil,
        preferencesStore: AppPreferencesStore? = nil,
        backupService: FloatTabsBackupService = FloatTabsBackupService()
    ) {
        let resolvedPreferencesStore = preferencesStore ?? AppPreferencesStore()
        // Layer-backed rail controls resolve dynamic NSColors to CGColor while
        // they are created. Apply the stored appearance before PanelController
        // builds any windows/views so a saved Dark choice cannot be cached as
        // Aqua white until the next appearance transition.
        resolvedPreferencesStore.applyStoredAppearance()
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
            onBeginForegroundActivation: { [weak self] in
                self?.beginStatusItemForegroundActivation() ?? 0
            },
            onReassertForeground: { [weak self] generation in
                self?.completeStatusItemActivationAfterTracking(generation: generation)
            },
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
                self?.panelController.acceptsAppCommands ?? false
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

        // Keep one local snapshot per app version/build. It is overwritten by
        // the same version on clean starts/exits, while older-version snapshots
        // remain available when a newer app build is installed.
        _ = try? backupService.writeAutomaticVersionSnapshot(makeBackupDocument())

#if DEBUG
        let benchmarkControlServer = BenchmarkControlServer { [weak self] request in
            self?.handleBenchmarkControl(request) ?? ["ok": false, "error": "coordinator_unavailable"]
        }
        self.benchmarkControlServer = benchmarkControlServer
        _ = try? benchmarkControlServer.start()
#endif
    }

    func prepareForTermination() {
        statusActivationGeneration &+= 1
#if DEBUG
        benchmarkControlServer?.stop()
#endif
        panelController.prepareForTermination()
        _ = try? backupService.writeAutomaticVersionSnapshot(makeBackupDocument())
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

    /// Begin the stronger status-item activation while still inside the explicit
    /// user action. PanelController's normal show has already run, so its previous
    /// application capture remains intact. The returned generation token binds the
    /// later post-tracking completion to this exact show request.
    private func beginStatusItemForegroundActivation() -> UInt {
        guard panelController.isVisible else { return statusActivationGeneration }

        statusActivationGeneration &+= 1
        let generation = statusActivationGeneration
        let frontmostIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
        fullscreenExperimentLog(
            "STATUS_ACTIVATION request generation=\(generation) active=\(NSApp.isActive) "
                + "frontmost=\(frontmostIdentifier)"
        )

        // Narrow compatibility fallback for a direct click on FloatTabs' own
        // menu-bar item. Ordinary shortcut/programmatic presentation is unchanged.
        NSApp.activate(ignoringOtherApps: true)
        return generation
    }

    /// Status-item tracking and cross-application activation are asynchronous.
    /// Never touch the source key-window / WebKit responder chain until AppKit
    /// reports that the application is actually active.
    private func completeStatusItemActivationAfterTracking(generation: UInt) {
        guard generation == statusActivationGeneration,
              panelController.isVisible else {
            return
        }

        completeStatusItemActivationWhenReady(
            generation: generation,
            attemptsRemaining: Self.statusActivationMaxAttempts
        )
    }

    private func completeStatusItemActivationWhenReady(
        generation: UInt,
        attemptsRemaining: Int
    ) {
        guard generation == statusActivationGeneration,
              panelController.isVisible else {
            return
        }

        guard NSApp.isActive else {
            guard attemptsRemaining > 0 else {
                let frontmostIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
                fullscreenExperimentLog(
                    "STATUS_ACTIVATION failed generation=\(generation) "
                        + "frontmost=\(frontmostIdentifier)"
                )
                return
            }

            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.statusActivationRetryDelay) {
                [weak self] in
                self?.completeStatusItemActivationWhenReady(
                    generation: generation,
                    attemptsRemaining: attemptsRemaining - 1
                )
            }
            return
        }

        let frontmostIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
        fullscreenExperimentLog(
            "STATUS_ACTIVATION active generation=\(generation) "
                + "frontmost=\(frontmostIdentifier)"
        )
        requestStatusItemKeyWindow(generation: generation)
    }

    /// Becoming active and becoming key are separate AppKit transitions. Request
    /// the source key window, then verify `isKeyWindow` before asking WebKit to
    /// become first responder. This removes the final race that made IME/text
    /// input intermittently fail even after application activation succeeded.
    private func requestStatusItemKeyWindow(generation: UInt) {
        guard generation == statusActivationGeneration,
              panelController.isVisible,
              NSApp.isActive else {
            return
        }

        let shellWindow = NSApp.windows.first {
            $0 is FloatingPanel && $0.isVisible
        }
        let sourceWindow = NSApp.windows.first(where: {
            $0 is FullscreenSourceWindow && $0.isVisible && $0.alphaValue > 0.01
        }) as? FullscreenSourceWindow

        shellWindow?.orderFrontRegardless()

        guard let sourceWindow else {
            shellWindow?.makeKeyAndOrderFront(nil)
            fullscreenExperimentLog(
                "STATUS_KEY shell generation=\(generation) active=\(NSApp.isActive) "
                    + "shellKey=\(shellWindow?.isKeyWindow ?? false)"
            )
            return
        }

        sourceWindow.orderFrontRegardless()
        sourceWindow.makeKeyAndOrderFront(nil)
        completeStatusItemKeyWindowWhenReady(
            generation: generation,
            sourceWindow: sourceWindow,
            attemptsRemaining: Self.statusKeyWindowMaxAttempts
        )
    }

    private func completeStatusItemKeyWindowWhenReady(
        generation: UInt,
        sourceWindow: FullscreenSourceWindow,
        attemptsRemaining: Int
    ) {
        guard generation == statusActivationGeneration,
              panelController.isVisible,
              NSApp.isActive,
              sourceWindow.isVisible else {
            return
        }

        guard sourceWindow.isKeyWindow else {
            guard attemptsRemaining > 0 else {
                fullscreenExperimentLog(
                    "STATUS_KEY failed generation=\(generation) active=\(NSApp.isActive) "
                        + "sourceKey=\(sourceWindow.isKeyWindow)"
                )
                return
            }

            sourceWindow.makeKeyAndOrderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.statusKeyWindowRetryDelay) {
                [weak self, weak sourceWindow] in
                guard let self, let sourceWindow else { return }
                self.completeStatusItemKeyWindowWhenReady(
                    generation: generation,
                    sourceWindow: sourceWindow,
                    attemptsRemaining: attemptsRemaining - 1
                )
            }
            return
        }

        finishStatusItemKeyboardFocus(
            generation: generation,
            sourceWindow: sourceWindow
        )
    }

    private func finishStatusItemKeyboardFocus(
        generation: UInt,
        sourceWindow: FullscreenSourceWindow
    ) {
        guard generation == statusActivationGeneration,
              panelController.isVisible,
              NSApp.isActive,
              sourceWindow.isKeyWindow else {
            return
        }

        let webView = webPanelContainer(in: sourceWindow.contentView)?.currentWebView
        let focused: Bool
        if let webView, webView.window === sourceWindow, !webView.isHidden {
            focused = sourceWindow.makeFirstResponder(webView)
        } else {
            focused = false
        }

        let frontmostIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
        fullscreenExperimentLog(
            "STATUS_FOCUS web generation=\(generation) active=\(NSApp.isActive) "
                + "sourceKey=\(sourceWindow.isKeyWindow) "
                + "webPresent=\(webView != nil) focused=\(focused) "
                + "responder=\(String(describing: sourceWindow.firstResponder.map { type(of: $0) })) "
                + "frontmost=\(frontmostIdentifier)"
        )
    }

    private func webPanelContainer(in view: NSView?) -> WebPanelContainerView? {
        guard let view else { return nil }
        if let container = view as? WebPanelContainerView {
            return container
        }
        for subview in view.subviews {
            if let container = webPanelContainer(in: subview) {
                return container
            }
        }
        return nil
    }

    private func toggleFloatTabs() {
        if panelController.isVisible {
            // Cancel queued activation/key-window completions before hiding so a
            // stale status-item callback cannot make a hidden source key again.
            statusActivationGeneration &+= 1
            panelController.hideFloatTabs()
        } else {
            panelController.showFloatTabs()
        }
    }
}
