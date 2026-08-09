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

    func testAutomaticMobileUsesCurrentIPhoneSafariIdentity() {
        let rendering = WebRenderingProfile.canonicalDefault
            .settingWebsiteMode(.mobile)
            .settingZoom(1.25)
        let webView = WebViewFactory.makeWebView(renderingProfile: rendering)
        let floatTabsWebView = tryUnwrapFloatTabsWebView(webView)

        XCTAssertTrue(webView.configuration.websiteDataStore.isPersistent)
        XCTAssertEqual(webView.configuration.defaultWebpagePreferences.preferredContentMode, .mobile)
        XCTAssertTrue(webView.customUserAgent?.contains("iPhone") == true)
        XCTAssertTrue(webView.customUserAgent?.contains("Version/26.") == true)
        XCTAssertTrue(
            webView.configuration.applicationNameForUserAgent?.contains("Version/") == true
        )
        XCTAssertTrue(
            webView.configuration.applicationNameForUserAgent?.contains("Safari/") == true
        )

        loadTestHTML(in: webView)
        let hasMobileRuntimeIdentity = evaluateNumber(
            "navigator.userAgent.includes('iPhone') ? 1 : 0",
            in: webView
        )
        XCTAssertEqual(hasMobileRuntimeIdentity, 1, accuracy: 0.001)
        XCTAssertEqual(floatTabsWebView.userPageZoom, 1.25, accuracy: 0.001)
        XCTAssertEqual(webView.pageZoom, 1.25, accuracy: 0.001)
    }

    func testWebsiteLayoutViewportSeparatesTargetCSSWidthFromVisibleWindowSize() {
        XCTAssertEqual(
            WebsiteLayoutViewport.targetCSSWidth(
                forVisibleWidth: 430,
                websiteMode: .desktop
            ),
            1280,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WebsiteLayoutViewport.fittingScale(
                forVisibleWidth: 430,
                websiteMode: .desktop
            ),
            430.0 / 1280.0,
            accuracy: 0.001
        )

        XCTAssertEqual(
            WebsiteLayoutViewport.targetCSSWidth(
                forVisibleWidth: 1400,
                websiteMode: .desktop
            ),
            1400,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WebsiteLayoutViewport.targetCSSWidth(
                forVisibleWidth: 900,
                websiteMode: .mobile
            ),
            390,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WebsiteLayoutViewport.fittingScale(
                forVisibleWidth: 900,
                websiteMode: .mobile
            ),
            900.0 / 390.0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WebsiteLayoutViewport.targetCSSWidth(
                forVisibleWidth: 320,
                websiteMode: .mobile
            ),
            320,
            accuracy: 0.001
        )

        let physical = CGSize(width: 430, height: 820)
        XCTAssertEqual(
            WebsiteLayoutViewport.logicalSize(
                forVisibleSize: physical,
                websiteMode: .desktop
            ),
            physical
        )
    }

    func testDesktopHostKeepsWebViewOneToOneWithVisibleSurface() {
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
    }

    func testVisibleResizeRecomputesPublicWebKitFitWithoutChangingPhysicalGeometry() {
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
        XCTAssertEqual(floatTabsWebView.websiteLayoutScale, 900.0 / 1280.0, accuracy: 0.001)
        XCTAssertEqual(webView.pageZoom, 900.0 / 1280.0, accuracy: 0.001)
    }

    func testDesktopModeChangesActualCSSLayoutWidthWhileVisibleSurfaceStaysNarrow() {
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
        XCTAssertEqual(cssWidth, 1280, accuracy: 2)
        XCTAssertEqual(innerWidth, 1280, accuracy: 2)
        XCTAssertEqual(desktopMediaQuery, 1, accuracy: 0.001)
    }

    func testMobileModeChangesActualCSSLayoutWidthWhileVisibleSurfaceStaysWide() {
        let rendering = WebRenderingProfile.canonicalDefault
            .settingWebsiteMode(.mobile)
            .settingSimplePreset(.wide)
        let webView = WebViewFactory.makeWebView(renderingProfile: rendering)
        let container = host(webView, visibleSize: NSSize(width: 900, height: 850))
        let floatTabsWebView = tryUnwrapFloatTabsWebView(webView)

        loadTestHTML(in: webView)
        let cssWidth = evaluateNumber("document.body.clientWidth", in: webView)
        let innerWidth = evaluateNumber("window.innerWidth", in: webView)
        let desktopMediaQuery = evaluateNumber(
            "matchMedia('(min-width: 1000px)').matches ? 1 : 0",
            in: webView
        )

        XCTAssertEqual(container.bounds.width, 900, accuracy: 0.001)
        XCTAssertEqual(webView.frame.width, 900, accuracy: 0.001)
        XCTAssertEqual(floatTabsWebView.websiteLayoutScale, 900.0 / 390.0, accuracy: 0.001)
        XCTAssertEqual(cssWidth, 390, accuracy: 2)
        XCTAssertEqual(innerWidth, 390, accuracy: 2)
        XCTAssertEqual(desktopMediaQuery, 0, accuracy: 0.001)
    }

    func testNativeWebCoordinatesRemainOneToOneWithVisibleCoordinates() {
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = host(webView, visibleSize: NSSize(width: 430, height: 820))

        let webPoint = webView.convert(NSPoint(x: 215, y: 410), from: container)
        XCTAssertEqual(webPoint.x, 215, accuracy: 0.5)
        XCTAssertEqual(webPoint.y, 410, accuracy: 0.5)
    }

    func testHotHostsPreserveInactiveViewportAcrossDifferentSlotSizes() {
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
        XCTAssertTrue(first.window === window)

        container.deactivate(slotID: firstID, residencyPolicy: .hot)
        container.setFrameSize(NSSize(width: 900, height: 850))
        container.layoutSubtreeIfNeeded()

        XCTAssertEqual(first.frame.size, firstSize)
        XCTAssertTrue(first.window === window)

        container.show(webView: second, slotID: secondID, residencyPolicy: .hot)
        container.layoutSubtreeIfNeeded()
        XCTAssertEqual(second.frame.size, NSSize(width: 900, height: 850))
        XCTAssertEqual(first.frame.size, firstSize)
        XCTAssertTrue(first.window === window)
        XCTAssertTrue(second.window === window)
    }

    func testDesktopPublicPageZoomKeepsNativeClickHitTestingWorking() {
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
        clickWebViewCenter(webView, in: window)

        // WKWebView forwards the synthesized mouse event to the WebContent
        // process asynchronously, so the DOM click handler fires a few run-loop
        // spins after `mouseDown`/`mouseUp` return. Poll for the side effect
        // instead of asserting immediately, which would race WebKit delivery.
        waitForJavaScriptNumber("window.clicks", in: webView, equals: 1)
        window.orderOut(nil)
    }

    /// Unit test for the production new-window policy decision
    /// (`SlotNavigationObserver.shouldOpenInCurrentSlot`). `target="_blank"` /
    /// `window.open` web navigations (targetFrame == nil, http/https) must route
    /// into the current slot; other schemes and nil URLs must not.
    func testNewWindowPolicyRoutesBlankWebLinksIntoCurrentSlot() {
        XCTAssertTrue(SlotNavigationObserver.shouldOpenInCurrentSlot(
            targetFrame: nil,
            url: URL(string: "https://www.bilibili.com/video/BV1234")
        ))
        XCTAssertTrue(SlotNavigationObserver.shouldOpenInCurrentSlot(
            targetFrame: nil,
            url: URL(string: "http://example.com")
        ))
        XCTAssertFalse(SlotNavigationObserver.shouldOpenInCurrentSlot(
            targetFrame: nil,
            url: URL(string: "about:blank")
        ))
        XCTAssertFalse(SlotNavigationObserver.shouldOpenInCurrentSlot(
            targetFrame: nil,
            url: URL(string: "mailto:a@b.com")
        ))
        XCTAssertFalse(SlotNavigationObserver.shouldOpenInCurrentSlot(
            targetFrame: nil,
            url: nil
        ))
    }

    /// End-to-end: a `target="_blank"` link must navigate within the current
    /// web view instead of being dropped. (Without a `WKUIDelegate`, WebKit
    /// discards such navigations and the click appears to do nothing — the
    /// real Bilibili desktop symptom.) Uses a test delegate that mirrors the
    /// production policy plus an offline custom scheme so it is CI-safe.
    func testBlankTargetLinksNavigateWithinCurrentSlot() {
        _ = NSApplication.shared
        let destination = URL(string: "x-ft-test://host/destination")!
        let delegate = NewWindowPolicyDelegate()
        let webView = makePolicyWebView(delegate: delegate)
        let window = hostDirect(webView)

        let loaded = expectation(description: "loaded")
        delegate.onFinish = { loaded.fulfill() }
        webView.loadHTMLString(offlineCenteredLinkHTML(href: destination.absoluteString, target: "_blank"), baseURL: nil)
        wait(for: [loaded], timeout: 5)
        clickWebViewCenter(webView, in: window)
        waitForURL(webView, toBecome: destination, timeout: 3)

        XCTAssertEqual(webView.url, destination)
        window.orderOut(nil)
    }

    /// Control: ordinary `_self` links must keep navigating normally (no
    /// regression for in-frame navigations from the `_blank` routing).
    func testSelfTargetLinksStillNavigateWithinCurrentSlot() {
        _ = NSApplication.shared
        let destination = URL(string: "x-ft-test://host/self-destination")!
        let delegate = NewWindowPolicyDelegate()
        let webView = makePolicyWebView(delegate: delegate)
        let window = hostDirect(webView)

        let loaded = expectation(description: "loaded")
        delegate.onFinish = { loaded.fulfill() }
        webView.loadHTMLString(offlineCenteredLinkHTML(href: destination.absoluteString, target: nil), baseURL: nil)
        wait(for: [loaded], timeout: 5)
        clickWebViewCenter(webView, in: window)
        waitForURL(webView, toBecome: destination, timeout: 3)

        XCTAssertEqual(webView.url, destination)
        window.orderOut(nil)
    }

    func testWebsiteFitComposesWithIndependentUserZoomState() {
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

        let mobileRendering = desktopRendering
            .settingWebsiteMode(.mobile)
            .settingSimplePreset(.wide)
        let mobileWebView = WebViewFactory.makeWebView(renderingProfile: mobileRendering)
        _ = host(mobileWebView, visibleSize: NSSize(width: 900, height: 850))
        let mobileFloatWebView = tryUnwrapFloatTabsWebView(mobileWebView)

        XCTAssertEqual(mobileFloatWebView.userPageZoom, 1.25, accuracy: 0.001)
        XCTAssertEqual(mobileFloatWebView.websiteLayoutScale, 900.0 / 390.0, accuracy: 0.001)
        XCTAssertEqual(
            mobileWebView.pageZoom,
            1.25 * 900.0 / 390.0,
            accuracy: 0.001
        )
    }

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
        XCTAssertEqual(floatTabsWebView.websiteLayoutScale, 900.0 / 390.0, accuracy: 0.001)
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

        let iPhoneSafari = UserAgentProvider.userAgent(
            for: .iphoneSafari,
            websiteMode: .mobile,
            versions: versions
        )
        XCTAssertTrue(iPhoneSafari.contains("iPhone"))
        XCTAssertTrue(iPhoneSafari.contains("Version/26.6"))

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

    func testAutomaticIdentityFollowsWebsiteModeWhenMaterialized() {
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
        XCTAssertNotEqual(mobileUA, desktopUA)
        XCTAssertTrue(desktopUA.contains("Macintosh"))
        XCTAssertTrue(desktopUA.contains("Version/26.6"))
        XCTAssertTrue(mobileUA.contains("iPhone"))
        XCTAssertFalse(mobileUA.contains("Macintosh"))
    }

    func testExplicitMacOSSafariCanOverrideMobileAutomaticIdentity() {
        let rendering = WebRenderingProfile.canonicalDefault
            .settingWebsiteMode(.mobile)
            .settingBrowserIdentity(.macosSafari)
        let ua = UserAgentProvider.customUserAgent(
            for: rendering,
            versions: versions
        )

        XCTAssertTrue(ua?.contains("Macintosh") == true)
        XCTAssertFalse(ua?.contains("iPhone") == true)
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

    func testWebViewInstallsPermanentContentScrollbarSuppression() {
        let webView = WebViewFactory.makeWebView()
        let script = webView.configuration.userContentController.userScripts.first {
            $0.source.contains("floattabs-hidden-scrollbar-style")
        }

        XCTAssertNotNil(script)
        XCTAssertEqual(script?.injectionTime, WKUserScriptInjectionTime.atDocumentStart)
        XCTAssertFalse(script?.isForMainFrameOnly ?? true)
        XCTAssertTrue(script?.source.contains("html::-webkit-scrollbar") == true)
        XCTAssertTrue(script?.source.contains("scrollbar-width: none") == true)
    }

    func testContentScrollbarSuppressionPreservesDocumentScrolling() {
        let webView = WebViewFactory.makeWebView()
        _ = host(webView, visibleSize: NSSize(width: 320, height: 400))
        loadTestHTML(in: webView)

        let styleInstalled = evaluateNumber(
            "document.getElementById('floattabs-hidden-scrollbar-style') ? 1 : 0",
            in: webView
        )
        let scrollY = evaluateNumber(
            "(() => { document.body.style.height = '2400px'; window.scrollTo(0, 200); return window.scrollY; })()",
            in: webView
        )

        XCTAssertEqual(styleInstalled, 1, accuracy: 0.001)
        XCTAssertGreaterThan(scrollY, 0)
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

    private func loadInteractiveTestHTML(in webView: WKWebView) {
        let expectation = expectation(description: "WKWebView interaction test page loaded")
        let waiter = NavigationWaiter {
            expectation.fulfill()
        }
        webView.navigationDelegate = waiter
        webView.loadHTMLString(
            """
            <!doctype html>
            <html>
              <head>
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <style>
                  html, body { margin:0; width:100%; height:100%; }
                  #target {
                    position:fixed;
                    left:50vw;
                    top:50vh;
                    width:120px;
                    height:80px;
                    transform:translate(-50%, -50%);
                  }
                </style>
              </head>
              <body>
                <button id="target">click</button>
                <script>
                  window.clicks = 0;
                  target.addEventListener('click', () => window.clicks++);
                </script>
              </body>
            </html>
            """,
            baseURL: nil
        )
        wait(for: [expectation], timeout: 5)
        withExtendedLifetime(waiter) {}
    }

    private func clickWebViewCenter(_ webView: WKWebView, in window: NSWindow) {
        let location = NSPoint(x: webView.frame.midX, y: webView.frame.midY)
        guard let down = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: location,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ), let up = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: location,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 0
        ) else {
            XCTFail("Expected synthetic click events")
            return
        }

        webView.mouseDown(with: down)
        webView.mouseUp(with: up)
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

    /// Polls a JavaScript numeric expression in a WKWebView until it matches the
    /// expected value, or fails with a clear timeout.
    ///
    /// This is the correct way to assert on state that is mutated by an
    /// asynchronous WebKit event. `webView.mouseDown`/`mouseUp` (and real
    /// `sendEvent` dispatch) hand the event to the WebContent process, which
    /// fires the DOM handler some run-loop iterations later. A single
    /// `evaluateJavaScript` issued immediately afterward can return the
    /// pre-event value. Polling on a short cadence waits for delivery to settle
    /// instead of guessing a fixed sleep duration, succeeding as soon as the
    /// value flips.
    private func waitForJavaScriptNumber(
        _ script: String,
        in webView: WKWebView,
        equals expected: Double,
        accuracy: Double = 0.001,
        timeout: TimeInterval = 2.0,
        pollInterval: TimeInterval = 0.03
    ) {
        let deadline = Date(timeIntervalSinceNow: timeout)
        var lastValue: Double = .nan
        var matched = false

        repeat {
            lastValue = evaluateNumber(script, in: webView)
            if !lastValue.isNaN, abs(lastValue - expected) <= accuracy {
                matched = true
                break
            }
            // Yield to the run loop so WebContent can process pending input.
            let tick = expectation(description: "poll interval")
            DispatchQueue.main.asyncAfter(deadline: .now() + pollInterval) { tick.fulfill() }
            wait(for: [tick], timeout: pollInterval * 2)
        } while Date() < deadline

        if !matched {
            XCTFail(
                "Timed out after \(timeout)s waiting for `\(script)` to equal \(expected)"
                + " ±\(accuracy); last value was \(lastValue)"
            )
        }
    }

    private func tryUnwrapFloatTabsWebView(_ webView: WKWebView) -> FloatTabsWebView {
        guard let result = webView as? FloatTabsWebView else {
            XCTFail("Expected FloatTabsWebView")
            fatalError("Expected FloatTabsWebView")
        }
        return result
    }

    // MARK: - Offline navigation test helpers

    private func makePolicyWebView(delegate: WKNavigationDelegate) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.setURLSchemeHandler(OfflinePageSchemeHandler(), forURLScheme: "x-ft-test")
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 430, height: 820),
            configuration: configuration
        )
        webView.navigationDelegate = delegate
        return webView
    }

    private func hostDirect(_ webView: WKWebView) -> NSWindow {
        // Host through the production container (layer-backed clip/logical host)
        // — the same path real panels use — so the WKWebView actually commits loads.
        let container = WebPanelContainerView(frame: NSRect(x: 0, y: 0, width: 430, height: 820))
        container.show(webView: webView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 820),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = container
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        container.layoutSubtreeIfNeeded()
        webView.layoutSubtreeIfNeeded()
        return window
    }

    private func waitForURL(_ webView: WKWebView, toBecome expected: URL, timeout: TimeInterval) {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            let tick = expectation(description: "url tick")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { tick.fulfill() }
            wait(for: [tick], timeout: 0.2)
            if webView.url == expected { return }
        }
        XCTFail("Timed out waiting for url to become \(expected); was \(webView.url?.absoluteString ?? "nil")")
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

/// Serves deterministic, offline pages for `x-ft-test://`:
/// - `/landing-blank`: a centered link with `target="_blank"` to `/destination`
/// - `/landing-self`:  a centered ordinary link to `/self-destination`
/// - anything else:    a plain "destination" page.
/// Custom-scheme top-frame loads go through `SlotNavigationObserver` exactly
/// like real URL navigations, avoiding the `loadHTMLString`+observer stall.
private func offlineCenteredLinkHTML(href: String, target: String?) -> String {
    """
    <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head><body>
    <style>html,body{margin:0;width:100%;height:100%;}
    a{position:fixed;left:50%;top:50%;transform:translate(-50%,-50%);width:280px;height:100px;
      display:flex;align-items:center;justify-content:center;background:#ddd;font-size:22px;}</style>
    <a id="link" href="\(href)"\(target.map { " target=\"\($0)\"" } ?? "")>open</a>
    </body></html>
    """
}

private final class OfflinePageSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let url = urlSchemeTask.request.url ?? URL(string: "x-ft-test://host")!
        let path = url.path
        let body: String
        if path.contains("landing-blank") {
            body = offlineCenteredLinkHTML(href: "x-ft-test://host/destination", target: "_blank")
        } else if path.contains("landing-self") {
            body = offlineCenteredLinkHTML(href: "x-ft-test://host/self-destination", target: nil)
        } else {
            body = "<!doctype html><html><body>destination reached</body></html>"
        }
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html; charset=utf-8"]
        ) else {
            urlSchemeTask.didFailWithError(NSError(domain: "OfflinePageSchemeHandler", code: 1))
            return
        }
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(Data(body.utf8))
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

/// Test navigation delegate that mirrors `SlotNavigationObserver`'s new-window
/// policy (route `targetFrame == nil` web navigations into the current web
/// view). It additionally accepts the offline `x-ft-test` scheme so the
/// destination can be served deterministically without network. Used because
/// the production observer cannot be driven end-to-end inside the XCTest
/// harness (it stalls WebContent there); the production *decision* itself is
/// covered directly by `testNewWindowPolicyRoutesBlankWebLinksIntoCurrentSlot`.
@MainActor
private final class NewWindowPolicyDelegate: NSObject, WKNavigationDelegate {
    var onFinish: (() -> Void)?

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        if navigationAction.targetFrame == nil,
           let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" || scheme == "x-ft-test" {
            decisionHandler(.cancel, preferences)
            webView.load(navigationAction.request)
            return
        }
        decisionHandler(.allow, preferences)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let finish = onFinish
        onFinish = nil // one-shot: only the initial fixture load fulfills the expectation
        finish?()
    }
}