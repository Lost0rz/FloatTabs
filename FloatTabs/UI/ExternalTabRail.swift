import AppKit
import QuartzCore

struct ExternalTabMetrics {
    static let tabHeight: CGFloat = 32
    static let tabRadius: CGFloat = 8
    static let collapsedWidth: CGFloat = 40
    static let hoverWidth: CGFloat = 76
    static let activeWidth: CGFloat = 40
    static let activeHoverWidth: CGFloat = 76
    static let topOffset: CGFloat = 23
    static let tabGap: CGFloat = 4
    static let addGap: CGFloat = 8

    static let addHeight: CGFloat = 28
    static let addNormalWidth: CGFloat = 34
    static let addHoverWidth: CGFloat = 54
    static let addOpenWidth: CGFloat = 58

    static let systemControlHeight: CGFloat = 28
    static let systemControlNormalWidth: CGFloat = 34
    static let systemControlHoverWidth: CGFloat = 54
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
    var onAdd: (() -> Void)?
    var onEdit: ((UUID) -> Void)?
    var onRemove: ((UUID) -> Void)?
    var onSetWebsiteMode: ((UUID, WebsiteMode) -> Void)?
    var onSetWindowSize: ((UUID, SimpleViewportPreset) -> Void)?
    var onSetZoom: ((UUID, CGFloat) -> Void)?
    var onSetResidency: ((UUID, SlotResidencyPolicy) -> Void)?
    var onSetBackgroundMedia: ((UUID, BackgroundMediaPolicy) -> Void)?
    var onReorder: ((UUID, Int) -> Void)?
    var onCurrentControls: (() -> Void)?
    var onTogglePin: (() -> Void)?

    private var profiles: [WebAppProfile] = []
    private var activeTabID: UUID?
    private var tabViews: [UUID: ExternalWebAppTabView] = [:]
    private var previewOrderIDs: [UUID]?
    private let addControl = AddWebAppControl()
    private let currentControls = CurrentWebAppControl()
    private let pinControl = PinPanelControl()
    private var trackingAreaReference: NSTrackingArea?
    private var pointerY: CGFloat?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        addSubview(addControl)
        addSubview(currentControls)
        addSubview(pinControl)
        addControl.onActivate = { [weak self] in self?.onAdd?() }
        currentControls.onActivate = { [weak self] in self?.onCurrentControls?() }
        pinControl.onActivate = { [weak self] in self?.onTogglePin?() }
        addControl.onPointerMoved = { [weak self] event in
            self?.updateDockPointer(with: event)
        }
        currentControls.onPointerMoved = { [weak self] event in
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
        pointerY = nil
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
            view.update(profile: profile, isActive: profile.id == activeTabID)
        }

        currentControls.isEnabled = activeTabID != nil
        needsLayout = true
    }

    func setAddEditorOpen(_ isOpen: Bool) {
        addControl.isEditorOpen = isOpen
        layoutControls(animated: true, duration: ExternalTabMetrics.dockSettleDuration)
    }

    func setPinned(_ isPinned: Bool) {
        pinControl.setPinned(isPinned)
    }

    override func layout() {
        super.layout()
        layoutControls(animated: false, duration: 0)
    }

    func tabView(for id: UUID) -> ExternalWebAppTabView? {
        tabViews[id]
    }

    var addControlFrame: NSRect {
        addControl.frame
    }

    var currentControlsFrame: NSRect {
        currentControls.frame
    }

    var pinControlFrame: NSRect {
        pinControl.frame
    }

    private func makeTabView(for id: UUID) -> ExternalWebAppTabView {
        let view = ExternalWebAppTabView(slotID: id)
        tabViews[id] = view
        addSubview(view, positioned: .above, relativeTo: addControl)

        view.onSelect = { [weak self] slotID in self?.onSelect?(slotID) }
        view.onReturnHome = { [weak self] slotID in self?.onReturnHome?(slotID) }
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
        pointerY = location.y
        layoutControls(animated: true, duration: ExternalTabMetrics.dockMotionDuration)
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

                let width = min(tab.preferredWidth, self.bounds.width)
                let targetFrame = NSRect(
                    x: max(self.bounds.width - width, 0),
                    y: y,
                    width: width,
                    height: ExternalTabMetrics.tabHeight
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

            let addWidth = min(self.addControl.preferredWidth, self.bounds.width)
            let addFrame = NSRect(
                x: max(self.bounds.width - addWidth, 0),
                y: y,
                width: addWidth,
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
            let pinWidth = min(self.pinControl.preferredWidth, self.bounds.width)
            let pinFrame = NSRect(
                x: max(self.bounds.width - pinWidth, 0),
                y: pinY,
                width: pinWidth,
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
            self.currentControls.setDockInfluence(systemInfluence)
            let systemWidth = min(self.currentControls.preferredWidth, self.bounds.width)
            let systemFrame = NSRect(
                x: max(self.bounds.width - systemWidth, 0),
                y: systemY,
                width: systemWidth,
                height: ExternalTabMetrics.systemControlHeight
            )
            self.setFrame(systemFrame, for: self.currentControls, animated: animated)
        }

        guard animated else {
            updateFrames()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            updateFrames()
        }
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

@MainActor
enum ExternalTabVisualPalette {
    /// Single seam for the future Settings → Appearance accent picker.
    static var activeAccent: NSColor { .controlAccentColor }
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
    var onEdit: ((UUID) -> Void)?
    var onRemove: ((UUID) -> Void)?
    var onSetWebsiteMode: ((UUID, WebsiteMode) -> Void)?
    var onSetWindowSize: ((UUID, SimpleViewportPreset) -> Void)?
    var onSetZoom: ((UUID, CGFloat) -> Void)?
    var onSetResidency: ((UUID, SlotResidencyPolicy) -> Void)?
    var onSetBackgroundMedia: ((UUID, BackgroundMediaPolicy) -> Void)?
    var onPointerMoved: ((NSEvent) -> Void)?
    var onDragChanged: ((UUID, NSEvent) -> Void)?
    var onDragEnded: ((UUID) -> Void)?

    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let shapeLayer = CAShapeLayer()
    private var trackingAreaReference: NSTrackingArea?
    private var isActive = false
    private var isHovered = false
    private var dockInfluence: CGFloat = 0
    private var mouseDownLocation: NSPoint?
    private var isDragging = false
    private var renderingProfile: WebRenderingProfile = .canonicalDefault
    private var residencyPolicy: SlotResidencyPolicy = .warm
    private var backgroundMediaPolicy: BackgroundMediaPolicy = .pauseWhenInactive
    private var faviconOriginKey: String?

    var preferredWidth: CGFloat {
        // Resting tabs are icon-only. Only the hovered row fully expands;
        // nearby Dock influence is intentionally capped so labels do not leak.
        let hoverInfluence: CGFloat = isHovered ? 1 : min(dockInfluence, 0.12)
        return ExternalTabMetrics.width(isActive: isActive, dockInfluence: hoverInfluence)
    }

    var isShowingLabel: Bool { isHovered }
    var displayedIcon: NSImage? { iconView.image }

    init(slotID: UUID) {
        self.slotID = slotID
        super.init(frame: .zero)

        wantsLayer = true
        layer?.masksToBounds = false
        layer?.addSublayer(shapeLayer)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.image = Self.fallbackIcon()
        addSubview(iconView)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byClipping
        label.alignment = .left
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.isHidden = true
        addSubview(label)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func layout() {
        super.layout()
        updateShape()
    }

    func setDockInfluence(_ influence: CGFloat) {
        dockInfluence = min(max(influence, 0), 1)
    }

    func update(profile: WebAppProfile, isActive: Bool) {
        self.isActive = isActive
        label.stringValue = profile.name
        toolTip = profile.name
        renderingProfile = profile.renderingProfile.normalized()
        residencyPolicy = profile.residencyPolicy
        backgroundMediaPolicy = profile.backgroundMediaPolicy
        loadFaviconIfNeeded(from: profile.homeURL)
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
        isHovered = true
        label.isHidden = false
        updateAppearance()
        onPointerMoved?(event)
    }

    override func mouseMoved(with event: NSEvent) {
        onPointerMoved?(event)
        if isDragging {
            onDragChanged?(slotID, event)
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        label.isHidden = true
        updateAppearance()
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
            keyEquivalent: "h"
        )
        home.keyEquivalentModifierMask = [.command, .shift]
        home.target = self
        menu.addItem(home)
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
        menu.addItem(windowSize)

        let zoom = NSMenuItem(title: "Zoom", action: nil, keyEquivalent: "")
        let zoomMenu = NSMenu(title: "Zoom")
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

    @objc private func setZoomFromMenu(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else { return }
        onSetZoom?(slotID, CGFloat(number.doubleValue))
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
        updateAppearance()
    }

    private func loadFaviconIfNeeded(from url: URL) {
        let key = WebsiteFaviconProvider.originKey(for: url)
        guard key != faviconOriginKey else { return }
        faviconOriginKey = key
        iconView.image = Self.fallbackIcon()
        WebsiteFaviconProvider.shared.load(for: url) { [weak self] image in
            guard let self, self.faviconOriginKey == key else { return }
            self.iconView.image = image ?? Self.fallbackIcon()
        }
    }

    private func updateAppearance() {
        label.isHidden = !isHovered
        label.font = .systemFont(ofSize: 11.5, weight: isActive ? .semibold : .medium)
        label.textColor = isActive ? .labelColor : .secondaryLabelColor
        updateShape()
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
            let accent = ExternalTabVisualPalette.activeAccent
            shapeLayer.fillColor = NSColor.windowBackgroundColor.withAlphaComponent(0.98).cgColor
            shapeLayer.strokeColor = accent.withAlphaComponent(0.92).cgColor
            shapeLayer.lineWidth = 2
            layer?.shadowColor = accent.cgColor
            layer?.shadowOpacity = 0.34
            layer?.shadowRadius = 8
            layer?.shadowOffset = .zero
            layer?.shadowPath = path
        } else {
            shapeLayer.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(isHovered ? 0.96 : 0.82).cgColor
            shapeLayer.strokeColor = NSColor.separatorColor.withAlphaComponent(0.48).cgColor
            shapeLayer.lineWidth = 1
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = isHovered ? 0.16 : 0.08
            layer?.shadowRadius = isHovered ? 5 : 2
            layer?.shadowOffset = NSSize(width: -1, height: -1)
            layer?.shadowPath = path
        }
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

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    func setDockInfluence(_ influence: CGFloat) {
        dockInfluence = min(max(influence, 0), 1)
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
        updateAppearance()
        onPointerMoved?(event)
    }

    override func mouseMoved(with event: NSEvent) {
        onPointerMoved?(event)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        onActivate?()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
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

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    func setDockInfluence(_ influence: CGFloat) {
        dockInfluence = min(max(influence, 0), 1)
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
        isHovered = true
        updateAppearance()
        onPointerMoved?(event)
    }

    override func mouseMoved(with event: NSEvent) {
        onPointerMoved?(event)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        onActivate?()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
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
final class CurrentWebAppControl: NSView {
    var onActivate: (() -> Void)?
    var onPointerMoved: ((NSEvent) -> Void)?

    private let imageView = NSImageView()
    private var trackingAreaReference: NSTrackingArea?
    private var isHovered = false
    private var dockInfluence: CGFloat = 0

    var isEnabled = false {
        didSet { updateAppearance() }
    }

    var preferredWidth: CGFloat {
        ExternalTabMetrics.systemControlWidth(dockInfluence: dockInfluence)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = ExternalTabMetrics.tabRadius
        toolTip = "Current Web App Controls"

        imageView.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Current Web App Controls")
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

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isEnabled else { return nil }
        return frame.contains(point) ? self : nil
    }

    func setDockInfluence(_ influence: CGFloat) {
        dockInfluence = min(max(influence, 0), 1)
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
        updateAppearance()
        onPointerMoved?(event)
    }

    override func mouseMoved(with event: NSEvent) {
        onPointerMoved?(event)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled else { return }
        onActivate?()
    }

    private func updateAppearance() {
        let fraction: CGFloat = isHovered ? 0.10 : 0.02
        layer?.backgroundColor = NSColor.controlBackgroundColor
            .blended(withFraction: fraction, of: .labelColor)?
            .withAlphaComponent(isEnabled ? 0.94 : 0.55)
            .cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.30).cgColor
        layer?.borderWidth = 1
        imageView.contentTintColor = isEnabled ? .labelColor : .tertiaryLabelColor
    }
}
