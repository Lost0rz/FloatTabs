import AppKit
import QuartzCore
import WebKit

/// AppKit owns the Stage 1 shell so hit testing and WebKit focus remain explicit.
final class PanelRootView: NSView {
    let externalControlZoneView: ExternalControlZoneView
    let webPanelContainerView: WebPanelContainerView

    init(webView: WKWebView) {
        externalControlZoneView = ExternalControlZoneView()
        webPanelContainerView = WebPanelContainerView(webView: webView)

        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        externalControlZoneView.translatesAutoresizingMaskIntoConstraints = false
        webPanelContainerView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(externalControlZoneView)
        addSubview(webPanelContainerView)

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

/// The zone is visually transparent. Most blank area intentionally returns nil
/// from AppKit view hit testing so it remains click-through in the real-Mac
/// behavior already observed. Only explicit control subviews should intercept
/// events. Stage 1 reserves one small top drag region; future tabs and system
/// controls can be added as additional subviews without turning the full 76 pt
/// zone into an invisible sidebar.
final class ExternalControlZoneView: NSView {
    let dragRegionView = PanelDragRegionView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        dragRegionView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dragRegionView)

        NSLayoutConstraint.activate([
            dragRegionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dragRegionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            dragRegionView.topAnchor.constraint(equalTo: topAnchor),
            dragRegionView.heightAnchor.constraint(
                equalToConstant: PanelMetrics.externalControlZoneDragRegionHeight
            ),
        ])
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

/// A deliberately small drag target outside the WKWebView. Using
/// NSWindow.performDrag(with:) delegates the actual move to WindowServer and
/// avoids making the whole transparent control zone consume mouse events.
final class PanelDragRegionView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        toolTip = "Drag FloatTabs"
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

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .openHand)
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
