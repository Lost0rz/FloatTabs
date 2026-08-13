import AppKit
import KeyboardShortcuts
import WebKit

@MainActor
final class AppCoordinator {
    private static let statusActivationMaxAttempts = 50
    private static let statusActivationRetryDelay: TimeInterval = 0.02
    private static let statusKeyWindowMaxAttempts = 50
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
            onCaptureForegroundGeneration: { [weak self] in
                self?.statusItemForegroundGeneration() ?? 0
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

    private func statusItemForegroundGeneration() -> UInt {
        if statusItemForegroundPresentation() == nil, !NSApp.isActive {
            fullscreenExperimentLog(
                "STATUS_ACTIVATION fallback generation=\(statusActivationGeneration)"
            )
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                _ = NSRunningApplication.current.activate(options: [])
            }
        }
        return statusActivationGeneration
    }

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

            DispatchQueue.main.asyncAfter(deadline: .now() + Self.statusActivationRetryDelay) {
                [weak self] in
                RunLoop.main.perform(inModes: [.default]) { [weak self] in
                    self?.completeStatusItemActivationWhenReady(
                        generation: generation,
                        attemptsRemaining: attemptsRemaining - 1
                    )
                }
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

    static func statusItemForegroundTargetWindow(for shellWindow: FloatingPanel) -> NSWindow {
        shellWindow.childWindows?
            .compactMap { $0 as? FullscreenSourceWindow }
            .first(where: { $0.isVisible && $0.alphaValue > 0.01 })
            ?? shellWindow
    }

    private func statusItemForegroundPresentation() -> (shell: FloatingPanel, target: NSWindow)? {
        guard let shellWindow = NSApp.windows
            .compactMap({ $0 as? FloatingPanel })
            .first(where: { $0.isVisible }) else {
            return nil
        }
        return (
            shell: shellWindow,
            target: Self.statusItemForegroundTargetWindow(for: shellWindow)
        )
    }

    static func statusItemShouldYieldToNewerKeyWindow(
        _ keyWindow: NSWindow?,
        allowedWindowNumbers: Set<Int>
    ) -> Bool {
        guard let keyWindow, keyWindow.canBecomeKey else { return false }
        return !allowedWindowNumbers.contains(keyWindow.windowNumber)
    }

    private func requestStatusItemKeyWindow(generation: UInt) {
        guard generation == statusActivationGeneration,
              panelController.isVisible,
              NSApp.isActive,
              let presentation = statusItemForegroundPresentation() else {
            fullscreenExperimentLog(
                "STATUS_KEY missing generation=\(generation) active=\(NSApp.isActive)"
            )
            return
        }

        let allowedWindowNumbers = Set([
            presentation.shell.windowNumber,
            presentation.target.windowNumber,
        ])
        guard !Self.statusItemShouldYieldToNewerKeyWindow(
            NSApp.keyWindow,
            allowedWindowNumbers: allowedWindowNumbers
        ) else {
            fullscreenExperimentLog(
                "STATUS_KEY canceled generation=\(generation) reason=newerKeyWindow "
                    + "key=\(NSApp.keyWindow?.windowNumber ?? -1)"
            )
            return
        }

        presentation.shell.orderFront(nil)
        presentation.target.makeKeyAndOrderFront(nil)
        fullscreenExperimentLog(
            "STATUS_KEY request generation=\(generation) "
                + "target=\(String(describing: type(of: presentation.target))) "
                + "window=\(presentation.target.windowNumber)"
        )
        completeStatusItemKeyWindowWhenReady(
            generation: generation,
            targetWindowNumber: presentation.target.windowNumber,
            attemptsRemaining: Self.statusKeyWindowMaxAttempts
        )
    }

    private func completeStatusItemKeyWindowWhenReady(
        generation: UInt,
        targetWindowNumber: Int,
        attemptsRemaining: Int
    ) {
        guard generation == statusActivationGeneration,
              panelController.isVisible,
              NSApp.isActive,
              let presentation = statusItemForegroundPresentation() else {
            return
        }

        let allowedWindowNumbers = Set([
            presentation.shell.windowNumber,
            presentation.target.windowNumber,
            targetWindowNumber,
        ])
        guard !Self.statusItemShouldYieldToNewerKeyWindow(
            NSApp.keyWindow,
            allowedWindowNumbers: allowedWindowNumbers
        ) else {
            fullscreenExperimentLog(
                "STATUS_KEY canceled generation=\(generation) reason=newerKeyWindow "
                    + "key=\(NSApp.keyWindow?.windowNumber ?? -1)"
            )
            return
        }

        if presentation.target.windowNumber != targetWindowNumber {
            presentation.shell.orderFront(nil)
            presentation.target.makeKeyAndOrderFront(nil)
            completeStatusItemKeyWindowWhenReady(
                generation: generation,
                targetWindowNumber: presentation.target.windowNumber,
                attemptsRemaining: Self.statusKeyWindowMaxAttempts
            )
            return
        }

        guard presentation.target.isKeyWindow else {
            guard attemptsRemaining > 0 else {
                fullscreenExperimentLog(
                    "STATUS_KEY failed generation=\(generation) active=\(NSApp.isActive) "
                        + "target=\(String(describing: type(of: presentation.target))) "
                        + "window=\(presentation.target.windowNumber)"
                )
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + Self.statusKeyWindowRetryDelay) {
                [weak self] in
                RunLoop.main.perform(inModes: [.default]) { [weak self] in
                    self?.completeStatusItemKeyWindowWhenReady(
                        generation: generation,
                        targetWindowNumber: targetWindowNumber,
                        attemptsRemaining: attemptsRemaining - 1
                    )
                }
            }
            return
        }

        finishStatusItemKeyboardFocus(
            generation: generation,
            targetWindowNumber: targetWindowNumber
        )
    }

    static func statusItemResponderBelongsToCurrentWebHierarchy(
        _ responder: NSResponder?,
        currentWebView: WKWebView?,
        targetWindow: NSWindow
    ) -> Bool {
        guard let responderView = responder as? NSView,
              responderView.window === targetWindow,
              let currentWebView,
              currentWebView.window === targetWindow else {
            return false
        }
        return responderView === currentWebView
            || responderView.isDescendant(of: currentWebView)
    }

    private static func visibleEditingControl(
        for fieldEditor: NSTextView,
        in view: NSView?
    ) -> NSControl? {
        guard let view else { return nil }
        if let control = view as? NSControl,
           !control.isHiddenOrHasHiddenAncestor,
           control.currentEditor() === fieldEditor {
            return control
        }
        for subview in view.subviews {
            if let control = visibleEditingControl(for: fieldEditor, in: subview) {
                return control
            }
        }
        return nil
    }

    static func statusItemShouldPreserveFirstResponder(
        _ responder: NSResponder?,
        currentWebView: WKWebView?,
        targetWindow: NSWindow
    ) -> Bool {
        guard let responderView = responder as? NSView,
              responderView.window === targetWindow else {
            return false
        }

        if statusItemResponderBelongsToCurrentWebHierarchy(
            responder,
            currentWebView: currentWebView,
            targetWindow: targetWindow
        ) {
            return true
        }

        guard let fieldEditor = responderView as? NSTextView,
              fieldEditor.isFieldEditor else {
            return false
        }
        return visibleEditingControl(
            for: fieldEditor,
            in: targetWindow.contentView
        ) != nil
    }

    private func finishStatusItemKeyboardFocus(
        generation: UInt,
        targetWindowNumber: Int
    ) {
        guard generation == statusActivationGeneration,
              panelController.isVisible,
              NSApp.isActive,
              let presentation = statusItemForegroundPresentation(),
              presentation.target.windowNumber == targetWindowNumber,
              presentation.target.isKeyWindow else {
            return
        }

        let webView = webPanelContainer(in: presentation.target.contentView)?.currentWebView
        let preserveExistingFocus = Self.statusItemShouldPreserveFirstResponder(
            presentation.target.firstResponder,
            currentWebView: webView,
            targetWindow: presentation.target
        )
        let focusRequestAccepted: Bool
        let focused: Bool

        if preserveExistingFocus {
            focusRequestAccepted = true
            focused = true
        } else if let webView,
                  webView.window === presentation.target,
                  !webView.isHidden,
                  webView.acceptsFirstResponder {
            focusRequestAccepted = presentation.target.makeFirstResponder(webView)
            focused = focusRequestAccepted
                && Self.statusItemResponderBelongsToCurrentWebHierarchy(
                    presentation.target.firstResponder,
                    currentWebView: webView,
                    targetWindow: presentation.target
                )
        } else {
            focusRequestAccepted = false
            focused = false
        }

        let frontmostIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
        fullscreenExperimentLog(
            "STATUS_FOCUS generation=\(generation) active=\(NSApp.isActive) "
                + "target=\(String(describing: type(of: presentation.target))) "
                + "key=\(presentation.target.isKeyWindow) "
                + "webPresent=\(webView != nil) requestAccepted=\(focusRequestAccepted) "
                + "focused=\(focused) "
                + "responder=\(String(describing: presentation.target.firstResponder.map { type(of: $0) })) "
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
        statusActivationGeneration &+= 1
        if panelController.isVisible {
            panelController.hideFloatTabs()
        } else {
            panelController.showFloatTabs()
        }
    }
}
