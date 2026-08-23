import AppKit
import KeyboardShortcuts
import UniformTypeIdentifiers

@MainActor
final class AppCoordinator {
    private let panelController: PanelController
    private var statusItemController: StatusItemController?
    private var globalHotkeyController: GlobalHotkeyController?
    private var appCommandController: AppCommandController?
    private let preferencesStore: AppPreferencesStore
    private let backupService: FloatTabsBackupService
    private let attentionSoundPlayer: AttentionSoundPlaying
    private let profileRepository: ProfileRepository?
    private var globalSettingsController: GlobalSettingsController?
    private var preserveExistingAutomaticBackupAfterEmptyStartupRecovery = false
    private var lastAttentionReadyCount = 0
#if DEBUG
    private var benchmarkControlServer: BenchmarkControlServer?
#endif

    init(
        panelController: PanelController? = nil,
        preferencesStore: AppPreferencesStore? = nil,
        backupService: FloatTabsBackupService = FloatTabsBackupService(),
        attentionSoundPlayer: AttentionSoundPlaying = AttentionSoundPlayer()
    ) {
        let resolvedPreferencesStore = preferencesStore ?? AppPreferencesStore()
        // Layer-backed rail controls resolve dynamic NSColors to CGColor while
        // they are created. Apply the stored appearance before PanelController
        // builds any windows/views so a saved Dark choice cannot be cached as
        // Aqua white until the next appearance transition.
        resolvedPreferencesStore.applyStoredAppearance()
        self.preferencesStore = resolvedPreferencesStore
        self.backupService = backupService
        self.attentionSoundPlayer = attentionSoundPlayer

        if let panelController {
            self.panelController = panelController
            profileRepository = nil
        } else {
            let profileRepository = ProfileRepository()
            self.profileRepository = profileRepository
            let tabStore = TabStore(repository: profileRepository)
            tabStore.onPersistenceFailure = {
                Self.presentConfigurationSaveFailure()
            }
            let webViewPool = WebViewPool(
                onURLChange: { slotID, url in
                    tabStore.updateCurrentURL(id: slotID, url: url)
                },
                isSlotActive: { slotID in
                    tabStore.activeTabID == slotID
                }
            )
            // Exactly one runtime attention authority for the whole app,
            // injected into the presentation owner. AppCoordinator itself
            // never routes provider observations.
            let attentionCoordinator = WebAttentionCoordinator()
            self.panelController = PanelController(
                tabStore: tabStore,
                webViewPool: webViewPool,
                attentionCoordinator: attentionCoordinator,
                preferencesStore: resolvedPreferencesStore
            )
        }
    }

    func start() {
        resolveStartupConfigurationRecoveryIfNeeded()

        globalSettingsController = GlobalSettingsController(
            preferencesStore: preferencesStore,
            attentionSoundPlayer: attentionSoundPlayer,
            onExportBackup: { [weak self] url in
                guard let self else { throw FloatTabsBackupError.restoreFailed }
                try self.exportBackup(to: url)
            },
            onRestoreBackup: { [weak self] url in
                guard let self else { throw FloatTabsBackupError.restoreFailed }
                return try self.restoreBackup(from: url)
            },
            browserProfileManager: panelController.browserProfileManagementClient()
        )
        panelController.onOpenGlobalSettings = { [weak self] in
            self?.showGlobalSettings()
        }

        statusItemController = StatusItemController(
            onToggle: { [weak self] in self?.toggleFloatTabs() },
            onWillShow: { [weak self] in
                self?.panelController.prepareForStatusItemPresentation()
            },
            isVisible: { [weak self] in self?.panelController.isVisible ?? false },
            onSettings: { [weak self] in self?.showGlobalSettings() },
            onQuit: { NSApp.terminate(nil) },
            preferencesStore: preferencesStore
        )
        statusItemController?.setActiveWebApp(
            name: panelController.selectedSlotName,
            faviconURL: panelController.selectedSlotFaviconURL
        )
        panelController.onSelectedSlotPresentationChange = { [weak self] name, faviconURL in
            self?.statusItemController?.setActiveWebApp(name: name, faviconURL: faviconURL)
        }
        lastAttentionReadyCount = max(0, panelController.attentionReadyCount)
        panelController.onAttentionPresentationChange = { [weak self] readyCount, floatTabsVisible in
            guard let self else { return }
            _ = Self.playAttentionReadySoundIfNeeded(
                previousReadyCount: self.lastAttentionReadyCount,
                currentReadyCount: readyCount,
                preferencesStore: self.preferencesStore,
                player: self.attentionSoundPlayer
            )
            self.lastAttentionReadyCount = max(0, readyCount)
            self.statusItemController?.setAttentionPresentation(
                readyCount: readyCount,
                floatTabsVisible: floatTabsVisible
            )
        }
        statusItemController?.setAttentionPresentation(
            readyCount: panelController.attentionReadyCount,
            floatTabsVisible: panelController.isVisible
        )

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
        // remain available when a newer app build is installed. Startup
        // recovery is resolved before reaching this point, so an unreadable
        // profile store can never generate an automatic empty snapshot.
        writeAutomaticVersionSnapshotIfSafe()

#if DEBUG
        let benchmarkControlServer = BenchmarkControlServer { [weak self] request in
            self?.handleBenchmarkControl(request) ?? ["ok": false, "error": "coordinator_unavailable"]
        }
        self.benchmarkControlServer = benchmarkControlServer
        _ = try? benchmarkControlServer.start()
#endif
    }

    func prepareForTermination() {
#if DEBUG
        benchmarkControlServer?.stop()
#endif
        panelController.prepareForTermination()
        // Recovery protection applies on exit too. If the user explicitly chose
        // Start Empty after a corrupt store, keep the previous automatic backup
        // until a new Web App configuration actually exists.
        writeAutomaticVersionSnapshotIfSafe()
    }

    nonisolated static func shouldPlayAttentionReadySound(
        previousReadyCount: Int,
        currentReadyCount: Int
    ) -> Bool {
        max(0, currentReadyCount) > max(0, previousReadyCount)
    }

    @discardableResult
    static func playAttentionReadySoundIfNeeded(
        previousReadyCount: Int,
        currentReadyCount: Int,
        preferencesStore: AppPreferencesStore,
        player: AttentionSoundPlaying
    ) -> Bool {
        guard shouldPlayAttentionReadySound(
            previousReadyCount: previousReadyCount,
            currentReadyCount: currentReadyCount
        ), preferencesStore.attentionSoundEnabled else {
            return false
        }
        player.play(
            soundName: preferencesStore.attentionSoundName,
            volume: preferencesStore.attentionSoundVolume
        )
        return true
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

    private func resolveStartupConfigurationRecoveryIfNeeded() {
        guard let profileRepository,
              profileRepository.startupRecoveryRequired else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)

        while profileRepository.startupRecoveryRequired {
            let latest = backupService.latestValidAutomaticSnapshot()
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "FloatTabs Couldn’t Read Its Configuration"
            alert.informativeText = "The existing WebAppProfiles.json will not be overwritten until FloatTabs preserves an exact recovery copy. Restore a known-good backup, choose another backup file, or explicitly start with an empty configuration."

            let restoreLatestButton = alert.addButton(withTitle: "Restore Latest Backup")
            restoreLatestButton.isEnabled = latest != nil
            alert.addButton(withTitle: "Choose Backup…")
            alert.addButton(withTitle: "Start Empty")

            do {
                switch alert.runModal() {
                case .alertFirstButtonReturn:
                    guard let latest else { continue }
                    try restoreStartupBackup(latest.document)

                case .alertSecondButtonReturn:
                    guard let selectedURL = chooseStartupBackupURL() else { continue }
                    let document = try backupService.load(from: selectedURL)
                    try restoreStartupBackup(document)

                case .alertThirdButtonReturn:
                    try beginWithEmptyStartupConfiguration()

                default:
                    continue
                }
            } catch {
                presentStartupRecoveryFailure(error)
            }
        }
    }

    private func chooseStartupBackupURL() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose FloatTabs Backup"
        panel.prompt = "Restore"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if let backupType = UTType(filenameExtension: FloatTabsBackupService.fileExtension) {
            panel.allowedContentTypes = [backupType]
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func restoreStartupBackup(_ document: FloatTabsBackupDocument) throws {
        try prepareUnreadableProfileStoreForReplacement()
        guard let profileRepository else {
            throw FloatTabsBackupError.startupRecoveryFailed
        }
        do {
            try profileRepository.performStartupRecoveryReplacement {
                try self.applyBackupDocument(document)
            }
        } catch let error as FloatTabsBackupError where error == .restoreFailed {
            throw FloatTabsBackupError.startupRecoveryFailed
        }
    }

    private func beginWithEmptyStartupConfiguration() throws {
        try prepareUnreadableProfileStoreForReplacement()
        guard let profileRepository else {
            throw FloatTabsBackupError.startupRecoveryFailed
        }
        try profileRepository.performStartupRecoveryReplacement {
            guard panelController.restoreStoredWebAppState(.empty) else {
                throw FloatTabsBackupError.startupRecoveryFailed
            }
        }
        // The user deliberately chose an empty live configuration, but the last
        // automatic backup may still be the only known-good structured recovery
        // point. Do not immediately overwrite it with an empty snapshot. Normal
        // automatic snapshots resume once a new Web App configuration exists.
        preserveExistingAutomaticBackupAfterEmptyStartupRecovery = true
    }

    private func prepareUnreadableProfileStoreForReplacement() throws {
        guard let profileRepository,
              profileRepository.startupRecoveryRequired else {
            return
        }
        guard try profileRepository.preserveUnreadableStoreForRecovery() != nil else {
            throw FloatTabsBackupError.startupRecoveryFailed
        }
    }

    private func presentStartupRecoveryFailure(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.alertStyle = .critical
        alert.messageText = "Recovery Was Not Completed"
        alert.informativeText = "FloatTabs has kept the unreadable configuration protected and has not written an automatic empty backup. Choose another recovery option to continue.\n\n\(error.localizedDescription)"
        alert.runModal()
    }

    nonisolated static func shouldWriteAutomaticVersionSnapshot(
        startupRecoveryRequired: Bool,
        preserveExistingAutomaticBackupAfterEmptyStartupRecovery: Bool,
        webAppState: StoredWebAppState
    ) -> Bool {
        guard !startupRecoveryRequired else { return false }
        if preserveExistingAutomaticBackupAfterEmptyStartupRecovery,
           webAppState.profiles.isEmpty {
            return false
        }
        return true
    }

    private func writeAutomaticVersionSnapshotIfSafe() {
        let webAppState = panelController.storedWebAppStateSnapshot()
        guard Self.shouldWriteAutomaticVersionSnapshot(
            startupRecoveryRequired: profileRepository?.startupRecoveryRequired == true,
            preserveExistingAutomaticBackupAfterEmptyStartupRecovery:
                preserveExistingAutomaticBackupAfterEmptyStartupRecovery,
            webAppState: webAppState
        ) else {
            return
        }
        _ = try? backupService.writeAutomaticVersionSnapshot(makeBackupDocument())
    }

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
                fixedViewportHeight: Double(preferencesStore.fixedViewportSize.height),
                isTabRailCollapsed: preferencesStore.isTabRailCollapsed,
                menuBarDisplayMode: preferencesStore.menuBarDisplayMode,
                attentionSoundEnabled: preferencesStore.attentionSoundEnabled,
                attentionSoundName: preferencesStore.attentionSoundName,
                attentionSoundVolume: preferencesStore.attentionSoundVolume
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
        try applyBackupDocument(imported)
        return rollbackURL
    }

    private func applyBackupDocument(_ imported: FloatTabsBackupDocument) throws {
        guard panelController.restoreStoredWebAppState(imported.webAppState) else {
            throw FloatTabsBackupError.restoreFailed
        }

        preferencesStore.followPreferredSize = imported.globalPreferences.followPreferredSize
        preferencesStore.appearanceMode = imported.globalPreferences.appearanceMode
        preferencesStore.customBorderColorHex = imported.globalPreferences.customBorderColorHex
            ?? AppPreferencesStore.defaultCustomBorderColorHex
        preferencesStore.borderTheme = imported.globalPreferences.borderTheme ?? .rainbow
        preferencesStore.menuBarDisplayMode =
            imported.globalPreferences.resolvedMenuBarDisplayMode
        Self.restoreAttentionSoundPreferences(
            imported.globalPreferences,
            to: preferencesStore
        )
        if let width = imported.globalPreferences.fixedViewportWidth,
           let height = imported.globalPreferences.fixedViewportHeight {
            preferencesStore.fixedViewportSize = CGSize(width: width, height: height)
        }
        if let isTabRailCollapsed = imported.globalPreferences.isTabRailCollapsed {
            preferencesStore.isTabRailCollapsed = isTabRailCollapsed
            panelController.applyRestoredRailCollapse(isTabRailCollapsed)
        }

        let shortcut = imported.globalShowHideShortcut.map {
            KeyboardShortcuts.Shortcut(
                carbonKeyCode: $0.carbonKeyCode,
                carbonModifiers: $0.carbonModifiers
            )
        }
        KeyboardShortcuts.setShortcut(shortcut, for: .toggleFloatTabs)
    }

    static func restoreAttentionSoundPreferences(
        _ backupPreferences: FloatTabsBackupPreferences,
        to preferencesStore: AppPreferencesStore
    ) {
        preferencesStore.attentionSoundEnabled =
            backupPreferences.resolvedAttentionSoundEnabled
        preferencesStore.attentionSoundName =
            backupPreferences.resolvedAttentionSoundName
        preferencesStore.attentionSoundVolume =
            backupPreferences.resolvedAttentionSoundVolume
    }

    private func showGlobalSettings() {
        globalSettingsController?.show()
    }

    private func toggleFloatTabs() {
        if panelController.isVisible {
            panelController.hideFloatTabs()
        } else {
            panelController.showFloatTabs()
        }
    }

    private static func presentConfigurationSaveFailure() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn’t Save Changes"
        alert.informativeText = "FloatTabs couldn’t save its configuration. Your previous settings were kept."
        alert.addButton(withTitle: "OK")

        if let window = NSApp.keyWindow, window.attachedSheet == nil {
            alert.beginSheetModal(for: window)
        } else {
            NSSound.beep()
        }
    }
}
