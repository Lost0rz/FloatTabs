import AppKit
import CoreImage
import KeyboardShortcuts
import QuartzCore

struct BrowserProfileMenuOption: Equatable {
    let id: UUID?
    let name: String
    let color: BrowserProfileColor
    let isEnabled: Bool

    init(
        id: UUID?,
        name: String,
        color: BrowserProfileColor = .default,
        isEnabled: Bool
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.isEnabled = isEnabled
    }

    static func defaultProfile(
        name: String = "Default",
        color: BrowserProfileColor = .default
    ) -> BrowserProfileMenuOption {
        BrowserProfileMenuOption(
            id: nil,
            name: name,
            color: color,
            isEnabled: true
        )
    }
}

struct ExternalTabMetrics {
    static let tabHeight: CGFloat = 32
    static let tabRadius: CGFloat = 8
    static let collapsedWidth: CGFloat = 40
    static let hoverWidth: CGFloat = 76
    static let activeWidth: CGFloat = 40
    static let activeHoverWidth: CGFloat = 76
    static let topOffset: CGFloat = 23
    static let tabGap: CGFloat = 4

    /// One clock for every surface that must move together when the rail
    /// folds: the rail's alpha fade, the shell's zone-width constraint, and
    /// the separately hosted source window frame.
    static let railFoldAnimationDuration: TimeInterval = 0.22
    static let addGap: CGFloat = 8

    // Add / Settings / Pin are members of the same rail, not separate
    // floating buttons. Keep their resting and hover geometry identical to tabs.
    static let addHeight: CGFloat = tabHeight
    static let addNormalWidth: CGFloat = collapsedWidth
    static let addHoverWidth: CGFloat = hoverWidth
    static let addOpenWidth: CGFloat = hoverWidth

    static let systemControlHeight: CGFloat = tabHeight
    static let systemControlNormalWidth: CGFloat = collapsedWidth
    static let systemControlHoverWidth: CGFloat = hoverWidth
    static let systemControlBottomOffset: CGFloat = 18
    static let systemControlGap: CGFloat = 4

    /// Dock-like magnification is proximity driven instead of a binary hover.
    /// At one row away the neighboring tab still grows noticeably; the effect
    /// then falls to zero before reaching the second distant row.
    static let dockInfluenceRadius: CGFloat = 82
    static let dockMotionDuration: TimeInterval = 0.085
    static let dockSettleDuration: TimeInterval = 0.16

    static func dockInfluence(forDistance distance: CGFloat) -> CGFloat {
        guard dockInfluenceRadius > 0 else { return 0 }
        let normalized = min(max(abs(distance) / dockInfluenceRadius, 0), 1)
        guard normalized < 1 else { return 0 }
        return (1 + CGFloat(cos(Double.pi * Double(normalized)))) / 2
    }

    static func width(isActive: Bool, dockInfluence: CGFloat) -> CGFloat {
        let influence = min(max(dockInfluence, 0), 1)
        let resting = isActive ? activeWidth : collapsedWidth
        let magnified = isActive ? activeHoverWidth : hoverWidth
        return resting + (magnified - resting) * influence
    }

    static func addWidth(isEditorOpen: Bool, dockInfluence: CGFloat) -> CGFloat {
        let influence = min(max(dockInfluence, 0), 1)
        let magnified = addNormalWidth + (addHoverWidth - addNormalWidth) * influence
        return isEditorOpen ? max(addOpenWidth, magnified) : magnified
    }

    static func systemControlWidth(dockInfluence: CGFloat) -> CGFloat {
        let influence = min(max(dockInfluence, 0), 1)
        return systemControlNormalWidth
            + (systemControlHoverWidth - systemControlNormalWidth) * influence
    }
}

@MainActor
final class ExternalControlZoneView: NSView {
    var onSelect: ((UUID) -> Void)?
    var onReturnHome: ((UUID) -> Void)?
    var onReload: ((UUID) -> Void)?
    var onAdd: (() -> Void)?
    var onEdit: ((UUID) -> Void)?
    var onRemove: ((UUID) -> Void)?
    var onSetWebsiteMode: ((UUID, WebsiteMode) -> Void)?
    var onSetWindowSize: ((UUID, SimpleViewportPreset) -> Void)?
    var onSetZoom: ((UUID, CGFloat) -> Void)?
    var onSetResidency: ((UUID, SlotResidencyPolicy) -> Void)?
    var onSetBackgroundMedia: ((UUID, BackgroundMediaPolicy) -> Void)?
    var onSetBrowserProfile: ((UUID, UUID?) -> Void)?
    var onOpenInNewTabWithBrowserProfile: ((UUID, UUID?) -> Void)?
    var onManageBrowserProfiles: (() -> Void)?
    var onReorder: ((UUID, Int) -> Void)?
    var onSettings: (() -> Void)?
    var onTogglePin: (() -> Void)?
    var onActiveTabGeometryChange: (() -> Void)?

    private var profiles: [WebAppProfile] = []
    private var activeTabID: UUID?
    private var residentSlotIDs = Set<UUID>()
    private var readySlotIDs = Set<UUID>()
    private var tabViews: [UUID: ExternalWebAppTabView] = [:]
    private var previewOrderIDs: [UUID]?
    private let addControl = AddWebAppControl()
    private let settingsControl = GlobalSettingsControl()
    private let pinControl = PinPanelControl()
    private var trackingAreaReference: NSTrackingArea?
    private var pointerLocation: NSPoint?
    private var pointerY: CGFloat?
    private var windowSizeEditingEnabled = true
    private var browserProfileMenuOptions: [BrowserProfileMenuOption] = [.defaultProfile()]
    private var browserProfileAssignmentEnabled = true
    private var browserProfileDuplicationEnabled = true
    private var railVisibilityGeneration = 0
    private(set) var isRailCollapsed = false

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        addSubview(addControl)
        addSubview(settingsControl)
        addSubview(pinControl)
        addControl.onActivate = { [weak self] in self?.onAdd?() }
        settingsControl.onActivate = { [weak self] in self?.onSettings?() }
        pinControl.onActivate = { [weak self] in self?.onTogglePin?() }
        addControl.onPointerMoved = { [weak self] event in
            self?.updateDockPointer(with: event)
        }
        settingsControl.onPointerMoved = { [weak self] event in
            self?.updateDockPointer(with: event)
        }
        pinControl.onPointerMoved = { [weak self] event in
            self?.updateDockPointer(with: event)
        }
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        guard window != nil else { return }

        // CALayer stores concrete CGColors rather than dynamic NSColors. A rail
        // can be created while its panel is ordered out, then attached under a
        // different effective appearance. Resolve every cached layer color
        // again once the view inherits its actual window appearance.
        refreshAppearance()
        DispatchQueue.main.async { [weak self] in
            self?.refreshAppearance()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }

        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        trackingAreaReference = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        updateDockPointer(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateDockPointer(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        pointerLocation = nil
        pointerY = nil
        synchronizeHoverState(at: nil)
        layoutControls(animated: true, duration: ExternalTabMetrics.dockSettleDuration)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let candidate = super.hitTest(point)
        return candidate === self ? nil : candidate
    }

    func apply(profiles: [WebAppProfile], activeTabID: UUID?) {
        self.profiles = profiles.sorted(by: { $0.order < $1.order })
        self.activeTabID = activeTabID
        previewOrderIDs = nil

        let validIDs = Set(profiles.map(\.id))
        let staleIDs = tabViews.keys.filter { !validIDs.contains($0) }
        for id in staleIDs {
            tabViews[id]?.removeFromSuperview()
            tabViews.removeValue(forKey: id)
        }

        for profile in self.profiles {
            let view = tabViews[profile.id] ?? makeTabView(for: profile.id)
            view.update(
                profile: profile,
                isActive: profile.id == activeTabID,
                isResident: residentSlotIDs.contains(profile.id)
            )
            view.setReadyAttention(readySlotIDs.contains(profile.id))
        }

        needsLayout = true
    }

    func setAddEditorOpen(_ isOpen: Bool) {
        addControl.isEditorOpen = isOpen
        layoutControls(animated: true, duration: ExternalTabMetrics.dockSettleDuration)
    }

    func setPinned(_ isPinned: Bool) {
        pinControl.setPinned(isPinned)
    }

    func setWindowSizeEditingEnabled(_ enabled: Bool) {
        windowSizeEditingEnabled = enabled
        for tab in tabViews.values {
            tab.setWindowSizeEditingEnabled(enabled)
        }
    }

    func setBrowserProfileMenuSnapshot(
        options: [BrowserProfileMenuOption],
        assignmentEnabled: Bool,
        duplicationEnabled: Bool = true
    ) {
        browserProfileMenuOptions = options.isEmpty
            ? [.defaultProfile()]
            : options
        browserProfileAssignmentEnabled = assignmentEnabled
        browserProfileDuplicationEnabled = duplicationEnabled
        for tab in tabViews.values {
            tab.setBrowserProfileMenuSnapshot(
                options: browserProfileMenuOptions,
                assignmentEnabled: assignmentEnabled,
                duplicationEnabled: duplicationEnabled
            )
        }
    }

    func setBrowserProfileAssignmentEnabled(_ enabled: Bool) {
        browserProfileAssignmentEnabled = enabled
        for tab in tabViews.values {
            tab.setBrowserProfileAssignmentEnabled(enabled)
        }
    }

    func setBrowserProfileDuplicationEnabled(_ enabled: Bool) {
        browserProfileDuplicationEnabled = enabled
        for tab in tabViews.values {
            tab.setBrowserProfileDuplicationEnabled(enabled)
        }
    }

    func refreshAppearance() {
        for tab in tabViews.values {
            tab.refreshAppearance()
        }
        addControl.refreshAppearance()
        settingsControl.refreshAppearance()
        pinControl.refreshAppearance()
    }

    func setCollapsed(_ collapsed: Bool, animated: Bool) {
        guard isRailCollapsed != collapsed || !animated else { return }
        isRailCollapsed = collapsed
        railVisibilityGeneration += 1
        let generation = railVisibilityGeneration
        pointerLocation = nil
        pointerY = nil
        synchronizeHoverState(at: nil)

        let controls = railContentViews
        controls.forEach { $0.isHidden = false }

        guard animated else {
            finishRailVisibility(generation: generation, collapsed: collapsed)
            needsLayout = true
            return
        }

        let translation: CGFloat = -12
        for view in controls {
            guard let layer = view.layer else { continue }
            let slide = CABasicAnimation(keyPath: "transform.translation.x")
            slide.fromValue = collapsed ? 0 : translation
            slide.toValue = collapsed ? translation : 0
            slide.duration = ExternalTabMetrics.railFoldAnimationDuration
            slide.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.78, 0.22, 1)
            layer.add(slide, forKey: "FloatTabs.railFoldSlide")
        }

        if !collapsed {
            controls.forEach { $0.alphaValue = 0 }
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = ExternalTabMetrics.railFoldAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            controls.forEach { $0.animator().alphaValue = collapsed ? 0 : 1 }
        } completionHandler: {
            Task { @MainActor [weak self] in
                self?.finishRailVisibility(
                    generation: generation,
                    collapsed: collapsed
                )
            }
        }
        onActiveTabGeometryChange?()
    }

    func setResidentSlotIDs(_ slotIDs: Set<UUID>) {
        residentSlotIDs = slotIDs
        for (slotID, tab) in tabViews {
            tab.setResident(slotIDs.contains(slotID))
        }
    }

    func setReadySlotIDs(_ slotIDs: Set<UUID>) {
        guard readySlotIDs != slotIDs else { return }
        readySlotIDs = slotIDs
        for (slotID, tab) in tabViews {
            tab.setReadyAttention(slotIDs.contains(slotID))
        }
    }

    override func layout() {
        super.layout()
        layoutControls(animated: false, duration: 0)
    }

    func tabView(for id: UUID) -> ExternalWebAppTabView? {
        tabViews[id]
    }

    func activeTabFrame(in ancestor: NSView) -> NSRect? {
        guard !isRailCollapsed,
              let activeTabID,
              let tab = tabViews[activeTabID],
              tab.superview != nil else {
            return nil
        }
        return tab.convert(tab.bounds, to: ancestor)
    }

    var addControlFrame: NSRect {
        addControl.frame
    }

    var settingsControlFrame: NSRect {
        settingsControl.frame
    }

    var pinControlFrame: NSRect {
        pinControl.frame
    }

    private var railContentViews: [NSView] {
        Array(tabViews.values) + [addControl, settingsControl, pinControl]
    }

    private func finishRailVisibility(generation: Int, collapsed: Bool) {
        guard generation == railVisibilityGeneration else { return }
        railContentViews.forEach {
            $0.alphaValue = collapsed ? 0 : 1
            $0.isHidden = collapsed
        }
        onActiveTabGeometryChange?()
    }

    private func makeTabView(for id: UUID) -> ExternalWebAppTabView {
        let view = ExternalWebAppTabView(slotID: id)
        view.setWindowSizeEditingEnabled(windowSizeEditingEnabled)
        view.setBrowserProfileMenuSnapshot(
            options: browserProfileMenuOptions,
            assignmentEnabled: browserProfileAssignmentEnabled,
            duplicationEnabled: browserProfileDuplicationEnabled
        )
        view.alphaValue = isRailCollapsed ? 0 : 1
        view.isHidden = isRailCollapsed
        tabViews[id] = view
        addSubview(view, positioned: .above, relativeTo: addControl)

        view.onSelect = { [weak self] slotID in self?.onSelect?(slotID) }
        view.onReturnHome = { [weak self] slotID in self?.onReturnHome?(slotID) }
        view.onReload = { [weak self] slotID in self?.onReload?(slotID) }
        view.onEdit = { [weak self] slotID in self?.onEdit?(slotID) }
        view.onRemove = { [weak self] slotID in self?.onRemove?(slotID) }
        view.onSetWebsiteMode = { [weak self] slotID, mode in
            self?.onSetWebsiteMode?(slotID, mode)
        }
        view.onSetWindowSize = { [weak self] slotID, preset in
            self?.onSetWindowSize?(slotID, preset)
        }
        view.onSetZoom = { [weak self] slotID, zoom in
            self?.onSetZoom?(slotID, zoom)
        }
        view.onSetResidency = { [weak self] slotID, policy in
            self?.onSetResidency?(slotID, policy)
        }
        view.onSetBackgroundMedia = { [weak self] slotID, policy in
            self?.onSetBackgroundMedia?(slotID, policy)
        }
        view.onSetBrowserProfile = { [weak self] slotID, profileID in
            self?.onSetBrowserProfile?(slotID, profileID)
        }
        view.onOpenInNewTabWithBrowserProfile = { [weak self] slotID, profileID in
            self?.onOpenInNewTabWithBrowserProfile?(slotID, profileID)
        }
        view.onManageBrowserProfiles = { [weak self] in
            self?.onManageBrowserProfiles?()
        }
        view.onPointerMoved = { [weak self] event in
            self?.updateDockPointer(with: event)
        }
        view.onDragChanged = { [weak self] slotID, event in
            self?.updateDockPointer(with: event)
            self?.updateReorderPreview(slotID: slotID, event: event)
        }
        view.onDragEnded = { [weak self] slotID in
            self?.commitReorder(slotID: slotID)
        }
        return view
    }

    private func updateDockPointer(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        pointerLocation = location
        pointerY = location.y
        synchronizeHoverState(at: location)
        layoutControls(animated: true, duration: ExternalTabMetrics.dockMotionDuration)
    }

    private func synchronizeHoverState(at location: NSPoint?) {
        guard !isRailCollapsed else { return }
        for tab in tabViews.values {
            tab.setHovered(location.map { tab.frame.contains($0) } ?? false)
        }
        addControl.setHovered(location.map { addControl.frame.contains($0) } ?? false)
        settingsControl.setHovered(
            location.map { settingsControl.frame.contains($0) } ?? false
        )
        pinControl.setHovered(location.map { pinControl.frame.contains($0) } ?? false)
    }

    private func layoutControls(animated: Bool, duration: TimeInterval) {
        let updateFrames = {
            var y = ExternalTabMetrics.topOffset
            let ids = self.previewOrderIDs ?? self.profiles.map(\.id)

            for id in ids {
                guard let tab = self.tabViews[id] else { continue }
                let centerY = y + ExternalTabMetrics.tabHeight / 2
                let influence = self.pointerY.map {
                    ExternalTabMetrics.dockInfluence(forDistance: $0 - centerY)
                } ?? 0
                tab.setDockInfluence(influence)

                let targetFrame = self.attachedFrame(
                    preferredWidth: tab.preferredWidth,
                    y: y,
                    height: ExternalTabMetrics.tabHeight,
                    isActiveTab: tab.isActiveTab
                )
                self.setFrame(targetFrame, for: tab, animated: animated)
                y += ExternalTabMetrics.tabHeight + ExternalTabMetrics.tabGap
            }

            if !ids.isEmpty {
                y += ExternalTabMetrics.addGap - ExternalTabMetrics.tabGap
            }

            let addCenterY = y + ExternalTabMetrics.addHeight / 2
            let addInfluence = self.pointerY.map {
                ExternalTabMetrics.dockInfluence(forDistance: $0 - addCenterY)
            } ?? 0
            self.addControl.setDockInfluence(addInfluence)

            let addFrame = self.attachedFrame(
                preferredWidth: self.addControl.preferredWidth,
                y: y,
                height: ExternalTabMetrics.addHeight
            )
            self.setFrame(addFrame, for: self.addControl, animated: animated)

            let pinY = max(
                self.bounds.height
                    - ExternalTabMetrics.systemControlBottomOffset
                    - ExternalTabMetrics.systemControlHeight,
                0
            )
            let pinCenterY = pinY + ExternalTabMetrics.systemControlHeight / 2
            let pinInfluence = self.pointerY.map {
                ExternalTabMetrics.dockInfluence(forDistance: $0 - pinCenterY)
            } ?? 0
            self.pinControl.setDockInfluence(pinInfluence)
            let pinFrame = self.attachedFrame(
                preferredWidth: self.pinControl.preferredWidth,
                y: pinY,
                height: ExternalTabMetrics.systemControlHeight
            )
            self.setFrame(pinFrame, for: self.pinControl, animated: animated)

            let systemY = max(
                pinY
                    - ExternalTabMetrics.systemControlGap
                    - ExternalTabMetrics.systemControlHeight,
                0
            )
            let systemCenterY = systemY + ExternalTabMetrics.systemControlHeight / 2
            let systemInfluence = self.pointerY.map {
                ExternalTabMetrics.dockInfluence(forDistance: $0 - systemCenterY)
            } ?? 0
            self.settingsControl.setDockInfluence(systemInfluence)
            let systemFrame = self.attachedFrame(
                preferredWidth: self.settingsControl.preferredWidth,
                y: systemY,
                height: ExternalTabMetrics.systemControlHeight
            )
            self.setFrame(systemFrame, for: self.settingsControl, animated: animated)

        }

        guard animated else {
            updateFrames()
            onActiveTabGeometryChange?()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            updateFrames()
        }
        onActiveTabGeometryChange?()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.onActiveTabGeometryChange?()
        }
    }

    private func attachedFrame(
        preferredWidth: CGFloat,
        y: CGFloat,
        height: CGFloat,
        isActiveTab: Bool = false
    ) -> NSRect {
        let rightInset = isActiveTab ? 0 : PanelMetrics.interactionBorderOutset
        let availableWidth = max(bounds.width - rightInset, 0)
        let width = min(preferredWidth, availableWidth)
        return NSRect(
            x: max(bounds.width - rightInset - width, 0),
            y: y,
            width: width,
            height: height
        )
    }

    private func setFrame(_ frame: NSRect, for view: NSView, animated: Bool) {
        if animated {
            view.animator().frame = frame
        } else {
            view.frame = frame
        }
    }

    private func updateReorderPreview(slotID: UUID, event: NSEvent) {
        var ids = previewOrderIDs ?? profiles.map(\.id)
        guard let currentIndex = ids.firstIndex(of: slotID) else { return }

        let location = convert(event.locationInWindow, from: nil)
        let pitch = ExternalTabMetrics.tabHeight + ExternalTabMetrics.tabGap
        let rawIndex = Int(((location.y - ExternalTabMetrics.topOffset) / pitch).rounded(.down))
        let destination = min(max(rawIndex, 0), ids.count - 1)
        guard destination != currentIndex else { return }

        ids.remove(at: currentIndex)
        ids.insert(slotID, at: destination)
        previewOrderIDs = ids
        needsLayout = true
    }

    private func commitReorder(slotID: UUID) {
        guard let ids = previewOrderIDs,
              let destination = ids.firstIndex(of: slotID) else {
            previewOrderIDs = nil
            needsLayout = true
            return
        }

        previewOrderIDs = nil
        onReorder?(slotID, destination)
        needsLayout = true
    }
}

/// Bottom-left mirror of the native-looking resize grip. Three themed strokes
/// sit entirely inside the Web surface and fan open / tuck inward with the rail.
@MainActor
final class RailFoldControl: NSView {
    var onActivate: (() -> Void)?

    private let strokeLayers = [CAShapeLayer(), CAShapeLayer(), CAShapeLayer()]
    private var trackingAreaReference: NSTrackingArea?
    private var borderTheme: PanelBorderTheme = .rainbow
    private var customBorderColor: NSColor = .systemBlue
    private(set) var isExpanded = true
    private var isHovered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        for stroke in strokeLayers {
            stroke.fillColor = NSColor.clear.cgColor
            stroke.lineWidth = 1.35
            stroke.lineCap = .round
            layer?.addSublayer(stroke)
        }

        toolTip = "Hide Tab Rail"
        setAccessibilityRole(.button)
        setAccessibilityLabel(toolTip)
        applyColorAppearance()
    }

    convenience init() { self.init(frame: .zero) }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        trackingAreaReference = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSCursor.arrow.set()
        refreshAppearance()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        refreshAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        NSCursor.arrow.set()
        let press = CASpringAnimation(keyPath: "transform.scale")
        press.fromValue = 0.82
        press.toValue = 1
        press.mass = 0.55
        press.stiffness = 260
        press.damping = 19
        press.duration = press.settlingDuration
        layer?.add(press, forKey: "FloatTabs.railGripPress")
        onActivate?()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    override func layout() {
        super.layout()
        for (index, stroke) in strokeLayers.enumerated() {
            stroke.frame = bounds
            stroke.path = gripPath(index: index, expanded: isExpanded)
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        // This control overlaps the source window's inner movement band. Its
        // own cursor rect must win so a rail toggle never advertises dragging.
        addCursorRect(bounds, cursor: .arrow)
    }

    func apply(theme: PanelBorderTheme, customColor: NSColor) {
        borderTheme = theme
        customBorderColor = customColor
        applyColorAppearance()
    }

    func refreshAppearance() {
        let opacity: Float = isHovered ? 1 : 0.82
        let width: CGFloat = isHovered ? 1.7 : 1.35
        strokeLayers.forEach {
            $0.opacity = opacity
            $0.lineWidth = width
        }
    }

    func setExpanded(_ expanded: Bool, animated: Bool) {
        guard isExpanded != expanded else { return }
        let oldPaths = strokeLayers.indices.map { gripPath(index: $0, expanded: isExpanded) }
        isExpanded = expanded
        toolTip = expanded ? "Hide Tab Rail" : "Show Tab Rail"
        setAccessibilityLabel(toolTip)

        for (index, stroke) in strokeLayers.enumerated() {
            let newPath = gripPath(index: index, expanded: expanded)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            stroke.path = newPath
            CATransaction.commit()

            guard animated else { continue }
            let fold = CABasicAnimation(keyPath: "path")
            fold.fromValue = oldPaths[index]
            fold.toValue = newPath
            fold.duration = ExternalTabMetrics.railFoldAnimationDuration
            fold.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.82, 0.2, 1)
            stroke.add(fold, forKey: "FloatTabs.railGripFold")
        }
    }

    /// The open state extends slightly beyond the right grip's 5/9/13 rhythm;
    /// the hidden state tucks back to that familiar size. The 40pt acquisition
    /// target never changes, keeping the control easy to recover.
    private func gripPath(index: Int, expanded: Bool) -> CGPath {
        let inset = PanelMetrics.resizeHandleVisualInset
        let expandedOffsets: [CGFloat] = [7, 12, 17]
        let tuckedOffsets: [CGFloat] = [5, 9, 13]
        let offset = (expanded ? expandedOffsets : tuckedOffsets)[index]
        let path = CGMutablePath()
        path.move(to: CGPoint(
            x: bounds.minX + inset + offset,
            y: bounds.minY + inset
        ))
        path.addLine(to: CGPoint(
            x: bounds.minX + inset,
            y: bounds.minY + inset + offset
        ))
        return path
    }

    private func applyColorAppearance() {
        strokeLayers.forEach { $0.removeAnimation(forKey: "FloatTabs.railGripRainbow") }
        if borderTheme == .rainbow {
            let colors = [NSColor.systemBlue, .systemPurple, .systemPink, .systemOrange]
            for (index, stroke) in strokeLayers.enumerated() {
                stroke.strokeColor = colors[index].cgColor
                let flow = CAKeyframeAnimation(keyPath: "strokeColor")
                flow.values = (0...3).map { colors[(index + $0) % colors.count].cgColor }
                    + [colors[index].cgColor]
                flow.keyTimes = [0, 0.25, 0.5, 0.75, 1]
                flow.duration = 3.2
                flow.repeatCount = .infinity
                flow.calculationMode = .linear
                stroke.add(flow, forKey: "FloatTabs.railGripRainbow")
            }
        } else {
            let color = borderTheme.solidColor ?? customBorderColor
            strokeLayers.forEach { $0.strokeColor = color.cgColor }
        }
        refreshAppearance()
    }
}

@MainActor
enum ExternalTabVisualPalette {
    /// Single seam for the future Settings → Appearance accent picker.
    static var activeAccent: NSColor { .controlAccentColor }
}

@MainActor
extension BrowserProfileColor {
    var appKitColor: NSColor {
        switch preset {
        case .custom:
            return customSRGBHex
                .flatMap(AppPreferencesStore.color(fromHex:))
                ?? .systemBlue
        default:
            return PanelBorderTheme(rawValue: preset.rawValue)?.solidColor ?? .systemBlue
        }
    }
}

@MainActor
final class WebsiteFaviconProvider {
    static let shared = WebsiteFaviconProvider()

    private var cache: [String: NSImage] = [:]
    private var failedOrigins = Set<String>()

    static func originKey(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased() else { return nil }
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }

    static func faviconURL(for url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme != nil,
              components.host != nil else { return nil }
        components.path = "/favicon.ico"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    func load(for url: URL, completion: @escaping (NSImage?) -> Void) {
        guard let key = Self.originKey(for: url),
              let faviconURL = Self.faviconURL(for: url) else {
            completion(nil)
            return
        }
        if let cached = cache[key] {
            completion(cached)
            return
        }
        if failedOrigins.contains(key) {
            completion(nil)
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                var request = URLRequest(url: faviconURL)
                request.cachePolicy = .returnCacheDataElseLoad
                request.timeoutInterval = 8
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse,
                   !(200..<300).contains(http.statusCode) {
                    failedOrigins.insert(key)
                    completion(nil)
                    return
                }
                guard let image = NSImage(data: data) else {
                    failedOrigins.insert(key)
                    completion(nil)
                    return
                }
                image.size = NSSize(width: 16, height: 16)
                cache[key] = image
                completion(image)
            } catch {
                failedOrigins.insert(key)
                completion(nil)
            }
        }
    }
}

@MainActor
final class ExternalWebAppTabView: NSView {
    let slotID: UUID

    var onSelect: ((UUID) -> Void)?
    var onReturnHome: ((UUID) -> Void)?
    var onReload: ((UUID) -> Void)?
    var onEdit: ((UUID) -> Void)?
    var onRemove: ((UUID) -> Void)?
    var onSetWebsiteMode: ((UUID, WebsiteMode) -> Void)?
    var onSetWindowSize: ((UUID, SimpleViewportPreset) -> Void)?
    var onSetZoom: ((UUID, CGFloat) -> Void)?
    var onSetResidency: ((UUID, SlotResidencyPolicy) -> Void)?
    var onSetBackgroundMedia: ((UUID, BackgroundMediaPolicy) -> Void)?
    var onSetBrowserProfile: ((UUID, UUID?) -> Void)?
    var onOpenInNewTabWithBrowserProfile: ((UUID, UUID?) -> Void)?
    var onManageBrowserProfiles: (() -> Void)?
    var onPointerMoved: ((NSEvent) -> Void)?
    var onDragChanged: ((UUID, NSEvent) -> Void)?
    var onDragEnded: ((UUID) -> Void)?

    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let shapeLayer = CAShapeLayer()
    private let readyAttentionLayer = CAShapeLayer()
    private var trackingAreaReference: NSTrackingArea?
    private var isActive = false
    private var isResident = false
    private var isHovered = false
    private var dockInfluence: CGFloat = 0
    private var mouseDownLocation: NSPoint?
    private var isDragging = false
    private var renderingProfile: WebRenderingProfile = .canonicalDefault
    private var residencyPolicy: SlotResidencyPolicy = .warm
    private var windowSizeEditingEnabled = true
    private var backgroundMediaPolicy: BackgroundMediaPolicy = .pauseWhenInactive
    private var webAppName = ""
    private var browserProfileID: UUID?
    private var browserProfileColor: BrowserProfileColor = .default
    private var browserProfileMenuOptions: [BrowserProfileMenuOption] = [.defaultProfile()]
    private var browserProfileAssignmentEnabled = true
    private var browserProfileDuplicationEnabled = true
    private var faviconOriginKey: String?
    private var sourceIcon: NSImage?
    private var grayscaleIcon: NSImage?

    private static let grayscaleContext = CIContext(options: nil)
    private static let readyAttentionDiameter: CGFloat = 6

    var preferredWidth: CGFloat {
        // Resting tabs are icon-only. Only the hovered row fully expands;
        // nearby Dock influence is intentionally capped so labels do not leak.
        let hoverInfluence: CGFloat = isHovered ? 1 : min(dockInfluence, 0.12)
        return ExternalTabMetrics.width(isActive: isActive, dockInfluence: hoverInfluence)
    }

    var isShowingLabel: Bool { isHovered }
    var displayedLabelText: String { label.stringValue }
    var isActiveTab: Bool { isActive }
    var isResidentRuntime: Bool { isResident }
    var displayedIcon: NSImage? { iconView.image }
    var isShowingReadyAttention: Bool { !readyAttentionLayer.isHidden }
    var readyAttentionFrame: NSRect { readyAttentionLayer.frame }
    var iconFrame: NSRect { iconView.frame }
    var readyAttentionColor: NSColor? {
        readyAttentionLayer.fillColor.flatMap(NSColor.init(cgColor:))
    }
    var displayedBrowserProfileColor: BrowserProfileColor { browserProfileColor }
    var displayedActiveTabFillColor: NSColor? {
        guard isActive else { return nil }
        return shapeLayer.fillColor.flatMap(NSColor.init(cgColor:))
    }
    var displayedTabFillColor: NSColor? {
        shapeLayer.fillColor.flatMap(NSColor.init(cgColor:))
    }
    var displayedActiveTabForegroundColor: NSColor? {
        guard isActive else { return nil }
        return label.textColor
    }
    var displayedIconTintColor: NSColor? { iconView.contentTintColor }

    init(slotID: UUID) {
        self.slotID = slotID
        super.init(frame: .zero)

        wantsLayer = true
        layer?.masksToBounds = false
        layer?.addSublayer(shapeLayer)
        readyAttentionLayer.fillColor = NSColor.systemRed.cgColor
        readyAttentionLayer.isHidden = true
        readyAttentionLayer.zPosition = 1
        layer?.addSublayer(readyAttentionLayer)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        setSourceIcon(Self.fallbackIcon())
        addSubview(iconView)

        setAccessibilityRole(.button)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byClipping
        label.alignment = .left
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.isHidden = true
        addSubview(label)

        let labelTrailingConstraint = label.trailingAnchor.constraint(
            equalTo: trailingAnchor,
            constant: -8
        )
        // A collapsed 40pt Tab intentionally has room for only the 16pt icon.
        // Keep the label's trailing edge optional until Dock magnification
        // expands the row; a required edge made AppKit break icon constraints
        // every time a hidden/new Tab was laid out at zero or collapsed width.
        labelTrailingConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 7),
            labelTrailingConstraint,
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool { false }

    // The shell is an activating panel in an LSUIElement app. Without this the
    // first click from a background application is spent on activation alone,
    // so selecting a tab would take two clicks. Drag and resize affordances
    // already accept first mouse; tab selection must fire on the same click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func layout() {
        super.layout()
        // Rail magnification animates the tab's width. Refresh cursor rects so
        // the registered arrow rect always covers the expanded row.
        window?.invalidateCursorRects(for: self)
        updateShape()
        updateReadyAttentionGeometry()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        // The whole rail column doubles as the shell's blank movement zone. A
        // tab's own cursor rect must win so tab hits never advertise dragging.
        addCursorRect(bounds, cursor: .arrow)
    }

    func setDockInfluence(_ influence: CGFloat) {
        dockInfluence = min(max(influence, 0), 1)
    }

    func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        label.isHidden = !hovered
        updateAppearance()
    }

    func setResident(_ resident: Bool) {
        guard isResident != resident else { return }
        isResident = resident
        updateAppearance()
        updateRuntimeToolTip()
    }

    func setReadyAttention(_ ready: Bool) {
        guard isShowingReadyAttention != ready else { return }
        readyAttentionLayer.isHidden = !ready
    }

    func setWindowSizeEditingEnabled(_ enabled: Bool) {
        windowSizeEditingEnabled = enabled
    }

    func setBrowserProfileMenuSnapshot(
        options: [BrowserProfileMenuOption],
        assignmentEnabled: Bool,
        duplicationEnabled: Bool = true
    ) {
        browserProfileMenuOptions = options.isEmpty
            ? [.defaultProfile()]
            : options
        browserProfileAssignmentEnabled = assignmentEnabled
        browserProfileDuplicationEnabled = duplicationEnabled
        refreshProfilePresentation()
        updateAppearance()
        updateRuntimeToolTip()
    }

    func setBrowserProfileAssignmentEnabled(_ enabled: Bool) {
        browserProfileAssignmentEnabled = enabled
    }

    func setBrowserProfileDuplicationEnabled(_ enabled: Bool) {
        browserProfileDuplicationEnabled = enabled
    }

    func update(profile: WebAppProfile, isActive: Bool, isResident: Bool) {
        self.isActive = isActive
        self.isResident = isResident
        webAppName = profile.name
        browserProfileID = profile.browserProfileID
        renderingProfile = profile.renderingProfile.normalized()
        residencyPolicy = profile.residencyPolicy
        backgroundMediaPolicy = profile.backgroundMediaPolicy
        loadFaviconIfNeeded(from: profile.homeURL)
        refreshProfilePresentation()
        updateAppearance()
        updateRuntimeToolTip()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        trackingAreaReference = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        setHovered(true)
        onPointerMoved?(event)
    }

    override func mouseMoved(with event: NSEvent) {
        onPointerMoved?(event)
        if isDragging {
            onDragChanged?(slotID, event)
        }
    }

    override func mouseExited(with event: NSEvent) {
        setHovered(false)
        onPointerMoved?(event)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = convert(event.locationInWindow, from: nil)
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownLocation else { return }
        let current = convert(event.locationInWindow, from: nil)
        if !isDragging,
           hypot(current.x - mouseDownLocation.x, current.y - mouseDownLocation.y) >= 4 {
            isDragging = true
        }
        if isDragging {
            onDragChanged?(slotID, event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownLocation = nil
            isDragging = false
        }
        if isDragging {
            onDragEnded?(slotID)
        } else {
            onSelect?(slotID)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menu(for: event) else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu(title: "Web App")

        let home = NSMenuItem(
            title: "Return to Home",
            action: #selector(returnHomeFromMenu(_:)),
            keyEquivalent: ""
        )
        home.setShortcut(KeyboardShortcuts.getShortcut(for: .returnHome))
        home.target = self
        menu.addItem(home)

        let reload = NSMenuItem(
            title: "Reload",
            action: #selector(reloadFromMenu(_:)),
            keyEquivalent: ""
        )
        reload.setShortcut(KeyboardShortcuts.getShortcut(for: .reload))
        reload.target = self
        reload.isEnabled = isResident
        menu.addItem(reload)
        menu.addItem(.separator())

        let websiteMode = NSMenuItem(title: "Website Mode", action: nil, keyEquivalent: "")
        let websiteModeMenu = NSMenu(title: "Website Mode")
        for mode in WebsiteMode.allCases {
            let item = NSMenuItem(title: mode.displayName, action: #selector(setWebsiteModeFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = mode == renderingProfile.websiteMode ? .on : .off
            websiteModeMenu.addItem(item)
        }
        websiteMode.submenu = websiteModeMenu
        menu.addItem(websiteMode)

        let windowSize = NSMenuItem(title: "Window Size", action: nil, keyEquivalent: "")
        let windowSizeMenu = NSMenu(title: "Window Size")
        for preset in SimpleViewportPreset.allCases where preset != .custom {
            let item = NSMenuItem(title: preset.menuTitle, action: #selector(setWindowSizeFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.rawValue
            item.state = preset == renderingProfile.sizePreset ? .on : .off
            windowSizeMenu.addItem(item)
        }
        if renderingProfile.sizePreset == .custom {
            windowSizeMenu.addItem(.separator())
            let custom = NSMenuItem(
                title: "Custom  \(Int(renderingProfile.viewportWidth)) × \(Int(renderingProfile.viewportHeight))",
                action: nil,
                keyEquivalent: ""
            )
            custom.state = .on
            custom.isEnabled = false
            windowSizeMenu.addItem(custom)
        }
        windowSize.submenu = windowSizeMenu
        windowSize.isEnabled = windowSizeEditingEnabled
        windowSize.toolTip = windowSizeEditingEnabled
            ? nil
            : "Window size is fixed globally in Settings → Appearance."
        menu.addItem(windowSize)

        let zoom = NSMenuItem(title: "Zoom", action: nil, keyEquivalent: "")
        let zoomMenu = NSMenu(title: "Zoom")

        let zoomIn = NSMenuItem(
            title: "Zoom In",
            action: #selector(zoomInFromMenu(_:)),
            keyEquivalent: ""
        )
        zoomIn.setShortcut(KeyboardShortcuts.getShortcut(for: .zoomIn))
        zoomIn.target = self
        zoomMenu.addItem(zoomIn)

        let zoomOut = NSMenuItem(
            title: "Zoom Out",
            action: #selector(zoomOutFromMenu(_:)),
            keyEquivalent: ""
        )
        zoomOut.setShortcut(KeyboardShortcuts.getShortcut(for: .zoomOut))
        zoomOut.target = self
        zoomMenu.addItem(zoomOut)

        let resetZoom = NSMenuItem(
            title: "Reset Zoom",
            action: #selector(resetZoomFromMenu(_:)),
            keyEquivalent: ""
        )
        resetZoom.setShortcut(KeyboardShortcuts.getShortcut(for: .resetZoom))
        resetZoom.target = self
        zoomMenu.addItem(resetZoom)
        zoomMenu.addItem(.separator())

        for value in ZoomSteps.values {
            let item = NSMenuItem(title: ZoomSteps.percentageText(for: value), action: #selector(setZoomFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: Double(value))
            item.state = abs(value - renderingProfile.zoom) < 0.001 ? .on : .off
            zoomMenu.addItem(item)
        }
        zoom.submenu = zoomMenu
        menu.addItem(zoom)
        menu.addItem(.separator())

        let profile = NSMenuItem(title: "Profile", action: nil, keyEquivalent: "")
        let profileMenu = NSMenu(title: "Profile")
        let profileOptions = browserProfileMenuOptions.isEmpty
            ? [.defaultProfile()]
            : browserProfileMenuOptions
        for option in profileOptions {
            let item = NSMenuItem(
                title: option.name,
                action: #selector(setBrowserProfileFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = option.id?.uuidString ?? NSNull()
            item.state = option.id == browserProfileID ? .on : .off
            item.isEnabled = browserProfileAssignmentEnabled && option.isEnabled
            profileMenu.addItem(item)
        }
        profileMenu.addItem(.separator())
        let manageProfiles = NSMenuItem(
            title: "Manage Profiles…",
            action: #selector(manageBrowserProfilesFromMenu(_:)),
            keyEquivalent: ""
        )
        manageProfiles.target = self
        profileMenu.addItem(manageProfiles)
        profile.submenu = profileMenu
        menu.addItem(profile)

        let duplicateProfile = NSMenuItem(
            title: "Open in New Tab with Profile",
            action: nil,
            keyEquivalent: ""
        )
        let duplicateProfileMenu = NSMenu(title: "Open in New Tab with Profile")
        for option in profileOptions {
            let item = NSMenuItem(
                title: option.name,
                action: #selector(openInNewTabWithBrowserProfileFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = option.id?.uuidString ?? NSNull()
            item.isEnabled = browserProfileDuplicationEnabled && option.isEnabled
            duplicateProfileMenu.addItem(item)
        }
        duplicateProfile.submenu = duplicateProfileMenu
        menu.addItem(duplicateProfile)

        let residency = NSMenuItem(title: "Residency", action: nil, keyEquivalent: "")
        let residencyMenu = NSMenu(title: "Residency")
        for policy in SlotResidencyPolicy.allCases {
            let item = NSMenuItem(title: policy.displayName, action: #selector(setResidencyFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = policy.rawValue
            item.state = policy == residencyPolicy ? .on : .off
            residencyMenu.addItem(item)
        }
        residency.submenu = residencyMenu
        menu.addItem(residency)

        let media = NSMenuItem(title: "Background Media", action: nil, keyEquivalent: "")
        let mediaMenu = NSMenu(title: "Background Media")
        for policy in BackgroundMediaPolicy.allCases {
            let item = NSMenuItem(title: policy.displayName, action: #selector(setBackgroundMediaFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = policy.rawValue
            item.state = policy == backgroundMediaPolicy ? .on : .off
            mediaMenu.addItem(item)
        }
        media.submenu = mediaMenu
        menu.addItem(media)
        menu.addItem(.separator())

        let edit = NSMenuItem(title: "Edit Web App…", action: #selector(editFromMenu(_:)), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)
        menu.addItem(.separator())

        let remove = NSMenuItem(title: "Remove Web App…", action: #selector(removeFromMenu(_:)), keyEquivalent: "")
        remove.target = self
        menu.addItem(remove)
        return menu
    }

    @objc private func returnHomeFromMenu(_ sender: NSMenuItem) { onReturnHome?(slotID) }
    @objc private func reloadFromMenu(_ sender: NSMenuItem) { onReload?(slotID) }

    @objc private func setWebsiteModeFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = WebsiteMode(rawValue: raw) else { return }
        onSetWebsiteMode?(slotID, mode)
    }

    @objc private func setWindowSizeFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let preset = SimpleViewportPreset(rawValue: raw),
              preset != .custom else { return }
        onSetWindowSize?(slotID, preset)
    }

    @objc private func zoomInFromMenu(_ sender: NSMenuItem) {
        onSetZoom?(slotID, ZoomSteps.nextLarger(after: renderingProfile.zoom))
    }

    @objc private func zoomOutFromMenu(_ sender: NSMenuItem) {
        onSetZoom?(slotID, ZoomSteps.nextSmaller(before: renderingProfile.zoom))
    }

    @objc private func resetZoomFromMenu(_ sender: NSMenuItem) {
        onSetZoom?(slotID, 1.0)
    }

    @objc private func setZoomFromMenu(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else { return }
        onSetZoom?(slotID, CGFloat(number.doubleValue))
    }

    @objc private func setBrowserProfileFromMenu(_ sender: NSMenuItem) {
        guard browserProfileAssignmentEnabled,
              let representedObject = sender.representedObject else {
            return
        }
        let profileID = (representedObject as? String).flatMap(UUID.init(uuidString:))
        onSetBrowserProfile?(slotID, profileID)
    }

    @objc private func openInNewTabWithBrowserProfileFromMenu(_ sender: NSMenuItem) {
        guard browserProfileDuplicationEnabled,
              let representedObject = sender.representedObject else {
            return
        }
        let profileID = (representedObject as? String).flatMap(UUID.init(uuidString:))
        onOpenInNewTabWithBrowserProfile?(slotID, profileID)
    }

    @objc private func manageBrowserProfilesFromMenu(_ sender: NSMenuItem) {
        onManageBrowserProfiles?()
    }

    @objc private func setResidencyFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let policy = SlotResidencyPolicy(rawValue: raw) else { return }
        onSetResidency?(slotID, policy)
    }

    @objc private func setBackgroundMediaFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let policy = BackgroundMediaPolicy(rawValue: raw) else { return }
        onSetBackgroundMedia?(slotID, policy)
    }

    @objc private func editFromMenu(_ sender: NSMenuItem) { onEdit?(slotID) }
    @objc private func removeFromMenu(_ sender: NSMenuItem) { onRemove?(slotID) }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    func refreshAppearance() {
        updateAppearance()
    }

    private func loadFaviconIfNeeded(from url: URL) {
        let key = WebsiteFaviconProvider.originKey(for: url)
        guard key != faviconOriginKey else { return }
        faviconOriginKey = key
        setSourceIcon(Self.fallbackIcon())
        WebsiteFaviconProvider.shared.load(for: url) { [weak self] image in
            guard let self, self.faviconOriginKey == key else { return }
            self.setSourceIcon(image ?? Self.fallbackIcon())
        }
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            applyResolvedAppearance()
        }
    }

    private func applyResolvedAppearance() {
        label.isHidden = !isHovered
        label.font = .systemFont(ofSize: 11.5, weight: isActive ? .semibold : .medium)
        label.textColor = isActive
            ? Self.activeForegroundColor(for: browserProfileColor.appKitColor)
            : .secondaryLabelColor
        applyIconAppearance()
        updateShape()
        readyAttentionLayer.fillColor = NSColor.systemRed.cgColor
        updateReadyAttentionGeometry()
    }

    private static func activeForegroundColor(for background: NSColor) -> NSColor {
        guard let color = background.usingColorSpace(.sRGB) else {
            return .white
        }

        func linearized(_ component: CGFloat) -> CGFloat {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }

        let luminance =
            0.2126 * linearized(color.redComponent)
            + 0.7152 * linearized(color.greenComponent)
            + 0.0722 * linearized(color.blueComponent)

        // A resolved sRGB luminance of 0.5 cleanly separates bright colors
        // such as Yellow from dark colors such as Graphite and Purple.
        return luminance >= 0.5 ? .black : .white
    }

    private var browserProfileDisplayName: String {
        guard let browserProfileID else {
            return browserProfileMenuOptions.first(where: { $0.id == nil })?.name
                ?? BrowserProfileMenuOption.defaultProfile().name
        }
        return browserProfileMenuOptions.first(where: { $0.id == browserProfileID })?.name
            ?? "Unknown Profile"
    }

    private var displayedPresentationTitle: String {
        guard !webAppName.isEmpty else { return browserProfileDisplayName }
        return "\(webAppName) · \(browserProfileDisplayName)"
    }

    private func refreshProfilePresentation() {
        browserProfileColor = browserProfileMenuOptions.first(where: {
            $0.id == browserProfileID
        })?.color ?? .default
        label.stringValue = displayedPresentationTitle
        setAccessibilityLabel(displayedPresentationTitle)
    }

    private func setSourceIcon(_ image: NSImage?) {
        sourceIcon = image
        if let image, !image.isTemplate {
            grayscaleIcon = Self.grayscaleImage(from: image)
        } else {
            grayscaleIcon = nil
        }
        applyIconAppearance()
    }

    private func applyIconAppearance() {
        let base = sourceIcon ?? Self.fallbackIcon()
        let templateTint = isActive
            ? Self.activeForegroundColor(for: browserProfileColor.appKitColor)
            : NSColor.labelColor
        if isResident {
            // Runtime truth owns color: active, Hot, Warm cache and Cold grace
            // all stay full color while a live WKWebView still exists.
            iconView.image = base
            iconView.alphaValue = 1
            iconView.contentTintColor = base?.isTemplate == true ? templateTint : nil
        } else {
            if base?.isTemplate == true {
                iconView.image = base
                iconView.contentTintColor = isActive ? templateTint : .tertiaryLabelColor
            } else {
                iconView.image = grayscaleIcon ?? Self.fallbackIcon()
                iconView.contentTintColor = grayscaleIcon == nil ? .tertiaryLabelColor : nil
            }
            iconView.alphaValue = isHovered ? 0.74 : 0.56
        }
    }

    private func updateRuntimeToolTip() {
        let state = isResident ? "Open" : "Released"
        toolTip = "\(displayedPresentationTitle) · \(state)"
    }

    private func updateShape() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        shapeLayer.frame = bounds
        let radius: CGFloat = 8
        let path = CGMutablePath()
        path.move(to: CGPoint(x: bounds.maxX, y: bounds.minY))
        path.addLine(to: CGPoint(x: bounds.minX + radius, y: bounds.minY))
        path.addQuadCurve(to: CGPoint(x: bounds.minX, y: bounds.minY + radius), control: CGPoint(x: bounds.minX, y: bounds.minY))
        path.addLine(to: CGPoint(x: bounds.minX, y: bounds.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: bounds.minX + radius, y: bounds.maxY), control: CGPoint(x: bounds.minX, y: bounds.maxY))
        path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY))
        path.closeSubpath()
        shapeLayer.path = path

        if isActive {
            // The animated PanelInteractionBorderView owns the active outline.
            // Keep only the tab surface here so page + active tab read as one shape.
            shapeLayer.fillColor = browserProfileColor.appKitColor
                .withAlphaComponent(1)
                .cgColor
            shapeLayer.strokeColor = NSColor.clear.cgColor
            shapeLayer.lineWidth = 0
            layer?.shadowOpacity = 0
            layer?.shadowPath = nil
        } else {
            shapeLayer.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(isHovered ? 0.96 : 0.82).cgColor
            // Selection is represented by the shared page+tab rainbow outline.
            // Inactive tabs have no individual hairline, especially in Light
            // appearance where a dark separator looked like a second border.
            shapeLayer.strokeColor = NSColor.clear.cgColor
            shapeLayer.lineWidth = 0
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = isHovered ? 0.16 : 0.08
            layer?.shadowRadius = isHovered ? 5 : 2
            layer?.shadowOffset = NSSize(width: -1, height: -1)
            layer?.shadowPath = path
        }
    }

    private func updateReadyAttentionGeometry() {
        guard layer != nil else { return }
        let iconFrame = iconView.convert(iconView.bounds, to: self)
        let diameter = Self.readyAttentionDiameter
        let frame = NSRect(
            x: iconFrame.maxX - diameter * 0.75,
            y: iconFrame.maxY - diameter * 0.75,
            width: diameter,
            height: diameter
        )
        readyAttentionLayer.frame = frame
        readyAttentionLayer.path = CGPath(
            ellipseIn: CGRect(origin: .zero, size: frame.size),
            transform: nil
        )
    }

    private static func grayscaleImage(from image: NSImage) -> NSImage? {
        guard let data = image.tiffRepresentation,
              let input = CIImage(data: data),
              let filter = CIFilter(name: "CIColorControls") else {
            return nil
        }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(0.0, forKey: kCIInputSaturationKey)
        guard let output = filter.outputImage,
              let cgImage = grayscaleContext.createCGImage(output, from: output.extent) else {
            return nil
        }
        let result = NSImage(cgImage: cgImage, size: image.size)
        result.isTemplate = false
        return result
    }

    private static func fallbackIcon() -> NSImage? {
        NSImage(systemSymbolName: "globe", accessibilityDescription: "Website")
    }
}

@MainActor
final class AddWebAppControl: NSView {
    var onActivate: (() -> Void)?
    var onPointerMoved: ((NSEvent) -> Void)?

    private let imageView = NSImageView()
    private var trackingAreaReference: NSTrackingArea?
    private var isHovered = false
    private var dockInfluence: CGFloat = 0

    var isEditorOpen = false {
        didSet {
            updateAppearance()
        }
    }

    var preferredWidth: CGFloat {
        ExternalTabMetrics.addWidth(
            isEditorOpen: isEditorOpen,
            dockInfluence: dockInfluence
        )
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = ExternalTabMetrics.tabRadius
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]

        imageView.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add Web App")
        imageView.contentTintColor = .labelColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 12),
            imageView.heightAnchor.constraint(equalToConstant: 12),
        ])

        updateAppearance()
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool { false }

    // Same activation contract as ExternalWebAppTabView: the first click from
    // a background application must reach the control, not be spent activating
    // the shell. Every drag and resize affordance already accepts first mouse.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func layout() {
        super.layout()
        // Dock influence animates the control's width. Refresh cursor rects so
        // the registered arrow rect always covers the expanded row.
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        // The whole rail column doubles as the shell's blank movement zone. The
        // control's own cursor rect must win so hits never advertise dragging.
        addCursorRect(bounds, cursor: .arrow)
    }

    func setDockInfluence(_ influence: CGFloat) {
        dockInfluence = min(max(influence, 0), 1)
    }

    func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        updateAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        trackingAreaReference = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        setHovered(true)
        onPointerMoved?(event)
    }

    override func mouseMoved(with event: NSEvent) {
        onPointerMoved?(event)
    }

    override func mouseExited(with event: NSEvent) {
        setHovered(false)
        onPointerMoved?(event)
    }

    override func mouseUp(with event: NSEvent) {
        onActivate?()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    func refreshAppearance() {
        updateAppearance()
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            applyResolvedAppearance()
        }
    }

    private func applyResolvedAppearance() {
        let fraction: CGFloat = (isHovered || isEditorOpen) ? 0.10 : 0.02
        layer?.backgroundColor = NSColor.controlBackgroundColor
            .blended(withFraction: fraction, of: .labelColor)?
            .withAlphaComponent(0.94)
            .cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.30).cgColor
        layer?.borderWidth = 1
    }
}


@MainActor
final class PinPanelControl: NSView {
    var onActivate: (() -> Void)?
    var onPointerMoved: ((NSEvent) -> Void)?

    private let imageView = NSImageView()
    private var trackingAreaReference: NSTrackingArea?
    private var isHovered = false
    private var dockInfluence: CGFloat = 0

    private(set) var isPinned = false {
        didSet { updateAppearance() }
    }

    var preferredWidth: CGFloat {
        ExternalTabMetrics.systemControlWidth(dockInfluence: dockInfluence)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = ExternalTabMetrics.tabRadius
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 13),
            imageView.heightAnchor.constraint(equalToConstant: 13),
        ])
        updateAppearance()
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool { false }

    // Same activation contract as ExternalWebAppTabView: the first click from
    // a background application must reach the control, not be spent activating
    // the shell. Every drag and resize affordance already accepts first mouse.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func layout() {
        super.layout()
        // Dock influence animates the control's width. Refresh cursor rects so
        // the registered arrow rect always covers the expanded row.
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        // The whole rail column doubles as the shell's blank movement zone. The
        // control's own cursor rect must win so hits never advertise dragging.
        addCursorRect(bounds, cursor: .arrow)
    }

    func setDockInfluence(_ influence: CGFloat) {
        dockInfluence = min(max(influence, 0), 1)
    }

    func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        updateAppearance()
    }

    func setPinned(_ pinned: Bool) {
        isPinned = pinned
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        trackingAreaReference = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        setHovered(true)
        onPointerMoved?(event)
    }

    override func mouseMoved(with event: NSEvent) {
        onPointerMoved?(event)
    }

    override func mouseExited(with event: NSEvent) {
        setHovered(false)
        onPointerMoved?(event)
    }

    override func mouseUp(with event: NSEvent) {
        onActivate?()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    func refreshAppearance() {
        updateAppearance()
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            applyResolvedAppearance()
        }
    }

    private func applyResolvedAppearance() {
        let symbol = isPinned ? "pin.fill" : "pin"
        let description = isPinned ? "Pinned: keep FloatTabs visible" : "Pin FloatTabs"
        imageView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        toolTip = isPinned
            ? "Pinned · Click or press ⌘⇧P to auto-hide when inactive"
            : "Keep FloatTabs Visible · ⌘⇧P"

        let fraction: CGFloat
        if isPinned {
            fraction = isHovered ? 0.18 : 0.12
        } else {
            fraction = isHovered ? 0.10 : 0.02
        }
        layer?.backgroundColor = NSColor.controlBackgroundColor
            .blended(withFraction: fraction, of: .labelColor)?
            .withAlphaComponent(0.94)
            .cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.30).cgColor
        layer?.borderWidth = 1
        imageView.contentTintColor = isPinned ? .labelColor : .secondaryLabelColor
    }
}

@MainActor
final class GlobalSettingsControl: NSView {
    var onActivate: (() -> Void)?
    var onPointerMoved: ((NSEvent) -> Void)?

    private let imageView = NSImageView()
    private var trackingAreaReference: NSTrackingArea?
    private var isHovered = false
    private var dockInfluence: CGFloat = 0

    var preferredWidth: CGFloat {
        ExternalTabMetrics.systemControlWidth(dockInfluence: dockInfluence)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = ExternalTabMetrics.tabRadius
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        toolTip = "FloatTabs Settings · ⌘,"

        imageView.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Global Settings")
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 13),
            imageView.heightAnchor.constraint(equalToConstant: 13),
        ])
        updateAppearance()
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool { false }

    // Same activation contract as ExternalWebAppTabView: the first click from
    // a background application must reach the control, not be spent activating
    // the shell. Every drag and resize affordance already accepts first mouse.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func layout() {
        super.layout()
        // Dock influence animates the control's width. Refresh cursor rects so
        // the registered arrow rect always covers the expanded row.
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        // The whole rail column doubles as the shell's blank movement zone. The
        // control's own cursor rect must win so hits never advertise dragging.
        addCursorRect(bounds, cursor: .arrow)
    }

    func setDockInfluence(_ influence: CGFloat) {
        dockInfluence = min(max(influence, 0), 1)
    }

    func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        updateAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        trackingAreaReference = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        setHovered(true)
        onPointerMoved?(event)
    }

    override func mouseMoved(with event: NSEvent) {
        onPointerMoved?(event)
    }

    override func mouseExited(with event: NSEvent) {
        setHovered(false)
        onPointerMoved?(event)
    }

    override func mouseUp(with event: NSEvent) {
        onActivate?()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    func refreshAppearance() {
        updateAppearance()
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            applyResolvedAppearance()
        }
    }

    private func applyResolvedAppearance() {
        let fraction: CGFloat = isHovered ? 0.10 : 0.02
        layer?.backgroundColor = NSColor.controlBackgroundColor
            .blended(withFraction: fraction, of: .labelColor)?
            .withAlphaComponent(0.94)
            .cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.30).cgColor
        layer?.borderWidth = 1
        imageView.contentTintColor = .labelColor
    }
}
