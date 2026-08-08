import AppKit
import WebKit

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let panel: FloatingPanel
    private let rootView: PanelRootView
    private let tabStore: TabStore
    private let webViewPool: WebViewPool
    private let frameStore: PanelFrameStore

    private var moveHoverController: PanelMoveHoverController?
    private var previousApplication: NSRunningApplication?
    private var restoredFrame: NSRect?
    private var hasPositionedPanel = false

    var isVisible: Bool {
        panel.isVisible
    }

    init(
        tabStore: TabStore,
        webViewPool: WebViewPool,
        frameStore: PanelFrameStore = PanelFrameStore()
    ) {
        self.tabStore = tabStore
        self.webViewPool = webViewPool
        self.frameStore = frameStore
        restoredFrame = frameStore.loadFrame()

        let initialFrame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        panel = FloatingPanel(contentRect: initialFrame)
        rootView = PanelRootView()

        super.init()

        panel.delegate = self
        panel.contentView = rootView

        // The animated color outline is the only persistent shell outline.
        // Remove the older gray structural border and halo/shadow completely.
        rootView.webPanelContainerView.layer?.borderWidth = 0
        rootView.webPanelContainerView.layer?.shadowOpacity = 0
        rootView.webPanelContainerView.layer?.shadowRadius = 0
        rootView.webPanelContainerView.layer?.shadowOffset = .zero

        // Tracking areas with .activeAlways continue to report hover while some
        // other application is active, so the four-way move cursor is visible
        // before the first click instead of requiring FloatTabs activation.
        moveHoverController = PanelMoveHoverController(view: rootView.perimeterDragView)

        rootView.onResizeEnded = { [weak self] in
            self?.clampPanelToConnectedScreens()
            self?.persistPanelFrame()
        }
        configureSlotInteractions()

        tabStore.onChange = { [weak self] in
            self?.synchronizeSlotState()
        }
        synchronizeSlotState()
    }

    func showFloatTabs() {
        capturePreviousApplication()
        positionPanelForCurrentScreens()
        synchronizeSlotState()
        activateFloatTabs()

        panel.makeKeyAndOrderFront(nil)
        focusActiveWebViewIfAvailable()
    }

    func hideFloatTabs() {
        persistPanelFrame()
        panel.orderOut(nil)

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
        }
    }

    private func configureSlotInteractions() {
        let rail = rootView.externalControlZoneView

        rail.onSelect = { [weak self] id in
            _ = self?.tabStore.select(id: id)
        }
        rail.onAdd = { [weak self] in
            self?.presentAddWebAppEditor()
        }
        rail.onEdit = { [weak self] id in
            self?.presentEditWebAppEditor(id: id)
        }
        rail.onRename = { [weak self] id in
            self?.presentRenameEditor(id: id)
        }
        rail.onRemove = { [weak self] id in
            self?.presentRemoveConfirmation(id: id)
        }
        rail.onReorder = { [weak self] id, destination in
            _ = self?.tabStore.move(id: id, toIndex: destination)
        }
    }

    private func synchronizeSlotState() {
        let orderedProfiles = tabStore.orderedProfiles
        rootView.externalControlZoneView.apply(
            profiles: orderedProfiles,
            activeTabID: tabStore.activeTabID
        )

        guard let activeProfile = tabStore.activeProfile else {
            rootView.webPanelContainerView.showEmptyState()
            return
        }

        let webView = webViewPool.webView(for: activeProfile)
        rootView.webPanelContainerView.show(webView: webView)
        WebViewFactory.configureHiddenScrollers(in: webView)

        if panel.isKeyWindow {
            _ = panel.makeFirstResponder(webView)
        }
    }

    private func focusActiveWebViewIfAvailable() {
        guard let webView = rootView.webPanelContainerView.currentWebView else { return }
        _ = panel.makeFirstResponder(webView)
    }

    private func presentAddWebAppEditor() {
        guard panel.attachedSheet == nil else { return }
        rootView.externalControlZoneView.setAddEditorOpen(true)

        WebAppEditorController.presentAdd(attachedTo: panel) { [weak self] value in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.rootView.externalControlZoneView.setAddEditorOpen(false)
                guard let value else { return }
                _ = self.tabStore.add(name: value.name, homeURL: value.url)
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
                guard self.tabStore.update(id: id, name: value.name, homeURL: value.url) else {
                    return
                }
                if oldHomeURL != value.url {
                    self.webViewPool.navigate(slotID: id, to: value.url)
                }
            }
        }
    }

    private func presentRenameEditor(id: UUID) {
        guard panel.attachedSheet == nil,
              let profile = tabStore.profiles.first(where: { $0.id == id }) else {
            return
        }

        WebAppEditorController.presentRename(profile: profile, attachedTo: panel) { [weak self] name in
            Task { @MainActor [weak self] in
                guard let self, let name else { return }
                _ = self.tabStore.rename(id: id, name: name)
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
                self.webViewPool.remove(slotID: id)
            }
        }
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
