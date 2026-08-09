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
        XCTAssertEqual(loadedRequests.last?.cachePolicy, .reloadIgnoringLocalCacheData)
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
        XCTAssertEqual(loadedRequests[1].cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(loadedRequests[2].cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(pool.count, 1)
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

    private func makePool() -> WebViewPool {
        WebViewPool(onURLChange: { _, _ in }, initialLoad: { _, _ in })
    }

    private func makeProfile(name: String) -> WebAppProfile {
        WebAppProfile(
            order: 0,
            name: name,
            homeURL: URL(string: "https://example.com/\(name)")!
        )
    }
}
