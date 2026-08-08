import AppKit
import WebKit
import XCTest
@testable import FloatTabs

@MainActor
final class WebViewFactoryTests: XCTestCase {
    private let versions = BrowserVersionCatalog(
        safari: "26.6",
        webKit: "619.3.7",
        chrome: "150.0.7871.187",
        edge: "150.0.4078.99"
    )

    func testStageZeroWebViewUsesPersistentWebsiteDataStore() {
        let webView = WebViewFactory.makeStageZeroWebView()
        XCTAssertTrue(webView.configuration.websiteDataStore.isPersistent)
        XCTAssertTrue(webView.configuration.preferences.isElementFullscreenEnabled)
    }

    func testRenderingProfileAppliesMobileIdentityContentModeAndZoom() {
        let rendering = WebRenderingProfile.canonicalDefault
            .settingWebsiteMode(.mobile)
            .settingZoom(1.25)
        let webView = WebViewFactory.makeWebView(renderingProfile: rendering)

        XCTAssertTrue(webView.configuration.websiteDataStore.isPersistent)
        XCTAssertEqual(webView.configuration.defaultWebpagePreferences.preferredContentMode, .mobile)
        XCTAssertTrue(webView.customUserAgent?.contains("iPhone") == true)
        XCTAssertTrue(webView.customUserAgent?.contains("Version/") == true)
        XCTAssertEqual(webView.pageZoom, 1.25, accuracy: 0.001)
    }

    func testWebsiteLayoutViewportSeparatesDesktopAndMobileCSSWidths() {
        let narrowDesktop = WebsiteLayoutViewport.logicalSize(
            forVisibleSize: CGSize(width: 430, height: 820),
            websiteMode: .desktop
        )
        XCTAssertEqual(narrowDesktop.width, 1280, accuracy: 0.001)
        XCTAssertEqual(narrowDesktop.height, 820.0 * 1280.0 / 430.0, accuracy: 0.001)

        let wideDesktop = WebsiteLayoutViewport.logicalSize(
            forVisibleSize: CGSize(width: 1400, height: 850),
            websiteMode: .desktop
        )
        XCTAssertEqual(wideDesktop, CGSize(width: 1400, height: 850))

        let wideMobile = WebsiteLayoutViewport.logicalSize(
            forVisibleSize: CGSize(width: 900, height: 850),
            websiteMode: .mobile
        )
        XCTAssertEqual(wideMobile.width, 390, accuracy: 0.001)
        XCTAssertEqual(wideMobile.height, 850.0 * 390.0 / 900.0, accuracy: 0.001)

        let narrowMobile = WebsiteLayoutViewport.logicalSize(
            forVisibleSize: CGSize(width: 320, height: 400),
            websiteMode: .mobile
        )
        XCTAssertEqual(narrowMobile, CGSize(width: 320, height: 400))
    }

    func testDesktopHostKeepsVisibleSurfaceAndGivesWebKitRealLogicalFrame() {
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = host(webView, visibleSize: NSSize(width: 430, height: 820))

        XCTAssertEqual(container.bounds.size, NSSize(width: 430, height: 820))
        XCTAssertEqual(webView.frame.width, 1280, accuracy: 0.001)
        XCTAssertEqual(webView.frame.height, 820.0 * 1280.0 / 430.0, accuracy: 0.001)
        XCTAssertEqual(webView.bounds.size, webView.frame.size)
        XCTAssertEqual(container.websiteLayoutScale, 430.0 / 1280.0, accuracy: 0.001)
    }

    func testLogicalWebViewFrameAndFitScaleTrackVisibleResize() {
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
    }

    func testDesktopModeChangesActualCSSLayoutWidthWhileVisibleSurfaceStaysNarrow() {
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = host(webView, visibleSize: NSSize(width: 430, height: 820))

        loadTestHTML(in: webView)
        let cssWidth = evaluateNumber("document.body.clientWidth", in: webView)

        XCTAssertEqual(container.bounds.width, 430, accuracy: 0.001)
        XCTAssertEqual(webView.frame.width, 1280, accuracy: 0.001)
        XCTAssertEqual(cssWidth, 1280, accuracy: 2)
    }

    func testMobileModeChangesActualCSSLayoutWidthWhileVisibleSurfaceStaysWide() {
        let rendering = WebRenderingProfile.canonicalDefault
            .settingWebsiteMode(.mobile)
            .settingSimplePreset(.wide)
        let webView = WebViewFactory.makeWebView(renderingProfile: rendering)
        let container = host(webView, visibleSize: NSSize(width: 900, height: 850))

        loadTestHTML(in: webView)
        let cssWidth = evaluateNumber("document.body.clientWidth", in: webView)

        XCTAssertEqual(container.bounds.width, 900, accuracy: 0.001)
        XCTAssertEqual(webView.frame.width, 390, accuracy: 0.001)
        XCTAssertEqual(container.websiteLayoutScale, 900.0 / 390.0, accuracy: 0.001)
        XCTAssertEqual(cssWidth, 390, accuracy: 2)
    }

    func testLogicalHostMapsVisibleCoordinatesIntoLogicalWebCoordinates() {
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = host(webView, visibleSize: NSSize(width: 430, height: 820))

        let logicalPoint = webView.convert(NSPoint(x: 215, y: 410), from: container)
        XCTAssertEqual(logicalPoint.x, 640, accuracy: 2)
    }

    func testWebsiteLayoutFittingDoesNotOverwriteUserPageZoom() {
        let desktopRendering = WebRenderingProfile.canonicalDefault.settingZoom(1.25)
        let desktopWebView = WebViewFactory.makeWebView(renderingProfile: desktopRendering)
        let desktopContainer = host(
            desktopWebView,
            visibleSize: NSSize(width: 430, height: 820)
        )

        XCTAssertEqual(desktopContainer.websiteLayoutScale, 430.0 / 1280.0, accuracy: 0.001)
        XCTAssertEqual(desktopWebView.pageZoom, 1.25, accuracy: 0.001)

        let mobileRendering = desktopRendering.settingWebsiteMode(.mobile)
        let mobileWebView = WebViewFactory.makeWebView(renderingProfile: mobileRendering)
        let mobileContainer = host(
            mobileWebView,
            visibleSize: NSSize(width: 900, height: 850)
        )

        XCTAssertEqual(mobileContainer.websiteLayoutScale, 900.0 / 390.0, accuracy: 0.001)
        XCTAssertEqual(mobileWebView.pageZoom, 1.25, accuracy: 0.001)
    }

    func testMacOSSafariRuntimeUsesNativeWebKitUAWithSafariSuffix() {
        let rendering = WebRenderingProfile.canonicalDefault
            .settingBrowserIdentity(.macosSafari)

        XCTAssertNil(
            UserAgentProvider.customUserAgent(
                for: rendering,
                versions: versions
            )
        )

        let webView = WebViewFactory.makeWebView(renderingProfile: rendering)
        XCTAssertTrue(
            webView.configuration.applicationNameForUserAgent?.contains("Version/") == true
        )
        XCTAssertTrue(
            webView.configuration.applicationNameForUserAgent?.contains("Safari/") == true
        )

        loadTestHTML(in: webView)
        let hasSafariRuntimeIdentity = evaluateNumber(
            "navigator.userAgent.includes('Version/') && navigator.userAgent.includes('Safari/') ? 1 : 0",
            in: webView
        )
        XCTAssertEqual(hasSafariRuntimeIdentity, 1, accuracy: 0.001)
    }

    func testSafariCompatibilityIdentityUsesResolvedWebKitVersion() {
        let ua = UserAgentProvider.userAgent(
            for: .macosSafari,
            websiteMode: .desktop,
            versions: versions
        )
        XCTAssertTrue(ua.contains("Macintosh"))
        XCTAssertTrue(ua.contains("AppleWebKit/619.3.7"))
        XCTAssertTrue(ua.contains("Version/26.6"))
        XCTAssertTrue(ua.contains("Safari/619.3.7"))
        XCTAssertEqual(
            UserAgentProvider.safariApplicationName(versions: versions),
            "Version/26.6 Safari/619.3.7"
        )
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
        XCTAssertTrue(iPhoneChrome.contains("AppleWebKit/619.3.7"))
        XCTAssertTrue(iPhoneChrome.contains("CriOS/150.0.7871.187"))

        let android = UserAgentProvider.userAgent(
            for: .androidChrome,
            websiteMode: .mobile,
            versions: versions
        )
        XCTAssertTrue(android.contains("Android 16"))
        XCTAssertTrue(android.contains("Mobile Safari"))
    }

    func testAutomaticIdentityFollowsWebsiteModeWithoutChangingWindowSizePolicy() {
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

    private func host(
        _ webView: WKWebView,
        visibleSize: NSSize
    ) -> WebPanelContainerView {
        let container = WebPanelContainerView(
            frame: NSRect(origin: .zero, size: visibleSize)
        )
        container.show(webView: webView)
        container.layoutSubtreeIfNeeded()
        webView.layoutSubtreeIfNeeded()
        return container
    }

    private func loadTestHTML(in webView: WKWebView) {
        let expectation = expectation(description: "WKWebView test page loaded")
        let waiter = NavigationWaiter {
            expectation.fulfill()
        }
        webView.navigationDelegate = waiter
        webView.loadHTMLString(
            """
            <!doctype html>
            <html>
              <head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
              <body style="margin:0">FloatTabs layout test</body>
            </html>
            """,
            baseURL: nil
        )
        wait(for: [expectation], timeout: 5)
        withExtendedLifetime(waiter) {}
    }

    private func evaluateNumber(_ script: String, in webView: WKWebView) -> Double {
        let expectation = expectation(description: "JavaScript value evaluated")
        var number: Double?
        var evaluationError: Error?

        webView.evaluateJavaScript(script) { value, error in
            evaluationError = error
            number = (value as? NSNumber)?.doubleValue
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5)
        XCTAssertNil(evaluationError)
        guard let number else {
            XCTFail("Expected numeric JavaScript result")
            return .nan
        }
        return number
    }
}

@MainActor
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish()
    }
}
