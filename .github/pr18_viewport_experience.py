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


# ---------------------------------------------------------------------------
# Production: four physically distinct viewport experiences.
# ---------------------------------------------------------------------------
rendering_path = Path("FloatTabs/Tabs/WebRenderingProfile.swift")
rendering = rendering_path.read_text()
rendering = replace_once(
    rendering,
    '''    var size: CGSize? {
        switch self {
        case .small: CGSize(width: 390, height: 780)
        case .medium: CGSize(width: 430, height: 820)
        case .large: CGSize(width: 600, height: 800)
        case .wide: CGSize(width: 900, height: 850)
        case .custom: nil
        }
    }''',
    '''    /// Visible FloatTabs viewport sizes are product experience tiers, not
    /// device emulation sizes. Their spacing is intentionally large enough to
    /// produce materially different reading/browsing surfaces.
    var size: CGSize? {
        switch self {
        case .small: CGSize(width: 420, height: 760)
        case .medium: CGSize(width: 600, height: 820)
        case .large: CGSize(width: 820, height: 850)
        case .wide: CGSize(width: 1080, height: 850)
        case .custom: nil
        }
    }''',
    "preset visible sizes",
)
rendering = replace_once(
    rendering,
    '''        viewportWidth: 430,
        viewportHeight: 820,''',
    '''        viewportWidth: 600,
        viewportHeight: 820,''',
    "canonical medium size",
)
rendering = replace_once(
    rendering,
    '''        let width = try container.decodeIfPresent(CGFloat.self, forKey: .viewportWidth) ?? 430
        let height = try container.decodeIfPresent(CGFloat.self, forKey: .viewportHeight) ?? 820''',
    '''        let width = try container.decodeIfPresent(CGFloat.self, forKey: .viewportWidth) ?? 600
        let height = try container.decodeIfPresent(CGFloat.self, forKey: .viewportHeight) ?? 820''',
    "decode medium fallback",
)
rendering_path.write_text(rendering)

screen_path = Path("FloatTabs/Panel/ScreenPositioning.swift")
screen = screen_path.read_text()
screen = replace_once(
    screen,
    '''    static let defaultViewportSize = NSSize(width: 430, height: 820)''',
    '''    static let defaultViewportSize = NSSize(width: 600, height: 820)''',
    "default panel viewport",
)
screen_path.write_text(screen)

prefs_path = Path("FloatTabs/Persistence/AppPreferencesStore.swift")
prefs = prefs_path.read_text()
prefs = replace_once(
    prefs,
    '''    static let defaultFixedViewportSize = CGSize(width: 430, height: 820)''',
    '''    static let defaultFixedViewportSize = CGSize(width: 600, height: 820)''',
    "default fixed viewport",
)
prefs_path.write_text(prefs)

factory_path = Path("FloatTabs/Web/WebViewFactory.swift")
factory = factory_path.read_text()
pattern = re.compile(r"(?ms)^/// Website Mode owns the CSS layout class.*?^}\n\n@MainActor\nenum WebViewFactory")
replacement = '''/// Website Mode owns the responsive layout class while Window Size remains the
/// real visible FloatTabs viewport. Desktop maps visible widths into deliberate
/// experience classes so Small/Medium/Large/Wide do not merely show the same
/// 1280px page at four scales. Mobile remains native 1:1. The AppKit logical
/// host performs the uniform coordinate mapping; pageZoom remains user Zoom.
enum WebsiteLayoutViewport {
    static let compactVisibleMaximum: CGFloat = 520
    static let balancedVisibleMaximum: CGFloat = 720
    static let standardVisibleMaximum: CGFloat = 960

    static let compactCSSWidth: CGFloat = 720
    static let balancedCSSWidth: CGFloat = 1024
    static let standardCSSWidth: CGFloat = 1280
    static let expandedCSSWidth: CGFloat = 1440

    static func desktopCSSWidth(forVisibleWidth visibleWidth: CGFloat) -> CGFloat {
        guard visibleWidth > 0 else { return visibleWidth }
        switch visibleWidth {
        case ...compactVisibleMaximum:
            return compactCSSWidth
        case ...balancedVisibleMaximum:
            return balancedCSSWidth
        case ...standardVisibleMaximum:
            return standardCSSWidth
        default:
            return max(expandedCSSWidth, visibleWidth)
        }
    }

    static func targetCSSWidth(
        forVisibleWidth visibleWidth: CGFloat,
        websiteMode: WebsiteMode
    ) -> CGFloat {
        guard visibleWidth > 0 else { return visibleWidth }
        switch websiteMode {
        case .desktop:
            return desktopCSSWidth(forVisibleWidth: visibleWidth)
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
    }
}

@MainActor
enum WebViewFactory'''
factory, count = pattern.subn(replacement, factory, count=1)
if count != 1:
    raise SystemExit(f"WebsiteLayoutViewport: expected exactly one block, found {count}")
factory_path.write_text(factory)


# ---------------------------------------------------------------------------
# Tests: product geometry, legacy preservation, real responsive layout classes.
# ---------------------------------------------------------------------------
prefs_tests_path = Path("FloatTabsTests/AppPreferencesStoreTests.swift")
prefs_tests = prefs_tests_path.read_text()
prefs_tests = replace_test(prefs_tests, "testFixedViewportDefaultsToMediumAndPersistsSeparately", '''    func testFixedViewportDefaultsToMediumAndPersistsSeparately() {
        let first = AppPreferencesStore(defaults: defaults)
        XCTAssertFalse(first.hasStoredFixedViewportSize)
        XCTAssertEqual(first.fixedViewportSize.width, 600, accuracy: 0.001)
        XCTAssertEqual(first.fixedViewportSize.height, 820, accuracy: 0.001)

        first.fixedViewportSize = CGSize(width: 777, height: 666)
        XCTAssertTrue(first.hasStoredFixedViewportSize)

        let second = AppPreferencesStore(defaults: defaults)
        XCTAssertEqual(second.fixedViewportSize.width, 777, accuracy: 0.001)
        XCTAssertEqual(second.fixedViewportSize.height, 666, accuracy: 0.001)
        XCTAssertNil(SimpleViewportPreset.matching(second.fixedViewportSize))
    }''')
prefs_tests_path.write_text(prefs_tests)

screen_tests_path = Path("FloatTabsTests/ScreenPositioningTests.swift")
screen_tests = screen_tests_path.read_text()
screen_tests = replace_test(screen_tests, "testDefaultViewportProducesExpectedTotalPanelSize", '''    func testDefaultViewportProducesExpectedTotalPanelSize() {
        XCTAssertEqual(
            PanelMetrics.panelSize(forViewport: NSSize(width: 600, height: 820)),
            NSSize(width: 688, height: 844)
        )
        XCTAssertEqual(PanelMetrics.defaultPanelSize, NSSize(width: 688, height: 844))
    }''')
screen_tests = replace_test(screen_tests, "testPanelSizeProducesViewportSizeWithoutShellChrome", '''    func testPanelSizeProducesViewportSizeWithoutShellChrome() {
        XCTAssertEqual(
            PanelMetrics.viewportSize(forPanelSize: NSSize(width: 688, height: 844)),
            NSSize(width: 600, height: 820)
        )
    }''')
screen_tests = replace_test(screen_tests, "testCenteredFrameUsesRequestedSizeWhenItFits", '''    func testCenteredFrameUsesRequestedSizeWhenItFits() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 1000)

        let frame = ScreenPositioning.centeredFrame(
            size: PanelMetrics.defaultPanelSize,
            in: visible
        )

        XCTAssertEqual(frame.size, NSSize(width: 688, height: 844))
        XCTAssertEqual(frame.midX, visible.midX, accuracy: 0.001)
        XCTAssertEqual(frame.midY, visible.midY, accuracy: 0.001)
    }''')
screen_tests_path.write_text(screen_tests)

shell_tests_path = Path("FloatTabsTests/ExternalShellTests.swift")
shell_tests = shell_tests_path.read_text()
shell_tests = replace_once(
    shell_tests,
    '''            ["Small  390 × 780", "Medium  430 × 820", "Large  600 × 800", "Wide  900 × 850"]''',
    '''            ["Small  420 × 760", "Medium  600 × 820", "Large  820 × 850", "Wide  1080 × 850"]''',
    "context menu preset titles",
)
shell_tests_path.write_text(shell_tests)

repo_tests_path = Path("FloatTabsTests/ProfileRepositoryTests.swift")
repo_tests = repo_tests_path.read_text()
repo_tests = replace_once(
    repo_tests,
    '''            XCTAssertEqual(profile.renderingProfile.sizePreset, .small)
            XCTAssertEqual(profile.renderingProfile.viewportSize, CGSize(width: 390, height: 780))''',
    '''            // Legacy records without a named preset keep their exact old
            // geometry instead of being silently reinterpreted as the new Small.
            XCTAssertEqual(profile.renderingProfile.sizePreset, .custom)
            XCTAssertEqual(profile.renderingProfile.viewportSize, CGSize(width: 390, height: 780))''',
    "legacy explicit size preservation",
)
repo_tests_path.write_text(repo_tests)

web_tests_path = Path("FloatTabsTests/WebViewFactoryTests.swift")
web_tests = web_tests_path.read_text()
web_tests = replace_test(web_tests, "testWebsiteLayoutViewportKeepsDesktopLayoutClassButMobileOneToOne", '''    func testWebsiteLayoutViewportMapsVisibleWidthsToDistinctDesktopExperiences() {
        XCTAssertEqual(
            WebsiteLayoutViewport.targetCSSWidth(forVisibleWidth: 420, websiteMode: .desktop),
            720,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WebsiteLayoutViewport.targetCSSWidth(forVisibleWidth: 600, websiteMode: .desktop),
            1024,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WebsiteLayoutViewport.targetCSSWidth(forVisibleWidth: 820, websiteMode: .desktop),
            1280,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WebsiteLayoutViewport.targetCSSWidth(forVisibleWidth: 1080, websiteMode: .desktop),
            1440,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WebsiteLayoutViewport.targetCSSWidth(forVisibleWidth: 1600, websiteMode: .desktop),
            1600,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WebsiteLayoutViewport.targetCSSWidth(forVisibleWidth: 1080, websiteMode: .mobile),
            1080,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WebsiteLayoutViewport.fittingScale(forVisibleWidth: 600, websiteMode: .desktop),
            600.0 / 1024.0,
            accuracy: 0.001
        )

        let medium = WebsiteLayoutViewport.logicalSize(
            forVisibleSize: CGSize(width: 600, height: 820),
            websiteMode: .desktop
        )
        XCTAssertEqual(medium.width, 1024, accuracy: 0.001)
        XCTAssertEqual(medium.height, 820.0 * 1024.0 / 600.0, accuracy: 0.001)

        let mobile = WebsiteLayoutViewport.logicalSize(
            forVisibleSize: CGSize(width: 1080, height: 850),
            websiteMode: .mobile
        )
        XCTAssertEqual(mobile, CGSize(width: 1080, height: 850))
    }''')
web_tests = replace_test(web_tests, "testDesktopHostUsesRealLogicalWebViewFrameWithoutPageZoomFit", '''    func testMediumDesktopHostUsesBalancedLogicalLayoutWithoutPageZoomFit() {
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = host(webView, visibleSize: NSSize(width: 600, height: 820))
        let floatTabsWebView = tryUnwrapFloatTabsWebView(webView)

        XCTAssertEqual(container.bounds.size, NSSize(width: 600, height: 820))
        XCTAssertEqual(webView.frame.width, 1024, accuracy: 0.001)
        XCTAssertEqual(webView.frame.height, 820.0 * 1024.0 / 600.0, accuracy: 0.001)
        XCTAssertEqual(webView.bounds.size, webView.frame.size)
        XCTAssertEqual(container.websiteLayoutScale, 600.0 / 1024.0, accuracy: 0.001)
        XCTAssertEqual(floatTabsWebView.websiteLayoutScale, 1, accuracy: 0.001)
        XCTAssertEqual(webView.pageZoom, 1, accuracy: 0.001)
        XCTAssertEqual(webView.magnification, 1, accuracy: 0.001)
    }''')
web_tests = replace_test(web_tests, "testVisibleResizeRecomputesLogicalHostWithoutPageZoomFit", '''    func testVisibleResizeMovesBetweenDesktopExperienceClassesWithoutPageZoomFit() {
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = host(webView, visibleSize: NSSize(width: 600, height: 820))

        XCTAssertEqual(webView.frame.width, 1024, accuracy: 0.001)
        container.setFrameSize(NSSize(width: 820, height: 850))
        container.layoutSubtreeIfNeeded()
        webView.layoutSubtreeIfNeeded()

        XCTAssertEqual(container.bounds.size, NSSize(width: 820, height: 850))
        XCTAssertEqual(webView.frame.width, 1280, accuracy: 0.001)
        XCTAssertEqual(webView.frame.height, 850.0 * 1280.0 / 820.0, accuracy: 0.001)
        XCTAssertEqual(webView.bounds.size, webView.frame.size)
        XCTAssertEqual(container.websiteLayoutScale, 820.0 / 1280.0, accuracy: 0.001)
        XCTAssertEqual(webView.pageZoom, 1, accuracy: 0.001)
    }''')
web_tests = replace_test(web_tests, "testDesktopModeExposesDesktopClassCSSWidthInsideNarrowWindow", '''    func testSmallDesktopModeUsesCompactResponsiveCSSClass() {
        let rendering = WebRenderingProfile.canonicalDefault.settingSimplePreset(.small)
        let webView = WebViewFactory.makeWebView(renderingProfile: rendering)
        let container = host(webView, visibleSize: NSSize(width: 420, height: 760))
        loadTestHTML(in: webView)

        let cssWidth = evaluateNumber("document.body.clientWidth", in: webView)
        let reaches700 = evaluateNumber(
            "matchMedia('(min-width: 700px)').matches ? 1 : 0",
            in: webView
        )
        let reaches768 = evaluateNumber(
            "matchMedia('(min-width: 768px)').matches ? 1 : 0",
            in: webView
        )

        XCTAssertEqual(container.bounds.width, 420, accuracy: 0.001)
        XCTAssertEqual(webView.frame.width, 720, accuracy: 0.001)
        XCTAssertEqual(webView.pageZoom, 1, accuracy: 0.001)
        XCTAssertEqual(cssWidth, 720, accuracy: 3)
        XCTAssertEqual(reaches700, 1, accuracy: 0.001)
        XCTAssertEqual(reaches768, 0, accuracy: 0.001)
    }''')
web_tests = replace_test(web_tests, "testMobileModeRemainsNativeOneToOneAtWideWindowSize", '''    func testMobileModeRemainsNativeOneToOneAtWideWindowSize() {
        let rendering = WebRenderingProfile.canonicalDefault
            .settingWebsiteMode(.mobile)
            .settingSimplePreset(.wide)
        let webView = WebViewFactory.makeWebView(renderingProfile: rendering)
        let container = host(webView, visibleSize: NSSize(width: 1080, height: 850))
        let floatTabsWebView = tryUnwrapFloatTabsWebView(webView)
        loadTestHTML(in: webView)

        let cssWidth = evaluateNumber("document.body.clientWidth", in: webView)
        XCTAssertEqual(container.bounds.width, 1080, accuracy: 0.001)
        XCTAssertEqual(webView.frame.width, 1080, accuracy: 0.001)
        XCTAssertEqual(floatTabsWebView.websiteLayoutScale, 1, accuracy: 0.001)
        XCTAssertEqual(webView.pageZoom, 1, accuracy: 0.001)
        XCTAssertEqual(cssWidth, 1080, accuracy: 3)
    }''')
web_tests = replace_test(web_tests, "testDesktopHostMapsVisibleCenterIntoLogicalWebCoordinates", '''    func testDesktopHostMapsVisibleCenterIntoLogicalWebCoordinates() {
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = host(webView, visibleSize: NSSize(width: 600, height: 820))

        let webPoint = webView.convert(NSPoint(x: 300, y: 410), from: container)
        XCTAssertEqual(webPoint.x, webView.bounds.midX, accuracy: 0.5)
        XCTAssertEqual(webPoint.y, webView.bounds.midY, accuracy: 0.5)
    }''')
web_tests = replace_test(web_tests, "testHotHostsPreserveInactiveViewportAcrossDifferentSlotSizes", '''    func testHotHostsPreserveInactiveViewportAcrossDifferentSlotSizes() {
        _ = NSApplication.shared
        let container = WebPanelContainerView(
            frame: NSRect(x: 0, y: 0, width: 600, height: 820)
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
        XCTAssertEqual(first.frame.width, 1024, accuracy: 0.001)
        XCTAssertEqual(container.websiteLayoutScale, 600.0 / 1024.0, accuracy: 0.001)
        XCTAssertTrue(first.window === window)

        container.deactivate(slotID: firstID, residencyPolicy: .hot)
        XCTAssertTrue(first.superview?.isHidden == true)
        container.setFrameSize(NSSize(width: 1080, height: 850))
        container.layoutSubtreeIfNeeded()

        XCTAssertEqual(first.frame.size, firstSize)
        XCTAssertTrue(first.window === window)

        container.show(webView: second, slotID: secondID, residencyPolicy: .hot)
        container.layoutSubtreeIfNeeded()
        XCTAssertEqual(second.frame.width, 1440, accuracy: 0.001)
        XCTAssertEqual(container.websiteLayoutScale, 1080.0 / 1440.0, accuracy: 0.001)
        XCTAssertEqual(first.frame.size, firstSize)
        XCTAssertTrue(first.window === window)
        XCTAssertTrue(second.window === window)
        XCTAssertTrue(first.superview?.isHidden == true)

        container.show(webView: first, slotID: firstID, residencyPolicy: .hot)
        container.layoutSubtreeIfNeeded()
        XCTAssertFalse(first.superview?.isHidden ?? true)
        XCTAssertTrue(container.currentWebView === first)
        XCTAssertEqual(first.frame.width, 1440, accuracy: 0.001)
        XCTAssertEqual(container.websiteLayoutScale, 1080.0 / 1440.0, accuracy: 0.001)
        XCTAssertTrue(first.window === window)
    }''')
web_tests = replace_test(web_tests, "testDesktopLogicalHostKeepsNativeWindowClickHitTestingWorking", '''    func testDesktopLogicalHostKeepsNativeWindowClickHitTestingWorking() {
        _ = NSApplication.shared
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = WebPanelContainerView(
            frame: NSRect(x: 0, y: 0, width: 600, height: 820)
        )
        container.show(webView: webView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 820),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = container
        window.orderFront(nil)
        container.layoutSubtreeIfNeeded()
        webView.layoutSubtreeIfNeeded()

        loadInteractiveTestHTML(in: webView)
        XCTAssertEqual(webView.frame.width, 1024, accuracy: 0.001)
        XCTAssertEqual(webView.pageZoom, 1, accuracy: 0.001)
        clickWindow(at: NSPoint(x: 300, y: 410), in: window)
        waitForJavaScriptNumber("window.clicks", in: webView, equals: 1)
        window.orderOut(nil)
    }''')
web_tests = replace_test(web_tests, "testUserZoomStaysIndependentFromDesktopHostLayoutFit", '''    func testUserZoomStaysIndependentFromDesktopHostLayoutFit() {
        let desktopRendering = WebRenderingProfile.canonicalDefault.settingZoom(1.25)
        let desktopWebView = WebViewFactory.makeWebView(renderingProfile: desktopRendering)
        let desktopContainer = host(desktopWebView, visibleSize: NSSize(width: 600, height: 820))
        let desktopFloatWebView = tryUnwrapFloatTabsWebView(desktopWebView)

        XCTAssertEqual(desktopFloatWebView.userPageZoom, 1.25, accuracy: 0.001)
        XCTAssertEqual(desktopFloatWebView.websiteLayoutScale, 1, accuracy: 0.001)
        XCTAssertEqual(desktopContainer.websiteLayoutScale, 600.0 / 1024.0, accuracy: 0.001)
        XCTAssertEqual(desktopWebView.frame.width, 1024, accuracy: 0.001)
        XCTAssertEqual(desktopWebView.pageZoom, 1.25, accuracy: 0.001)
        XCTAssertEqual(desktopWebView.magnification, 1, accuracy: 0.001)

        let mobileRendering = desktopRendering
            .settingWebsiteMode(.mobile)
            .settingSimplePreset(.wide)
        let mobileWebView = WebViewFactory.makeWebView(renderingProfile: mobileRendering)
        let mobileContainer = host(mobileWebView, visibleSize: NSSize(width: 1080, height: 850))
        let mobileFloatWebView = tryUnwrapFloatTabsWebView(mobileWebView)

        XCTAssertEqual(mobileFloatWebView.userPageZoom, 1.25, accuracy: 0.001)
        XCTAssertEqual(mobileFloatWebView.websiteLayoutScale, 1, accuracy: 0.001)
        XCTAssertEqual(mobileContainer.websiteLayoutScale, 1, accuracy: 0.001)
        XCTAssertEqual(mobileWebView.frame.width, 1080, accuracy: 0.001)
        XCTAssertEqual(mobileWebView.pageZoom, 1.25, accuracy: 0.001)
        XCTAssertEqual(mobileWebView.magnification, 1, accuracy: 0.001)
    }''')
web_tests_path.write_text(web_tests)
