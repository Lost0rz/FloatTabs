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
    }

    func testRenderingProfileAppliesMobileIdentityAndZoom() {
        let rendering = WebRenderingProfile.canonicalDefault
            .settingWebsiteMode(.mobile)
            .settingZoom(1.25)
        let webView = WebViewFactory.makeWebView(renderingProfile: rendering)

        XCTAssertTrue(webView.configuration.websiteDataStore.isPersistent)
        XCTAssertTrue(webView.customUserAgent?.contains("iPhone") == true)
        XCTAssertTrue(webView.customUserAgent?.contains("Version/") == true)
        XCTAssertEqual(webView.pageZoom, 1.25, accuracy: 0.001)
    }

    func testWebsiteLayoutPolicySeparatesDesktopAndMobileCSSWidths() {
        XCTAssertEqual(
            WebsiteLayoutPolicy.logicalWidth(
                forVisibleWidth: 430,
                websiteMode: .desktop
            ),
            980,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WebsiteLayoutPolicy.viewScale(
                forVisibleWidth: 430,
                websiteMode: .desktop
            ),
            430.0 / 980.0,
            accuracy: 0.001
        )

        XCTAssertEqual(
            WebsiteLayoutPolicy.logicalWidth(
                forVisibleWidth: 900,
                websiteMode: .mobile
            ),
            390,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WebsiteLayoutPolicy.viewScale(
                forVisibleWidth: 900,
                websiteMode: .mobile
            ),
            900.0 / 390.0,
            accuracy: 0.001
        )

        XCTAssertEqual(
            WebsiteLayoutPolicy.viewScale(
                forVisibleWidth: 1200,
                websiteMode: .desktop
            ),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WebsiteLayoutPolicy.viewScale(
                forVisibleWidth: 320,
                websiteMode: .mobile
            ),
            1,
            accuracy: 0.001
        )
    }

    func testDesktopKeepsPhysicalWebViewPinnedToVisibleWindowSize() {
        let host = makeLayoutHost(size: NSSize(width: 430, height: 820))
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        pin(webView: webView, to: host)
        host.layoutSubtreeIfNeeded()
        webView.layoutSubtreeIfNeeded()

        XCTAssertEqual(host.bounds.size, host.frame.size)
        XCTAssertEqual(webView.frame.size, NSSize(width: 430, height: 820))
        XCTAssertEqual(webView.bounds.size, webView.frame.size)
        XCTAssertEqual(
            (webView as? FloatTabsWebView)?.requestedWebsiteLayoutScale,
            430.0 / 980.0,
            accuracy: 0.001
        )
        XCTAssertTrue((webView as? FloatTabsWebView)?.websiteLayoutSPIAvailable == true)
    }

    func testPhysicalWebViewFrameTracksWindowResizeWithoutBlackRemainder() {
        let host = makeLayoutHost(size: NSSize(width: 430, height: 820))
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        pin(webView: webView, to: host)
        host.layoutSubtreeIfNeeded()

        host.setFrameSize(NSSize(width: 900, height: 850))
        host.layoutSubtreeIfNeeded()
        webView.layoutSubtreeIfNeeded()

        XCTAssertEqual(host.bounds.size, NSSize(width: 900, height: 850))
        XCTAssertEqual(webView.frame.size, NSSize(width: 900, height: 850))
        XCTAssertEqual(webView.bounds.size, webView.frame.size)
        XCTAssertEqual(
            (webView as? FloatTabsWebView)?.requestedWebsiteLayoutScale,
            900.0 / 980.0,
            accuracy: 0.001
        )
    }

    func testDesktopModeChangesActualCSSLayoutWidthWithoutChangingPhysicalFrame() {
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        webView.setFrameSize(NSSize(width: 430, height: 820))

        guard let floatTabsWebView = webView as? FloatTabsWebView else {
            return XCTFail("Expected FloatTabsWebView")
        }
        XCTAssertTrue(floatTabsWebView.websiteLayoutSPIAvailable)

        loadTestHTML(in: webView)
        let cssWidth = evaluateNumber("document.body.clientWidth", in: webView)

        XCTAssertEqual(webView.frame.width, 430, accuracy: 0.001)
        XCTAssertEqual(webView.bounds.width, 430, accuracy: 0.001)
        XCTAssertEqual(cssWidth, 980, accuracy: 2)
    }

    func testMobileModeChangesActualCSSLayoutWidthWithoutChangingPhysicalFrame() {
        let rendering = WebRenderingProfile.canonicalDefault
            .settingWebsiteMode(.mobile)
            .settingSimplePreset(.wide)
        let webView = WebViewFactory.makeWebView(renderingProfile: rendering)
        webView.setFrameSize(NSSize(width: 900, height: 850))

        guard let floatTabsWebView = webView as? FloatTabsWebView else {
            return XCTFail("Expected FloatTabsWebView")
        }
        XCTAssertTrue(floatTabsWebView.websiteLayoutSPIAvailable)

        loadTestHTML(in: webView)
        let cssWidth = evaluateNumber("document.body.clientWidth", in: webView)

        XCTAssertEqual(webView.frame.width, 900, accuracy: 0.001)
        XCTAssertEqual(webView.bounds.width, 900, accuracy: 0.001)
        XCTAssertEqual(cssWidth, 390, accuracy: 2)
    }

    func testMacOSSafariRuntimeUsesNativeWebKitUAWithSafariSuffix() {
        let rendering = WebRenderingProfile.canonicalDefault
            .settingBrowserIdentity(.macosSafari)
        let webView = WebViewFactory.makeWebView(renderingProfile: rendering)

        XCTAssertNil(webView.customUserAgent)
        XCTAssertTrue(
            webView.configuration.applicationNameForUserAgent?.contains("Version/") == true
        )
        XCTAssertTrue(
            webView.configuration.applicationNameForUserAgent?.contains("Safari/") == true
        )
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

    private func makeLayoutHost(size: NSSize) -> NSView {
        let host = NSView(frame: NSRect(origin: .zero, size: size))
        host.translatesAutoresizingMaskIntoConstraints = true
        return host
    }

    private func pin(webView: WKWebView, to host: NSView) {
        webView.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            webView.topAnchor.constraint(equalTo: host.topAnchor),
            webView.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
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
