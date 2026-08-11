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

    func testWebViewsUseNativeElementFullscreenWithExitOnlyResetBridge() throws {
        let webView = WebViewFactory.makeWebView()
        let bridge = try XCTUnwrap(
            webView.configuration.userContentController.userScripts.first(where: {
                $0.source.contains("__floatTabsNativeFullscreenExitBridgeInstalled")
            })
        )

        XCTAssertTrue(webView.configuration.preferences.isElementFullscreenEnabled)
        XCTAssertEqual(bridge.injectionTime, .atDocumentStart)
        XCTAssertFalse(bridge.isForMainFrameOnly)
        XCTAssertTrue(bridge.source.contains("Document.prototype, 'exitFullscreen'"))
        XCTAssertFalse(bridge.source.contains("closeAllMediaPresentations"))
        XCTAssertFalse(bridge.source.contains("requestFullscreen"))
        XCTAssertFalse(bridge.source.contains("wrapExitMethod(Element.prototype,"))
        XCTAssertFalse(bridge.source.contains("style.position"))
    }

    func testFullscreenSessionResetPoliciesRequireAnActiveNativePresentation() {
        XCTAssertTrue(
            NativeFullscreenSessionResetCoordinator.shouldResetForEscape(
                keyCode: NativeFullscreenSessionResetCoordinator.escapeKeyCode,
                fullscreenState: .inFullscreen,
                resetInFlight: false
            )
        )
        XCTAssertFalse(
            NativeFullscreenSessionResetCoordinator.shouldResetForEscape(
                keyCode: 36,
                fullscreenState: .inFullscreen,
                resetInFlight: false
            )
        )
        XCTAssertFalse(
            NativeFullscreenSessionResetCoordinator.shouldResetForEscape(
                keyCode: NativeFullscreenSessionResetCoordinator.escapeKeyCode,
                fullscreenState: .enteringFullscreen,
                resetInFlight: false
            )
        )
        XCTAssertFalse(
            NativeFullscreenSessionResetCoordinator.shouldResetForEscape(
                keyCode: NativeFullscreenSessionResetCoordinator.escapeKeyCode,
                fullscreenState: .inFullscreen,
                resetInFlight: true
            )
        )

        XCTAssertTrue(
            NativeFullscreenSessionResetCoordinator.canResetForPageExit(
                fullscreenState: .enteringFullscreen,
                resetInFlight: false
            )
        )
        XCTAssertTrue(
            NativeFullscreenSessionResetCoordinator.canResetForPageExit(
                fullscreenState: .inFullscreen,
                resetInFlight: false
            )
        )
        XCTAssertFalse(
            NativeFullscreenSessionResetCoordinator.canResetForPageExit(
                fullscreenState: .exitingFullscreen,
                resetInFlight: false
            )
        )
        XCTAssertFalse(
            NativeFullscreenSessionResetCoordinator.canResetForPageExit(
                fullscreenState: .notInFullscreen,
                resetInFlight: false
            )
        )
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

    func testWebsiteLayoutViewportMapsVisibleWidthsToDistinctDesktopExperiences() {
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
    }

    func testMediumDesktopHostUsesBalancedLogicalLayoutWithoutPageZoomFit() {
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
    }

    func testVisibleResizeMovesBetweenDesktopExperienceClassesWithoutPageZoomFit() {
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
    }

    func testSmallDesktopModeUsesCompactResponsiveCSSClass() {
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
    }

    func testMobileModeRemainsNativeOneToOneAtWideWindowSize() {
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
    }

    func testDesktopHostMapsVisibleCenterIntoLogicalWebCoordinates() {
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = host(webView, visibleSize: NSSize(width: 600, height: 820))

        let webPoint = webView.convert(NSPoint(x: 300, y: 410), from: container)
        XCTAssertEqual(webPoint.x, webView.bounds.midX, accuracy: 0.5)
        XCTAssertEqual(webPoint.y, webView.bounds.midY, accuracy: 0.5)
    }

    func testHotHostsPreserveInactiveViewportAcrossDifferentSlotSizes() {
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
    }

    func testDesktopLogicalHostKeepsNativeWindowClickHitTestingWorking() {
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

    func testUserZoomStaysIndependentFromDesktopHostLayoutFit() {
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

    private func clickWindow(at location: NSPoint, in window: NSWindow) {
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

    private func clickWebViewCenter(_ webView: WKWebView, in window: NSWindow) {
        let location = webView.convert(
            NSPoint(x: webView.bounds.midX, y: webView.bounds.midY),
            to: nil
        )
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
