import AppKit
import WebKit

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private static let followPreferredSizeKey = "FloatTabs.followTabPreferredSize"

    private let panel: FloatingPanel
    private let rootView: PanelRootView
    private let tabStore: TabStore
    private let webViewPool: WebViewPool
    private let frameStore: PanelFrameStore
    private let quickURLOverlayView = QuickURLOverlayView()
    private let zoomHUDView = ZoomHUDView()
    private lazy var slotLifecycleCoordinator = SlotLifecycleCoordinator(
        webViewPool: webViewPool,
        container: rootView.webPanelContainerView
    )

    private var moveHoverController: PanelMoveHoverController?
    private var previousApplication: NSRunningApplication?
    private var restoredFrame: NSRect?
    private var hasPositionedPanel = false
    private var lastSynchronizedActiveID: UUID?
    private var lastSynchronizedActiveProfile: WebAppProfile?
    private var followPreferredSize: Bool
    private(set) var isPinned = false
    private var externalMouseMonitor: Any?

    var isVisible: Bool {
        panel.isVisible
    }

    var selectedSlotName: String? {
        tabStore.activeProfile?.name
    }

    var onSelectedSlotNameChange: ((String?) -> Void)?

    init(
        tabStore: TabStore,
        webViewPool: WebViewPool,
        frameStore: PanelFrameStore = PanelFrameStore()
    ) {
        self.tabStore = tabStore
        self.webViewPool = webViewPool
        self.frameStore = frameStore
        restoredFrame = frameStore.loadFrame()
        if UserDefaults.standard.object(forKey: Self.followPreferredSizeKey) == nil {
            followPreferredSize = true
        } else {
            followPreferredSize = UserDefaults.standard.bool(forKey: Self.followPreferredSizeKey)
        }

        let initialFrame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        panel = FloatingPanel(contentRect: initialFrame)
        rootView = PanelRootView()

        super.init()

        panel.delegate = self
        panel.contentView = rootView

        // The animated color outline is the only persistent shell outline.
        rootView.webPanelContainerView.layer?.borderWidth = 0
        rootView.webPanelContainerView.layer?.shadowOpacity = 0
        rootView.webPanelContainerView.layer?.shadowRadius = 0
        rootView.webPanelContainerView.layer?.shadowOffset = .zero

        moveHoverController = PanelMoveHoverController(view: rootView.perimeterDragView)
        configureTransientUI()

        rootView.onResizeEnded = { [weak self] in
            self?.handleManualResizeEnded()
        }
        configureSlotInteractions()
        rootView.externalControlZoneView.setPinned(isPinned)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidActivateApplication(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        externalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleExternalMouseDown()
            }
        }

        webViewPool.onResidentSetChange = { [weak self] in
        self?.synchronizeResidentIndicators()
    }
    tabStore.onChange = { [weak self] in
        self?.synchronizeSlotState()
    }
    synchronizeSlotState()

    }

    func showFloatTabs() {
        capturePreviousApplication()
        positionPanelForCurrentScreens()
        slotLifecycleCoordinator.setPanelVisible(true, activeProfile: tabStore.activeProfile)
        synchronizeSlotState()
        activateFloatTabs()

        panel.makeKeyAndOrderFront(nil)
        focusActiveWebViewIfAvailable()
    }

    func hideFloatTabs() {
        quickURLOverlayView.dismiss()
        persistPanelFrame()
        panel.orderOut(nil)
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

    static func shouldAutoHide(panelIsVisible: Bool, isPinned: Bool) -> Bool {
        panelIsVisible && !isPinned
    }

    private func togglePinnedState() {
        isPinned.toggle()
        rootView.externalControlZoneView.setPinned(isPinned)
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

    private func handleExternalMouseDown() {
        guard Self.shouldAutoHideForExternalMouseDown(
            panelIsVisible: panel.isVisible,
            isPinned: isPinned
        ) else {
            return
        }
        autoHideAfterApplicationDeactivation()
    }

    @objc private func workspaceDidActivateApplication(_ notification: Notification) {
        guard let activatedApplication = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
              Self.shouldAutoHideForActivatedApplication(
                panelIsVisible: panel.isVisible,
                isPinned: isPinned,
                activatedProcessIdentifier: activatedApplication.processIdentifier,
                ownProcessIdentifier: ProcessInfo.processInfo.processIdentifier
              ) else {
            return
        }
        autoHideAfterApplicationDeactivation()
    }

    private func autoHideAfterApplicationDeactivation() {
        // The user has already selected another application. Unlike the explicit
        // global-toggle hide path, do not reactivate `previousApplication` here:
        // doing so would steal focus from the application the user just chose.
        quickURLOverlayView.dismiss()
        persistPanelFrame()
        panel.orderOut(nil)
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
        "pinned": isPinned,
        "profiles": profiles,
        "resident_slot_count": webViewPool.count,
        "resident_slot_ids": webViewPool.residentSlotIDs.map(\.uuidString).sorted(),
        "pending_cold_release_count": slotLifecycleCoordinator.pendingColdReleaseCount,
        "pending_warm_release_count": slotLifecycleCoordinator.pendingWarmReleaseCount,
        "media_protected_slot_ids": slotLifecycleCoordinator.mediaProtectedIDs.map(\.uuidString).sorted(),
        "hidden_active_grace_pending": slotLifecycleCoordinator.isHiddenActiveGracePending,
    ]
    snapshot["active_slot_id"] = tabStore.activeTabID?.uuidString ?? NSNull()

        return snapshot
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

        case .quickURL:
            presentQuickURL()

        case .returnHome:
            returnActiveSlotHome()

        case .togglePin:
            togglePinnedState()
        }
    }

    private func configureTransientUI() {
        quickURLOverlayView.translatesAutoresizingMaskIntoConstraints = false
        zoomHUDView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(quickURLOverlayView)
        rootView.addSubview(zoomHUDView)

        NSLayoutConstraint.activate([
            quickURLOverlayView.leadingAnchor.constraint(
                equalTo: rootView.webPanelContainerView.leadingAnchor,
                constant: 22
            ),
            quickURLOverlayView.trailingAnchor.constraint(
                equalTo: rootView.webPanelContainerView.trailingAnchor,
                constant: -22
            ),
            quickURLOverlayView.topAnchor.constraint(
                equalTo: rootView.webPanelContainerView.topAnchor,
                constant: 22
            ),
            quickURLOverlayView.heightAnchor.constraint(equalToConstant: 52),

            zoomHUDView.centerXAnchor.constraint(
                equalTo: rootView.webPanelContainerView.centerXAnchor
            ),
            zoomHUDView.bottomAnchor.constraint(
                equalTo: rootView.webPanelContainerView.bottomAnchor,
                constant: -28
            ),
            zoomHUDView.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),
            zoomHUDView.heightAnchor.constraint(equalToConstant: 34),
        ])

        quickURLOverlayView.onCommit = { [weak self] rawValue in
            self?.commitQuickURL(rawValue) ?? false
        }
        quickURLOverlayView.onDismiss = { [weak self] in
            self?.focusActiveWebViewIfAvailable()
        }
    }

    private func configureSlotInteractions() {
        let rail = rootView.externalControlZoneView

        rail.onSelect = { [weak self] id in
            _ = self?.tabStore.select(id: id)
        }
        rail.onReturnHome = { [weak self] id in
            self?.returnSlotHome(id: id)
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
                  let profile = self.tabStore.profiles.first(where: { $0.id == id }),
                  let size = preset.size else { return }
            _ = self.tabStore.updateRenderingProfile(
                id: id,
                renderingProfile: profile.renderingProfile.settingSimplePreset(preset)
            )
            if self.tabStore.activeTabID == id {
                self.applyPreferredViewport(size)
            }
        }
        rail.onSetZoom = { [weak self] id, zoom in
            _ = self?.tabStore.updateZoom(id: id, zoom: zoom)
        }
        rail.onSetResidency = { [weak self] id, policy in
            _ = self?.tabStore.updateResourcePolicy(id: id, residencyPolicy: policy)
        }
        rail.onSetBackgroundMedia = { [weak self] id, policy in
            _ = self?.tabStore.updateResourcePolicy(id: id, backgroundMediaPolicy: policy)
        }
        rail.onReorder = { [weak self] id, destination in
            _ = self?.tabStore.move(id: id, toIndex: destination)
        }
        rail.onCurrentControls = { [weak self] in
            self?.presentCurrentWebAppControls()
        }
        rail.onTogglePin = { [weak self] in
            self?.togglePinnedState()
        }
    }

    private func synchronizeSlotState() {
        let orderedProfiles = tabStore.orderedProfiles
        rootView.externalControlZoneView.apply(
        profiles: orderedProfiles,
        activeTabID: tabStore.activeTabID
    )
    synchronizeResidentIndicators()
    slotLifecycleCoordinator.reconcile(profiles: orderedProfiles)


        guard let activeProfile = tabStore.activeProfile else {
            if let previous = lastSynchronizedActiveProfile {
                slotLifecycleCoordinator.deactivate(profile: previous)
            }
            lastSynchronizedActiveID = nil
        lastSynchronizedActiveProfile = nil
        rootView.webPanelContainerView.showEmptyState()
        synchronizeResidentIndicators()
        onSelectedSlotNameChange?(nil)
        return

        }

        let activeChanged = lastSynchronizedActiveID != activeProfile.id
        if activeChanged,
           let previous = lastSynchronizedActiveProfile,
           previous.id != activeProfile.id {
            slotLifecycleCoordinator.deactivate(profile: previous)
        }

        if activeChanged, hasPositionedPanel, followPreferredSize {
            applyPreferredViewport(activeProfile.renderingProfile.viewportSize)
        }

        let webView = webViewPool.webView(for: activeProfile)
        rootView.webPanelContainerView.show(
            webView: webView,
            slotID: activeProfile.id,
            residencyPolicy: activeProfile.residencyPolicy
        )
        slotLifecycleCoordinator.activate(profile: activeProfile)
        WebViewFactory.configureHiddenScrollers(in: webView)
        lastSynchronizedActiveID = activeProfile.id
        lastSynchronizedActiveProfile = activeProfile
        synchronizeResidentIndicators()
        onSelectedSlotNameChange?(activeProfile.name)

        if panel.isKeyWindow {
            _ = panel.makeFirstResponder(webView)
        }
    }

    private func synchronizeResidentIndicators() {
        rootView.externalControlZoneView.setResidentSlotIDs(webViewPool.residentSlotIDs)
    }

    private func focusActiveWebViewIfAvailable() {
        guard !quickURLOverlayView.isPresented,
              let webView = rootView.webPanelContainerView.currentWebView else { return }
        _ = panel.makeFirstResponder(webView)
    }

    private func returnActiveSlotHome() {
        guard let id = tabStore.activeTabID else { return }
        returnSlotHome(id: id)
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
            webViewPool.navigate(slotID: id, to: profile.homeURL)
        }

        if tabStore.activeTabID == id {
            focusActiveWebViewIfAvailable()
        }
    }

    private func presentAddWebAppEditor() {
        guard panel.attachedSheet == nil else { return }
        rootView.externalControlZoneView.setAddEditorOpen(true)

        WebAppEditorController.presentAdd(attachedTo: panel) { [weak self] value in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.rootView.externalControlZoneView.setAddEditorOpen(false)
                guard let value,
                      let added = self.tabStore.add(
                        name: value.name,
                        homeURL: value.url,
                        renderingProfile: value.renderingProfile
                      ) else {
                    return
                }

                // The user explicitly chose this new Slot's size. Apply it now;
                // the follow preference only governs later automatic Slot switches.
                self.applyPreferredViewport(added.renderingProfile.viewportSize)
            }
        }
    }

    private func presentEditWebAppEditor(id: UUID) {
        guard panel.attachedSheet == nil,
              let profile = tabStore.profiles.first(where: { $0.id == id }) else {
            return
        }

        WebAppEditorController.presentEdit(profile: profile, attachedTo: panel) { [weak self] value in
            Task { @MainActor [weak self] in
                guard let self, let value else { return }
                let oldHomeURL = self.tabStore.profiles.first(where: { $0.id == id })?.homeURL
                guard self.tabStore.update(
                    id: id,
                    name: value.name,
                    homeURL: value.url,
                    renderingProfile: value.renderingProfile
                ) else {
                    return
                }
                if oldHomeURL != value.url {
                    self.webViewPool.navigate(slotID: id, to: value.url)
                }
                if self.tabStore.activeTabID == id {
                    // Editing the current Slot is an explicit size request and
                    // must not depend on the automatic switch-follow preference.
                    self.applyPreferredViewport(value.renderingProfile.viewportSize)
                }
            }
        }
    }

    private func presentCurrentWebAppControls() {
        guard panel.attachedSheet == nil,
              let profile = tabStore.activeProfile else { return }

        WebAppEditorController.presentCurrentControls(
            profile: profile,
            followPreferredSize: followPreferredSize,
            attachedTo: panel
        ) { [weak self] value in
            Task { @MainActor [weak self] in
                guard let self, let value else { return }
                self.followPreferredSize = value.followPreferredSize
                UserDefaults.standard.set(
                    value.followPreferredSize,
                    forKey: Self.followPreferredSizeKey
                )
                _ = self.tabStore.updateRenderingProfile(
                    id: profile.id,
                    renderingProfile: value.renderingProfile
                )

                // Applying settings to the current Slot is explicit user intent.
                // `followPreferredSize` only controls automatic resize on Slot switch.
                self.applyPreferredViewport(value.renderingProfile.viewportSize)
            }
        }
    }

    private func presentRemoveConfirmation(id: UUID) {
        guard panel.attachedSheet == nil,
              let profile = tabStore.profiles.first(where: { $0.id == id }) else {
            return
        }

        WebAppEditorController.confirmRemove(profile: profile, attachedTo: panel) { [weak self] confirmed in
            Task { @MainActor [weak self] in
                guard let self, confirmed else { return }
                _ = self.tabStore.remove(id: id)
                self.slotLifecycleCoordinator.remove(slotID: id)
                self.webViewPool.remove(slotID: id)
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
        zoomHUDView.show(zoom: normalized)
    }

    private func presentQuickURL() {
        guard let profile = tabStore.activeProfile else { return }
        let url = profile.currentURL ?? profile.homeURL
        quickURLOverlayView.present(url: url, in: panel)
    }

    private func commitQuickURL(_ rawValue: String) -> Bool {
        guard let id = tabStore.activeTabID,
              let url = WebAppURL.normalized(from: rawValue) else {
            NSSound.beep()
            quickURLOverlayView.markInvalid()
            return false
        }

        tabStore.updateCurrentURL(id: id, url: url)
        webViewPool.navigate(slotID: id, to: url)
        quickURLOverlayView.dismiss()
        focusActiveWebViewIfAvailable()
        return true
    }

    private func handleManualResizeEnded() {
        clampPanelToConnectedScreens()
        let viewport = PanelMetrics.viewportSize(forPanelSize: panel.frame.size)
        if let id = tabStore.activeTabID {
            _ = tabStore.updatePreferredViewport(
                id: id,
                size: CGSize(width: viewport.width, height: viewport.height)
            )
        }
        persistPanelFrame()
    }

    private func applyPreferredViewport(_ viewportSize: CGSize) {
        guard hasPositionedPanel else { return }
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
        panel.setFrame(target, display: true, animate: true)
        persistPanelFrame()
    }

    private func activateFloatTabs() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            _ = NSRunningApplication.current.activate(options: [])
        }
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
        }
    }

    private func persistPanelFrame() {
        guard hasPositionedPanel else { return }
        frameStore.saveFrame(panel.frame)
    }
}

@MainActor
final class QuickURLOverlayView: NSVisualEffectView {
    var onCommit: ((String) -> Bool)?
    var onDismiss: (() -> Void)?

    private let field = QuickURLTextField()
    private let icon = NSImageView()
    private(set) var isPresented = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true

        icon.image = NSImage(systemSymbolName: "link", accessibilityDescription: "URL")
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = .systemFont(ofSize: 14, weight: .medium)
        field.placeholderString = "https://example.com"
        field.focusRingType = .none

        addSubview(icon)
        addSubview(field)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),
            field.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        field.onCommit = { [weak self] value in
            _ = self?.onCommit?(value)
        }
        field.onCancel = { [weak self] in
            self?.dismiss()
            self?.onDismiss?()
        }
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
        field.textColor = .labelColor
        field.stringValue = url.absoluteString
        isHidden = false
        isPresented = true
        window.makeFirstResponder(field)
        field.selectText(nil)
    }

    func dismiss() {
        isHidden = true
        isPresented = false
        field.textColor = .labelColor
    }

    func markInvalid() {
        field.textColor = .systemRed
        field.selectText(nil)
    }
}

@MainActor
private final class QuickURLTextField: NSTextField {
    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            onCommit?(stringValue)
        case 53:
            onCancel?()
        default:
            super.keyDown(with: event)
        }
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

@MainActor
final class PanelMoveHoverController: NSResponder {
    static let trackingOptions: NSTrackingArea.Options = [
        .mouseEnteredAndExited,
        .mouseMoved,
        .activeAlways,
        .inVisibleRect,
    ]

    private weak var view: PanelPerimeterDragView?
    private var trackingArea: NSTrackingArea?
    private var moveCursorIsPushed = false

    init(view: PanelPerimeterDragView) {
        self.view = view
        super.init()

        let area = NSTrackingArea(
            rect: .zero,
            options: Self.trackingOptions,
            owner: self,
            userInfo: nil
        )
        view.addTrackingArea(area)
        trackingArea = area
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if moveCursorIsPushed {
            NSCursor.pop()
        }
        if let view, let trackingArea {
            view.removeTrackingArea(trackingArea)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        updateCursor(for: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(for: event)
    }

    override func mouseExited(with event: NSEvent) {
        restorePreviousCursorIfNeeded()
    }

    static func isDraggable(point: NSPoint, in bounds: NSRect) -> Bool {
        PanelPerimeterDragView.dragRects(in: bounds).contains(where: { $0.contains(point) })
    }

    private func updateCursor(for event: NSEvent) {
        guard let view else {
            restorePreviousCursorIfNeeded()
            return
        }

        let point = view.convert(event.locationInWindow, from: nil)
        let draggable = Self.isDraggable(point: point, in: view.bounds)

        if draggable, !moveCursorIsPushed {
            PanelMoveCursor.cursor.push()
            moveCursorIsPushed = true
        } else if !draggable {
            restorePreviousCursorIfNeeded()
        }
    }

    private func restorePreviousCursorIfNeeded() {
        guard moveCursorIsPushed else { return }
        NSCursor.pop()
        moveCursorIsPushed = false
    }
}
