import WebKit
import XCTest
@testable import FloatTabs

@MainActor
final class WebViewPoolTests: XCTestCase {
    func testDifferentSlotIDsReceiveDifferentWebViews() {
        let pool = makePool()
        let first = makeProfile(name: "A")
        let second = makeProfile(name: "B")

        let firstView = pool.webView(for: first)
        let secondView = pool.webView(for: second)

        XCTAssertFalse(firstView === secondView)
        XCTAssertEqual(pool.count, 2)
    }

    func testSameSlotIDReusesSameWebViewInstance() {
        let pool = makePool()
        let profile = makeProfile(name: "A")

        let first = pool.webView(for: profile)
        let second = pool.webView(for: profile)

        XCTAssertTrue(first === second)
        XCTAssertEqual(pool.count, 1)
    }

    func testZoomOrViewportChangeAppliesWithoutRebuildingSlotWebView() {
        let pool = makePool()
        var profile = makeProfile(name: "A")
        let first = pool.webView(for: profile)

        profile.renderingProfile = profile.renderingProfile
            .settingZoom(1.25)
            .settingViewport(CGSize(width: 612, height: 777))
        let second = pool.webView(for: profile)

        XCTAssertTrue(first === second)
        XCTAssertEqual(second.pageZoom, 1.25, accuracy: 0.001)
        XCTAssertEqual(pool.count, 1)
    }

    func testBrowserIdentityChangeRebuildsOnlyAffectedSlotAndRestoresURL() {
        var loadedRequests: [URLRequest] = []
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, request in loadedRequests.append(request) }
        )
        var firstProfile = makeProfile(name: "A")
        let secondProfile = makeProfile(name: "B")
        firstProfile.currentURL = URL(string: "https://example.com/current")!

        let firstView = pool.webView(for: firstProfile)
        let secondView = pool.webView(for: secondProfile)

        firstProfile.renderingProfile = firstProfile.renderingProfile
            .settingBrowserIdentity(.windowsChrome)
        let rebuilt = pool.webView(for: firstProfile)
        let secondAgain = pool.webView(for: secondProfile)

        XCTAssertFalse(firstView === rebuilt)
        XCTAssertTrue(secondView === secondAgain)
        XCTAssertTrue(rebuilt.configuration.websiteDataStore.isPersistent)
        XCTAssertTrue(rebuilt.customUserAgent?.contains("Windows NT 10.0") == true)
        XCTAssertEqual(
            loadedRequests.filter { $0.url == firstProfile.currentURL }.count,
            2
        )
        XCTAssertEqual(loadedRequests.first?.cachePolicy, .useProtocolCachePolicy)
        XCTAssertEqual(loadedRequests.last?.cachePolicy, .useProtocolCachePolicy)
        XCTAssertEqual(pool.count, 2)
    }

    func testRebuildNavigationURLPrefersInitialRequestBeforeRedirectedURL() {
        let initialURL = URL(string: "https://www.example.com/article")!
        let redirectedURL = URL(string: "https://m.example.com/article")!

        let result = WebViewPool.rebuildNavigationURL(
            initialURL: initialURL,
            visibleURL: redirectedURL,
            storedCurrentURL: redirectedURL,
            homeURL: URL(string: "https://www.example.com")!
        )

        XCTAssertEqual(result, initialURL)
    }

    func testAutomaticWebsiteModeCanMoveDesktopMobileAndBackWithoutSticking() {
        var loadedRequests: [URLRequest] = []
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, request in loadedRequests.append(request) }
        )
        var profile = makeProfile(name: "A")

        let desktop = pool.webView(for: profile)
        XCTAssertEqual(
            desktop.configuration.defaultWebpagePreferences.preferredContentMode,
            .desktop
        )
        XCTAssertTrue(
            desktop.configuration.applicationNameForUserAgent?.contains("Version/") == true
        )
        XCTAssertTrue(
            desktop.configuration.applicationNameForUserAgent?.contains("Safari/") == true
        )

        profile.renderingProfile = profile.renderingProfile.settingWebsiteMode(.mobile)
        let mobile = pool.webView(for: profile)
        XCTAssertFalse(desktop === mobile)
        XCTAssertEqual(
            mobile.configuration.defaultWebpagePreferences.preferredContentMode,
            .mobile
        )
        XCTAssertTrue(mobile.customUserAgent?.contains("iPhone") == true)
        XCTAssertFalse(mobile.customUserAgent?.contains("Macintosh") == true)

        profile.renderingProfile = profile.renderingProfile.settingWebsiteMode(.desktop)
        let desktopAgain = pool.webView(for: profile)
        XCTAssertFalse(mobile === desktopAgain)
        XCTAssertEqual(
            desktopAgain.configuration.defaultWebpagePreferences.preferredContentMode,
            .desktop
        )
        XCTAssertTrue(
            desktopAgain.configuration.applicationNameForUserAgent?.contains("Version/") == true
        )
        XCTAssertTrue(
            desktopAgain.configuration.applicationNameForUserAgent?.contains("Safari/") == true
        )
        XCTAssertEqual(loadedRequests.count, 3)
        XCTAssertEqual(loadedRequests[0].cachePolicy, .useProtocolCachePolicy)
        XCTAssertEqual(loadedRequests[1].cachePolicy, .useProtocolCachePolicy)
        XCTAssertEqual(loadedRequests[2].cachePolicy, .useProtocolCachePolicy)
        XCTAssertEqual(pool.count, 1)
    }

    func testChatGPTMobileAutomaticUsesDesktopPointerCompatibilityIdentity() {
        let pool = makePool()
        var profile = makeProfile(
            name: "ChatGPT",
            homeURL: URL(string: "https://chatgpt.com/")!
        )
        profile.renderingProfile = profile.renderingProfile.settingWebsiteMode(.mobile)

        let webView = pool.webView(for: profile)

        XCTAssertEqual(
            webView.configuration.defaultWebpagePreferences.preferredContentMode,
            .mobile
        )
        XCTAssertTrue(webView.customUserAgent?.contains("Macintosh") == true)
        XCTAssertFalse(webView.customUserAgent?.contains("iPhone") == true)
    }

    func testDevicePresetChangeDoesNotRebuildOrAlterBrowserIdentity() {
        let pool = makePool()
        var profile = makeProfile(name: "A")
        let first = pool.webView(for: profile)
        let firstUA = first.customUserAgent

        profile.renderingProfile = profile.renderingProfile.settingDevicePreset(id: "iphone-17-pro")
        let second = pool.webView(for: profile)

        XCTAssertTrue(first === second)
        XCTAssertEqual(second.customUserAgent, firstUA)
        XCTAssertEqual(profile.renderingProfile.websiteMode, .desktop)
        XCTAssertEqual(profile.renderingProfile.viewportSize, CGSize(width: 402, height: 874))
    }

    func testPooledWebViewsUsePersistentWebsiteDataStore() {
        let pool = makePool()
        let webView = pool.webView(for: makeProfile(name: "A"))

        XCTAssertTrue(webView.configuration.websiteDataStore.isPersistent)
    }

    func testPooledWebViewsInstallPopupCoordinator() {
        let pool = makePool()
        let webView = pool.webView(for: makeProfile(name: "A"))

        XCTAssertTrue(webView.uiDelegate is PopupCoordinator)
    }

    func testRemovingOneSlotDoesNotAffectOtherWebViewIdentity() {
        let pool = makePool()
        let first = makeProfile(name: "A")
        let second = makeProfile(name: "B")
        _ = pool.webView(for: first)
        let secondView = pool.webView(for: second)

        pool.remove(slotID: first.id)

        XCTAssertFalse(pool.contains(slotID: first.id))
        XCTAssertTrue(pool.contains(slotID: second.id))
        XCTAssertTrue(pool.webView(for: second) === secondView)
        XCTAssertEqual(pool.count, 1)
    }

    func testNavigationCoordinatorKeepsSameSiteBlankInCurrentSlot() {
        let result = WebNavigationCoordinator.disposition(
            hasTargetFrame: false,
            sourceURL: URL(string: "https://www.bilibili.com/"),
            targetURL: URL(string: "https://bilibili.com/video/BV123")
        )

        XCTAssertEqual(result, .loadInCurrentSlot)
    }

    func testNavigationCoordinatorLetsCrossSiteBlankReachUIDelegate() {
        let result = WebNavigationCoordinator.disposition(
            hasTargetFrame: false,
            sourceURL: URL(string: "https://example.com/article"),
            targetURL: URL(string: "https://developer.apple.com/documentation")
        )

        XCTAssertEqual(result, .allow)
    }

    func testNavigationCoordinatorAllowsNormalInFrameNavigation() {
        let result = WebNavigationCoordinator.disposition(
            hasTargetFrame: true,
            sourceURL: URL(string: "https://example.com"),
            targetURL: URL(string: "https://example.com/next")
        )

        XCTAssertEqual(result, .allow)
    }

    func testPopupRoutingKeepsSameSiteContextInCurrentSlot() {
        let result = PopupCoordinator.disposition(
            navigationType: .linkActivated,
            sourceURL: URL(string: "https://www.bilibili.com/"),
            targetURL: URL(string: "https://bilibili.com/video/BV123")
        )

        XCTAssertEqual(result, .currentSlot)
    }

    func testPopupRoutingSendsCrossSiteUserLinkToDefaultBrowser() {
        let result = PopupCoordinator.disposition(
            navigationType: .linkActivated,
            sourceURL: URL(string: "https://example.com"),
            targetURL: URL(string: "https://developer.apple.com")
        )

        XCTAssertEqual(result, .externalBrowser)
    }

    func testPopupRoutingUsesTemporaryChildForScriptedCrossSitePopup() {
        let result = PopupCoordinator.disposition(
            navigationType: .other,
            sourceURL: URL(string: "https://example.com"),
            targetURL: URL(string: "https://accounts.example-idp.com/oauth")
        )

        XCTAssertEqual(result, .temporaryPopup)
    }

    func testPopupRoutingTreatsAboutBlankAsTemporaryChild() {
        let result = PopupCoordinator.disposition(
            navigationType: .other,
            sourceURL: URL(string: "https://example.com"),
            targetURL: URL(string: "about:blank")
        )

        XCTAssertEqual(result, .temporaryPopup)
    }

    func testPopupRoutingHandsNonWebSchemeToSystem() {
        let result = PopupCoordinator.disposition(
            navigationType: .linkActivated,
            sourceURL: URL(string: "https://example.com"),
            targetURL: URL(string: "mailto:test@example.com")
        )

        XCTAssertEqual(result, .externalBrowser)
    }

    func testUploadPanelPolicyForSingleFile() {
        let policy = UploadPanelPolicy.make(
            allowsMultipleSelection: false,
            allowsDirectories: false
        )

        XCTAssertFalse(policy.allowsMultipleSelection)
        XCTAssertTrue(policy.canChooseFiles)
        XCTAssertFalse(policy.canChooseDirectories)
    }

    func testUploadPanelPolicyForMultipleFiles() {
        let policy = UploadPanelPolicy.make(
            allowsMultipleSelection: true,
            allowsDirectories: false
        )

        XCTAssertTrue(policy.allowsMultipleSelection)
        XCTAssertTrue(policy.canChooseFiles)
        XCTAssertFalse(policy.canChooseDirectories)
    }

    func testUploadPanelPolicyForDirectory() {
        let policy = UploadPanelPolicy.make(
            allowsMultipleSelection: true,
            allowsDirectories: true
        )

        XCTAssertTrue(policy.allowsMultipleSelection)
        XCTAssertFalse(policy.canChooseFiles)
        XCTAssertTrue(policy.canChooseDirectories)
    }

    func testExplicitDownloadActionUsesDownloadPolicy() {
        XCTAssertEqual(
            DownloadCoordinator.actionPolicy(shouldPerformDownload: true),
            .download
        )
        XCTAssertEqual(
            DownloadCoordinator.actionPolicy(shouldPerformDownload: false),
            .allow
        )
    }

    func testUnshowableMimeResponseUsesDownloadPolicy() {
        XCTAssertEqual(
            DownloadCoordinator.responsePolicy(canShowMIMEType: false),
            .download
        )
        XCTAssertEqual(
            DownloadCoordinator.responsePolicy(canShowMIMEType: true),
            .allow
        )
    }

    func testDownloadSuggestedFilenameDropsPathComponents() {
        XCTAssertEqual(
            DownloadCoordinator.safeSuggestedFilename("nested/path/report.txt"),
            "report.txt"
        )
        XCTAssertEqual(
            DownloadCoordinator.safeSuggestedFilename(""),
            "Download"
        )
    }

    private func makePool() -> WebViewPool {
        WebViewPool(onURLChange: { _, _ in }, initialLoad: { _, _ in })
    }

    private func makeProfile(name: String, homeURL: URL? = nil) -> WebAppProfile {
        WebAppProfile(
            order: 0,
            name: name,
            homeURL: homeURL ?? URL(string: "https://example.com/\(name)")!
        )
    }
}
