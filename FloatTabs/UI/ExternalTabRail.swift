import AppKit
import QuartzCore

struct ExternalTabMetrics {
    static let tabHeight: CGFloat = 32
    static let tabRadius: CGFloat = 8
    static let inactiveWidth: CGFloat = 44
    static let hoverWidth: CGFloat = 66
    static let activeWidth: CGFloat = 68
    static let activeHoverWidth: CGFloat = 74
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
        let resting = isActive ? activeWidth : inactiveWidth
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
    var onSetResidency: ((UUID, SlotResidencyPolicy) -> Void)?
    var onSetBackgroundMedia: ((UUID, BackgroundMediaPolicy) -> Void)?
    var onReorder: ((UUID, Int) -> Void)?
    var onCurrentControls: (() -> Void)?

    private var profiles: [WebAppProfile] = []
    private var activeTabID: UUID?
    private var tabViews: [UUID: ExternalWebAppTabView] = [:]
    private var previewOrderIDs: [UUID]?
    private let addControl = AddWebAppControl()
    private let currentControls = CurrentWebAppControl()
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
        addControl.onActivate = { [weak self] in self?.onAdd?() }
        currentControls.onActivate = { [weak self] in self?.onCurrentControls?() }
        addControl.onPointerMoved = { [weak self] event in
            self?.updateDockPointer(with: event)
        }
        currentControls.onPointerMoved = { [weak self] event in
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

    private func makeTabView(for id: UUID) -> ExternalWebAppTabView {
        let view = ExternalWebAppTabView(slotID: id)
        tabViews[id] = view
        addSubview(view, positioned: .above, relativeTo: addControl)

        view.onSelect = { [weak self] slotID in self?.onSelect?(slotID) }
        view.onReturnHome = { [weak self] slotID in self?.onReturnHome?(slotID) }
        view.onEdit = { [weak self] slotID in self?.onEdit?(slotID) }
        view.onRemove = { [weak self] slotID in self?.onRemove?(slotID) }
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

            let systemY = max(
                self.bounds.height
                    - ExternalTabMetrics.systemControlBottomOffset
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
final class ExternalWebAppTabView: NSView {
    let slotID: UUID

    var onSelect: ((UUID) -> Void)?
    var onReturnHome: ((UUID) -> Void)?
    var onEdit: ((UUID) -> Void)?
    var onRemove: ((UUID) -> Void)?
    var onSetResidency: ((UUID, SlotResidencyPolicy) -> Void)?
    var onSetBackgroundMedia: ((UUID, BackgroundMediaPolicy) -> Void)?
    var onPointerMoved: ((NSEvent) -> Void)?
    var onDragChanged: ((UUID, NSEvent) -> Void)?
    var onDragEnded: ((UUID) -> Void)?

    private let label = NSTextField(labelWithString: "")
    private var trackingAreaReference: NSTrackingArea?
    private var isActive = false
    private var isHovered = false
    private var dockInfluence: CGFloat = 0
    private var mouseDownLocation: NSPoint?
    private var isDragging = false
    private var residencyPolicy: SlotResidencyPolicy = .warm
    private var backgroundMediaPolicy: BackgroundMediaPolicy = .pauseWhenInactive

    var preferredWidth: CGFloat {
        ExternalTabMetrics.width(isActive: isActive, dockInfluence: dockInfluence)
    }

    init(slotID: UUID) {
        self.slotID = slotID
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = ExternalTabMetrics.tabRadius
        layer?.masksToBounds = false

        label.translatesAutoresizingMaskIntoConstraints = false
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.alignment = .center
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
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

    func update(profile: WebAppProfile, isActive: Bool) {
        label.stringValue = profile.name
        residencyPolicy = profile.residencyPolicy
        backgroundMediaPolicy = profile.backgroundMediaPolicy
        toolTip = "\(profile.name) · \(profile.residencyPolicy.displayName)"
        self.isActive = isActive
        updateAppearance()
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
        guard !isDragging else { return }
        isHovered = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownLocation else { return }
        let distance = hypot(
            event.locationInWindow.x - mouseDownLocation.x,
            event.locationInWindow.y - mouseDownLocation.y
        )
        guard isDragging || distance >= 3 else { return }

        if !isDragging {
            isDragging = true
            updateAppearance()
        }
        onDragChanged?(slotID, event)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownLocation = nil
            if isDragging {
                isDragging = false
                isHovered = bounds.contains(convert(event.locationInWindow, from: nil))
                updateAppearance()
            }
        }

        if isDragging {
            onDragEnded?(slotID)
        } else {
            onSelect?(slotID)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()

        let home = NSMenuItem(
            title: "Return to Home",
            action: #selector(returnHomeFromMenu),
            keyEquivalent: "h"
        )
        home.keyEquivalentModifierMask = [.command, .shift]
        home.target = self
        menu.addItem(home)
        menu.addItem(.separator())

        let residency = NSMenuItem(title: "Residency", action: nil, keyEquivalent: "")
        let residencyMenu = NSMenu(title: "Residency")
        for policy in SlotResidencyPolicy.allCases {
            let item = NSMenuItem(
                title: policy.displayName,
                action: #selector(setResidencyFromMenu(_:)),
                keyEquivalent: ""
            )
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
            let item = NSMenuItem(
                title: policy.displayName,
                action: #selector(setBackgroundMediaFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = policy.rawValue
            item.state = policy == backgroundMediaPolicy ? .on : .off
            mediaMenu.addItem(item)
        }
        media.submenu = mediaMenu
        menu.addItem(media)
        menu.addItem(.separator())

        let edit = NSMenuItem(title: "Edit Web App…", action: #selector(editFromMenu), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)

        menu.addItem(.separator())

        let remove = NSMenuItem(title: "Remove Web App…", action: #selector(removeFromMenu), keyEquivalent: "")
        remove.target = self
        menu.addItem(remove)
        return menu
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    @objc private func returnHomeFromMenu() {
        onReturnHome?(slotID)
    }

    @objc private func editFromMenu() {
        onEdit?(slotID)
    }

    @objc private func setResidencyFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let policy = SlotResidencyPolicy(rawValue: rawValue) else { return }
        onSetResidency?(slotID, policy)
    }

    @objc private func setBackgroundMediaFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let policy = BackgroundMediaPolicy(rawValue: rawValue) else { return }
        onSetBackgroundMedia?(slotID, policy)
    }

    @objc private func removeFromMenu() {
        onRemove?(slotID)
    }

    private func updateAppearance() {
        let surface: NSColor
        if isActive {
            surface = NSColor.controlBackgroundColor.blended(withFraction: 0.18, of: .labelColor)
                ?? .controlBackgroundColor
        } else if isHovered {
            surface = NSColor.controlBackgroundColor.blended(withFraction: 0.10, of: .labelColor)
                ?? .controlBackgroundColor
        } else {
            surface = NSColor.controlBackgroundColor.withAlphaComponent(0.92)
        }

        layer?.backgroundColor = surface.cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        layer?.borderWidth = 1
        layer?.shadowOpacity = isDragging ? 0.24 : 0
        layer?.shadowRadius = isDragging ? 8 : 0
        layer?.shadowOffset = CGSize(width: 0, height: -2)

        label.textColor = (isActive || isHovered) ? .labelColor : .secondaryLabelColor
        label.font = NSFont.systemFont(
            ofSize: 11,
            weight: isActive ? .semibold : .medium
        )
        alphaValue = isDragging ? 0.88 : 1
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
