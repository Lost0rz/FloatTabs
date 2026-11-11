import AppKit
import CoreImage
import CryptoKit
import Foundation
import ImageIO
import KeyboardShortcuts
import QuartzCore
import WebKit

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
    static let activeWidth: CGFloat = 76
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

    static func tabSurfacePath(in bounds: CGRect) -> CGPath {
        let radius = tabRadius
        let path = CGMutablePath()
        path.move(to: CGPoint(x: bounds.maxX, y: bounds.minY))
        path.addLine(to: CGPoint(x: bounds.minX + radius, y: bounds.minY))
        path.addQuadCurve(
            to: CGPoint(x: bounds.minX, y: bounds.minY + radius),
            control: CGPoint(x: bounds.minX, y: bounds.minY)
        )
        path.addLine(to: CGPoint(x: bounds.minX, y: bounds.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: bounds.minX + radius, y: bounds.maxY),
            control: CGPoint(x: bounds.minX, y: bounds.maxY)
        )
        path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY))
        path.closeSubpath()
        return path
    }
}

enum ExternalTabSurfacePalette {
    static func neutralFill(isHovered: Bool) -> NSColor {
        NSColor.controlBackgroundColor.withAlphaComponent(isHovered ? 0.96 : 0.82)
    }

    static func tabFill(
        isUnread: Bool,
        isHovered: Bool,
        style: TabAttentionStyle = .dot
    ) -> NSColor {
        // Attention is projected on the separate shared effect renderer. The
        // production Tab surface stays geometrically and visually neutral.
        _ = isUnread
        _ = style
        return neutralFill(isHovered: isHovered)
    }

    static func attentionForeground(for background: NSColor) -> NSColor {
        let luminance = relativeLuminance(background)
        let blackContrast = (luminance + 0.05) / 0.05
        let whiteContrast = 1.05 / (luminance + 0.05)
        return blackContrast >= whiteContrast ? .black : .white
    }

    private static func relativeLuminance(_ color: NSColor) -> CGFloat {
        guard let color = color.usingColorSpace(.sRGB) else { return 0 }
        func linearized(_ component: CGFloat) -> CGFloat {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearized(color.redComponent)
            + 0.7152 * linearized(color.greenComponent)
            + 0.0722 * linearized(color.blueComponent)
    }
}

enum AttentionStyleEffect: String, CaseIterable, Identifiable, Equatable {
    case dot
    case beacon
    case orbit
    case pulse

    var id: String { rawValue }
}

enum TabAttentionPalette: String, CaseIterable, Identifiable, Equatable {
    case red
    case amber
    case blue
    case violet
    case mint
    case spectrum

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .red: "Red"
        case .amber: "Amber"
        case .blue: "Blue"
        case .violet: "Violet"
        case .mint: "Mint"
        case .spectrum: "Spectrum"
        }
    }

    var colors: [NSColor] {
        switch self {
        case .red: [.systemRed, .systemPink]
        case .amber: [.systemOrange, .systemYellow]
        case .blue: [.systemBlue, .systemTeal]
        case .violet: [.systemPurple, .systemPink]
        case .mint: [.systemTeal, .systemGreen]
        case .spectrum:
            [
                .systemRed, .systemOrange, .systemYellow, .systemGreen,
                .systemTeal, .systemBlue, .systemPurple, .systemPink,
            ]
        }
    }

    var representativeColor: NSColor {
        switch self {
        case .spectrum: .systemTeal
        default: colors.first ?? .systemRed
        }
    }

    static func compatibilityPalette(for previousStyle: String?) -> TabAttentionPalette? {
        return switch previousStyle {
        case "signal": .red
        case "ember": .amber
        case "aurora": .violet
        case "spectrum": .spectrum
        default: nil
        }
    }
}

enum TabAttentionStyle: String, CaseIterable, Identifiable, Equatable {
    case dot
    case beacon
    case orbit
    case pulse

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dot: "Dot"
        case .beacon: "Beacon"
        case .orbit: "Orbit"
        case .pulse: "Pulse"
        }
    }

    var effect: AttentionStyleEffect {
        switch self {
        case .dot: .dot
        case .beacon: .beacon
        case .orbit: .orbit
        case .pulse: .pulse
        }
    }

    var configuration: AttentionStyleConfiguration { configuration(for: .red) }

    func configuration(for requestedPalette: TabAttentionPalette) -> AttentionStyleConfiguration {
        let palette = self == .dot ? TabAttentionPalette.red : requestedPalette
        let colors = palette.colors
        let primary = palette.representativeColor
        let cycle: TimeInterval?
        switch self {
        case .dot: cycle = nil
        case .beacon: cycle = 4.0
        case .orbit: cycle = 5.2
        case .pulse: cycle = 4.4
        }
        return AttentionStyleConfiguration(
            effect: effect,
            palette: palette,
            paletteRole: "\(rawValue)-\(palette.rawValue)",
            colors: colors,
            representativeColor: primary,
            foregroundColor: ExternalTabSurfacePalette.attentionForeground(
                for: NSColor.controlBackgroundColor
            ),
            animationCycleDuration: cycle,
            gentlyBreathes: self == .pulse
        )
    }

    static func compatibleStoredValue(_ raw: String?) -> TabAttentionStyle {
        guard let raw else { return .dot }
        if let style = TabAttentionStyle(rawValue: raw) { return style }
        return switch raw {
        case "signal": .dot
        case "ember": .pulse
        case "aurora": .pulse
        case "spectrum": .pulse
        case "halo": .pulse
        case "sweep": .orbit
        default: .dot
        }
    }
}

struct AttentionStyleConfiguration {
    let effect: AttentionStyleEffect
    let palette: TabAttentionPalette
    let paletteRole: String
    let colors: [NSColor]
    let representativeColor: NSColor
    let foregroundColor: NSColor
    let animationCycleDuration: TimeInterval?
    let gentlyBreathes: Bool
}

enum AttentionSurfaceGeometry: Equatable {
    case railTab
    case overflowControl
    case settingsPreview
}

/// Shared layer renderer for unread Tabs, overflow, and Settings previews.
/// Effects stay inside a fixed surface; Orbit rotates color around a continuous
/// internal perimeter while Pulse breathes across the whole surface.
@MainActor
final class AttentionStyleSurfaceView: NSView {
    private static let beaconAnimationKey = "FloatTabs.attentionStyle.beacon"
    private static let orbitAnimationKey = "FloatTabs.attentionStyle.orbit"
    private static let pulseAnimationKey = "FloatTabs.attentionStyle.pulse"
    private static let animationEpoch = CACurrentMediaTime()

    private let pulseLayer = CAGradientLayer()
    private let pulseMaskLayer = CAShapeLayer()
    private let beaconLayer = CAGradientLayer()
    private let beaconMaskLayer = CAShapeLayer()
    private let orbitLayer = CAGradientLayer()
    private let orbitMaskLayer = CAShapeLayer()
    private var reduceMotionOverride: Bool?
    private var workspaceObserverInstalled = false
    private var isPresentationVisible = true

    private(set) var style: TabAttentionStyle = .dot
    private(set) var palette: TabAttentionPalette = .red
    private(set) var geometry: AttentionSurfaceGeometry
    private(set) var showsAttention = false
    private(set) var renderedEffect: AttentionStyleEffect = .dot
    private(set) var renderedPalette: TabAttentionPalette = .red
    private(set) var renderedPaletteRole = "dot-red"
    private(set) var renderedAnimationCycleDuration: TimeInterval?

    var isReduceMotionEnabled: Bool {
        reduceMotionOverride ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var isContinuousMotionActive: Bool {
        beaconLayer.animation(forKey: Self.beaconAnimationKey) != nil
            || orbitLayer.animation(forKey: Self.orbitAnimationKey) != nil
            || pulseLayer.animation(forKey: Self.pulseAnimationKey) != nil
    }

    var hasStaticRepresentativeEffect: Bool {
        showsAttention && (isReduceMotionEnabled || !isContinuousMotionActive)
    }

    var usesSymmetricPreviewGeometry: Bool {
        geometry == .settingsPreview
    }

    var renderedGradientStopCount: Int { pulseLayer.colors?.count ?? 0 }

    init(frame frameRect: NSRect, geometry: AttentionSurfaceGeometry = .railTab) {
        self.geometry = geometry
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.backgroundColor = NSColor.clear.cgColor
        pulseMaskLayer.fillColor = NSColor.white.cgColor
        beaconMaskLayer.fillColor = NSColor.white.cgColor
        orbitMaskLayer.fillColor = NSColor.clear.cgColor
        orbitMaskLayer.strokeColor = NSColor.white.cgColor
        pulseLayer.mask = pulseMaskLayer
        beaconLayer.mask = beaconMaskLayer
        orbitLayer.mask = orbitMaskLayer
        for sublayer in [pulseLayer, beaconLayer, orbitLayer] {
            sublayer.actions = [
                "colors": NSNull(), "locations": NSNull(), "startPoint": NSNull(),
                "endPoint": NSNull(), "opacity": NSNull(), "path": NSNull(),
                "lineDashPhase": NSNull(), "shadowOpacity": NSNull(),
            ]
            layer?.addSublayer(sublayer)
        }
        isHidden = true
        renderStyle()
    }

    convenience init(
        frame: NSRect = .zero,
        style: TabAttentionStyle,
        palette: TabAttentionPalette = .red,
        showsAttention: Bool,
        reduceMotionOverride: Bool? = nil,
        geometry: AttentionSurfaceGeometry = .railTab
    ) {
        self.init(frame: frame, geometry: geometry)
        self.reduceMotionOverride = reduceMotionOverride
        configure(style: style, palette: palette, showsAttention: showsAttention)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        style: TabAttentionStyle,
        palette: TabAttentionPalette,
        showsAttention: Bool
    ) {
        self.style = style
        self.palette = palette
        self.showsAttention = showsAttention
        isHidden = !showsAttention
        renderStyle()
    }

    func setReduceMotionOverride(_ value: Bool?) {
        reduceMotionOverride = value
        renderStyle()
    }

    func setPresentationVisible(_ visible: Bool) {
        guard isPresentationVisible != visible else { return }
        isPresentationVisible = visible
        renderStyle()
    }

    override func layout() {
        super.layout()
        updateLayerGeometry()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            if workspaceObserverInstalled {
                NSWorkspace.shared.notificationCenter.removeObserver(
                    self,
                    name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                    object: nil
                )
                workspaceObserverInstalled = false
            }
        } else if !workspaceObserverInstalled {
            NSWorkspace.shared.notificationCenter.addObserver(
                self,
                selector: #selector(accessibilityDisplayOptionsDidChange(_:)),
                name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: nil
            )
            workspaceObserverInstalled = true
            renderStyle()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        renderStyle()
    }

    @objc private func accessibilityDisplayOptionsDidChange(_ notification: Notification) {
        renderStyle()
    }

    private func renderStyle() {
        let configuration = style.configuration(for: palette)
        renderedEffect = configuration.effect
        renderedPalette = configuration.palette
        renderedPaletteRole = configuration.paletteRole
        renderedAnimationCycleDuration = configuration.animationCycleDuration
        removeAllEffectAnimations()
        resetEffectLayers()

        effectiveAppearance.performAsCurrentDrawingAppearance {
            updateLayerGeometry()
            switch configuration.effect {
            case .dot:
                break
            case .beacon:
                beaconMaskLayer.path = beaconPath()
                beaconLayer.colors = configuration.colors.map(\.cgColor)
                beaconLayer.locations = evenlySpacedLocations(count: configuration.colors.count)
                beaconLayer.startPoint = CGPoint(x: 0.5, y: 0)
                beaconLayer.endPoint = CGPoint(x: 0.5, y: 1)
                beaconLayer.shadowPath = beaconPath()
                beaconLayer.shadowColor = configuration.representativeColor.cgColor
                beaconLayer.shadowRadius = 4
                beaconLayer.shadowOpacity = 0.55
                beaconLayer.shadowOffset = .zero
                beaconLayer.isHidden = false
            case .orbit:
                orbitMaskLayer.path = surfacePath(in: bounds.insetBy(dx: 2.5, dy: 2.5))
                orbitMaskLayer.lineWidth = 3.0
                orbitMaskLayer.lineCap = .round
                orbitMaskLayer.lineDashPattern = nil
                orbitMaskLayer.lineDashPhase = 0
                orbitLayer.type = .conic
                orbitLayer.colors = configuration.colors.map(\.cgColor)
                orbitLayer.locations = evenlySpacedLocations(count: configuration.colors.count)
                orbitLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
                orbitLayer.endPoint = CGPoint(x: 0.5, y: 0.02)
                orbitLayer.isHidden = false
            case .pulse:
                let colors = configuration.colors.map(\.cgColor)
                pulseLayer.colors = colors.isEmpty ? [configuration.representativeColor.cgColor] : colors
                pulseLayer.locations = evenlySpacedLocations(count: pulseLayer.colors?.count ?? 1)
                pulseLayer.startPoint = CGPoint(x: 0, y: 0.5)
                pulseLayer.endPoint = CGPoint(x: 1, y: 0.5)
                pulseLayer.opacity = 0.72
                pulseLayer.isHidden = false
            }
        }

        guard showsAttention,
              isPresentationVisible,
              !isReduceMotionEnabled,
              let cycle = configuration.animationCycleDuration else { return }
        addAnimation(for: configuration.effect, cycle: cycle)
    }

    private func addAnimation(for effect: AttentionStyleEffect, cycle: TimeInterval) {
        switch effect {
        case .dot:
            break
        case .beacon:
            let breathe = CABasicAnimation(keyPath: "shadowOpacity")
            breathe.fromValue = 0.34
            breathe.toValue = 0.62
            addSharedTiming(breathe, cycle: cycle, autoreverses: true)
            beaconLayer.add(breathe, forKey: Self.beaconAnimationKey)
        case .orbit:
            let orbit = CAKeyframeAnimation(keyPath: "endPoint")
            orbit.values = [
                CGPoint(x: 0.5, y: 0.02),
                CGPoint(x: 0.98, y: 0.5),
                CGPoint(x: 0.5, y: 0.98),
                CGPoint(x: 0.02, y: 0.5),
                CGPoint(x: 0.5, y: 0.02),
            ]
            orbit.keyTimes = [0, 0.25, 0.5, 0.75, 1]
            orbit.duration = cycle
            orbit.repeatCount = .infinity
            orbit.beginTime = Self.animationEpoch
            orbit.calculationMode = .linear
            orbit.timingFunction = CAMediaTimingFunction(name: .linear)
            orbit.isRemovedOnCompletion = false
            orbitLayer.add(orbit, forKey: Self.orbitAnimationKey)
        case .pulse:
            let breathe = CABasicAnimation(keyPath: "opacity")
            breathe.fromValue = 0.38
            breathe.toValue = 1.00
            addSharedTiming(breathe, cycle: cycle, autoreverses: true)
            pulseLayer.add(breathe, forKey: Self.pulseAnimationKey)
        }
    }

    private func addSharedTiming(
        _ animation: CABasicAnimation,
        cycle: TimeInterval,
        autoreverses: Bool
    ) {
        animation.duration = cycle / (autoreverses ? 2 : 1)
        animation.autoreverses = autoreverses
        animation.repeatCount = .infinity
        animation.beginTime = Self.animationEpoch
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.isRemovedOnCompletion = false
    }

    private func removeAllEffectAnimations() {
        beaconLayer.removeAnimation(forKey: Self.beaconAnimationKey)
        orbitLayer.removeAnimation(forKey: Self.orbitAnimationKey)
        pulseLayer.removeAnimation(forKey: Self.pulseAnimationKey)
    }

    private func resetEffectLayers() {
        layer?.shadowOpacity = 0
        layer?.shadowPath = nil
        layer?.shadowColor = nil
        layer?.shadowRadius = 0
        layer?.shadowOffset = .zero
        beaconLayer.isHidden = true
        beaconLayer.shadowOpacity = 0
        beaconLayer.shadowPath = nil
        beaconLayer.shadowColor = nil
        beaconLayer.shadowRadius = 0
        orbitLayer.isHidden = true
        orbitLayer.type = .axial
        pulseLayer.isHidden = true
        pulseLayer.opacity = 0
    }

    private func updateLayerGeometry() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if geometry == .settingsPreview {
            let radius = min(bounds.height / 2, 14)
            layer?.backgroundColor = NSColor.controlBackgroundColor
                .withAlphaComponent(0.92)
                .cgColor
            layer?.cornerRadius = radius
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.34).cgColor
            layer?.borderWidth = 1
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.cornerRadius = 0
            layer?.borderWidth = 0
        }
        pulseLayer.frame = bounds
        pulseMaskLayer.frame = bounds
        pulseMaskLayer.path = surfacePath(in: bounds)
        beaconLayer.frame = bounds
        orbitLayer.frame = bounds
        beaconMaskLayer.frame = bounds
        orbitMaskLayer.frame = bounds
        if style == .beacon {
            beaconMaskLayer.path = beaconPath()
        } else if style == .orbit {
            orbitMaskLayer.path = surfacePath(in: bounds.insetBy(dx: 2.5, dy: 2.5))
        }
        CATransaction.commit()
    }

    private func surfacePath(in rect: CGRect) -> CGPath {
        return switch geometry {
        case .railTab, .overflowControl:
            ExternalTabMetrics.tabSurfacePath(in: rect)
        case .settingsPreview: settingsPreviewPath(in: rect)
        }
    }

    private func settingsPreviewPath(in rect: CGRect) -> CGPath {
        let radius = min(rect.height / 2, 14)
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    private func beaconPath() -> CGPath {
        let verticalInset = min(7, bounds.height * 0.18)
        let leadingInset = geometry == .settingsPreview ? CGFloat(8) : CGFloat(4)
        let accentWidth: CGFloat = 5.5
        let rect = CGRect(
            x: bounds.minX + leadingInset,
            y: bounds.minY + verticalInset,
            width: accentWidth,
            height: max(0, bounds.height - verticalInset * 2)
        )
        return CGPath(roundedRect: rect, cornerWidth: accentWidth / 2, cornerHeight: accentWidth / 2, transform: nil)
    }

    private func evenlySpacedLocations(count: Int) -> [NSNumber] {
        (0..<count).map { index in
            NSNumber(value: Double(index) / Double(max(count - 1, 1)))
        }
    }
}

@MainActor
final class ClassicUnreadDotView: NSView {
    static let diameter: CGFloat = 11.5

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.systemRed.cgColor
        layer?.cornerRadius = Self.diameter / 2
        layer?.borderColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderWidth = 1.1
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.22
        layer?.shadowRadius = 1.5
        layer?.shadowOffset = NSSize(width: 0, height: -0.5)
        isHidden = true
        setAccessibilityElement(false)
    }

    convenience init() { self.init(frame: .zero) }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
private protocol RailHoverInteractionOwner: AnyObject {
    func setHoverInteractionSuspended(_ suspended: Bool)
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

    private let attentionSurfaceView = AttentionStyleSurfaceView(
        frame: .zero,
        geometry: .overflowControl
    )
    private let imageView = NSImageView()
    private let unreadDotView = ClassicUnreadDotView()
    private var items: [RailOverflowItem] = []
    private var attentionStyle: TabAttentionStyle = .dot
    private var attentionPalette: TabAttentionPalette = .red
    private var trackingAreaReference: NSTrackingArea?
    private var isHoverInteractionSuspended = false

    var menuItems: [RailOverflowItem] { items }
    private var hasUnreadItem: Bool { items.contains(where: \.isUnread) }
    var displayedAttentionStyle: TabAttentionStyle { attentionStyle }
    var displayedAttentionPalette: TabAttentionPalette { attentionPalette }
    var attentionSurfaceEffect: AttentionStyleEffect { attentionSurfaceView.renderedEffect }
    var showsClassicUnreadDot: Bool { !unreadDotView.isHidden }
    var attentionSurfaceUsesSharedRenderer: Bool {
        attentionSurfaceView.renderedPaletteRole
            == attentionStyle.configuration(for: attentionPalette).paletteRole
    }
    var attentionSurfaceMotionIsActive: Bool {
        attentionSurfaceView.isContinuousMotionActive
    }
    var attentionSurfaceReduceMotionIsEnabled: Bool {
        attentionSurfaceView.isReduceMotionEnabled
    }
    var isShowingUnreadResponse: Bool { hasUnreadItem }
    var unreadResponseFrame: NSRect { hasUnreadItem ? bounds : .zero }
    var unreadResponseColor: NSColor? {
        guard hasUnreadItem, let backgroundColor = layer?.backgroundColor else { return nil }
        return NSColor(cgColor: backgroundColor)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = ExternalTabMetrics.tabRadius
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        attentionSurfaceView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(attentionSurfaceView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        unreadDotView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(unreadDotView, positioned: .above, relativeTo: imageView)
        NSLayoutConstraint.activate([
            attentionSurfaceView.leadingAnchor.constraint(equalTo: leadingAnchor),
            attentionSurfaceView.trailingAnchor.constraint(equalTo: trailingAnchor),
            attentionSurfaceView.topAnchor.constraint(equalTo: topAnchor),
            attentionSurfaceView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 13),
            imageView.heightAnchor.constraint(equalToConstant: 13),
            unreadDotView.centerXAnchor.constraint(equalTo: imageView.trailingAnchor, constant: -1),
            unreadDotView.centerYAnchor.constraint(equalTo: imageView.topAnchor, constant: 1),
            unreadDotView.widthAnchor.constraint(equalToConstant: ClassicUnreadDotView.diameter),
            unreadDotView.heightAnchor.constraint(equalToConstant: ClassicUnreadDotView.diameter),
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
        setAccessibilityLabel(
            hasUnreadItem
                ? "\(label) · Unread response"
                : label
        )
        refreshAppearance()
    }

    func setAttentionStyle(_ style: TabAttentionStyle, palette: TabAttentionPalette? = nil) {
        let nextPalette = palette ?? attentionPalette
        guard attentionStyle != style || attentionPalette != nextPalette else { return }
        attentionStyle = style
        attentionPalette = nextPalette
        refreshAppearance()
    }

    func setAttentionStyleReduceMotionOverride(_ value: Bool?) {
        attentionSurfaceView.setReduceMotionOverride(value)
    }

    func setAttentionPresentationVisible(_ visible: Bool) {
        attentionSurfaceView.setPresentationVisible(visible)
    }

    func refreshAppearance(isHovered: Bool = false) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            attentionSurfaceView.configure(
                style: attentionStyle,
                palette: attentionPalette,
                showsAttention: hasUnreadItem
            )
            unreadDotView.isHidden = !(hasUnreadItem && attentionStyle == .dot)
            imageView.contentTintColor = .labelColor
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
    var onSetResidency: ((UUID, SlotResidencyPolicy) -> Void)? // legacy command/test seam
    var onSetRuntimeRetention: ((UUID, SlotRuntimeRetentionPreference) -> Void)?
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
    private var unreadSlotIDs = Set<UUID>()
    private var attentionStyle: TabAttentionStyle = .dot
    private var attentionPalette: TabAttentionPalette = .red
    private var attentionStylePreferencesStore: AppPreferencesStore?
    private var tabViews: [UUID: ExternalWebAppTabView] = [:]
    private var previewOrderIDs: [UUID]?
    private let addControl = AddWebAppControl()
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
        addSubview(settingsControl)
        addSubview(pinControl)
        addSubview(tabOverflowControl)
        addControl.onActivate = { [weak self] in self?.onAdd?() }
        settingsControl.onActivate = { [weak self] in self?.onSettings?() }
        pinControl.onActivate = { [weak self] in self?.onTogglePin?() }
        tabOverflowControl.onSelect = { [weak self] slotID in self?.onSelect?(slotID) }
        addControl.onPointerMoved = { [weak self] event in
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

    convenience init(preferencesStore: AppPreferencesStore) {
        self.init(frame: .zero)
        attentionStylePreferencesStore = preferencesStore
        setAttentionStyle(preferencesStore.attentionStyle, palette: preferencesStore.attentionPalette)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(attentionStylePreferenceDidChange(_:)),
            name: .floatTabsAttentionStyleDidChange,
            object: preferencesStore
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(attentionPalettePreferenceDidChange(_:)),
            name: .floatTabsAttentionPaletteDidChange,
            object: preferencesStore
        )
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

    func setAttentionStyle(_ style: TabAttentionStyle, palette: TabAttentionPalette? = nil) {
        let nextPalette = palette ?? attentionPalette
        guard attentionStyle != style || attentionPalette != nextPalette else { return }
        attentionStyle = style
        attentionPalette = nextPalette
        tabViews.values.forEach { $0.setAttentionStyle(style, palette: nextPalette) }
        tabOverflowControl.setAttentionStyle(style, palette: nextPalette)
    }

    @objc private func attentionStylePreferenceDidChange(_ notification: Notification) {
        guard let preferencesStore = attentionStylePreferencesStore else { return }
        setAttentionStyle(preferencesStore.attentionStyle, palette: preferencesStore.attentionPalette)
    }

    @objc private func attentionPalettePreferenceDidChange(_ notification: Notification) {
        guard let preferencesStore = attentionStylePreferencesStore else { return }
        setAttentionStyle(preferencesStore.attentionStyle, palette: preferencesStore.attentionPalette)
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

    var addControlFrame: NSRect {
        addControl.frame
    }

    var settingsControlFrame: NSRect {
        settingsControl.frame
    }

    var pinControlFrame: NSRect {
        pinControl.frame
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
                addControl, settingsControl, pinControl, tabOverflowControl,
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
        railContentViews.forEach { view in
            view.alphaValue = collapsed ? 0 : 1
            let isHidden = collapsed || isHiddenByOverflow(view)
            view.isHidden = isHidden
            if let tab = view as? ExternalWebAppTabView {
                tab.setAttentionPresentationVisible(!isHidden)
            } else if view === tabOverflowControl {
                tabOverflowControl.setAttentionPresentationVisible(!isHidden)
            }
        }
        onActiveTabGeometryChange?()
    }

    private func makeTabView(for id: UUID) -> ExternalWebAppTabView {
        let view = ExternalWebAppTabView(slotID: id)
        view.setAttentionStyle(attentionStyle, palette: attentionPalette)
        view.setHoverInteractionSuspended(isModalPresentationActive)
        view.setWindowSizeEditingEnabled(windowSizeEditingEnabled)
        view.setBrowserProfileMenuSnapshot(
            options: browserProfileMenuOptions,
            assignmentEnabled: browserProfileAssignmentEnabled,
            duplicationEnabled: browserProfileDuplicationEnabled
        )
        view.alphaValue = isRailCollapsed ? 0 : 1
        view.isHidden = isRailCollapsed
        view.setAttentionPresentationVisible(!isRailCollapsed)
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
        view.onSetRuntimeRetention = { [weak self] slotID, preference in
            self?.onSetRuntimeRetention?(slotID, preference)
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
                    tab.setAttentionPresentationVisible(!tab.isHidden)
                    self.setFrame(.zero, for: tab, animated: animated)
                    continue
                }
                tab.isHidden = self.isRailCollapsed
                tab.setAttentionPresentationVisible(!tab.isHidden)
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
                self.tabOverflowControl.setAttentionPresentationVisible(
                    !self.tabOverflowControl.isHidden
                )
                y += ExternalTabMetrics.systemControlHeight + ExternalTabMetrics.addGap
            } else {
                self.tabOverflowControl.isHidden = true
                self.tabOverflowControl.setAttentionPresentationVisible(false)
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
                - (ExternalTabMetrics.systemControlHeight + ExternalTabMetrics.systemControlGap),
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
        let controls: [NSView] = [pinControl, settingsControl]
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
        let controls: [NSView] = [settingsControl, pinControl]
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
    /// Single seam for the future Settings → General accent picker.
    static var activeAccent: NSColor { .controlAccentColor }
}

@MainActor
final class WebsiteFaviconAssetStore {
    struct Limits: Equatable {
        let maximumOrigins: Int
        let maximumImageBytes: Int
        let maximumStoreBytes: Int

        static let production = Limits(
            maximumOrigins: 256,
            maximumImageBytes: 64 * 1024,
            maximumStoreBytes: 16 * 1024 * 1024
        )
    }

    struct Record: Codable, Equatable {
        static let currentVersion = 1

        let version: Int
        let originKey: String
        let imageData: Data
        let pixelSHA256: String
        let priority: Int
        let kind: String
        var isLocked: Bool

        init(
            originKey: String,
            imageData: Data,
            pixelSHA256: String,
            priority: Int,
            kind: String,
            isLocked: Bool
        ) {
            version = Self.currentVersion
            self.originKey = originKey
            self.imageData = imageData
            self.pixelSHA256 = pixelSHA256
            self.priority = priority
            self.kind = kind
            self.isLocked = isLocked
        }
    }

    enum ReadResult {
        case record(Record)
        case missing
        case corrupt
        case unavailable
    }

    enum WriteResult: Equatable {
        case saved
        case capacityExceeded
        case corruptExistingRecord
        case invalidRecord
        case unavailable
    }

    private struct FileEntry {
        let url: URL
        let size: Int
        let modifiedAt: Date
        let record: Record?
    }

    static let shared = WebsiteFaviconAssetStore(directoryURL: WebsiteFaviconAssetStore.defaultDirectoryURL)

    private let directoryURL: URL?
    private let fileManager: FileManager
    private let limits: Limits
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()
    private var memoryRecords: [String: Record] = [:]
    private var memoryOrder: [String] = []
    private var corruptOrigins: Set<String> = []

    /// A nil directory is a bounded in-memory store for provider tests. The
    /// production singleton uses the isolated Application Support directory.
    init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default,
        limits: Limits = .production
    ) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        self.limits = limits
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
    }

    func load(originKey: String) -> ReadResult {
        guard Self.isSafeOriginKey(originKey) else { return .corrupt }
        if directoryURL == nil {
            guard let record = memoryRecords[originKey] else { return .missing }
            guard Self.isValid(record, for: originKey),
                  record.imageData.count <= limits.maximumImageBytes else {
                corruptOrigins.insert(originKey)
                return .corrupt
            }
            memoryOrder.removeAll { $0 == originKey }
            memoryOrder.append(originKey)
            return .record(record)
        }

        let fileURL = Self.recordURL(for: originKey, in: directoryURL!)
        guard fileManager.fileExists(atPath: fileURL.path) else { return .missing }
        guard !corruptOrigins.contains(originKey),
              let data = try? Data(contentsOf: fileURL),
              let record = try? decoder.decode(Record.self, from: data),
              Self.isValid(record, for: originKey),
              record.imageData.count <= limits.maximumImageBytes else {
            corruptOrigins.insert(originKey)
            return .corrupt
        }
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
        return .record(record)
    }

    func save(_ record: Record) -> WriteResult {
        guard Self.isValid(record, for: record.originKey) else { return .invalidRecord }
        guard record.imageData.count <= limits.maximumImageBytes else { return .capacityExceeded }
        guard !corruptOrigins.contains(record.originKey) else { return .corruptExistingRecord }
        guard let encoded = try? encoder.encode(record) else { return .invalidRecord }

        guard let directoryURL else {
            memoryRecords[record.originKey] = record
            memoryOrder.removeAll { $0 == record.originKey }
            memoryOrder.append(record.originKey)
            while memoryRecords.count > limits.maximumOrigins {
                guard let oldestUnlocked = memoryOrder.first(where: {
                    memoryRecords[$0]?.isLocked == false
                }) else {
                    memoryRecords.removeValue(forKey: record.originKey)
                    memoryOrder.removeAll { $0 == record.originKey }
                    return .capacityExceeded
                }
                memoryRecords.removeValue(forKey: oldestUnlocked)
                memoryOrder.removeAll { $0 == oldestUnlocked }
            }
            return .saved
        }

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            recoverInterruptedEvictions(in: directoryURL)
        } catch {
            return .unavailable
        }

        let targetURL = Self.recordURL(for: record.originKey, in: directoryURL)
        let targetPath = targetURL.standardizedFileURL.path
        let entries: [FileEntry]
        do {
            entries = try recordEntries(in: directoryURL)
        } catch {
            return .unavailable
        }
        let existingTarget = entries.first {
            $0.url.standardizedFileURL.path == targetPath
        }
        if let existingTarget,
           existingTarget.record == nil || existingTarget.record?.originKey != record.originKey {
            corruptOrigins.insert(record.originKey)
            return .corruptExistingRecord
        }

        var countAfterWrite = entries.count + (existingTarget == nil ? 1 : 0)
        var bytesAfterWrite = entries.reduce(0) { $0 + $1.size }
            - (existingTarget?.size ?? 0)
            + encoded.count
        var evictionCandidates = entries
            .filter {
                $0.url.standardizedFileURL.path != targetPath
                    && $0.record?.isLocked == false
            }
            .sorted { $0.modifiedAt < $1.modifiedAt }
        var evictions: [FileEntry] = []
        while countAfterWrite > limits.maximumOrigins || bytesAfterWrite > limits.maximumStoreBytes {
            guard !evictionCandidates.isEmpty else { return .capacityExceeded }
            let entry = evictionCandidates.removeFirst()
            evictions.append(entry)
            countAfterWrite -= 1
            bytesAfterWrite -= entry.size
        }

        var stagedEvictions: [(original: URL, staged: URL)] = []
        for entry in evictions {
            let stagedURL = directoryURL.appendingPathComponent(
                ".evicting-\(UUID().uuidString)-\(entry.url.lastPathComponent)"
            )
            do {
                try fileManager.moveItem(at: entry.url, to: stagedURL)
                stagedEvictions.append((entry.url, stagedURL))
            } catch {
                restore(stagedEvictions)
                return .unavailable
            }
        }

        let previousTargetData = try? Data(contentsOf: targetURL)
        do {
            try encoded.write(to: targetURL, options: [.atomic])
        } catch {
            restore(stagedEvictions)
            return .unavailable
        }

        do {
            for item in stagedEvictions {
                try fileManager.removeItem(at: item.staged)
            }
        } catch {
            if let previousTargetData {
                try? previousTargetData.write(to: targetURL, options: [.atomic])
            } else {
                try? fileManager.removeItem(at: targetURL)
            }
            restore(stagedEvictions.filter { fileManager.fileExists(atPath: $0.staged.path) })
            return .unavailable
        }
        return .saved
    }

    func setLocked(_ isLocked: Bool, originKey: String) -> WriteResult {
        guard case let .record(existing) = load(originKey: originKey) else {
            return corruptOrigins.contains(originKey) ? .corruptExistingRecord : .invalidRecord
        }
        var updated = existing
        updated.isLocked = isLocked
        return save(updated)
    }

    func markCorrupt(originKey: String) {
        corruptOrigins.insert(originKey)
    }

    func recordURL(forTesting originKey: String) -> URL? {
        directoryURL.map { Self.recordURL(for: originKey, in: $0) }
    }

    private func recordEntries(in directoryURL: URL) throws -> [FileEntry] {
        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: []
        ).filter { $0.pathExtension == "json" }
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = values?.fileSize ?? ((try? Data(contentsOf: url).count) ?? 0)
            let modifiedAt = values?.contentModificationDate ?? .distantPast
            let data = try? Data(contentsOf: url)
            let decoded = data.flatMap { try? decoder.decode(Record.self, from: $0) }
            let record: Record? = decoded.flatMap { value -> Record? in
                guard Self.isValid(value, for: value.originKey),
                      Self.recordURL(for: value.originKey, in: directoryURL).lastPathComponent
                        == url.lastPathComponent else {
                    return nil
                }
                return value
            }
            return FileEntry(url: url, size: size, modifiedAt: modifiedAt, record: record)
        }
    }

    private func restore(_ items: [(original: URL, staged: URL)]) {
        for item in items.reversed() where fileManager.fileExists(atPath: item.staged.path) {
            try? fileManager.moveItem(at: item.staged, to: item.original)
        }
    }

    private func recoverInterruptedEvictions(in directoryURL: URL) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: []
        ) else { return }
        for file in files where file.lastPathComponent.hasPrefix(".evicting-") {
            guard let data = try? Data(contentsOf: file),
                  let record = try? decoder.decode(Record.self, from: data),
                  Self.isValid(record, for: record.originKey) else {
                continue
            }
            let target = Self.recordURL(for: record.originKey, in: directoryURL)
            if fileManager.fileExists(atPath: target.path) {
                try? fileManager.removeItem(at: file)
            } else {
                try? fileManager.moveItem(at: file, to: target)
            }
        }
    }

    private static func isValid(_ record: Record, for originKey: String) -> Bool {
        record.version == Record.currentVersion
            && record.originKey == originKey
            && isSafeOriginKey(record.originKey)
            && record.imageData.count <= Limits.production.maximumImageBytes
            && record.pixelSHA256.count == 64
            && record.pixelSHA256.allSatisfy(\.isHexDigit)
            && ["icon", "appleTouch", "mask", "conventional"].contains(record.kind)
    }

    private static func isSafeOriginKey(_ value: String) -> Bool {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host != nil,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/" else {
            return false
        }
        return true
    }

    private static func recordURL(for originKey: String, in directoryURL: URL) -> URL {
        let digest = SHA256.hash(data: Data(originKey.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directoryURL.appendingPathComponent("\(digest).json", isDirectory: false)
    }

    private static var defaultDirectoryURL: URL {
        let applicationSupport = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport
            .appendingPathComponent("FloatTabs", isDirectory: true)
            .appendingPathComponent("Favicons-v1", isDirectory: true)
    }
}

@MainActor
final class WebsiteFaviconProvider {
    typealias DataLoader = @MainActor @Sendable (
        URLRequest
    ) async throws -> (Data, URLResponse)
    typealias MonotonicClock = @MainActor @Sendable () -> TimeInterval
    typealias RetryWaiter = @MainActor @Sendable (TimeInterval) async -> Void
    typealias Completion = (NSImage?) -> Void

    enum DOMCandidateReadResult: Equatable {
        case candidates([Candidate])
        case noCandidates
        case readFailed
    }

    enum DOMCandidateUpdateSource: Equatable {
        case initialization
        case pageNavigation

        static func forDOMRead(
            previousRuntimeIdentity: WebRuntimeDiagnosticIdentity?,
            currentRuntimeIdentity: WebRuntimeDiagnosticIdentity
        ) -> Self {
            previousRuntimeIdentity == currentRuntimeIdentity ? .pageNavigation : .initialization
        }
    }

    enum ProjectionOutcome: String, Equatable {
        case iconDisplayed = "icon_displayed"
        case fallbackDisplayed = "fallback_displayed"
        case noImageDisplayed = "no_image_displayed"
    }

    private enum FailureStage: String, Hashable {
        case noCandidates = "no_candidates"
        case requestFailed = "request_failed"
        case requestTimedOut = "request_timed_out"
        case httpStatus = "http_status"
        case htmlDecodeFailed = "html_decode_failed"
        case imageDecodeFailed = "image_decode_failed"
        case pixelNormalizationFailed = "pixel_normalization_failed"
        case noVisiblePixels = "no_visible_pixels"
    }

    private enum CacheUpdateOutcome: String, Equatable {
        case updated = "updated"
        case memoryOnlyUpdated = "memory_only_updated"
        case awaitingConfirmation = "awaiting_confirmation"
        case sameVisualContent = "same_visual_content"
        case locked = "locked"
        case reusedSameResource = "reused_same_resource"
        case retainedPrevious = "retained_previous"
        case empty = "empty"
        case failed = "failed"
    }

    enum IconControlResult: Equatable {
        case changed
        case unchanged
        case unavailable
        case capacityExceeded
        case corruptStorage
        case noAcceptedIcon
        case fetchFailed

        var succeeded: Bool {
            self == .changed || self == .unchanged
        }
    }

    struct IconControlState: Equatable {
        let hasAcceptedIcon: Bool
        let isLocked: Bool
    }

    private enum AcceptanceMode: Equatable {
        case automatic
        case explicitChoice
    }

    private enum CandidateFetchResult {
        case fetched(FetchedFavicon)
        case failed(FailureStage)
    }

    private struct FetchReport {
        let favicon: FetchedFavicon?
        let failureStages: Set<FailureStage>
        let candidateCount: Int
    }

    private enum PageHTMLResult {
        case loaded(String, URLResponse)
        case failed(FailureStage)
    }

    struct Candidate: Equatable {
        enum Kind: String, Equatable {
            case icon
            case appleTouch
            case mask
            case conventional

            var preference: Int {
                switch self {
                case .icon: 0
                case .appleTouch: 1
                case .mask: 2
                case .conventional: 3
                }
            }
        }

        let url: URL
        let kind: Kind
        let sizes: String
        let type: String
        let mediaSpecific: Bool
        let sourceOrder: Int

        var resourceIdentity: String {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let scheme = components.scheme?.lowercased(),
                  let host = components.host?.lowercased() else {
                return url.absoluteString
            }
            components.scheme = scheme
            components.host = host
            if components.port == (scheme == "https" ? 443 : 80) {
                components.port = nil
            }
            components.fragment = nil
            return components.string ?? url.absoluteString
        }

        var priority: Int {
            let sizeRank: Int
            let declaredSizes = sizes.lowercased().split(whereSeparator: \.isWhitespace)
            if declaredSizes.contains("any") || declaredSizes.contains("32x32") {
                sizeRank = 0
            } else if declaredSizes.contains("16x16") {
                sizeRank = 1
            } else if declaredSizes.isEmpty {
                sizeRank = 2
            } else {
                sizeRank = 3
            }

            let normalizedType = type.lowercased()
            let typeRank: Int
            if normalizedType == "image/png" || normalizedType == "image/svg+xml" {
                typeRank = 0
            } else if normalizedType == "image/x-icon"
                || normalizedType == "image/vnd.microsoft.icon" {
                typeRank = 1
            } else if normalizedType.hasPrefix("image/") {
                typeRank = 2
            } else {
                typeRank = 3
            }

            return kind.preference * 1_000
                + (mediaSpecific ? 100 : 0)
                + sizeRank * 10
                + typeRank
        }

        static func conventional(_ url: URL, sourceOrder: Int = 0) -> Self {
            Self(
                url: url,
                kind: .conventional,
                sizes: "",
                type: "",
                mediaSpecific: false,
                sourceOrder: sourceOrder
            )
        }

        static func declared(_ url: URL, sourceOrder: Int = 0) -> Self {
            Self(
                url: url,
                kind: .icon,
                sizes: "",
                type: "",
                mediaSpecific: false,
                sourceOrder: sourceOrder
            )
        }
    }

    private struct CachedFavicon {
        let image: NSImage
        let pixelSHA256: String
        let priority: Int
        let resourceIdentity: String?
        let kind: Candidate.Kind
        let isLocked: Bool
    }

    private struct FetchedFavicon {
        let image: NSImage
        let pixelSHA256: String
        let priority: Int
        let resourceIdentity: String
        let kind: Candidate.Kind
    }

    private struct PendingFavicon {
        let fetched: FetchedFavicon
    }

    private struct AcceptanceResult {
        let cacheOutcome: CacheUpdateOutcome
        let controlResult: IconControlResult?
    }

    private struct ConsumerDemand {
        let originKey: String
        var url: URL
        var automaticallyRetries: Bool
        var completion: Completion
    }

    private struct InFlightRequest {
        let id: UUID
        let resourceIdentity: String?
        let acceptanceMode: AcceptanceMode
        let task: Task<Void, Never>
    }

    private struct ScheduledRetry {
        let id: UUID
        let fireAt: TimeInterval
        let task: Task<Void, Never>
    }

    static let shared = WebsiteFaviconProvider(assetStore: .shared)
    private static let automaticRetryDelay: TimeInterval = 15
    private static let retryBackoff: [TimeInterval] = [120, 240, 480, 900]
    private static let maximumDeclaredCandidates = 8
    private static let maximumDiscoveryPages = 2
    private static let maximumCachedOrigins = 256
    private static let maximumDOMCandidateOrigins = 128
    private static let requestTimeout: TimeInterval = 8
    private static let requestBudget: TimeInterval = 25
    private static let faviconSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        return URLSession(configuration: configuration)
    }()

    private let dataLoader: DataLoader
    private let monotonicClock: MonotonicClock
    private let retryWaiter: RetryWaiter
    private let assetStore: WebsiteFaviconAssetStore
    private weak var diagnosticRecorder: (any RuntimeDiagnosticRecording)?
    private var cache: [String: CachedFavicon] = [:]
    private var cacheOrder: [String] = []
    private var pendingFavicons: [String: PendingFavicon] = [:]
    private var domCandidates: [String: [Candidate]] = [:]
    private var domCandidateOrder: [String] = []
    private var demands: [UUID: ConsumerDemand] = [:]
    private var oneShotCompletions: [String: [Completion]] = [:]
    private var explicitChoiceCompletions: [
        String: [(IconControlResult) -> Void]
    ] = [:]
    private var failureCycles: [String: Int] = [:]
    private var cooldownUntil: [String: TimeInterval] = [:]
    private var inFlight: [String: InFlightRequest] = [:]
    private var scheduledRetries: [String: ScheduledRetry] = [:]

    init(
        dataLoader: DataLoader? = nil,
        monotonicClock: @escaping MonotonicClock = {
            ProcessInfo.processInfo.systemUptime
        },
        retryWaiter: @escaping RetryWaiter = { delay in
            let nanoseconds = UInt64(max(delay, 0) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
        },
        diagnosticRecorder: (any RuntimeDiagnosticRecording)? = nil,
        assetStore: WebsiteFaviconAssetStore? = nil
    ) {
        self.dataLoader = dataLoader ?? { request in
            try await Self.faviconSession.data(for: request)
        }
        self.monotonicClock = monotonicClock
        self.retryWaiter = retryWaiter
        self.diagnosticRecorder = diagnosticRecorder
        self.assetStore = assetStore ?? WebsiteFaviconAssetStore()
    }

    func setDiagnosticRecorder(_ recorder: any RuntimeDiagnosticRecording) {
        diagnosticRecorder = recorder
    }

    func recordProjection(_ outcome: ProjectionOutcome, surface: String) {
        guard ["tab", "menu_bar"].contains(surface) else { return }
        diagnosticRecorder?.record(
            event: "favicon.ui_projection",
            level: outcome == .noImageDisplayed ? .warning : .notice,
            subsystem: "favicon",
            fields: [
                "surface": .string(surface),
                "outcome": .string(outcome.rawValue)
            ]
        )
    }

    static func originKey(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(),
              URLComponents(url: url, resolvingAgainstBaseURL: false)?.user == nil,
              URLComponents(url: url, resolvingAgainstBaseURL: false)?.password == nil else {
            return nil
        }
        let defaultPort = scheme == "https" ? 443 : 80
        let port = url.port.flatMap { $0 == defaultPort ? nil : $0 }
            .map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }

    private static func candidate(_ candidate: Candidate, shouldReplace cached: CachedFavicon) -> Bool {
        candidate.priority < cached.priority
            || (candidate.priority == cached.priority
                && candidate.resourceIdentity != cached.resourceIdentity)
    }

    /// Reads only icon link declarations from the loaded main document. The
    /// isolated WebKit client world prevents this helper from calling any
    /// page-provided JavaScript and returns no page content.
    static func readDOMFaviconCandidates(
        from webView: WKWebView,
        completion: @escaping (DOMCandidateReadResult) -> Void
    ) {
        let script = #"""
        (() => {
          const records = Array.from(document.querySelectorAll("link[rel]"))
            .map((link, sourceOrder) => {
              const rel = (link.getAttribute("rel") || "").toLowerCase();
              const tokens = rel.split(/\s+/).filter(Boolean);
              const kind = tokens.includes("icon") ? "icon"
                : tokens.includes("apple-touch-icon-precomposed") ? "appleTouch"
                : tokens.includes("apple-touch-icon") ? "appleTouch"
                : tokens.includes("mask-icon") ? "mask" : null;
              const media = link.getAttribute("media") || "";
              const matchesMedia = !media || (() => {
                try { return window.matchMedia(media).matches; }
                catch (_) { return false; }
              })();
              return {
                href: link.href,
                kind,
                sizes: link.getAttribute("sizes") || "",
                type: (link.getAttribute("type") || "").toLowerCase(),
                mediaSpecific: false,
                sourceOrder,
                matchesMedia
              };
            })
            .filter(item => item.kind && item.matchesMedia && /^https?:\/\//i.test(item.href));
          const priority = item => {
            const kindRank = { icon: 0, appleTouch: 1, mask: 2 }[item.kind] * 1000;
            const sizes = item.sizes.toLowerCase().split(/\s+/).filter(Boolean);
            const sizeRank = sizes.includes("any") || sizes.includes("32x32") ? 0
              : sizes.includes("16x16") ? 1 : sizes.length === 0 ? 2 : 3;
            const typeRank = item.type === "image/png" || item.type === "image/svg+xml" ? 0
              : item.type === "image/x-icon" || item.type === "image/vnd.microsoft.icon" ? 1
              : item.type.startsWith("image/") ? 2 : 3;
            return kindRank + sizeRank * 10 + typeRank;
          };
          const seen = new Set();
          const selected = records
            .sort((a, b) => priority(a) - priority(b) || a.sourceOrder - b.sourceOrder)
            .filter(item => seen.has(item.href) ? false : (seen.add(item.href), true))
            .slice(0, 8);
          return JSON.stringify(selected);
        })()
        """#
        webView.evaluateJavaScript(script, in: nil, in: .defaultClient) { result in
            completion(parseDOMCandidateReadResult(result))
        }
    }

    static func parseDOMCandidateReadResult(
        _ result: Result<Any, Error>
    ) -> DOMCandidateReadResult {
        guard case let .success(rawValue) = result,
              let json = rawValue as? String,
              let data = json.data(using: .utf8),
              let records = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return .readFailed
        }
        let candidates = records.enumerated().compactMap { order, record -> Candidate? in
            guard let href = record["href"] as? String,
                  let url = URL(string: href),
                  Self.originKey(for: url) != nil,
                  let kind = Self.candidateKind(from: record["kind"] as? String) else {
                return nil
            }
            return Candidate(
                url: url,
                kind: kind,
                sizes: record["sizes"] as? String ?? "",
                type: record["type"] as? String ?? "",
                mediaSpecific: record["mediaSpecific"] as? Bool ?? false,
                sourceOrder: record["sourceOrder"] as? Int ?? order
            )
        }
        let ordered = Array(orderedCandidates(candidates).prefix(maximumDeclaredCandidates))
        return ordered.isEmpty ? .noCandidates : .candidates(ordered)
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
        baseURL: URL,
        limit: Int = 8
    ) -> [URL] {
        discoveredFaviconCandidates(in: html, baseURL: baseURL, limit: limit).map(\.url)
    }

    static func discoveredFaviconCandidates(
        in html: String,
        baseURL: URL,
        limit: Int = 8
    ) -> [Candidate] {
        guard limit > 0 else { return [] }
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

        var result: [Candidate] = []
        let htmlRange = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in linkRegex.matches(in: html, range: htmlRange) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])
            let attributes = linkAttributes(in: tag, using: attributeRegex)
            let relTokens = (attributes["rel"] ?? "")
                .lowercased()
                .split { $0.isWhitespace }
                .map(String.init)
            guard let kind = Self.candidateKind(from: relTokens),
                  let href = attributes["href"],
                  let candidate = URL(string: href, relativeTo: documentBaseURL)?.absoluteURL,
                  isHTTPURL(candidate) else {
                continue
            }
            result.append(Candidate(
                url: candidate,
                kind: kind,
                sizes: attributes["sizes"] ?? "",
                type: (attributes["type"] ?? "").lowercased(),
                mediaSpecific: !(attributes["media"] ?? "").isEmpty,
                sourceOrder: match.range.location
            ))
        }
        return Array(Self.orderedCandidates(result).prefix(limit))
    }

    private static func candidateKind(from rawKind: String?) -> Candidate.Kind? {
        switch rawKind?.lowercased() {
        case "icon": .icon
        case "appletouch", "apple-touch-icon", "apple-touch-icon-precomposed": .appleTouch
        case "mask", "mask-icon": .mask
        default: nil
        }
    }

    private static func candidateKind(from relTokens: [String]) -> Candidate.Kind? {
        if relTokens.contains("icon") { return .icon }
        if relTokens.contains("apple-touch-icon-precomposed")
            || relTokens.contains("apple-touch-icon") {
            return .appleTouch
        }
        if relTokens.contains("mask-icon") { return .mask }
        return nil
    }

    private static func orderedCandidates(_ candidates: [Candidate]) -> [Candidate] {
        let sorted = candidates.filter { originKey(for: $0.url) != nil }.sorted {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return $0.sourceOrder < $1.sourceOrder
        }
        var seen = Set<String>()
        return sorted.filter { seen.insert($0.resourceIdentity).inserted }
    }

    private static func isValidDOMCandidate(
        _ candidate: Candidate,
        forPageOriginKey pageOriginKey: String
    ) -> Bool {
        guard let resourceOriginKey = originKey(for: candidate.url) else { return false }
        guard resourceOriginKey != pageOriginKey else { return true }
        return candidate.url.scheme?.lowercased() == "https"
    }

    /// One stable subscriber per UI consumer. Repeating the call for the same
    /// consumer replaces its callback instead of accumulating stale waiters.
    func subscribe(
        for url: URL,
        consumerID: UUID,
        automaticallyRetries: Bool = true,
        completion: @escaping Completion
    ) {
        guard let key = Self.originKey(for: url) else {
            cancel(consumerID: consumerID)
            completion(nil)
            return
        }

        if demands[consumerID]?.originKey != key,
           demands[consumerID] != nil {
            cancel(consumerID: consumerID)
        }
        demands[consumerID] = ConsumerDemand(
            originKey: key,
            url: url,
            automaticallyRetries: automaticallyRetries,
            completion: completion
        )
        if let cached = cachedImage(for: key) {
            completion(cached)
            return
        }
        ensureRequest(for: key, fallbackURL: url)
    }

    func iconControlState(for url: URL) -> IconControlState {
        guard let key = Self.originKey(for: url),
              cachedFavicon(for: key) != nil,
              let accepted = cache[key] else {
            return IconControlState(hasAcceptedIcon: false, isLocked: false)
        }
        return IconControlState(hasAcceptedIcon: true, isLocked: accepted.isLocked)
    }

    func lockCurrentIcon(for url: URL) -> IconControlResult {
        guard let key = Self.originKey(for: url),
              let accepted = cachedFavicon(for: key) else {
            return .noAcceptedIcon
        }
        guard !accepted.isLocked else { return .unchanged }
        let result = persistLockState(true, accepted: accepted, originKey: key)
        if result == .changed {
            cache[key] = CachedFavicon(
                image: accepted.image,
                pixelSHA256: accepted.pixelSHA256,
                priority: accepted.priority,
                resourceIdentity: accepted.resourceIdentity,
                kind: accepted.kind,
                isLocked: true
            )
        }
        return result
    }

    func unlockIcon(for url: URL) -> IconControlResult {
        guard let key = Self.originKey(for: url),
              let accepted = cachedFavicon(for: key) else {
            return .noAcceptedIcon
        }
        guard accepted.isLocked else { return .unchanged }
        let result = persistLockState(false, accepted: accepted, originKey: key)
        if result == .changed {
            cache[key] = CachedFavicon(
                image: accepted.image,
                pixelSHA256: accepted.pixelSHA256,
                priority: accepted.priority,
                resourceIdentity: accepted.resourceIdentity,
                kind: accepted.kind,
                isLocked: false
            )
        }
        return result
    }

    private func persistLockState(
        _ isLocked: Bool,
        accepted: CachedFavicon,
        originKey: String
    ) -> IconControlResult {
        guard let imageData = Self.serializedImageData(accepted.image) else { return .unavailable }
        let record = WebsiteFaviconAssetStore.Record(
            originKey: originKey,
            imageData: imageData,
            pixelSHA256: accepted.pixelSHA256,
            priority: accepted.priority,
            kind: accepted.kind.rawValue,
            isLocked: isLocked
        )
        switch assetStore.save(record) {
        case .saved: return .changed
        case .capacityExceeded: return .capacityExceeded
        case .corruptExistingRecord: return .corruptStorage
        case .invalidRecord, .unavailable: return .unavailable
        }
    }

    func refreshAndChooseIcon(
        for url: URL,
        completion: @escaping (IconControlResult) -> Void
    ) {
        guard let key = Self.originKey(for: url) else {
            completion(.unavailable)
            return
        }

        pendingFavicons.removeValue(forKey: key)
        let currentImage = cachedImage(for: key)
        let displacedOneShots = oneShotCompletions.removeValue(forKey: key) ?? []
        displacedOneShots.forEach { $0(currentImage) }
        inFlight.removeValue(forKey: key)?.task.cancel()
        scheduledRetries.removeValue(forKey: key)?.task.cancel()
        cooldownUntil.removeValue(forKey: key)
        explicitChoiceCompletions[key, default: []].append(completion)
        startRequest(
            for: key,
            fallbackURL: url,
            preferredURL: url,
            initialCachePolicy: .reloadIgnoringLocalCacheData,
            acceptanceMode: .explicitChoice
        )
    }

    func setAutomaticRetryDemand(consumerID: UUID, enabled: Bool) {
        guard var demand = demands[consumerID] else { return }
        guard demand.automaticallyRetries != enabled else { return }
        demand.automaticallyRetries = enabled
        demands[consumerID] = demand
        if enabled {
            ensureRequest(for: demand.originKey, fallbackURL: demand.url)
        } else if !hasAutomaticRetryDemand(for: demand.originKey) {
            scheduledRetries.removeValue(forKey: demand.originKey)?.task.cancel()
        }
    }

    /// Compatibility entry point for finite, non-UI callers and tests. These
    /// callbacks do not establish background retry demand after a failure.
    func load(for url: URL, completion: @escaping Completion) {
        guard let key = Self.originKey(for: url) else {
            completion(nil)
            return
        }
        if let cached = cachedImage(for: key) {
            completion(cached)
            return
        }
        if let until = cooldownUntil[key], until > monotonicClock() {
            completion(nil)
            return
        }
        oneShotCompletions[key, default: []].append(completion)
        ensureRequest(for: key, fallbackURL: url)
    }

    func cancel(consumerID: UUID) {
        guard let demand = demands.removeValue(forKey: consumerID) else { return }
        guard !hasDemand(for: demand.originKey),
              oneShotCompletions[demand.originKey]?.isEmpty != false else {
            return
        }
        if inFlight[demand.originKey]?.acceptanceMode == .explicitChoice {
            return
        }
        inFlight.removeValue(forKey: demand.originKey)?.task.cancel()
        scheduledRetries.removeValue(forKey: demand.originKey)?.task.cancel()
    }

    /// Called only after PanelController has revalidated the exact Slot,
    /// Runtime, committed URL and navigation generation for the DOM result.
    func setDOMCandidates(
        _ candidates: [Candidate],
        for committedURL: URL,
        source: DOMCandidateUpdateSource = .pageNavigation
    ) {
        guard let key = Self.originKey(for: committedURL) else { return }
        let normalized = Self.orderedCandidates(candidates)
            .filter { Self.isValidDOMCandidate($0, forPageOriginKey: key) }
            .prefix(Self.maximumDeclaredCandidates)
        let next = Array(normalized)
        guard domCandidates[key] != next else { return }
        storeDOMCandidates(next, for: key)

        let accepted = cachedFavicon(for: key)
        let targetIdentity = next.first?.resourceIdentity
        let initializationMayUpgradeFallback = source == .initialization
            && accepted?.kind == .conventional
            && next.first?.kind == .icon
        let initializationHasAcceptedIcon = source == .initialization
            && accepted != nil
            && !initializationMayUpgradeFallback
        if !initializationHasAcceptedIcon,
           let request = inFlight[key],
           request.acceptanceMode == .automatic,
           request.resourceIdentity != targetIdentity {
            inFlight.removeValue(forKey: key)?.task.cancel()
        }

        if let candidate = next.first,
           let entry = accepted,
           candidate.resourceIdentity == entry.resourceIdentity {
            let metadataChanged = candidate.priority != entry.priority || candidate.kind != entry.kind
            if metadataChanged {
                let updated = CachedFavicon(
                    image: entry.image,
                    pixelSHA256: entry.pixelSHA256,
                    priority: candidate.priority,
                    resourceIdentity: candidate.resourceIdentity,
                    kind: entry.kind,
                    isLocked: entry.isLocked
                )
                cache[key] = updated
                cacheOrder.removeAll { $0 == key }
                cacheOrder.append(key)
                recordCacheUpdate(.reusedSameResource)
            }
            return
        }

        // A new Runtime's first DOM read cannot replace an existing accepted
        // brand icon. It may still upgrade a conventional fallback to a formal
        // DOM icon; later reads retain the automatic confirmation path.
        guard !initializationHasAcceptedIcon else { return }

        let hasInterest = hasDemand(for: key) || oneShotCompletions[key]?.isEmpty == false
        let needsFetch = accepted.map { entry in
            next.first.map { Self.candidate($0, shouldReplace: entry) } ?? false
        } ?? true
        guard hasInterest, needsFetch else {
            return
        }
        if let request = inFlight[key], request.resourceIdentity == targetIdentity {
            return
        }
        // DOM declarations belong to the committed page origin even when a
        // valid HTTPS CDN serves the icon resource. A changed resource at
        // equal priority is also a real refresh request.
        // The currently cached image remains visible until that request succeeds.
        inFlight.removeValue(forKey: key)?.task.cancel()
        scheduledRetries.removeValue(forKey: key)?.task.cancel()
        cooldownUntil.removeValue(forKey: key)
        startRequest(for: key, fallbackURL: committedURL)
    }

    /// A user initiated WebView reload is the only caller allowed to bypass
    /// the local favicon cache while an image is already available. The old
    /// image stays in `cache` until a fresh response has decoded and passed
    /// visible-pixel validation; `finish` then notifies only current demands.
    func refreshAfterManualReload(
        candidateReadResult: DOMCandidateReadResult,
        committedURL: URL,
        for targetURLs: [URL]
    ) {
        let committedOriginKey = Self.originKey(for: committedURL)
        var refreshedOrigins = Set<String>()
        for targetURL in targetURLs {
            guard let key = Self.originKey(for: targetURL),
                  refreshedOrigins.insert(key).inserted else {
                continue
            }

            // The DOM read belongs only to the current committed page identity;
            // its icon resource may be served by a valid HTTPS CDN. A different
            // Tab home origin retains its own declarations and resources.
            if key == committedOriginKey {
                switch candidateReadResult {
                case let .candidates(candidates):
                    let normalized = Self.orderedCandidates(candidates)
                        .filter { Self.isValidDOMCandidate($0, forPageOriginKey: key) }
                        .prefix(Self.maximumDeclaredCandidates)
                    storeDOMCandidates(Array(normalized), for: key)
                case .noCandidates:
                    storeDOMCandidates([], for: key)
                case .readFailed:
                    // A transient DOM read failure must not discard declarations
                    // which were validated for this origin on an earlier page.
                    break
                }
            }

            // A manual refresh may need to update the Tab identity cache even
            // while its view is detached. finish() notifies only demands that
            // are still valid when the fresh result arrives.
            scheduledRetries.removeValue(forKey: key)?.task.cancel()
            cooldownUntil.removeValue(forKey: key)
            inFlight.removeValue(forKey: key)?.task.cancel()
            startRequest(
                for: key,
                fallbackURL: targetURL,
                preferredURL: targetURL,
                initialCachePolicy: .reloadIgnoringLocalCacheData
            )
        }
    }

    private func startRequest(
        for key: String,
        fallbackURL: URL,
        preferredURL: URL? = nil,
        initialCachePolicy: URLRequest.CachePolicy = .returnCacheDataElseLoad,
        acceptanceMode: AcceptanceMode = .automatic
    ) {
        guard inFlight[key] == nil else { return }
        let requestID = UUID()
        let initialURL = preferredURL
            ?? demands.values.first(where: { $0.originKey == key })?.url
            ?? fallbackURL
        let hints = domCandidates[key] ?? []
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            let initialReport = await self.fetchFavicon(
                for: initialURL,
                iconURLHints: hints,
                cachePolicy: initialCachePolicy
            )
            guard !Task.isCancelled,
                  self.inFlight[key]?.id == requestID else { return }
            self.recordFetchReport(initialReport, phase: "cached_first")
            if let cachedImage = initialReport.favicon {
                self.finish(cachedImage, for: key, requestID: requestID)
                return
            }

            self.pendingFavicons.removeValue(forKey: key)
            await self.retryWaiter(Self.automaticRetryDelay)
            guard !Task.isCancelled,
                  self.inFlight[key]?.id == requestID else { return }
            let freshReport = await self.fetchFavicon(
                for: initialURL,
                iconURLHints: self.domCandidates[key] ?? hints,
                cachePolicy: .reloadIgnoringLocalCacheData
            )
            guard !Task.isCancelled,
                  self.inFlight[key]?.id == requestID else { return }
            self.recordFetchReport(freshReport, phase: "fresh_retry")
            self.finish(freshReport.favicon, for: key, requestID: requestID)
        }
        inFlight[key] = InFlightRequest(
            id: requestID,
            resourceIdentity: hints.first?.resourceIdentity,
            acceptanceMode: acceptanceMode,
            task: task
        )
    }

    func setDOMCandidates(
        _ candidates: [URL],
        for committedURL: URL,
        source: DOMCandidateUpdateSource = .pageNavigation
    ) {
        setDOMCandidates(
            candidates.enumerated().map { Candidate.declared($0.element, sourceOrder: $0.offset) },
            for: committedURL,
            source: source
        )
    }

    private func ensureRequest(for key: String, fallbackURL: URL) {
        guard inFlight[key] == nil else { return }
        if let retry = scheduledRetries[key] {
            if retry.fireAt > monotonicClock() { return }
            scheduledRetries.removeValue(forKey: key)?.task.cancel()
        }
        if let until = cooldownUntil[key] {
            let remaining = until - monotonicClock()
            guard remaining <= 0 else {
                if hasAutomaticRetryDemand(for: key) {
                    scheduleRetry(for: key, fallbackURL: fallbackURL, after: remaining)
                }
                return
            }
            cooldownUntil.removeValue(forKey: key)
        }
        startRequest(for: key, fallbackURL: fallbackURL)
    }

    private func finish(_ fetched: FetchedFavicon?, for key: String, requestID: UUID) {
        guard let request = inFlight[key], request.id == requestID else { return }
        inFlight.removeValue(forKey: key)
        let oneShots = oneShotCompletions.removeValue(forKey: key) ?? []
        let existingImage = cachedImage(for: key)
        var cacheOutcome: CacheUpdateOutcome
        if let fetched {
            let acceptance = accept(fetched, for: key, mode: request.acceptanceMode)
            cacheOutcome = acceptance.cacheOutcome
            failureCycles.removeValue(forKey: key)
            cooldownUntil.removeValue(forKey: key)
            scheduledRetries.removeValue(forKey: key)?.task.cancel()
            if request.acceptanceMode == .explicitChoice {
                let result = acceptance.controlResult ?? .unavailable
                explicitChoiceCompletions.removeValue(forKey: key)?.forEach { $0(result) }
            }
        } else {
            pendingFavicons.removeValue(forKey: key)
            cacheOutcome = existingImage == nil ? .empty : .retainedPrevious
            let failureIndex = failureCycles[key, default: 0]
            let delay = Self.retryBackoff[min(failureIndex, Self.retryBackoff.count - 1)]
            failureCycles[key] = failureIndex + 1
            cooldownUntil[key] = monotonicClock() + delay
            if hasAutomaticRetryDemand(for: key) {
                let retryURL = demands.values.first(where: { $0.originKey == key })?.url
                    ?? URL(string: key)
                if let retryURL {
                    scheduleRetry(for: key, fallbackURL: retryURL, after: delay)
                }
            }
            if request.acceptanceMode == .explicitChoice {
                explicitChoiceCompletions.removeValue(forKey: key)?.forEach { $0(.fetchFailed) }
            }
        }
        recordCacheUpdate(cacheOutcome)
        if (cacheOutcome == .updated || cacheOutcome == .memoryOnlyUpdated), let fetched {
            notifyDemands(for: key, with: fetched.image)
        } else if existingImage == nil {
            notifyDemands(for: key, with: nil)
        }
        oneShots.forEach { $0(cache[key]?.image) }
    }

    private func hasDemand(for key: String) -> Bool {
        demands.values.contains { $0.originKey == key }
    }

    private func cachedImage(for key: String) -> NSImage? {
        cachedFavicon(for: key)?.image
    }

    private func cachedFavicon(for key: String) -> CachedFavicon? {
        if let cached = cache[key] {
            refreshMemoryCacheOrder(for: key)
            return cached
        }
        guard case let .record(record) = assetStore.load(originKey: key),
              let image = NSImage(data: record.imageData) else {
            return nil
        }
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = record.kind == Candidate.Kind.mask.rawValue
        guard Self.hasVisiblePixels(image),
              let pixelSHA256 = Self.normalizedPixelSHA256(of: image),
              pixelSHA256 == record.pixelSHA256,
              let kind = Candidate.Kind(rawValue: record.kind) else {
            assetStore.markCorrupt(originKey: key)
            return nil
        }
        let cached = CachedFavicon(
            image: image,
            pixelSHA256: pixelSHA256,
            priority: record.priority,
            resourceIdentity: nil,
            kind: kind,
            isLocked: record.isLocked
        )
        cache[key] = cached
        refreshMemoryCacheOrder(for: key)
        return cached
    }

    private func accept(
        _ fetched: FetchedFavicon,
        for key: String,
        mode: AcceptanceMode
    ) -> AcceptanceResult {
        let existing = cachedFavicon(for: key)
        let existingTemplateSemantics = existing?.kind == .mask
        let fetchedTemplateSemantics = fetched.kind == .mask
        if let existing,
           existing.pixelSHA256 == fetched.pixelSHA256,
           existingTemplateSemantics == fetchedTemplateSemantics {
            pendingFavicons.removeValue(forKey: key)
            cache[key] = CachedFavicon(
                image: existing.image,
                pixelSHA256: existing.pixelSHA256,
                priority: fetched.priority,
                resourceIdentity: fetched.resourceIdentity,
                kind: existing.kind,
                isLocked: existing.isLocked
            )
            refreshMemoryCacheOrder(for: key)
            return AcceptanceResult(cacheOutcome: .sameVisualContent, controlResult: .unchanged)
        }

        if let existing, existing.isLocked, mode == .automatic {
            pendingFavicons.removeValue(forKey: key)
            return AcceptanceResult(cacheOutcome: .locked, controlResult: nil)
        }

        let pending = pendingFavicons[key]?.fetched
        let pendingMatches = pending?.pixelSHA256 == fetched.pixelSHA256
            && (pending?.kind == .mask) == fetchedTemplateSemantics
        if existing != nil, mode == .automatic, !pendingMatches {
            pendingFavicons[key] = PendingFavicon(fetched: fetched)
            return AcceptanceResult(cacheOutcome: .awaitingConfirmation, controlResult: nil)
        }

        let locked = existing?.isLocked ?? false
        guard let imageData = Self.serializedImageData(fetched.image) else {
            return AcceptanceResult(cacheOutcome: .failed, controlResult: .unavailable)
        }
        let record = WebsiteFaviconAssetStore.Record(
            originKey: key,
            imageData: imageData,
            pixelSHA256: fetched.pixelSHA256,
            priority: fetched.priority,
            kind: fetched.kind.rawValue,
            isLocked: locked
        )
        let writeResult = assetStore.save(record)
        // Persistence failure does not make a validated icon unusable in this runtime.
        cache[key] = CachedFavicon(
            image: fetched.image,
            pixelSHA256: fetched.pixelSHA256,
            priority: fetched.priority,
            resourceIdentity: fetched.resourceIdentity,
            kind: fetched.kind,
            isLocked: locked
        )
        pendingFavicons.removeValue(forKey: key)
        refreshMemoryCacheOrder(for: key)

        let cacheOutcome: CacheUpdateOutcome
        let controlResult: IconControlResult
        switch writeResult {
        case .saved:
            cacheOutcome = .updated
            controlResult = .changed
        case .capacityExceeded:
            cacheOutcome = .memoryOnlyUpdated
            controlResult = .capacityExceeded
        case .corruptExistingRecord:
            cacheOutcome = .memoryOnlyUpdated
            controlResult = .corruptStorage
        case .invalidRecord, .unavailable:
            cacheOutcome = .memoryOnlyUpdated
            controlResult = .unavailable
        }
        return AcceptanceResult(cacheOutcome: cacheOutcome, controlResult: controlResult)
    }

    private func refreshMemoryCacheOrder(for key: String) {
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        trimMemoryCache()
    }

    private func trimMemoryCache() {
        while cacheOrder.count > Self.maximumCachedOrigins {
            let removedKey = cacheOrder.removeFirst()
            cache.removeValue(forKey: removedKey)
            pendingFavicons.removeValue(forKey: removedKey)
        }
    }

    private static let normalizedPixelSide = 32
    private static let normalizedPixelBitmapInfo = CGBitmapInfo.byteOrder32Big.union(
        CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    )

    private static func normalizedPixelData(of image: NSImage) -> Data? {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let source = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil),
              image.size.width > 0,
              image.size.height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }
        let side = normalizedPixelSide
        let bytesPerRow = side * 4
        var pixels = [UInt8](repeating: 0, count: side * bytesPerRow)
        let drawn = pixels.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(
                data: storage.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: normalizedPixelBitmapInfo.rawValue
            ) else {
                return false
            }
            context.clear(CGRect(x: 0, y: 0, width: side, height: side))
            context.interpolationQuality = .high
            let scale = min(
                CGFloat(side) / image.size.width,
                CGFloat(side) / image.size.height
            )
            let width = image.size.width * scale
            let height = image.size.height * scale
            context.draw(
                source,
                in: CGRect(
                    x: (CGFloat(side) - width) / 2,
                    y: (CGFloat(side) - height) / 2,
                    width: width,
                    height: height
                )
            )
            return true
        }
        guard drawn else { return nil }
        return Data(pixels)
    }

    private static func serializedImageData(_ image: NSImage) -> Data? {
        let side = normalizedPixelSide
        let bytesPerRow = side * 4
        guard let pixels = normalizedPixelData(of: image),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: pixels as CFData),
              let canonicalImage = CGImage(
                width: side,
                height: side,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: normalizedPixelBitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            return nil
        }

        let pngData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            pngData as CFMutableData,
            "public.png" as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, canonicalImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return pngData as Data
    }

    private static func normalizedPixelSHA256(of image: NSImage) -> String? {
        guard let pixels = normalizedPixelData(of: image) else { return nil }
        let digest = SHA256.hash(data: pixels)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func notifyDemands(for key: String, with image: NSImage?) {
        let callbacks = demands.compactMap { id, demand in
            demand.originKey == key ? (id, demand.completion) : nil
        }
        callbacks.forEach { $0.1(image) }
    }

    private func recordCacheUpdate(_ outcome: CacheUpdateOutcome) {
        diagnosticRecorder?.record(
            event: "favicon.cache_update",
            level: outcome == .failed || outcome == .memoryOnlyUpdated ? .warning : .notice,
            subsystem: "favicon",
            fields: ["outcome": .string(outcome.rawValue)]
        )
    }

    private func recordFetchReport(_ report: FetchReport, phase: String) {
        let reasons = report.failureStages.map(\.rawValue).sorted().joined(separator: ",")
        diagnosticRecorder?.record(
            event: "favicon.fetch_attempt",
            level: report.favicon == nil ? .notice : .info,
            subsystem: "favicon",
            fields: [
                "phase": .string(phase),
                "outcome": .string(report.favicon == nil ? "failed" : "loaded"),
                "candidate_count": .integer(Int64(report.candidateCount)),
                "failure_stages": reasons.isEmpty ? .null : .string(reasons)
            ]
        )
    }

    private func storeDOMCandidates(_ candidates: [Candidate], for key: String) {
        if candidates.isEmpty {
            domCandidates.removeValue(forKey: key)
            domCandidateOrder.removeAll { $0 == key }
            return
        }
        domCandidates[key] = candidates
        domCandidateOrder.removeAll { $0 == key }
        domCandidateOrder.append(key)
        while domCandidateOrder.count > Self.maximumDOMCandidateOrigins {
            domCandidates.removeValue(forKey: domCandidateOrder.removeFirst())
        }
    }

    private func hasAutomaticRetryDemand(for key: String) -> Bool {
        demands.values.contains { $0.originKey == key && $0.automaticallyRetries }
    }

    private func scheduleRetry(for key: String, fallbackURL: URL, after delay: TimeInterval) {
        guard hasAutomaticRetryDemand(for: key), scheduledRetries[key] == nil else { return }
        let id = UUID()
        let fireAt = monotonicClock() + max(0, delay)
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.retryWaiter(delay)
            guard !Task.isCancelled,
                  self.scheduledRetries[key]?.id == id else { return }
            self.scheduledRetries.removeValue(forKey: key)
            guard self.hasAutomaticRetryDemand(for: key), self.inFlight[key] == nil else { return }
            self.cooldownUntil.removeValue(forKey: key)
            self.startRequest(for: key, fallbackURL: fallbackURL)
        }
        scheduledRetries[key] = ScheduledRetry(id: id, fireAt: fireAt, task: task)
    }

    private func fetchFavicon(
        for url: URL,
        iconURLHints: [Candidate],
        cachePolicy: URLRequest.CachePolicy
    ) async -> FetchReport {
        let deadline = monotonicClock() + Self.requestBudget
        var seen = Set<String>()
        var declaredCount = 0
        var failureStages = Set<FailureStage>()

        for candidate in Self.orderedCandidates(iconURLHints).prefix(Self.maximumDeclaredCandidates) {
            guard monotonicClock() < deadline else {
                failureStages.insert(.requestTimedOut)
                return FetchReport(favicon: nil, failureStages: failureStages, candidateCount: declaredCount)
            }
            guard seen.insert(candidate.resourceIdentity).inserted else { continue }
            declaredCount += 1
            switch await fetchImage(
                from: candidate,
                cachePolicy: cachePolicy,
                deadline: deadline
            ) {
            case let .fetched(fetched):
                return FetchReport(
                    favicon: fetched,
                    failureStages: failureStages,
                    candidateCount: declaredCount
                )
            case let .failed(stage):
                failureStages.insert(stage)
            }
        }

        for pageURL in Self.pageDiscoveryURLs(for: url).prefix(Self.maximumDiscoveryPages) {
            guard monotonicClock() < deadline,
                  declaredCount < Self.maximumDeclaredCandidates else { break }
            let htmlResult = await fetchPageHTML(
                for: pageURL,
                cachePolicy: cachePolicy,
                deadline: deadline
            )
            let html: String
            let response: URLResponse
            switch htmlResult {
            case let .loaded(pageHTML, pageResponse):
                html = pageHTML
                response = pageResponse
            case let .failed(stage):
                failureStages.insert(stage)
                continue
            }
            let candidates = Self.discoveredFaviconCandidates(
                in: html,
                baseURL: response.url ?? pageURL,
                limit: Self.maximumDeclaredCandidates - declaredCount
            )
            for candidate in candidates {
                guard monotonicClock() < deadline else {
                    failureStages.insert(.requestTimedOut)
                    return FetchReport(
                        favicon: nil,
                        failureStages: failureStages,
                        candidateCount: declaredCount
                    )
                }
                guard seen.insert(candidate.resourceIdentity).inserted else { continue }
                declaredCount += 1
                switch await fetchImage(
                    from: candidate,
                    cachePolicy: cachePolicy,
                    deadline: deadline
                ) {
                case let .fetched(fetched):
                    return FetchReport(
                        favicon: fetched,
                        failureStages: failureStages,
                        candidateCount: declaredCount
                    )
                case let .failed(stage):
                    failureStages.insert(stage)
                }
            }
        }

        // Declared icons from the loaded page and the bounded HTML discovery
        // pass take precedence over conventional filenames such as favicon.ico.
        for (sourceOrder, candidateURL) in Self.fallbackFaviconURLs(for: url).enumerated()
            where seen.insert(Candidate.conventional(candidateURL).resourceIdentity).inserted {
            guard monotonicClock() < deadline else {
                failureStages.insert(.requestTimedOut)
                return FetchReport(
                    favicon: nil,
                    failureStages: failureStages,
                    candidateCount: declaredCount
                )
            }
            declaredCount += 1
            switch await fetchImage(
                from: Candidate.conventional(candidateURL, sourceOrder: sourceOrder),
                cachePolicy: cachePolicy,
                deadline: deadline
            ) {
            case let .fetched(fetched):
                return FetchReport(
                    favicon: fetched,
                    failureStages: failureStages,
                    candidateCount: declaredCount
                )
            case let .failed(stage):
                failureStages.insert(stage)
            }
        }
        if declaredCount == 0 {
            failureStages.insert(.noCandidates)
        }
        return FetchReport(
            favicon: nil,
            failureStages: failureStages,
            candidateCount: declaredCount
        )
    }

    static func pageDiscoveryURLs(for url: URL) -> [URL] {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme != nil,
              components.host != nil else { return [] }
        let origin = components
        components.path = "/"
        components.query = nil
        components.fragment = nil
        var pages = [components.url].compactMap { $0 }

        guard !origin.path.isEmpty, origin.path != "/" else { return pages }
        var pathComponents = origin
        pathComponents.query = nil
        pathComponents.fragment = nil
        if let pathURL = pathComponents.url,
           !pages.contains(pathURL) {
            pages.append(pathURL)
        }
        return pages
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

    private func fetchImage(
        from candidate: Candidate,
        cachePolicy: URLRequest.CachePolicy,
        deadline: TimeInterval
    ) async -> CandidateFetchResult {
        let url = candidate.url
        guard Self.isHTTPURL(url) else { return .failed(.requestFailed) }
        guard let timeout = effectiveTimeout(until: deadline) else {
            return .failed(.requestTimedOut)
        }
        var request = URLRequest(url: url)
        request.cachePolicy = cachePolicy
        request.timeoutInterval = timeout
        request.httpShouldHandleCookies = false
        request.setValue(
            "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
        do {
            let (data, response) = try await loadDataWithTimeout(request)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                return .failed(.httpStatus)
            }
            guard let image = NSImage(data: data) else { return .failed(.imageDecodeFailed) }
            guard Self.hasVisiblePixels(image) else { return .failed(.noVisiblePixels) }
            image.size = NSSize(width: 16, height: 16)
            image.isTemplate = candidate.kind == .mask
            guard let pixelSHA256 = Self.normalizedPixelSHA256(of: image) else {
                return .failed(.pixelNormalizationFailed)
            }
            return .fetched(FetchedFavicon(
                image: image,
                pixelSHA256: pixelSHA256,
                priority: candidate.priority,
                resourceIdentity: candidate.resourceIdentity,
                kind: candidate.kind
            ))
        } catch let error as URLError where error.code == .timedOut {
            return .failed(.requestTimedOut)
        } catch {
            return .failed(.requestFailed)
        }
    }

    private static func hasVisiblePixels(_ image: NSImage) -> Bool {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 32,
            pixelsHigh: 32,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return false
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(
            in: NSRect(x: 0, y: 0, width: 32, height: 32),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: nil
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
                    return true
                }
            }
        }
        return false
    }

    private func fetchPageHTML(
        for url: URL,
        cachePolicy: URLRequest.CachePolicy,
        deadline: TimeInterval
    ) async -> PageHTMLResult {
        guard Self.isHTTPURL(url) else { return .failed(.requestFailed) }
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return .failed(.requestFailed)
        }
        // Favicon discovery does not need query tokens or fragments. Avoid
        // replaying page-specific tracking/session parameters through the
        // auxiliary URLSession request.
        components.query = nil
        components.fragment = nil
        guard let pageURL = components.url else { return .failed(.requestFailed) }
        guard let timeout = effectiveTimeout(until: deadline) else {
            return .failed(.requestTimedOut)
        }
        var request = URLRequest(url: pageURL)
        request.cachePolicy = cachePolicy
        request.timeoutInterval = timeout
        request.httpShouldHandleCookies = false
        request.setValue(
            "text/html,application/xhtml+xml;q=0.9,*/*;q=0.1",
            forHTTPHeaderField: "Accept"
        )
        do {
            let (data, response) = try await loadDataWithTimeout(request)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                return .failed(.httpStatus)
            }
            guard let html = String(data: data, encoding: .utf8) else {
                return .failed(.htmlDecodeFailed)
            }
            return .loaded(html, response)
        } catch let error as URLError where error.code == .timedOut {
            return .failed(.requestTimedOut)
        } catch {
            return .failed(.requestFailed)
        }
    }

    private func effectiveTimeout(until deadline: TimeInterval) -> TimeInterval? {
        let remaining = deadline - monotonicClock()
        guard remaining > 0 else { return nil }
        return min(Self.requestTimeout, remaining)
    }

    private func loadDataWithTimeout(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
            group.addTask {
                try await self.dataLoader(request)
            }
            group.addTask {
                let nanoseconds = UInt64(max(request.timeoutInterval, 0) * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw URLError(.unknown)
            }
            return result
        }
    }
}

@MainActor
final class ExternalWebAppTabView: NSView, RailHoverInteractionOwner {
    typealias FaviconLoadHandler = @MainActor (
        URL,
        @escaping (NSImage?) -> Void
    ) -> Void
    typealias FaviconCancelHandler = @MainActor (UUID) -> Void

    let slotID: UUID

    var onSelect: ((UUID) -> Void)?
    var onReturnHome: ((UUID) -> Void)?
    var onReload: ((UUID) -> Void)?
    var onEdit: ((UUID) -> Void)?
    var onRemove: ((UUID) -> Void)?
    var onSetWebsiteMode: ((UUID, WebsiteMode) -> Void)?
    var onSetWindowSize: ((UUID, SimpleViewportPreset) -> Void)?
    var onSetZoom: ((UUID, CGFloat) -> Void)?
    var onSetResidency: ((UUID, SlotResidencyPolicy) -> Void)? // legacy command/test seam
    var onSetRuntimeRetention: ((UUID, SlotRuntimeRetentionPreference) -> Void)?
    var onSetBackgroundMedia: ((UUID, BackgroundMediaPolicy) -> Void)?
    var onSetBrowserProfile: ((UUID, UUID?) -> Void)?
    var onOpenInNewTabWithBrowserProfile: ((UUID, UUID?) -> Void)?
    var onManageBrowserProfiles: (() -> Void)?
    var onPointerMoved: ((NSEvent) -> Void)?
    var onDragChanged: ((UUID, NSEvent) -> Void)?
    var onDragEnded: ((UUID) -> Void)?

    private let attentionSurfaceView = AttentionStyleSurfaceView(
        frame: .zero,
        geometry: .railTab
    )
    private let requestFavicon: FaviconLoadHandler
    private let cancelFavicon: FaviconCancelHandler
    private let faviconConsumerID: UUID
    private let iconView = NSImageView()
    private let unreadDotView = ClassicUnreadDotView()
    private let label = NSTextField(labelWithString: "")
    private let shapeLayer = CAShapeLayer()
    private var trackingAreaReference: NSTrackingArea?
    private var isActive = false
    private var isResident = false
    private var isHovered = false
    private var isHoverInteractionSuspended = false
    private var dockInfluence: CGFloat = 0
    private var mouseDownLocation: NSPoint?
    private var isDragging = false
    private var renderingProfile: WebRenderingProfile = .canonicalDefault
    private var runtimeRetentionPreference: SlotRuntimeRetentionPreference = .automatic
    private var windowSizeEditingEnabled = true
    private var backgroundMediaPolicy: BackgroundMediaPolicy = .pauseWhenInactive
    private var webAppName = ""
    private var faviconHomeURL: URL?
    private var browserProfileID: UUID?
    private var browserProfileMenuOptions: [BrowserProfileMenuOption] = [.defaultProfile()]
    private var browserProfileAssignmentEnabled = true
    private var browserProfileDuplicationEnabled = true
    private var faviconOriginKey: String?
    private var loadedFaviconOriginKey: String?
    private var subscribedFaviconOriginKey: String?
    private var faviconRequestGeneration: UInt64 = 0
    private var sourceIcon: NSImage?
    private var grayscaleIcon: NSImage?
    private var sourceIconLuminance: CGFloat?
    private var isUnreadResponse = false
    private var attentionStyle: TabAttentionStyle = .dot
    private var attentionPalette: TabAttentionPalette = .red

    private static let grayscaleContext = CIContext(options: nil)

    var preferredWidth: CGFloat {
        // Resting tabs are icon-only. Only the hovered row fully expands;
        // nearby Dock influence is intentionally capped so labels do not leak.
        let hoverInfluence: CGFloat = isHovered ? 1 : min(dockInfluence, 0.12)
        return ExternalTabMetrics.width(isActive: isActive, dockInfluence: hoverInfluence)
    }

    var isShowingLabel: Bool { isActive || isHovered }
    var displayedLabelText: String { label.stringValue }
    var isActiveTab: Bool { isActive }
    var isResidentRuntime: Bool { isResident }
    var displayedIcon: NSImage? { iconView.image }
    var displayedIconAlpha: CGFloat { iconView.alphaValue }
    var isShowingUnreadResponse: Bool { isUnreadResponse }
    var unreadResponseFrame: NSRect { isUnreadResponse ? bounds : .zero }
    var iconFrame: NSRect { iconView.frame }
    var unreadResponseColor: NSColor? {
        isUnreadResponse ? displayedTabFillColor : nil
    }
    var displayedActiveTabFillColor: NSColor? {
        guard isActive else { return nil }
        return displayedTabFillColor
    }
    var displayedTabFillColor: NSColor? {
        shapeLayer.fillColor.flatMap(NSColor.init(cgColor:))
    }
    var displayedActiveTabForegroundColor: NSColor? {
        guard isActive else { return nil }
        return label.textColor
    }
    var displayedIconTintColor: NSColor? { iconView.contentTintColor }
    var displayedIconContrastBackgroundColor: NSColor? {
        iconView.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))
    }
    var displayedAttentionStyle: TabAttentionStyle { attentionStyle }
    var displayedAttentionPalette: TabAttentionPalette { attentionPalette }
    var attentionSurfaceEffect: AttentionStyleEffect { attentionSurfaceView.renderedEffect }
    var showsClassicUnreadDot: Bool { !unreadDotView.isHidden }
    var attentionSurfaceUsesSharedRenderer: Bool {
        attentionSurfaceView.renderedPaletteRole
            == attentionStyle.configuration(for: attentionPalette).paletteRole
    }
    var attentionSurfaceMotionIsActive: Bool {
        attentionSurfaceView.isContinuousMotionActive
    }
    var attentionSurfaceReduceMotionIsEnabled: Bool {
        attentionSurfaceView.isReduceMotionEnabled
    }

    init(
        slotID: UUID,
        faviconLoader: FaviconLoadHandler? = nil,
        faviconCanceller: FaviconCancelHandler? = nil
    ) {
        self.slotID = slotID
        let faviconConsumerID = UUID()
        self.faviconConsumerID = faviconConsumerID
        self.requestFavicon = faviconLoader ?? { url, completion in
            WebsiteFaviconProvider.shared.subscribe(
                for: url,
                consumerID: faviconConsumerID,
                automaticallyRetries: false,
                completion: completion
            )
        }
        self.cancelFavicon = faviconCanceller ?? {
            WebsiteFaviconProvider.shared.cancel(consumerID: $0)
        }
        super.init(frame: .zero)

        wantsLayer = true
        layer?.masksToBounds = false
        layer?.addSublayer(shapeLayer)
        attentionSurfaceView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(attentionSurfaceView)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.masksToBounds = true
        iconView.layer?.cornerRadius = 3.5
        setSourceIcon(Self.fallbackIcon())
        addSubview(iconView)
        unreadDotView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(unreadDotView, positioned: .above, relativeTo: iconView)

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
            attentionSurfaceView.leadingAnchor.constraint(equalTo: leadingAnchor),
            attentionSurfaceView.trailingAnchor.constraint(equalTo: trailingAnchor),
            attentionSurfaceView.topAnchor.constraint(equalTo: topAnchor),
            attentionSurfaceView.bottomAnchor.constraint(equalTo: bottomAnchor),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            unreadDotView.centerXAnchor.constraint(equalTo: iconView.trailingAnchor, constant: -1),
            unreadDotView.centerYAnchor.constraint(equalTo: iconView.topAnchor, constant: 1),
            unreadDotView.widthAnchor.constraint(equalToConstant: ClassicUnreadDotView.diameter),
            unreadDotView.heightAnchor.constraint(equalToConstant: ClassicUnreadDotView.diameter),
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
        bounds.contains(point) ? self : nil
    }

    override func layout() {
        super.layout()
        // Rail magnification animates the tab's width. Refresh cursor rects so
        // the registered arrow rect always covers the expanded row.
        window?.invalidateCursorRects(for: self)
        updateShape()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        // Keep the Tab's normal arrow cursor across its complete animated
        // frame as Dock magnification changes the row width.
        addCursorRect(bounds, cursor: .arrow)
    }

    func setDockInfluence(_ influence: CGFloat) {
        dockInfluence = min(max(influence, 0), 1)
    }

    func setHovered(_ hovered: Bool) {
        guard !isHoverInteractionSuspended || !hovered else { return }
        guard isHovered != hovered else { return }
        isHovered = hovered
        label.isHidden = !(isActive || hovered)
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
        updateAppearance()
        updateAccessibilityLabel()
    }

    func setAttentionStyle(_ style: TabAttentionStyle, palette: TabAttentionPalette? = nil) {
        let nextPalette = palette ?? attentionPalette
        guard attentionStyle != style || attentionPalette != nextPalette else { return }
        attentionStyle = style
        attentionPalette = nextPalette
        updateAppearance()
    }

    func setAttentionStyleReduceMotionOverride(_ value: Bool?) {
        attentionSurfaceView.setReduceMotionOverride(value)
    }

    func setAttentionPresentationVisible(_ visible: Bool) {
        attentionSurfaceView.setPresentationVisible(visible)
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
        faviconHomeURL = profile.homeURL
        browserProfileID = profile.browserProfileID
        renderingProfile = profile.renderingProfile.normalized()
        runtimeRetentionPreference = profile.runtimeRetentionPreference
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
        makeContextMenu()
    }

    func makeContextMenu() -> NSMenu {
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
        let iconState = faviconHomeURL.map {
            WebsiteFaviconProvider.shared.iconControlState(for: $0)
        } ?? WebsiteFaviconProvider.IconControlState(hasAcceptedIcon: false, isLocked: false)
        let lockIcon = NSMenuItem(
            title: "Lock Current Icon",
            action: #selector(lockCurrentIconFromMenu(_:)),
            keyEquivalent: ""
        )
        lockIcon.target = self
        lockIcon.state = iconState.isLocked ? .on : .off
        lockIcon.isEnabled = iconState.hasAcceptedIcon && !iconState.isLocked
        menu.addItem(lockIcon)
        let unlockIcon = NSMenuItem(
            title: "Unlock Icon",
            action: #selector(unlockIconFromMenu(_:)),
            keyEquivalent: ""
        )
        unlockIcon.target = self
        unlockIcon.isEnabled = iconState.hasAcceptedIcon && iconState.isLocked
        menu.addItem(unlockIcon)
        let refreshIcon = NSMenuItem(
            title: "Refresh & Choose Icon",
            action: #selector(refreshAndChooseIconFromMenu(_:)),
            keyEquivalent: ""
        )
        refreshIcon.target = self
        refreshIcon.isEnabled = faviconHomeURL != nil
        menu.addItem(refreshIcon)
        let iconScope = NSMenuItem(
            title: "Shared by tabs on this website",
            action: nil,
            keyEquivalent: ""
        )
        iconScope.isEnabled = false
        iconScope.toolTip = "Tabs with the same website origin share one favicon and lock state."
        menu.addItem(iconScope)
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
            : "Window size is fixed globally in Settings → General."
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

        let runtimeRetention = NSMenuItem(
            title: "Runtime Retention",
            action: nil,
            keyEquivalent: ""
        )
        let runtimeRetentionMenu = NSMenu(title: "Runtime Retention")
        for preference in SlotRuntimeRetentionPreference.allCases {
            let item = NSMenuItem(
                title: preference.displayName,
                action: #selector(setRuntimeRetentionFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = preference.rawValue
            item.state = preference == runtimeRetentionPreference ? .on : .off
            runtimeRetentionMenu.addItem(item)
        }
        runtimeRetention.submenu = runtimeRetentionMenu
        menu.addItem(runtimeRetention)

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

    @objc private func lockCurrentIconFromMenu(_ sender: NSMenuItem) {
        guard let faviconHomeURL else { return }
        presentFaviconControlFailure(
            WebsiteFaviconProvider.shared.lockCurrentIcon(for: faviconHomeURL)
        )
    }

    @objc private func unlockIconFromMenu(_ sender: NSMenuItem) {
        guard let faviconHomeURL else { return }
        presentFaviconControlFailure(
            WebsiteFaviconProvider.shared.unlockIcon(for: faviconHomeURL)
        )
    }

    @objc private func refreshAndChooseIconFromMenu(_ sender: NSMenuItem) {
        guard let faviconHomeURL else { return }
        WebsiteFaviconProvider.shared.refreshAndChooseIcon(for: faviconHomeURL) { [weak self] result in
            self?.presentFaviconControlFailure(result)
        }
    }

    private func presentFaviconControlFailure(
        _ result: WebsiteFaviconProvider.IconControlResult
    ) {
        guard !result.succeeded else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        switch result {
        case .capacityExceeded:
            alert.messageText = "The icon could not be saved"
            alert.informativeText = "The favicon asset store is full. Existing locked icons were kept."
        case .corruptStorage:
            alert.messageText = "The saved icon could not be read"
            alert.informativeText = "The existing favicon file was left unchanged."
        case .fetchFailed:
            alert.messageText = "No new icon was selected"
            alert.informativeText = "The current icon and lock state were kept."
        case .noAcceptedIcon:
            alert.messageText = "There is no accepted icon to lock"
            alert.informativeText = "Choose a valid website icon first."
        case .unavailable:
            alert.messageText = "The icon could not be saved"
            alert.informativeText = "The current icon and lock state were kept."
        case .changed, .unchanged:
            return
        }
        guard let window else {
            NSSound.beep()
            return
        }
        alert.beginSheetModal(for: window)
    }

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

    @objc private func setRuntimeRetentionFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let preference = SlotRuntimeRetentionPreference(rawValue: raw) else { return }
        onSetRuntimeRetention?(slotID, preference)
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
        WebsiteFaviconProvider.shared.setAutomaticRetryDemand(
            consumerID: faviconConsumerID,
            enabled: isActive
        )
        if key != faviconOriginKey {
            cancelFavicon(faviconConsumerID)
            faviconOriginKey = key
            loadedFaviconOriginKey = nil
            subscribedFaviconOriginKey = nil
            faviconRequestGeneration &+= 1
            setSourceIcon(Self.fallbackIcon())
        }
        guard let key,
              loadedFaviconOriginKey != key,
              subscribedFaviconOriginKey != key else { return }

        subscribedFaviconOriginKey = key
        let requestGeneration = faviconRequestGeneration
        requestFavicon(url) { [weak self] image in
            guard let self,
                  self.faviconOriginKey == key,
                  self.faviconRequestGeneration == requestGeneration else { return }
            if image != nil {
                self.loadedFaviconOriginKey = key
            }
            let projection = self.setSourceIcon(image ?? Self.fallbackIcon())
            let outcome = image == nil && projection != .noImageDisplayed
                ? WebsiteFaviconProvider.ProjectionOutcome.fallbackDisplayed
                : projection
            WebsiteFaviconProvider.shared.recordProjection(outcome, surface: "tab")
        }
        WebsiteFaviconProvider.shared.setAutomaticRetryDemand(
            consumerID: faviconConsumerID,
            enabled: isActive
        )
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        if newSuperview == nil {
            cancelFavicon(faviconConsumerID)
            subscribedFaviconOriginKey = nil
            faviconRequestGeneration &+= 1
        }
        super.viewWillMove(toSuperview: newSuperview)
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            applyResolvedAppearance()
        }
    }

    private func applyResolvedAppearance() {
        label.isHidden = !(isActive || isHovered)
        label.font = .systemFont(ofSize: 11.5, weight: isActive ? .semibold : .medium)
        let attentionConfiguration = attentionStyle.configuration(for: attentionPalette)
        let attentionForeground = attentionConfiguration.foregroundColor
        label.textColor = isUnreadResponse
            ? attentionForeground
            : (isActive ? .labelColor : .secondaryLabelColor)
        applyIconAppearance(attentionForeground: attentionForeground)
        attentionSurfaceView.configure(
            style: attentionStyle,
            palette: attentionPalette,
            showsAttention: isUnreadResponse
        )
        unreadDotView.isHidden = !(isUnreadResponse && attentionStyle == .dot)
        updateShape()
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
        label.stringValue = displayedPresentationTitle
        updateAccessibilityLabel()
    }

    private func updateAccessibilityLabel() {
        var parts = [displayedPresentationTitle]
        if isUnreadResponse {
            parts.append("Unread response")
        }
        setAccessibilityLabel(parts.joined(separator: " · "))
    }

    @discardableResult
    func setSourceIcon(_ image: NSImage?) -> WebsiteFaviconProvider.ProjectionOutcome {
        sourceIcon = image
        if let image, !image.isTemplate {
            grayscaleIcon = Self.grayscaleImage(from: image)
            sourceIconLuminance = Self.averageVisibleLuminance(of: image)
        } else {
            grayscaleIcon = nil
            sourceIconLuminance = nil
        }
        applyIconAppearance()
        guard iconView.image != nil else { return .noImageDisplayed }
        return image == nil ? .fallbackDisplayed : .iconDisplayed
    }

    private func applyIconAppearance(attentionForeground: NSColor? = nil) {
        let base = sourceIcon ?? Self.fallbackIcon()
        if base?.isTemplate == true {
            iconView.image = base
            iconView.contentTintColor = isResident
                ? (isUnreadResponse
                    ? (attentionForeground ?? attentionStyle.configuration(for: attentionPalette).foregroundColor)
                    : .labelColor)
                : .tertiaryLabelColor
        } else {
            iconView.image = isResident ? base : (grayscaleIcon ?? base)
            iconView.contentTintColor = nil
        }
        let contrastBackground = residentIconContrastBackgroundColor()
        iconView.layer?.backgroundColor = contrastBackground?.cgColor
        iconView.layer?.borderColor = contrastBackground.map {
            $0.withAlphaComponent(0.28).cgColor
        }
        iconView.layer?.borderWidth = contrastBackground == nil ? 0 : 0.5
        iconView.alphaValue = isResident ? 1 : (isHovered ? 0.60 : 0.38)
    }

    private func residentIconContrastBackgroundColor() -> NSColor? {
        guard isResident,
              sourceIcon?.isTemplate != true,
              let sourceIconLuminance else {
            return nil
        }
        let appearance = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
        if appearance == .darkAqua, sourceIconLuminance < 0.55 {
            return NSColor.white.withAlphaComponent(0.92)
        }
        if appearance == .aqua, sourceIconLuminance > 0.82 {
            return NSColor.black.withAlphaComponent(0.78)
        }
        return nil
    }

    private func updateRuntimeToolTip() {
        let state = isResident ? "Open" : "Released"
        toolTip = "\(displayedPresentationTitle) · \(state)"
    }

    private func updateShape() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        shapeLayer.frame = bounds
        let path = ExternalTabMetrics.tabSurfacePath(in: bounds)
        shapeLayer.path = path
        shapeLayer.fillColor = ExternalTabSurfacePalette.tabFill(
            isUnread: isUnreadResponse,
            isHovered: isHovered,
            style: attentionStyle
        ).cgColor
        // The animated PanelInteractionBorderView owns the active outline.
        // Keep the Tab surface profile-independent and let the shared outline
        // plus active typography identify selection.
        shapeLayer.strokeColor = NSColor.clear.cgColor
        shapeLayer.lineWidth = 0
        if isActive {
            layer?.shadowOpacity = 0
            layer?.shadowPath = nil
        } else {
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = isHovered ? 0.16 : 0.08
            layer?.shadowRadius = isHovered ? 5 : 2
            layer?.shadowOffset = NSSize(width: -1, height: -1)
            layer?.shadowPath = path
        }
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

    private static func averageVisibleLuminance(of image: NSImage) -> CGFloat? {
        guard let data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data),
              bitmap.pixelsWide > 0,
              bitmap.pixelsHigh > 0 else {
            return nil
        }
        var luminanceTotal: CGFloat = 0
        var alphaTotal: CGFloat = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                let alpha = color.alphaComponent
                guard alpha > 0.02 else { continue }
                let luminance = 0.2126 * color.redComponent
                    + 0.7152 * color.greenComponent
                    + 0.0722 * color.blueComponent
                luminanceTotal += luminance * alpha
                alphaTotal += alpha
            }
        }
        guard alphaTotal > 0 else { return nil }
        return luminanceTotal / alphaTotal
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
        // Keep the control's normal arrow cursor across its animated frame.
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
        // Keep the control's normal arrow cursor across its animated frame.
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
        // Keep the control's normal arrow cursor across its animated frame.
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
