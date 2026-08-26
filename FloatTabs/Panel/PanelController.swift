import AppKit
import WebKit

typealias BrowserProfileSwitchConfirmation = @MainActor (WebAppProfile, BrowserProfile?, String) -> Bool

struct FullscreenVisibilityIntent {
    private(set) var shouldRestoreNormalPresentation = false

    mutating func begin(wasVisible: Bool) {
        shouldRestoreNormalPresentation = wasVisible
    }

    mutating func requestPresentation() {
        shouldRestoreNormalPresentation = true
    }

    mutating func dismissPresentation() {
        shouldRestoreNormalPresentation = false
    }

    mutating func consumeRestore(currentVisibility: Bool) -> Bool {
        let restoredVisibility = currentVisibility || shouldRestoreNormalPresentation
        shouldRestoreNormalPresentation = false
        return restoredVisibility
    }
}

/// The shell is re-presented by more paths than the explicit status-item
/// show: the fullscreen restore re-presents it from inside WebKit's Space
/// teardown. Workspace activation events that macOS delivers while that
/// transition is still settling describe the pre-exit Space's frontmost
/// application rather than a fresh user choice, so a just-restored shell
/// needs the same short auto-hide grace that showFloatTabs arms.
struct WorkspaceAutoHideSuppression: Equatable {
    static let graceInterval: TimeInterval = 0.25

    private(set) var deadline: TimeInterval = -.infinity

    mutating func arm(atUptime uptime: TimeInterval) {
        deadline = uptime + Self.graceInterval
    }

    func suppressesAutoHide(nowUptime uptime: TimeInterval) -> Bool {
        uptime < deadline
    }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let panel: FloatingPanel
    private let rootView: PanelRootView
    private let sourceHostController: FullscreenSourceHostController
    private let tabStore: TabStore
    private let webViewPool: WebViewPool
    private let attentionCoordinator: WebAttentionCoordinator
    private let webFocusRouter: WebFocusRouter
    private let frameStore: PanelFrameStore
    private let confirmBrowserProfileSwitch: BrowserProfileSwitchConfirmation
    private weak var websiteCacheUsageStore: WebsiteCacheUsageStore?
    private weak var websiteCacheCleanupCoordinator: WebsiteCacheCleanupCoordinator?
    private let addressOverlayView = AddressOverlayView()
    private let zoomHUDView = ZoomHUDView()
    private var transientUIConstraints: [NSLayoutConstraint] = []
    private lazy var slotLifecycleCoordinator = SlotLifecycleCoordinator(
        webViewPool: webViewPool,
        container: rootView.webPanelContainerView,
        coldReleaseDelay: preferencesStore.coldWebViewReleaseDelay,
        warmReleaseDelay: preferencesStore.warmWebViewRetentionDelay,
        onRuntimeReleased: { [weak self] profile in
            self?.handleRuntimeReleased(profile)
        },
        attentionProtectionQuery: { [weak self] slotID in
            self?.attentionCoordinator.isAttentionProtected(slotID) ?? false
        }
    )

    /// Stage C routing boundary: normalized bridge observations become
    /// coordinator events, with actual visibility resolved only for
    /// completion. The owner gathers the facts; the router stays stateless.
    private lazy var attentionRouter = WebAttentionObservationRouter(
        attentionCoordinator: attentionCoordinator,
        isUserVisible: { [weak self] slotID in
            self?.isAttentionUserVisible(slotID: slotID) ?? false
        }
    )

    private var previousApplication: NSRunningApplication?
    private var restoredFrame: NSRect?
    private var hasPositionedPanel = false
    private var lastSynchronizedActiveID: UUID?
    private var lastSynchronizedActiveProfile: WebAppProfile?
    private let preferencesStore: AppPreferencesStore
    private(set) var isPinned = false
    private var externalMouseMonitor: Any?
    private var requestedVisibility = false
    private var pendingSlotSynchronization = false
    private var lastPresentationUptime: TimeInterval = -.infinity
    private var workspaceAutoHideSuppression = WorkspaceAutoHideSuppression()
    private var fullscreenProfile: WebAppProfile?
    private var companionActiveProfile: WebAppProfile?
    private var fullscreenVisibilityIntent = FullscreenVisibilityIntent()
    private var shouldClampAfterFullscreen = false
    private var needsFocusAfterApplicationActivation = false

    var isVisible: Bool {
        requestedVisibility
    }

    /// The status item and global shortcut normally toggle the requested
    /// visibility. During a WebKit fullscreen exit, however, requested state
    /// can briefly be true while the shell is physically ordered out. Treat
    /// that transition as hidden so the next shortcut re-presents the shell
    /// instead of hiding an already invisible window.
    var isPresentationActuallyVisible: Bool {
        panel.isVisible
    }

    static func shouldPresentAfterToggle(shellIsVisible: Bool) -> Bool {
        !shellIsVisible
    }

    func toggleFloatTabs() {
        fullscreenExperimentLog(
            "TOGGLE_REQUEST requested=\(requestedVisibility) "
                + "actual=\(panel.isVisible) "
                + "session=\(sourceHostController.sessionState.rawValue)"
        )
        if Self.shouldPresentAfterToggle(shellIsVisible: panel.isVisible) {
            showFloatTabs()
        } else {
            hideFloatTabs()
        }
    }

    /// AppCoordinator uses this edge-triggered callback to wake the persisted
    /// automatic cache scheduler. The callback never performs WebKit work on
    /// the panel's visibility path.
    var onPanelBecameHidden: (() -> Void)?

    /// Local event monitors only receive this process's events, so AppKit's
    /// application-wide active flag is not an additional safety boundary here.
    /// In an LSUIElement accessory app that flag can briefly be false while a
    /// FloatTabs source window is key. A fullscreen source also remains an
    /// interactive FloatTabs presentation when its companion shell is hidden.
    var acceptsAppCommands: Bool {
        Self.acceptsAppCommands(
            requestedVisibility: requestedVisibility,
            sourceSessionLocked: sourceHostController.isSessionLocked
        )
    }

    static func acceptsAppCommands(
        requestedVisibility: Bool,
        sourceSessionLocked: Bool
    ) -> Bool {
        requestedVisibility || sourceSessionLocked
    }

    var selectedSlotName: String? {
        tabStore.activeProfile?.name
    }

    var isShowingUnsupportedBrowserProfile: Bool {
        if sourceHostController.isSessionLocked {
            return sourceHostController.companionContainer.isShowingUnsupportedBrowserProfile
        }
        return rootView.webPanelContainerView.isShowingUnsupportedBrowserProfile
    }

    var displayedUnsupportedBrowserProfileName: String? {
        if sourceHostController.isSessionLocked {
            return sourceHostController.companionContainer.displayedUnsupportedBrowserProfileName
        }
        return rootView.webPanelContainerView.displayedUnsupportedBrowserProfileName
    }

    static func unsupportedBrowserProfileName(
        for profile: WebAppProfile,
        error: Error,
        browserProfiles: [BrowserProfile]
    ) -> String? {
        guard profile.browserProfileID != nil,
              let providerError = error as? BrowserProfileDataStoreProviderError,
              providerError == .customProfilesUnsupported else {
            return nil
        }

        guard let browserProfileID = profile.browserProfileID else {
            return nil
        }
        return browserProfiles.first(where: { $0.id == browserProfileID })?.name
            ?? "Selected Profile"
    }

    /// The menu bar favicon source is the selected Slot's committed site when
    /// a resident WebView has one. Cold/no-commit Slots intentionally fall back
    /// to their configured Home URL until WebKit reports a real commit.
    var selectedSlotFaviconURL: URL? {
        guard let activeProfile = tabStore.activeProfile else { return nil }
        return faviconURL(for: activeProfile)
    }

    var attentionReadyCount: Int {
        attentionCoordinator.readySlotIDs.count
    }

    var onSelectedSlotPresentationChange: ((String?, URL?) -> Void)?
    var onAttentionPresentationChange: ((Int, Bool) -> Void)?
    var onOpenGlobalSettings: (() -> Void)?

    init(
        tabStore: TabStore,
        webViewPool: WebViewPool,
        attentionCoordinator: WebAttentionCoordinator = WebAttentionCoordinator(),
        frameStore: PanelFrameStore = PanelFrameStore(),
        preferencesStore: AppPreferencesStore? = nil,
        webFocusRouter: WebFocusRouter? = nil,
        confirmBrowserProfileSwitch: @escaping BrowserProfileSwitchConfirmation = PanelController.defaultBrowserProfileSwitchConfirmation
    ) {
        self.tabStore = tabStore
        self.webViewPool = webViewPool
        self.attentionCoordinator = attentionCoordinator
        self.webFocusRouter = webFocusRouter ?? WebFocusRouter()
        self.frameStore = frameStore
        self.confirmBrowserProfileSwitch = confirmBrowserProfileSwitch
        self.preferencesStore = preferencesStore ?? AppPreferencesStore()
        restoredFrame = frameStore.loadFrame()

        let initialFrame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        panel = FloatingPanel(contentRect: initialFrame)
        rootView = PanelRootView()
        sourceHostController = FullscreenSourceHostController(
            container: rootView.webPanelContainerView,
            resizeHandle: rootView.resizeHandleView,
            resizeReadout: rootView.resizeReadoutView,
            shellWindow: panel
        )

        super.init()

        panel.delegate = self
        panel.contentView = rootView

        sourceHostController.onSessionLockChange = { [weak self] isLocked in
            self?.handleSourceSessionLockChange(isLocked: isLocked)
        }
        sourceHostController.onSessionStateChange = { [weak self] state in
            self?.handleSourceSessionStateChange(state)
        }
        sourceHostController.onSourceRebuildRequired = { [weak self] in
            self?.rebuildFullscreenSourceAfterRestoreTimeout()
        }

        // The animated color outline is the only persistent shell outline.
        rootView.webPanelContainerView.layer?.borderWidth = 0
        rootView.webPanelContainerView.layer?.shadowOpacity = 0
        rootView.webPanelContainerView.layer?.shadowRadius = 0
        rootView.webPanelContainerView.layer?.shadowOffset = .zero

        configureTransientUI()

        rootView.onResizeEnded = { [weak self] in
            self?.handleManualResizeEnded()
        }
        rootView.fullscreenExitPlaceholderView.onExitFullscreen = { [weak self] in
            self?.sourceHostController.requestFullscreenExit()
        }
        configureSlotInteractions()
        configurePreferenceObservers()
        synchronizePreferencePresentation()
        rootView.externalControlZoneView.setPinned(isPinned)
        synchronizePinnedPresentation()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidActivateApplication(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidChangeActiveSpace(_:)),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        externalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            let eventTimestamp = event.timestamp
            let mouseLocation = NSEvent.mouseLocation
            Task { @MainActor [weak self] in
                self?.handleExternalMouseDown(
                    eventTimestamp: eventTimestamp,
                    mouseLocation: mouseLocation
                )
            }
        }

        webViewPool.onResidentSetChange = { [weak self] in
            self?.synchronizeResidentIndicators()
        }
        webViewPool.onAttentionObservation = { [weak self] slotID, observation in
            self?.handleAttentionObservation(slotID: slotID, observation: observation)
        }
        webViewPool.onCommittedURLChange = { [weak self] slotID, url in
            self?.handleCommittedURLChange(slotID: slotID, url: url)
        }
        tabStore.onChange = { [weak self] in
            self?.synchronizeSlotState()
        }
        synchronizeSlotState()
    }

    deinit {
        if let externalMouseMonitor {
            NSEvent.removeMonitor(externalMouseMonitor)
        }
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.removeObserver(
            self,
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.removeObserver(
            self,
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    /// macOS 14 treats activation as a contextual request. Submit it directly
    /// from the status-item action while that user intent is still available;
    /// the actual window presentation is completed after tracking unwinds.
    func prepareForStatusItemPresentation() {
        guard !requestedVisibility else { return }
        capturePreviousApplication()
        activateFloatTabs()
    }

    func showFloatTabs() {
        let presentationUptime = ProcessInfo.processInfo.systemUptime
        fullscreenExperimentLog(
            "SHOW_REQUEST requestedBefore=\(requestedVisibility) "
                + "session=\(sourceHostController.sessionState.rawValue) "
                + "panelVisible=\(panel.isVisible)"
        )
        lastPresentationUptime = presentationUptime
        workspaceAutoHideSuppression.arm(atUptime: presentationUptime)
        updateRequestedVisibility(true)
        // System has no explicit override: resolve it from the current macOS
        // appearance again whenever a hidden shell is presented. Explicit
        // Light/Dark modes use this same path so newly created Tab layers
        // cannot retain colors from an earlier appearance.
        synchronizeAppearance()
        guard !sourceHostController.isSessionLocked else {
            fullscreenVisibilityIntent.requestPresentation()
            // A companion presentation is one movable window group. Remove its
            // old Space representation before placing it on the mouse display.
            panel.orderOut(nil)
            showFullscreenCompanionIfReady()
            return
        }

        capturePreviousApplication()
        positionPanelForCurrentScreens()
        synchronizeFixedViewportAfterPositioning()
        synchronizeSourceHostFrame(display: false)
        slotLifecycleCoordinator.setPanelVisible(true, activeProfile: tabStore.activeProfile)
        synchronizeSlotState()
        needsFocusAfterApplicationActivation = !NSApp.isActive

        // Activation requests for an accessory app can be rejected while the
        // app has no ordered windows. Establish this user-requested window group
        // in WindowServer first, then transfer application/key focus below.
        panel.orderFrontRegardless()
        activateFloatTabs()

        // Establish the target display as AppKit's key-window context before
        // handing focus to the ordinary Web source window. WebKit consults the
        // main/key screen when it creates its element-fullscreen window; merely
        // ordering the cross-Space shell left that context on the previously
        // clicked display for the first fullscreen gesture.
        panel.makeKeyAndOrderFront(nil)
        focusActiveWebViewIfAvailable(makeSourceWindowMain: true)
        if NSApp.isActive {
            needsFocusAfterApplicationActivation = false
        }
        // The source host has now actually been ordered/presented/focused,
        // so a previously hidden selected Ready Slot can be acknowledged.
        acknowledgeActiveAttentionIfActuallyPresented()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            fullscreenExperimentLog(
                "SHOW shell=\(self.panel.windowNumber) source=\(self.sourceHostController.window.windowNumber) "
                    + "shellScreen=\(fullscreenExperimentScreenID(self.panel.screen)) "
                    + "sourceScreen=\(fullscreenExperimentScreenID(self.sourceHostController.window.screen)) "
                    + "shellKey=\(self.panel.isKeyWindow) "
                    + "sourceKey=\(self.sourceHostController.window.isKeyWindow) "
                    + "sourceVisible=\(self.sourceHostController.window.isVisible)"
            )
        }
    }

    func hideFloatTabs() {
        let wasVisible = requestedVisibility
        fullscreenExperimentLog(
            "HIDE_REQUEST requestedBefore=\(wasVisible) "
                + "session=\(sourceHostController.sessionState.rawValue) "
                + "panelVisible=\(panel.isVisible)"
        )
        updateRequestedVisibility(false)
        if wasVisible { onPanelBecameHidden?() }
        needsFocusAfterApplicationActivation = false
        addressOverlayView.dismiss()
        persistPanelFrame()
        panel.orderOut(nil)

        // WebKit still needs the ordered, unmoved source host and placeholder
        // until its own fullscreen controller has reattached the WKWebView.
        guard !sourceHostController.isSessionLocked else {
            fullscreenVisibilityIntent.dismissPresentation()
            tearDownFullscreenCompanion(
                pauseInactiveMedia: true,
                hidePanel: true
            )
            return
        }

        sourceHostController.orderOutIfSafe()
        slotLifecycleCoordinator.setPanelVisible(false, activeProfile: tabStore.activeProfile)

        guard let previousApplication else {
            NSApp.deactivate()
            return
        }

        self.previousApplication = nil
        NSApp.deactivate()
        _ = previousApplication.activate(options: [])
    }

    func prepareForTermination() {
        persistPanelFrame()
    }

    func storedWebAppStateSnapshot() -> StoredWebAppState {
        tabStore.storedStateSnapshot()
    }

    /// Builds the cache-management coordinator from the same WebViewPool and
    /// lifecycle authorities that own normal runtime creation and release.
    func websiteCacheCleanupCoordinator(
        preferencesStore: AppPreferencesStore,
        usageStore: WebsiteCacheUsageStore,
        sizeMeasurer: WebsiteCacheSizeMeasurer? = nil
    ) -> WebsiteCacheCleanupCoordinator {
        websiteCacheUsageStore = usageStore
        tabStore.onUserProfileUse = { [weak usageStore] browserProfileID, date in
            usageStore?.recordUse(
                of: BrowserProfileIdentity(browserProfileID: browserProfileID),
                at: date
            )
        }

        let service = WebsiteCacheCleanupService(
            dataStoreResolver: { [weak self] identity in
                guard let self else {
                    throw WebsiteCacheCleanupServiceError.dataStoreUnavailable
                }
                return try self.webViewPool.websiteDataStore(for: identity)
            }
        )

        let resolvedSizeMeasurer = sizeMeasurer ?? WebsiteCacheSizeMeasurer(
            profileIdentifiersProvider: { [weak self] in
                Set(self?.tabStore.browserProfiles.map(\.id) ?? [])
            }
        )

        let coordinator = WebsiteCacheCleanupCoordinator(
            preferencesStore: preferencesStore,
            usageStore: usageStore,
            service: service,
            sizeMeasurer: resolvedSizeMeasurer,
            profilesProvider: { [weak self, weak usageStore] in
                self?.websiteCacheProfileSnapshots(usageStore: usageStore) ?? []
            },
            activeIdentityProvider: { [weak self] in
                guard let activeProfile = self?.tabStore.activeProfile else { return nil }
                return BrowserProfileIdentity(browserProfileID: activeProfile.browserProfileID)
            },
            panelVisibilityProvider: { [weak self] in self?.isVisible ?? false },
            prepareRuntime: { [weak self] identity, allowActive in
                guard let self else {
                    throw WebsiteCacheManagementError.runtimeStillInUse
                }
                try self.prepareForWebsiteCacheCleanup(
                    identity: identity,
                    allowActive: allowActive
                )
            },
            restoreRuntime: { [weak self] in
                self?.restoreAfterWebsiteCacheCleanup()
            }
        )
        websiteCacheCleanupCoordinator = coordinator
        return coordinator
    }

    func websiteDataStore(for identity: BrowserProfileIdentity) throws -> WKWebsiteDataStore {
        try webViewPool.websiteDataStore(for: identity)
    }

    private func websiteCacheProfileSnapshots(
        usageStore: WebsiteCacheUsageStore?
    ) -> [WebsiteCacheProfileSnapshot] {
        var lastUsedByIdentity: [BrowserProfileIdentity: Date] = [:]
        var residencyByIdentity: [BrowserProfileIdentity: SlotResidencyPolicy] = [:]
        var identities = Set<BrowserProfileIdentity>([.default])

        for profile in tabStore.profiles {
            let identity = BrowserProfileIdentity(browserProfileID: profile.browserProfileID)
            identities.insert(identity)
            lastUsedByIdentity[identity] = max(
                lastUsedByIdentity[identity] ?? .distantPast,
                profile.lastUsedAt
            )
            let existingResidency = residencyByIdentity[identity] ?? .cold
            residencyByIdentity[identity] = SlotResidencyPolicy.mostProtective(
                existingResidency,
                profile.residencyPolicy
            )
        }
        for browserProfile in tabStore.browserProfiles {
            identities.insert(.custom(browserProfile.id))
        }
        // Usage history is advisory metadata, not an authority for which
        // Browser Profiles exist. Prune stale UUIDs and never resolve a store
        // for one of them.
        usageStore?.prune(keeping: identities)

        let activeIdentity = tabStore.activeProfile.map {
            BrowserProfileIdentity(browserProfileID: $0.browserProfileID)
        }
        return identities.map { identity in
            let entry = usageStore?.entry(for: identity) ?? .empty
            return WebsiteCacheProfileSnapshot(
                identity: identity,
                lastUsedAt: lastUsedByIdentity[identity]
                    ?? entry.lastUsedAt
                    ?? .distantPast,
                useCount: entry.useCount30Days,
                isActive: identity == activeIdentity,
                residencyPolicy: residencyByIdentity[identity] ?? .warm
            )
        }
    }

    private func handleRuntimeReleased(_ profile: WebAppProfile) {
        guard profile.residencyPolicy == .cold else { return }
        let identity = BrowserProfileIdentity(browserProfileID: profile.browserProfileID)

        // Cache is shared at Browser Profile scope. Do not clear it while a
        // sibling Tab using the same store still has a live WebView runtime.
        guard webViewPool.residentSlotIDs(using: identity).isEmpty else { return }
        websiteCacheCleanupCoordinator?.requestColdCleanup(for: identity)
    }

    private func prepareForWebsiteCacheCleanup(
        identity: BrowserProfileIdentity,
        allowActive: Bool
    ) throws {
        guard !sourceHostController.isSessionLocked else {
            throw WebsiteCacheManagementError.runtimeStillInUse
        }

        let activeIdentity = tabStore.activeProfile.map {
            BrowserProfileIdentity(browserProfileID: $0.browserProfileID)
        }
        if activeIdentity == identity,
           isVisible,
           !allowActive {
            throw WebsiteCacheManagementError.activeProfileProtected
        }

        for slotID in webViewPool.residentSlotIDs(using: identity) {
            // The lifecycle coordinator removes the view from its container
            // before WebViewPool drops the WKWebView and its runtime callbacks.
            slotLifecycleCoordinator.remove(slotID: slotID)
            webViewPool.release(slotID: slotID)
        }
        guard webViewPool.residentSlotIDs(using: identity).isEmpty else {
            throw WebsiteCacheManagementError.runtimeStillInUse
        }
    }

    private func restoreAfterWebsiteCacheCleanup() {
        guard !sourceHostController.isSessionLocked else { return }
        // currentURL was persisted by TabStore before runtime release. The
        // normal synchronization path therefore restores a safe currentURL or
        // homeURL without inventing a page-derived URL.
        synchronizeSlotState()
    }

    func browserProfileManagementClient(
        usageStore: WebsiteCacheUsageStore? = nil
    ) -> BrowserProfileManagementClient {
        BrowserProfileManagementClient(
            snapshot: { [weak self] in
                self?.browserProfileManagementSnapshot()
                    ?? BrowserProfileManagementSnapshot(
                        customProfiles: [],
                        referencedProfileIDs: [],
                        customProfilesSupported: false
                    )
            },
            create: { [weak self] name in
                guard let self else { throw BrowserProfileManagementError.notFound }
                return try self.createBrowserProfile(name: name)
            },
            rename: { [weak self] id, name in
                guard let self else { throw BrowserProfileManagementError.notFound }
                try self.renameBrowserProfile(id: id, name: name)
            },
            setColor: { [weak self] id, color in
                guard let self else { throw BrowserProfileManagementError.notFound }
                try self.setBrowserProfileColor(id: id, color: color)
            },
            delete: { [weak self] id in
                guard let self else { throw BrowserProfileManagementError.notFound }
                try await self.deleteBrowserProfile(id: id, usageStore: usageStore)
            }
        )
    }

    func browserProfileManagementSnapshot() -> BrowserProfileManagementSnapshot {
        var referencingWebAppNamesByProfileID: [UUID: [String]] = [:]
        for profile in tabStore.profiles {
            guard let browserProfileID = profile.browserProfileID else { continue }
            referencingWebAppNamesByProfileID[browserProfileID, default: []].append(profile.name)
        }
        return BrowserProfileManagementSnapshot(
            customProfiles: tabStore.browserProfiles,
            defaultProfilePresentation: tabStore.defaultBrowserProfilePresentation,
            referencedProfileIDs: Set(referencingWebAppNamesByProfileID.keys),
            referencingWebAppNamesByProfileID: referencingWebAppNamesByProfileID,
            customProfilesSupported: webViewPool.customBrowserProfilesSupported
        )
    }

    static func canRequestBrowserProfileSwitch(
        currentProfileID: UUID?,
        targetProfileID: UUID?,
        targetExists: Bool,
        customProfilesSupported: Bool,
        sessionIsLocked: Bool
    ) -> Bool {
        guard targetProfileID == nil || targetExists else { return false }
        guard currentProfileID != targetProfileID else { return true }
        guard !sessionIsLocked else { return false }
        guard targetProfileID == nil || customProfilesSupported else { return false }
        return true
    }

    @discardableResult
    func requestBrowserProfileSwitch(
        slotID: UUID,
        targetProfileID: UUID?
    ) -> Bool {
        guard let sourceProfile = tabStore.profiles.first(where: { $0.id == slotID }) else {
            NSSound.beep()
            return false
        }

        let targetProfile = targetProfileID.flatMap { targetID in
            tabStore.browserProfiles.first(where: { $0.id == targetID })
        }
        let targetExists = targetProfileID == nil || targetProfile != nil
        guard Self.canRequestBrowserProfileSwitch(
            currentProfileID: sourceProfile.browserProfileID,
            targetProfileID: targetProfileID,
            targetExists: targetExists,
            customProfilesSupported: webViewPool.customBrowserProfilesSupported,
            sessionIsLocked: sourceHostController.isSessionLocked
        ) else {
            NSSound.beep()
            return false
        }

        guard sourceProfile.browserProfileID != targetProfileID else {
            return true
        }

        if attentionCoordinator.isAttentionProtected(slotID),
           !confirmBrowserProfileSwitch(
                sourceProfile,
                targetProfile,
                tabStore.defaultBrowserProfilePresentation.name
           ) {
            return false
        }

        // Confirmation is a re-entrancy boundary. Re-read the authoritative
        // model and safety facts before committing the binding.
        guard let currentProfile = tabStore.profiles.first(where: { $0.id == slotID }) else {
            NSSound.beep()
            return false
        }
        let currentTargetProfile = targetProfileID.flatMap { targetID in
            tabStore.browserProfiles.first(where: { $0.id == targetID })
        }
        let currentTargetExists = targetProfileID == nil || currentTargetProfile != nil
        guard Self.canRequestBrowserProfileSwitch(
            currentProfileID: currentProfile.browserProfileID,
            targetProfileID: targetProfileID,
            targetExists: currentTargetExists,
            customProfilesSupported: webViewPool.customBrowserProfilesSupported,
            sessionIsLocked: sourceHostController.isSessionLocked
        ) else {
            NSSound.beep()
            return false
        }
        guard currentProfile.browserProfileID != targetProfileID else {
            return true
        }

        // The model/disk commit deliberately suppresses TabStore.onChange.
        // Otherwise the normal synchronization callback would create the new
        // runtime before the explicit old-runtime teardown below.
        guard tabStore.setBrowserProfile(
            slotID: slotID,
            profileID: targetProfileID,
            notifyOnSuccess: false
        ) else {
            return false
        }

        slotLifecycleCoordinator.remove(slotID: slotID)
        webViewPool.release(slotID: slotID)
        attentionCoordinator.removeSlot(slotID)
        synchronizeSlotState()
        return true
    }

    static func canRequestOpenInNewTabWithBrowserProfile(
        sourceExists: Bool,
        targetProfileID: UUID?,
        targetExists: Bool,
        customProfilesSupported: Bool,
        sessionIsLocked: Bool
    ) -> Bool {
        guard sourceExists,
              targetProfileID == nil || targetExists else {
            return false
        }
        guard !sessionIsLocked else { return false }
        guard targetProfileID == nil || customProfilesSupported else { return false }
        return true
    }

    @discardableResult
    func requestOpenInNewTabWithBrowserProfile(
        sourceSlotID: UUID,
        targetProfileID: UUID?
    ) -> WebAppProfile? {
        let sourceExists = tabStore.profiles.contains(where: { $0.id == sourceSlotID })
        let targetExists = targetProfileID == nil
            || tabStore.browserProfiles.contains(where: { $0.id == targetProfileID })
        guard Self.canRequestOpenInNewTabWithBrowserProfile(
            sourceExists: sourceExists,
            targetProfileID: targetProfileID,
            targetExists: targetExists,
            customProfilesSupported: webViewPool.customBrowserProfilesSupported,
            sessionIsLocked: sourceHostController.isSessionLocked
        ) else {
            NSSound.beep()
            return nil
        }

        // duplicateSlot owns the single transactional save and publishes the
        // new active Slot through the normal TabStore.onChange path. That path
        // creates the target runtime only after the target binding is durable.
        return tabStore.duplicateSlot(
            sourceID: sourceSlotID,
            targetBrowserProfileID: targetProfileID
        )
    }

    static func defaultBrowserProfileSwitchConfirmation(
        sourceProfile: WebAppProfile,
        targetProfile: BrowserProfile?,
        defaultProfileName: String
    ) -> Bool {
        let targetName = targetProfile?.name ?? defaultProfileName
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Switch Browser Profile?"
        alert.informativeText = "Switching \(sourceProfile.name) to \(targetName) replaces the current page runtime. Ongoing or unseen ChatGPT work may be discarded. To keep both identities live, use “Open in New Tab with Profile” instead."
        alert.addButton(withTitle: "Switch Profile")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func createBrowserProfile(name: String) throws -> BrowserProfile {
        guard webViewPool.customBrowserProfilesSupported else {
            throw BrowserProfileManagementError.unsupported
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw BrowserProfileManagementError.invalidName
        }
        let allNames = [tabStore.defaultBrowserProfilePresentation.name]
            + tabStore.browserProfiles.map(\.name)
        guard !allNames.contains(where: { $0.caseInsensitiveCompare(trimmedName) == .orderedSame }) else {
            throw BrowserProfileManagementError.duplicateName
        }

        guard let created = tabStore.createBrowserProfile(name: trimmedName) else {
            throw BrowserProfileManagementError.metadataPersistenceFailed
        }
        return created
    }

    func renameBrowserProfile(id: UUID?, name: String) throws {
        if id == nil {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                throw BrowserProfileManagementError.invalidName
            }
            guard !tabStore.browserProfiles.contains(where: {
                $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
            }) else {
                throw BrowserProfileManagementError.duplicateName
            }
            guard tabStore.renameDefaultBrowserProfile(name: trimmedName) else {
                throw BrowserProfileManagementError.metadataPersistenceFailed
            }
            return
        }

        guard let id else { throw BrowserProfileManagementError.notFound }
        guard tabStore.browserProfiles.contains(where: { $0.id == id }) else {
            throw BrowserProfileManagementError.notFound
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw BrowserProfileManagementError.invalidName
        }
        guard tabStore.defaultBrowserProfilePresentation.name.caseInsensitiveCompare(trimmedName) != .orderedSame,
              !tabStore.browserProfiles.contains(where: {
                  $0.id != id && $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
              }) else {
            throw BrowserProfileManagementError.duplicateName
        }

        guard tabStore.renameBrowserProfile(id: id, name: trimmedName) else {
            throw BrowserProfileManagementError.metadataPersistenceFailed
        }
    }

    func setBrowserProfileColor(
        id: UUID?,
        color: BrowserProfileColor
    ) throws {
        guard tabStore.setBrowserProfileColor(profileID: id, color: color) else {
            throw BrowserProfileManagementError.metadataPersistenceFailed
        }
    }

    func deleteBrowserProfile(
        id: UUID,
        usageStore: WebsiteCacheUsageStore? = nil
    ) async throws {
        guard tabStore.browserProfiles.contains(where: { $0.id == id }) else {
            throw BrowserProfileManagementError.notFound
        }
        guard !tabStore.profiles.contains(where: { $0.browserProfileID == id }) else {
            throw BrowserProfileManagementError.referenced
        }

        let identity = BrowserProfileIdentity.custom(id)
        let staleSlotIDs = webViewPool.residentSlotIDs(using: identity)
        for slotID in staleSlotIDs {
            // This is deletion cleanup for a runtime that no longer has a
            // corresponding persisted binding, not a residency policy change.
            slotLifecycleCoordinator.remove(slotID: slotID)
        }
        webViewPool.releaseRuntimes(using: identity)
        guard webViewPool.residentSlotIDs(using: identity).isEmpty else {
            throw BrowserProfileManagementError.runtimeStillResident
        }

        // The metadata remains present until the provider confirms WebKit
        // removal. TabStore owns transactional rollback if its save fails.
        try await webViewPool.removeCustomBrowserProfileDataStore(id: id)
        guard tabStore.deleteBrowserProfileMetadata(id: id) else {
            throw BrowserProfileManagementError.metadataPersistenceFailed
        }
        // A profile's operational history is removed only after both WebKit's
        // public profile-store deletion and metadata persistence succeed. A
        // failed deletion therefore remains diagnosable and retryable.
        (usageStore ?? websiteCacheUsageStore)?.removeEntry(for: identity)
    }

    /// Backup import must use the same geometry-aware path as the in-app
    /// toggle: the shell constraint and the separately hosted source window
    /// cannot be left at the previous leading inset until the next launch.
    func applyRestoredRailCollapse(_ collapsed: Bool) {
        setTabRailCollapsed(collapsed, animated: false)
    }

    @discardableResult
    func restoreStoredWebAppState(_ state: StoredWebAppState) -> Bool {
        // Replacing the stored model releases every live WebView. Never allow
        // that operation while WebKit is still using one as a fullscreen source.
        guard !sourceHostController.isSessionLocked else { return false }

        // Persist and validate the replacement before touching live runtimes. A
        // failed restore must leave the current page/DOM/session presentation
        // untouched as well as leaving the durable model unchanged.
        let existingIDs = Set(tabStore.profiles.map(\.id))
        guard tabStore.replaceStoredState(state, notifyOnSuccess: false) else {
            return false
        }

        slotLifecycleCoordinator.reset(slotIDs: existingIDs)
        for slotID in existingIDs {
            webViewPool.release(slotID: slotID)
            // Replacement Slots are new identities: their attention
            // bookkeeping starts fresh rather than being restored.
            attentionCoordinator.removeSlot(slotID)
        }
        lastSynchronizedActiveID = nil
        lastSynchronizedActiveProfile = nil
        synchronizeSlotState()
        return true
    }

    static func shouldAutoHide(panelIsVisible: Bool, isPinned: Bool) -> Bool {
        panelIsVisible && !isPinned
    }

    static func shouldPersistManualViewportToActiveTab(
        windowSizeMode: PanelWindowSizeMode
    ) -> Bool {
        windowSizeMode == .perWebApp
    }

    private func togglePinnedState() {
        isPinned.toggle()
        rootView.externalControlZoneView.setPinned(isPinned)
        synchronizePinnedPresentation()
        if isPinned, sourceHostController.sessionState == .fullscreen {
            updateRequestedVisibility(true)
            fullscreenVisibilityIntent.requestPresentation()
            showFullscreenCompanionIfReady()
        }
    }

    private func synchronizePinnedPresentation() {
        panel.setPinnedPresentation(isPinned)
        sourceHostController.setPinnedPresentation(isPinned)
    }

    static func shouldAutoHideForActivatedApplication(
        panelIsVisible: Bool,
        isPinned: Bool,
        activatedProcessIdentifier: pid_t,
        ownProcessIdentifier: pid_t
    ) -> Bool {
        panelIsVisible
            && !isPinned
            && activatedProcessIdentifier != ownProcessIdentifier
    }

    static func shouldAutoHideForExternalMouseDown(
        panelIsVisible: Bool,
        isPinned: Bool
    ) -> Bool {
        shouldAutoHide(panelIsVisible: panelIsVisible, isPinned: isPinned)
    }

    static func externalMouseDownIsInsideVisiblePresentation(
        mouseLocation: NSPoint,
        shellFrame: NSRect,
        shellIsVisible: Bool,
        sourceFrame: NSRect,
        sourceIsVisibleAndIdle: Bool
    ) -> Bool {
        (shellIsVisible && shellFrame.contains(mouseLocation))
            || (sourceIsVisibleAndIdle && sourceFrame.contains(mouseLocation))
    }

    private func handleExternalMouseDown(
        eventTimestamp: TimeInterval,
        mouseLocation: NSPoint
    ) {
        // Global monitor delivery is bridged back to MainActor. A click that
        // happened on B before the hotkey can otherwise arrive after A has been
        // presented and incorrectly hide that new presentation.
        guard eventTimestamp >= lastPresentationUptime else { return }
        if Self.externalMouseDownIsInsideVisiblePresentation(
            mouseLocation: mouseLocation,
            shellFrame: panel.frame,
            shellIsVisible: panel.isVisible,
            sourceFrame: sourceHostController.window.frame,
            sourceIsVisibleAndIdle: sourceHostController.window.isVisible
                && !sourceHostController.isSessionLocked
        ) {
            fullscreenExperimentLog(
                "GLOBAL_MOUSE_IGNORED reason=insidePresentation "
                    + "mouse=\(NSStringFromPoint(mouseLocation))"
            )
            return
        }
        guard Self.shouldAutoHideForExternalMouseDown(
            panelIsVisible: requestedVisibility,
            isPinned: isPinned
        ) else {
            return
        }
        fullscreenExperimentLog(
            "AUTO_HIDE reason=globalMouse event=\(eventTimestamp) "
                + "shown=\(lastPresentationUptime) mouse=\(NSStringFromPoint(mouseLocation))"
        )
        autoHideAfterApplicationDeactivation()
    }

    @objc private func workspaceDidActivateApplication(_ notification: Notification) {
        guard let activatedApplication = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else {
            return
        }

        if activatedApplication.processIdentifier
            == ProcessInfo.processInfo.processIdentifier {
            // Returning to FloatTabs can leave the same Slot selected, so a
            // tab change must not be required to acknowledge Ready. The
            // presentation fact below still rejects Settings or any other
            // non-Web key window.
            acknowledgeActiveAttentionIfActuallyPresented()
            return
        }

        guard !workspaceAutoHideSuppression.suppressesAutoHide(
                  nowUptime: ProcessInfo.processInfo.systemUptime
              ),
              NSWorkspace.shared.frontmostApplication?.processIdentifier
                == activatedApplication.processIdentifier,
              Self.shouldAutoHideForActivatedApplication(
                panelIsVisible: requestedVisibility,
                isPinned: isPinned,
                activatedProcessIdentifier: activatedApplication.processIdentifier,
                ownProcessIdentifier: ProcessInfo.processInfo.processIdentifier
              ) else {
            return
        }
        fullscreenExperimentLog(
            "AUTO_HIDE reason=workspace app=\(activatedApplication.bundleIdentifier ?? "unknown") "
                + "pid=\(activatedApplication.processIdentifier)"
        )
        autoHideAfterApplicationDeactivation()
    }

    @objc private func workspaceDidChangeActiveSpace(_ notification: Notification) {
        guard requestedVisibility,
              !sourceHostController.isSessionLocked else {
            return
        }

        // The notification can arrive before WindowServer has finished
        // materializing the host application's fullscreen Space. Reconcile on
        // two subsequent run-loop turns so both the immediate Space switch and
        // the delayed fullscreen transition get the actual WKWebView window.
        let delays: [TimeInterval] = [0, 0.2]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self,
                      self.requestedVisibility,
                      !self.sourceHostController.isSessionLocked else {
                    return
                }
                self.sourceHostController.reconcileVisiblePresentationAfterSpaceChange()
            }
        }
    }

    private func autoHideAfterApplicationDeactivation() {
        // The user has already selected another application. Unlike the explicit
        // global-toggle hide path, do not reactivate `previousApplication` here:
        // doing so would steal focus from the application the user just chose.
        updateRequestedVisibility(false)
        needsFocusAfterApplicationActivation = false
        addressOverlayView.dismiss()
        persistPanelFrame()
        panel.orderOut(nil)
        guard !sourceHostController.isSessionLocked else {
            fullscreenVisibilityIntent.dismissPresentation()
            tearDownFullscreenCompanion(
                pauseInactiveMedia: true,
                hidePanel: true
            )
            previousApplication = nil
            return
        }
        sourceHostController.orderOutIfSafe()
        slotLifecycleCoordinator.setPanelVisible(false, activeProfile: tabStore.activeProfile)
        previousApplication = nil
    }

#if DEBUG
    func benchmarkControlSnapshot() -> [String: Any] {
        let profiles: [[String: Any]] = tabStore.orderedProfiles.map { profile in
            [
                "id": profile.id.uuidString,
                "order": profile.order,
                "name": profile.name,
                "residency": profile.residencyPolicy.rawValue,
                "background_media": profile.backgroundMediaPolicy.rawValue,
                "website_mode": profile.renderingProfile.websiteMode.rawValue,
                "viewport_width": Double(profile.renderingProfile.viewportWidth),
                "viewport_height": Double(profile.renderingProfile.viewportHeight),
                "zoom": Double(profile.renderingProfile.zoom),
            ]
        }
        var snapshot: [String: Any] = [
            "visible": isVisible,
            "shell_visible": panel.isVisible,
            "shell_screen": fullscreenExperimentScreenID(panel.screen),
            "source_visible": sourceHostController.window.isVisible,
            "source_screen": fullscreenExperimentScreenID(sourceHostController.window.screen),
            "source_parented_to_shell": sourceHostController.window.parent === panel,
            "source_key": sourceHostController.window.isKeyWindow,
            "pinned": isPinned,
            "profiles": profiles,
            "resident_slot_count": webViewPool.count,
            "resident_slot_ids": webViewPool.residentSlotIDs.map(\.uuidString).sorted(),
            "pending_cold_release_count": slotLifecycleCoordinator.pendingColdReleaseCount,
            "pending_warm_release_count": slotLifecycleCoordinator.pendingWarmReleaseCount,
            "media_protected_slot_ids": slotLifecycleCoordinator.mediaProtectedIDs.map(\.uuidString).sorted(),
            "hidden_active_grace_pending": slotLifecycleCoordinator.isHiddenActiveGracePending,
            "fullscreen_source_state": sourceHostController.sessionState.rawValue,
        ]
        snapshot["active_slot_id"] = tabStore.activeTabID?.uuidString ?? NSNull()

        return snapshot
    }

    /// Read-only cross-feature diagnostics. Each accessor exposes one piece
    /// of already-existing internal state — the rail's current Ready
    /// projection and the lifecycle coordinator's current plan bookkeeping —
    /// so integration tests can observe real wiring without any mutation,
    /// second source of truth, or test-specific business path.
    func debugIsProjectingReadyAttention(slotID: UUID) -> Bool {
        rootView.externalControlZoneView
            .tabView(for: slotID)?.isShowingReadyAttention ?? false
    }

    var debugPendingColdReleaseCount: Int {
        slotLifecycleCoordinator.pendingColdReleaseCount
    }

    var debugPendingWarmReleaseCount: Int {
        slotLifecycleCoordinator.pendingWarmReleaseCount
    }

    var debugIsHiddenActiveGracePending: Bool {
        slotLifecycleCoordinator.isHiddenActiveGracePending
    }

    func debugInactivePlanToken(slotID: UUID) -> UUID? {
        slotLifecycleCoordinator.debugInactivePlanToken(slotID: slotID)
    }

    func benchmarkSetResourcePolicy(
        slotIDStrings: [String],
        residencyRawValue: String?,
        backgroundMediaRawValue: String?
    ) -> Bool {
        let ids = slotIDStrings.compactMap(UUID.init(uuidString:))
        guard ids.count == slotIDStrings.count, !ids.isEmpty else { return false }
        let validIDs = Set(tabStore.profiles.map(\.id))
        guard ids.allSatisfy(validIDs.contains) else { return false }

        let residency = residencyRawValue.flatMap(SlotResidencyPolicy.init(rawValue:))
        let media = backgroundMediaRawValue.flatMap(BackgroundMediaPolicy.init(rawValue:))
        if residencyRawValue != nil, residency == nil { return false }
        if backgroundMediaRawValue != nil, media == nil { return false }
        guard residency != nil || media != nil else { return false }

        for id in ids {
            guard tabStore.updateResourcePolicy(
                id: id,
                residencyPolicy: residency,
                backgroundMediaPolicy: media
            ) else {
                return false
            }
        }
        return true
    }

    func benchmarkSelect(slotIDString: String) -> Bool {
        guard let id = UUID(uuidString: slotIDString) else { return false }
        return tabStore.select(id: id)
    }
#endif

    func handle(_ command: AppCommand) {
        switch command {
        case let .selectSlot(index):
            guard let slot = tabStore.slotByKeyboardIndex(index) else { return }
            _ = tabStore.select(id: slot.id)

        case .nextSlot:
            _ = tabStore.selectNext()

        case .previousSlot:
            _ = tabStore.selectPrevious()

        case .addWebApp:
            presentAddWebAppEditor()

        case .zoomIn:
            changeActiveZoom(larger: true)

        case .zoomOut:
            changeActiveZoom(larger: false)

        case .resetZoom:
            setActiveZoom(1.0)

        case .addressBar:
            presentAddressBar()

        case .returnHome:
            returnActiveSlotHome()

        case .reload:
            reloadActiveSlot()

        case .togglePrimaryFocus:
            togglePrimaryWebFocus()

        case .settings:
            onOpenGlobalSettings?()

        case .togglePin:
            togglePinnedState()
        }
    }

    private func configureTransientUI() {
        addressOverlayView.translatesAutoresizingMaskIntoConstraints = false
        zoomHUDView.translatesAutoresizingMaskIntoConstraints = false
        installTransientUI(
            in: sourceHostController.transientUIContainerView,
            viewport: sourceHostController.transientUIContainerView
        )

        addressOverlayView.onCommit = { [weak self] rawValue in
            self?.commitAddress(rawValue) ?? false
        }
        addressOverlayView.onCopy = { [weak self] rawValue in
            self?.copyAddressToPasteboard(rawValue) ?? false
        }
        addressOverlayView.onCreateWebApp = { [weak self] in
            self?.presentDerivedWebAppFromCurrentPage()
        }
        addressOverlayView.onDismiss = { [weak self] in
            self?.focusActiveWebViewIfAvailable()
        }
    }

    private func installTransientUI(in host: NSView, viewport: NSView) {
        guard addressOverlayView.superview !== host || zoomHUDView.superview !== host else {
            return
        }

        NSLayoutConstraint.deactivate(transientUIConstraints)
        transientUIConstraints.removeAll()
        addressOverlayView.removeFromSuperview()
        zoomHUDView.removeFromSuperview()
        host.addSubview(addressOverlayView)
        host.addSubview(zoomHUDView)

        transientUIConstraints = [
            addressOverlayView.leadingAnchor.constraint(
                equalTo: viewport.leadingAnchor,
                constant: 22
            ),
            addressOverlayView.trailingAnchor.constraint(
                equalTo: viewport.trailingAnchor,
                constant: -22
            ),
            addressOverlayView.topAnchor.constraint(
                equalTo: viewport.topAnchor,
                constant: 22
            ),
            addressOverlayView.heightAnchor.constraint(equalToConstant: 52),

            zoomHUDView.centerXAnchor.constraint(
                equalTo: viewport.centerXAnchor
            ),
            zoomHUDView.bottomAnchor.constraint(
                equalTo: viewport.bottomAnchor,
                constant: -28
            ),
            zoomHUDView.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),
            zoomHUDView.heightAnchor.constraint(equalToConstant: 34),
        ]
        NSLayoutConstraint.activate(transientUIConstraints)
    }

    private func synchronizeTransientUIHost() {
        if sourceHostController.isSessionLocked {
            installTransientUI(
                in: rootView,
                viewport: rootView.webViewportLayoutView
            )
        } else {
            installTransientUI(
                in: sourceHostController.transientUIContainerView,
                viewport: sourceHostController.transientUIContainerView
            )
        }
    }

    private func configurePreferenceObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appearancePreferenceDidChange(_:)),
            name: .floatTabsAppearanceDidChange,
            object: preferencesStore
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(borderPreferenceDidChange(_:)),
            name: .floatTabsBorderPreferenceDidChange,
            object: preferencesStore
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowSizeModeDidChange(_:)),
            name: .floatTabsWindowSizeModeDidChange,
            object: preferencesStore
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fixedWindowSizeDidChange(_:)),
            name: .floatTabsFixedWindowSizeDidChange,
            object: preferencesStore
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(slotRetentionPreferenceDidChange(_:)),
            name: .floatTabsSlotRetentionDidChange,
            object: preferencesStore
        )
    }

    @objc private func appearancePreferenceDidChange(_ notification: Notification) {
        synchronizeAppearance()
    }

    private func synchronizeAppearance() {
        let appearance = preferencesStore.appearanceMode.appKitAppearance
        panel.appearance = appearance
        sourceHostController.window.appearance = appearance
        rootView.externalControlZoneView.refreshAppearance()
        synchronizeBorderTheme()
        rootView.needsDisplay = true
    }

    @objc private func borderPreferenceDidChange(_ notification: Notification) {
        synchronizeBorderTheme()
    }

    @objc private func windowSizeModeDidChange(_ notification: Notification) {
        synchronizeWindowSizeMode()
        switch preferencesStore.windowSizeMode {
        case .perWebApp:
            if let active = tabStore.activeProfile {
                applyPreferredViewport(active.renderingProfile.viewportSize)
            }
        case .fixed:
            guard hasPositionedPanel else { return }
            if preferencesStore.hasStoredFixedViewportSize {
                applySharedFixedViewport(preferencesStore.fixedViewportSize, animated: panel.isVisible)
            } else {
                let viewport = PanelMetrics.viewportSize(forPanelSize: panel.frame.size)
                preferencesStore.fixedViewportSize = viewport
            }
        }
    }

    @objc private func fixedWindowSizeDidChange(_ notification: Notification) {
        guard preferencesStore.windowSizeMode == .fixed else { return }
        applySharedFixedViewport(preferencesStore.fixedViewportSize, animated: panel.isVisible)
    }

    @objc private func slotRetentionPreferenceDidChange(_ notification: Notification) {
        slotLifecycleCoordinator.updateReleaseDelays(
            coldReleaseDelay: preferencesStore.coldWebViewReleaseDelay,
            warmReleaseDelay: preferencesStore.warmWebViewRetentionDelay
        )
    }

    private func synchronizePreferencePresentation() {
        synchronizeAppearance()
        synchronizeBorderTheme()
        synchronizeWindowSizeMode()
    }

    private func synchronizeBorderTheme() {
        rootView.interactionBorderView.apply(
            theme: preferencesStore.borderTheme,
            customColor: preferencesStore.customBorderColor
        )
        sourceHostController.railFoldControl.apply(
            theme: preferencesStore.borderTheme,
            customColor: preferencesStore.customBorderColor
        )
        rootView.companionRailFoldControlView.apply(
            theme: preferencesStore.borderTheme,
            customColor: preferencesStore.customBorderColor
        )
    }

    private func synchronizeWindowSizeMode() {
        rootView.externalControlZoneView.setWindowSizeEditingEnabled(
            preferencesStore.windowSizeMode == .perWebApp
        )
    }

    private func configureSlotInteractions() {
        let rail = rootView.externalControlZoneView

        rail.onSelect = { [weak self] id in
            _ = self?.tabStore.select(id: id)
        }
        rail.onReturnHome = { [weak self] id in
            self?.returnSlotHome(id: id)
        }
        rail.onReload = { [weak self] id in
            self?.reloadSlot(id: id)
        }
        rail.onAdd = { [weak self] in
            self?.presentAddWebAppEditor()
        }
        rail.onEdit = { [weak self] id in
            self?.presentEditWebAppEditor(id: id)
        }
        rail.onRemove = { [weak self] id in
            self?.presentRemoveConfirmation(id: id)
        }
        rail.onSetWebsiteMode = { [weak self] id, mode in
            guard let self,
                  let profile = self.tabStore.profiles.first(where: { $0.id == id }) else { return }
            _ = self.tabStore.updateRenderingProfile(
                id: id,
                renderingProfile: profile.renderingProfile.settingWebsiteMode(mode)
            )
        }
        rail.onSetWindowSize = { [weak self] id, preset in
            guard let self,
                  self.preferencesStore.windowSizeMode == .perWebApp,
                  let profile = self.tabStore.profiles.first(where: { $0.id == id }),
                  let size = preset.size,
                  self.tabStore.updateRenderingProfile(
                    id: id,
                    renderingProfile: profile.renderingProfile.settingSimplePreset(preset)
                  ) else { return }
            if self.tabStore.activeTabID == id {
                self.applyPreferredViewport(size)
            }
        }
        rail.onSetZoom = { [weak self] id, zoom in
            _ = self?.tabStore.updateZoom(id: id, zoom: zoom)
        }
        rail.onSetResidency = { [weak self] id, policy in
            guard let self,
                  self.tabStore.updateResourcePolicy(id: id, residencyPolicy: policy),
                  let updatedProfile = self.tabStore.profiles.first(where: { $0.id == id }) else {
                return
            }
            // If a Slot was already cold/detached when its label changes to
            // Cold, there will be no later lifecycle release callback. Apply
            // the same safe fast-path immediately; the coordinator still
            // revalidates the current aggregate residency for the shared
            // Browser Profile.
            self.handleRuntimeReleased(updatedProfile)
        }
        rail.onSetBackgroundMedia = { [weak self] id, policy in
            _ = self?.tabStore.updateResourcePolicy(id: id, backgroundMediaPolicy: policy)
        }
        rail.onSetBrowserProfile = { [weak self] id, profileID in
            _ = self?.requestBrowserProfileSwitch(
                slotID: id,
                targetProfileID: profileID
            )
        }
        rail.onOpenInNewTabWithBrowserProfile = { [weak self] id, profileID in
            _ = self?.requestOpenInNewTabWithBrowserProfile(
                sourceSlotID: id,
                targetProfileID: profileID
            )
        }
        rail.onManageBrowserProfiles = { [weak self] in
            self?.onOpenGlobalSettings?()
        }
        rail.onReorder = { [weak self] id, destination in
            _ = self?.tabStore.move(id: id, toIndex: destination)
        }
        rail.onSettings = { [weak self] in
            self?.onOpenGlobalSettings?()
        }
        rail.onTogglePin = { [weak self] in
            self?.togglePinnedState()
        }
        let toggleRail: () -> Void = { [weak self] in
            guard let self else { return }
            // The fullscreen source frame is frozen by design while WebKit
            // owns the WebView; the companion fold grip stays reachable during
            // element fullscreen, so refuse geometry changes there instead of
            // letting shell and source drift apart until restore.
            guard !self.sourceHostController.isSessionLocked else {
                NSSound.beep()
                return
            }
            self.setTabRailCollapsed(
                !self.rootView.externalControlZoneView.isRailCollapsed,
                animated: true
            )
        }
        sourceHostController.railFoldControl.onActivate = toggleRail
        rootView.companionRailFoldControlView.onActivate = toggleRail
        setTabRailCollapsed(preferencesStore.isTabRailCollapsed, animated: false)
    }

    /// Collapse is physical-only (see PanelRootView.setTabRailCollapsed). The
    /// persisted window frame, nominal panel/viewport formulas and
    /// manual-resize persistence all stay 76-based; only the shell's zone
    /// width, the drag bands and the source window's physical frame move.
    /// Re-expanding therefore returns the content to exactly the persisted
    /// nominal viewport size.
    private func setTabRailCollapsed(_ collapsed: Bool, animated: Bool) {
        guard !sourceHostController.isSessionLocked else { return }
        preferencesStore.isTabRailCollapsed = collapsed
        sourceHostController.railLeadingInset = collapsed
            ? PanelMetrics.collapsedRailLeadingInset
            : PanelMetrics.externalControlZoneWidth
        rootView.setTabRailCollapsed(collapsed, animated: animated)
        sourceHostController.railFoldControl.setExpanded(!collapsed, animated: animated)
        rootView.companionRailFoldControlView.setExpanded(
            !collapsed,
            animated: animated
        )
        synchronizeSourceHostFrame(display: true, animated: animated)
    }

    private func synchronizeSlotState() {
        synchronizeBrowserProfileMenuPresentation()
        guard !sourceHostController.isSessionLocked else {
            pendingSlotSynchronization = true
            synchronizeFullscreenCompanionSlotState()
            return
        }
        pendingSlotSynchronization = false

        let orderedProfiles = tabStore.orderedProfiles
        rootView.externalControlZoneView.apply(
            profiles: orderedProfiles,
            activeTabID: tabStore.activeTabID
        )
        synchronizeAttentionIndicators()
        synchronizeResidentIndicators()
        slotLifecycleCoordinator.reconcile(profiles: orderedProfiles)

        guard let activeProfile = tabStore.activeProfile else {
            if let previous = lastSynchronizedActiveProfile {
                slotLifecycleCoordinator.deactivate(profile: previous)
            }
            lastSynchronizedActiveID = nil
            lastSynchronizedActiveProfile = nil
            webFocusRouter.setCurrentWebView(nil)
            rootView.webPanelContainerView.showEmptyState()
            synchronizeResidentIndicators()
            onSelectedSlotPresentationChange?(nil, nil)
            return
        }

        let activeChanged = lastSynchronizedActiveID != activeProfile.id
        if activeChanged,
           let previous = lastSynchronizedActiveProfile,
           previous.id != activeProfile.id {
            slotLifecycleCoordinator.deactivate(profile: previous)
        }

        if activeChanged, hasPositionedPanel, preferencesStore.followPreferredSize {
            applyPreferredViewport(activeProfile.renderingProfile.viewportSize)
        }

        let webView: WKWebView
        do {
            webView = try webViewPool.webView(for: activeProfile)
        } catch {
            webFocusRouter.setCurrentWebView(nil)
            if let profileName = Self.unsupportedBrowserProfileName(
                for: activeProfile,
                error: error,
                browserProfiles: tabStore.browserProfiles
            ) {
                rootView.webPanelContainerView.showUnsupportedBrowserProfile(
                    profileName: profileName,
                    defaultProfileName: tabStore.defaultBrowserProfilePresentation.name
                )
            } else {
                rootView.webPanelContainerView.showEmptyState()
            }
            synchronizeResidentIndicators()
            return
        }
        rootView.webPanelContainerView.show(
            webView: webView,
            slotID: activeProfile.id,
            residencyPolicy: activeProfile.residencyPolicy
        )
        webFocusRouter.setCurrentWebView(webView)
        slotLifecycleCoordinator.activate(profile: activeProfile)
        WebViewFactory.configureHiddenScrollers(in: webView)
        sourceHostController.observeFullscreenState(of: webView)
        lastSynchronizedActiveID = activeProfile.id
        lastSynchronizedActiveProfile = activeProfile
        synchronizeResidentIndicators()
        onSelectedSlotPresentationChange?(
            activeProfile.name,
            faviconURL(for: activeProfile)
        )

        // The new WebView is now the physically current presentation; the
        // helper itself refuses to acknowledge while nothing is visible.
        acknowledgeAttentionIfActuallyVisible(slotID: activeProfile.id)

        if panel.isVisible,
           panel.isKeyWindow || sourceHostController.window.isKeyWindow {
            sourceHostController.orderFrontAndFocus(webView)
        }
    }

    private func faviconURL(for profile: WebAppProfile) -> URL? {
        webViewPool.committedURL(for: profile.id) ?? profile.homeURL
    }

    private func handleCommittedURLChange(slotID: UUID, url: URL) {
        guard tabStore.activeTabID == slotID,
              let activeProfile = tabStore.activeProfile,
              activeProfile.id == slotID else {
            return
        }
        onSelectedSlotPresentationChange?(activeProfile.name, url)
        if let webView = selectedPresentationWebView() {
            Task { @MainActor [weak self, weak webView] in
                guard let self, let webView else { return }
                await self.webFocusRouter.refreshRecognition(for: webView)
            }
        }
    }

    private func synchronizeResidentIndicators() {
        rootView.externalControlZoneView.setResidentSlotIDs(webViewPool.residentSlotIDs)
    }

    private func synchronizeBrowserProfileMenuPresentation() {
        let options = [BrowserProfileMenuOption.defaultProfile(
            name: tabStore.defaultBrowserProfilePresentation.name,
            color: tabStore.defaultBrowserProfilePresentation.color
        )]
            + tabStore.browserProfiles.map {
                BrowserProfileMenuOption(
                    id: $0.id,
                    name: $0.name,
                    color: $0.color,
                    isEnabled: webViewPool.customBrowserProfilesSupported
                )
            }
        rootView.externalControlZoneView.setBrowserProfileMenuSnapshot(
            options: options,
            assignmentEnabled: !sourceHostController.isSessionLocked,
            duplicationEnabled: !sourceHostController.isSessionLocked
        )
    }

    private func synchronizeAttentionIndicators() {
        let readySlotIDs = attentionCoordinator.readySlotIDs
        rootView.externalControlZoneView.setReadySlotIDs(readySlotIDs)
        onAttentionPresentationChange?(readySlotIDs.count, requestedVisibility)
    }

    private func updateRequestedVisibility(_ visible: Bool) {
        requestedVisibility = visible
        onAttentionPresentationChange?(
            attentionCoordinator.readySlotIDs.count,
            requestedVisibility
        )
    }

    // MARK: Attention visibility + acknowledgement

    /// Routes an observation through the Stage C authority, then compares the
    /// same authority on both sides of the observation. A protection-ending
    /// runtime reset may arrive after an old inactive timer was skipped, so an
    /// already-inactive Warm/Cold Slot gets a fresh lifecycle boundary here.
    private func handleAttentionObservation(
        slotID: UUID,
        observation: ChatGPTAttentionObservation
    ) {
        let wasProtected = attentionCoordinator.isAttentionProtected(slotID)

        attentionRouter.handle(observation, for: slotID)
        synchronizeAttentionIndicators()

        let isProtected = attentionCoordinator.isAttentionProtected(slotID)
        guard wasProtected,
              !isProtected,
              let profile = tabStore.profiles.first(where: { $0.id == slotID }) else {
            return
        }

        slotLifecycleCoordinator.restartAfterAttentionProtectionEnded(
            profile: profile
        )
    }

    /// The one authoritative attention-visibility mapping. Gathers the actual
    /// physical presentation facts — pooled runtime identity, current normal
    /// presentation, source-window visibility, fullscreen source/companion
    /// state — and lets `AttentionPresentation` decide. Logical selection or
    /// residency alone never make a Slot visible.
    func isAttentionUserVisible(slotID: UUID) -> Bool {
        let pooledWebView = webViewPool.existingWebView(for: slotID)
        let facts = AttentionPresentation.Facts(
            slotID: slotID,
            sessionIsLocked: sourceHostController.isSessionLocked,
            pooledWebViewExists: pooledWebView != nil,
            normalCurrentWebViewIsSlotWebView: pooledWebView.map { webView in
                rootView.webPanelContainerView.currentWebView === webView
            } ?? false,
            sourceWindowIsVisible: sourceHostController.window.isVisible,
            webPresentationOwnsActiveInteraction: pooledWebView.map(
                ownsActiveInteraction(of:)
            ) ?? false,
            fullscreenSourceSlotID: fullscreenProfile?.id,
            panelIsVisible: panel.isVisible,
            companionSlotID: companionActiveProfile?.id,
            companionCurrentWebViewIsSlotWebView: pooledWebView.map { webView in
                sourceHostController.companionContainer.currentWebView === webView
            } ?? false
        )
        return AttentionPresentation.isUserVisible(facts)
    }

    /// Reads the current WebView/window topology at the moment the attention
    /// decision is requested. `WKWebView.window` is the actual interaction
    /// surface for normal, companion, and WebKit-owned fullscreen modes; its
    /// key-window status is stronger than process-level activity and changes
    /// with the real AppKit focus transfer. No foreground state is stored.
    private func ownsActiveInteraction(of webView: WKWebView) -> Bool {
        webView.window?.isKeyWindow == true
    }

    /// Acknowledges a Slot's completed-but-unseen output only when that
    /// output is actually presented right now. Calling this for Idle or
    /// Generating Slots is harmless: the coordinator is the transition
    /// authority and ignores it.
    func acknowledgeAttentionIfActuallyVisible(slotID: UUID) {
        attentionCoordinator.acknowledge(
            slotID: slotID,
            userVisible: isAttentionUserVisible(slotID: slotID)
        )
        synchronizeAttentionIndicators()
    }

    private func acknowledgeActiveAttentionIfActuallyPresented() {
        guard let activeSlotID = tabStore.activeTabID else { return }
        acknowledgeAttentionIfActuallyVisible(slotID: activeSlotID)
    }

    private func focusActiveWebViewIfAvailable(makeSourceWindowMain: Bool = false) {
        guard !addressOverlayView.isPresented else { return }
        if sourceHostController.isSessionLocked {
            if let webView = sourceHostController.companionContainer.currentWebView {
                WebViewFocus.focus(webView, in: panel)
            }
            return
        }
        sourceHostController.orderFrontAndFocus(
            rootView.webPanelContainerView.currentWebView,
            makeSourceWindowMain: makeSourceWindowMain
        )
    }

    private func togglePrimaryWebFocus() {
        guard let webView = selectedPresentationWebView() else {
            Task { @MainActor [weak self] in
                _ = await self?.webFocusRouter.togglePrimaryFocus()
            }
            return
        }

        webFocusRouter.setCurrentWebView(webView)
        if sourceHostController.isSessionLocked {
            panel.makeKeyAndOrderFront(nil)
            WebViewFocus.focus(webView, in: panel)
        } else {
            sourceHostController.orderFrontAndFocus(webView)
        }

        Task { @MainActor [weak self, weak webView] in
            guard let self, let webView,
                  self.webFocusRouter.currentWebView === webView else { return }
            _ = await self.webFocusRouter.togglePrimaryFocus()
        }
    }

    private func returnActiveSlotHome() {
        guard let id = tabStore.activeTabID else { return }
        returnSlotHome(id: id)
    }

    private func reloadActiveSlot() {
        guard let id = tabStore.activeTabID else { return }
        reloadSlot(id: id)
    }

    private func reloadSlot(id: UUID) {
        guard webViewPool.reload(slotID: id) else { return }
        if tabStore.activeTabID == id {
            focusActiveWebViewIfAvailable()
        }
    }

    private func returnSlotHome(id: UUID) {
        guard let profile = tabStore.profiles.first(where: { $0.id == id }),
              WebAppURL.isSafe(profile.homeURL) else {
            return
        }

        // `homeURL` is stable Slot identity; only `currentURL` moves. Updating
        // currentURL before load also makes Return to Home deterministic for a
        // cold inactive Slot without clearing a warm WebView's history list.
        tabStore.updateCurrentURL(id: id, url: profile.homeURL)
        if webViewPool.contains(slotID: id) {
            webViewPool.navigate(
                slotID: id,
                to: profile.homeURL,
                allowHTTPEntryFallback: profile.homeURLSchemeWasInferred
            )
        }

        if tabStore.activeTabID == id {
            focusActiveWebViewIfAvailable()
        }
    }

    private func presentAddWebAppEditor() {
        guard panel.attachedSheet == nil else { return }
        rootView.externalControlZoneView.setAddEditorOpen(true)

        WebAppEditorController.presentAdd(
            browserProfiles: tabStore.browserProfiles,
            defaultProfileName: tabStore.defaultBrowserProfilePresentation.name,
            customProfilesSupported: webViewPool.customBrowserProfilesSupported,
            allowsWindowSizeEditing: preferencesStore.windowSizeMode == .perWebApp,
            attachedTo: panel
        ) { [weak self] value in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.rootView.externalControlZoneView.setAddEditorOpen(false)
                guard let value,
                      value.browserProfileID == nil || self.webViewPool.customBrowserProfilesSupported,
                      let added = self.tabStore.add(
                        name: value.name,
                        homeURL: value.url,
                        homeURLSchemeWasInferred: value.homeURLSchemeWasInferred,
                        renderingProfile: value.renderingProfile,
                        browserProfileID: value.browserProfileID
                      ) else {
                    return
                }

                if self.preferencesStore.windowSizeMode == .perWebApp {
                    self.applyPreferredViewport(added.renderingProfile.viewportSize)
                }
            }
        }
    }

    private func presentEditWebAppEditor(id: UUID) {
        guard panel.attachedSheet == nil,
              let profile = tabStore.profiles.first(where: { $0.id == id }) else {
            return
        }

        WebAppEditorController.presentEdit(
            profile: profile,
            allowsWindowSizeEditing: preferencesStore.windowSizeMode == .perWebApp,
            attachedTo: panel
        ) { [weak self] value in
            Task { @MainActor [weak self] in
                guard let self, let value else { return }
                let oldHomeURL = self.tabStore.profiles.first(where: { $0.id == id })?.homeURL
                guard self.tabStore.update(
                    id: id,
                    name: value.name,
                    homeURL: value.url,
                    homeURLSchemeWasInferred: value.homeURLSchemeWasInferred,
                    renderingProfile: value.renderingProfile
                ) else {
                    return
                }
                if oldHomeURL != value.url {
                    self.webViewPool.navigate(
                        slotID: id,
                        to: value.url,
                        allowHTTPEntryFallback: value.homeURLSchemeWasInferred
                    )
                }
                if self.tabStore.activeTabID == id,
                   self.preferencesStore.windowSizeMode == .perWebApp {
                    self.applyPreferredViewport(value.renderingProfile.viewportSize)
                }
            }
        }
    }

    private func presentRemoveConfirmation(id: UUID) {
        guard Self.canRemoveSlotDuringFullscreen(
            slotID: id,
            fullscreenSourceSlotID: fullscreenProfile?.id,
            sessionIsLocked: sourceHostController.isSessionLocked
        ) else {
            NSSound.beep()
            return
        }
        guard panel.attachedSheet == nil,
              let profile = tabStore.profiles.first(where: { $0.id == id }) else {
            return
        }

        WebAppEditorController.confirmRemove(profile: profile, attachedTo: panel) { [weak self] confirmed in
            Task { @MainActor [weak self] in
                guard let self, confirmed,
                      self.tabStore.remove(id: id) else { return }
                self.slotLifecycleCoordinator.remove(slotID: id)
                self.webViewPool.remove(slotID: id)
                // Pool removal already routed the bridge's final runtimeReset;
                // dropping the bookkeeping fully forgets the deleted Slot.
                self.attentionCoordinator.removeSlot(id)
            }
        }
    }

    private func changeActiveZoom(larger: Bool) {
        guard let profile = tabStore.activeProfile else { return }
        let current = profile.renderingProfile.zoom
        let target = larger
            ? ZoomSteps.nextLarger(after: current)
            : ZoomSteps.nextSmaller(before: current)
        setActiveZoom(target)
    }

    private func setActiveZoom(_ zoom: CGFloat) {
        guard let id = tabStore.activeTabID else { return }
        let normalized = ZoomSteps.nearest(to: zoom)
        guard tabStore.updateZoom(id: id, zoom: normalized) else { return }
        synchronizeTransientUIHost()
        zoomHUDView.show(zoom: normalized)
    }

    private func presentAddressBar() {
        guard let url = currentAddressURL() else { return }
        synchronizeTransientUIHost()
        let hostWindow = sourceHostController.isSessionLocked
            ? panel
            : sourceHostController.window
        hostWindow.makeKeyAndOrderFront(nil)
        addressOverlayView.present(url: url, in: hostWindow)
    }

    private func currentAddressURL() -> URL? {
        if let webURL = selectedPresentationWebView()?.url,
           WebAppURL.isSafe(webURL) {
            return webURL
        }
        guard let profile = tabStore.activeProfile else { return nil }
        if let currentURL = profile.currentURL, WebAppURL.isSafe(currentURL) {
            return currentURL
        }
        return WebAppURL.isSafe(profile.homeURL) ? profile.homeURL : nil
    }

    private func selectedPresentationWebView() -> WKWebView? {
        if sourceHostController.isSessionLocked,
           let companionWebView = sourceHostController.companionContainer.currentWebView {
            return companionWebView
        }
        return rootView.webPanelContainerView.currentWebView
    }

    static func canRemoveSlotDuringFullscreen(
        slotID: UUID,
        fullscreenSourceSlotID: UUID?,
        sessionIsLocked: Bool
    ) -> Bool {
        !sessionIsLocked || slotID != fullscreenSourceSlotID
    }

    private func commitAddress(_ rawValue: String) -> Bool {
        guard let id = tabStore.activeTabID,
              let normalized = WebAppURL.normalizedEntry(from: rawValue) else {
            NSSound.beep()
            addressOverlayView.markInvalid()
            return false
        }

        tabStore.updateCurrentURL(id: id, url: normalized.url)
        webViewPool.navigate(
            slotID: id,
            to: normalized.url,
            allowHTTPEntryFallback: normalized.schemeWasInferred
        )
        addressOverlayView.dismiss()
        focusActiveWebViewIfAvailable()
        return true
    }

    private func copyAddressToPasteboard(_ rawValue: String) -> Bool {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(value, forType: .string)
    }

    private func presentDerivedWebAppFromCurrentPage() {
        guard panel.attachedSheet == nil,
              let source = tabStore.activeProfile,
              let currentURL = currentAddressURL() else {
            return
        }

        let sourceID = source.id
        addressOverlayView.dismiss()
        WebAppEditorController.presentDerivedAdd(
            sourceProfile: source,
            currentURL: currentURL,
            attachedTo: panel
        ) { [weak self] name in
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.focusActiveWebViewIfAvailable() }
                guard let name else { return }
                _ = self.tabStore.addDerived(
                    from: sourceID,
                    name: name,
                    homeURL: currentURL
                )
            }
        }
    }

    private func handleManualResizeEnded() {
        clampPanelToConnectedScreens()
        let viewport = PanelMetrics.viewportSize(forPanelSize: panel.frame.size)

        switch preferencesStore.windowSizeMode {
        case .perWebApp:
            if let active = tabStore.activeProfile {
                let previousViewport = active.renderingProfile.viewportSize
                if !tabStore.updatePreferredViewport(
                    id: active.id,
                    size: CGSize(width: viewport.width, height: viewport.height)
                ) {
                    // The configuration save was rejected and TabStore restored
                    // its model. Restore the physical panel as part of the same
                    // transaction so UI and durable preference cannot diverge.
                    applyViewportSize(previousViewport, animated: false)
                    return
                }
            }
        case .fixed:
            // Manual resizing updates only the shared Fixed viewport. Every Web
            // App keeps its own hidden preferred size for Per Web App mode.
            preferencesStore.fixedViewportSize = viewport
        }
        persistPanelFrame()
    }

    private func applyPreferredViewport(_ viewportSize: CGSize) {
        guard preferencesStore.windowSizeMode == .perWebApp,
              hasPositionedPanel else { return }
        applyViewportSize(viewportSize, animated: true)
    }

    private func applySharedFixedViewport(_ viewportSize: CGSize, animated: Bool) {
        guard preferencesStore.windowSizeMode == .fixed,
              hasPositionedPanel else { return }
        applyViewportSize(viewportSize, animated: animated)
    }

    private func applyViewportSize(_ viewportSize: CGSize, animated: Bool) {
        let visibleFrame = panel.screen?.visibleFrame
            ?? ScreenPositioning.targetScreen()?.visibleFrame
        guard let visibleFrame else { return }

        let target = ScreenPositioning.frameFollowingPreferredViewport(
            currentFrame: panel.frame,
            preferredViewportSize: NSSize(
                width: viewportSize.width,
                height: viewportSize.height
            ),
            followPreferredSize: true,
            visibleFrame: visibleFrame
        )
        guard target != panel.frame else { return }
        panel.setFrame(target, display: true, animate: animated)
        synchronizeSourceHostFrame(display: true)
        persistPanelFrame()
    }

    private func synchronizeFixedViewportAfterPositioning() {
        guard preferencesStore.windowSizeMode == .fixed,
              hasPositionedPanel else { return }
        if preferencesStore.hasStoredFixedViewportSize {
            applySharedFixedViewport(preferencesStore.fixedViewportSize, animated: false)
        } else {
            let viewport = PanelMetrics.viewportSize(forPanelSize: panel.frame.size)
            preferencesStore.fixedViewportSize = viewport
        }
    }

    private func activateFloatTabs() {
        // This path only runs for an explicit user presentation. Current macOS
        // treats activation as contextual, while older releases require the
        // explicit override for an LSUIElement accessory application.
        _ = NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func applicationDidBecomeActive(_ notification: Notification) {
        guard needsFocusAfterApplicationActivation else {
            // App activation is only a trigger to re-evaluate the current
            // window facts. It is not itself proof that the Web presentation
            // owns interaction.
            acknowledgeActiveAttentionIfActuallyPresented()
            return
        }
        needsFocusAfterApplicationActivation = false

        // Activation can complete after the original show call. Finish through
        // the same window-owning controller instead of searching NSApp.windows
        // from a separate retry state machine.
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            Task { @MainActor [weak self] in
                self?.finishFocusAfterApplicationActivation()
            }
        }
    }

    private func finishFocusAfterApplicationActivation() {
        guard requestedVisibility, NSApp.isActive else { return }
        if sourceHostController.isSessionLocked {
            guard panel.isVisible else { return }
            panel.makeKeyAndOrderFront(nil)
            if let webView = sourceHostController.companionContainer.currentWebView {
                WebViewFocus.focus(webView, in: panel)
            }
        } else {
            panel.orderFrontRegardless()
            focusActiveWebViewIfAvailable(makeSourceWindowMain: true)
        }
        // Completes the deferred presentation half of showFloatTabs.
        acknowledgeActiveAttentionIfActuallyPresented()
    }

    @objc func windowDidBecomeKey(_ notification: Notification) {
        // This intentionally handles stale/unrelated key-window events too:
        // acknowledgement is gated by the current real WebView window facts,
        // so a Settings window or a different FloatTabs surface cannot clear
        // Ready merely by becoming key.
        acknowledgeActiveAttentionIfActuallyPresented()
    }

    private func capturePreviousApplication() {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return }
        guard frontmost.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        previousApplication = frontmost
    }

    private func positionPanelForCurrentScreens() {
        let screens = NSScreen.screens
        guard let targetScreen = ScreenPositioning.targetScreen(screens: screens) else { return }

        let targetFrame: NSRect

        if hasPositionedPanel {
            targetFrame = ScreenPositioning.clampedFrame(
                panel.frame,
                to: targetScreen.visibleFrame
            )
        } else if let restoredFrame {
            targetFrame = ScreenPositioning.restoredFrame(
                restoredFrame,
                visibleFrames: screens.map(\.visibleFrame),
                fallbackVisibleFrame: targetScreen.visibleFrame
            )
        } else {
            targetFrame = ScreenPositioning.centeredFrame(
                size: PanelMetrics.defaultPanelSize,
                in: targetScreen.visibleFrame
            )
        }

        panel.setFrame(targetFrame, display: false)
        synchronizeSourceHostFrame(display: false)
        restoredFrame = nil
        hasPositionedPanel = true
    }

    private func clampPanelToConnectedScreens() {
        let screens = NSScreen.screens
        guard let fallbackScreen = ScreenPositioning.targetScreen(screens: screens) else { return }

        let clamped = ScreenPositioning.restoredFrame(
            panel.frame,
            visibleFrames: screens.map(\.visibleFrame),
            fallbackVisibleFrame: fallbackScreen.visibleFrame
        )

        if clamped != panel.frame {
            panel.setFrame(clamped, display: true)
            synchronizeSourceHostFrame(display: true)
        }
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        guard !sourceHostController.isSessionLocked else {
            shouldClampAfterFullscreen = true
            return
        }
        clampPanelToConnectedScreens()
    }

    private func persistPanelFrame() {
        guard hasPositionedPanel else { return }
        frameStore.saveFrame(panel.frame)
    }

    func windowDidMove(_ notification: Notification) {
        synchronizeSourceHostFrame(display: false)
    }

    func windowDidResize(_ notification: Notification) {
        synchronizeSourceHostFrame(display: true)
    }

    private func synchronizeSourceHostFrame(display: Bool, animated: Bool = false) {
        sourceHostController.synchronizeFrame(with: panel, display: display, animated: animated)
    }

    private func handleSourceSessionLockChange(isLocked: Bool) {
        rootView.externalControlZoneView.setBrowserProfileAssignmentEnabled(!isLocked)
        rootView.externalControlZoneView.setBrowserProfileDuplicationEnabled(!isLocked)
        if isLocked {
            fullscreenVisibilityIntent.begin(wasVisible: requestedVisibility)
            fullscreenProfile = lastSynchronizedActiveProfile ?? tabStore.activeProfile
            if let fullscreenProfile {
                slotLifecycleCoordinator.beginFullscreenSourceVisibility(
                    profile: fullscreenProfile
                )
                // WebKit now owns the actual fullscreen presentation of this
                // Slot, so a Ready result is genuinely being shown.
                acknowledgeAttentionIfActuallyVisible(slotID: fullscreenProfile.id)
            }
            companionActiveProfile = nil
            pendingSlotSynchronization = false
            addressOverlayView.dismiss()
            synchronizeTransientUIHost()
            panel.orderOut(nil)
            rootView.removeFullscreenCompanionContainer(
                sourceHostController.companionContainer
            )
            rootView.removeFullscreenExitPlaceholder()
            updateRequestedVisibility(isPinned)
            return
        }

        if let fullscreenProfile {
            slotLifecycleCoordinator.endFullscreenSourceVisibility(
                profile: fullscreenProfile
            )
        }

        synchronizeTransientUIHost()
        synchronizePinnedPresentation()

        updateRequestedVisibility(
            fullscreenVisibilityIntent.consumeRestore(
                currentVisibility: requestedVisibility
            )
        )
        let shouldKeepShellVisible = requestedVisibility
        let shouldPauseCompanion = !shouldKeepShellVisible
        // The companion collection behavior is tied to the fullscreen Space.
        // Merely changing its flags while the panel remains ordered leaves the
        // panel represented in the Space that macOS is destroying. Re-home it
        // atomically only after WebKit has restored the real page: order out,
        // rebuild the normal hierarchy, and order front again in this same main
        // run-loop turn. The restored source page remains underneath throughout.
        if shouldKeepShellVisible {
            panel.orderOut(nil)
        }
        tearDownFullscreenCompanion(
            pauseInactiveMedia: shouldPauseCompanion,
            hidePanel: !shouldKeepShellVisible
        )
        fullscreenProfile = nil
        panel.setFullscreenCompanionPresentation(false)
        pendingSlotSynchronization = true

        if shouldClampAfterFullscreen {
            shouldClampAfterFullscreen = false
            clampPanelToConnectedScreens()
        }

        if pendingSlotSynchronization {
            synchronizeSlotState()
        }

        guard requestedVisibility else {
            sourceHostController.orderOutIfSafe()
            slotLifecycleCoordinator.setPanelVisible(
                false,
                activeProfile: tabStore.activeProfile
            )
            return
        }

        synchronizeSourceHostFrame(display: false)
        slotLifecycleCoordinator.setPanelVisible(true, activeProfile: tabStore.activeProfile)
        synchronizeSlotState()
        // The restore re-presents the shell from inside WebKit's Space
        // teardown. Arm the same workspace auto-hide grace that an explicit
        // show uses: activation notifications still describing the pre-exit
        // frontmost application must not hide the just-restored shell, and the
        // global mouse monitor can deliver clicks made on the exiting
        // fullscreen presentation after the shell is back.
        let restoreUptime = ProcessInfo.processInfo.systemUptime
        lastPresentationUptime = restoreUptime
        workspaceAutoHideSuppression.arm(atUptime: restoreUptime)
        // Re-establish the queued target display before returning Web focus.
        panel.makeKeyAndOrderFront(nil)
        focusActiveWebViewIfAvailable()
        // The restored source presentation is physically visible again.
        acknowledgeActiveAttentionIfActuallyPresented()
        fullscreenExperimentLog(
            "RESTORE_PRESENTED shell=\(panel.windowNumber) "
                + "source=\(sourceHostController.window.windowNumber) "
                + "shellScreen=\(fullscreenExperimentScreenID(panel.screen)) "
                + "sourceScreen=\(fullscreenExperimentScreenID(sourceHostController.window.screen)) "
                + "shellVisible=\(panel.isVisible) "
                + "sourceVisible=\(sourceHostController.window.isVisible)"
        )
    }

    /// A last-resort recovery used only after WebKit has publicly left
    /// fullscreen but failed to restore its source view for ten seconds. The
    /// persisted Slot remains intact; only its transient WKWebView is rebuilt.
    private func rebuildFullscreenSourceAfterRestoreTimeout() {
        guard let sourceID = fullscreenProfile?.id else { return }
        slotLifecycleCoordinator.remove(slotID: sourceID)
        webViewPool.release(slotID: sourceID)
        if lastSynchronizedActiveID == sourceID {
            lastSynchronizedActiveID = nil
            lastSynchronizedActiveProfile = nil
        }
        pendingSlotSynchronization = true
    }

    private func handleSourceSessionStateChange(_ state: FullscreenSourceSessionState) {
        fullscreenExperimentLog(
            "SESSION state=\(state.rawValue) requested=\(requestedVisibility) "
                + "shellVisible=\(panel.isVisible) "
                + "shellScreen=\(fullscreenExperimentScreenID(panel.screen))"
        )
        switch state {
        case .fullscreen:
            showFullscreenCompanionIfReady()
        case .exiting, .restoring:
            // Keep the requested shell in place while WebKit returns the
            // fullscreen WebView to its source hierarchy. Ordering it out here
            // created a visible empty frame before the normal page was shown.
            if !requestedVisibility {
                panel.orderOut(nil)
            }
        case .idle, .entering:
            break
        }
    }

    private func showFullscreenCompanionIfReady() {
        guard requestedVisibility,
              sourceHostController.sessionState == .fullscreen else {
            return
        }

        capturePreviousApplication()
        panel.orderOut(nil)
        rootView.removeFullscreenCompanionContainer(
            sourceHostController.companionContainer
        )
        positionPanelForCurrentScreens()
        panel.setFullscreenCompanionPresentation(true)
        rootView.companionRailFoldControlView.isHidden = false
        synchronizeFullscreenCompanionSlotState()
        needsFocusAfterApplicationActivation = !NSApp.isActive
        panel.orderFrontRegardless()
        activateFloatTabs()
        panel.makeKeyAndOrderFront(nil)

        if let webView = sourceHostController.companionContainer.currentWebView {
            WebViewFocus.focus(webView, in: panel)
        }
        if NSApp.isActive {
            needsFocusAfterApplicationActivation = false
        }
        // The companion shell has actually been ordered visible, so the
        // presented companion Slot's Ready output can be acknowledged.
        if let companionSlotID = companionActiveProfile?.id {
            acknowledgeAttentionIfActuallyVisible(slotID: companionSlotID)
        }
    }

    private func synchronizeFullscreenCompanionSlotState() {
        let orderedProfiles = tabStore.orderedProfiles
        rootView.externalControlZoneView.apply(
            profiles: orderedProfiles,
            activeTabID: tabStore.activeTabID
        )
        synchronizeAttentionIndicators()
        synchronizeResidentIndicators()

        guard let activeProfile = tabStore.activeProfile else {
            deactivateCompanionProfile(pauseInactiveMedia: true)
            webFocusRouter.setCurrentWebView(nil)
            sourceHostController.companionContainer.showEmptyState()
            rootView.removeFullscreenCompanionContainer(
                sourceHostController.companionContainer
            )
            rootView.removeFullscreenExitPlaceholder()
            onSelectedSlotPresentationChange?(nil, nil)
            return
        }

        onSelectedSlotPresentationChange?(
            activeProfile.name,
            faviconURL(for: activeProfile)
        )

        // Selecting the fullscreen Slot only selects its rail identity. Its
        // WKWebView must remain exclusively owned by WebKit until restore.
        guard activeProfile.id != fullscreenProfile?.id else {
            deactivateCompanionProfile(pauseInactiveMedia: true)
            webFocusRouter.setCurrentWebView(nil)
            sourceHostController.companionContainer.showEmptyState()
            rootView.removeFullscreenCompanionContainer(
                sourceHostController.companionContainer
            )
            rootView.installFullscreenExitPlaceholder()
            return
        }

        if companionActiveProfile?.id != activeProfile.id {
            deactivateCompanionProfile(pauseInactiveMedia: true)
            if preferencesStore.followPreferredSize {
                applyPreferredViewport(activeProfile.renderingProfile.viewportSize)
            }
        }

        let webView: WKWebView
        do {
            webView = try webViewPool.webView(for: activeProfile)
        } catch {
            webFocusRouter.setCurrentWebView(nil)
            if let profileName = Self.unsupportedBrowserProfileName(
                for: activeProfile,
                error: error,
                browserProfiles: tabStore.browserProfiles
            ) {
                rootView.installFullscreenCompanionContainer(
                    sourceHostController.companionContainer
                )
                sourceHostController.companionContainer.showUnsupportedBrowserProfile(
                    profileName: profileName,
                    defaultProfileName: tabStore.defaultBrowserProfilePresentation.name
                )
            } else {
                sourceHostController.companionContainer.showEmptyState()
            }
            companionActiveProfile = nil
            synchronizeResidentIndicators()
            return
        }
        rootView.installFullscreenCompanionContainer(
            sourceHostController.companionContainer
        )
        sourceHostController.companionContainer.show(
            webView: webView,
            slotID: activeProfile.id,
            residencyPolicy: activeProfile.residencyPolicy
        )
        webFocusRouter.setCurrentWebView(webView)
        slotLifecycleCoordinator.beginSupplementalVisibility(profile: activeProfile)
        WebViewFactory.configureHiddenScrollers(in: webView)
        companionActiveProfile = activeProfile

        guard requestedVisibility,
              sourceHostController.sessionState == .fullscreen else { return }
        WebViewFocus.focus(webView, in: panel)
        // Selecting a new companion Slot during an already-visible companion
        // presentation acknowledges it once it is actually presented.
        acknowledgeAttentionIfActuallyVisible(slotID: activeProfile.id)
    }

    private func hideFullscreenCompanion(pauseInactiveMedia: Bool) {
        panel.orderOut(nil)
        if pauseInactiveMedia,
           let profile = companionActiveProfile,
           profile.backgroundMediaPolicy == .pauseWhenInactive {
            webViewPool.pauseMediaPlayback(slotID: profile.id)
        }
    }

    private func tearDownFullscreenCompanion(
        pauseInactiveMedia: Bool,
        hidePanel: Bool
    ) {
        rootView.companionRailFoldControlView.isHidden = true
        if hidePanel {
            hideFullscreenCompanion(pauseInactiveMedia: pauseInactiveMedia)
        }
        deactivateCompanionProfile(pauseInactiveMedia: pauseInactiveMedia)
        sourceHostController.companionContainer.showEmptyState()
        rootView.removeFullscreenCompanionContainer(
            sourceHostController.companionContainer
        )
        rootView.removeFullscreenExitPlaceholder()
    }

    private func deactivateCompanionProfile(pauseInactiveMedia: Bool) {
        guard let profile = companionActiveProfile else { return }
        if pauseInactiveMedia,
           profile.backgroundMediaPolicy == .pauseWhenInactive {
            webViewPool.pauseMediaPlayback(slotID: profile.id)
        }
        sourceHostController.companionContainer.deactivate(
            slotID: profile.id,
            residencyPolicy: profile.residencyPolicy
        )
        slotLifecycleCoordinator.endSupplementalVisibility(
            profile: profile,
            prepareAsInactive: pauseInactiveMedia
        )
        companionActiveProfile = nil
    }
}

@MainActor
final class AddressOverlayView: NSVisualEffectView, NSTextFieldDelegate {
    var onCommit: ((String) -> Bool)?
    var onCopy: ((String) -> Bool)?
    var onCreateWebApp: (() -> Void)?
    var onDismiss: (() -> Void)?

    let field = NSTextField()
    private let copyButton = NSButton()
    private let createButton = NSButton(title: "New App", target: nil, action: nil)
    private var copyFeedbackWorkItem: DispatchWorkItem?
    private(set) var isPresented = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true

        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = .systemFont(ofSize: 14, weight: .medium)
        field.placeholderString = "https://example.com"
        field.focusRingType = .none
        field.delegate = self

        copyButton.image = NSImage(
            systemSymbolName: "doc.on.doc",
            accessibilityDescription: "Copy URL"
        )
        copyButton.toolTip = "Copy URL"
        copyButton.bezelStyle = .inline
        copyButton.isBordered = false
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.target = self
        copyButton.action = #selector(copyPressed(_:))

        createButton.toolTip = "Create a new Web App from the current page"
        createButton.bezelStyle = .rounded
        createButton.controlSize = .small
        createButton.translatesAutoresizingMaskIntoConstraints = false
        createButton.target = self
        createButton.action = #selector(createPressed(_:))

        addSubview(field)
        addSubview(copyButton)
        addSubview(createButton)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),

            copyButton.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: 8),
            copyButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            copyButton.widthAnchor.constraint(equalToConstant: 26),
            copyButton.heightAnchor.constraint(equalToConstant: 26),

            createButton.leadingAnchor.constraint(equalTo: copyButton.trailingAnchor, constant: 6),
            createButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            createButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            createButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 66),
        ])

        isHidden = true
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(url: URL, in window: NSWindow) {
        copyFeedbackWorkItem?.cancel()
        restoreCopyIcon()
        field.textColor = .labelColor
        field.stringValue = url.absoluteString
        isHidden = false
        isPresented = true
        window.makeFirstResponder(field)
        field.selectText(nil)
    }

    func dismiss() {
        copyFeedbackWorkItem?.cancel()
        restoreCopyIcon()
        isHidden = true
        isPresented = false
        field.textColor = .labelColor
    }

    func markInvalid() {
        field.textColor = .systemRed
        field.selectText(nil)
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        let commandName = NSStringFromSelector(commandSelector)
        if commandSelector == #selector(NSResponder.insertNewline(_:))
            || commandName == "insertNewlineIgnoringFieldEditor:" {
            _ = onCommit?(field.stringValue)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            dismiss()
            onDismiss?()
            return true
        }
        return false
    }

    @objc private func copyPressed(_ sender: NSButton) {
        guard onCopy?(field.stringValue) == true else { return }
        copyFeedbackWorkItem?.cancel()
        copyButton.image = NSImage(
            systemSymbolName: "checkmark",
            accessibilityDescription: "Copied"
        )
        let workItem = DispatchWorkItem { [weak self] in
            self?.restoreCopyIcon()
        }
        copyFeedbackWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }

    @objc private func createPressed(_ sender: NSButton) {
        onCreateWebApp?()
    }

    private func restoreCopyIcon() {
        copyButton.image = NSImage(
            systemSymbolName: "doc.on.doc",
            accessibilityDescription: "Copy URL"
        )
    }
}

@MainActor
final class ZoomHUDView: NSView {
    private let label = NSTextField(labelWithString: "100%")
    private var hideWorkItem: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        isHidden = true
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(zoom: CGFloat) {
        hideWorkItem?.cancel()
        label.stringValue = ZoomSteps.percentageText(for: zoom)
        isHidden = false

        let item = DispatchWorkItem { [weak self] in
            self?.isHidden = true
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85, execute: item)
    }
}
