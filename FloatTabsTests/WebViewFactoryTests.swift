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

    func testRenderingProfileAppliesMobileIdentityContentModeAndUserZoom() {
        let rendering = WebRenderingProfile.canonicalDefault
            .settingWebsiteMode(.mobile)
            .settingZoom(1.25)
        let webView = WebViewFactory.makeWebView(renderingProfile: rendering)
        let floatTabsWebView = tryUnwrapFloatTabsWebView(webView)

        XCTAssertTrue(webView.configuration.websiteDataStore.isPersistent)
        XCTAssertEqual(webView.configuration.defaultWebpagePreferences.preferredContentMode, .mobile)
        XCTAssertTrue(webView.customUserAgent?.contains("iPhone") == true)
        XCTAssertTrue(webView.customUserAgent?.contains("Version/") == true)
        XCTAssertEqual(floatTabsWebView.userPageZoom, 1.25, accuracy: 0.001)
        XCTAssertEqual(webView.pageZoom, 1.25, accuracy: 0.001)
    }

    func testWebsiteLayoutViewportSeparatesTargetCSSWidthFromVisibleWindowSize() {
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
            390,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WebsiteLayoutViewport.fittingScale(forVisibleWidth: 390, websiteMode: .mobile),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WebsiteLayoutViewport.targetCSSWidth(forVisibleWidth: 320, websiteMode: .mobile),
            320,
            accuracy: 0.001
        )

        let physical = CGSize(width: 430, height: 820)
        XCTAssertEqual(
            WebsiteLayoutViewport.logicalSize(forVisibleSize: physical, websiteMode: .desktop),
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
        let desktopMediaQuery = evaluateNumber("matchMedia('(min-width: 1000px)').matches ? 1 : 0", in: webView)

        XCTAssertEqual(container.bounds.width, 430, accuracy: 0.001)
        XCTAssertEqual(webView.frame.width, 430, accuracy: 0.001)
        XCTAssertEqual(cssWidth, 1280, accuracy: 2)
        XCTAssertEqual(innerWidth, 1280, accuracy: 2)
        XCTAssertEqual(desktopMediaQuery, 1, accuracy: 0.001)
    }

    func testMobileModeUsesCenteredPhysicalSurfaceWhileWindowStaysWide() {
        let rendering = WebRenderingProfile.canonicalDefault
            .settingWebsiteMode(.mobile)
            .settingSimplePreset(.wide)
        let webView = WebViewFactory.makeWebView(renderingProfile: rendering)
        let container = host(webView, visibleSize: NSSize(width: 900, height: 850))
        let floatTabsWebView = tryUnwrapFloatTabsWebView(webView)

        loadTestHTML(in: webView)
        let cssWidth = evaluateNumber("document.body.clientWidth", in: webView)
        let innerWidth = evaluateNumber("window.innerWidth", in: webView)
        let desktopMediaQuery = evaluateNumber("matchMedia('(min-width: 1000px)').matches ? 1 : 0", in: webView)

        XCTAssertEqual(container.bounds.width, 900, accuracy: 0.001)
        XCTAssertEqual(webView.frame.minX, 255, accuracy: 0.001)
        XCTAssertEqual(webView.frame.width, 390, accuracy: 0.001)
        XCTAssertEqual(webView.frame.height, 850, accuracy: 0.001)
        XCTAssertEqual(webView.bounds.size, webView.frame.size)
        XCTAssertEqual(container.websiteLayoutScale, 1, accuracy: 0.001)
        XCTAssertEqual(floatTabsWebView.websiteLayoutScale, 1, accuracy: 0.001)
        XCTAssertEqual(webView.pageZoom, 1, accuracy: 0.001)
        XCTAssertEqual(cssWidth, 390, accuracy: 2)
        XCTAssertEqual(innerWidth, 390, accuracy: 2)
        XCTAssertEqual(desktopMediaQuery, 0, accuracy: 0.001)
    }

    func testMobileSurfaceCapsAt390WithoutChangingOuterWindowSize() {
        let mediumRendering = WebRenderingProfile.canonicalDefault
            .settingWebsiteMode(.mobile)
            .settingSimplePreset(.medium)
        let mediumWebView = WebViewFactory.makeWebView(renderingProfile: mediumRendering)
        let mediumContainer = host(mediumWebView, visibleSize: NSSize(width: 430, height: 820))

        XCTAssertEqual(mediumContainer.bounds.width, 430, accuracy: 0.001)
        XCTAssertEqual(mediumWebView.frame.minX, 20, accuracy: 0.001)
        XCTAssertEqual(mediumWebView.frame.width, 390, accuracy: 0.001)
        XCTAssertEqual(mediumWebView.pageZoom, 1, accuracy: 0.001)

        let compactRendering = mediumRendering.settingSimplePreset(.compact)
        let compactWebView = WebViewFactory.makeWebView(renderingProfile: compactRendering)
        let compactContainer = host(compactWebView, visibleSize: NSSize(width: 360, height: 720))

        XCTAssertEqual(compactContainer.bounds.width, 360, accuracy: 0.001)
        XCTAssertEqual(compactWebView.frame.minX, 0, accuracy: 0.001)
        XCTAssertEqual(compactWebView.frame.width, 360, accuracy: 0.001)
        XCTAssertEqual(compactWebView.pageZoom, 1, accuracy: 0.001)
    }

    func testNativeWebCoordinatesRemainOneToOneWithVisibleCoordinates() {
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = host(webView, visibleSize: NSSize(width: 430, height: 820))

        let webPoint = webView.convert(NSPoint(x: 215, y: 410), from: container)
        XCTAssertEqual(webPoint.x, 215, accuracy: 0.5)
        XCTAssertEqual(webPoint.y, 410, accuracy: 0.5)
    }

    func testDesktopPublicPageZoomKeepsNativeClickHitTestingWorking() {
        _ = NSApplication.shared
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = WebPanelContainerView(frame: NSRect(x: 0, y: 0, width: 430, height: 820))
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
        waitForJavaScriptNumber("window.clicks", in: webView, equals: 1)
        window.orderOut(nil)
    }

    func testMobileCenteredSurfaceRoutesOffCenterHitIntoWebViewTree() {
        _ = NSApplication.shared

        let rendering = WebRenderingProfile.canonicalDefault
            .settingWebsiteMode(.mobile)
            .settingSimplePreset(.wide)
        let webView = WebViewFactory.makeWebView(renderingProfile: rendering)
        let container = WebPanelContainerView(frame: NSRect(x: 0, y: 0, width: 900, height: 850))
        container.show(webView: webView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 850),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = container
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        container.layoutSubtreeIfNeeded()
        webView.layoutSubtreeIfNeeded()

        XCTAssertEqual(webView.frame.minX, 255, accuracy: 0.001)
        XCTAssertEqual(webView.frame.width, 390, accuracy: 0.001)
        XCTAssertEqual(webView.pageZoom, 1, accuracy: 0.001)

        let webLocalPoint = NSPoint(x: 48, y: 48)
        let containerPoint = webView.convert(webLocalPoint, to: container)
        XCTAssertEqual(containerPoint.x, 303, accuracy: 0.5)
        XCTAssertEqual(containerPoint.y, 48, accuracy: 0.5)

        guard let hit = container.hitTest(containerPoint) else {
            XCTFail("Expected off-center Mobile point to hit the WebView subtree")
            window.orderOut(nil)
            return
        }
        XCTAssertTrue(isDescendant(hit, of: webView))
        XCTAssertFalse(webView.frame.contains(NSPoint(x: 100, y: 48)))

        window.orderOut(nil)
    }

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
        XCTAssertFalse(SlotNavigationObserver.shouldOpenInCurrentSlot(targetFrame: nil, url: nil))
    }

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
        XCTAssertEqual(desktopWebView.pageZoom, 1.25 * 430.0 / 1280.0, accuracy: 0.001)

        let mobileRendering = desktopRendering
            .settingWebsiteMode(.mobile)
            .settingSimplePreset(.wide)
        let mobileWebView = WebViewFactory.makeWebView(renderingProfile: mobileRendering)
        _ = host(mobileWebView, visibleSize: NSSize(width: 900, height: 850))
        let mobileFloatWebView = tryUnwrapFloatTabsWebView(mobileWebView)

        XCTAssertEqual(mobileFloatWebView.userPageZoom, 1.25, accuracy: 0.001)
        XCTAssertEqual(mobileFloatWebView.websiteLayoutScale, 1, accuracy: 0.001)
        XCTAssertEqual(mobileWebView.pageZoom, 1.25, accuracy: 0.001)
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
        XCTAssertEqual(floatTabsWebView.websiteLayoutScale, 1, accuracy: 0.001)
    }

    func testMacOSSafariRuntimeUsesNativeWebKitUAWithSafariSuffix() {
        let rendering = WebRenderingProfile.canonicalDefault.settingBrowserIdentity(.macosSafari)

        XCTAssertNil(UserAgentProvider.customUserAgent(for: rendering, versions: versions))

        let webView = WebViewFactory.makeWebView(renderingProfile: rendering)
        XCTAssertTrue(webView.configuration.applicationNameForUserAgent?.contains("Version/") == true)
        XCTAssertTrue(webView.configuration.applicationNameForUserAgent?.contains("Safari/") == true)

        loadTestHTML(in: webView)
        let hasSafariRuntimeIdentity = evaluateNumber(
            "navigator.userAgent.includes('Version/') && navigator.userAgent.includes('Safari/') ? 1 : 0",
            in: webView
        )
        XCTAssertEqual(hasSafariRuntimeIdentity, 1, accuracy: 0.001)
    }

    func testSafariCompatibilityIdentityUsesResolvedWebKitVersion() {
        let ua = UserAgentProvider.userAgent(for: .macosSafari, websiteMode: .desktop, versions: versions)
        XCTAssertTrue(ua.contains("Macintosh"))
        XCTAssertTrue(ua.contains("AppleWebKit/619.3.7"))
        XCTAssertTrue(ua.contains("Version/26.6"))
        XCTAssertTrue(ua.contains("Safari/619.3.7"))
        XCTAssertEqual(UserAgentProvider.safariApplicationName(versions: versions), "Version/26.6 Safari/619.3.7")
    }

    func testExactDesktopAndMobileIdentityPresetsAreCentralized() {
        let macChrome = UserAgentProvider.userAgent(for: .macosChrome, websiteMode: .desktop, versions: versions)
        XCTAssertTrue(macChrome.contains("Macintosh"))
        XCTAssertTrue(macChrome.contains("Chrome/150.0.7871.187"))

        let windowsChrome = UserAgentProvider.userAgent(for: .windowsChrome, websiteMode: .desktop, versions: versions)
        XCTAssertTrue(windowsChrome.contains("Windows NT 10.0"))
        XCTAssertTrue(windowsChrome.contains("Chrome/150.0.7871.187"))

        let linuxChrome = UserAgentProvider.userAgent(for: .linuxChrome, websiteMode: .desktop, versions: versions)
        XCTAssertTrue(linuxChrome.contains("Linux x86_64"))

        let edge = UserAgentProvider.userAgent(for: .windowsEdge, websiteMode: .desktop, versions: versions)
        XCTAssertTrue(edge.contains("Windows NT 10.0"))
        XCTAssertTrue(edge.contains("Chrome/150.0.7871.187"))
        XCTAssertTrue(edge.contains("Edg/150.0.4078.99"))

        let iPhoneChrome = UserAgentProvider.userAgent(for: .iphoneChrome, websiteMode: .mobile, versions: versions)
        XCTAssertTrue(iPhoneChrome.contains("iPhone"))
        XCTAssertTrue(iPhoneChrome.contains("AppleWebKit/619.3.7"))
        XCTAssertTrue(iPhoneChrome.contains("CriOS/150.0.7871.187"))

        let android = UserAgentProvider.userAgent(for: .androidChrome, websiteMode: .mobile, versions: versions)
        XCTAssertTrue(android.contains("Android 16"))
        XCTAssertTrue(android.contains("Mobile Safari"))
    }

    func testAutomaticIdentityFollowsWebsiteModeWithoutChangingWindowSizePolicy() {
        let desktopUA = UserAgentProvider.userAgent(for: .automatic, websiteMode: .desktop, versions: versions)
        let mobileUA = UserAgentProvider.userAgent(for: .automatic, websiteMode: .mobile, versions: versions)
        XCTAssertTrue(desktopUA.contains("Macintosh"))
        XCTAssertTrue(desktopUA.contains("Version/26.6"))
        XCTAssertTrue(mobileUA.contains("iPhone"))
        XCTAssertTrue(mobileUA.contains("Version/26.6"))
    }

    func testCustomUserAgentPassesThroughExactly() {
        let custom = "FloatTabs-Test-UA/1.0"
        XCTAssertEqual(
            UserAgentProvider.userAgent(for: .custom, websiteMode: .desktop, customUserAgent: custom, versions: versions),
            custom
        )
    }

    func testBrowserVersionNormalizationAvoidsStalePartialVersionStrings() {
        XCTAssertEqual(BrowserVersionResolver.normalizedSafariVersion("26.6.1"), "26.6")
        XCTAssertEqual(BrowserVersionResolver.normalizedChromiumVersion("150.0.7871.187"), "150.0.7871.187")
        XCTAssertEqual(BrowserVersionResolver.normalizedChromiumVersion("150"), "150.0.0.0")
    }

    func testNavigationFinishRestoresHiddenScrollerPolicyAfterWebKitReenablesIt() {
        let webView = WebViewFactory.makeWebView()
        let simulatedWebKitScrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 500))
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

        WebViewFactory.setScrollerVisibility(scrollView, vertical: true, horizontal: false)

        XCTAssertEqual(scrollView.scrollerStyle, .overlay)
        XCTAssertTrue(scrollView.autohidesScrollers)
        XCTAssertTrue(scrollView.hasVerticalScroller)
        XCTAssertFalse(scrollView.hasHorizontalScroller)

        WebViewFactory.configureHiddenScrollerStyle(scrollView)
        XCTAssertFalse(scrollView.hasVerticalScroller)
        XCTAssertFalse(scrollView.hasHorizontalScroller)
    }

    private func host(_ webView: WKWebView, visibleSize: NSSize) -> WebPanelContainerView {
        let container = WebPanelContainerView(frame: NSRect(origin: .zero, size: visibleSize))
        container.show(webView: webView)
        container.layoutSubtreeIfNeeded()
        webView.layoutSubtreeIfNeeded()
        return container
    }

    private func loadTestHTML(in webView: WKWebView) {
        let expectation = expectation(description: "WKWebView test page loaded")
        let waiter = NavigationWaiter { expectation.fulfill() }
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
        let waiter = NavigationWaiter { expectation.fulfill() }
        webView.navigationDelegate = waiter
        webView.loadHTMLString(
            """
            <!doctype html>
            <html>
              <head>
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <style>
                  html, body { margin:0; width:100%; height:100%; }
                  #target { position:fixed; left:50vw; top:50vh; width:120px; height:80px; transform:translate(-50%, -50%); }
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
        let localPoint = NSPoint(x: webView.bounds.midX, y: webView.bounds.midY)
        clickWebView(webView, localPoint: localPoint, in: window)
    }

    private func clickWebView(_ webView: WKWebView, localPoint: NSPoint, in window: NSWindow) {
        let location = webView.convert(localPoint, to: nil)
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

    private func isDescendant(_ candidate: NSView, of ancestor: NSView) -> Bool {
        var current: NSView? = candidate
        while let view = current {
            if view === ancestor { return true }
            current = view.superview
        }
        return false
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
        onFinish = nil
        finish?()
    }
}
