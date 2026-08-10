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

factory_path = Path("FloatTabs/Web/WebViewFactory.swift")
factory = factory_path.read_text()

old_viewport = '''enum WebsiteLayoutViewport {
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
}'''
new_viewport = '''enum WebsiteLayoutViewport {
    /// Desktop mode should keep a desktop-class responsive layout even when the
    /// floating window is physically narrow. Mobile deliberately stays 1:1 so
    /// its WebKit/AppKit hit-testing and phone layout remain native.
    static let desktopMinimumCSSWidth: CGFloat = 1280

    static func targetCSSWidth(
        forVisibleWidth visibleWidth: CGFloat,
        websiteMode: WebsiteMode
    ) -> CGFloat {
        guard visibleWidth > 0 else { return visibleWidth }
        switch websiteMode {
        case .desktop:
            return max(desktopMinimumCSSWidth, visibleWidth)
        case .mobile:
            return visibleWidth
        }
    }

    static func fittingScale(
        forVisibleWidth visibleWidth: CGFloat,
        websiteMode: WebsiteMode
    ) -> CGFloat {
        guard visibleWidth > 0 else { return 1 }
        let targetWidth = targetCSSWidth(
            forVisibleWidth: visibleWidth,
            websiteMode: websiteMode
        )
        guard targetWidth > 0 else { return 1 }
        return visibleWidth / targetWidth
    }

    /// AppKit geometry remains exactly the visible size. CSS layout widening is
    /// performed only by WKWebView.pageZoom, never by view transforms.
    static func logicalSize(
        forVisibleSize visibleSize: CGSize,
        websiteMode: WebsiteMode
    ) -> CGSize {
        visibleSize
    }
}'''
factory = replace_once(factory, old_viewport, new_viewport, "WebsiteLayoutViewport")

old_comment = '''/// Keeps WKWebView at the real visible AppKit/CSS size. Website Mode changes
/// WebKit content mode / browser identity; user Zoom is the only pageZoom input.
/// No synthetic 1280/390 viewport and no AppKit/WebKit magnification are used.'''
new_comment = '''/// Keeps WKWebView at the real visible AppKit size. Desktop mode uses WebKit's
/// public pageZoom API to expose a desktop-class CSS width inside narrow FloatTabs
/// windows while preserving native AppKit/WebKit event coordinates. Mobile stays
/// strictly 1:1. User Zoom composes with the Desktop layout fit at this boundary.'''
factory = replace_once(factory, old_comment, new_comment, "FloatTabsWebView comment")

old_refresh = '''    private func refreshWebsiteLayoutScale() {
        websiteLayoutScale = 1
        if abs(pageZoom - userPageZoom) > 0.0001 {
            pageZoom = userPageZoom
        }
    }'''
new_refresh = '''    private func refreshWebsiteLayoutScale() {
        websiteLayoutScale = WebsiteLayoutViewport.fittingScale(
            forVisibleWidth: frame.width,
            websiteMode: websiteMode
        )
        let effectivePageZoom = websiteLayoutScale * userPageZoom
        if abs(pageZoom - effectivePageZoom) > 0.0001 {
            pageZoom = effectivePageZoom
        }
    }'''
factory = replace_once(factory, old_refresh, new_refresh, "refreshWebsiteLayoutScale")
factory_path.write_text(factory)

tests_path = Path("FloatTabsTests/WebViewFactoryTests.swift")
tests = tests_path.read_text()

tests = replace_test(tests, "testWebsiteLayoutViewportUsesRealVisibleWidthForBothModes", '''    func testWebsiteLayoutViewportKeepsDesktopLayoutClassButMobileOneToOne() {
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
            WebsiteLayoutViewport.fittingScale(forVisibleWidth: 1400, websiteMode: .desktop),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WebsiteLayoutViewport.targetCSSWidth(forVisibleWidth: 900, websiteMode: .mobile),
            900,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WebsiteLayoutViewport.fittingScale(forVisibleWidth: 900, websiteMode: .mobile),
            1,
            accuracy: 0.001
        )

        let physical = CGSize(width: 430, height: 820)
        XCTAssertEqual(
            WebsiteLayoutViewport.logicalSize(forVisibleSize: physical, websiteMode: .desktop),
            physical
        )
    }''')

tests = replace_test(tests, "testDesktopHostKeepsWebViewOneToOneWithVisibleSurface", '''    func testDesktopHostKeepsPhysicalGeometryOneToOneWhileFittingCSSLayout() {
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = host(webView, visibleSize: NSSize(width: 430, height: 820))
        let floatTabsWebView = tryUnwrapFloatTabsWebView(webView)

        XCTAssertEqual(container.bounds.size, NSSize(width: 430, height: 820))
        XCTAssertEqual(webView.frame.size, NSSize(width: 430, height: 820))
        XCTAssertEqual(webView.bounds.size, webView.frame.size)
        XCTAssertEqual(container.websiteLayoutScale, 1, accuracy: 0.001)
        XCTAssertEqual(floatTabsWebView.websiteLayoutScale, 430.0 / 1280.0, accuracy: 0.001)
        XCTAssertEqual(webView.pageZoom, 430.0 / 1280.0, accuracy: 0.001)
        XCTAssertEqual(webView.magnification, 1, accuracy: 0.001)
    }''')

tests = replace_test(tests, "testVisibleResizeKeepsNativeOneToOneGeometry", '''    func testVisibleResizeRecomputesDesktopFitWithoutChangingPhysicalGeometry() {
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = host(webView, visibleSize: NSSize(width: 430, height: 820))
        let floatTabsWebView = tryUnwrapFloatTabsWebView(webView)

        container.setFrameSize(NSSize(width: 900, height: 850))
        container.layoutSubtreeIfNeeded()
        webView.layoutSubtreeIfNeeded()

        XCTAssertEqual(container.bounds.size, NSSize(width: 900, height: 850))
        XCTAssertEqual(webView.frame.size, NSSize(width: 900, height: 850))
        XCTAssertEqual(webView.bounds.size, webView.frame.size)
        XCTAssertEqual(floatTabsWebView.websiteLayoutScale, 900.0 / 1280.0, accuracy: 0.001)
        XCTAssertEqual(webView.pageZoom, 900.0 / 1280.0, accuracy: 0.001)
    }''')

tests = replace_test(tests, "testDesktopModeDoesNotSynthesizeHiddenCSSWidth", '''    func testDesktopModeExposesDesktopClassCSSWidthInsideNarrowWindow() {
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = host(webView, visibleSize: NSSize(width: 430, height: 820))
        loadTestHTML(in: webView)

        let cssWidth = evaluateNumber("document.body.clientWidth", in: webView)
        let desktopMediaQuery = evaluateNumber(
            "matchMedia('(min-width: 1000px)').matches ? 1 : 0",
            in: webView
        )

        XCTAssertEqual(container.bounds.width, 430, accuracy: 0.001)
        XCTAssertEqual(webView.frame.width, 430, accuracy: 0.001)
        XCTAssertEqual(cssWidth, 1280, accuracy: 3)
        XCTAssertEqual(desktopMediaQuery, 1, accuracy: 0.001)
    }''')

tests = replace_test(tests, "testMobileModeDoesNotSynthesizeHiddenCSSWidth", '''    func testMobileModeRemainsNativeOneToOneAtWideWindowSize() {
        let rendering = WebRenderingProfile.canonicalDefault
            .settingWebsiteMode(.mobile)
            .settingSimplePreset(.wide)
        let webView = WebViewFactory.makeWebView(renderingProfile: rendering)
        let container = host(webView, visibleSize: NSSize(width: 900, height: 850))
        let floatTabsWebView = tryUnwrapFloatTabsWebView(webView)
        loadTestHTML(in: webView)

        let cssWidth = evaluateNumber("document.body.clientWidth", in: webView)
        XCTAssertEqual(container.bounds.width, 900, accuracy: 0.001)
        XCTAssertEqual(webView.frame.width, 900, accuracy: 0.001)
        XCTAssertEqual(floatTabsWebView.websiteLayoutScale, 1, accuracy: 0.001)
        XCTAssertEqual(webView.pageZoom, 1, accuracy: 0.001)
        XCTAssertEqual(cssWidth, 900, accuracy: 3)
    }''')

tests = replace_test(tests, "testUserZoomIsOnlyPageZoomInputAcrossWebsiteModes", '''    func testDesktopLayoutFitComposesWithUserZoomWhileMobileUsesUserZoomOnly() {
        let desktopRendering = WebRenderingProfile.canonicalDefault.settingZoom(1.25)
        let desktopWebView = WebViewFactory.makeWebView(renderingProfile: desktopRendering)
        _ = host(desktopWebView, visibleSize: NSSize(width: 430, height: 820))
        let desktopFloatWebView = tryUnwrapFloatTabsWebView(desktopWebView)

        XCTAssertEqual(desktopFloatWebView.userPageZoom, 1.25, accuracy: 0.001)
        XCTAssertEqual(desktopFloatWebView.websiteLayoutScale, 430.0 / 1280.0, accuracy: 0.001)
        XCTAssertEqual(
            desktopWebView.pageZoom,
            1.25 * 430.0 / 1280.0,
            accuracy: 0.001
        )
        XCTAssertEqual(desktopWebView.magnification, 1, accuracy: 0.001)

        let mobileRendering = desktopRendering
            .settingWebsiteMode(.mobile)
            .settingSimplePreset(.wide)
        let mobileWebView = WebViewFactory.makeWebView(renderingProfile: mobileRendering)
        _ = host(mobileWebView, visibleSize: NSSize(width: 900, height: 850))
        let mobileFloatWebView = tryUnwrapFloatTabsWebView(mobileWebView)

        XCTAssertEqual(mobileFloatWebView.userPageZoom, 1.25, accuracy: 0.001)
        XCTAssertEqual(mobileFloatWebView.websiteLayoutScale, 1, accuracy: 0.001)
        XCTAssertEqual(mobileWebView.pageZoom, 1.25, accuracy: 0.001)
        XCTAssertEqual(mobileWebView.magnification, 1, accuracy: 0.001)
    }''')

tests_path.write_text(tests)
