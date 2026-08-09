from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f"anchor not found in {path}: {old[:120]!r}")
    p.write_text(text.replace(old, new, 1))


# -----------------------------------------------------------------------------
# Resize acquisition: enlarge the hit target and fix local-coordinate hit test.
# -----------------------------------------------------------------------------
replace_once(
    "FloatTabs/Panel/ScreenPositioning.swift",
    """    /// Bottom-right remains the only resize affordance.\n    static let resizeHandleSize: CGFloat = 18\n""",
    """    /// Bottom-right remains the only resize affordance. The visible grip\n    /// occupies only the inner corner; the view itself is deliberately larger\n    /// so the affordance is easy to acquire from an inactive application.\n    static let resizeHandleSize: CGFloat = 32\n""",
)

replace_once(
    "FloatTabs/Web/WebViewContainer.swift",
    """    private var startingMouseLocation: NSPoint?\n    private var startingFrame: NSRect?\n\n    override init(frame frameRect: NSRect) {\n""",
    """    private var startingMouseLocation: NSPoint?\n    private var startingFrame: NSRect?\n    private var trackingAreaReference: NSTrackingArea?\n    private var resizeCursorIsPushed = false\n\n    override init(frame frameRect: NSRect) {\n""",
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

# Correct the same coordinate-space mistake on the shell controls while here.
rail_path = Path("FloatTabs/UI/ExternalTabRail.swift")
rail_text = rail_path.read_text()
rail_text = rail_text.replace("frame.contains(point) ? self : nil", "bounds.contains(point) ? self : nil")
rail_path.write_text(rail_text)

# -----------------------------------------------------------------------------
# Rendering boundary: pageZoom owns only layout fitting; magnification owns the
# user's explicit zoom. Bound layout fitting to browser-like presentation ranges
# so narrow Desktop and wide Mobile do not drive CSS zoom to 0.33x / 2.3x.
# -----------------------------------------------------------------------------
replace_once(
    "FloatTabs/Web/WebViewFactory.swift",
    """enum WebsiteLayoutViewport {\n    static let desktopMinimumCSSWidth: CGFloat = 1280\n    static let mobileMaximumCSSWidth: CGFloat = 390\n""",
    """enum WebsiteLayoutViewport {\n    static let desktopMinimumCSSWidth: CGFloat = 1280\n    static let mobileMaximumCSSWidth: CGFloat = 390\n\n    /// `pageZoom` is a CSS/layout zoom boundary, not a neutral compositor scale.\n    /// Keep the automatic Website Mode fit inside a legible range. Desktop still\n    /// requests desktop content mode/identity and is allowed to shrink, while\n    /// Mobile is never automatically enlarged above 1:1 in a wide FloatTabs\n    /// window. User Zoom is applied separately with WKWebView.magnification.\n    static let minimumAutomaticFitScale: CGFloat = 0.50\n    static let maximumAutomaticFitScale: CGFloat = 1.00\n""",
)
replace_once(
    "FloatTabs/Web/WebViewFactory.swift",
    """        guard targetWidth > 0 else { return 1 }\n        return visibleWidth / targetWidth\n    }\n""",
    """        guard targetWidth > 0 else { return 1 }\n        let rawScale = visibleWidth / targetWidth\n        return min(\n            max(rawScale, minimumAutomaticFitScale),\n            maximumAutomaticFitScale\n        )\n    }\n\n    static func effectiveCSSWidth(\n        forVisibleWidth visibleWidth: CGFloat,\n        websiteMode: WebsiteMode\n    ) -> CGFloat {\n        guard visibleWidth > 0 else { return visibleWidth }\n        return visibleWidth / fittingScale(\n            forVisibleWidth: visibleWidth,\n            websiteMode: websiteMode\n        )\n    }\n""",
)
replace_once(
    "FloatTabs/Web/WebViewFactory.swift",
    """        } else {\n            webView.pageZoom = rendering.zoom\n        }\n\n        webView.customUserAgent = UserAgentProvider.customUserAgent(\n""",
    """        } else {\n            webView.pageZoom = 1\n            webView.magnification = rendering.zoom\n        }\n\n        webView.customUserAgent = UserAgentProvider.customUserAgent(\n""",
)
replace_once(
    "FloatTabs/Web/WebViewFactory.swift",
    """/// Keeps WKWebView at the real visible AppKit size. Website Mode is translated\n/// into a public WebKit pageZoom fitting factor so CSS layout can be 1280/390-\n/// class without any parent-view scaling. `userPageZoom` remains an independent\n/// product value and is composed with the internal fitting factor only at the\n/// final WebKit presentation boundary.\n""",
    """/// Keeps WKWebView at the real visible AppKit size. Website Mode uses a bounded\n/// public WebKit pageZoom fitting factor; the user's explicit Zoom is a separate\n/// native WKWebView magnification. This avoids multiplying two independent product\n/// concepts into one CSS zoom value, which distorted typography on real sites.\n""",
)
replace_once(
    "FloatTabs/Web/WebViewFactory.swift",
    """        let effectivePageZoom = websiteLayoutScale * userPageZoom\n        if abs(pageZoom - effectivePageZoom) > 0.0001 {\n            pageZoom = effectivePageZoom\n        }\n""",
    """        if abs(pageZoom - websiteLayoutScale) > 0.0001 {\n            pageZoom = websiteLayoutScale\n        }\n        if abs(magnification - userPageZoom) > 0.0001 {\n            magnification = userPageZoom\n        }\n""",
)

# -----------------------------------------------------------------------------
# Context menu fast rendering controls.
# -----------------------------------------------------------------------------
replace_once(
    "FloatTabs/UI/ExternalTabRail.swift",
    """    var onSetResidency: ((UUID, SlotResidencyPolicy) -> Void)?\n    var onSetBackgroundMedia: ((UUID, BackgroundMediaPolicy) -> Void)?\n""",
    """    var onSetWebsiteMode: ((UUID, WebsiteMode) -> Void)?\n    var onSetWindowSize: ((UUID, SimpleViewportPreset) -> Void)?\n    var onSetZoom: ((UUID, CGFloat) -> Void)?\n    var onSetResidency: ((UUID, SlotResidencyPolicy) -> Void)?\n    var onSetBackgroundMedia: ((UUID, BackgroundMediaPolicy) -> Void)?\n""",
)
replace_once(
    "FloatTabs/UI/ExternalTabRail.swift",
    """        view.onSetResidency = { [weak self] slotID, policy in\n            self?.onSetResidency?(slotID, policy)\n        }\n""",
    """        view.onSetWebsiteMode = { [weak self] slotID, mode in\n            self?.onSetWebsiteMode?(slotID, mode)\n        }\n        view.onSetWindowSize = { [weak self] slotID, preset in\n            self?.onSetWindowSize?(slotID, preset)\n        }\n        view.onSetZoom = { [weak self] slotID, zoom in\n            self?.onSetZoom?(slotID, zoom)\n        }\n        view.onSetResidency = { [weak self] slotID, policy in\n            self?.onSetResidency?(slotID, policy)\n        }\n""",
)
replace_once(
    "FloatTabs/UI/ExternalTabRail.swift",
    """    var onEdit: ((UUID) -> Void)?\n    var onRemove: ((UUID) -> Void)?\n    var onSetResidency: ((UUID, SlotResidencyPolicy) -> Void)?\n""",
    """    var onEdit: ((UUID) -> Void)?\n    var onRemove: ((UUID) -> Void)?\n    var onSetWebsiteMode: ((UUID, WebsiteMode) -> Void)?\n    var onSetWindowSize: ((UUID, SimpleViewportPreset) -> Void)?\n    var onSetZoom: ((UUID, CGFloat) -> Void)?\n    var onSetResidency: ((UUID, SlotResidencyPolicy) -> Void)?\n""",
)
replace_once(
    "FloatTabs/UI/ExternalTabRail.swift",
    """    private var residencyPolicy: SlotResidencyPolicy = .warm\n    private var backgroundMediaPolicy: BackgroundMediaPolicy = .pauseWhenInactive\n""",
    """    private var renderingProfile: WebRenderingProfile = .canonicalDefault\n    private var residencyPolicy: SlotResidencyPolicy = .warm\n    private var backgroundMediaPolicy: BackgroundMediaPolicy = .pauseWhenInactive\n""",
)
replace_once(
    "FloatTabs/UI/ExternalTabRail.swift",
    """        label.stringValue = profile.name\n        residencyPolicy = profile.residencyPolicy\n""",
    """        label.stringValue = profile.name\n        renderingProfile = profile.renderingProfile.normalized()\n        residencyPolicy = profile.residencyPolicy\n""",
)

menu_anchor = """        home.target = self\n        menu.addItem(home)\n        menu.addItem(.separator())\n\n        let residency = NSMenuItem(title: \"Residency\", action: nil, keyEquivalent: \"\")\n"""
menu_insert = """        home.target = self\n        menu.addItem(home)\n        menu.addItem(.separator())\n\n        let websiteMode = NSMenuItem(title: \"Website Mode\", action: nil, keyEquivalent: \"\")\n        let websiteModeMenu = NSMenu(title: \"Website Mode\")\n        for mode in WebsiteMode.allCases {\n            let item = NSMenuItem(\n                title: mode.displayName,\n                action: #selector(setWebsiteModeFromMenu(_:)),\n                keyEquivalent: \"\"\n            )\n            item.target = self\n            item.representedObject = mode.rawValue\n            item.state = mode == renderingProfile.websiteMode ? .on : .off\n            websiteModeMenu.addItem(item)\n        }\n        websiteMode.submenu = websiteModeMenu\n        menu.addItem(websiteMode)\n\n        let windowSize = NSMenuItem(title: \"Window Size\", action: nil, keyEquivalent: \"\")\n        let windowSizeMenu = NSMenu(title: \"Window Size\")\n        for preset in SimpleViewportPreset.allCases where preset != .custom {\n            let item = NSMenuItem(\n                title: preset.menuTitle,\n                action: #selector(setWindowSizeFromMenu(_:)),\n                keyEquivalent: \"\"\n            )\n            item.target = self\n            item.representedObject = preset.rawValue\n            item.state = preset == renderingProfile.sizePreset ? .on : .off\n            windowSizeMenu.addItem(item)\n        }\n        if renderingProfile.sizePreset == .custom {\n            windowSizeMenu.addItem(.separator())\n            let currentCustom = NSMenuItem(\n                title: \"Custom  \\(Int(renderingProfile.viewportWidth)) × \\(Int(renderingProfile.viewportHeight))\",\n                action: nil,\n                keyEquivalent: \"\"\n            )\n            currentCustom.state = .on\n            currentCustom.isEnabled = false\n            windowSizeMenu.addItem(currentCustom)\n        }\n        windowSize.submenu = windowSizeMenu\n        menu.addItem(windowSize)\n\n        let zoom = NSMenuItem(title: \"Zoom\", action: nil, keyEquivalent: \"\")\n        let zoomMenu = NSMenu(title: \"Zoom\")\n        for value in ZoomSteps.values {\n            let item = NSMenuItem(\n                title: ZoomSteps.percentageText(for: value),\n                action: #selector(setZoomFromMenu(_:)),\n                keyEquivalent: \"\"\n            )\n            item.target = self\n            item.representedObject = NSNumber(value: Double(value))\n            item.state = abs(value - renderingProfile.zoom) < 0.001 ? .on : .off\n            zoomMenu.addItem(item)\n        }\n        zoom.submenu = zoomMenu\n        menu.addItem(zoom)\n        menu.addItem(.separator())\n\n        let residency = NSMenuItem(title: \"Residency\", action: nil, keyEquivalent: \"\")\n"""
replace_once("FloatTabs/UI/ExternalTabRail.swift", menu_anchor, menu_insert)

replace_once(
    "FloatTabs/UI/ExternalTabRail.swift",
    """    @objc private func setResidencyFromMenu(_ sender: NSMenuItem) {\n""",
    """    @objc private func setWebsiteModeFromMenu(_ sender: NSMenuItem) {\n        guard let rawValue = sender.representedObject as? String,\n              let mode = WebsiteMode(rawValue: rawValue) else { return }\n        onSetWebsiteMode?(slotID, mode)\n    }\n\n    @objc private func setWindowSizeFromMenu(_ sender: NSMenuItem) {\n        guard let rawValue = sender.representedObject as? String,\n              let preset = SimpleViewportPreset(rawValue: rawValue),\n              preset != .custom else { return }\n        onSetWindowSize?(slotID, preset)\n    }\n\n    @objc private func setZoomFromMenu(_ sender: NSMenuItem) {\n        guard let number = sender.representedObject as? NSNumber else { return }\n        onSetZoom?(slotID, CGFloat(number.doubleValue))\n    }\n\n    @objc private func setResidencyFromMenu(_ sender: NSMenuItem) {\n""",
)

# Wire the new immediate actions into TabStore and active panel sizing.
replace_once(
    "FloatTabs/Panel/PanelController.swift",
    """        rail.onRemove = { [weak self] id in\n            self?.presentRemoveConfirmation(id: id)\n        }\n        rail.onSetResidency = { [weak self] id, policy in\n""",
    """        rail.onRemove = { [weak self] id in\n            self?.presentRemoveConfirmation(id: id)\n        }\n        rail.onSetWebsiteMode = { [weak self] id, mode in\n            self?.setWebsiteMode(id: id, mode: mode)\n        }\n        rail.onSetWindowSize = { [weak self] id, preset in\n            self?.setWindowSize(id: id, preset: preset)\n        }\n        rail.onSetZoom = { [weak self] id, zoom in\n            self?.setZoom(id: id, zoom: zoom)\n        }\n        rail.onSetResidency = { [weak self] id, policy in\n""",
)
replace_once(
    "FloatTabs/Panel/PanelController.swift",
    """    private func changeActiveZoom(larger: Bool) {\n""",
    """    private func setWebsiteMode(id: UUID, mode: WebsiteMode) {\n        guard let profile = tabStore.profiles.first(where: { $0.id == id }) else { return }\n        _ = tabStore.updateRenderingProfile(\n            id: id,\n            renderingProfile: profile.renderingProfile.settingWebsiteMode(mode)\n        )\n    }\n\n    private func setWindowSize(id: UUID, preset: SimpleViewportPreset) {\n        guard preset != .custom,\n              let profile = tabStore.profiles.first(where: { $0.id == id }) else { return }\n        let rendering = profile.renderingProfile.settingSimplePreset(preset)\n        guard tabStore.updateRenderingProfile(id: id, renderingProfile: rendering) else { return }\n        if tabStore.activeTabID == id {\n            applyPreferredViewport(rendering.viewportSize)\n        }\n    }\n\n    private func setZoom(id: UUID, zoom: CGFloat) {\n        guard let profile = tabStore.profiles.first(where: { $0.id == id }) else { return }\n        _ = tabStore.updateRenderingProfile(\n            id: id,\n            renderingProfile: profile.renderingProfile.settingZoom(zoom)\n        )\n        if tabStore.activeTabID == id {\n            zoomHUDView.show(zoom: ZoomSteps.nearest(to: zoom))\n        }\n    }\n\n    private func changeActiveZoom(larger: Bool) {\n""",
)

# Edit is now identity/name/url oriented; Add retains the full first-run controls.
replace_once(
    "FloatTabs/UI/WebAppEditorController.swift",
    """            initialRendering: .canonicalDefault,\n            attachedTo: window,\n""",
    """            initialRendering: .canonicalDefault,\n            showsPrimaryRenderingControls: true,\n            attachedTo: window,\n""",
)
replace_once(
    "FloatTabs/UI/WebAppEditorController.swift",
    """            initialRendering: profile.renderingProfile,\n            attachedTo: window,\n""",
    """            initialRendering: profile.renderingProfile,\n            showsPrimaryRenderingControls: false,\n            attachedTo: window,\n""",
)
replace_once(
    "FloatTabs/UI/WebAppEditorController.swift",
    """        initialURL: String,\n        initialRendering: WebRenderingProfile,\n        attachedTo window: NSWindow,\n""",
    """        initialURL: String,\n        initialRendering: WebRenderingProfile,\n        showsPrimaryRenderingControls: Bool,\n        attachedTo window: NSWindow,\n""",
)
replace_once(
    "FloatTabs/UI/WebAppEditorController.swift",
    """        let renderingForm = RenderingForm(initial: initialRendering)\n\n        let stack = NSStackView(views: [\n""",
    """        let renderingForm = RenderingForm(\n            initial: initialRendering,\n            showsPrimaryControls: showsPrimaryRenderingControls\n        )\n\n        let stack = NSStackView(views: [\n""",
)
replace_once(
    "FloatTabs/UI/WebAppEditorController.swift",
    """        stack.setFrameSize(NSSize(width: 400, height: 350))\n""",
    """        stack.setFrameSize(NSSize(\n            width: 400,\n            height: showsPrimaryRenderingControls ? 350 : 190\n        ))\n""",
)
replace_once(
    "FloatTabs/UI/WebAppEditorController.swift",
    """    init(initial: WebRenderingProfile) {\n        let rendering = initial.normalized()\n""",
    """    init(\n        initial: WebRenderingProfile,\n        showsPrimaryControls: Bool = true\n    ) {\n        let rendering = initial.normalized()\n""",
)
replace_once(
    "FloatTabs/UI/WebAppEditorController.swift",
    """        view = NSStackView(views: [\n            Self.label(\"Website Mode\"),\n            modePopup,\n            Self.label(\"Window Size\"),\n            sizeRow,\n            Self.label(\"Zoom\"),\n            zoomPopup,\n            advancedButton,\n        ])\n""",
    """        let primaryViews: [NSView] = showsPrimaryControls\n            ? [\n                Self.label(\"Website Mode\"),\n                modePopup,\n                Self.label(\"Window Size\"),\n                sizeRow,\n                Self.label(\"Zoom\"),\n                zoomPopup,\n                advancedButton,\n            ]\n            : [\n                Self.label(\"Advanced Compatibility\"),\n                advancedButton,\n            ]\n        view = NSStackView(views: primaryViews)\n""",
)

# -----------------------------------------------------------------------------
# Tests: resize geometry, context-menu shape, and rendering separation.
# -----------------------------------------------------------------------------
replace_once(
    "FloatTabsTests/ExternalShellTests.swift",
    """    func testMoveHoverTrackingRemainsActiveWhenAppIsInactive() {\n""",
    """    func testResizeHandleUsesExpandedInactiveAppHitTarget() {\n        XCTAssertGreaterThanOrEqual(PanelMetrics.resizeHandleSize, 30)\n        let handle = PanelResizeHandleView(frame: NSRect(x: 0, y: 0, width: 32, height: 32))\n        XCTAssertTrue(handle.hitTest(NSPoint(x: 2, y: 2)) === handle)\n        XCTAssertNil(handle.hitTest(NSPoint(x: 40, y: 40)))\n    }\n\n    func testMoveHoverTrackingRemainsActiveWhenAppIsInactive() {\n""",
)
replace_once(
    "FloatTabsTests/ExternalShellTests.swift",
    """            [\"Return to Home\", \"Residency\", \"Background Media\", \"Edit Web App…\", \"Remove Web App…\"]\n        )\n        XCTAssertEqual(menu.item(withTitle: \"Residency\")?.submenu?.items.map(\\.title), [\"Hot\", \"Warm\", \"Cold\"])\n""",
    """            [\"Return to Home\", \"Website Mode\", \"Window Size\", \"Zoom\", \"Residency\", \"Background Media\", \"Edit Web App…\", \"Remove Web App…\"]\n        )\n        XCTAssertEqual(menu.item(withTitle: \"Website Mode\")?.submenu?.items.map(\\.title), [\"Desktop\", \"Mobile\"])\n        XCTAssertEqual(\n            menu.item(withTitle: \"Window Size\")?.submenu?.items.filter { !$0.isSeparatorItem }.map(\\.title),\n            [\"Small  390 × 780\", \"Medium  430 × 820\", \"Large  600 × 800\", \"Wide  900 × 850\"]\n        )\n        XCTAssertEqual(menu.item(withTitle: \"Residency\")?.submenu?.items.map(\\.title), [\"Hot\", \"Warm\", \"Cold\"])\n""",
)

# Replace the rendering-specific test expectations using small targeted edits.
tests = Path("FloatTabsTests/WebViewFactoryTests.swift")
text = tests.read_text()
text = text.replace("XCTAssertEqual(webView.pageZoom, 1.25, accuracy: 0.001)", "XCTAssertEqual(webView.pageZoom, 1.0, accuracy: 0.001)\n        XCTAssertEqual(webView.magnification, 1.25, accuracy: 0.001)", 1)
text = text.replace("XCTAssertEqual(desktopScale, 430.0 / 1280.0, accuracy: 0.001)", "XCTAssertEqual(desktopScale, 0.50, accuracy: 0.001)", 1)
text = text.replace("XCTAssertEqual(mobileScale, 900.0 / 390.0, accuracy: 0.001)", "XCTAssertEqual(mobileScale, 1.00, accuracy: 0.001)", 1)
text = text.replace("XCTAssertEqual(floatWebView?.websiteLayoutScale ?? 0, 430.0 / 1280.0, accuracy: 0.01)\n        XCTAssertEqual(webView.pageZoom, 430.0 / 1280.0, accuracy: 0.01)", "XCTAssertEqual(floatWebView?.websiteLayoutScale ?? 0, 0.50, accuracy: 0.01)\n        XCTAssertEqual(webView.pageZoom, 0.50, accuracy: 0.01)\n        XCTAssertEqual(webView.magnification, 1.0, accuracy: 0.01)", 1)
text = text.replace("XCTAssertEqual(cssWidth, 1280, accuracy: 3)", "XCTAssertEqual(cssWidth, 860, accuracy: 3)", 1)
text = text.replace("XCTAssertEqual(mediaQuery, 1, accuracy: 0.001)", "XCTAssertEqual(mediaQuery, 0, accuracy: 0.001)", 1)
text = text.replace("XCTAssertEqual(floatWebView?.websiteLayoutScale ?? 0, 900.0 / 390.0, accuracy: 0.01)\n        XCTAssertEqual(webView.pageZoom, 900.0 / 390.0, accuracy: 0.01)", "XCTAssertEqual(floatWebView?.websiteLayoutScale ?? 0, 1.0, accuracy: 0.01)\n        XCTAssertEqual(webView.pageZoom, 1.0, accuracy: 0.01)\n        XCTAssertEqual(webView.magnification, 1.0, accuracy: 0.01)", 1)
text = text.replace("XCTAssertEqual(cssWidth, 390, accuracy: 3)", "XCTAssertEqual(cssWidth, 900, accuracy: 3)", 1)
# Last composition assertion: layout fit is independent from user magnification.
text = text.replace("XCTAssertEqual(webView.pageZoom, (430.0 / 1280.0) * 1.5, accuracy: 0.01)", "XCTAssertEqual(webView.pageZoom, 0.50, accuracy: 0.01)\n        XCTAssertEqual(webView.magnification, 1.50, accuracy: 0.01)", 1)
tests.write_text(text)

# Add an explicit pure-geometry assertion without depending on real website DOM.
replace_once(
    "FloatTabsTests/WebViewFactoryTests.swift",
    """    func testWebsiteLayoutScaleKeepsDesktopAndMobileIndependentFromWindowSize() {\n""",
    """    func testAutomaticFitKeepsExtremeCSSZoomWithinLegibleBounds() {\n        XCTAssertEqual(\n            WebsiteLayoutViewport.effectiveCSSWidth(\n                forVisibleWidth: 430,\n                websiteMode: .desktop\n            ),\n            860,\n            accuracy: 0.001\n        )\n        XCTAssertEqual(\n            WebsiteLayoutViewport.effectiveCSSWidth(\n                forVisibleWidth: 900,\n                websiteMode: .mobile\n            ),\n            900,\n            accuracy: 0.001\n        )\n    }\n\n    func testWebsiteLayoutScaleKeepsDesktopAndMobileIndependentFromWindowSize() {\n""",
)

print("Stage 5D core refinement patch applied")
