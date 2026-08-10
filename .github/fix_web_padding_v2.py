from pathlib import Path
import re


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def replace_test(text: str, name: str, replacement: str) -> str:
    pattern = re.compile(
        rf"(?ms)^    func {re.escape(name)}\(\) \{{.*?(?=^    func |^    private func |\Z)"
    )
    text, count = pattern.subn(replacement.rstrip() + "\n\n", text, count=1)
    if count != 1:
        raise SystemExit(f"{name}: expected exactly one function, found {count}")
    return text


# 1) WebViewFactory: keep user pageZoom independent; logical Desktop sizing is
# supplied by the AppKit host rather than by shrinking WKWebView pageZoom.
factory_path = Path("FloatTabs/Web/WebViewFactory.swift")
factory = factory_path.read_text()

old_logical = '''    /// AppKit geometry remains exactly the visible size. CSS layout widening is
    /// performed only by WKWebView.pageZoom, never by view transforms.
    static func logicalSize(
        forVisibleSize visibleSize: CGSize,
        websiteMode: WebsiteMode
    ) -> CGSize {
        visibleSize
    }'''
new_logical = '''    /// The visible FloatTabs frame and the website layout viewport are separate.
    /// Desktop receives a real desktop-class WKWebView frame; its containing
    /// AppKit host maps that logical frame uniformly into the visible panel.
    /// Mobile deliberately remains 1:1 with the visible panel.
    static func logicalSize(
        forVisibleSize visibleSize: CGSize,
        websiteMode: WebsiteMode
    ) -> CGSize {
        guard visibleSize.width > 0, visibleSize.height > 0 else {
            return visibleSize
        }

        let logicalWidth = targetCSSWidth(
            forVisibleWidth: visibleSize.width,
            websiteMode: websiteMode
        )
        guard logicalWidth > 0 else { return visibleSize }

        let scale = logicalWidth / visibleSize.width
        return CGSize(
            width: logicalWidth,
            height: visibleSize.height * scale
        )
    }'''
factory = replace_once(factory, old_logical, new_logical, "logicalSize")

old_comment = '''/// Keeps WKWebView at the real visible AppKit size. Desktop mode uses WebKit's
/// public pageZoom API to expose a desktop-class CSS width inside narrow FloatTabs
/// windows while preserving native AppKit/WebKit event coordinates. Mobile stays
/// strictly 1:1. User Zoom composes with the Desktop layout fit at this boundary.'''
new_comment = '''/// Keeps WKWebView page zoom independent from Website Mode. The AppKit host owns
/// Desktop viewport fitting, so WebKit lays out at a real desktop-class frame and
/// fonts/line-height are scaled uniformly with the rest of the rendered page.
/// `pageZoom` is reserved for the user's explicit Zoom value only.'''
factory = replace_once(factory, old_comment, new_comment, "FloatTabsWebView comment")

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
factory = replace_once(factory, old_refresh, new_refresh, "refreshWebsiteLayoutScale")
factory_path.write_text(factory)


# 2) WebViewContainer: activate the existing logical-host architecture for both
# transient and Hot slots. Inactive Hot hosts keep their old visible frame.
container_path = Path("FloatTabs/Web/WebViewContainer.swift")
container = container_path.read_text()

old_hot_host = '''final class WebSlotHostView: NSView {
    private(set) weak var webView: WKWebView?

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
            webView.autoresizingMask = [.width, .height]
            addSubview(webView)
            self.webView = webView
        }
        webView.frame = bounds
    }

    override func layout() {
        super.layout()
        if webView?.frame != bounds {
            webView?.frame = bounds
        }
    }
}'''
new_hot_host = '''final class WebSlotHostView: NSView {
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
}'''
container = replace_once(container, old_hot_host, new_hot_host, "WebSlotHostView")

old_layout = '''    override func layout() {
        super.layout()
        if activeSlotID == nil || hostedWebView != nil {
            updateWebsiteLayoutIfNeeded()
        }
        layer?.shadowPath = CGPath(
            roundedRect: bounds,
            cornerWidth: PanelMetrics.webPanelCornerRadius,
            cornerHeight: PanelMetrics.webPanelCornerRadius,
            transform: nil
        )
    }'''
new_layout = '''    override func layout() {
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
    }'''
container = replace_once(container, old_layout, new_layout, "WebPanelContainerView.layout")

old_hot_scale = '''        host.layoutSubtreeIfNeeded()
        bringToFront(host)

        websiteLayoutScale = 1
        activeSlotID = slotID
        activeWebView = webView'''
new_hot_scale = '''        host.layoutSubtreeIfNeeded()
        bringToFront(host)

        websiteLayoutScale = host.websiteLayoutScale
        activeSlotID = slotID
        activeWebView = webView'''
container = replace_once(container, old_hot_scale, new_hot_scale, "showHot scale")
container_path.write_text(container)


# 3) Tests: assert real logical WKWebView geometry, no internal pageZoom fitting,
# Hot parity, and real window hit-routing through the scaled host.
tests_path = Path("FloatTabsTests/WebViewFactoryTests.swift")
tests = tests_path.read_text()

tests = replace_test(tests, "testWebsiteLayoutViewportKeepsDesktopLayoutClassButMobileOneToOne", '''    func testWebsiteLayoutViewportKeepsDesktopLayoutClassButMobileOneToOne() {
        XCTAssertEqual(
            WebsiteLayoutViewport.targetCSSWidth(forVisibleWidth: 430, websiteMode: .desktop),
            1280,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WebsiteLayoutViewport.fittingScale(forVisibleWidth: 430, websiteMode: .desktop),
            430.0 / 1280.0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WebsiteLayoutViewport.targetCSSWidth(forVisibleWidth: 1400, websiteMode: .desktop),
            1400,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WebsiteLayoutViewport.targetCSSWidth(forVisibleWidth: 900, websiteMode: .mobile),
            900,
            accuracy: 0.001
        )

        let desktop = WebsiteLayoutViewport.logicalSize(
            forVisibleSize: CGSize(width: 430, height: 820),
            websiteMode: .desktop
        )
        XCTAssertEqual(desktop.width, 1280, accuracy: 0.001)
        XCTAssertEqual(desktop.height, 820.0 * 1280.0 / 430.0, accuracy: 0.001)

        let mobile = WebsiteLayoutViewport.logicalSize(
            forVisibleSize: CGSize(width: 900, height: 850),
            websiteMode: .mobile
        )
        XCTAssertEqual(mobile, CGSize(width: 900, height: 850))
    }''')

tests = replace_test(tests, "testDesktopHostKeepsPhysicalGeometryOneToOneWhileFittingCSSLayout", '''    func testDesktopHostUsesRealLogicalWebViewFrameWithoutPageZoomFit() {
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = host(webView, visibleSize: NSSize(width: 430, height: 820))
        let floatTabsWebView = tryUnwrapFloatTabsWebView(webView)

        XCTAssertEqual(container.bounds.size, NSSize(width: 430, height: 820))
        XCTAssertEqual(webView.frame.width, 1280, accuracy: 0.001)
        XCTAssertEqual(webView.frame.height, 820.0 * 1280.0 / 430.0, accuracy: 0.001)
        XCTAssertEqual(webView.bounds.size, webView.frame.size)
        XCTAssertEqual(container.websiteLayoutScale, 430.0 / 1280.0, accuracy: 0.001)
        XCTAssertEqual(floatTabsWebView.websiteLayoutScale, 1, accuracy: 0.001)
        XCTAssertEqual(webView.pageZoom, 1, accuracy: 0.001)
        XCTAssertEqual(webView.magnification, 1, accuracy: 0.001)
    }''')

tests = replace_test(tests, "testVisibleResizeRecomputesDesktopFitWithoutChangingPhysicalGeometry", '''    func testVisibleResizeRecomputesLogicalHostWithoutPageZoomFit() {
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = host(webView, visibleSize: NSSize(width: 430, height: 820))

        container.setFrameSize(NSSize(width: 900, height: 850))
        container.layoutSubtreeIfNeeded()
        webView.layoutSubtreeIfNeeded()

        XCTAssertEqual(container.bounds.size, NSSize(width: 900, height: 850))
        XCTAssertEqual(webView.frame.width, 1280, accuracy: 0.001)
        XCTAssertEqual(webView.frame.height, 850.0 * 1280.0 / 900.0, accuracy: 0.001)
        XCTAssertEqual(webView.bounds.size, webView.frame.size)
        XCTAssertEqual(container.websiteLayoutScale, 900.0 / 1280.0, accuracy: 0.001)
        XCTAssertEqual(webView.pageZoom, 1, accuracy: 0.001)
    }''')

tests = replace_test(tests, "testDesktopModeExposesDesktopClassCSSWidthInsideNarrowWindow", '''    func testDesktopModeExposesDesktopClassCSSWidthInsideNarrowWindow() {
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = host(webView, visibleSize: NSSize(width: 430, height: 820))
        loadTestHTML(in: webView)

        let cssWidth = evaluateNumber("document.body.clientWidth", in: webView)
        let desktopMediaQuery = evaluateNumber(
            "matchMedia('(min-width: 1000px)').matches ? 1 : 0",
            in: webView
        )

        XCTAssertEqual(container.bounds.width, 430, accuracy: 0.001)
        XCTAssertEqual(webView.frame.width, 1280, accuracy: 0.001)
        XCTAssertEqual(webView.pageZoom, 1, accuracy: 0.001)
        XCTAssertEqual(cssWidth, 1280, accuracy: 3)
        XCTAssertEqual(desktopMediaQuery, 1, accuracy: 0.001)
    }''')

tests = replace_test(tests, "testNativeWebCoordinatesRemainOneToOneWithVisibleCoordinates", '''    func testDesktopHostMapsVisibleCenterIntoLogicalWebCoordinates() {
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = host(webView, visibleSize: NSSize(width: 430, height: 820))

        let webPoint = webView.convert(NSPoint(x: 215, y: 410), from: container)
        XCTAssertEqual(webPoint.x, webView.bounds.midX, accuracy: 0.5)
        XCTAssertEqual(webPoint.y, webView.bounds.midY, accuracy: 0.5)
    }''')

tests = replace_test(tests, "testHotHostsPreserveInactiveViewportAcrossDifferentSlotSizes", '''    func testHotHostsPreserveInactiveViewportAcrossDifferentSlotSizes() {
        _ = NSApplication.shared
        let container = WebPanelContainerView(
            frame: NSRect(x: 0, y: 0, width: 430, height: 820)
        )
        let window = NSWindow(
            contentRect: container.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = container
        container.layoutSubtreeIfNeeded()

        let firstID = UUID()
        let secondID = UUID()
        let first = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let second = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)

        container.show(webView: first, slotID: firstID, residencyPolicy: .hot)
        container.layoutSubtreeIfNeeded()
        let firstSize = first.frame.size
        XCTAssertEqual(first.frame.width, 1280, accuracy: 0.001)
        XCTAssertEqual(container.websiteLayoutScale, 430.0 / 1280.0, accuracy: 0.001)
        XCTAssertTrue(first.window === window)

        container.deactivate(slotID: firstID, residencyPolicy: .hot)
        XCTAssertTrue(first.superview?.isHidden == true)
        container.setFrameSize(NSSize(width: 900, height: 850))
        container.layoutSubtreeIfNeeded()

        XCTAssertEqual(first.frame.size, firstSize)
        XCTAssertTrue(first.window === window)

        container.show(webView: second, slotID: secondID, residencyPolicy: .hot)
        container.layoutSubtreeIfNeeded()
        XCTAssertEqual(second.frame.width, 1280, accuracy: 0.001)
        XCTAssertEqual(container.websiteLayoutScale, 900.0 / 1280.0, accuracy: 0.001)
        XCTAssertEqual(first.frame.size, firstSize)
        XCTAssertTrue(first.window === window)
        XCTAssertTrue(second.window === window)
        XCTAssertTrue(first.superview?.isHidden == true)

        container.show(webView: first, slotID: firstID, residencyPolicy: .hot)
        container.layoutSubtreeIfNeeded()
        XCTAssertFalse(first.superview?.isHidden ?? true)
        XCTAssertTrue(container.currentWebView === first)
        XCTAssertEqual(first.frame.width, 1280, accuracy: 0.001)
        XCTAssertEqual(container.websiteLayoutScale, 900.0 / 1280.0, accuracy: 0.001)
        XCTAssertTrue(first.window === window)
    }''')

tests = replace_test(tests, "testDesktopPublicPageZoomKeepsNativeClickHitTestingWorking", '''    func testDesktopLogicalHostKeepsNativeWindowClickHitTestingWorking() {
        _ = NSApplication.shared
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = WebPanelContainerView(
            frame: NSRect(x: 0, y: 0, width: 430, height: 820)
        )
        container.show(webView: webView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 820),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = container
        window.orderFront(nil)
        container.layoutSubtreeIfNeeded()
        webView.layoutSubtreeIfNeeded()

        loadInteractiveTestHTML(in: webView)
        XCTAssertEqual(webView.frame.width, 1280, accuracy: 0.001)
        XCTAssertEqual(webView.pageZoom, 1, accuracy: 0.001)
        clickWindow(at: NSPoint(x: 215, y: 410), in: window)
        waitForJavaScriptNumber("window.clicks", in: webView, equals: 1)
        window.orderOut(nil)
    }''')

tests = replace_test(tests, "testDesktopLayoutFitComposesWithUserZoomWhileMobileUsesUserZoomOnly", '''    func testUserZoomStaysIndependentFromDesktopHostLayoutFit() {
        let desktopRendering = WebRenderingProfile.canonicalDefault.settingZoom(1.25)
        let desktopWebView = WebViewFactory.makeWebView(renderingProfile: desktopRendering)
        let desktopContainer = host(desktopWebView, visibleSize: NSSize(width: 430, height: 820))
        let desktopFloatWebView = tryUnwrapFloatTabsWebView(desktopWebView)

        XCTAssertEqual(desktopFloatWebView.userPageZoom, 1.25, accuracy: 0.001)
        XCTAssertEqual(desktopFloatWebView.websiteLayoutScale, 1, accuracy: 0.001)
        XCTAssertEqual(desktopContainer.websiteLayoutScale, 430.0 / 1280.0, accuracy: 0.001)
        XCTAssertEqual(desktopWebView.frame.width, 1280, accuracy: 0.001)
        XCTAssertEqual(desktopWebView.pageZoom, 1.25, accuracy: 0.001)
        XCTAssertEqual(desktopWebView.magnification, 1, accuracy: 0.001)

        let mobileRendering = desktopRendering
            .settingWebsiteMode(.mobile)
            .settingSimplePreset(.wide)
        let mobileWebView = WebViewFactory.makeWebView(renderingProfile: mobileRendering)
        let mobileContainer = host(mobileWebView, visibleSize: NSSize(width: 900, height: 850))
        let mobileFloatWebView = tryUnwrapFloatTabsWebView(mobileWebView)

        XCTAssertEqual(mobileFloatWebView.userPageZoom, 1.25, accuracy: 0.001)
        XCTAssertEqual(mobileFloatWebView.websiteLayoutScale, 1, accuracy: 0.001)
        XCTAssertEqual(mobileContainer.websiteLayoutScale, 1, accuracy: 0.001)
        XCTAssertEqual(mobileWebView.frame.width, 900, accuracy: 0.001)
        XCTAssertEqual(mobileWebView.pageZoom, 1.25, accuracy: 0.001)
        XCTAssertEqual(mobileWebView.magnification, 1, accuracy: 0.001)
    }''')

helper_anchor = '''    private func clickWebViewCenter(_ webView: WKWebView, in window: NSWindow) {'''
new_helper = '''    private func clickWindow(at location: NSPoint, in window: NSWindow) {
        guard let down = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: location,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 101,
            clickCount: 1,
            pressure: 1
        ), let up = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: location,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 102,
            clickCount: 1,
            pressure: 0
        ) else {
            XCTFail("Expected synthetic window click events")
            return
        }

        window.sendEvent(down)
        window.sendEvent(up)
    }

    private func clickWebViewCenter(_ webView: WKWebView, in window: NSWindow) {'''
tests = replace_once(tests, helper_anchor, new_helper, "clickWindow helper insertion")

tests_path.write_text(tests)
