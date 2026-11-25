import AppKit
import KeyboardShortcuts
import OSLog
import UniformTypeIdentifiers

@MainActor
final class AppCoordinator {
    typealias WebsiteCacheClock = @MainActor () -> Date
    typealias WebsiteCacheSleeper = @MainActor (TimeInterval) async throws -> Void

    private static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static let websiteCacheLogger = Logger(
        subsystem: "com.lost0rz.FloatTabs",
        category: "WebsiteCache"
    )

    static func openDiagnosticsLogsFolder(
        at directory: URL = RuntimeDiagnosticWriter.defaultDirectory,
        fileManager: FileManager = .default,
        open: (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
            )
        } catch {
            return
        }
        open(directory)
    }

    private let panelController: PanelController
    private let diagnostics: RuntimeDiagnostics
    private let diagnosticExporter: RuntimeDiagnosticExporter
    private let completionNotificationCoordinator: ChatGPTCompletionNotificationCoordinator
    private var statusItemController: StatusItemController?
    private var globalHotkeyController: GlobalHotkeyController?
    private var appCommandController: AppCommandController?
    private var externalCommandController: FloatTabsExternalCommandController?
    private var externalVoiceFocusTask: Task<Void, Never>?
    private var externalVoiceFocusRequestID: String?
    private let preferencesStore: AppPreferencesStore
    private let backupService: FloatTabsBackupService
    private let attentionSoundAssetStore: AttentionSoundAssetStore
    private let attentionSoundPlayer: AttentionSoundPlaying
    private let websiteCacheUsageStore: WebsiteCacheUsageStore
    private let websiteCacheClock: WebsiteCacheClock
    private let websiteCacheSleeper: WebsiteCacheSleeper
    private let profileRepository: ProfileRepository?
    private var globalSettingsController: GlobalSettingsController?
    private var websiteCacheCleanupCoordinator: WebsiteCacheCleanupCoordinator?
    private var websiteCacheAutomaticTask: Task<Void, Never>?
    private var longTermPerformanceObservationCoordinator: LongTermPerformanceObservationCoordinator?
    private var pendingExternalSlotDelta = 0
    private var externalSlotBatchTrace: RuntimeDiagnosticTrace?
    private var externalSlotFlushScheduled = false
    nonisolated(unsafe) private var appLanguageObserver: NSObjectProtocol?
    private var isTerminating = false
    private var preserveExistingAutomaticBackupAfterEmptyStartupRecovery = false
#if DEBUG
    private var benchmarkControlServer: BenchmarkControlServer?
#endif

    init(
        panelController: PanelController? = nil,
        preferencesStore: AppPreferencesStore? = nil,
        backupService: FloatTabsBackupService = FloatTabsBackupService(),
        attentionSoundAssetStore: AttentionSoundAssetStore? = nil,
        attentionSoundPlayer: AttentionSoundPlaying = AttentionSoundPlayer(),
        websiteCacheClock: @escaping WebsiteCacheClock = Date.init,
        websiteCacheSleeper: @escaping WebsiteCacheSleeper = { delay in
            let nanoseconds = UInt64(
                min(
                    max(0, delay),
                    Double(UInt64.max) / 1_000_000_000
                ) * 1_000_000_000
            )
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        let resolvedPreferencesStore = preferencesStore ?? AppPreferencesStore()
        let resolvedAttentionSoundAssetStore = attentionSoundAssetStore ?? AttentionSoundAssetStore()
        let diagnostics = RuntimeDiagnostics(
            writer: RuntimeDiagnosticWriter(directory: RuntimeDiagnosticWriter.defaultDirectory),
            modeProvider: { resolvedPreferencesStore.runtimeDiagnosticsMode }
        )
        // Layer-backed rail controls resolve dynamic NSColors to CGColor while
        // they are created. Apply the stored appearance before PanelController
        // builds any windows/views so a saved Dark choice cannot be cached as
        // Aqua white until the next appearance transition.
        resolvedPreferencesStore.applyStoredAppearance()
        if !Self.isRunningUnderXCTest {
            resolvedPreferencesStore.applyStoredLanguage(postNotification: false)
        }
        appLanguageObserver = NotificationCenter.default.addObserver(
            forName: .floatTabsAppLanguageDidChange,
            object: resolvedPreferencesStore,
            queue: .main
        ) { [weak resolvedPreferencesStore] _ in
            Task { @MainActor [weak resolvedPreferencesStore] in
                guard !Self.isRunningUnderXCTest,
                      let resolvedPreferencesStore else { return }
                AppLocalization.apply(resolvedPreferencesStore.appLanguage)
            }
        }
        self.preferencesStore = resolvedPreferencesStore
        self.diagnostics = diagnostics
        self.diagnosticExporter = RuntimeDiagnosticExporter(diagnostics: diagnostics)
        self.completionNotificationCoordinator = ChatGPTCompletionNotificationCoordinator(
            diagnostics: diagnostics
        )
        self.backupService = backupService
        self.attentionSoundAssetStore = resolvedAttentionSoundAssetStore
        self.attentionSoundPlayer = attentionSoundPlayer
        self.websiteCacheUsageStore = WebsiteCacheUsageStore()
        self.websiteCacheClock = websiteCacheClock
        self.websiteCacheSleeper = websiteCacheSleeper

        if let panelController {
            self.panelController = panelController
            profileRepository = nil
        } else {
            let profileRepository = ProfileRepository()
            self.profileRepository = profileRepository
            let tabStore = TabStore(
                repository: profileRepository,
                diagnostics: diagnostics,
                runtimePersistenceDebounceInterval: Self.isRunningUnderXCTest ? 0 : 0.35
            )
            tabStore.onPersistenceFailure = {
                Self.presentConfigurationSaveFailure()
            }
            let webViewPool = WebViewPool(
                onURLChange: { slotID, url in
                    tabStore.updateCurrentURL(id: slotID, url: url)
                },
                recoveryLoad: { webView, request in
                    webView.load(request)
                },
                isSlotActive: { slotID in
                    tabStore.activeTabID == slotID
                },
                residencyPolicyProvider: { slotID in
                    tabStore.profiles.first { $0.id == slotID }?.residencyPolicy
                },
                diagnostics: diagnostics
            )
            // Exactly one runtime attention authority for the whole app,
            // injected into the presentation owner. AppCoordinator itself
            // never routes provider observations.
            let attentionCoordinator = WebAttentionCoordinator(diagnostics: diagnostics)
            self.panelController = PanelController(
                tabStore: tabStore,
                webViewPool: webViewPool,
                attentionCoordinator: attentionCoordinator,
                preferencesStore: resolvedPreferencesStore,
                diagnostics: diagnostics
            )
        }
    }

    func start() {
        let trace = diagnostics.beginTrace(root: "app.launch")
        diagnostics.record(
            event: "app.launch",
            level: .info,
            subsystem: "app",
            trace: trace,
            fields: diagnostics.environmentFields()
        )
        // Install the native-notification delegate during normal startup,
        // before any completion notification can be delivered, and wire the
        // Phase 3 projection: durable unread `.marked` → native notification;
        // notification default action → exact persistent Slot presentation.
        // The existing onChatGPTGenerationCompleted sound route stays
        // unchanged and independent.
        completionNotificationCoordinator.installAtStartup()
        completionNotificationCoordinator.onRouteSlot = { [weak self] slotID in
            _ = self?.panelController.presentSlotFromCompletionNotification(slotID)
        }
        panelController.onChatGPTUnreadCompletionMarked = { [weak completionNotificationCoordinator] slotID, displayName, assistantPreview in
            completionNotificationCoordinator?.notify(
                slotID: slotID,
                displayName: displayName,
                assistantPreview: assistantPreview
            )
        }
        panelController.onUniversalNotificationRequested = { [weak completionNotificationCoordinator] slotID, displayName, preview, fallbackBody in
            completionNotificationCoordinator?.notify(
                slotID: slotID,
                displayName: displayName,
                assistantPreview: preview,
                fallbackBody: fallbackBody
            )
        }
        panelController.onUnreadSlotAcknowledged = { [weak completionNotificationCoordinator] slotID in
            completionNotificationCoordinator?.withdrawNotification(for: slotID)
        }
        resolveStartupConfigurationRecoveryIfNeeded()
        resolveStartupBookmarksRecoveryIfNeeded()
        if profileRepository != nil {
            WebsiteFaviconProvider.shared.pruneOrphanSlotIcons(
                keeping: panelController.configuredSlotIDs
            )
        }

        let websiteCacheCoordinator = panelController.websiteCacheCleanupCoordinator(
            preferencesStore: preferencesStore,
            usageStore: websiteCacheUsageStore
        )
        websiteCacheCleanupCoordinator = websiteCacheCoordinator

        let captureIncidentHandler: RuntimeDiagnosticsIncidentCaptureHandler = { [weak self] in
            self?.panelController.captureStuckTabSnapshot() ?? "Snapshot unavailable."
        }

        globalSettingsController = GlobalSettingsController(
            preferencesStore: preferencesStore,
            attentionSoundAssetStore: attentionSoundAssetStore,
            attentionSoundPlayer: attentionSoundPlayer,
            onExportBackup: { [weak self] url in
                guard let self else { throw FloatTabsBackupError.restoreFailed }
                try self.exportBackup(to: url)
            },
            onRestoreBackup: { [weak self] url in
                guard let self else { throw FloatTabsBackupError.restoreFailed }
                return try self.restoreBackup(from: url)
            },
            browserProfileManager: panelController.browserProfileManagementClient(
                usageStore: websiteCacheUsageStore
            ),
            websiteCacheManager: websiteCacheCoordinator.client,
            bookmarkManager: panelController.bookmarkManagementClient(),
            onExportDiagnostics: { [weak self] url, completion in
                self?.diagnosticExporter.exportRecent(to: url, completion: completion)
                    ?? completion(.failure(.writerUnavailable))
            },
            onOpenDiagnosticsLogs: {
                Self.openDiagnosticsLogsFolder()
            },
            onCaptureDiagnosticsIncident: captureIncidentHandler,
            onProvideDiagnosticsLiveStatus: { [weak self] in
                guard let self else { return nil }
                return self.panelController.diagnosticsLiveStatusSnapshot(
                    sessionSummary: self.diagnostics.sessionSummary()
                )
            },
            onLoadRecentDiagnosticsEvents: { [weak self] limit, completion in
                guard let self else {
                    completion([])
                    return
                }
                self.diagnostics.loadRecentCombinedEvents(limit: limit, completion: completion)
            }
        )
        let observationCoordinator = LongTermPerformanceObservationCoordinator(
            preferencesStore: preferencesStore,
            observe: { [weak self] shouldRecord, completion in
                guard let self else {
                    completion()
                    return
                }
                self.panelController.captureLongTermDiagnosticsCheckpoint(
                    shouldRecord: shouldRecord,
                    completion: completion
                )
            }
        )
        longTermPerformanceObservationCoordinator = observationCoordinator
        observationCoordinator.start()
        websiteCacheCoordinator.onPolicyChanged = { [weak self] in
            self?.restartWebsiteCacheAutomaticSchedule()
        }
        panelController.onPanelBecameHidden = { [weak self] in
            self?.triggerWebsiteCacheAutomaticCheck()
        }
        panelController.onOpenGlobalSettings = { [weak self] in
            self?.showGlobalSettings()
        }
        panelController.onOpenBookmarksSettings = { [weak self] in
            self?.showGlobalSettings(selecting: .bookmarks)
        }
        panelController.onTabStoreDidChange = { [weak self] in
            self?.globalSettingsController?.refreshBookmarksIfLoaded()
        }

        statusItemController = StatusItemController(
            onToggle: { [weak self] in self?.toggleFloatTabs() },
            onWillShow: { [weak self] in
                self?.panelController.prepareForStatusItemPresentation()
            },
            onWillShowWithTrace: { [weak self] trace in
                self?.panelController.prepareForStatusItemPresentation(trace: trace)
            },
            isVisible: { [weak self] in
                self?.panelController.isPresentationActuallyVisible ?? false
            },
            onSettings: { [weak self] in self?.showGlobalSettings() },
            onQuit: { NSApp.terminate(nil) },
            preferencesStore: preferencesStore,
            menuSnapshotProvider: { [weak self] in
                self?.panelController.statusItemMenuSnapshot
                    ?? StatusItemMenuSnapshot(slots: [], isPinned: false)
            },
            onSelectSlot: { [weak self] slotID in
                _ = self?.panelController.selectAndPresentSlotFromMenuBar(slotID)
            },
            onTogglePin: { [weak self] in
                self?.panelController.handle(.togglePin)
            },
            diagnostics: diagnostics,
            onToggleWithTrace: { [weak self] trace in
                self?.panelController.toggleFloatTabs(
                    trace: trace,
                    dismissSource: .menubar
                )
            }
        )
        statusItemController?.setActiveWebApp(
            name: panelController.selectedSlotName,
            faviconURL: panelController.selectedSlotFaviconURL
        )
        panelController.onSelectedSlotPresentationChange = { [weak self] name, faviconURL in
            self?.statusItemController?.setActiveWebApp(name: name, faviconURL: faviconURL)
        }
        panelController.onChatGPTGenerationCompleted = { [weak self] _ in
            guard let self else { return }
            _ = Self.playAttentionSoundForGenerationCompletion(
                preferencesStore: self.preferencesStore,
                assetStore: self.attentionSoundAssetStore,
                player: self.attentionSoundPlayer
            )
        }
        panelController.onAttentionPresentationChange = { [weak self] unreadCount, floatTabsVisible in
            guard let self else { return }
            self.statusItemController?.setAttentionPresentation(
                unreadCount: unreadCount,
                floatTabsVisible: floatTabsVisible
            )
        }
        statusItemController?.setAttentionPresentation(
            unreadCount: panelController.unreadResponseCount,
            floatTabsVisible: panelController.isVisible
        )

        globalHotkeyController = GlobalHotkeyController(
            onToggle: { [weak self] in self?.toggleOrPresentFloatTabs() },
            isPrimaryFocusEnabled: { [weak self] in
                self?.panelController.acceptsAppCommands ?? false
            },
            onPrimaryFocus: { [weak self] in
                self?.panelController.handle(.togglePrimaryFocus)
            },
            diagnostics: diagnostics,
            onToggleWithTrace: { [weak self] trace in
                self?.toggleOrPresentFloatTabs(trace: trace)
            },
            onPrimaryFocusWithTrace: { [weak self] trace in
                self?.panelController.handle(.togglePrimaryFocus, trace: trace)
            }
        )

        appCommandController = AppCommandController(
            isEnabled: { [weak self] in
                self?.panelController.acceptsAppCommands ?? false
            },
            presentedAddressOverlayProvider: { [weak self] in
                self?.panelController.presentedAddressOverlay
            },
            onCommand: { [weak self] command in
                guard let self else { return }
                if command == .settings {
                    self.showGlobalSettings()
                } else {
                    self.panelController.handle(command)
                }
            },
            diagnostics: diagnostics
        )

        // RemoteOrbit uses semantic commands instead of replaying FloatTabs'
        // configurable keyboard shortcuts. Keep this listener alive while the
        // panel is hidden so the remote's summon, focus, tab, and scroll actions
        // all share one stable application entry point.
        externalCommandController = FloatTabsExternalCommandController(
            onCommand: { [weak self] command, userInfo in
                self?.handleExternalCommand(command, userInfo: userInfo)
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
            guard let self else {
                return ["ok": false, "error": "coordinator_unavailable"]
            }
            return await self.handleBenchmarkControl(request)
        }
        self.benchmarkControlServer = benchmarkControlServer
        _ = try? benchmarkControlServer.start()
#endif

        // Startup remains responsive. The scheduler persists its last check,
        // waits 45 seconds on a first run, and then sleeps until the next
        // eligible interval instead of using a high-frequency timer.
        startWebsiteCacheAutomaticSchedule(initialDelay: WebsiteCacheAutomaticSchedulePolicy.initialDelay)
        diagnostics.record(
            event: "app.ready",
            level: .notice,
            subsystem: "app",
            trace: trace,
            fields: ["diagnostics_mode": .string(diagnostics.mode.rawValue)]
        )
    }

    func prepareForTermination() {
        let trace = diagnostics.beginTrace(root: "app.termination")
        diagnostics.record(
            event: "app.termination.begin",
            level: .notice,
            subsystem: "app",
            trace: trace
        )
        isTerminating = true
        externalVoiceFocusTask?.cancel()
        externalVoiceFocusTask = nil
        externalVoiceFocusRequestID = nil
        websiteCacheAutomaticTask?.cancel()
        websiteCacheAutomaticTask = nil
        longTermPerformanceObservationCoordinator?.stop()
        longTermPerformanceObservationCoordinator = nil
        websiteCacheCleanupCoordinator?.stop()
#if DEBUG
        benchmarkControlServer?.stop()
#endif
        panelController.prepareForTermination(trace: trace)
        // Recovery protection applies on exit too. If the user explicitly chose
        // Start Empty after a corrupt store, keep the previous automatic backup
        // until a new Web App configuration actually exists.
        writeAutomaticVersionSnapshotIfSafe()
        diagnostics.record(
            event: "app.termination.flush",
            level: .notice,
            subsystem: "app",
            trace: trace
        )
        diagnostics.requestFinalFlush(timeout: 0.25) {}
    }

    private func startWebsiteCacheAutomaticSchedule(initialDelay: TimeInterval? = nil) {
        websiteCacheAutomaticTask?.cancel()
        websiteCacheAutomaticTask = nil
        guard !isTerminating,
              let coordinator = websiteCacheCleanupCoordinator,
              coordinator.automaticCleanupEnabled else { return }

        websiteCacheAutomaticTask = Task { @MainActor [weak self, weak coordinator] in
            guard let self, let coordinator else { return }
            let scheduler = WebsiteCacheAutomaticScheduler(
                snapshotProvider: { [weak self, weak coordinator] in
                    guard let self,
                          let coordinator,
                          !self.isTerminating else { return nil }
                    return WebsiteCacheAutomaticScheduleSnapshot(
                        now: self.websiteCacheClock(),
                        lastAutomaticCheckAt: coordinator.lastAutomaticCheckAt,
                        lastAutomaticFailureAt: coordinator.lastAutomaticFailureAt,
                        minimumCleanupInterval: coordinator.minimumCleanupInterval,
                        automaticCleanupEnabled: coordinator.automaticCleanupEnabled
                    )
                },
                sleeper: self.websiteCacheSleeper,
                cleanup: { [weak self, weak coordinator] in
                    guard let self, let coordinator, !self.isTerminating else {
                        throw WebsiteCacheManagementError.applicationTerminating
                    }
                    _ = try await coordinator.runAutomaticIfNeeded(
                        now: self.websiteCacheClock()
                    )
                },
                failureHandler: { error in
                    Self.websiteCacheLogger.error(
                        "Automatic website cache cleanup failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            )
            await scheduler.run(initialDelay: initialDelay)
        }
    }

    private func restartWebsiteCacheAutomaticSchedule() {
        startWebsiteCacheAutomaticSchedule(initialDelay: 0)
    }

    private func triggerWebsiteCacheAutomaticCheck() {
        guard let coordinator = websiteCacheCleanupCoordinator,
              coordinator.automaticCleanupEnabled,
              !coordinator.isOperationInProgress else { return }
        startWebsiteCacheAutomaticSchedule(initialDelay: 0)
    }

    static func attentionSoundPlaybackSource(
        preferencesStore: AppPreferencesStore,
        assetStore: AttentionSoundAssetStore
    ) -> AttentionSoundPlaybackSource {
        guard preferencesStore.attentionSoundSourceKind == .custom else {
            return .system(name: preferencesStore.attentionSoundName)
        }
        guard let selectedID = preferencesStore.selectedCustomAttentionSoundID,
              let asset = preferencesStore.customAttentionSoundAsset(id: selectedID),
              let url = assetStore.existingURL(for: asset) else {
            return .system(name: AppPreferencesStore.defaultAttentionSoundName)
        }
        return .custom(url: url)
    }

    @discardableResult
    static func playAttentionSoundForGenerationCompletion(
        preferencesStore: AppPreferencesStore,
        assetStore: AttentionSoundAssetStore,
        player: AttentionSoundPlaying
    ) -> Bool {
        guard preferencesStore.attentionSoundEnabled else {
            return false
        }
        player.play(
            source: attentionSoundPlaybackSource(
                preferencesStore: preferencesStore,
                assetStore: assetStore
            ),
            volume: preferencesStore.attentionSoundVolume
        )
        return true
    }

#if DEBUG
    private func handleBenchmarkControl(_ request: [String: Any]) async -> [String: Any] {
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

        case "chatgpt_measurement_configure":
            guard let slotID = request["slot_id"] as? String,
                  request["enabled"] == nil || request["enabled"] is Bool,
                  request["reset"] == nil || request["reset"] is Bool else {
                return ["ok": false, "error": "invalid_measurement_configuration"]
            }
            let measurement = await panelController.benchmarkConfigureChatGPTMeasurement(
                slotIDString: slotID,
                enabled: request["enabled"] as? Bool,
                reset: request["reset"] as? Bool ?? false
            )
            return ["ok": true, "measurement": measurement]

        case "chatgpt_measurement_snapshot":
            guard let slotID = request["slot_id"] as? String else {
                return ["ok": false, "error": "missing_slot_id"]
            }
            let measurement = await panelController.benchmarkCaptureChatGPTSnapshot(
                slotIDString: slotID
            )
            return ["ok": true, "measurement": measurement]

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

        panelController.prepareForExplicitActivation()
        NSApp.activate()

        while profileRepository.startupRecoveryRequired {
            let latest = backupService.latestValidAutomaticSnapshot()
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = L10n.tr(
                "FloatTabs Couldn’t Read Its Configuration",
                "FloatTabs 无法读取配置文件"
            )
            alert.informativeText = L10n.tr(
                "The existing WebAppProfiles.json will not be overwritten until FloatTabs preserves an exact recovery copy. Restore a known-good backup, choose another backup file, or explicitly start with an empty configuration.",
                "在完整保留恢复副本之前，现有的 WebAppProfiles.json 不会被覆盖。你可以恢复已知正常的备份、选择其他备份文件，或显式以空白配置启动。"
            )

            let restoreLatestButton = alert.addButton(
                withTitle: L10n.tr("Restore Latest Backup", "恢复最新备份")
            )
            restoreLatestButton.isEnabled = latest != nil
            alert.addButton(withTitle: L10n.tr("Choose Backup…", "选择备份…"))
            alert.addButton(withTitle: L10n.tr("Start Empty", "以空白启动"))

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
        panel.title = L10n.tr("Choose FloatTabs Backup", "选择 FloatTabs 备份")
        panel.prompt = L10n.tr("Restore", "恢复")
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
            let emptyState = profileRepository.emptyCoreStatePreservingSidecarBookmarks()
            guard panelController.restoreStoredWebAppState(emptyState) else {
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

    deinit {
        if let appLanguageObserver {
            NotificationCenter.default.removeObserver(appLanguageObserver)
        }
    }

    private func resolveStartupBookmarksRecoveryIfNeeded() {
        guard !Self.isRunningUnderXCTest,
              let profileRepository,
              profileRepository.bookmarksRecoveryRequired else {
            return
        }

        panelController.prepareForExplicitActivation()
        NSApp.activate()

        while profileRepository.bookmarksRecoveryRequired {
            let latest = backupService.latestValidAutomaticSnapshot()
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L10n.tr(
                "FloatTabs Couldn’t Read Bookmarks.json",
                "FloatTabs 无法读取书签文件 Bookmarks.json"
            )
            alert.informativeText = L10n.tr(
                "A recovery copy of the unreadable Bookmarks.json was preserved and the original file has not been overwritten. Restore a backup to recover your bookmarks, or explicitly continue with an empty bookmark list.",
                "FloatTabs 已保留无法读取的 Bookmarks.json 恢复副本，且尚未覆盖原文件。你可以从备份恢复书签，或显式以空白书签列表继续。"
            )

            let restoreLatestButton = alert.addButton(
                withTitle: L10n.tr("Restore Latest Backup", "恢复最新备份")
            )
            restoreLatestButton.isEnabled = latest != nil
            alert.addButton(withTitle: L10n.tr("Choose Backup…", "选择备份…"))
            alert.addButton(withTitle: L10n.tr("Continue with Empty Bookmarks", "以空白书签继续"))

            do {
                switch alert.runModal() {
                case .alertFirstButtonReturn:
                    guard let latest else { continue }
                    try applyBackupDocument(latest.document)

                case .alertSecondButtonReturn:
                    guard let selectedURL = chooseStartupBackupURL() else { continue }
                    let document = try backupService.load(from: selectedURL)
                    try applyBackupDocument(document)

                case .alertThirdButtonReturn:
                    try profileRepository.acceptEmptyBookmarksAfterRecovery()
                    preserveExistingAutomaticBackupAfterEmptyStartupRecovery = true

                default:
                    continue
                }
            } catch {
                presentStartupRecoveryFailure(error)
            }
        }
    }

    private func presentStartupRecoveryFailure(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.alertStyle = .critical
        alert.messageText = L10n.tr("Recovery Was Not Completed", "未能完成恢复")
        alert.informativeText = L10n.tr(
            "FloatTabs has kept the unreadable configuration protected and has not written an automatic empty backup. Choose another recovery option to continue.\n\n\(error.localizedDescription)",
            "FloatTabs 已保护无法读取的配置文件，并未写入自动空白备份。请选择其他恢复方式以继续。\n\n\(error.localizedDescription)"
        )
        alert.runModal()
    }

    nonisolated static func shouldWriteAutomaticVersionSnapshot(
        startupRecoveryRequired: Bool,
        bookmarksRecoveryRequired: Bool = false,
        preserveExistingAutomaticBackupAfterEmptyStartupRecovery: Bool,
        webAppState: StoredWebAppState
    ) -> Bool {
        guard !startupRecoveryRequired, !bookmarksRecoveryRequired else { return false }
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
            bookmarksRecoveryRequired: profileRepository?.bookmarksRecoveryRequired == true,
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
        let allShortcutNames: [KeyboardShortcuts.Name] = [.toggleFloatTabs] + AppShortcutCatalog.allNames
        let appShortcuts = allShortcutNames.map { name in
            let assigned = KeyboardShortcuts.getShortcut(for: name).map {
                FloatTabsBackupShortcut(
                    carbonKeyCode: $0.carbonKeyCode,
                    carbonModifiers: $0.carbonModifiers
                )
            }
            return FloatTabsNamedBackupShortcut(name: name.rawValue, shortcut: assigned)
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
                appLanguage: preferencesStore.appLanguage,
                followPreferredSize: preferencesStore.followPreferredSize,
                borderTheme: preferencesStore.borderTheme,
                customBorderColorHex: preferencesStore.customBorderColorHex,
                fixedViewportWidth: Double(preferencesStore.fixedViewportSize.width),
                fixedViewportHeight: Double(preferencesStore.fixedViewportSize.height),
                isTabRailCollapsed: preferencesStore.isTabRailCollapsed,
                menuBarDisplayMode: preferencesStore.menuBarDisplayMode,
                attentionStyle: preferencesStore.attentionStyle,
                attentionPalette: preferencesStore.attentionPalette,
                attentionSoundEnabled: preferencesStore.attentionSoundEnabled,
                attentionSoundName: preferencesStore.attentionSoundName,
                attentionSoundVolume: preferencesStore.attentionSoundVolume,
                externalCommandsEnabled: preferencesStore.externalCommandsEnabled
            ),
            globalShowHideShortcut: shortcutBackup,
            appShortcuts: appShortcuts,
            websiteCachePolicy: preferencesStore.websiteCachePolicy
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
        try profileRepository?.allowBookmarksReplacementAfterBackupRestore()
        guard panelController.restoreStoredWebAppState(imported.webAppState) else {
            throw FloatTabsBackupError.restoreFailed
        }

        preferencesStore.followPreferredSize = imported.globalPreferences.followPreferredSize
        preferencesStore.appearanceMode = imported.globalPreferences.appearanceMode
        if let appLanguage = imported.globalPreferences.appLanguage {
            preferencesStore.appLanguage = appLanguage
            if !Self.isRunningUnderXCTest {
                AppLocalization.apply(appLanguage)
            }
        }
        preferencesStore.customBorderColorHex = imported.globalPreferences.customBorderColorHex
            ?? AppPreferencesStore.defaultCustomBorderColorHex
        preferencesStore.borderTheme = imported.globalPreferences.borderTheme ?? .rainbow
        preferencesStore.menuBarDisplayMode =
            imported.globalPreferences.resolvedMenuBarDisplayMode
        preferencesStore.attentionStyle =
            imported.globalPreferences.resolvedAttentionStyle
        preferencesStore.attentionPalette =
            imported.globalPreferences.resolvedAttentionPalette
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
        preferencesStore.externalCommandsEnabled =
            imported.globalPreferences.resolvedExternalCommandsEnabled
        if let websiteCachePolicy = imported.websiteCachePolicy {
            preferencesStore.websiteCachePolicy = websiteCachePolicy
            websiteCacheCleanupCoordinator?.onPolicyChanged?()
        }

        if let backedUpShortcuts = imported.appShortcuts {
            let namesByRawValue = Dictionary(
                uniqueKeysWithValues: ([KeyboardShortcuts.Name.toggleFloatTabs] + AppShortcutCatalog.allNames)
                    .map { ($0.rawValue, $0) }
            )
            var restoredToggle = false
            for entry in backedUpShortcuts {
                guard let name = namesByRawValue[entry.name] else { continue }
                let restored = entry.shortcut.map {
                    KeyboardShortcuts.Shortcut(
                        carbonKeyCode: $0.carbonKeyCode,
                        carbonModifiers: $0.carbonModifiers
                    )
                }
                KeyboardShortcuts.setShortcut(restored, for: name)
                if name == .toggleFloatTabs {
                    restoredToggle = true
                }
            }
            if !restoredToggle {
                let fallback = imported.globalShowHideShortcut.map {
                    KeyboardShortcuts.Shortcut(
                        carbonKeyCode: $0.carbonKeyCode,
                        carbonModifiers: $0.carbonModifiers
                    )
                }
                KeyboardShortcuts.setShortcut(fallback, for: .toggleFloatTabs)
            }
        } else {
            let shortcut = imported.globalShowHideShortcut.map {
                KeyboardShortcuts.Shortcut(
                    carbonKeyCode: $0.carbonKeyCode,
                    carbonModifiers: $0.carbonModifiers
                )
            }
            KeyboardShortcuts.setShortcut(shortcut, for: .toggleFloatTabs)
        }
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
        // Custom audio is machine-local and is intentionally absent from the
        // backup schema. A restore must never activate a local custom asset
        // merely because the current machine still has one.
        preferencesStore.attentionSoundSourceKind = .system
    }

    private func showGlobalSettings(selecting page: GlobalSettingsPage? = nil) {
        panelController.prepareForExplicitActivation()
        globalSettingsController?.show(selecting: page)
    }

    private func toggleFloatTabs(trace: RuntimeDiagnosticTrace? = nil) {
        panelController.toggleFloatTabs(
            trace: trace,
            dismissSource: .menubar
        )
    }

    private func presentFloatTabs() {
        panelController.presentFloatTabs()
    }

    private func toggleOrPresentFloatTabs(trace: RuntimeDiagnosticTrace? = nil) {
        panelController.toggleOrPresentFloatTabs(trace: trace)
    }

    /// Apply the first external tab command immediately, then fold commands
    /// that arrive in the same main-queue turn into one relative selection.
    /// This preserves the feel of a single click while preventing a burst of
    /// remote volume reports from synchronously activating and persisting every
    /// intermediate WebView.
    private func enqueueExternalSlotSwitch(
        delta: Int,
        trace: RuntimeDiagnosticTrace
    ) {
        guard delta != 0 else { return }
        if externalSlotFlushScheduled {
            pendingExternalSlotDelta += delta
            if let batchTrace = externalSlotBatchTrace {
                diagnostics.record(
                    event: "external.command.coalesced",
                    level: .info,
                    subsystem: "external",
                    trace: trace,
                    fields: [
                        "batch_trace_id": .string(batchTrace.id.uuidString),
                        "delta": .integer(Int64(delta))
                    ]
                )
            }
            return
        }

        externalSlotFlushScheduled = true
        externalSlotBatchTrace = trace
        _ = panelController.selectSlot(relativeOffset: delta, trace: trace)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let pendingDelta = self.pendingExternalSlotDelta
            self.pendingExternalSlotDelta = 0
            self.externalSlotBatchTrace = nil
            self.externalSlotFlushScheduled = false
            guard pendingDelta != 0 else { return }
            self.enqueueExternalSlotSwitch(delta: pendingDelta, trace: trace)
        }
    }

    private func handleExternalCommand(
        _ command: FloatTabsExternalCommand,
        userInfo: [AnyHashable: Any]?
    ) {
        guard preferencesStore.externalCommandsEnabled else {
            diagnostics.record(
                event: "external.command.ignored_disabled",
                level: .info,
                subsystem: "external",
                fields: ["command": .string(command.rawValue)]
            )
            return
        }
        let trace = diagnostics.beginTrace(root: "external.command")
        diagnostics.record(
            event: "external.command.received",
            level: .info,
            subsystem: "external",
            trace: trace,
            fields: ["command": .string(command.rawValue)]
        )
        switch command {
        case .show:
            panelController.showFloatTabs(trace: trace)

        case .toggleVisibility:
            panelController.toggleFloatTabs(
                trace: trace,
                dismissSource: .externalCommand
            )

        case .selectSlot:
            guard let index = (userInfo?["slotIndex"] as? NSNumber)?.intValue,
                  (1...9).contains(index) else { return }
            panelController.handle(.selectSlot(index), trace: trace)

        case .nextSlot:
            enqueueExternalSlotSwitch(delta: 1, trace: trace)

        case .previousSlot:
            enqueueExternalSlotSwitch(delta: -1, trace: trace)

        case .addWebApp:
            panelController.handle(.addWebApp)

        case .zoomIn:
            panelController.handle(.zoomIn)

        case .zoomOut:
            panelController.handle(.zoomOut)

        case .resetZoom:
            panelController.handle(.resetZoom)

        case .addressBar:
            panelController.handle(.addressBar)

        case .returnHome:
            panelController.handle(.returnHome)

        case .togglePrimaryFocus:
            panelController.handle(.togglePrimaryFocus)

        case .scrollUp:
            let lines = (userInfo?["scrollLines"] as? NSNumber)?.intValue ?? 6
            _ = panelController.scrollWebView(lines: max(1, lines))

        case .scrollDown:
            let lines = (userInfo?["scrollLines"] as? NSNumber)?.intValue ?? 6
            _ = panelController.scrollWebView(lines: -max(1, lines))

        case .reload:
            panelController.handle(.reload)

        case .cancelScroll:
            panelController.cancelExternalScrollCommands()

        case .settings:
            showGlobalSettings()

        case .togglePin:
            panelController.handle(.togglePin)

        case .setResidency:
            guard let rawValue = userInfo?["residencyPolicy"] as? String,
                  let policy = SlotResidencyPolicy(rawValue: rawValue) else { return }
            panelController.handle(.setResidency(policy))

        case .focusInputForVoice:
            guard let requestID = userInfo?["requestID"] as? String else { return }
            let protocolVersion = (userInfo?["protocolVersion"] as? NSNumber)?.intValue
                ?? 1
            guard protocolVersion == FloatTabsExternalCommand.protocolVersion else {
                postExternalVoiceFocusResult(
                    requestID: requestID,
                    result: .failed("protocol-mismatch-\(protocolVersion)")
                )
                return
            }

            externalVoiceFocusTask?.cancel()
            externalVoiceFocusRequestID = requestID
            externalVoiceFocusTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let result = await self.panelController
                    .prepareInputFocusForExternalVoice(trace: trace)
                self.postExternalVoiceFocusResult(
                    requestID: requestID,
                    result: result
                )
                if self.externalVoiceFocusRequestID == requestID {
                    self.externalVoiceFocusRequestID = nil
                    self.externalVoiceFocusTask = nil
                }
            }
        }
    }

    private func postExternalVoiceFocusResult(
        requestID: String,
        result: ExternalVoiceFocusResult
    ) {
        DistributedNotificationCenter.default().post(
            name: FloatTabsExternalCommand.focusReadyNotificationName,
            object: nil,
            userInfo: [
                "requestID": requestID,
                "protocolVersion": NSNumber(
                    value: FloatTabsExternalCommand.protocolVersion
                ),
                "ready": NSNumber(value: result.ready),
                "reason": result.reason,
            ]
        )
    }

    private static func presentConfigurationSaveFailure() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.tr("Couldn’t Save Changes", "无法保存更改")
        alert.informativeText = L10n.tr(
            "FloatTabs couldn’t save its configuration. Your previous settings were kept.",
            "FloatTabs 无法保存配置，之前的设置已保留。"
        )
        alert.addButton(withTitle: L10n.tr("OK", "好"))

        if let window = NSApp.keyWindow, window.attachedSheet == nil {
            alert.beginSheetModal(for: window)
        } else {
            NSSound.beep()
        }
    }
}
