import AppKit
import WebKit
import XCTest
@testable import FloatTabs

@MainActor
final class WebViewFactoryTests: XCTestCase {
    private let versions = BrowserVersionCatalog(
        safari: "26.6",
        chrome: "150.0.7871.187",
        edge: "150.0.4078.99"
    )

    func testStageZeroWebViewUsesPersistentWebsiteDataStore() {
        let webView = WebViewFactory.makeStageZeroWebView()
        XCTAssertTrue(webView.configuration.websiteDataStore.isPersistent)
    }

    func testRenderingProfileAppliesWebsiteModeFullUserAgentAndZoom() {
        let rendering = WebRenderingProfile.canonicalDefault
            .settingWebsiteMode(.mobile)
            .settingZoom(1.25)
        let webView = WebViewFactory.makeWebView(renderingProfile: rendering)

        XCTAssertTrue(webView.configuration.websiteDataStore.isPersistent)
        XCTAssertEqual(
            webView.configuration.defaultWebpagePreferences.preferredContentMode,
            .mobile
        )
        XCTAssertTrue(webView.customUserAgent?.contains("iPhone") == true)
        XCTAssertTrue(webView.customUserAgent?.contains("Version/") == true)
        XCTAssertEqual(webView.pageZoom, 1.25, accuracy: 0.001)
    }

    func testWebsiteLayoutViewportSeparatesModeFromVisibleWindowSize() {
        let narrowWindow = CGSize(width: 430, height: 820)
        let desktopLayout = WebsiteLayoutViewport.logicalSize(
            forVisibleSize: narrowWindow,
            websiteMode: .desktop
        )
        XCTAssertEqual(desktopLayout.width, 1280, accuracy: 0.001)
        XCTAssertEqual(
            desktopLayout.width / desktopLayout.height,
            narrowWindow.width / narrowWindow.height,
            accuracy: 0.001
        )

        let wideWindow = CGSize(width: 900, height: 850)
        let mobileLayout = WebsiteLayoutViewport.logicalSize(
            forVisibleSize: wideWindow,
            websiteMode: .mobile
        )
        XCTAssertEqual(mobileLayout.width, 390, accuracy: 0.001)
        XCTAssertEqual(
            mobileLayout.width / mobileLayout.height,
            wideWindow.width / wideWindow.height,
            accuracy: 0.001
        )

        let veryWideDesktop = WebsiteLayoutViewport.logicalSize(
            forVisibleSize: CGSize(width: 1600, height: 900),
            websiteMode: .desktop
        )
        XCTAssertEqual(veryWideDesktop.width, 1600, accuracy: 0.001)

        let veryNarrowMobile = WebsiteLayoutViewport.logicalSize(
            forVisibleSize: CGSize(width: 320, height: 700),
            websiteMode: .mobile
        )
        XCTAssertEqual(veryNarrowMobile.width, 320, accuracy: 0.001)
    }

    func testFloatTabsWebViewKeepsVisibleFrameButUsesIndependentWebsiteBoundsAndZoom() {
        let desktop = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        desktop.setFrameSize(NSSize(width: 430, height: 820))

        XCTAssertEqual(desktop.frame.size.width, 430, accuracy: 0.001)
        XCTAssertEqual(desktop.frame.size.height, 820, accuracy: 0.001)
        XCTAssertEqual(desktop.bounds.width, 1280, accuracy: 0.001)
        XCTAssertGreaterThan(desktop.bounds.height, desktop.frame.height)
        XCTAssertEqual(desktop.pageZoom, 1.0, accuracy: 0.001)

        let mobileRendering = WebRenderingProfile.canonicalDefault
            .settingWebsiteMode(.mobile)
            .settingSimplePreset(.wide)
            .settingZoom(1.25)
        let mobile = WebViewFactory.makeWebView(renderingProfile: mobileRendering)
        mobile.setFrameSize(NSSize(width: 900, height: 850))

        XCTAssertEqual(mobile.frame.size.width, 900, accuracy: 0.001)
        XCTAssertEqual(mobile.frame.size.height, 850, accuracy: 0.001)
        XCTAssertEqual(mobile.bounds.width, 390, accuracy: 0.001)
        XCTAssertLessThan(mobile.bounds.height, mobile.frame.height)
        XCTAssertEqual(mobile.pageZoom, 1.25, accuracy: 0.001)
    }

    func testSafariCompatibilityIdentityIsCompleteInsteadOfNativeWKWebViewUA() {
        let ua = UserAgentProvider.userAgent(
            for: .macosSafari,
            websiteMode: .desktop,
            versions: versions
        )
        XCTAssertTrue(ua.contains("Macintosh"))
        XCTAssertTrue(ua.contains("Version/26.6"))
        XCTAssertTrue(ua.contains("Safari/605.1.15"))
    }

    func testExactDesktopAndMobileIdentityPresetsAreCentralized() {
        let macChrome = UserAgentProvider.userAgent(
            for: .macosChrome,
            websiteMode: .desktop,
            versions: versions
        )
        XCTAssertTrue(macChrome.contains("Macintosh"))
        XCTAssertTrue(macChrome.contains("Chrome/150.0.7871.187"))

        let windowsChrome = UserAgentProvider.userAgent(
            for: .windowsChrome,
            websiteMode: .desktop,
            versions: versions
        )
        XCTAssertTrue(windowsChrome.contains("Windows NT 10.0"))
        XCTAssertTrue(windowsChrome.contains("Chrome/150.0.7871.187"))

        let linuxChrome = UserAgentProvider.userAgent(
            for: .linuxChrome,
            websiteMode: .desktop,
            versions: versions
        )
        XCTAssertTrue(linuxChrome.contains("Linux x86_64"))

        let edge = UserAgentProvider.userAgent(
            for: .windowsEdge,
            websiteMode: .desktop,
            versions: versions
        )
        XCTAssertTrue(edge.contains("Windows NT 10.0"))
        XCTAssertTrue(edge.contains("Chrome/150.0.7871.187"))
        XCTAssertTrue(edge.contains("Edg/150.0.4078.99"))

        let iPhoneChrome = UserAgentProvider.userAgent(
            for: .iphoneChrome,
            websiteMode: .mobile,
            versions: versions
        )
        XCTAssertTrue(iPhoneChrome.contains("iPhone"))
        XCTAssertTrue(iPhoneChrome.contains("CriOS/150.0.7871.187"))

        let android = UserAgentProvider.userAgent(
            for: .androidChrome,
            websiteMode: .mobile,
            versions: versions
        )
        XCTAssertTrue(android.contains("Android 16"))
        XCTAssertTrue(android.contains("Mobile Safari"))
    }

    func testAutomaticIdentityFollowsWebsiteModeWithoutChangingViewport() {
        let desktopUA = UserAgentProvider.userAgent(
            for: .automatic,
            websiteMode: .desktop,
            versions: versions
        )
        let mobileUA = UserAgentProvider.userAgent(
            for: .automatic,
            websiteMode: .mobile,
            versions: versions
        )
        XCTAssertTrue(desktopUA.contains("Macintosh"))
        XCTAssertTrue(desktopUA.contains("Version/26.6"))
        XCTAssertTrue(mobileUA.contains("iPhone"))
        XCTAssertTrue(mobileUA.contains("Version/26.6"))
    }

    func testCustomUserAgentPassesThroughExactly() {
        let custom = "FloatTabs-Test-UA/1.0"
        XCTAssertEqual(
            UserAgentProvider.userAgent(
                for: .custom,
                websiteMode: .desktop,
                customUserAgent: custom,
                versions: versions
            ),
            custom
        )
    }

    func testBrowserVersionNormalizationAvoidsStalePartialVersionStrings() {
        XCTAssertEqual(BrowserVersionResolver.normalizedSafariVersion("26.6.1"), "26.6")
        XCTAssertEqual(
            BrowserVersionResolver.normalizedChromiumVersion("150.0.7871.187"),
            "150.0.7871.187"
        )
        XCTAssertEqual(BrowserVersionResolver.normalizedChromiumVersion("150"), "150.0.0.0")
    }

    func testWebsiteModeMappingIsExplicit() {
        XCTAssertEqual(WebViewFactory.preferredContentMode(for: .desktop), .desktop)
        XCTAssertEqual(WebViewFactory.preferredContentMode(for: .mobile), .mobile)
    }

    func testNavigationWebsiteModeCanMoveMobileDesktopAndBack() {
        let preferences = WKWebpagePreferences()

        SlotNavigationObserver.applyWebsiteMode(.mobile, to: preferences)
        XCTAssertEqual(preferences.preferredContentMode, .mobile)

        SlotNavigationObserver.applyWebsiteMode(.desktop, to: preferences)
        XCTAssertEqual(preferences.preferredContentMode, .desktop)

        SlotNavigationObserver.applyWebsiteMode(.mobile, to: preferences)
        XCTAssertEqual(preferences.preferredContentMode, .mobile)
    }

    func testNavigationFinishRestoresHiddenScrollerPolicyAfterWebKitReenablesIt() {
        let webView = WebViewFactory.makeWebView()
        let simulatedWebKitScrollView = NSScrollView(
            frame: NSRect(x: 0, y: 0, width: 300, height: 500)
        )
        simulatedWebKitScrollView.scrollerStyle = .legacy
        simulatedWebKitScrollView.autohidesScrollers = false
        simulatedWebKitScrollView.hasVerticalScroller = true
        simulatedWebKitScrollView.hasHorizontalScroller = true
        webView.addSubview(simulatedWebKitScrollView)

        let observer = SlotNavigationObserver(
            slotID: UUID(),
            webView: webView,
            websiteMode: .desktop,
            onURLChange: { _, _ in }
        )
        observer.webView(webView, didFinish: nil)

        XCTAssertEqual(simulatedWebKitScrollView.scrollerStyle, .overlay)
        XCTAssertTrue(simulatedWebKitScrollView.autohidesScrollers)
        XCTAssertFalse(simulatedWebKitScrollView.hasVerticalScroller)
        XCTAssertFalse(simulatedWebKitScrollView.hasHorizontalScroller)
    }

    func testConfiguredScrollerIsCompletelyHiddenAtRest() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 500))
        scrollView.scrollerStyle = .legacy
        scrollView.autohidesScrollers = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true

        WebViewFactory.configureHiddenScrollerStyle(scrollView)

        XCTAssertEqual(scrollView.scrollerStyle, .overlay)
        XCTAssertTrue(scrollView.autohidesScrollers)
        XCTAssertFalse(scrollView.hasVerticalScroller)
        XCTAssertFalse(scrollView.hasHorizontalScroller)
    }

    func testScrollerVisibilityCanBeEnabledOnlyForActiveAxis() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 500))
        WebViewFactory.configureHiddenScrollerStyle(scrollView)

        WebViewFactory.setScrollerVisibility(
            scrollView,
            vertical: true,
            horizontal: false
        )

        XCTAssertEqual(scrollView.scrollerStyle, .overlay)
        XCTAssertTrue(scrollView.autohidesScrollers)
        XCTAssertTrue(scrollView.hasVerticalScroller)
        XCTAssertFalse(scrollView.hasHorizontalScroller)

        WebViewFactory.configureHiddenScrollerStyle(scrollView)
        XCTAssertFalse(scrollView.hasVerticalScroller)
        XCTAssertFalse(scrollView.hasHorizontalScroller)
    }
}
