from pathlib import Path
import re


def read(path):
    return Path(path).read_text()


def write(path, text):
    Path(path).write_text(text)


def replace_once(path, old, new):
    text = read(path)
    if old not in text:
        raise SystemExit(f"anchor not found: {path}: {old[:100]!r}")
    write(path, text.replace(old, new, 1))


def replace_function(text, name, next_name, replacement):
    start = text.index(f"    func {name}() {{")
    end = text.index(f"    func {next_name}() {{", start)
    return text[:start] + replacement.rstrip() + "\n\n" + text[end:]


# -----------------------------------------------------------------------------
# Resize acquisition
# -----------------------------------------------------------------------------
replace_once(
    "FloatTabs/Panel/ScreenPositioning.swift",
    "static let resizeHandleSize: CGFloat = 18",
    "static let resizeHandleSize: CGFloat = 32",
)

replace_once(
    "FloatTabs/Web/WebViewContainer.swift",
    """    private var startingMouseLocation: NSPoint?\n    private var startingFrame: NSRect?\n""",
    """    private var startingMouseLocation: NSPoint?\n    private var startingFrame: NSRect?\n    private var trackingAreaReference: NSTrackingArea?\n    private var resizeCursorIsPushed = false\n""",
)
replace_once(
    "FloatTabs/Web/WebViewContainer.swift",
    """    override func hitTest(_ point: NSPoint) -> NSView? {\n        frame.contains(point) ? self : nil\n    }\n\n    override func mouseDown(with event: NSEvent) {\n""",
    """    override func hitTest(_ point: NSPoint) -> NSView? {\n        bounds.contains(point) ? self : nil\n    }\n\n    override func updateTrackingAreas() {\n        super.updateTrackingAreas()\n        if let trackingAreaReference {\n            removeTrackingArea(trackingAreaReference)\n        }\n        let tracking = NSTrackingArea(\n            rect: bounds,\n            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],\n            owner: self,\n            userInfo: nil\n        )\n        addTrackingArea(tracking)\n        trackingAreaReference = tracking\n    }\n\n    override func mouseEntered(with event: NSEvent) {\n        pushResizeCursorIfNeeded()\n    }\n\n    override func mouseMoved(with event: NSEvent) {\n        pushResizeCursorIfNeeded()\n    }\n\n    override func mouseExited(with event: NSEvent) {\n        restoreResizeCursorIfNeeded()\n    }\n\n    override func mouseDown(with event: NSEvent) {\n""",
)
replace_once(
    "FloatTabs/Web/WebViewContainer.swift",
    """    override func resetCursorRects() {\n        super.resetCursorRects()\n        addCursorRect(bounds, cursor: .resizeLeftRight)\n    }\n\n    override func draw(_ dirtyRect: NSRect) {\n""",
    """    override func resetCursorRects() {\n        super.resetCursorRects()\n        addCursorRect(bounds, cursor: .resizeLeftRight)\n    }\n\n    private func pushResizeCursorIfNeeded() {\n        guard !resizeCursorIsPushed else { return }\n        NSCursor.resizeLeftRight.push()\n        resizeCursorIsPushed = true\n    }\n\n    private func restoreResizeCursorIfNeeded() {\n        guard resizeCursorIsPushed else { return }\n        NSCursor.pop()\n        resizeCursorIsPushed = false\n    }\n\n    override func draw(_ dirtyRect: NSRect) {\n""",
)

# -----------------------------------------------------------------------------
# Rendering: Website Mode chooses WebKit content mode / identity; Window Size is
# the real viewport; user Zoom alone owns WKWebView.pageZoom.
# -----------------------------------------------------------------------------
web = read("FloatTabs/Web/WebViewFactory.swift")
start = web.index("enum WebsiteLayoutViewport {")
end = web.index("\n\n@MainActor\nenum WebViewFactory", start)
web = web[:start] + '''enum WebsiteLayoutViewport {
    static func targetCSSWidth(
        forVisibleWidth visibleWidth: CGFloat,
        websiteMode: WebsiteMode
    ) -> CGFloat {
        visibleWidth
    }

    static func fittingScale(
        forVisibleWidth visibleWidth: CGFloat,
        websiteMode: WebsiteMode
    ) -> CGFloat {
        1
    }

    static func logicalSize(
        forVisibleSize visibleSize: CGSize,
        websiteMode: WebsiteMode
    ) -> CGSize {
        visibleSize
    }
}''' + web[end:]
web = web.replace(
'''/// Keeps WKWebView at the real visible AppKit size. Website Mode is translated
/// into a public WebKit pageZoom fitting factor so CSS layout can be 1280/390-
/// class without any parent-view scaling. `userPageZoom` remains an independent
/// product value and is composed with the internal fitting factor only at the
/// final WebKit presentation boundary.''',
'''/// Keeps WKWebView at the real visible AppKit/CSS size. Website Mode changes
/// WebKit content mode / browser identity; user Zoom is the only pageZoom input.
/// No synthetic 1280/390 viewport and no AppKit/WebKit magnification are used.''')
old_refresh = '''    private func refreshWebsiteLayoutScale() {
        websiteLayoutScale = WebsiteLayoutViewport.fittingScale(
            forVisibleWidth: frame.width,
            websiteMode: websiteMode
        )
        let effectivePageZoom = websiteLayoutScale * userPageZoom
        if abs(pageZoom - effectivePageZoom) > 0.0001 {
            pageZoom = effectivePageZoom
        }
    }'''
new_refresh = '''    private func refreshWebsiteLayoutScale() {
        websiteLayoutScale = 1
        if abs(pageZoom - userPageZoom) > 0.0001 {
            pageZoom = userPageZoom
        }
    }'''
if old_refresh not in web:
    raise SystemExit("WebViewFactory refresh anchor missing")
web = web.replace(old_refresh, new_refresh, 1)
write("FloatTabs/Web/WebViewFactory.swift", web)

# -----------------------------------------------------------------------------
# External tab rail: callbacks, favicon tab presentation, fast context controls.
# -----------------------------------------------------------------------------
rail_path = "FloatTabs/UI/ExternalTabRail.swift"
rail = read(rail_path)
rail = rail.replace("    static let inactiveWidth: CGFloat = 44\n    static let hoverWidth: CGFloat = 66\n    static let activeWidth: CGFloat = 68\n    static let activeHoverWidth: CGFloat = 74\n",
'''    static let collapsedWidth: CGFloat = 40
    static let hoverWidth: CGFloat = 76
    static let activeWidth: CGFloat = 40
    static let activeHoverWidth: CGFloat = 76
''', 1)
rail = rail.replace(
'''        let resting = isActive ? activeWidth : inactiveWidth
        let magnified = isActive ? activeHoverWidth : hoverWidth
        return resting + (magnified - resting) * influence''',
'''        let resting = isActive ? activeWidth : collapsedWidth
        let magnified = isActive ? activeHoverWidth : hoverWidth
        return resting + (magnified - resting) * influence''', 1)
rail = rail.replace(
'''    var onSetResidency: ((UUID, SlotResidencyPolicy) -> Void)?
    var onSetBackgroundMedia: ((UUID, BackgroundMediaPolicy) -> Void)?''',
'''    var onSetWebsiteMode: ((UUID, WebsiteMode) -> Void)?
    var onSetWindowSize: ((UUID, SimpleViewportPreset) -> Void)?
    var onSetZoom: ((UUID, CGFloat) -> Void)?
    var onSetResidency: ((UUID, SlotResidencyPolicy) -> Void)?
    var onSetBackgroundMedia: ((UUID, BackgroundMediaPolicy) -> Void)?''', 1)
rail = rail.replace(
'''        view.onSetResidency = { [weak self] slotID, policy in
            self?.onSetResidency?(slotID, policy)
        }''',
'''        view.onSetWebsiteMode = { [weak self] slotID, mode in
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
        }''', 1)

class_start = rail.index("@MainActor\nfinal class ExternalWebAppTabView")
class_end = rail.index("\n@MainActor\nfinal class AddWebAppControl", class_start)
new_tab = r'''@MainActor
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
        bounds.contains(point) ? self : nil
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
'''
rail = rail[:class_start] + new_tab + rail[class_end:]
write(rail_path, rail)

# -----------------------------------------------------------------------------
# PanelController wires fast context controls through TabStore.
# -----------------------------------------------------------------------------
panel_path = "FloatTabs/Panel/PanelController.swift"
panel = read(panel_path)
anchor = '''        rail.onRemove = { [weak self] id in
            self?.presentRemoveConfirmation(id: id)
        }
        rail.onSetResidency = { [weak self] id, policy in'''
insert = '''        rail.onRemove = { [weak self] id in
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
        rail.onSetResidency = { [weak self] id, policy in'''
if anchor not in panel:
    raise SystemExit("Panel callback anchor missing")
panel = panel.replace(anchor, insert, 1)
write(panel_path, panel)

# -----------------------------------------------------------------------------
# Edit Web App keeps Name/URL + advanced identity; Add keeps full rendering form.
# -----------------------------------------------------------------------------
editor_path = "FloatTabs/UI/WebAppEditorController.swift"
editor = read(editor_path)
editor = editor.replace(
'''            initialRendering: .canonicalDefault,
            attachedTo: window,''',
'''            initialRendering: .canonicalDefault,
            showsPrimaryRenderingControls: true,
            attachedTo: window,''', 1)
editor = editor.replace(
'''            initialRendering: profile.renderingProfile,
            attachedTo: window,''',
'''            initialRendering: profile.renderingProfile,
            showsPrimaryRenderingControls: false,
            attachedTo: window,''', 1)
editor = editor.replace(
'''        initialRendering: WebRenderingProfile,
        attachedTo window: NSWindow,''',
'''        initialRendering: WebRenderingProfile,
        showsPrimaryRenderingControls: Bool,
        attachedTo window: NSWindow,''', 1)
editor = editor.replace(
'''        let renderingForm = RenderingForm(initial: initialRendering)''',
'''        let renderingForm = RenderingForm(
            initial: initialRendering,
            showsPrimaryRenderingControls: showsPrimaryRenderingControls
        )''', 1)
editor = editor.replace(
'''    init(initial: WebRenderingProfile) {
        let rendering = initial.normalized()''',
'''    init(
        initial: WebRenderingProfile,
        showsPrimaryRenderingControls: Bool = true
    ) {
        let rendering = initial.normalized()''', 1)
old_stack = '''        view = NSStackView(views: [
            Self.label("Website Mode"),
            modePopup,
            Self.label("Window Size"),
            sizeRow,
            Self.label("Zoom"),
            zoomPopup,
            advancedButton,
        ])'''
new_stack = '''        let primaryViews: [NSView] = showsPrimaryRenderingControls
            ? [
                Self.label("Website Mode"),
                modePopup,
                Self.label("Window Size"),
                sizeRow,
                Self.label("Zoom"),
                zoomPopup,
                advancedButton,
            ]
            : [
                Self.label("Browser Identity / Compatibility"),
                advancedButton,
            ]
        view = NSStackView(views: primaryViews)'''
if old_stack not in editor:
    raise SystemExit("RenderingForm stack anchor missing")
editor = editor.replace(old_stack, new_stack, 1)
write(editor_path, editor)

# -----------------------------------------------------------------------------
# Tests
# -----------------------------------------------------------------------------
shell_path = "FloatTabsTests/ExternalShellTests.swift"
shell = read(shell_path)
shell = shell.replace(
'''            ["Return to Home", "Residency", "Background Media", "Edit Web App…", "Remove Web App…"]''',
'''            ["Return to Home", "Website Mode", "Window Size", "Zoom", "Residency", "Background Media", "Edit Web App…", "Remove Web App…"]''', 1)
shell = shell.replace(
'''        XCTAssertEqual(menu.item(withTitle: "Residency")?.submenu?.items.map(\.title), ["Hot", "Warm", "Cold"])''',
'''        XCTAssertEqual(menu.item(withTitle: "Website Mode")?.submenu?.items.map(\.title), ["Desktop", "Mobile"])
        XCTAssertEqual(
            menu.item(withTitle: "Window Size")?.submenu?.items.filter { !$0.isSeparatorItem }.map(\.title),
            ["Small  390 × 780", "Medium  430 × 820", "Large  600 × 800", "Wide  900 × 850"]
        )
        XCTAssertEqual(menu.item(withTitle: "Residency")?.submenu?.items.map(\.title), ["Hot", "Warm", "Cold"])''', 1)
shell = shell.replace(
'''        XCTAssertEqual(activeView.frame.width, ExternalTabMetrics.activeWidth, accuracy: 0.001)
        XCTAssertEqual(inactiveView.frame.width, ExternalTabMetrics.inactiveWidth, accuracy: 0.001)''',
'''        XCTAssertEqual(activeView.frame.width, ExternalTabMetrics.activeWidth, accuracy: 0.001)
        XCTAssertEqual(inactiveView.frame.width, ExternalTabMetrics.collapsedWidth, accuracy: 0.001)
        XCTAssertFalse(activeView.isShowingLabel)
        XCTAssertFalse(inactiveView.isShowingLabel)''', 1)
shell = shell.replace(
'''    func testMoveHoverTrackingRemainsActiveWhenAppIsInactive() {''',
'''    func testResizeHandleUsesExpandedFirstMouseHitTarget() {
        XCTAssertGreaterThanOrEqual(PanelMetrics.resizeHandleSize, 30)
        let handle = PanelResizeHandleView(frame: NSRect(x: 100, y: 100, width: 32, height: 32))
        XCTAssertTrue(handle.acceptsFirstMouse(for: nil))
        XCTAssertTrue(handle.hitTest(NSPoint(x: 2, y: 2)) === handle)
        XCTAssertNil(handle.hitTest(NSPoint(x: 40, y: 40)))
    }

    func testFaviconURLUsesWebsiteOriginWithoutThirdPartyService() {
        let input = URL(string: "https://example.com/a/b?q=1")!
        XCTAssertEqual(
            WebsiteFaviconProvider.faviconURL(for: input)?.absoluteString,
            "https://example.com/favicon.ico"
        )
    }

    func testMoveHoverTrackingRemainsActiveWhenAppIsInactive() {''', 1)
write(shell_path, shell)

wv_path = "FloatTabsTests/WebViewFactoryTests.swift"
t = read(wv_path)
t = replace_function(t, "testWebsiteLayoutViewportSeparatesTargetCSSWidthFromVisibleWindowSize", "testDesktopHostKeepsWebViewOneToOneWithVisibleSurface", '''    func testWebsiteLayoutViewportUsesRealVisibleWidthForBothModes() {
        XCTAssertEqual(WebsiteLayoutViewport.targetCSSWidth(forVisibleWidth: 430, websiteMode: .desktop), 430, accuracy: 0.001)
        XCTAssertEqual(WebsiteLayoutViewport.fittingScale(forVisibleWidth: 430, websiteMode: .desktop), 1, accuracy: 0.001)
        XCTAssertEqual(WebsiteLayoutViewport.targetCSSWidth(forVisibleWidth: 900, websiteMode: .mobile), 900, accuracy: 0.001)
        XCTAssertEqual(WebsiteLayoutViewport.fittingScale(forVisibleWidth: 900, websiteMode: .mobile), 1, accuracy: 0.001)
        let physical = CGSize(width: 430, height: 820)
        XCTAssertEqual(WebsiteLayoutViewport.logicalSize(forVisibleSize: physical, websiteMode: .desktop), physical)
    }''')
t = replace_function(t, "testDesktopHostKeepsWebViewOneToOneWithVisibleSurface", "testVisibleResizeRecomputesPublicWebKitFitWithoutChangingPhysicalGeometry", '''    func testDesktopHostKeepsWebViewOneToOneWithVisibleSurface() {
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = host(webView, visibleSize: NSSize(width: 430, height: 820))
        let floatTabsWebView = tryUnwrapFloatTabsWebView(webView)
        XCTAssertEqual(container.bounds.size, NSSize(width: 430, height: 820))
        XCTAssertEqual(webView.frame.size, NSSize(width: 430, height: 820))
        XCTAssertEqual(webView.bounds.size, webView.frame.size)
        XCTAssertEqual(container.websiteLayoutScale, 1, accuracy: 0.001)
        XCTAssertEqual(floatTabsWebView.websiteLayoutScale, 1, accuracy: 0.001)
        XCTAssertEqual(webView.pageZoom, 1, accuracy: 0.001)
        XCTAssertEqual(webView.magnification, 1, accuracy: 0.001)
    }''')
t = replace_function(t, "testVisibleResizeRecomputesPublicWebKitFitWithoutChangingPhysicalGeometry", "testDesktopModeChangesActualCSSLayoutWidthWhileVisibleSurfaceStaysNarrow", '''    func testVisibleResizeKeepsNativeOneToOneGeometry() {
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = host(webView, visibleSize: NSSize(width: 430, height: 820))
        let floatTabsWebView = tryUnwrapFloatTabsWebView(webView)
        container.setFrameSize(NSSize(width: 900, height: 850))
        container.layoutSubtreeIfNeeded()
        webView.layoutSubtreeIfNeeded()
        XCTAssertEqual(container.bounds.size, NSSize(width: 900, height: 850))
        XCTAssertEqual(webView.frame.size, NSSize(width: 900, height: 850))
        XCTAssertEqual(floatTabsWebView.websiteLayoutScale, 1, accuracy: 0.001)
        XCTAssertEqual(webView.pageZoom, 1, accuracy: 0.001)
    }''')
t = replace_function(t, "testDesktopModeChangesActualCSSLayoutWidthWhileVisibleSurfaceStaysNarrow", "testMobileModeChangesActualCSSLayoutWidthWhileVisibleSurfaceStaysWide", '''    func testDesktopModeDoesNotSynthesizeHiddenCSSWidth() {
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = host(webView, visibleSize: NSSize(width: 430, height: 820))
        loadTestHTML(in: webView)
        let cssWidth = evaluateNumber("document.body.clientWidth", in: webView)
        XCTAssertEqual(container.bounds.width, 430, accuracy: 0.001)
        XCTAssertEqual(webView.frame.width, 430, accuracy: 0.001)
        XCTAssertEqual(cssWidth, 430, accuracy: 3)
    }''')
t = replace_function(t, "testMobileModeChangesActualCSSLayoutWidthWhileVisibleSurfaceStaysWide", "testNativeWebCoordinatesRemainOneToOneWithVisibleCoordinates", '''    func testMobileModeDoesNotSynthesizeHiddenCSSWidth() {
        let rendering = WebRenderingProfile.canonicalDefault.settingWebsiteMode(.mobile).settingSimplePreset(.wide)
        let webView = WebViewFactory.makeWebView(renderingProfile: rendering)
        let container = host(webView, visibleSize: NSSize(width: 900, height: 850))
        let floatTabsWebView = tryUnwrapFloatTabsWebView(webView)
        loadTestHTML(in: webView)
        let cssWidth = evaluateNumber("document.body.clientWidth", in: webView)
        XCTAssertEqual(container.bounds.width, 900, accuracy: 0.001)
        XCTAssertEqual(webView.frame.width, 900, accuracy: 0.001)
        XCTAssertEqual(floatTabsWebView.websiteLayoutScale, 1, accuracy: 0.001)
        XCTAssertEqual(cssWidth, 900, accuracy: 3)
    }''')
t = replace_function(t, "testWebsiteFitComposesWithIndependentUserZoomState", "testNavigationObserverRestoresWebsiteModeWithoutDiscardingUserZoom", '''    func testUserZoomIsOnlyPageZoomInputAcrossWebsiteModes() {
        let desktopRendering = WebRenderingProfile.canonicalDefault.settingZoom(1.25)
        let desktopWebView = WebViewFactory.makeWebView(renderingProfile: desktopRendering)
        _ = host(desktopWebView, visibleSize: NSSize(width: 430, height: 820))
        let desktopFloatWebView = tryUnwrapFloatTabsWebView(desktopWebView)
        XCTAssertEqual(desktopFloatWebView.userPageZoom, 1.25, accuracy: 0.001)
        XCTAssertEqual(desktopFloatWebView.websiteLayoutScale, 1, accuracy: 0.001)
        XCTAssertEqual(desktopWebView.pageZoom, 1.25, accuracy: 0.001)
        XCTAssertEqual(desktopWebView.magnification, 1, accuracy: 0.001)

        let mobileRendering = desktopRendering.settingWebsiteMode(.mobile).settingSimplePreset(.wide)
        let mobileWebView = WebViewFactory.makeWebView(renderingProfile: mobileRendering)
        _ = host(mobileWebView, visibleSize: NSSize(width: 900, height: 850))
        let mobileFloatWebView = tryUnwrapFloatTabsWebView(mobileWebView)
        XCTAssertEqual(mobileFloatWebView.userPageZoom, 1.25, accuracy: 0.001)
        XCTAssertEqual(mobileFloatWebView.websiteLayoutScale, 1, accuracy: 0.001)
        XCTAssertEqual(mobileWebView.pageZoom, 1.25, accuracy: 0.001)
        XCTAssertEqual(mobileWebView.magnification, 1, accuracy: 0.001)
    }''')
t = t.replace("XCTAssertEqual(floatTabsWebView.websiteLayoutScale, 900.0 / 390.0, accuracy: 0.001)", "XCTAssertEqual(floatTabsWebView.websiteLayoutScale, 1, accuracy: 0.001)", 1)
write(wv_path, t)

# -----------------------------------------------------------------------------
# Product contract
# -----------------------------------------------------------------------------
doc = '''# FloatTabs Stage 5D — Interaction & Rendering Refinement

Status: implementation candidate pending Real-Mac acceptance and final benchmark.

## Resize
- Bottom-right visual grip remains small, but the acquisition view is 32 × 32 pt.
- The resize view accepts first mouse, uses local `bounds` hit testing, and an `activeAlways` tracking area so an inactive FloatTabs panel can be resized on the first drag.

## Rendering contract
- Website Mode selects WebKit Desktop/Mobile content mode and browser identity.
- Window Size is the real WKWebView/CSS viewport.
- Zoom is the only input to `WKWebView.pageZoom`.
- FloatTabs does not synthesize hidden 1280/390 CSS widths, does not use `WKWebView.magnification`, and does not inject site-specific layout CSS/JavaScript.

## Tab rail
- Resting active and inactive tabs are favicon-only.
- Hover expands the tab and reveals its name.
- Active presentation uses the app accent seam and an attached open-right-edge silhouette; inactive tabs use a quieter sticky-note silhouette.
- Favicons are fetched generically from the Web App origin `/favicon.ico`, cached in memory, and fall back to a system globe. No third-party favicon service or site-specific mapping is used.
- The active accent is centralized at `ExternalTabVisualPalette.activeAccent` so a future Settings → Appearance screen can replace it without changing tab behavior.

## Tab context menu
Common controls are available directly from the Web App tab and persist through `TabStore`:
- Website Mode
- Window Size
- Zoom
- Residency
- Background Media

`Edit Web App…` is reduced to Name, URL, and advanced Browser Identity / compatibility. Add Web App retains the complete initial rendering form.

## Deferred
Global Settings is a later independent screen (Appearance / Hotkeys / Global / About). Stage 5D does not build it.

## Real-Mac acceptance before benchmark
1. Resize an inactive FloatTabs panel from another app/full-screen space on the first drag; verify no dead corner areas.
2. Verify favicon-only resting tabs, hover name reveal, active attached accent, inactive sticky-note presentation, context menu, drag reorder, +, gear and Pin.
3. Verify right-click Website Mode / Window Size / Zoom apply immediately and survive restart; Edit remains low-frequency; Add remains complete.
4. Verify Google Desktop 100%, Bilibili Mobile, and ChatGPT Desktop/Mobile no longer show synthetic-scale typography/cropping; verify native clicking at 50/100/150/200% zoom.
5. Re-run Stage 5C summon/Pin/Hot-state and background-audio regressions.
6. Only after acceptance run the automated Stage 5B benchmark against the previous baseline.
'''
Path("docs/product/FloatTabs_Stage_5D_Interaction_Rendering_Refinement.md").write_text(doc)

print("Stage 5D final patch prepared")
