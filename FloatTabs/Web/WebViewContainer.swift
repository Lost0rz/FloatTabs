import AppKit
import QuartzCore
import WebKit

/// AppKit owns the Stage 1 shell so hit testing and WebKit focus remain explicit.
final class PanelRootView: NSView {
    let externalControlZoneView: ExternalControlZoneView
    let webPanelContainerView: WebPanelContainerView
    let perimeterDragView: PanelPerimeterDragView

    init(webView: WKWebView) {
        externalControlZoneView = ExternalControlZoneView()
        webPanelContainerView = WebPanelContainerView(webView: webView)
        perimeterDragView = PanelPerimeterDragView()

        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        externalControlZoneView.translatesAutoresizingMaskIntoConstraints = false
        webPanelContainerView.translatesAutoresizingMaskIntoConstraints = false
        perimeterDragView.translatesAutoresizingMaskIntoConstraints = false

        // Ordering matters. The perimeter drag overlay sits above WebKit so the
        // four edge bands are predictable even when the website fills the
        // visible rectangle. The external control zone sits above that overlay
        // so future tabs/gear/FT controls retain interaction priority; blank
        // control-zone space still returns nil and can fall through normally.
        addSubview(webPanelContainerView)
        addSubview(perimeterDragView)
        addSubview(externalControlZoneView)

        NSLayoutConstraint.activate([
            externalControlZoneView.leadingAnchor.constraint(equalTo: leadingAnchor),
            externalControlZoneView.topAnchor.constraint(equalTo: topAnchor),
            externalControlZoneView.bottomAnchor.constraint(equalTo: bottomAnchor),
            externalControlZoneView.widthAnchor.constraint(
                equalToConstant: PanelMetrics.externalControlZoneWidth
            ),

            webPanelContainerView.leadingAnchor.constraint(
                equalTo: externalControlZoneView.trailingAnchor
            ),
            webPanelContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webPanelContainerView.topAnchor.constraint(equalTo: topAnchor),
            webPanelContainerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            perimeterDragView.leadingAnchor.constraint(equalTo: leadingAnchor),
            perimeterDragView.trailingAnchor.constraint(equalTo: trailingAnchor),
            perimeterDragView.topAnchor.constraint(equalTo: topAnchor),
            perimeterDragView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let candidate = super.hitTest(point)
        return candidate === self ? nil : candidate
    }
}

/// The zone is visually transparent. Blank area intentionally returns nil from
/// AppKit view hit testing. Future tabs and system controls can be added as
/// subviews; because this view is layered above the perimeter drag overlay,
/// those explicit controls will take precedence wherever they are visible.
final class ExternalControlZoneView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let candidate = super.hitTest(point)
        return candidate === self ? nil : candidate
    }
}

/// A predictable four-sided movement affordance. The outermost resize inset is
/// deliberately left untouched for AppKit's native resize handling, and the
/// corners are excluded so diagonal resize acquisition remains reliable.
///
/// The overlay is otherwise hit-test transparent: website interaction and the
/// future external-control blank zone are unaffected away from the narrow edge
/// bands. Movement uses Apple's public NSWindow.performDrag(with:) API.
final class PanelPerimeterDragView: NSView {
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
        guard bounds.contains(point) else { return nil }
        return Self.dragRects(in: bounds).contains(where: { $0.contains(point) }) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for rect in Self.dragRects(in: bounds) {
            addCursorRect(rect, cursor: .openHand)
        }
    }

    static func dragRects(in bounds: NSRect) -> [NSRect] {
        guard bounds.width > 0, bounds.height > 0 else { return [] }

        let resizeInset = max(PanelMetrics.perimeterDragResizeInset, 0)
        let requestedBand = max(PanelMetrics.perimeterDragBandWidth, 0)
        let cornerExclusion = max(PanelMetrics.perimeterDragCornerExclusion, 0)
        let insetBounds = bounds.insetBy(dx: resizeInset, dy: resizeInset)

        guard insetBounds.width > 0, insetBounds.height > 0 else { return [] }

        let horizontalBandHeight = min(requestedBand, insetBounds.height)
        let verticalBandWidth = min(requestedBand, insetBounds.width)
        let horizontalLength = max(insetBounds.width - 2 * cornerExclusion, 0)
        let verticalLength = max(insetBounds.height - 2 * cornerExclusion, 0)

        var rects: [NSRect] = []

        if horizontalLength > 0, horizontalBandHeight > 0 {
            rects.append(
                NSRect(
                    x: insetBounds.minX + cornerExclusion,
                    y: insetBounds.minY,
                    width: horizontalLength,
                    height: horizontalBandHeight
                )
            )
            rects.append(
                NSRect(
                    x: insetBounds.minX + cornerExclusion,
                    y: insetBounds.maxY - horizontalBandHeight,
                    width: horizontalLength,
                    height: horizontalBandHeight
                )
            )
        }

        if verticalLength > 0, verticalBandWidth > 0 {
            rects.append(
                NSRect(
                    x: insetBounds.minX,
                    y: insetBounds.minY + cornerExclusion,
                    width: verticalBandWidth,
                    height: verticalLength
                )
            )
            rects.append(
                NSRect(
                    x: insetBounds.maxX - verticalBandWidth,
                    y: insetBounds.minY + cornerExclusion,
                    width: verticalBandWidth,
                    height: verticalLength
                )
            )
        }

        return rects
    }
}

/// Visible website rectangle: zero padding, 14 pt radius, 1 pt semantic border,
/// and a restrained shell shadow. WKWebView itself remains opaque/normal.
final class WebPanelContainerView: NSView {
    private let clipView = NSView()
    private let webView: WKWebView

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)

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

        webView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(clipView)
        clipView.addSubview(webView)

        NSLayoutConstraint.activate([
            clipView.leadingAnchor.constraint(equalTo: leadingAnchor),
            clipView.trailingAnchor.constraint(equalTo: trailingAnchor),
            clipView.topAnchor.constraint(equalTo: topAnchor),
            clipView.bottomAnchor.constraint(equalTo: bottomAnchor),

            webView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            webView.topAnchor.constraint(equalTo: clipView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: clipView.bottomAnchor),
        ])

        updateSemanticColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
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
    }

    private func updateSemanticColors() {
        let fallback = NSColor.windowBackgroundColor
        layer?.backgroundColor = fallback.cgColor
        clipView.layer?.backgroundColor = fallback.cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
    }
}
