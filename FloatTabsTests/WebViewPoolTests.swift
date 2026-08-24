import AppKit
import WebKit
import XCTest
@testable import FloatTabs

@MainActor
final class WebViewPoolTests: XCTestCase {
    func testDifferentSlotIDsReceiveDifferentWebViews() throws {
        let pool = makePool()
        let first = makeProfile(name: "A")
        let second = makeProfile(name: "B")

        let firstView = try pool.webView(for: first)
        let secondView = try pool.webView(for: second)

        XCTAssertFalse(firstView === secondView)
        XCTAssertEqual(pool.count, 2)
    }

    func testSameSlotIDReusesSameWebViewInstance() throws {
        let pool = makePool()
        let profile = makeProfile(name: "A")

        let first = try pool.webView(for: profile)
        let second = try pool.webView(for: profile)

        XCTAssertTrue(first === second)
        XCTAssertEqual(pool.count, 1)
    }

    func testZoomOrViewportChangeAppliesWithoutRebuildingSlotWebView() throws {
        let pool = makePool()
        var profile = makeProfile(name: "A")
        let first = try pool.webView(for: profile)

        profile.renderingProfile = profile.renderingProfile
            .settingZoom(1.25)
            .settingViewport(CGSize(width: 612, height: 777))
        let second = try pool.webView(for: profile)

        XCTAssertTrue(first === second)
        XCTAssertEqual(second.pageZoom, 1.25, accuracy: 0.001)
        XCTAssertEqual(pool.count, 1)
    }

    func testBrowserIdentityChangeRebuildsOnlyAffectedSlotAndRestoresURL() throws {
        var loadedRequests: [URLRequest] = []
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, request in loadedRequests.append(request) }
        )
        var firstProfile = makeProfile(name: "A")
        let secondProfile = makeProfile(name: "B")
        firstProfile.currentURL = URL(string: "https://example.com/current")!

        let firstView = try pool.webView(for: firstProfile)
        let secondView = try pool.webView(for: secondProfile)

        firstProfile.renderingProfile = firstProfile.renderingProfile
            .settingBrowserIdentity(.windowsChrome)
        let rebuilt = try pool.webView(for: firstProfile)
        let secondAgain = try pool.webView(for: secondProfile)

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

    func testDefaultAndCustomBrowserProfilesResolveDistinctStoresAndRecordIdentity() throws {
        let customID = UUID()
        let defaultStore = WKWebsiteDataStore.nonPersistent()
        let customStore = WKWebsiteDataStore.nonPersistent()
        var resolvedCustomIDs: [UUID] = []
        let provider = BrowserProfileDataStoreProvider(
            isCustomProfileSupported: { true },
            defaultStoreResolver: { defaultStore },
            customStoreResolver: { id in
                resolvedCustomIDs.append(id)
                return customStore
            }
        )
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, _ in },
            browserProfileDataStoreProvider: provider
        )
        var profile = makeProfile(name: "DefaultRuntime")

        let defaultWebView = try pool.webView(for: profile)
        XCTAssertTrue(defaultWebView.configuration.websiteDataStore === defaultStore)
        XCTAssertEqual(pool.browserProfileIdentity(for: profile.id), .default)

        profile.browserProfileID = customID
        let customWebView = try pool.webView(for: profile)
        XCTAssertTrue(customWebView.configuration.websiteDataStore === customStore)
        XCTAssertEqual(
            pool.browserProfileIdentity(for: profile.id),
            .custom(customID)
        )
        XCTAssertEqual(resolvedCustomIDs, [customID])
    }

    func testSameBrowserProfileIdentityReusesRuntimeWithoutResolvingAgain() throws {
        let customID = UUID()
        let customStore = WKWebsiteDataStore.nonPersistent()
        var resolverCalls = 0
        let provider = BrowserProfileDataStoreProvider(
            isCustomProfileSupported: { true },
            customStoreResolver: { id in
                XCTAssertEqual(id, customID)
                resolverCalls += 1
                return customStore
            }
        )
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, _ in },
            browserProfileDataStoreProvider: provider
        )
        let profile = makeProfile(name: "WarmCustom", browserProfileID: customID)

        let first = try pool.webView(for: profile)
        let second = try pool.webView(for: profile)

        XCTAssertTrue(first === second)
        XCTAssertEqual(resolverCalls, 1)
        XCTAssertEqual(pool.browserProfileIdentity(for: profile.id), .custom(customID))
    }

    func testTwoSlotsBoundToTheSameCustomProfileResolveTheExactUUIDIndependently() throws {
        let customID = UUID()
        let customStore = WKWebsiteDataStore.nonPersistent()
        var resolvedIDs: [UUID] = []
        let provider = BrowserProfileDataStoreProvider(
            isCustomProfileSupported: { true },
            customStoreResolver: { id in
                resolvedIDs.append(id)
                return customStore
            }
        )
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, _ in },
            browserProfileDataStoreProvider: provider
        )
        let first = makeProfile(name: "SharedFirst", browserProfileID: customID)
        let second = makeProfile(name: "SharedSecond", browserProfileID: customID)

        let firstWebView = try pool.webView(for: first)
        let secondWebView = try pool.webView(for: second)

        XCTAssertFalse(firstWebView === secondWebView)
        XCTAssertTrue(firstWebView.configuration.websiteDataStore === customStore)
        XCTAssertTrue(secondWebView.configuration.websiteDataStore === customStore)
        XCTAssertEqual(resolvedIDs, [customID, customID])
        XCTAssertEqual(pool.browserProfileIdentity(for: first.id), .custom(customID))
        XCTAssertEqual(pool.browserProfileIdentity(for: second.id), .custom(customID))
    }

    func testBrowserProfileIdentityChangeRebuildsRuntimeWithSuppliedStoreAndNavigation() throws {
        let customID = UUID()
        let customStore = WKWebsiteDataStore.nonPersistent()
        var loadedRequests: [URLRequest] = []
        let provider = BrowserProfileDataStoreProvider(
            isCustomProfileSupported: { true },
            customStoreResolver: { _ in customStore }
        )
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, request in loadedRequests.append(request) },
            browserProfileDataStoreProvider: provider
        )
        var profile = makeProfile(name: "RebuildCustom")
        profile.currentURL = URL(string: "https://example.com/live")!

        let original = try pool.webView(for: profile)
        let originalBridge = pool.attentionBridge(for: profile.id)
        profile.browserProfileID = customID
        let rebuilt = try pool.webView(for: profile)

        XCTAssertFalse(original === rebuilt)
        XCTAssertTrue(originalBridge?.isInvalidated == true)
        XCTAssertFalse(pool.attentionBridge(for: profile.id) === originalBridge)
        XCTAssertTrue(rebuilt.configuration.websiteDataStore === customStore)
        XCTAssertEqual(loadedRequests.map(\.url), [profile.currentURL, profile.currentURL])
        XCTAssertEqual(pool.browserProfileIdentity(for: profile.id), .custom(customID))
        XCTAssertEqual(pool.count, 1)
    }

    func testSuccessfulBrowserProfileRebuildDoesNotChurnResidentSet() throws {
        let customID = UUID()
        let provider = BrowserProfileDataStoreProvider(
            isCustomProfileSupported: { true },
            customStoreResolver: { _ in WKWebsiteDataStore.nonPersistent() }
        )
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, _ in },
            browserProfileDataStoreProvider: provider
        )
        var profile = makeProfile(name: "StableResident")
        var snapshots: [Set<UUID>] = []
        pool.onResidentSetChange = { snapshots.append(pool.residentSlotIDs) }

        _ = try pool.webView(for: profile)
        profile.browserProfileID = customID
        _ = try pool.webView(for: profile)

        XCTAssertEqual(snapshots, [[profile.id]])
        XCTAssertEqual(pool.residentSlotIDs, [profile.id])
    }

    func testReleasingSlotRemovesBrowserProfileIdentityDiagnostic() throws {
        let customID = UUID()
        let provider = BrowserProfileDataStoreProvider(
            isCustomProfileSupported: { true },
            customStoreResolver: { _ in WKWebsiteDataStore.nonPersistent() }
        )
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, _ in },
            browserProfileDataStoreProvider: provider
        )
        let profile = makeProfile(name: "ReleaseIdentity", browserProfileID: customID)

        _ = try pool.webView(for: profile)
        XCTAssertEqual(pool.browserProfileIdentity(for: profile.id), .custom(customID))

        pool.release(slotID: profile.id)

        XCTAssertNil(pool.browserProfileIdentity(for: profile.id))
        XCTAssertFalse(pool.contains(slotID: profile.id))
    }

    func testColdReleaseAndRecreatePreservesCustomBrowserProfileIdentity() throws {
        let customID = UUID()
        let customStore = WKWebsiteDataStore.nonPersistent()
        var resolverCalls = 0
        let provider = BrowserProfileDataStoreProvider(
            isCustomProfileSupported: { true },
            customStoreResolver: { id in
                XCTAssertEqual(id, customID)
                resolverCalls += 1
                return customStore
            }
        )
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, _ in },
            browserProfileDataStoreProvider: provider
        )
        let profile = makeProfile(name: "ColdRecreate", browserProfileID: customID)

        let first = try pool.webView(for: profile)
        pool.release(slotID: profile.id)
        XCTAssertNil(pool.browserProfileIdentity(for: profile.id))

        let recreated = try pool.webView(for: profile)

        XCTAssertFalse(first === recreated)
        XCTAssertTrue(recreated.configuration.websiteDataStore === customStore)
        XCTAssertEqual(resolverCalls, 2)
        XCTAssertEqual(pool.browserProfileIdentity(for: profile.id), .custom(customID))
    }

    func testContentProcessRecoveryKeepsBrowserProfileIdentityWithoutReresolving() throws {
        let customID = UUID()
        var resolverCalls = 0
        var loadedRequests: [URLRequest] = []
        let provider = BrowserProfileDataStoreProvider(
            isCustomProfileSupported: { true },
            customStoreResolver: { _ in
                resolverCalls += 1
                return WKWebsiteDataStore.nonPersistent()
            }
        )
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, request in loadedRequests.append(request) },
            isSlotActive: { _ in true },
            browserProfileDataStoreProvider: provider
        )
        var profile = makeProfile(name: "RecoveryIdentity", browserProfileID: customID)
        profile.currentURL = URL(string: "https://example.com/recover")!

        let original = try pool.webView(for: profile)
        pool.handleContentProcessTermination(slotID: profile.id)
        let recovered = try pool.webView(for: profile)

        XCTAssertTrue(original === recovered)
        XCTAssertEqual(resolverCalls, 1)
        XCTAssertEqual(pool.browserProfileIdentity(for: profile.id), .custom(customID))
        XCTAssertEqual(loadedRequests.count, 2)
    }

    func testDifferentSlotsKeepIndependentBrowserProfileRuntimeIdentities() throws {
        let firstID = UUID()
        let secondID = UUID()
        let firstStore = WKWebsiteDataStore.nonPersistent()
        let secondStore = WKWebsiteDataStore.nonPersistent()
        let provider = BrowserProfileDataStoreProvider(
            isCustomProfileSupported: { true },
            customStoreResolver: { id in
                id == firstID ? firstStore : secondStore
            }
        )
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, _ in },
            browserProfileDataStoreProvider: provider
        )
        let first = makeProfile(name: "FirstIdentity", browserProfileID: firstID)
        let second = makeProfile(name: "SecondIdentity", browserProfileID: secondID)

        let firstWebView = try pool.webView(for: first)
        let secondWebView = try pool.webView(for: second)

        XCTAssertTrue(firstWebView.configuration.websiteDataStore === firstStore)
        XCTAssertTrue(secondWebView.configuration.websiteDataStore === secondStore)
        XCTAssertEqual(pool.browserProfileIdentity(for: first.id), .custom(firstID))
        XCTAssertEqual(pool.browserProfileIdentity(for: second.id), .custom(secondID))
        XCTAssertTrue(try pool.webView(for: first) === firstWebView)
        XCTAssertTrue(try pool.webView(for: second) === secondWebView)
    }

    func testRenderingRebuildReappliesTheSameBrowserProfileIdentityAndStore() throws {
        let customID = UUID()
        let customStore = WKWebsiteDataStore.nonPersistent()
        var resolverCalls = 0
        let provider = BrowserProfileDataStoreProvider(
            isCustomProfileSupported: { true },
            customStoreResolver: { _ in
                resolverCalls += 1
                return customStore
            }
        )
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, _ in },
            browserProfileDataStoreProvider: provider
        )
        var profile = makeProfile(name: "RenderingRebuild", browserProfileID: customID)

        let original = try pool.webView(for: profile)
        profile.renderingProfile = profile.renderingProfile
            .settingBrowserIdentity(.windowsChrome)
        let rebuilt = try pool.webView(for: profile)

        XCTAssertFalse(original === rebuilt)
        XCTAssertTrue(rebuilt.configuration.websiteDataStore === customStore)
        XCTAssertEqual(resolverCalls, 2)
        XCTAssertEqual(pool.browserProfileIdentity(for: profile.id), .custom(customID))
    }

    func testInitialCustomProfileResolutionFailureDoesNotCreateRuntimeOrLoad() throws {
        let customID = UUID()
        var defaultResolverCalls = 0
        var customResolverCalls = 0
        var loadCount = 0
        var residentChangeCount = 0
        let provider = BrowserProfileDataStoreProvider(
            isCustomProfileSupported: { false },
            defaultStoreResolver: {
                defaultResolverCalls += 1
                return WKWebsiteDataStore.nonPersistent()
            },
            customStoreResolver: { _ in
                customResolverCalls += 1
                return WKWebsiteDataStore.nonPersistent()
            }
        )
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, _ in loadCount += 1 },
            browserProfileDataStoreProvider: provider
        )
        pool.onResidentSetChange = { residentChangeCount += 1 }
        let profile = makeProfile(name: "UnsupportedInitial", browserProfileID: customID)

        do {
            _ = try pool.webView(for: profile)
            XCTFail("Unsupported custom Profile resolution must fail")
        } catch {
            XCTAssertEqual(
                error as? BrowserProfileDataStoreProviderError,
                .customProfilesUnsupported
            )
        }

        XCTAssertEqual(defaultResolverCalls, 0)
        XCTAssertEqual(customResolverCalls, 0)
        XCTAssertEqual(loadCount, 0)
        XCTAssertEqual(residentChangeCount, 0)
        XCTAssertEqual(pool.count, 0)
        XCTAssertNil(pool.browserProfileIdentity(for: profile.id))
    }

    func testFirstLoadSeesSuppliedStoreAndRecordedBrowserProfileIdentity() throws {
        let customID = UUID()
        let customStore = WKWebsiteDataStore.nonPersistent()
        let provider = BrowserProfileDataStoreProvider(
            isCustomProfileSupported: { true },
            customStoreResolver: { id in
                XCTAssertEqual(id, customID)
                return customStore
            }
        )
        let profile = makeProfile(name: "FirstLoadOrdering", browserProfileID: customID)
        var observedStore: WKWebsiteDataStore?
        var observedIdentity: BrowserProfileIdentity?
        var pool: WebViewPool!
        pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { webView, _ in
                observedStore = webView.configuration.websiteDataStore
                observedIdentity = pool.browserProfileIdentity(for: profile.id)
            },
            browserProfileDataStoreProvider: provider
        )

        _ = try pool.webView(for: profile)

        XCTAssertTrue(observedStore === customStore)
        XCTAssertEqual(observedIdentity, .custom(customID))
    }

    func testBrowserProfileRebuildResolutionFailureRemovesOldRuntimeAndReportsResidency() throws {
        let customID = UUID()
        var customProfilesSupported = true
        var loadedRequests: [URLRequest] = []
        var snapshots: [Set<UUID>] = []
        let provider = BrowserProfileDataStoreProvider(
            isCustomProfileSupported: { customProfilesSupported },
            defaultStoreResolver: { WKWebsiteDataStore.nonPersistent() },
            customStoreResolver: { _ in WKWebsiteDataStore.nonPersistent() }
        )
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, request in loadedRequests.append(request) },
            browserProfileDataStoreProvider: provider
        )
        pool.onResidentSetChange = { snapshots.append(pool.residentSlotIDs) }
        var profile = makeProfile(name: "UnsupportedRebuild")

        _ = try pool.webView(for: profile)
        customProfilesSupported = false
        profile.browserProfileID = customID

        do {
            _ = try pool.webView(for: profile)
            XCTFail("Unsupported custom Profile rebuild must fail")
        } catch {
            XCTAssertEqual(
                error as? BrowserProfileDataStoreProviderError,
                .customProfilesUnsupported
            )
        }

        XCTAssertEqual(snapshots, [[profile.id], []])
        XCTAssertTrue(pool.residentSlotIDs.isEmpty)
        XCTAssertEqual(pool.count, 0)
        XCTAssertEqual(loadedRequests.count, 1)
        XCTAssertNil(pool.browserProfileIdentity(for: profile.id))
    }

    func testRebuildNavigationURLPrefersInitialRequestBeforeRedirectedURL() throws {
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

    func testAutomaticWebsiteModeCanMoveDesktopMobileAndBackWithoutSticking() throws {
        var loadedRequests: [URLRequest] = []
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, request in loadedRequests.append(request) }
        )
        var profile = makeProfile(name: "A")

        let desktop = try pool.webView(for: profile)
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
        let mobile = try pool.webView(for: profile)
        XCTAssertFalse(desktop === mobile)
        XCTAssertEqual(
            mobile.configuration.defaultWebpagePreferences.preferredContentMode,
            .mobile
        )
        XCTAssertTrue(mobile.customUserAgent?.contains("iPhone") == true)
        XCTAssertFalse(mobile.customUserAgent?.contains("Macintosh") == true)

        profile.renderingProfile = profile.renderingProfile.settingWebsiteMode(.desktop)
        let desktopAgain = try pool.webView(for: profile)
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

    func testChatGPTMobileAutomaticUsesDesktopPointerCompatibilityIdentity() throws {
        let pool = makePool()
        var profile = makeProfile(
            name: "ChatGPT",
            homeURL: URL(string: "https://chatgpt.com/")!
        )
        profile.renderingProfile = profile.renderingProfile.settingWebsiteMode(.mobile)

        let webView = try pool.webView(for: profile)

        XCTAssertEqual(
            webView.configuration.defaultWebpagePreferences.preferredContentMode,
            .mobile
        )
        XCTAssertTrue(webView.customUserAgent?.contains("Macintosh") == true)
        XCTAssertFalse(webView.customUserAgent?.contains("iPhone") == true)
    }

    func testChatGPTMobileAutomaticWarmReuseKeepsCompatibilityIdentityWithoutReload() throws {
        var loadedRequests: [URLRequest] = []
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, request in loadedRequests.append(request) }
        )
        var profile = makeProfile(
            name: "ChatGPT",
            homeURL: URL(string: "https://chatgpt.com/")!
        )
        profile.renderingProfile = profile.renderingProfile.settingWebsiteMode(.mobile)

        let first = try pool.webView(for: profile)
        let firstUA = first.customUserAgent
        let second = try pool.webView(for: profile)
        let third = try pool.webView(for: profile)

        XCTAssertTrue(first === second)
        XCTAssertTrue(second === third)
        XCTAssertEqual(loadedRequests.count, 1)
        XCTAssertEqual(second.customUserAgent, firstUA)
        XCTAssertEqual(third.customUserAgent, firstUA)
        XCTAssertTrue(third.customUserAgent?.contains("Macintosh") == true)
        XCTAssertFalse(third.customUserAgent?.contains("iPhone") == true)
    }

    func testDevicePresetChangeDoesNotRebuildOrAlterBrowserIdentity() throws {
        let pool = makePool()
        var profile = makeProfile(name: "A")
        let first = try pool.webView(for: profile)
        let firstUA = first.customUserAgent

        profile.renderingProfile = profile.renderingProfile.settingDevicePreset(id: "iphone-17-pro")
        let second = try pool.webView(for: profile)

        XCTAssertTrue(first === second)
        XCTAssertEqual(second.customUserAgent, firstUA)
        XCTAssertEqual(profile.renderingProfile.websiteMode, .desktop)
        XCTAssertEqual(profile.renderingProfile.viewportSize, CGSize(width: 402, height: 874))
    }

    func testPooledWebViewsUsePersistentWebsiteDataStore() throws {
        let pool = makePool()
        let webView = try pool.webView(for: makeProfile(name: "A"))

        XCTAssertTrue(webView.configuration.websiteDataStore.isPersistent)
    }

    func testPooledWebViewsInstallPopupCoordinator() throws {
        let pool = makePool()
        let webView = try pool.webView(for: makeProfile(name: "A"))

        XCTAssertTrue(webView.uiDelegate is PopupCoordinator)
    }

    func testRemovingOneSlotDoesNotAffectOtherWebViewIdentity() throws {
        let pool = makePool()
        let first = makeProfile(name: "A")
        let second = makeProfile(name: "B")
        _ = try pool.webView(for: first)
        let secondView = try pool.webView(for: second)

        pool.remove(slotID: first.id)

        XCTAssertFalse(pool.contains(slotID: first.id))
        XCTAssertTrue(pool.contains(slotID: second.id))
        XCTAssertTrue(try pool.webView(for: second) === secondView)
        XCTAssertEqual(pool.count, 1)
    }

    func testColdReleaseDropsOnlyRequestedLiveWebView() throws {
        let pool = makePool()
        let first = makeProfile(name: "A")
        let second = makeProfile(name: "B")
        _ = try pool.webView(for: first)
        let secondView = try pool.webView(for: second)

        pool.release(slotID: first.id)

        XCTAssertFalse(pool.contains(slotID: first.id))
        XCTAssertTrue(pool.contains(slotID: second.id))
        XCTAssertTrue(try pool.webView(for: second) === secondView)
        XCTAssertEqual(pool.count, 1)
    }

    func testResidentSetChangeTracksActualLiveWebViews() throws {
        let pool = makePool()
        let profile = makeProfile(name: "Resident")
        var snapshots: [Set<UUID>] = []
        pool.onResidentSetChange = { snapshots.append(pool.residentSlotIDs) }

        _ = try pool.webView(for: profile)
        XCTAssertEqual(pool.residentSlotIDs, [profile.id])
        pool.release(slotID: profile.id)

        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots.first, [profile.id])
        XCTAssertEqual(snapshots.last, [])
    }

    func testColdLifecycleReleasesAfterGracePeriod() async throws {
        let pool = makePool()
        var profile = makeProfile(name: "Cold")
        profile.residencyPolicy = .cold
        _ = try pool.webView(for: profile)
        let container = WebPanelContainerView(frame: NSRect(x: 0, y: 0, width: 430, height: 820))
        let lifecycle = SlotLifecycleCoordinator(
            webViewPool: pool,
            container: container,
            coldReleaseDelay: 0.01
        )

        lifecycle.activate(profile: profile)
        lifecycle.deactivate(profile: profile)

        XCTAssertTrue(pool.contains(slotID: profile.id))
        XCTAssertEqual(lifecycle.pendingColdReleaseCount, 1)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(pool.contains(slotID: profile.id))
        XCTAssertEqual(lifecycle.pendingColdReleaseCount, 0)
    }

    func testColdLifecycleNotifiesOnlyAfterWebViewRuntimeIsReleased() async throws {
        let pool = makePool()
        var profile = makeProfile(name: "ColdCacheRelease")
        profile.residencyPolicy = .cold
        _ = try pool.webView(for: profile)
        let container = WebPanelContainerView(frame: NSRect(x: 0, y: 0, width: 430, height: 820))
        var notifiedProfile: WebAppProfile?
        var poolWasStillResidentAtNotification = true
        let lifecycle = SlotLifecycleCoordinator(
            webViewPool: pool,
            container: container,
            coldReleaseDelay: 0.01,
            onRuntimeReleased: { releasedProfile in
                notifiedProfile = releasedProfile
                poolWasStillResidentAtNotification = pool.contains(slotID: releasedProfile.id)
            },
            installsMemoryPressureSource: false
        )

        lifecycle.activate(profile: profile)
        lifecycle.deactivate(profile: profile)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(notifiedProfile?.id, profile.id)
        XCTAssertFalse(poolWasStillResidentAtNotification)
    }

    func testColdLifecycleActivationCancelsPendingRelease() async throws {
        let pool = makePool()
        var profile = makeProfile(name: "ColdCancel")
        profile.residencyPolicy = .cold
        _ = try pool.webView(for: profile)
        let container = WebPanelContainerView(frame: NSRect(x: 0, y: 0, width: 430, height: 820))
        let lifecycle = SlotLifecycleCoordinator(
            webViewPool: pool,
            container: container,
            coldReleaseDelay: 0.01
        )

        lifecycle.activate(profile: profile)
        lifecycle.deactivate(profile: profile)
        XCTAssertEqual(lifecycle.pendingColdReleaseCount, 1)

        lifecycle.activate(profile: profile)
        XCTAssertEqual(lifecycle.pendingColdReleaseCount, 0)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(pool.contains(slotID: profile.id))
    }

    func testFullscreenCompanionVisibilityCancelsPendingColdRelease() async throws {
        let pool = makePool()
        var source = makeProfile(name: "FullscreenSource")
        source.residencyPolicy = .hot
        var companion = makeProfile(name: "Companion")
        companion.residencyPolicy = .cold
        _ = try pool.webView(for: source)
        _ = try pool.webView(for: companion)
        let container = WebPanelContainerView(
            frame: NSRect(x: 0, y: 0, width: 430, height: 820)
        )
        let lifecycle = SlotLifecycleCoordinator(
            webViewPool: pool,
            container: container,
            coldReleaseDelay: 0.01,
            installsMemoryPressureSource: false
        )

        lifecycle.activate(profile: companion)
        lifecycle.deactivate(profile: companion)
        lifecycle.activate(profile: source)
        XCTAssertEqual(lifecycle.pendingColdReleaseCount, 1)

        lifecycle.beginSupplementalVisibility(profile: companion)

        XCTAssertEqual(lifecycle.pendingColdReleaseCount, 0)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(pool.contains(slotID: companion.id))
    }

    func testHiddenShellNeverPausesOrReleasesVisibleFullscreenSource() async throws {
        let pool = makePool()
        var source = makeProfile(name: "FullscreenSource")
        source.residencyPolicy = .cold
        source.backgroundMediaPolicy = .pauseWhenInactive
        _ = try pool.webView(for: source)
        let container = WebPanelContainerView(
            frame: NSRect(x: 0, y: 0, width: 430, height: 820)
        )
        var pausedIDs: [UUID] = []
        let lifecycle = SlotLifecycleCoordinator(
            webViewPool: pool,
            container: container,
            coldReleaseDelay: 0.01,
            hiddenActiveGraceDelay: 0.02,
            mediaPauseAction: { pausedIDs.append($0) },
            installsMemoryPressureSource: false
        )

        lifecycle.setPanelVisible(true, activeProfile: source)
        lifecycle.activate(profile: source)
        lifecycle.beginFullscreenSourceVisibility(profile: source)
        lifecycle.setPanelVisible(false, activeProfile: source)

        XCTAssertTrue(pausedIDs.isEmpty)
        XCTAssertFalse(lifecycle.isHiddenActiveGracePending)
        XCTAssertEqual(lifecycle.pendingColdReleaseCount, 0)
        try await Task.sleep(nanoseconds: 70_000_000)
        XCTAssertTrue(pool.contains(slotID: source.id))

        // Once WebKit exits fullscreen, the same hidden source returns to the
        // ordinary pause + grace + Cold release contract.
        lifecycle.endFullscreenSourceVisibility(profile: source)
        lifecycle.setPanelVisible(false, activeProfile: source)
        XCTAssertEqual(pausedIDs, [source.id])
        XCTAssertTrue(lifecycle.isHiddenActiveGracePending)
        try await Task.sleep(nanoseconds: 70_000_000)
        XCTAssertFalse(pool.contains(slotID: source.id))
    }

    func testHiddenFullscreenCompanionReturnsToInactiveLifecycle() async throws {
        let pool = makePool()
        var source = makeProfile(name: "FullscreenSource")
        source.residencyPolicy = .hot
        var companion = makeProfile(name: "Companion")
        companion.residencyPolicy = .cold
        _ = try pool.webView(for: source)
        _ = try pool.webView(for: companion)
        let container = WebPanelContainerView(
            frame: NSRect(x: 0, y: 0, width: 430, height: 820)
        )
        let lifecycle = SlotLifecycleCoordinator(
            webViewPool: pool,
            container: container,
            coldReleaseDelay: 0.01,
            installsMemoryPressureSource: false
        )
        lifecycle.activate(profile: source)
        lifecycle.beginSupplementalVisibility(profile: companion)

        lifecycle.endSupplementalVisibility(
            profile: companion,
            prepareAsInactive: true
        )

        XCTAssertEqual(lifecycle.pendingColdReleaseCount, 1)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(pool.contains(slotID: companion.id))
    }

    func testResourceLifecycleDefaultTimingsMatchAcceptedContract() throws {
        XCTAssertEqual(SlotLifecycleCoordinator.defaultColdReleaseDelay, 30)
        XCTAssertEqual(SlotLifecycleCoordinator.defaultWarmReleaseDelay, 120)
        XCTAssertEqual(SlotLifecycleCoordinator.defaultHiddenActiveGraceDelay, 120)
        XCTAssertEqual(SlotLifecycleCoordinator.defaultWarmResidentLimit, 2)
    }

    func testWarmLifecycleDoesNotScheduleColdRelease() async throws {
        let pool = makePool()
        var profile = makeProfile(name: "Warm")
        profile.residencyPolicy = .warm
        _ = try pool.webView(for: profile)
        let container = WebPanelContainerView(frame: NSRect(x: 0, y: 0, width: 430, height: 820))
        let lifecycle = SlotLifecycleCoordinator(
            webViewPool: pool,
            container: container,
            coldReleaseDelay: 0.01
        )

        lifecycle.activate(profile: profile)
        lifecycle.deactivate(profile: profile)

        XCTAssertEqual(lifecycle.pendingColdReleaseCount, 0)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(pool.contains(slotID: profile.id))
    }

    func testWarmLifecycleReleasesAfterWarmTTL() async throws {
        let pool = makePool()
        var profile = makeProfile(name: "WarmTTL")
        profile.residencyPolicy = .warm
        _ = try pool.webView(for: profile)
        let container = WebPanelContainerView(frame: NSRect(x: 0, y: 0, width: 430, height: 820))
        let lifecycle = SlotLifecycleCoordinator(
            webViewPool: pool,
            container: container,
            warmReleaseDelay: 0.01,
            mediaPlayingQuery: { _, completion in completion(false) },
            installsMemoryPressureSource: false
        )
        lifecycle.setPanelVisible(true, activeProfile: nil)
        lifecycle.activate(profile: profile)
        lifecycle.deactivate(profile: profile)

        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 1)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(pool.contains(slotID: profile.id))
    }

    func testWarmLRULimitKeepsOnlyTwoRecentInactiveResidents() throws {
        let pool = makePool()
        let profiles = ["A", "B", "C"].enumerated().map { index, name in
            var profile = makeProfile(name: name)
            profile.order = index
            profile.residencyPolicy = .warm
            return profile
        }
        for profile in profiles {
            _ = try pool.webView(for: profile)
        }
        let container = WebPanelContainerView(frame: NSRect(x: 0, y: 0, width: 430, height: 820))
        let lifecycle = SlotLifecycleCoordinator(
            webViewPool: pool,
            container: container,
            warmReleaseDelay: 60,
            warmResidentLimit: 2,
            mediaPlayingQuery: { _, completion in completion(false) },
            installsMemoryPressureSource: false
        )
        lifecycle.setPanelVisible(true, activeProfile: nil)

        for profile in profiles {
            lifecycle.activate(profile: profile)
            lifecycle.deactivate(profile: profile)
        }

        XCTAssertEqual(pool.count, 2)
        XCTAssertFalse(pool.contains(slotID: profiles[0].id))
        XCTAssertTrue(pool.contains(slotID: profiles[1].id))
        XCTAssertTrue(pool.contains(slotID: profiles[2].id))
    }

    func testBackgroundAudioPlayingProtectsColdUntilPlaybackStopsThenStartsFreshGrace() async throws {
        let pool = makePool()
        var profile = makeProfile(name: "MediaCold")
        profile.residencyPolicy = .cold
        profile.backgroundMediaPolicy = .allowBackgroundAudio
        _ = try pool.webView(for: profile)
        var isPlaying = true
        let container = WebPanelContainerView(frame: NSRect(x: 0, y: 0, width: 430, height: 820))
        let lifecycle = SlotLifecycleCoordinator(
            webViewPool: pool,
            container: container,
            coldReleaseDelay: 0.05,
            mediaProtectionPollDelay: 0.005,
            mediaPlayingQuery: { _, completion in completion(isPlaying) },
            installsMemoryPressureSource: false
        )
        lifecycle.setPanelVisible(true, activeProfile: nil)
        lifecycle.activate(profile: profile)
        lifecycle.deactivate(profile: profile)

        try await Task.sleep(nanoseconds: 70_000_000)
        XCTAssertTrue(pool.contains(slotID: profile.id))
        XCTAssertTrue(lifecycle.mediaProtectedIDs.contains(profile.id))

        isPlaying = false
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertTrue(pool.contains(slotID: profile.id), "stopping playback starts a fresh Cold grace period")
        try await Task.sleep(nanoseconds: 70_000_000)
        XCTAssertFalse(pool.contains(slotID: profile.id))
    }

    func testHiddenSelectedColdGetsRecentActiveGraceBeforeColdRelease() async throws {
        let pool = makePool()
        var profile = makeProfile(name: "HiddenCold")
        profile.residencyPolicy = .cold
        _ = try pool.webView(for: profile)
        let container = WebPanelContainerView(frame: NSRect(x: 0, y: 0, width: 430, height: 820))
        let lifecycle = SlotLifecycleCoordinator(
            webViewPool: pool,
            container: container,
            coldReleaseDelay: 0.01,
            hiddenActiveGraceDelay: 0.02,
            mediaPlayingQuery: { _, completion in completion(false) },
            installsMemoryPressureSource: false
        )
        lifecycle.setPanelVisible(true, activeProfile: profile)
        lifecycle.activate(profile: profile)
        lifecycle.setPanelVisible(false, activeProfile: profile)

        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertTrue(pool.contains(slotID: profile.id))
        XCTAssertTrue(lifecycle.isHiddenActiveGracePending)
        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertFalse(pool.contains(slotID: profile.id))
    }

    func testHiddenSelectedDefaultMediaPausesImmediatelyBeforeRetentionGrace() throws {
        let pool = makePool()
        var profile = makeProfile(name: "HiddenPause")
        profile.residencyPolicy = .hot
        profile.backgroundMediaPolicy = .pauseWhenInactive
        _ = try pool.webView(for: profile)
        let container = WebPanelContainerView(
            frame: NSRect(x: 0, y: 0, width: 430, height: 820)
        )
        var pausedIDs: [UUID] = []
        let lifecycle = SlotLifecycleCoordinator(
            webViewPool: pool,
            container: container,
            mediaPauseAction: { pausedIDs.append($0) },
            installsMemoryPressureSource: false
        )
        lifecycle.setPanelVisible(true, activeProfile: profile)
        lifecycle.activate(profile: profile)

        lifecycle.setPanelVisible(false, activeProfile: profile)

        XCTAssertEqual(pausedIDs, [profile.id])
        XCTAssertTrue(pool.contains(slotID: profile.id), "pause does not change Hot residency")
    }

    func testHiddenSelectedBackgroundAudioDoesNotPause() throws {
        let pool = makePool()
        var profile = makeProfile(name: "HiddenBackgroundAudio")
        profile.residencyPolicy = .hot
        profile.backgroundMediaPolicy = .allowBackgroundAudio
        _ = try pool.webView(for: profile)
        let container = WebPanelContainerView(
            frame: NSRect(x: 0, y: 0, width: 430, height: 820)
        )
        var pausedIDs: [UUID] = []
        let lifecycle = SlotLifecycleCoordinator(
            webViewPool: pool,
            container: container,
            mediaPauseAction: { pausedIDs.append($0) },
            installsMemoryPressureSource: false
        )
        lifecycle.setPanelVisible(true, activeProfile: profile)
        lifecycle.activate(profile: profile)

        lifecycle.setPanelVisible(false, activeProfile: profile)

        XCTAssertTrue(pausedIDs.isEmpty)
    }

    func testShowingPanelCancelsHiddenActiveEviction() async throws {
        let pool = makePool()
        var profile = makeProfile(name: "HiddenCancel")
        profile.residencyPolicy = .cold
        _ = try pool.webView(for: profile)
        let container = WebPanelContainerView(frame: NSRect(x: 0, y: 0, width: 430, height: 820))
        let lifecycle = SlotLifecycleCoordinator(
            webViewPool: pool,
            container: container,
            coldReleaseDelay: 0.01,
            hiddenActiveGraceDelay: 0.03,
            mediaPlayingQuery: { _, completion in completion(false) },
            installsMemoryPressureSource: false
        )
        lifecycle.setPanelVisible(true, activeProfile: profile)
        lifecycle.activate(profile: profile)
        lifecycle.setPanelVisible(false, activeProfile: profile)
        try await Task.sleep(nanoseconds: 5_000_000)
        lifecycle.setPanelVisible(true, activeProfile: profile)

        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertTrue(pool.contains(slotID: profile.id))
        XCTAssertFalse(lifecycle.isHiddenActiveGracePending)
    }

    func testCriticalMemoryPressureEvictsInactiveWarmButNeverPlayingProtectedWarm() throws {
        let pool = makePool()
        var normal = makeProfile(name: "NormalWarm")
        normal.residencyPolicy = .warm
        var playing = makeProfile(name: "PlayingWarm")
        playing.residencyPolicy = .warm
        playing.backgroundMediaPolicy = .allowBackgroundAudio
        _ = try pool.webView(for: normal)
        _ = try pool.webView(for: playing)
        let container = WebPanelContainerView(frame: NSRect(x: 0, y: 0, width: 430, height: 820))
        let lifecycle = SlotLifecycleCoordinator(
            webViewPool: pool,
            container: container,
            warmReleaseDelay: 60,
            mediaPlayingQuery: { slotID, completion in completion(slotID == playing.id) },
            installsMemoryPressureSource: false
        )
        lifecycle.setPanelVisible(true, activeProfile: nil)
        lifecycle.activate(profile: normal)
        lifecycle.deactivate(profile: normal)
        lifecycle.activate(profile: playing)
        lifecycle.deactivate(profile: playing)

        lifecycle.handleMemoryPressure(.critical)

        XCTAssertFalse(pool.contains(slotID: normal.id))
        XCTAssertTrue(pool.contains(slotID: playing.id))
        XCTAssertTrue(lifecycle.mediaProtectedIDs.contains(playing.id))
    }

    func testWebContentRecoveryPolicyReloadsActiveAndDefersInactiveSlots() throws {
        XCTAssertEqual(
            WebViewPool.recoveryDisposition(isActive: true),
            .reloadNow
        )
        XCTAssertEqual(
            WebViewPool.recoveryDisposition(isActive: false),
            .deferUntilActivation
        )
    }

    func testActiveWebContentTerminationReloadsLastKnownURLImmediately() throws {
        var loadedRequests: [URLRequest] = []
        var profile = makeProfile(name: "A")
        profile.currentURL = URL(string: "https://example.com/current")!
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, request in loadedRequests.append(request) },
            isSlotActive: { _ in true }
        )

        _ = try pool.webView(for: profile)
        pool.handleContentProcessTermination(slotID: profile.id)

        XCTAssertEqual(loadedRequests.count, 2)
        XCTAssertEqual(loadedRequests.last?.url, profile.currentURL)
        XCTAssertEqual(loadedRequests.last?.cachePolicy, .useProtocolCachePolicy)
    }

    func testInactiveWebContentTerminationDefersReloadUntilSlotActivation() throws {
        var loadedRequests: [URLRequest] = []
        var isActive = false
        var profile = makeProfile(name: "A")
        profile.currentURL = URL(string: "https://example.com/current")!
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, request in loadedRequests.append(request) },
            isSlotActive: { _ in isActive }
        )

        let original = try pool.webView(for: profile)
        pool.handleContentProcessTermination(slotID: profile.id)
        XCTAssertEqual(loadedRequests.count, 1)

        isActive = true
        let recovered = try pool.webView(for: profile)

        XCTAssertTrue(original === recovered)
        XCTAssertEqual(loadedRequests.count, 2)
        XCTAssertEqual(loadedRequests.last?.url, profile.currentURL)
        XCTAssertEqual(loadedRequests.last?.cachePolicy, .useProtocolCachePolicy)
    }

    func testSlotNavigationObserverSurfacesContentProcessTermination() throws {
        let webView = WebViewFactory.makeWebView()
        let slotID = UUID()
        var terminatedSlotID: UUID?
        let observer = SlotNavigationObserver(
            slotID: slotID,
            webView: webView,
            websiteMode: .desktop,
            onURLChange: { _, _ in },
            onContentProcessTermination: { terminatedSlotID = $0 }
        )

        observer.webViewWebContentProcessDidTerminate(webView)

        XCTAssertEqual(terminatedSlotID, slotID)
    }

    func testNavigationCoordinatorKeepsSameSiteBlankInCurrentSlot() throws {
        let result = WebNavigationCoordinator.disposition(
            hasTargetFrame: false,
            sourceURL: URL(string: "https://www.bilibili.com/"),
            targetURL: URL(string: "https://bilibili.com/video/BV123")
        )

        XCTAssertEqual(result, .loadInCurrentSlot)
    }

    func testNavigationCoordinatorKeepsCrossSiteUserBlankInCurrentSlot() throws {
        let result = WebNavigationCoordinator.disposition(
            hasTargetFrame: false,
            navigationType: .linkActivated,
            sourceURL: URL(string: "https://example.com/article"),
            targetURL: URL(string: "https://developer.apple.com/documentation")
        )

        XCTAssertEqual(result, .loadInCurrentSlot)
    }

    func testNavigationCoordinatorLetsScriptedBlankReachUIDelegate() throws {
        let result = WebNavigationCoordinator.disposition(
            hasTargetFrame: false,
            navigationType: .other,
            sourceURL: URL(string: "https://example.com/article"),
            targetURL: URL(string: "https://accounts.example-idp.com/oauth")
        )

        XCTAssertEqual(result, .allow)
    }

    func testNavigationCoordinatorAllowsNormalInFrameNavigation() throws {
        let result = WebNavigationCoordinator.disposition(
            hasTargetFrame: true,
            sourceURL: URL(string: "https://example.com"),
            targetURL: URL(string: "https://example.com/next")
        )

        XCTAssertEqual(result, .allow)
    }

    func testPopupRoutingKeepsSameSiteContextInCurrentSlot() throws {
        let result = PopupCoordinator.disposition(
            navigationType: .linkActivated,
            sourceURL: URL(string: "https://www.bilibili.com/"),
            targetURL: URL(string: "https://bilibili.com/video/BV123")
        )

        XCTAssertEqual(result, .currentSlot)
    }

    func testPopupRoutingKeepsCrossSiteUserLinkInCurrentSlot() throws {
        let result = PopupCoordinator.disposition(
            navigationType: .linkActivated,
            sourceURL: URL(string: "https://example.com"),
            targetURL: URL(string: "https://developer.apple.com")
        )

        XCTAssertEqual(result, .currentSlot)
    }

    func testPopupRoutingPreservesScriptedCrossSitePopupContext() throws {
        let result = PopupCoordinator.disposition(
            navigationType: .other,
            sourceURL: URL(string: "https://example.com"),
            targetURL: URL(string: "https://accounts.example-idp.com/oauth")
        )

        XCTAssertEqual(result, .popup)
    }

    func testPopupRoutingKeepsScriptedVideoPageInCurrentSlot() throws {
        let result = PopupCoordinator.disposition(
            navigationType: .other,
            sourceURL: URL(string: "https://v.qq.com/"),
            targetURL: URL(string: "https://v.qq.com/x/cover/abc/video.html")
        )

        XCTAssertEqual(result, .currentSlot)
    }

    func testPopupRoutingKeepsOrdinaryScriptedAboutBlankInCurrentSlot() throws {
        let result = PopupCoordinator.disposition(
            navigationType: .other,
            sourceURL: URL(string: "https://example.com"),
            targetURL: URL(string: "about:blank")
        )

        XCTAssertEqual(result, .currentSlot)
    }

    func testPopupRoutingKeepsScriptedMissingInitialURLInCurrentSlot() throws {
        let result = PopupCoordinator.disposition(
            navigationType: .other,
            sourceURL: URL(string: "https://v.qq.com"),
            targetURL: nil
        )

        XCTAssertEqual(result, .currentSlot)
    }

    func testPopupRoutingPreservesGoogleAuthenticationPopup() throws {
        let result = PopupCoordinator.disposition(
            navigationType: .other,
            sourceURL: URL(string: "https://gemini.google.com/"),
            targetURL: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")
        )

        XCTAssertEqual(result, .popup)
    }

    func testPopupRoutingPreservesBlankAuthenticationChildPopup() throws {
        let result = PopupCoordinator.disposition(
            navigationType: .other,
            sourceURL: URL(string: "https://example-idp.com/login"),
            targetURL: URL(string: "about:blank")
        )

        XCTAssertEqual(result, .popup)
    }

    func testAuthenticationURLClassifierDoesNotTreatTencentVideoAsLogin() throws {
        XCTAssertFalse(
            PopupCoordinator.isAuthenticationURL(
                URL(string: "https://v.qq.com/x/cover/abc/video.html")
            )
        )
        XCTAssertTrue(
            PopupCoordinator.isAuthenticationURL(
                URL(string: "https://v.qq.com/login")
            )
        )
    }

    func testPopupRoutingHandsNonWebSchemeToSystem() throws {
        let result = PopupCoordinator.disposition(
            navigationType: .linkActivated,
            sourceURL: URL(string: "https://example.com"),
            targetURL: URL(string: "mailto:test@example.com")
        )

        XCTAssertEqual(result, .externalBrowser)
    }

    func testExplicitLinkContextMenuOffersUserControlledDestinations() throws {
        let webView = WebViewFactory.makeWebView()
        let coordinator = LinkContextMenuCoordinator(
            webView: webView,
            openFloating: { _, _ in },
            openExternal: { _ in }
        )
        let url = URL(string: "https://developer.apple.com/documentation")!
        let menu = coordinator.menu(for: url, sourceWebView: webView)
        let actionTitles = menu.items.filter { !$0.isSeparatorItem }.map(\.title)
        let script = LinkContextMenuCoordinator.userScript()

        XCTAssertEqual(
            actionTitles,
            ["Open in Floating Window", "Open in Default Browser", "Copy Link"]
        )
        XCTAssertEqual(script.injectionTime, .atDocumentStart)
        XCTAssertFalse(script.isForMainFrameOnly)
        XCTAssertTrue(script.source.contains("contextmenu"))
        XCTAssertTrue(script.source.contains(LinkContextMenuCoordinator.handlerName))
        coordinator.invalidate()
    }

    func testExplicitUserFloatingWindowKeepsPersistentSessionAndSourceIdentity() throws {
        let source = WebViewFactory.makeWebView()
        source.customUserAgent = "FloatTabs-Test-UA/1.0"
        let coordinator = PopupCoordinator(parentWebView: source)
        let url = URL(string: "https://example.invalid/floating")!

        let floating = try! XCTUnwrap(
            coordinator.openUserFloatingWindow(url, from: source)
        )

        XCTAssertTrue(floating.configuration.websiteDataStore.isPersistent)
        XCTAssertEqual(floating.customUserAgent, source.customUserAgent)
        XCTAssertEqual(coordinator.userFloatingWindowCount, 1)
        coordinator.closeAll()
    }

    func testUploadPanelPolicyForSingleFile() throws {
        let policy = UploadPanelPolicy.make(
            allowsMultipleSelection: false,
            allowsDirectories: false
        )

        XCTAssertFalse(policy.allowsMultipleSelection)
        XCTAssertTrue(policy.canChooseFiles)
        XCTAssertFalse(policy.canChooseDirectories)
    }

    func testUploadPanelPolicyForMultipleFiles() throws {
        let policy = UploadPanelPolicy.make(
            allowsMultipleSelection: true,
            allowsDirectories: false
        )

        XCTAssertTrue(policy.allowsMultipleSelection)
        XCTAssertTrue(policy.canChooseFiles)
        XCTAssertFalse(policy.canChooseDirectories)
    }

    func testUploadPanelPolicyForDirectory() throws {
        let policy = UploadPanelPolicy.make(
            allowsMultipleSelection: true,
            allowsDirectories: true
        )

        XCTAssertTrue(policy.allowsMultipleSelection)
        XCTAssertFalse(policy.canChooseFiles)
        XCTAssertTrue(policy.canChooseDirectories)
    }

    func testExplicitDownloadActionUsesDownloadPolicy() throws {
        XCTAssertEqual(
            DownloadCoordinator.actionPolicy(shouldPerformDownload: true),
            .download
        )
        XCTAssertEqual(
            DownloadCoordinator.actionPolicy(shouldPerformDownload: false),
            .allow
        )
    }

    func testUnshowableMimeResponseUsesDownloadPolicy() throws {
        XCTAssertEqual(
            DownloadCoordinator.responsePolicy(canShowMIMEType: false),
            .download
        )
        XCTAssertEqual(
            DownloadCoordinator.responsePolicy(canShowMIMEType: true),
            .allow
        )
    }

    func testDownloadSuggestedFilenameDropsPathComponents() throws {
        XCTAssertEqual(
            DownloadCoordinator.safeSuggestedFilename("nested/path/report.txt"),
            "report.txt"
        )
        XCTAssertEqual(
            DownloadCoordinator.safeSuggestedFilename(""),
            "Download"
        )
    }

    // MARK: - HTTPS entry fallback to HTTP (inferred scheme, non-443 ports)

    func testHostAppAllowsCleartextOnlyForWebContent() throws {
        let ats = Bundle.main.object(
            forInfoDictionaryKey: "NSAppTransportSecurity"
        ) as? [String: Any]
        XCTAssertEqual(ats?["NSAllowsArbitraryLoadsInWebContent"] as? Bool, true)
        XCTAssertNil(ats?["NSAllowsArbitraryLoads"])
    }

    func testURLNormalizationTracksInferredVersusExplicitScheme() throws {
        let inferred = WebAppURL.normalizedEntry(from: "nas.example.com:3010")
        XCTAssertEqual(inferred?.url, URL(string: "https://nas.example.com:3010"))
        XCTAssertEqual(inferred?.schemeWasInferred, true)

        let explicitHTTPS = WebAppURL.normalizedEntry(from: "https://nas.example.com:3010")
        XCTAssertEqual(explicitHTTPS?.url, URL(string: "https://nas.example.com:3010"))
        XCTAssertEqual(explicitHTTPS?.schemeWasInferred, false)

        let explicitHTTP = WebAppURL.normalizedEntry(from: "http://nas.example.com:3010")
        XCTAssertEqual(explicitHTTP?.url, URL(string: "http://nas.example.com:3010"))
        XCTAssertEqual(explicitHTTP?.schemeWasInferred, false)
    }

    func testHTTPFallbackCandidateRequiresNon443HTTPSShape() throws {
        XCTAssertEqual(
            WebAppURL.httpFallbackCandidate(for: URL(string: "https://nas.example.com:3010/")!),
            URL(string: "http://nas.example.com:3010/")
        )
        XCTAssertNil(WebAppURL.httpFallbackCandidate(for: URL(string: "https://example.com")!))
        XCTAssertNil(WebAppURL.httpFallbackCandidate(for: URL(string: "https://example.com:443")!))
        XCTAssertNil(WebAppURL.httpFallbackCandidate(for: URL(string: "http://nas.example.com:3010")!))
    }

    func testHTTPFallbackDecisionRequiresConnectionFailureAndMatchingURL() throws {
        let pending = URL(string: "https://nas.example.com:3010")!
        let connectionFailures = [
            NSURLErrorTimedOut,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorSecureConnectionFailed,
        ]
        for code in connectionFailures {
            let error = NSError(
                domain: NSURLErrorDomain,
                code: code,
                userInfo: ["NSErrorFailingURLStringKey": pending.absoluteString]
            )
            XCTAssertEqual(
                SlotNavigationObserver.httpFallbackURL(
                    pending: pending,
                    failingURL: URL(string: pending.absoluteString),
                    error: error
                ),
                URL(string: "http://nas.example.com:3010"),
                "expected fallback for \(code)"
            )
        }

        let certificateError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorServerCertificateUntrusted,
            userInfo: ["NSErrorFailingURLStringKey": pending.absoluteString]
        )
        XCTAssertNil(SlotNavigationObserver.httpFallbackURL(
            pending: pending,
            failingURL: pending,
            error: certificateError
        ))

        XCTAssertNil(SlotNavigationObserver.httpFallbackURL(
            pending: pending,
            failingURL: URL(string: "https://other.example.com:3010"),
            error: NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)
        ))
        XCTAssertNil(SlotNavigationObserver.httpFallbackURL(
            pending: nil,
            failingURL: pending,
            error: NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)
        ))
        XCTAssertNil(SlotNavigationObserver.httpFallbackURL(
            pending: pending,
            failingURL: pending,
            error: NSError(domain: "OtherDomain", code: 1)
        ))
    }

    func testObserverFallsBackToHTTPOnceOnlyWhenCallerAllowsInferredEntry() throws {
        let webView = WKWebView(frame: .zero)
        var loadedURLs: [URL] = []
        let observer = SlotNavigationObserver(
            slotID: UUID(),
            webView: webView,
            websiteMode: .desktop,
            onURLChange: { _, _ in },
            loadHandler: { _, url in loadedURLs.append(url) }
        )

        let entry = URL(string: "https://nas.example.com:3010")!
        observer.configureHTTPEntryFallback(for: entry, allowed: true)
        XCTAssertTrue(observer.isHTTPEntryFallbackPending)

        observer.webView(
            webView,
            didFailProvisionalNavigation: nil,
            withError: NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorSecureConnectionFailed,
                userInfo: ["NSErrorFailingURLStringKey": entry.absoluteString]
            )
        )

        XCTAssertEqual(loadedURLs, [URL(string: "http://nas.example.com:3010")!])
        XCTAssertFalse(observer.isHTTPEntryFallbackPending)

        observer.webView(
            webView,
            didFailProvisionalNavigation: nil,
            withError: NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorSecureConnectionFailed,
                userInfo: ["NSErrorFailingURLStringKey": entry.absoluteString]
            )
        )
        XCTAssertEqual(loadedURLs.count, 1)
    }

    func testObserverNeverArmsFallbackForExplicitHTTPSPermissionFalse() throws {
        let observer = SlotNavigationObserver(
            slotID: UUID(),
            webView: WKWebView(frame: .zero),
            websiteMode: .desktop,
            onURLChange: { _, _ in }
        )
        let entry = URL(string: "https://nas.example.com:3010")!

        observer.configureHTTPEntryFallback(for: entry, allowed: false)

        XCTAssertFalse(observer.isHTTPEntryFallbackPending)
    }

    func testObserverCommitCancelsPendingEntryFallback() throws {
        let webView = WKWebView(frame: .zero)
        var loadedURLs: [URL] = []
        let observer = SlotNavigationObserver(
            slotID: UUID(),
            webView: webView,
            websiteMode: .desktop,
            onURLChange: { _, _ in },
            loadHandler: { _, url in loadedURLs.append(url) }
        )

        let entry = URL(string: "https://nas.example.com:3010")!
        observer.configureHTTPEntryFallback(for: entry, allowed: true)
        observer.webView(webView, didCommit: nil)

        observer.webView(
            webView,
            didFailProvisionalNavigation: nil,
            withError: NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorCannotConnectToHost,
                userInfo: ["NSErrorFailingURLStringKey": entry.absoluteString]
            )
        )

        XCTAssertTrue(loadedURLs.isEmpty)
        XCTAssertFalse(observer.isHTTPEntryFallbackPending)
    }

    func testPoolNavigationRequiresExplicitFallbackPermission() throws {
        let pool = makePool()
        let profile = makeProfile(name: "A")
        _ = try pool.webView(for: profile)
        let nonStandardPort = URL(string: "https://nas.example.com:3010")!

        pool.navigate(slotID: profile.id, to: nonStandardPort)
        XCTAssertFalse(pool.isHTTPEntryFallbackPending(slotID: profile.id))

        pool.navigate(
            slotID: profile.id,
            to: nonStandardPort,
            allowHTTPEntryFallback: true
        )
        XCTAssertTrue(pool.isHTTPEntryFallbackPending(slotID: profile.id))

        pool.navigate(slotID: profile.id, to: URL(string: "https://example.com")!)
        XCTAssertFalse(pool.isHTTPEntryFallbackPending(slotID: profile.id))
    }

    func testPoolInitialHomeFallbackRequiresPersistedInferredScheme() throws {
        let pool = makePool()
        let inferred = makeProfile(
            name: "NAS",
            homeURL: URL(string: "https://nas.example.com:3010")!,
            homeURLSchemeWasInferred: true
        )
        _ = try pool.webView(for: inferred)
        XCTAssertTrue(pool.isHTTPEntryFallbackPending(slotID: inferred.id))

        let explicit = makeProfile(
            name: "ExplicitNAS",
            homeURL: URL(string: "https://nas.example.com:3010")!,
            homeURLSchemeWasInferred: false
        )
        _ = try pool.webView(for: explicit)
        XCTAssertFalse(pool.isHTTPEntryFallbackPending(slotID: explicit.id))
    }

    func testPageCurrentURLDoesNotRegainFallbackAfterRuntimeRecreation() throws {
        let pool = makePool()
        var profile = makeProfile(
            name: "NAS",
            homeURL: URL(string: "https://nas.example.com:3010")!,
            homeURLSchemeWasInferred: true
        )
        profile.currentURL = URL(string: "https://nas.example.com:3010/account")!

        _ = try pool.webView(for: profile)

        XCTAssertFalse(pool.isHTTPEntryFallbackPending(slotID: profile.id))
    }

    func testProfilePersistsHomeURLSchemeProvenance() throws {
        let profile = makeProfile(
            name: "NAS",
            homeURL: URL(string: "https://nas.example.com:3010")!,
            homeURLSchemeWasInferred: true
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(WebAppProfile.self, from: data)

        XCTAssertTrue(decoded.homeURLSchemeWasInferred)
        XCTAssertEqual(decoded.homeURL, profile.homeURL)
    }

    private func makePool() -> WebViewPool {
        WebViewPool(onURLChange: { _, _ in }, initialLoad: { _, _ in })
    }

    private func makeProfile(
        name: String,
        browserProfileID: UUID? = nil,
        homeURL: URL? = nil,
        homeURLSchemeWasInferred: Bool = false
    ) -> WebAppProfile {
        WebAppProfile(
            browserProfileID: browserProfileID,
            order: 0,
            name: name,
            homeURL: homeURL ?? URL(string: "https://example.com/\(name)")!,
            homeURLSchemeWasInferred: homeURLSchemeWasInferred
        )
    }
}
