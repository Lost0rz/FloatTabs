import AppKit
import CoreImage
import Foundation
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
private protocol RailHoverInteractionOwner: AnyObject {
    func setHoverInteractionSuspended(_ suspended: Bool)
}

@MainActor
final class SpeechRailControl: NSView, RailHoverInteractionOwner {
    enum Kind: Equatable {
        case autoSpeak
        case readLatest
        case replay
        case stop
    }

    let kind: Kind
    var onActivate: (() -> Void)?
    var onPointerMoved: ((NSEvent) -> Void)?

    private let imageView = NSImageView()
    private var trackingAreaReference: NSTrackingArea?
    private var isHovered = false
    private var isHoverInteractionSuspended = false
    private var dockInfluence: CGFloat = 0
    private var isEnabledForPresentation = false
    private var isActionEnabledForPresentation = false
    private var isAutoSpeakEnabled = false
    private var isCurrentActivePlayback = false
    private var playbackState: SpeechPlaybackState = .idle
    private var activeTabName: String?
    private var presentationLabels: SpeechPresentationLabels = .chatGPT

    var preferredWidth: CGFloat {
        ExternalTabMetrics.systemControlWidth(dockInfluence: dockInfluence)
    }

    var isCurrentlySpeakingForAction: Bool {
        isCurrentActivePlayback && playbackState == .speaking
    }

    var isCurrentlyPausedForAction: Bool {
        isCurrentActivePlayback && playbackState == .paused
    }

    var isStopActionVisible: Bool {
        kind == .stop && isActionEnabledForPresentation
    }

    var displayedPlaybackState: SpeechPlaybackState {
        playbackState
    }

    var isEnabledForSpeechPresentationState: Bool {
        isEnabledForPresentation
    }

    var isActionEnabledForSpeechPresentationState: Bool {
        isActionEnabledForPresentation
    }

    var isAutoSpeakEnabledForPresentation: Bool {
        isAutoSpeakEnabled
    }

    var displayedActiveTabName: String? {
        activeTabName
    }

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = ExternalTabMetrics.tabRadius
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]

        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 13),
            imageView.heightAnchor.constraint(equalToConstant: 13),
        ])
        imageView.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        setAccessibilityRole(.button)
        updatePresentation()
    }

    convenience init() {
        self.init(kind: .readLatest)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return bounds.contains(point) ? self : nil
    }

    override func layout() {
        super.layout()
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    func setDockInfluence(_ influence: CGFloat) {
        dockInfluence = min(max(influence, 0), 1)
    }

    func setHovered(_ hovered: Bool) {
        guard !isHoverInteractionSuspended || !hovered else { return }
        guard isHovered != hovered else { return }
        isHovered = hovered
        updatePresentation()
    }

    func setHoverInteractionSuspended(_ suspended: Bool) {
        isHoverInteractionSuspended = suspended
        if suspended {
            setHovered(false)
        }
    }

    func setSpeechState(
        isEnabled: Bool,
        isActionEnabled: Bool? = nil,
        isAutoSpeakEnabled: Bool,
        playbackState: SpeechPlaybackState,
        isCurrentActivePlayback: Bool,
        activeTabName: String?,
        labels: SpeechPresentationLabels = .chatGPT
    ) {
        self.isEnabledForPresentation = isEnabled
        self.isActionEnabledForPresentation = isActionEnabled ?? isEnabled
        self.isAutoSpeakEnabled = isAutoSpeakEnabled
        self.playbackState = playbackState
        self.isCurrentActivePlayback = isCurrentActivePlayback
        self.activeTabName = activeTabName
        self.presentationLabels = labels
        updatePresentation()
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
        guard isActionEnabledForPresentation else {
            NSSound.beep()
            return
        }
        onActivate?()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    func refreshAppearance() {
        updatePresentation()
    }

    private func updatePresentation() {
        let target = activeTabName ?? "Current Tab"
        let symbol: String
        let label: String
        let tooltip: String

        switch kind {
        case .autoSpeak:
            symbol = isAutoSpeakEnabled ? "speaker.wave.2.fill" : "speaker"
            label = isAutoSpeakEnabled
                ? "\(presentationLabels.autoSpeak) enabled for \(target)"
                : "\(presentationLabels.autoSpeak) \(target)"
            tooltip = isEnabledForPresentation
                ? (isAutoSpeakEnabled
                    ? "Disable Auto Speak This Tab · \(target)"
                    : "Auto Speak This Tab — speaks new responses after they finish · \(target)")
                : presentationLabels == .calibreReader
                    ? "Auto Speak unavailable for Calibre Reader tabs."
                    : "Speech is currently available for ChatGPT tabs."
        case .readLatest:
            switch (isCurrentActivePlayback, playbackState) {
            case (true, .speaking):
                symbol = "pause.fill"
                label = "Pause speech for \(target)"
                tooltip = isEnabledForPresentation
                    ? "Pause Speech · \(target)"
                    : "Speech is currently available for ChatGPT tabs."
            case (true, .paused):
                symbol = "play.fill"
                label = "Resume speech for \(target)"
                tooltip = isEnabledForPresentation
                    ? "Resume Speech · \(target)"
                    : "Speech is currently available for ChatGPT tabs."
            case (true, .starting), (true, .pausing), (true, .resuming):
                symbol = "ellipsis.circle"
                label = "Speech transition in progress for \(target)"
                tooltip = "Speech transition in progress · \(target)"
            default:
                symbol = "play.fill"
                label = "\(presentationLabels.read) \(target)"
                tooltip = isEnabledForPresentation
                    ? (presentationLabels == .calibreReader
                        ? "Read From Current Page · \(target)"
                        : "Read Latest Response From Current Active Tab · \(target)")
                    : presentationLabels == .calibreReader
                        ? "Calibre Reader speech is unavailable for this tab."
                        : "Speech is currently available for ChatGPT tabs."
        }
        case .replay:
            symbol = "arrow.counterclockwise"
            label = "\(presentationLabels.replay) \(target)"
            tooltip = isEnabledForPresentation
                ? (presentationLabels == .calibreReader
                    ? "Replay Current Page · \(target)"
                    : "Replay Latest Response From \(target)")
                : presentationLabels == .calibreReader
                    ? "Calibre Reader speech is unavailable for this tab."
                    : "Speech is currently available for ChatGPT tabs."
        case .stop:
            symbol = "stop.fill"
            label = "Stop speech for \(target)"
            tooltip = isEnabledForPresentation
                ? "Stop Speech · \(target)"
                : presentationLabels == .calibreReader
                    ? "Calibre Reader speech is unavailable for this tab."
                    : "Speech is currently available for ChatGPT tabs."
        }

        let hasActivePlayback = isCurrentActivePlayback
            && playbackState != .idle
        imageView.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: label
        )
        imageView.contentTintColor = isActionEnabledForPresentation
            ? (kind == .stop
                ? .systemRed
                : kind == .readLatest && hasActivePlayback && playbackState == .paused
                    ? .systemOrange
                    : .labelColor)
            : .tertiaryLabelColor
        imageView.alphaValue = isActionEnabledForPresentation ? 1 : 0.45
        toolTip = tooltip
        setAccessibilityLabel(label)

        effectiveAppearance.performAsCurrentDrawingAppearance {
            let fraction: CGFloat
            if !isActionEnabledForPresentation {
                fraction = isHovered ? 0.06 : 0.01
            } else if hasActivePlayback || isAutoSpeakEnabled {
                fraction = isHovered ? 0.16 : 0.08
            } else {
                fraction = isHovered ? 0.10 : 0.02
            }
            layer?.backgroundColor = NSColor.controlBackgroundColor
                .blended(withFraction: fraction, of: .labelColor)?
                .withAlphaComponent(0.94)
                .cgColor
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.30).cgColor
            layer?.borderWidth = 1
        }
    }
}

struct RailOverflowItem: Equatable {
    let slotID: UUID
    let title: String
    let isUnread: Bool

    init(slotID: UUID, title: String, isUnread: Bool = false) {
        self.slotID = slotID
        self.title = title
        self.isUnread = isUnread
    }
}

/// Explicit compact-mode access to Tab views that cannot fit in the rail.
/// This is a real button/menu surface, not a silently hidden action.
@MainActor
final class RailOverflowControl: NSView, RailHoverInteractionOwner {
    var onSelect: ((UUID) -> Void)?
    var onPointerMoved: ((NSEvent) -> Void)?

    private let imageView = NSImageView()
    private let unreadResponseLayer = CAShapeLayer()
    private var items: [RailOverflowItem] = []
    private var trackingAreaReference: NSTrackingArea?
    private var isHoverInteractionSuspended = false

    private static let unreadResponseDiameter: CGFloat = 6

    var menuItems: [RailOverflowItem] { items }
    var isShowingUnreadResponse: Bool { !unreadResponseLayer.isHidden }
    var unreadResponseFrame: NSRect { unreadResponseLayer.frame }
    var unreadResponseColor: NSColor? {
        unreadResponseLayer.fillColor.flatMap(NSColor.init(cgColor:))
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = ExternalTabMetrics.tabRadius
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        unreadResponseLayer.fillColor = NSColor.systemRed.cgColor
        unreadResponseLayer.isHidden = true
        unreadResponseLayer.zPosition = 1
        layer?.addSublayer(unreadResponseLayer)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 13),
            imageView.heightAnchor.constraint(equalToConstant: 13),
        ])
        setAccessibilityRole(.button)
        refreshAppearance()
    }

    convenience init() { self.init(frame: .zero) }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
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
        guard !isHoverInteractionSuspended else { return }
        refreshAppearance(isHovered: true)
        onPointerMoved?(event)
    }

    override func mouseMoved(with event: NSEvent) {
        guard !isHoverInteractionSuspended else { return }
        onPointerMoved?(event)
    }

    override func mouseExited(with event: NSEvent) {
        refreshAppearance(isHovered: false)
        guard !isHoverInteractionSuspended else { return }
        onPointerMoved?(event)
    }

    override func mouseUp(with event: NSEvent) {
        guard !items.isEmpty else {
            NSSound.beep()
            return
        }
        makeMenu().popUp(
            positioning: nil,
            at: NSPoint(x: bounds.maxX, y: bounds.minY),
            in: self
        )
    }

    override func layout() {
        super.layout()
        updateUnreadResponseGeometry()
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        items.forEach { item in
            let menuItem = NSMenuItem(
                title: item.title,
                action: #selector(selectTab(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.representedObject = item.slotID.uuidString
            if item.isUnread {
                menuItem.image = Self.unreadMarkerImage()
                menuItem.setAccessibilityLabel("\(item.title) · Unread response")
            }
            menu.addItem(menuItem)
        }
        return menu
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    func setItems(_ items: [RailOverflowItem]) {
        self.items = items
        let label = items.isEmpty
            ? "More Tabs"
            : "More Tabs (\(items.count) hidden)"
        toolTip = label
        setAccessibilityLabel(label)
        imageView.image = NSImage(
            systemSymbolName: "ellipsis",
            accessibilityDescription: label
        )
        unreadResponseLayer.isHidden = !items.contains(where: \.isUnread)
        setAccessibilityLabel(
            items.contains(where: \.isUnread)
                ? "\(label) · Unread response"
                : label
        )
        refreshAppearance()
    }

    func refreshAppearance(isHovered: Bool = false) {
        imageView.contentTintColor = .labelColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor
                .blended(withFraction: isHovered ? 0.12 : 0.03, of: .labelColor)?
                .withAlphaComponent(0.94)
                .cgColor
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.30).cgColor
            layer?.borderWidth = 1
        }
    }

    func setHoverInteractionSuspended(_ suspended: Bool) {
        isHoverInteractionSuspended = suspended
        if suspended {
            refreshAppearance()
        }
    }

    @objc private func selectTab(_ sender: NSMenuItem) {
        guard let rawID = sender.representedObject as? String,
              let slotID = UUID(uuidString: rawID) else {
            return
        }
        onSelect?(slotID)
    }

    private func updateUnreadResponseGeometry() {
        guard layer != nil else { return }
        let imageFrame = imageView.convert(imageView.bounds, to: self)
        let diameter = Self.unreadResponseDiameter
        let frame = NSRect(
            x: imageFrame.maxX - diameter * 0.75,
            y: imageFrame.maxY - diameter * 0.75,
            width: diameter,
            height: diameter
        )
        unreadResponseLayer.frame = frame
        unreadResponseLayer.path = CGPath(
            ellipseIn: CGRect(origin: .zero, size: frame.size),
            transform: nil
        )
    }

    private static func unreadMarkerImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 6, height: 6)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
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
    var onReadLatestResponse: (() -> Void)?
    var onReplayLatestResponse: (() -> Void)?
    var onToggleAutoSpeak: (() -> Void)?
    var onStopSpeech: (() -> Void)?
    var onTogglePin: (() -> Void)?
    var onActiveTabGeometryChange: (() -> Void)?

    private var profiles: [WebAppProfile] = []
    private var activeTabID: UUID?
    private var residentSlotIDs = Set<UUID>()
    private var unreadSlotIDs = Set<UUID>()
    private var tabViews: [UUID: ExternalWebAppTabView] = [:]
    private var previewOrderIDs: [UUID]?
    private let addControl = AddWebAppControl()
    private let autoSpeakControl = SpeechRailControl(kind: .autoSpeak)
    private let readLatestControl = SpeechRailControl(kind: .readLatest)
    private let replayControl = SpeechRailControl(kind: .replay)
    private let stopControl = SpeechRailControl(kind: .stop)
    private let settingsControl = GlobalSettingsControl()
    private let pinControl = PinPanelControl()
    private let tabOverflowControl = RailOverflowControl()
    private var trackingAreaReference: NSTrackingArea?
    private var pointerLocation: NSPoint?
    private var pointerY: CGFloat?
    private var windowSizeEditingEnabled = true
    private var browserProfileMenuOptions: [BrowserProfileMenuOption] = [.defaultProfile()]
    private var browserProfileAssignmentEnabled = true
    private var browserProfileDuplicationEnabled = true
    private var railVisibilityGeneration = 0
    private(set) var isRailCollapsed = false
    private(set) var isUsingCompactLayout = false
    private(set) var visibleTabIDs: [UUID] = []
    private(set) var overflowTabIDs: [UUID] = []
    private(set) var isModalPresentationActive = false

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        addSubview(addControl)
        addSubview(autoSpeakControl)
        addSubview(readLatestControl)
        addSubview(replayControl)
        addSubview(stopControl)
        addSubview(settingsControl)
        addSubview(pinControl)
        addSubview(tabOverflowControl)
        addControl.onActivate = { [weak self] in self?.onAdd?() }
        autoSpeakControl.onActivate = { [weak self] in self?.onToggleAutoSpeak?() }
        readLatestControl.onActivate = { [weak self] in self?.onReadLatestResponse?() }
        replayControl.onActivate = { [weak self] in self?.onReplayLatestResponse?() }
        stopControl.onActivate = { [weak self] in self?.onStopSpeech?() }
        settingsControl.onActivate = { [weak self] in self?.onSettings?() }
        pinControl.onActivate = { [weak self] in self?.onTogglePin?() }
        tabOverflowControl.onSelect = { [weak self] slotID in self?.onSelect?(slotID) }
        addControl.onPointerMoved = { [weak self] event in
            self?.updateDockPointer(with: event)
        }
        autoSpeakControl.onPointerMoved = { [weak self] event in
            self?.updateDockPointer(with: event)
        }
        readLatestControl.onPointerMoved = { [weak self] event in
            self?.updateDockPointer(with: event)
        }
        replayControl.onPointerMoved = { [weak self] event in
            self?.updateDockPointer(with: event)
        }
        stopControl.onPointerMoved = { [weak self] event in
            self?.updateDockPointer(with: event)
        }
        settingsControl.onPointerMoved = { [weak self] event in
            self?.updateDockPointer(with: event)
        }
        pinControl.onPointerMoved = { [weak self] event in
            self?.updateDockPointer(with: event)
        }
        tabOverflowControl.onPointerMoved = { [weak self] event in
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

    /// Modal sheets can prevent AppKit from delivering the mouse-exit that
    /// normally clears Dock magnification. Suspend every rail hover owner and
    /// clear the pointer-derived authority explicitly so the sheet cannot
    /// inherit a stale expanded Tab. Dismissal deliberately leaves the rail
    /// neutral; a new real pointer event must establish hover again.
    func setModalPresentationActive(_ active: Bool) {
        isModalPresentationActive = active
        pointerLocation = nil
        pointerY = nil
        hoverInteractionOwners.forEach {
            $0.setHoverInteractionSuspended(active)
        }
        if !active {
            synchronizeHoverState(at: nil)
        }
        layoutControls(animated: false, duration: 0)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        for view in subviews.reversed() {
            guard !view.isHidden,
                  view.alphaValue > 0,
                  view.frame.contains(point) else {
                continue
            }
            let localPoint = view.convert(point, from: self)
            if let candidate = view.hitTest(localPoint) {
                return candidate
            }
        }
        return nil
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
            view.setUnreadResponse(unreadSlotIDs.contains(profile.id))
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
        autoSpeakControl.refreshAppearance()
        readLatestControl.refreshAppearance()
        replayControl.refreshAppearance()
        stopControl.refreshAppearance()
        settingsControl.refreshAppearance()
        pinControl.refreshAppearance()
        tabOverflowControl.refreshAppearance()
    }

    func setCollapsed(_ collapsed: Bool, animated: Bool) {
        guard isRailCollapsed != collapsed || !animated else { return }
        isRailCollapsed = collapsed
        railVisibilityGeneration += 1
        let generation = railVisibilityGeneration
        pointerLocation = nil
        pointerY = nil
        synchronizeHoverState(at: nil)

        let controls = railContentViews.filter { !isHiddenByOverflow($0) }
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

    func setUnreadSlotIDs(_ slotIDs: Set<UUID>) {
        unreadSlotIDs = slotIDs
        for (slotID, tab) in tabViews {
            tab.setUnreadResponse(slotIDs.contains(slotID))
        }
        synchronizeOverflowItems()
    }

    func setSpeechPresentation(
        _ presentation: SpeechRailPresentation,
        activeTabName: String? = nil
    ) {
        let currentActive = presentation.activeSlotID
        let isAutoSpeakEnabled = presentation.activeSlotAutoSpeakEnabled
        let isCurrentActivePlayback = currentActive != nil
            && currentActive == presentation.currentSpeakingSlotID
        let targetName = activeTabName ?? currentActive.map { $0.uuidString }
        autoSpeakControl.setSpeechState(
            isEnabled: presentation.capabilities.canAutoSpeak
                && (presentation.activeSlotSupportsSpeech || isAutoSpeakEnabled),
            isAutoSpeakEnabled: isAutoSpeakEnabled,
            playbackState: presentation.playbackState,
            isCurrentActivePlayback: isCurrentActivePlayback,
            activeTabName: targetName,
            labels: presentation.labels
        )
        readLatestControl.setSpeechState(
            isEnabled: (presentation.capabilities.canRead
                && presentation.activeSlotSupportsSpeech) || isCurrentActivePlayback,
            isActionEnabled: isCurrentActivePlayback
                ? ![.starting, .pausing, .resuming].contains(presentation.playbackState)
                : presentation.capabilities.canRead
                    && presentation.activeSlotSupportsSpeech,
            isAutoSpeakEnabled: isAutoSpeakEnabled,
            playbackState: presentation.playbackState,
            isCurrentActivePlayback: isCurrentActivePlayback,
            activeTabName: targetName,
            labels: presentation.labels
        )
        replayControl.setSpeechState(
            isEnabled: (presentation.capabilities.canReplay
                && presentation.activeSlotSupportsSpeech) || isCurrentActivePlayback,
            isActionEnabled: (presentation.capabilities.canReplay
                && presentation.activeSlotSupportsSpeech) || isCurrentActivePlayback,
            isAutoSpeakEnabled: isAutoSpeakEnabled,
            playbackState: presentation.playbackState,
            isCurrentActivePlayback: isCurrentActivePlayback,
            activeTabName: targetName,
            labels: presentation.labels
        )
        stopControl.setSpeechState(
            isEnabled: (isCurrentActivePlayback && presentation.playbackState != .idle)
                || presentation.hasActiveSourceSession,
            isActionEnabled: (isCurrentActivePlayback && presentation.playbackState != .idle)
                || presentation.hasActiveSourceSession,
            isAutoSpeakEnabled: isAutoSpeakEnabled,
            playbackState: presentation.playbackState,
            isCurrentActivePlayback: isCurrentActivePlayback,
            activeTabName: targetName,
            labels: presentation.labels
        )
        for tab in tabViews.values {
            tab.setSpeechState(
                isAutoSpeakSource: presentation.autoSpeakSlotIDs.contains(tab.slotID),
                playbackState: tab.slotID == presentation.currentSpeakingSlotID
                    ? presentation.playbackState
                    : .idle
            )
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
              tab.superview != nil,
              !tab.isHidden,
              !tab.frame.isEmpty else {
            return nil
        }
        return tab.convert(tab.bounds, to: ancestor)
    }

    /// Movement may use uncovered rail gaps, but every visible Tab/rail
    /// control owns its complete animated rectangle. Returning these frames in
    /// the perimeter view's coordinate space keeps cursor, hit testing, and
    /// the acquisition surface aligned while Dock magnification runs.
    func movementExclusionRects(in ancestor: NSView) -> [NSRect] {
        return railContentViews.compactMap { view in
            guard !view.isHidden, view.superview === self else { return nil }
            let rect = view.convert(view.bounds, to: ancestor)
            return rect.isEmpty ? nil : rect
        }
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

    var replayControlFrame: NSRect {
        replayControl.frame
    }

    var stopControlFrame: NSRect {
        stopControl.frame
    }

    var tabOverflowControlFrame: NSRect {
        tabOverflowControl.frame
    }

    var overflowMenuItems: [RailOverflowItem] {
        tabOverflowControl.menuItems
    }

    var overflowControlAccessibilityLabel: String? {
        tabOverflowControl.accessibilityLabel()
    }

#if DEBUG
    /// Test-only access to the configured control callback. This intentionally
    /// forwards through the same closure that a real rail/overflow click uses;
    /// it does not duplicate selection or acknowledgement logic.
    func debugInvokeOverflowSelection(slotID: UUID) -> Bool {
        guard overflowTabIDs.contains(slotID) else { return false }
        tabOverflowControl.onSelect?(slotID)
        return true
    }
#endif

    private var railContentViews: [NSView] {
        Array(tabViews.values)
            + [
                addControl, autoSpeakControl, readLatestControl, replayControl,
                stopControl, settingsControl, pinControl, tabOverflowControl,
            ]
    }

    private func isHiddenByOverflow(_ view: NSView) -> Bool {
        if let tab = view as? ExternalWebAppTabView {
            return overflowTabIDs.contains(tab.slotID)
        }
        return view === tabOverflowControl && overflowTabIDs.isEmpty
    }

    private func finishRailVisibility(generation: Int, collapsed: Bool) {
        guard generation == railVisibilityGeneration else { return }
        railContentViews.forEach {
            $0.alphaValue = collapsed ? 0 : 1
            $0.isHidden = collapsed || isHiddenByOverflow($0)
        }
        onActiveTabGeometryChange?()
    }

    private func makeTabView(for id: UUID) -> ExternalWebAppTabView {
        let view = ExternalWebAppTabView(slotID: id)
        view.setHoverInteractionSuspended(isModalPresentationActive)
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
        guard !isModalPresentationActive else { return }
        let location = convert(event.locationInWindow, from: nil)
        pointerLocation = location
        pointerY = location.y
        synchronizeHoverState(at: location)
        layoutControls(animated: true, duration: ExternalTabMetrics.dockMotionDuration)
    }

    private func synchronizeHoverState(at location: NSPoint?) {
        guard !isRailCollapsed, !isModalPresentationActive else { return }
        for tab in tabViews.values {
            tab.setHovered(location.map { tab.frame.contains($0) } ?? false)
        }
        addControl.setHovered(location.map { addControl.frame.contains($0) } ?? false)
        autoSpeakControl.setHovered(
            location.map { autoSpeakControl.frame.contains($0) } ?? false
        )
        readLatestControl.setHovered(
            location.map { readLatestControl.frame.contains($0) } ?? false
        )
        replayControl.setHovered(
            location.map { replayControl.frame.contains($0) } ?? false
        )
        stopControl.setHovered(
            location.map { stopControl.frame.contains($0) } ?? false
        )
        settingsControl.setHovered(
            location.map { settingsControl.frame.contains($0) } ?? false
        )
        pinControl.setHovered(location.map { pinControl.frame.contains($0) } ?? false)
        if let location {
            tabOverflowControl.refreshAppearance(
                isHovered: tabOverflowControl.frame.contains(location)
            )
        } else {
            tabOverflowControl.refreshAppearance()
        }
    }

    private func layoutControls(animated: Bool, duration: TimeInterval) {
        let updateFrames = {
            let ids = self.previewOrderIDs ?? self.profiles.map(\.id)
            let standardTabEnd = self.tabEndY(for: ids.count)
            let standardControlsTop = max(
                self.bounds.height
                    - ExternalTabMetrics.systemControlBottomOffset
                    - ExternalTabMetrics.systemControlHeight
                    - 5 * (ExternalTabMetrics.systemControlHeight + ExternalTabMetrics.systemControlGap),
                0
            )
            let compact = standardTabEnd
                + ExternalTabMetrics.addHeight
                + ExternalTabMetrics.addGap
                > standardControlsTop
            self.isUsingCompactLayout = compact

            var visibleIDs = ids
            if compact {
                let compactControlsTop = self.compactControlsTopY
                let maximumAddBottom = max(
                    compactControlsTop - ExternalTabMetrics.addGap,
                    0
                )
                var visibleCount = ids.count
                while visibleCount > 0 {
                    let hasOverflow = visibleCount < ids.count
                    let candidateAddY = self.tabEndY(for: visibleCount)
                        + (hasOverflow
                            ? ExternalTabMetrics.systemControlHeight + ExternalTabMetrics.addGap
                            : 0)
                    if candidateAddY + ExternalTabMetrics.addHeight <= maximumAddBottom {
                        break
                    }
                    visibleCount -= 1
                }
                visibleIDs = Array(ids.prefix(visibleCount))

                // Selecting a hidden Tab must make that Tab visible in compact
                // mode instead of leaving the selected page behind the menu.
                if let activeTabID = self.activeTabID,
                   ids.contains(activeTabID),
                   !visibleIDs.contains(activeTabID),
                   let replacement = visibleIDs.last {
                    visibleIDs[visibleIDs.count - 1] = activeTabID
                    if replacement == activeTabID {
                        visibleIDs = ids.filter { visibleIDs.contains($0) }
                    }
                }
                visibleIDs = ids.filter { visibleIDs.contains($0) }
            }

            let visibleSet = Set(visibleIDs)
            let overflowIDs = ids.filter { !visibleSet.contains($0) }
            self.visibleTabIDs = visibleIDs
            self.overflowTabIDs = overflowIDs
            self.synchronizeOverflowItems()

            var y = ExternalTabMetrics.topOffset
            for id in ids {
                guard let tab = self.tabViews[id] else { continue }
                guard visibleSet.contains(id) else {
                    tab.setDockInfluence(0)
                    tab.isHidden = self.isRailCollapsed || overflowIDs.contains(id)
                    self.setFrame(.zero, for: tab, animated: animated)
                    continue
                }
                tab.isHidden = self.isRailCollapsed
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

            if !visibleIDs.isEmpty {
                y += ExternalTabMetrics.addGap - ExternalTabMetrics.tabGap
            }

            if !overflowIDs.isEmpty {
                let overflowFrame = self.attachedFrame(
                    preferredWidth: ExternalTabMetrics.systemControlNormalWidth,
                    y: y,
                    height: ExternalTabMetrics.systemControlHeight
                )
                self.setFrame(
                    overflowFrame,
                    for: self.tabOverflowControl,
                    animated: animated
                )
                self.tabOverflowControl.isHidden = self.isRailCollapsed
                y += ExternalTabMetrics.systemControlHeight + ExternalTabMetrics.addGap
            } else {
                self.tabOverflowControl.isHidden = true
                self.setFrame(.zero, for: self.tabOverflowControl, animated: animated)
            }

            let addCenterY = y + ExternalTabMetrics.addHeight / 2
            let addInfluence = compact
                ? 0
                : self.pointerY.map {
                    ExternalTabMetrics.dockInfluence(forDistance: $0 - addCenterY)
                } ?? 0
            self.addControl.setDockInfluence(addInfluence)

            let addFrame = self.attachedFrame(
                preferredWidth: self.addControl.preferredWidth,
                y: y,
                height: ExternalTabMetrics.addHeight
            )
            self.setFrame(addFrame, for: self.addControl, animated: animated)

            if compact {
                self.layoutCompactSystemControls(animated: animated)
            } else {
                self.layoutStandardSystemControls(animated: animated)
            }
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

    private func synchronizeOverflowItems() {
        tabOverflowControl.setItems(
            overflowTabIDs.compactMap { id in
                guard let profile = profiles.first(where: { $0.id == id }) else {
                    return nil
                }
                return RailOverflowItem(
                    slotID: id,
                    title: profile.name,
                    isUnread: unreadSlotIDs.contains(id)
                )
            }
        )
    }

    private var hoverInteractionOwners: [RailHoverInteractionOwner] {
        var owners: [RailHoverInteractionOwner] = Array(tabViews.values)
        owners.append(contentsOf: [
            addControl,
            autoSpeakControl,
            readLatestControl,
            replayControl,
            stopControl,
            settingsControl,
            pinControl,
            tabOverflowControl,
        ])
        return owners
    }

    private var compactControlsTopY: CGFloat {
        max(
            bounds.height
                - ExternalTabMetrics.systemControlBottomOffset
                - ExternalTabMetrics.systemControlHeight
                - 2 * (ExternalTabMetrics.systemControlHeight + ExternalTabMetrics.systemControlGap),
            0
        )
    }

    private func tabEndY(for count: Int) -> CGFloat {
        guard count > 0 else { return ExternalTabMetrics.topOffset }
        return ExternalTabMetrics.topOffset
            + CGFloat(count) * (ExternalTabMetrics.tabHeight + ExternalTabMetrics.tabGap)
            + ExternalTabMetrics.addGap
            - ExternalTabMetrics.tabGap
    }

    private func setDockInfluence(_ influence: CGFloat, for view: NSView) {
        switch view {
        case let control as SpeechRailControl:
            control.setDockInfluence(influence)
        case let control as AddWebAppControl:
            control.setDockInfluence(influence)
        case let control as GlobalSettingsControl:
            control.setDockInfluence(influence)
        case let control as PinPanelControl:
            control.setDockInfluence(influence)
        default:
            break
        }
    }

    private func preferredWidth(for view: NSView) -> CGFloat {
        switch view {
        case let control as SpeechRailControl:
            return control.preferredWidth
        case let control as AddWebAppControl:
            return control.preferredWidth
        case let control as GlobalSettingsControl:
            return control.preferredWidth
        case let control as PinPanelControl:
            return control.preferredWidth
        default:
            return ExternalTabMetrics.systemControlNormalWidth
        }
    }

    private func layoutStandardSystemControls(animated: Bool) {
        var y = max(
            bounds.height
                - ExternalTabMetrics.systemControlBottomOffset
                - ExternalTabMetrics.systemControlHeight,
            0
        )
        let controls: [NSView] = [
            pinControl, settingsControl, stopControl, replayControl,
            readLatestControl, autoSpeakControl,
        ]
        for control in controls {
            let centerY = y + ExternalTabMetrics.systemControlHeight / 2
            let influence = pointerY.map {
                ExternalTabMetrics.dockInfluence(forDistance: $0 - centerY)
            } ?? 0
            setDockInfluence(influence, for: control)
            setFrame(
                attachedFrame(
                    preferredWidth: preferredWidth(for: control),
                    y: y,
                    height: ExternalTabMetrics.systemControlHeight
                ),
                for: control,
                animated: animated
            )
            y = max(
                y
                    - ExternalTabMetrics.systemControlGap
                    - ExternalTabMetrics.systemControlHeight,
                0
            )
        }
    }

    private func layoutCompactSystemControls(animated: Bool) {
        let width = min(
            ExternalTabMetrics.systemControlNormalWidth,
            max((bounds.width - ExternalTabMetrics.systemControlGap) / 2, 0)
        )
        let controls: [NSView] = [
            autoSpeakControl, readLatestControl, replayControl,
            stopControl, settingsControl, pinControl,
        ]
        for (index, control) in controls.enumerated() {
            setDockInfluence(0, for: control)
            let row = index / 2
            let column = index % 2
            let frame = NSRect(
                x: CGFloat(column) * (width + ExternalTabMetrics.systemControlGap),
                y: compactControlsTopY
                    + CGFloat(row)
                        * (ExternalTabMetrics.systemControlHeight + ExternalTabMetrics.systemControlGap),
                width: width,
                height: ExternalTabMetrics.systemControlHeight
            )
            setFrame(frame, for: control, animated: animated)
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
        bounds.contains(point) ? self : nil
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
    typealias DataLoader = @MainActor @Sendable (
        URLRequest
    ) async throws -> (Data, URLResponse)

    static let shared = WebsiteFaviconProvider()

    private let dataLoader: DataLoader
    private var cache: [String: NSImage] = [:]
    private var failedOrigins = Set<String>()

    init(
        dataLoader: @escaping DataLoader = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.dataLoader = dataLoader
    }

    static func originKey(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased() else { return nil }
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }

    static func faviconURL(for url: URL) -> URL? {
        iconURL(path: "/favicon.ico", for: url)
    }

    static func fallbackFaviconURLs(for url: URL) -> [URL] {
        [
            "/favicon.ico",
            "/favicon.png",
            "/favicon.svg",
            "/apple-touch-icon.png",
            "/apple-touch-icon-precomposed.png",
        ].compactMap { iconURL(path: $0, for: url) }
    }

    /// Extracts the normal HTML favicon declarations without requiring a
    /// third-party favicon service. The parser is intentionally limited to
    /// link elements and http(s) URLs; it never executes page content.
    static func discoveredFaviconURLs(
        in html: String,
        baseURL: URL
    ) -> [URL] {
        let linkPattern = #"(?is)<link\b[^>]*>"#
        let attributePattern = #"(?i)([A-Za-z][A-Za-z0-9:_-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
        guard let linkRegex = try? NSRegularExpression(pattern: linkPattern),
              let attributeRegex = try? NSRegularExpression(pattern: attributePattern) else {
            return []
        }

        let baseHref = linkAttribute(
            named: "href",
            in: firstTag(matching: #"(?is)<base\b[^>]*>"#, html: html),
            using: attributeRegex
        )
        let documentBaseURL = baseHref
            .flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }
            ?? baseURL

        var result: [URL] = []
        var seen = Set<String>()
        let htmlRange = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in linkRegex.matches(in: html, range: htmlRange) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])
            let attributes = linkAttributes(in: tag, using: attributeRegex)
            let relTokens = (attributes["rel"] ?? "")
                .lowercased()
                .split { $0.isWhitespace }
                .map(String.init)
            let isIcon = relTokens.contains("icon")
                || relTokens.contains("apple-touch-icon")
                || relTokens.contains("apple-touch-icon-precomposed")
                || relTokens.contains("mask-icon")
            guard isIcon,
                  let href = attributes["href"],
                  let candidate = URL(string: href, relativeTo: documentBaseURL)?.absoluteURL,
                  isHTTPURL(candidate) else {
                continue
            }
            let key = candidate.absoluteString
            guard seen.insert(key).inserted else { continue }
            result.append(candidate)
        }
        return result
    }

    func load(for url: URL, completion: @escaping (NSImage?) -> Void) {
        guard let key = Self.originKey(for: url) else {
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

            // Keep the inexpensive and conventional endpoint first. Some
            // modern sites, including Gemini, return an empty HTML response
            // from /favicon.ico even though their real icon is declared in
            // the document head.
            if let faviconURL = Self.faviconURL(for: url),
               let image = await self.fetchImage(from: faviconURL) {
                self.cache[key] = image
                completion(image)
                return
            }

            // Read only the page markup and inspect <link rel="icon">. This
            // supports absolute/relative, PNG/SVG and cross-origin CDN icons
            // without executing JavaScript or sharing website cookies.
            if let (html, response) = await self.fetchPageHTML(for: url) {
                let pageURL = response.url ?? url
                let htmlCandidates = Self.discoveredFaviconURLs(
                    in: html,
                    baseURL: pageURL
                )
                for candidate in htmlCandidates {
                    if let image = await self.fetchImage(from: candidate) {
                        self.cache[key] = image
                        completion(image)
                        return
                    }
                }
            }

            // A few older sites omit HTML declarations but expose one of
            // these conventional names. Keep these after HTML discovery so a
            // slow or unreachable fallback endpoint cannot delay normal pages.
            for candidate in Self.fallbackFaviconURLs(for: url).dropFirst() {
                if let image = await self.fetchImage(from: candidate) {
                    self.cache[key] = image
                    completion(image)
                    return
                }
            }

            failedOrigins.insert(key)
            completion(nil)
        }
    }

    private static func iconURL(path: String, for url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme != nil,
              components.host != nil else { return nil }
        components.path = path
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func isHTTPURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              url.host != nil else { return false }
        return scheme == "http" || scheme == "https"
    }

    private static func firstTag(matching pattern: String, html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: html,
                range: NSRange(html.startIndex..<html.endIndex, in: html)
              ),
              let range = Range(match.range, in: html) else {
            return nil
        }
        return String(html[range])
    }

    private static func linkAttribute(
        named name: String,
        in tag: String?,
        using regex: NSRegularExpression
    ) -> String? {
        guard let tag else { return nil }
        return linkAttributes(in: tag, using: regex)[name.lowercased()]
    }

    private static func linkAttributes(
        in tag: String,
        using regex: NSRegularExpression
    ) -> [String: String] {
        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        var attributes: [String: String] = [:]
        for match in regex.matches(in: tag, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: tag),
                  let value = attributeValue(from: match, in: tag) else {
                continue
            }
            attributes[String(tag[nameRange]).lowercased()] = value
        }
        return attributes
    }

    private static func attributeValue(
        from match: NSTextCheckingResult,
        in tag: String
    ) -> String? {
        for index in 2...4 {
            let range = match.range(at: index)
            guard range.location != NSNotFound,
                  let valueRange = Range(range, in: tag) else { continue }
            return String(tag[valueRange])
        }
        return nil
    }

    private func fetchImage(from url: URL) async -> NSImage? {
        guard Self.isHTTPURL(url) else { return nil }
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 8
        request.setValue(
            "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
        do {
            let (data, response) = try await dataLoader(request)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                return nil
            }
            guard let image = NSImage(data: data) else { return nil }
            image.size = NSSize(width: 16, height: 16)
            return image
        } catch {
            return nil
        }
    }

    private func fetchPageHTML(for url: URL) async -> (String, URLResponse)? {
        guard Self.isHTTPURL(url) else { return nil }
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        // Favicon discovery does not need query tokens or fragments. Avoid
        // replaying page-specific tracking/session parameters through the
        // auxiliary URLSession request.
        components.query = nil
        components.fragment = nil
        guard let pageURL = components.url else { return nil }
        var request = URLRequest(url: pageURL)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 8
        request.setValue(
            "text/html,application/xhtml+xml;q=0.9,*/*;q=0.1",
            forHTTPHeaderField: "Accept"
        )
        do {
            let (data, response) = try await dataLoader(request)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                return nil
            }
            guard let html = String(data: data, encoding: .utf8) else { return nil }
            return (html, response)
        } catch {
            return nil
        }
    }
}

@MainActor
final class ExternalWebAppTabView: NSView, RailHoverInteractionOwner {
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
    private let speechBadgeView = NSImageView()
    private let shapeLayer = CAShapeLayer()
    private let unreadResponseLayer = CAShapeLayer()
    private var trackingAreaReference: NSTrackingArea?
    private var isActive = false
    private var isResident = false
    private var isHovered = false
    private var isHoverInteractionSuspended = false
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
    private var isAutoSpeakSource = false
    private var isUnreadResponse = false
    private var speechPlaybackState: SpeechPlaybackState = .idle

    private static let grayscaleContext = CIContext(options: nil)
    private static let unreadResponseDiameter: CGFloat = 6

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
    var isShowingUnreadResponse: Bool { !unreadResponseLayer.isHidden }
    var unreadResponseFrame: NSRect { unreadResponseLayer.frame }
    var iconFrame: NSRect { iconView.frame }
    var unreadResponseColor: NSColor? {
        unreadResponseLayer.fillColor.flatMap(NSColor.init(cgColor:))
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
    var isShowingAutoSpeakBadge: Bool { isAutoSpeakSource }
    var isShowingSpeakingBadge: Bool { speechPlaybackState == .speaking }
    var isShowingPausedSpeechBadge: Bool { speechPlaybackState == .paused }

    init(slotID: UUID) {
        self.slotID = slotID
        super.init(frame: .zero)

        wantsLayer = true
        layer?.masksToBounds = false
        layer?.addSublayer(shapeLayer)
        unreadResponseLayer.fillColor = NSColor.systemRed.cgColor
        unreadResponseLayer.isHidden = true
        unreadResponseLayer.zPosition = 1
        layer?.addSublayer(unreadResponseLayer)

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

        speechBadgeView.imageScaling = .scaleProportionallyUpOrDown
        speechBadgeView.isHidden = true
        speechBadgeView.setContentHuggingPriority(.required, for: .horizontal)
        speechBadgeView.setContentHuggingPriority(.required, for: .vertical)
        speechBadgeView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(speechBadgeView)

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
            speechBadgeView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            speechBadgeView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            speechBadgeView.widthAnchor.constraint(equalToConstant: 10),
            speechBadgeView.heightAnchor.constraint(equalToConstant: 10),
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
        bounds.contains(point) ? self : nil
    }

    override func layout() {
        super.layout()
        // Rail magnification animates the tab's width. Refresh cursor rects so
        // the registered arrow rect always covers the expanded row.
        window?.invalidateCursorRects(for: self)
        updateShape()
        updateUnreadResponseGeometry()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        // A tab's own cursor rect must win so tab hits never advertise window
        // dragging. Its complete animated frame is also excluded from the
        // shell movement geometry, so magnification never turns a Tab into a
        // move target.
        addCursorRect(bounds, cursor: .arrow)
    }

    func setDockInfluence(_ influence: CGFloat) {
        dockInfluence = min(max(influence, 0), 1)
    }

    func setHovered(_ hovered: Bool) {
        guard !isHoverInteractionSuspended || !hovered else { return }
        guard isHovered != hovered else { return }
        isHovered = hovered
        label.isHidden = !hovered
        updateAppearance()
    }

    func setHoverInteractionSuspended(_ suspended: Bool) {
        isHoverInteractionSuspended = suspended
        if suspended {
            setHovered(false)
        }
    }

    func setResident(_ resident: Bool) {
        guard isResident != resident else { return }
        isResident = resident
        updateAppearance()
        updateRuntimeToolTip()
    }

    func setUnreadResponse(_ unread: Bool) {
        guard isUnreadResponse != unread else { return }
        isUnreadResponse = unread
        unreadResponseLayer.isHidden = !unread
        updateAccessibilityLabel()
    }

    func setSpeechState(
        isAutoSpeakSource: Bool,
        playbackState: SpeechPlaybackState
    ) {
        guard self.isAutoSpeakSource != isAutoSpeakSource
            || self.speechPlaybackState != playbackState else {
            return
        }
        self.isAutoSpeakSource = isAutoSpeakSource
        self.speechPlaybackState = playbackState
        updateSpeechBadge()
        updateAccessibilityLabel()
    }

    func setSpeechState(isAutoSpeakSource: Bool, isCurrentlySpeaking: Bool) {
        setSpeechState(
            isAutoSpeakSource: isAutoSpeakSource,
            playbackState: isCurrentlySpeaking ? .speaking : .idle
        )
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
        guard !isHoverInteractionSuspended else { return }
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
        let activeBackground = Self.activeBackgroundColor(
            profileColor: browserProfileColor.appKitColor
        )
        label.textColor = isActive
            ? Self.activeForegroundColor(for: activeBackground)
            : .secondaryLabelColor
        applyIconAppearance(activeBackground: activeBackground)
        updateShape(activeBackground: activeBackground)
        unreadResponseLayer.fillColor = NSColor.systemRed.cgColor
        updateUnreadResponseGeometry()
    }

    static func activeBackgroundColor(
        profileColor: NSColor,
        baseColor: NSColor = .windowBackgroundColor
    ) -> NSColor {
        baseColor.blended(withFraction: 0.80, of: profileColor) ?? profileColor
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

        // The final 80% profile-color blend keeps bright Yellow readable with
        // dark text while dark Graphite and Purple remain readable with light
        // text.
        return luminance >= 0.35 ? .black : .white
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
        updateAccessibilityLabel()
    }

    private func updateAccessibilityLabel() {
        var parts = [displayedPresentationTitle]
        if isUnreadResponse {
            parts.append("Unread response")
        }
        if isAutoSpeakSource {
            parts.append("Auto Speak enabled")
        }
        switch speechPlaybackState {
        case .speaking:
            parts.append("Currently speaking")
        case .paused:
            parts.append("Speech paused")
        case .starting:
            parts.append("Speech starting")
        case .pausing:
            parts.append("Speech pausing")
        case .resuming:
            parts.append("Speech resuming")
        case .idle:
            break
        }
        setAccessibilityLabel(parts.joined(separator: " · "))
    }

    private func updateSpeechBadge() {
        let visible = isAutoSpeakSource || speechPlaybackState != .idle
        speechBadgeView.isHidden = !visible
        guard visible else { return }

        let symbol: String
        let description: String
        let tint: NSColor
        switch speechPlaybackState {
        case .starting, .resuming:
            symbol = "speaker.wave.2"
            description = "Speech transition in progress"
            tint = .systemOrange
        case .pausing:
            symbol = "pause.fill"
            description = "Speech pausing"
            tint = .systemOrange
        case .speaking:
            symbol = "speaker.wave.2.fill"
            description = "Currently speaking"
            tint = .systemRed
        case .paused:
            symbol = "pause.fill"
            description = "Speech paused"
            tint = .systemOrange
        case .idle:
            symbol = "speaker.wave.2"
            description = "Auto Speak enabled"
            tint = .controlAccentColor
        }
        speechBadgeView.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: description
        )
        speechBadgeView.contentTintColor = tint
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

    private func applyIconAppearance(activeBackground: NSColor? = nil) {
        let base = sourceIcon ?? Self.fallbackIcon()
        let resolvedActiveBackground = activeBackground
            ?? Self.activeBackgroundColor(profileColor: browserProfileColor.appKitColor)
        let templateTint = isActive
            ? Self.activeForegroundColor(for: resolvedActiveBackground)
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

    private func updateShape(activeBackground: NSColor? = nil) {
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
            let resolvedActiveBackground = activeBackground
                ?? Self.activeBackgroundColor(profileColor: browserProfileColor.appKitColor)
            shapeLayer.fillColor = resolvedActiveBackground.cgColor
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

    private func updateUnreadResponseGeometry() {
        guard layer != nil else { return }
        let iconFrame = iconView.convert(iconView.bounds, to: self)
        let diameter = Self.unreadResponseDiameter
        let frame = NSRect(
            x: iconFrame.maxX - diameter * 0.75,
            y: iconFrame.maxY - diameter * 0.75,
            width: diameter,
            height: diameter
        )
        unreadResponseLayer.frame = frame
        unreadResponseLayer.path = CGPath(
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
final class AddWebAppControl: NSView, RailHoverInteractionOwner {
    var onActivate: (() -> Void)?
    var onPointerMoved: ((NSEvent) -> Void)?

    private let imageView = NSImageView()
    private var trackingAreaReference: NSTrackingArea?
    private var isHovered = false
    private var isHoverInteractionSuspended = false
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
        bounds.contains(point) ? self : nil
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
        guard !isHoverInteractionSuspended || !hovered else { return }
        guard isHovered != hovered else { return }
        isHovered = hovered
        updateAppearance()
    }

    func setHoverInteractionSuspended(_ suspended: Bool) {
        isHoverInteractionSuspended = suspended
        if suspended {
            setHovered(false)
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
final class PinPanelControl: NSView, RailHoverInteractionOwner {
    var onActivate: (() -> Void)?
    var onPointerMoved: ((NSEvent) -> Void)?

    private let imageView = NSImageView()
    private var trackingAreaReference: NSTrackingArea?
    private var isHovered = false
    private var isHoverInteractionSuspended = false
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
        bounds.contains(point) ? self : nil
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
        guard !isHoverInteractionSuspended || !hovered else { return }
        guard isHovered != hovered else { return }
        isHovered = hovered
        updateAppearance()
    }

    func setHoverInteractionSuspended(_ suspended: Bool) {
        isHoverInteractionSuspended = suspended
        if suspended {
            setHovered(false)
        }
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
final class GlobalSettingsControl: NSView, RailHoverInteractionOwner {
    var onActivate: (() -> Void)?
    var onPointerMoved: ((NSEvent) -> Void)?

    private let imageView = NSImageView()
    private var trackingAreaReference: NSTrackingArea?
    private var isHovered = false
    private var isHoverInteractionSuspended = false
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
        bounds.contains(point) ? self : nil
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
        guard !isHoverInteractionSuspended || !hovered else { return }
        guard isHovered != hovered else { return }
        isHovered = hovered
        updateAppearance()
    }

    func setHoverInteractionSuspended(_ suspended: Bool) {
        isHoverInteractionSuspended = suspended
        if suspended {
            setHovered(false)
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
