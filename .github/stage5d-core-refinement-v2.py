from pathlib import Path

patch = Path('.github/stage5d-core-refinement.py')
text = patch.read_text()

render_start_marker = '''# -----------------------------------------------------------------------------
# Rendering boundary: pageZoom owns only layout fitting; magnification owns the
'''
context_marker = '''# -----------------------------------------------------------------------------
# Context menu fast rendering controls.
'''
render_start = text.index(render_start_marker)
context_start = text.index(context_marker)

safe_rendering = r'''# -----------------------------------------------------------------------------
# Rendering boundary: Website Mode owns browser content mode / identity; Window
# Size owns the real WKWebView viewport; user Zoom alone owns WKWebView.pageZoom.
# Do not synthesize a second 1280/390 CSS viewport through pageZoom and do not use
# AppKit/WKWebView magnification. Real-site QA showed the synthetic fit distorted
# typography/cropping, while magnification regressed native click hit-testing.
# -----------------------------------------------------------------------------
replace_once(
    "FloatTabs/Web/WebViewFactory.swift",
    """/// Website Mode owns the CSS layout class while Window Size remains the real
/// AppKit/WKWebView size. The public WKWebView.pageZoom API provides the mapping
/// between the physical width and the target CSS width. This keeps WebKit's own
/// event/hit-testing pipeline intact and avoids AppKit coordinate transforms or
/// private WebKit layout SPI.
enum WebsiteLayoutViewport {
    static let desktopMinimumCSSWidth: CGFloat = 1280
    static let mobileMaximumCSSWidth: CGFloat = 390

    static func targetCSSWidth(
        forVisibleWidth visibleWidth: CGFloat,
        websiteMode: WebsiteMode
    ) -> CGFloat {
        guard visibleWidth > 0 else { return visibleWidth }
        switch websiteMode {
        case .desktop:
            return max(desktopMinimumCSSWidth, visibleWidth)
        case .mobile:
            return min(mobileMaximumCSSWidth, visibleWidth)
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

    /// Compatibility hook for WebPanelContainerView. Under the public pageZoom
    /// strategy the AppKit host must remain 1:1 with the visible surface; the
    /// logical CSS width is produced inside WebKit instead of by resizing views.
    static func logicalSize(
        forVisibleSize visibleSize: CGSize,
        websiteMode: WebsiteMode
    ) -> CGSize {
        visibleSize
    }
}
""",
    """/// Window Size is the real WKWebView/CSS viewport. Website Mode changes
/// WebKit's requested content mode and browser identity, but does not manufacture
/// a second hidden 1280/390 CSS width through zoom. Keeping this boundary 1:1
/// preserves native typography, responsive layout and click hit-testing.
enum WebsiteLayoutViewport {
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
}
""",
)

replace_once(
    "FloatTabs/Web/WebViewFactory.swift",
    """/// Keeps WKWebView at the real visible AppKit size. Website Mode is translated
/// into a public WebKit pageZoom fitting factor so CSS layout can be 1280/390-
/// class without any parent-view scaling. `userPageZoom` remains an independent
/// product value and is composed with the internal fitting factor only at the
/// final WebKit presentation boundary.
""",
    """/// Keeps WKWebView at the real visible AppKit/CSS size. Website Mode is a
/// content-mode / browser-identity choice. User Zoom is the only pageZoom input;
/// it is never multiplied by an automatic Website Mode fitting factor.
""",
)

replace_once(
    "FloatTabs/Web/WebViewFactory.swift",
    """    private func refreshWebsiteLayoutScale() {
        websiteLayoutScale = WebsiteLayoutViewport.fittingScale(
            forVisibleWidth: frame.width,
            websiteMode: websiteMode
        )
        let effectivePageZoom = websiteLayoutScale * userPageZoom
        if abs(pageZoom - effectivePageZoom) > 0.0001 {
            pageZoom = effectivePageZoom
        }
    }
""",
    """    private func refreshWebsiteLayoutScale() {
        websiteLayoutScale = 1
        if abs(pageZoom - userPageZoom) > 0.0001 {
            pageZoom = userPageZoom
        }
    }
""",
)

'''
text = text[:render_start] + safe_rendering + text[context_start:]

# Keep the quick-control menu compact: rendering controls form one group and the
# existing residency controls follow directly without an empty top-level row.
text = text.replace(
    '        menu.addItem(zoom)\\n        menu.addItem(.separator())\\n\\n        let residency = NSMenuItem',
    '        menu.addItem(zoom)\\n\\n        let residency = NSMenuItem',
    1,
)

# Replace the old experimental rendering-test rewrite with expectations for the
# final 1:1 viewport / pageZoom-only model.
test_marker = '# Replace the rendering-specific test expectations using small targeted edits.\n'
print_marker = 'print("Stage 5D core refinement patch applied")\n'
test_start = text.index(test_marker)
print_start = text.index(print_marker)

safe_tests = r'''# Rendering tests: Website Mode does not synthesize CSS width; user Zoom is the
# only pageZoom input and native click hit-testing stays in the regression suite.
tests = Path("FloatTabsTests/WebViewFactoryTests.swift")
test_text = tests.read_text()

def replace_test_function(source: str, name: str, next_name: str, replacement: str) -> str:
    start = source.index(f"    func {name}() {{")
    end = source.index(f"    func {next_name}() {{", start)
    return source[:start] + replacement.rstrip() + "\n\n" + source[end:]

test_text = replace_test_function(
    test_text,
    "testWebsiteLayoutViewportSeparatesTargetCSSWidthFromVisibleWindowSize",
    "testDesktopHostKeepsWebViewOneToOneWithVisibleSurface",
    """
    func testWebsiteLayoutViewportIsAlwaysTheRealVisibleWidth() {
        XCTAssertEqual(
            WebsiteLayoutViewport.targetCSSWidth(forVisibleWidth: 430, websiteMode: .desktop),
            430,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WebsiteLayoutViewport.fittingScale(forVisibleWidth: 430, websiteMode: .desktop),
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
    }
    """,
)

test_text = replace_test_function(
    test_text,
    "testDesktopHostKeepsWebViewOneToOneWithVisibleSurface",
    "testVisibleResizeRecomputesPublicWebKitFitWithoutChangingPhysicalGeometry",
    """
    func testDesktopHostKeepsWebViewAndCSSScaleOneToOneWithVisibleSurface() {
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
    }
    """,
)

test_text = replace_test_function(
    test_text,
    "testVisibleResizeRecomputesPublicWebKitFitWithoutChangingPhysicalGeometry",
    "testDesktopModeChangesActualCSSLayoutWidthWhileVisibleSurfaceStaysNarrow",
    """
    func testVisibleResizeKeepsNativeOneToOneGeometryAndZoom() {
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = host(webView, visibleSize: NSSize(width: 430, height: 820))
        let floatTabsWebView = tryUnwrapFloatTabsWebView(webView)

        container.setFrameSize(NSSize(width: 900, height: 850))
        container.layoutSubtreeIfNeeded()
        webView.layoutSubtreeIfNeeded()

        XCTAssertEqual(container.bounds.size, NSSize(width: 900, height: 850))
        XCTAssertEqual(webView.frame.size, NSSize(width: 900, height: 850))
        XCTAssertEqual(webView.bounds.size, webView.frame.size)
        XCTAssertEqual(floatTabsWebView.websiteMode, .desktop)
        XCTAssertEqual(floatTabsWebView.websiteLayoutScale, 1, accuracy: 0.001)
        XCTAssertEqual(webView.pageZoom, 1, accuracy: 0.001)
    }
    """,
)

test_text = replace_test_function(
    test_text,
    "testDesktopModeChangesActualCSSLayoutWidthWhileVisibleSurfaceStaysNarrow",
    "testMobileModeChangesActualCSSLayoutWidthWhileVisibleSurfaceStaysWide",
    """
    func testDesktopModeUsesRealCSSWidthInsideNarrowPanel() {
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = host(webView, visibleSize: NSSize(width: 430, height: 820))

        loadTestHTML(in: webView)
        let cssWidth = evaluateNumber("document.body.clientWidth", in: webView)
        let innerWidth = evaluateNumber("window.innerWidth", in: webView)
        let desktopMediaQuery = evaluateNumber(
            "matchMedia('(min-width: 1000px)').matches ? 1 : 0",
            in: webView
        )

        XCTAssertEqual(container.bounds.width, 430, accuracy: 0.001)
        XCTAssertEqual(webView.frame.width, 430, accuracy: 0.001)
        XCTAssertEqual(cssWidth, 430, accuracy: 2)
        XCTAssertEqual(innerWidth, 430, accuracy: 2)
        XCTAssertEqual(desktopMediaQuery, 0, accuracy: 0.001)
    }
    """,
)

test_text = replace_test_function(
    test_text,
    "testMobileModeChangesActualCSSLayoutWidthWhileVisibleSurfaceStaysWide",
    "testNativeWebCoordinatesRemainOneToOneWithVisibleCoordinates",
    """
    func testMobileModeUsesRealCSSWidthInsideWidePanel() {
        let rendering = WebRenderingProfile.canonicalDefault
            .settingWebsiteMode(.mobile)
            .settingSimplePreset(.wide)
        let webView = WebViewFactory.makeWebView(renderingProfile: rendering)
        let container = host(webView, visibleSize: NSSize(width: 900, height: 850))
        let floatTabsWebView = tryUnwrapFloatTabsWebView(webView)

        loadTestHTML(in: webView)
        let cssWidth = evaluateNumber("document.body.clientWidth", in: webView)
        let innerWidth = evaluateNumber("window.innerWidth", in: webView)

        XCTAssertEqual(container.bounds.width, 900, accuracy: 0.001)
        XCTAssertEqual(webView.frame.width, 900, accuracy: 0.001)
        XCTAssertEqual(floatTabsWebView.websiteLayoutScale, 1, accuracy: 0.001)
        XCTAssertEqual(webView.pageZoom, 1, accuracy: 0.001)
        XCTAssertEqual(cssWidth, 900, accuracy: 2)
        XCTAssertEqual(innerWidth, 900, accuracy: 2)
    }
    """,
)

test_text = replace_test_function(
    test_text,
    "testWebsiteFitComposesWithIndependentUserZoomState",
    "testNavigationObserverRestoresWebsiteModeWithoutDiscardingUserZoom",
    """
    func testUserZoomIsIndependentFromWebsiteModeAndWindowSize() {
        let desktopRendering = WebRenderingProfile.canonicalDefault.settingZoom(1.25)
        let desktopWebView = WebViewFactory.makeWebView(renderingProfile: desktopRendering)
        _ = host(desktopWebView, visibleSize: NSSize(width: 430, height: 820))
        let desktopFloatWebView = tryUnwrapFloatTabsWebView(desktopWebView)

        XCTAssertEqual(desktopFloatWebView.userPageZoom, 1.25, accuracy: 0.001)
        XCTAssertEqual(desktopFloatWebView.websiteLayoutScale, 1, accuracy: 0.001)
        XCTAssertEqual(desktopWebView.pageZoom, 1.25, accuracy: 0.001)
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
    }
    """,
)

test_text = replace_test_function(
    test_text,
    "testNavigationObserverRestoresWebsiteModeWithoutDiscardingUserZoom",
    "testMacOSSafariRuntimeUsesNativeWebKitUAWithSafariSuffix",
    """
    func testNavigationObserverRestoresWebsiteModeWithoutDiscardingUserZoom() {
        let rendering = WebRenderingProfile.canonicalDefault
            .settingWebsiteMode(.mobile)
            .settingZoom(1.25)
        let webView = WebViewFactory.makeWebView(renderingProfile: rendering)
        _ = host(webView, visibleSize: NSSize(width: 900, height: 850))
        let floatTabsWebView = tryUnwrapFloatTabsWebView(webView)

        let observer = SlotNavigationObserver(
            slotID: UUID(),
            webView: webView,
            websiteMode: .mobile,
            onURLChange: { _, _ in }
        )
        observer.webView(webView, didFinish: nil)

        XCTAssertEqual(floatTabsWebView.websiteMode, .mobile)
        XCTAssertEqual(floatTabsWebView.userPageZoom, 1.25, accuracy: 0.001)
        XCTAssertEqual(floatTabsWebView.websiteLayoutScale, 1, accuracy: 0.001)
        XCTAssertEqual(webView.pageZoom, 1.25, accuracy: 0.001)
    }
    """,
)

tests.write_text(test_text)

# Canonical default currently uses a custom 864×564 viewport, so the quick-size
# submenu must retain that current value as read-only context beneath presets.
shell_tests = Path("FloatTabsTests/ExternalShellTests.swift")
shell_text = shell_tests.read_text()
shell_text = shell_text.replace(
    '["Small  390 × 780", "Medium  430 × 820", "Large  600 × 800", "Wide  900 × 850"]',
    '["Small  390 × 780", "Medium  430 × 820", "Large  600 × 800", "Wide  900 × 850", "Custom  864 × 564"]',
    1,
)
shell_tests.write_text(shell_text)

'''
text = text[:test_start] + safe_tests + print_marker + text[print_start + len(print_marker):]
patch.write_text(text)
print('prepared Stage 5D core patch v2')
