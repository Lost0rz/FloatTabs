import AppKit
import Foundation
import QuartzCore
import WebKit

/// AppKit owns the shell so hit testing and WebKit focus remain explicit.
final class PanelRootView: NSView {
    let externalControlZoneView: ExternalControlZoneView
    let webPanelContainerView: WebPanelContainerView
    let perimeterDragView: PanelPerimeterDragView
    let interactionBorderView: PanelInteractionBorderView
    let resizeHandleView: PanelResizeHandleView
    let resizeReadoutView: ResizeReadoutView

    var onResizeEnded: (() -> Void)?

    init() {
        externalControlZoneView = ExternalControlZoneView()
        webPanelContainerView = WebPanelContainerView()
        perimeterDragView = PanelPerimeterDragView()
        interactionBorderView = PanelInteractionBorderView()
        resizeHandleView = PanelResizeHandleView()
        resizeReadoutView = ResizeReadoutView()

        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        externalControlZoneView.translatesAutoresizingMaskIntoConstraints = false
        webPanelContainerView.translatesAutoresizingMaskIntoConstraints = false
        perimeterDragView.translatesAutoresizingMaskIntoConstraints = false
        interactionBorderView.translatesAutoresizingMaskIntoConstraints = false
        resizeHandleView.translatesAutoresizingMaskIntoConstraints = false
        resizeReadoutView.translatesAutoresizingMaskIntoConstraints = false

        // WebKit remains visually clean. The movement layer sits above it only
        // for the deliberately tiny top/bottom overlap, while the animated frame
        // is presentation-only and never participates in hit testing.
        addSubview(webPanelContainerView)
        addSubview(perimeterDragView)
        addSubview(externalControlZoneView)
        // Presentation-only and non-hit-testing, but deliberately above the tab rail so
        // inactive tabs cannot cover the animated frame. The active tab is cut into
        // the same outline below instead of drawing a second independent ring.
        addSubview(interactionBorderView)
        addSubview(resizeReadoutView)
        addSubview(resizeHandleView)

        NSLayoutConstraint.activate([
            externalControlZoneView.leadingAnchor.constraint(equalTo: leadingAnchor),
            externalControlZoneView.topAnchor.constraint(
                equalTo: topAnchor,
                constant: PanelMetrics.outerInteractionGutter
            ),
            externalControlZoneView.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: -PanelMetrics.outerInteractionGutter
            ),
            externalControlZoneView.widthAnchor.constraint(
                equalToConstant: PanelMetrics.externalControlZoneWidth
            ),

            webPanelContainerView.leadingAnchor.constraint(
                equalTo: externalControlZoneView.trailingAnchor
            ),
            webPanelContainerView.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -PanelMetrics.outerInteractionGutter
            ),
            webPanelContainerView.topAnchor.constraint(
                equalTo: topAnchor,
                constant: PanelMetrics.outerInteractionGutter
            ),
            webPanelContainerView.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: -PanelMetrics.outerInteractionGutter
            ),

            perimeterDragView.leadingAnchor.constraint(equalTo: leadingAnchor),
            perimeterDragView.trailingAnchor.constraint(equalTo: trailingAnchor),
            perimeterDragView.topAnchor.constraint(equalTo: topAnchor),
            perimeterDragView.bottomAnchor.constraint(equalTo: bottomAnchor),

            interactionBorderView.leadingAnchor.constraint(equalTo: leadingAnchor),
            interactionBorderView.trailingAnchor.constraint(equalTo: trailingAnchor),
            interactionBorderView.topAnchor.constraint(equalTo: topAnchor),
            interactionBorderView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Keep the complete resize target inside the visible Web corner.
            // Real-Mac acceptance showed the transparent outer gutter was an
            // unreliable acquisition surface, while the in-page area was stable.
            resizeHandleView.trailingAnchor.constraint(
                equalTo: webPanelContainerView.trailingAnchor
            ),
            resizeHandleView.bottomAnchor.constraint(
                equalTo: webPanelContainerView.bottomAnchor
            ),
            resizeHandleView.widthAnchor.constraint(equalToConstant: PanelMetrics.resizeHandleSize),
            resizeHandleView.heightAnchor.constraint(equalToConstant: PanelMetrics.resizeHandleSize),

            resizeReadoutView.trailingAnchor.constraint(
                equalTo: resizeHandleView.leadingAnchor,
                constant: -8
            ),
            resizeReadoutView.bottomAnchor.constraint(
                equalTo: webPanelContainerView.bottomAnchor,
                constant: -8
            ),
        ])

        externalControlZoneView.onActiveTabGeometryChange = { [weak self] in
            self?.synchronizeInteractionBorderGeometry()
        }

        resizeHandleView.onViewportSizeChange = { [weak self] viewportSize in
            self?.resizeReadoutView.update(viewportSize: viewportSize)
            self?.resizeReadoutView.isHidden = false
        }
        resizeHandleView.onResizeEnded = { [weak self] in
            self?.resizeReadoutView.isHidden = true
            self?.onResizeEnded?()
        }
    }

    convenience init(webView: WKWebView) {
        self.init()
        webPanelContainerView.show(webView: webView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        synchronizeInteractionBorderGeometry()
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // A transparent pixel that is still inside the FloatTabs window belongs to
        // FloatTabs. Returning self here is a safety net against accidental desktop
        // click-through; functional move/resize/tab views still win through normal
        // subview hit testing.
        return super.hitTest(point)
    }

    private func synchronizeInteractionBorderGeometry() {
        interactionBorderView.targetWebFrame = webPanelContainerView.frame
        interactionBorderView.activeTabFrame = externalControlZoneView.activeTabFrame(in: self)
    }
}

/// A visual-only Siri-like flowing frame. It sits outside the Web surface and
/// makes the movement shell discoverable without turning the gutter into heavy
/// chrome. The border never consumes mouse events.
final class PanelInteractionBorderView: NSView {
    private let gradientLayer = CAGradientLayer()
    private let borderMask = CAShapeLayer()
    private var borderTheme: PanelBorderTheme = .rainbow
    private var customBorderColor: NSColor = .systemBlue

    var targetWebFrame: NSRect = .zero {
        didSet {
            if oldValue != targetWebFrame {
                needsLayout = true
            }
        }
    }

    var activeTabFrame: NSRect? {
        didSet {
            if oldValue != activeTabFrame {
                needsLayout = true
            }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        gradientLayer.opacity = 0.72

        borderMask.fillColor = NSColor.clear.cgColor
        borderMask.strokeColor = NSColor.white.cgColor
        borderMask.lineWidth = PanelMetrics.interactionBorderLineWidth
        borderMask.lineJoin = .round
        borderMask.lineCap = .round
        gradientLayer.mask = borderMask
        layer?.addSublayer(gradientLayer)
        applyBorderAppearance()
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    func apply(theme: PanelBorderTheme, customColor: NSColor) {
        borderTheme = theme
        customBorderColor = customColor
        applyBorderAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyBorderAppearance()
    }

    private func applyBorderAppearance() {
        gradientLayer.removeAnimation(forKey: "FloatTabs.interactionBorderFlow")

        if borderTheme == .rainbow {
            gradientLayer.type = .conic
            gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)
            let palettes = Self.flowPalettes
            gradientLayer.colors = palettes.first
            gradientLayer.locations = [0, 0.22, 0.48, 0.74, 1]

            let flow = CAKeyframeAnimation(keyPath: "colors")
            flow.values = palettes
            flow.keyTimes = [0, 0.25, 0.5, 0.75, 1]
            flow.duration = 3.2
            flow.repeatCount = .infinity
            flow.calculationMode = .linear
            gradientLayer.add(flow, forKey: "FloatTabs.interactionBorderFlow")
        } else {
            let color = borderTheme.solidColor ?? customBorderColor
            gradientLayer.type = .axial
            gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
            gradientLayer.colors = [color.cgColor, color.cgColor]
            gradientLayer.locations = [0, 1]
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        gradientLayer.frame = bounds

        guard targetWebFrame.width > 0, targetWebFrame.height > 0 else {
            borderMask.path = nil
            return
        }

        borderMask.path = Self.outlinePath(
            webFrame: targetWebFrame,
            activeTabFrame: activeTabFrame,
            clippingBounds: bounds
        )
    }

    static func outlinePath(
        webFrame: NSRect,
        activeTabFrame: NSRect?,
        clippingBounds: NSRect? = nil
    ) -> CGPath {
        let outset = PanelMetrics.interactionBorderOutset
        let webRect = webFrame.insetBy(dx: -outset, dy: -outset)
        let webRadius = min(
            PanelMetrics.webPanelCornerRadius + outset,
            min(webRect.width, webRect.height) / 2
        )

        func plainRoundedWebPath() -> CGPath {
            CGPath(
                roundedRect: webRect,
                cornerWidth: webRadius,
                cornerHeight: webRadius,
                transform: nil
            )
        }

        guard let activeTabFrame else {
            return plainRoundedWebPath()
        }

        let tabRect = activeTabFrame.insetBy(dx: -outset, dy: -outset)
        let joinBottom = max(tabRect.minY, webRect.minY + webRadius + 1)
        let joinTop = min(tabRect.maxY, webRect.maxY - webRadius - 1)
        guard joinTop - joinBottom >= 8 else {
            return plainRoundedWebPath()
        }

        var tabLeft = tabRect.minX
        if let clippingBounds {
            tabLeft = max(
                tabLeft,
                clippingBounds.minX + PanelMetrics.interactionBorderLineWidth / 2
            )
        }
        guard tabLeft < webRect.minX - 1 else {
            return plainRoundedWebPath()
        }

        let tabRadius = min(
            ExternalTabMetrics.tabRadius + outset,
            (joinTop - joinBottom) / 2
        )
        let path = CGMutablePath()

        // Walk clockwise around the Web surface. On the left edge, detour around
        // the active tab and deliberately omit its right edge, producing one
        // continuous page+tab silhouette rather than two overlapping rings.
        path.move(to: CGPoint(x: webRect.minX + webRadius, y: webRect.maxY))
        path.addLine(to: CGPoint(x: webRect.maxX - webRadius, y: webRect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: webRect.maxX, y: webRect.maxY - webRadius),
            control: CGPoint(x: webRect.maxX, y: webRect.maxY)
        )
        path.addLine(to: CGPoint(x: webRect.maxX, y: webRect.minY + webRadius))
        path.addQuadCurve(
            to: CGPoint(x: webRect.maxX - webRadius, y: webRect.minY),
            control: CGPoint(x: webRect.maxX, y: webRect.minY)
        )
        path.addLine(to: CGPoint(x: webRect.minX + webRadius, y: webRect.minY))
        path.addQuadCurve(
            to: CGPoint(x: webRect.minX, y: webRect.minY + webRadius),
            control: CGPoint(x: webRect.minX, y: webRect.minY)
        )
        path.addLine(to: CGPoint(x: webRect.minX, y: joinBottom))
        path.addLine(to: CGPoint(x: tabLeft + tabRadius, y: joinBottom))
        path.addQuadCurve(
            to: CGPoint(x: tabLeft, y: joinBottom + tabRadius),
            control: CGPoint(x: tabLeft, y: joinBottom)
        )
        path.addLine(to: CGPoint(x: tabLeft, y: joinTop - tabRadius))
        path.addQuadCurve(
            to: CGPoint(x: tabLeft + tabRadius, y: joinTop),
            control: CGPoint(x: tabLeft, y: joinTop)
        )
        path.addLine(to: CGPoint(x: webRect.minX, y: joinTop))
        path.addLine(to: CGPoint(x: webRect.minX, y: webRect.maxY - webRadius))
        path.addQuadCurve(
            to: CGPoint(x: webRect.minX + webRadius, y: webRect.maxY),
            control: CGPoint(x: webRect.minX, y: webRect.maxY)
        )
        path.closeSubpath()
        return path
    }

    private static var flowPalettes: [[CGColor]] {
        let blue = NSColor.systemBlue.cgColor
        let purple = NSColor.systemPurple.cgColor
        let pink = NSColor.systemPink.cgColor
        let orange = NSColor.systemOrange.cgColor

        return [
            [blue, purple, pink, orange, blue],
            [purple, pink, orange, blue, purple],
            [pink, orange, blue, purple, pink],
            [orange, blue, purple, pink, orange],
            [blue, purple, pink, orange, blue],
        ]
    }
}

/// Four-way movement cursor used only where FloatTabs itself will move the
/// window. This gives immediate feedback before the user starts dragging.
enum PanelMoveCursor {
    static let cursor: NSCursor = {
        let size = NSSize(width: 24, height: 24)
        let image = NSImage(size: size, flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let path = NSBezierPath()
            path.lineCapStyle = .round
            path.lineJoinStyle = .round

            path.move(to: NSPoint(x: center.x, y: 3))
            path.line(to: NSPoint(x: center.x, y: 21))
            path.move(to: NSPoint(x: 3, y: center.y))
            path.line(to: NSPoint(x: 21, y: center.y))

            path.move(to: NSPoint(x: 12, y: 21))
            path.line(to: NSPoint(x: 9, y: 18))
            path.move(to: NSPoint(x: 12, y: 21))
            path.line(to: NSPoint(x: 15, y: 18))

            path.move(to: NSPoint(x: 12, y: 3))
            path.line(to: NSPoint(x: 9, y: 6))
            path.move(to: NSPoint(x: 12, y: 3))
            path.line(to: NSPoint(x: 15, y: 6))

            path.move(to: NSPoint(x: 3, y: 12))
            path.line(to: NSPoint(x: 6, y: 9))
            path.move(to: NSPoint(x: 3, y: 12))
            path.line(to: NSPoint(x: 6, y: 15))

            path.move(to: NSPoint(x: 21, y: 12))
            path.line(to: NSPoint(x: 18, y: 9))
            path.move(to: NSPoint(x: 21, y: 12))
            path.line(to: NSPoint(x: 18, y: 15))

            path.lineWidth = 3.5
            NSColor.black.withAlphaComponent(0.72).setStroke()
            path.stroke()

            path.lineWidth = 1.5
            NSColor.white.setStroke()
            path.stroke()
            return true
        }

        return NSCursor(image: image, hotSpot: NSPoint(x: 12, y: 12))
    }()
}

/// Window movement is acquired mainly outside the Web viewport: the external
/// left zone and thin top/bottom gutters. Top/bottom borrow only a few WebKit
/// pixels for easier acquisition. The website right edge remains protected.
///
/// Movement is implemented directly from global pointer deltas instead of
/// NSWindow.performDrag(with:), which is unreliable for this borderless floating
/// NSPanel configuration on real hardware.
final class PanelPerimeterDragView: NSView {
    private var startingMouseLocation: NSPoint?
    private var startingWindowOrigin: NSPoint?

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // NSView hit-test points arrive in the superview's coordinates, while
        // dragRects are expressed in our local bounds. Convert explicitly so
        // cursor discovery and actual mouse acquisition use identical geometry.
        guard frame.contains(point) else { return nil }
        let localPoint = convert(point, from: superview)
        return Self.dragRects(in: bounds).contains(where: { $0.contains(localPoint) }) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        startingMouseLocation = NSEvent.mouseLocation
        startingWindowOrigin = window.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window,
              let startingMouseLocation,
              let startingWindowOrigin else {
            return
        }

        let origin = Self.destinationOrigin(
            startingWindowOrigin: startingWindowOrigin,
            startingMouseLocation: startingMouseLocation,
            currentMouseLocation: NSEvent.mouseLocation
        )
        window.setFrameOrigin(origin)
    }

    override func mouseUp(with event: NSEvent) {
        startingMouseLocation = nil
        startingWindowOrigin = nil
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for rect in Self.dragRects(in: bounds) {
            addCursorRect(rect, cursor: PanelMoveCursor.cursor)
        }
    }

    override func layout() {
        super.layout()
        window?.invalidateCursorRects(for: self)
    }

    static func destinationOrigin(
        startingWindowOrigin: NSPoint,
        startingMouseLocation: NSPoint,
        currentMouseLocation: NSPoint
    ) -> NSPoint {
        NSPoint(
            x: startingWindowOrigin.x + currentMouseLocation.x - startingMouseLocation.x,
            y: startingWindowOrigin.y + currentMouseLocation.y - startingMouseLocation.y
        )
    }

    static func dragRects(in bounds: NSRect) -> [NSRect] {
        guard bounds.width > 0, bounds.height > 0 else { return [] }

        let outer = min(
            max(PanelMetrics.outerInteractionGutter, 0),
            min(bounds.width / 2, bounds.height / 2)
        )
        let overlap = max(PanelMetrics.innerMovementOverlap, 0)
        let bandDepth = min(outer + overlap, bounds.height / 2)
        guard bandDepth > 0 else { return [] }

        let leftWidth = min(PanelMetrics.externalControlZoneWidth, bounds.width)
        let middleHeight = max(bounds.height - 2 * outer, 0)
        let topWidth = max(bounds.width - PanelMetrics.webRightInteractionSafety, 0)
        let bottomExclusion = max(
            outer + PanelMetrics.resizeHandleSize,
            PanelMetrics.webRightInteractionSafety
        )
        let bottomWidth = max(bounds.width - bottomExclusion, 0)

        return [
            NSRect(
                x: bounds.minX,
                y: bounds.minY + outer,
                width: leftWidth,
                height: middleHeight
            ),
            NSRect(
                x: bounds.minX,
                y: bounds.maxY - bandDepth,
                width: topWidth,
                height: bandDepth
            ),
            NSRect(
                x: bounds.minX,
                y: bounds.minY,
                width: bottomWidth,
                height: bandDepth
            ),
        ]
    }
}

/// The only resize affordance. Both its visible grip and complete hit target
/// live inside the bottom-right Web corner. This deliberately avoids relying on
/// transparent outside-window-looking pixels for a precision interaction.
final class PanelResizeHandleView: NSView {
    var onViewportSizeChange: ((NSSize) -> Void)?
    var onResizeEnded: (() -> Void)?

    private var startingMouseLocation: NSPoint?
    private var startingFrame: NSRect?
    private var trackingAreaReference: NSTrackingArea?
    private var resizeCursorIsPushed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

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
        pushResizeCursorIfNeeded()
    }

    override func mouseMoved(with event: NSEvent) {
        pushResizeCursorIfNeeded()
    }

    override func mouseExited(with event: NSEvent) {
        restoreResizeCursorIfNeeded()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        startingMouseLocation = NSEvent.mouseLocation
        startingFrame = window.frame
        onViewportSizeChange?(PanelMetrics.viewportSize(forPanelSize: window.frame.size))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window,
              let startingMouseLocation,
              let startingFrame else {
            return
        }

        let currentMouseLocation = NSEvent.mouseLocation
        let deltaX = currentMouseLocation.x - startingMouseLocation.x
        let deltaY = currentMouseLocation.y - startingMouseLocation.y

        var size = PanelMetrics.clampedPanelSize(
            NSSize(
                width: startingFrame.width + deltaX,
                height: startingFrame.height - deltaY
            )
        )

        if let visibleFrame = window.screen?.visibleFrame {
            let maximumWidth = max(
                PanelMetrics.minimumPanelSize.width,
                visibleFrame.maxX - startingFrame.minX
            )
            let maximumHeight = max(
                PanelMetrics.minimumPanelSize.height,
                startingFrame.maxY - visibleFrame.minY
            )
            size.width = min(size.width, maximumWidth)
            size.height = min(size.height, maximumHeight)
        }

        let resizedFrame = NSRect(
            x: startingFrame.minX,
            y: startingFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )

        window.setFrame(resizedFrame, display: true)
        onViewportSizeChange?(PanelMetrics.viewportSize(forPanelSize: size))
    }

    override func mouseUp(with event: NSEvent) {
        startingMouseLocation = nil
        startingFrame = nil
        onResizeEnded?()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    private func pushResizeCursorIfNeeded() {
        guard !resizeCursorIsPushed else { return }
        NSCursor.resizeLeftRight.push()
        resizeCursorIsPushed = true
    }

    private func restoreResizeCursorIfNeeded() {
        guard resizeCursorIsPushed else { return }
        NSCursor.pop()
        resizeCursorIsPushed = false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let color = NSColor.tertiaryLabelColor.withAlphaComponent(0.80)
        color.setStroke()

        let path = NSBezierPath()
        path.lineWidth = 1.25
        path.lineCapStyle = .round

        let inset = PanelMetrics.resizeHandleVisualInset
        for offset in [5.0, 9.0, 13.0] {
            path.move(to: NSPoint(
                x: bounds.maxX - inset - CGFloat(offset),
                y: bounds.minY + inset
            ))
            path.line(to: NSPoint(
                x: bounds.maxX - inset,
                y: bounds.minY + inset + CGFloat(offset)
            ))
        }
        path.stroke()
    }
}

final class ResizeReadoutView: NSView {
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.maximumNumberOfLines = 1
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
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

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func update(viewportSize: NSSize) {
        label.stringValue = Self.text(forViewportSize: viewportSize)
        invalidateIntrinsicContentSize()
    }

    static func text(forViewportSize size: NSSize) -> String {
        let ratio = size.height > 0 ? size.width / size.height : 0
        return String(
            format: "%.1f × %.1f px  ·  W/H %.1f",
            Double(size.width),
            Double(size.height),
            Double(ratio)
        )
    }

    override var intrinsicContentSize: NSSize {
        let labelSize = label.intrinsicContentSize
        return NSSize(width: labelSize.width + 20, height: labelSize.height + 12)
    }
}

/// The visible FloatTabs Web surface stays at the user-selected Window Size.
/// The logical host keeps that visible frame but uses a larger/smaller bounds
/// coordinate system. The child WKWebView itself receives the real 1280/390-
/// class frame, so WebKit sees the requested CSS viewport while ordinary AppKit
/// ancestor coordinate conversion maps pointer events into WebKit coordinates.
/// No NSScrollView magnification is involved.
final class WebSlotHostView: NSView {
    private(set) weak var webView: WKWebView?
    private(set) var websiteLayoutScale: CGFloat = 1
    private var isApplyingWebsiteLayout = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        translatesAutoresizingMaskIntoConstraints = true
        autoresizingMask = []
    }

    convenience init(webView: WKWebView) {
        self.init(frame: .zero)
        attach(webView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attach(_ webView: WKWebView) {
        if self.webView !== webView {
            self.webView?.removeFromSuperview()
            webView.removeFromSuperview()
            webView.translatesAutoresizingMaskIntoConstraints = true
            webView.autoresizingMask = []
            addSubview(webView)
            self.webView = webView
        }
        applyWebsiteLayoutIfNeeded()
    }

    override func layout() {
        super.layout()
        applyWebsiteLayoutIfNeeded()
    }

    private func applyWebsiteLayoutIfNeeded() {
        guard !isApplyingWebsiteLayout,
              let webView,
              frame.width > 0,
              frame.height > 0 else {
            return
        }

        let visibleSize = frame.size
        let mode = (webView as? FloatTabsWebView)?.websiteMode
            ?? (webView.configuration.defaultWebpagePreferences.preferredContentMode == .mobile
                ? .mobile
                : .desktop)
        let logicalSize = WebsiteLayoutViewport.logicalSize(
            forVisibleSize: visibleSize,
            websiteMode: mode
        )
        guard logicalSize.width > 0, logicalSize.height > 0 else { return }

        isApplyingWebsiteLayout = true
        websiteLayoutScale = visibleSize.width / logicalSize.width

        if abs(bounds.width - logicalSize.width) > 0.5
            || abs(bounds.height - logicalSize.height) > 0.5
            || bounds.origin != .zero {
            bounds = NSRect(origin: .zero, size: logicalSize)
        }

        if abs(webView.frame.width - logicalSize.width) > 0.5
            || abs(webView.frame.height - logicalSize.height) > 0.5
            || webView.frame.origin != .zero {
            webView.frame = NSRect(origin: .zero, size: logicalSize)
        }
        isApplyingWebsiteLayout = false
    }
}

/// Owns the visible FloatTabs web surface. Warm/Cold use the accepted Stage 4
/// transient host. Hot Slots instead receive one independent host each, so an
/// inactive Hot WebView can stay attached to the FloatTabs window without being
/// resized when another Slot has a different Window Size preset.
final class WebPanelContainerView: NSView {
    private let clipView = NSView()
    private let logicalHostView = NSView()
    private let emptyView = EmptyWebAppView()
    private weak var currentContentView: NSView?
    private weak var hostedWebView: WKWebView?
    private weak var activeWebView: WKWebView?
    private var activeSlotID: UUID?
    private var hotHostViews: [UUID: WebSlotHostView] = [:]

    private(set) var websiteLayoutScale: CGFloat = 1

    var currentWebView: WKWebView? {
        activeWebView
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureShell()
        showEmptyState()
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Compatibility seam used by existing Stage 4 tests and the Stage 0 helper.
    /// Product Slot switching should call the policy-aware overload below.
    func show(webView: WKWebView) {
        showTransient(webView: webView, slotID: nil)
    }

    func show(
        webView: WKWebView,
        slotID: UUID,
        residencyPolicy: SlotResidencyPolicy
    ) {
        switch residencyPolicy {
        case .hot:
            showHot(webView: webView, slotID: slotID)
        case .warm, .cold:
            showTransient(webView: webView, slotID: slotID)
        }
    }

    func deactivate(slotID: UUID, residencyPolicy: SlotResidencyPolicy) {
        guard activeSlotID == slotID else { return }

        switch residencyPolicy {
        case .hot:
            if let host = hotHostViews[slotID] {
                // Freeze the outgoing Hot viewport before another Slot changes
                // the panel size. Only an active Hot host follows live resizing.
                //
                // Keep the independent host and WKWebView attached so Hot keeps
                // its DOM/SPA/runtime state, but stop presenting an inactive Hot
                // page. Reactivation unhides this exact same host in `showHot`.
                host.autoresizingMask = []
                host.isHidden = true
            }
        case .warm, .cold:
            hostedWebView?.removeFromSuperview()
            hostedWebView = nil
        }

        activeSlotID = nil
        activeWebView = nil
    }

    func retainHotSlots(_ validHotSlotIDs: Set<UUID>) {
        let staleHotSlotIDs = hotHostViews.keys.filter { !validHotSlotIDs.contains($0) }
        for slotID in staleHotSlotIDs {
            guard let host = hotHostViews.removeValue(forKey: slotID) else { continue }
            host.webView?.removeFromSuperview()
            host.removeFromSuperview()
        }
    }

    func removeSlot(_ slotID: UUID) {
        if activeSlotID == slotID {
            hostedWebView?.removeFromSuperview()
            hostedWebView = nil
            activeWebView = nil
            activeSlotID = nil
        }
        if let host = hotHostViews.removeValue(forKey: slotID) {
            host.webView?.removeFromSuperview()
            host.removeFromSuperview()
        }
    }

    func showEmptyState() {
        guard currentContentView !== emptyView else { return }
        hostedWebView?.removeFromSuperview()
        hostedWebView = nil
        activeWebView = nil
        activeSlotID = nil
        websiteLayoutScale = 1
        logicalHostView.bounds = NSRect(origin: .zero, size: logicalHostView.frame.size)
        setContentView(emptyView)
        emptyView.isHidden = false
        bringToFront(emptyView)
    }

    override func layout() {
        super.layout()
        if let activeSlotID,
           hostedWebView == nil,
           let hotHost = hotHostViews[activeSlotID],
           !hotHost.isHidden {
            hotHost.frame = clipView.bounds
            hotHost.layoutSubtreeIfNeeded()
            websiteLayoutScale = hotHost.websiteLayoutScale
        } else if activeSlotID == nil || hostedWebView != nil {
            updateWebsiteLayoutIfNeeded()
        }
        layer?.shadowPath = CGPath(
            roundedRect: bounds,
            cornerWidth: PanelMetrics.webPanelCornerRadius,
            cornerHeight: PanelMetrics.webPanelCornerRadius,
            transform: nil
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSemanticColors()
        for host in hotHostViews.values {
            host.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }

    private func showHot(webView: WKWebView, slotID: UUID) {
        hostedWebView?.removeFromSuperview()
        hostedWebView = nil
        currentContentView?.isHidden = true

        let host: WebSlotHostView
        if let existing = hotHostViews[slotID] {
            host = existing
            host.attach(webView)
        } else {
            host = WebSlotHostView(webView: webView)
            hotHostViews[slotID] = host
            host.frame = clipView.bounds
            clipView.addSubview(host)
        }

        host.frame = clipView.bounds
        host.autoresizingMask = [.width, .height]
        host.isHidden = false
        host.layoutSubtreeIfNeeded()
        bringToFront(host)

        websiteLayoutScale = host.websiteLayoutScale
        activeSlotID = slotID
        activeWebView = webView
    }

    private func showTransient(webView: WKWebView, slotID: UUID?) {
        if hostedWebView !== webView {
            hostedWebView?.removeFromSuperview()
            webView.removeFromSuperview()
            webView.translatesAutoresizingMaskIntoConstraints = true
            webView.autoresizingMask = []
            logicalHostView.addSubview(webView)
            hostedWebView = webView
        }

        if currentContentView !== logicalHostView {
            setContentView(logicalHostView)
        }
        logicalHostView.isHidden = false
        bringToFront(logicalHostView)

        activeSlotID = slotID
        activeWebView = webView
        needsLayout = true
        layoutSubtreeIfNeeded()
        updateWebsiteLayoutIfNeeded()
    }

    private func configureShell() {
        wantsLayer = true
        layer?.cornerRadius = PanelMetrics.webPanelCornerRadius
        layer?.borderWidth = PanelMetrics.structuralBorderWidth
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.30
        layer?.shadowRadius = 18
        layer?.shadowOffset = CGSize(width: 0, height: -10)

        clipView.wantsLayer = true
        clipView.layer?.cornerRadius = PanelMetrics.webPanelCornerRadius
        clipView.layer?.masksToBounds = true
        clipView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(clipView)

        NSLayoutConstraint.activate([
            clipView.leadingAnchor.constraint(equalTo: leadingAnchor),
            clipView.trailingAnchor.constraint(equalTo: trailingAnchor),
            clipView.topAnchor.constraint(equalTo: topAnchor),
            clipView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        updateSemanticColors()
    }

    private func setContentView(_ view: NSView) {
        currentContentView?.removeFromSuperview()
        view.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        clipView.addSubview(view)

        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            view.topAnchor.constraint(equalTo: clipView.topAnchor),
            view.bottomAnchor.constraint(equalTo: clipView.bottomAnchor),
        ])

        currentContentView = view
    }

    private func bringToFront(_ view: NSView) {
        guard view.superview === clipView,
              let index = clipView.subviews.firstIndex(where: { $0 === view }) else {
            return
        }
        var ordered = clipView.subviews
        let selected = ordered.remove(at: index)
        ordered.append(selected)
        clipView.subviews = ordered
    }

    private func updateWebsiteLayoutIfNeeded() {
        guard let webView = hostedWebView else { return }

        let visibleSize = clipView.bounds.size
        guard visibleSize.width > 0, visibleSize.height > 0 else { return }

        let mode = (webView as? FloatTabsWebView)?.websiteMode
            ?? (webView.configuration.defaultWebpagePreferences.preferredContentMode == .mobile
                ? .mobile
                : .desktop)
        let logicalSize = WebsiteLayoutViewport.logicalSize(
            forVisibleSize: visibleSize,
            websiteMode: mode
        )
        guard logicalSize.width > 0, logicalSize.height > 0 else { return }

        websiteLayoutScale = visibleSize.width / logicalSize.width

        if abs(webView.frame.width - logicalSize.width) > 0.5
            || abs(webView.frame.height - logicalSize.height) > 0.5 {
            webView.frame = NSRect(origin: .zero, size: logicalSize)
        }

        if abs(logicalHostView.bounds.width - logicalSize.width) > 0.5
            || abs(logicalHostView.bounds.height - logicalSize.height) > 0.5
            || logicalHostView.bounds.origin != .zero {
            logicalHostView.bounds = NSRect(origin: .zero, size: logicalSize)
        }
    }

    private func updateSemanticColors() {
        let fallback = NSColor.windowBackgroundColor
        layer?.backgroundColor = fallback.cgColor
        clipView.layer?.backgroundColor = fallback.cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
    }
}
