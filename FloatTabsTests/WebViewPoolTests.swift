import AppKit
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

    func testChatGPTMobileAutomaticWarmReuseKeepsCompatibilityIdentityWithoutReload() {
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

        let first = pool.webView(for: profile)
        let firstUA = first.customUserAgent
        let second = pool.webView(for: profile)
        let third = pool.webView(for: profile)

        XCTAssertTrue(first === second)
        XCTAssertTrue(second === third)
        XCTAssertEqual(loadedRequests.count, 1)
        XCTAssertEqual(second.customUserAgent, firstUA)
        XCTAssertEqual(third.customUserAgent, firstUA)
        XCTAssertTrue(third.customUserAgent?.contains("Macintosh") == true)
        XCTAssertFalse(third.customUserAgent?.contains("iPhone") == true)
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

    func testColdReleaseDropsOnlyRequestedLiveWebView() {
        let pool = makePool()
        let first = makeProfile(name: "A")
        let second = makeProfile(name: "B")
        _ = pool.webView(for: first)
        let secondView = pool.webView(for: second)

        pool.release(slotID: first.id)

        XCTAssertFalse(pool.contains(slotID: first.id))
        XCTAssertTrue(pool.contains(slotID: second.id))
        XCTAssertTrue(pool.webView(for: second) === secondView)
        XCTAssertEqual(pool.count, 1)
    }

    func testResidentSetChangeTracksActualLiveWebViews() {
        let pool = makePool()
        let profile = makeProfile(name: "Resident")
        var snapshots: [Set<UUID>] = []
        pool.onResidentSetChange = { snapshots.append(pool.residentSlotIDs) }

        _ = pool.webView(for: profile)
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
        _ = pool.webView(for: profile)
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

    func testColdLifecycleActivationCancelsPendingRelease() async throws {
        let pool = makePool()
        var profile = makeProfile(name: "ColdCancel")
        profile.residencyPolicy = .cold
        _ = pool.webView(for: profile)
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
        _ = pool.webView(for: source)
        _ = pool.webView(for: companion)
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
        _ = pool.webView(for: source)
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
        _ = pool.webView(for: source)
        _ = pool.webView(for: companion)
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

    func testResourceLifecycleDefaultTimingsMatchAcceptedContract() {
        XCTAssertEqual(SlotLifecycleCoordinator.defaultColdReleaseDelay, 30)
        XCTAssertEqual(SlotLifecycleCoordinator.defaultWarmReleaseDelay, 120)
        XCTAssertEqual(SlotLifecycleCoordinator.defaultHiddenActiveGraceDelay, 120)
        XCTAssertEqual(SlotLifecycleCoordinator.defaultWarmResidentLimit, 2)
    }

    func testWarmLifecycleDoesNotScheduleColdRelease() async throws {
        let pool = makePool()
        var profile = makeProfile(name: "Warm")
        profile.residencyPolicy = .warm
        _ = pool.webView(for: profile)
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
        _ = pool.webView(for: profile)
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

    func testWarmLRULimitKeepsOnlyTwoRecentInactiveResidents() {
        let pool = makePool()
        let profiles = ["A", "B", "C"].enumerated().map { index, name in
            var profile = makeProfile(name: name)
            profile.order = index
            profile.residencyPolicy = .warm
            return profile
        }
        for profile in profiles {
            _ = pool.webView(for: profile)
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
        _ = pool.webView(for: profile)
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
        _ = pool.webView(for: profile)
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

    func testHiddenSelectedDefaultMediaPausesImmediatelyBeforeRetentionGrace() {
        let pool = makePool()
        var profile = makeProfile(name: "HiddenPause")
        profile.residencyPolicy = .hot
        profile.backgroundMediaPolicy = .pauseWhenInactive
        _ = pool.webView(for: profile)
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

    func testHiddenSelectedBackgroundAudioDoesNotPause() {
        let pool = makePool()
        var profile = makeProfile(name: "HiddenBackgroundAudio")
        profile.residencyPolicy = .hot
        profile.backgroundMediaPolicy = .allowBackgroundAudio
        _ = pool.webView(for: profile)
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
        _ = pool.webView(for: profile)
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

    func testCriticalMemoryPressureEvictsInactiveWarmButNeverPlayingProtectedWarm() {
        let pool = makePool()
        var normal = makeProfile(name: "NormalWarm")
        normal.residencyPolicy = .warm
        var playing = makeProfile(name: "PlayingWarm")
        playing.residencyPolicy = .warm
        playing.backgroundMediaPolicy = .allowBackgroundAudio
        _ = pool.webView(for: normal)
        _ = pool.webView(for: playing)
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

    func testWebContentRecoveryPolicyReloadsActiveAndDefersInactiveSlots() {
        XCTAssertEqual(
            WebViewPool.recoveryDisposition(isActive: true),
            .reloadNow
        )
        XCTAssertEqual(
            WebViewPool.recoveryDisposition(isActive: false),
            .deferUntilActivation
        )
    }

    func testActiveWebContentTerminationReloadsLastKnownURLImmediately() {
        var loadedRequests: [URLRequest] = []
        var profile = makeProfile(name: "A")
        profile.currentURL = URL(string: "https://example.com/current")!
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, request in loadedRequests.append(request) },
            isSlotActive: { _ in true }
        )

        _ = pool.webView(for: profile)
        pool.handleContentProcessTermination(slotID: profile.id)

        XCTAssertEqual(loadedRequests.count, 2)
        XCTAssertEqual(loadedRequests.last?.url, profile.currentURL)
        XCTAssertEqual(loadedRequests.last?.cachePolicy, .useProtocolCachePolicy)
    }

    func testInactiveWebContentTerminationDefersReloadUntilSlotActivation() {
        var loadedRequests: [URLRequest] = []
        var isActive = false
        var profile = makeProfile(name: "A")
        profile.currentURL = URL(string: "https://example.com/current")!
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, request in loadedRequests.append(request) },
            isSlotActive: { _ in isActive }
        )

        let original = pool.webView(for: profile)
        pool.handleContentProcessTermination(slotID: profile.id)
        XCTAssertEqual(loadedRequests.count, 1)

        isActive = true
        let recovered = pool.webView(for: profile)

        XCTAssertTrue(original === recovered)
        XCTAssertEqual(loadedRequests.count, 2)
        XCTAssertEqual(loadedRequests.last?.url, profile.currentURL)
        XCTAssertEqual(loadedRequests.last?.cachePolicy, .useProtocolCachePolicy)
    }

    func testSlotNavigationObserverSurfacesContentProcessTermination() {
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

    func testNavigationCoordinatorKeepsSameSiteBlankInCurrentSlot() {
        let result = WebNavigationCoordinator.disposition(
            hasTargetFrame: false,
            sourceURL: URL(string: "https://www.bilibili.com/"),
            targetURL: URL(string: "https://bilibili.com/video/BV123")
        )

        XCTAssertEqual(result, .loadInCurrentSlot)
    }

    func testNavigationCoordinatorKeepsCrossSiteUserBlankInCurrentSlot() {
        let result = WebNavigationCoordinator.disposition(
            hasTargetFrame: false,
            navigationType: .linkActivated,
            sourceURL: URL(string: "https://example.com/article"),
            targetURL: URL(string: "https://developer.apple.com/documentation")
        )

        XCTAssertEqual(result, .loadInCurrentSlot)
    }

    func testNavigationCoordinatorLetsScriptedBlankReachUIDelegate() {
        let result = WebNavigationCoordinator.disposition(
            hasTargetFrame: false,
            navigationType: .other,
            sourceURL: URL(string: "https://example.com/article"),
            targetURL: URL(string: "https://accounts.example-idp.com/oauth")
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

    func testPopupRoutingKeepsCrossSiteUserLinkInCurrentSlot() {
        let result = PopupCoordinator.disposition(
            navigationType: .linkActivated,
            sourceURL: URL(string: "https://example.com"),
            targetURL: URL(string: "https://developer.apple.com")
        )

        XCTAssertEqual(result, .currentSlot)
    }

    func testPopupRoutingKeepsScriptedCrossSitePopupInCurrentSlot() {
        let result = PopupCoordinator.disposition(
            navigationType: .other,
            sourceURL: URL(string: "https://example.com"),
            targetURL: URL(string: "https://accounts.example-idp.com/oauth")
        )

        XCTAssertEqual(result, .currentSlot)
    }

    func testPopupRoutingKeepsAboutBlankInCurrentSlot() {
        let result = PopupCoordinator.disposition(
            navigationType: .other,
            sourceURL: URL(string: "https://example.com"),
            targetURL: URL(string: "about:blank")
        )

        XCTAssertEqual(result, .currentSlot)
    }

    func testPopupRoutingKeepsMissingInitialURLInCurrentSlot() {
        let result = PopupCoordinator.disposition(
            navigationType: .other,
            sourceURL: URL(string: "https://v.qq.com"),
            targetURL: nil
        )

        XCTAssertEqual(result, .currentSlot)
    }

    func testWindowOpenScriptForcesWebDestinationsIntoCurrentSlot() {
        let script = PopupCoordinator.currentSlotWindowOpenScript()

        XCTAssertEqual(script.injectionTime, .atDocumentStart)
        XCTAssertFalse(script.isForMainFrameOnly)
        XCTAssertTrue(script.source.contains("window.location.assign"))
        XCTAssertTrue(script.source.contains("about:blank"))
        XCTAssertTrue(script.source.contains("return window"))
    }

    func testPopupRoutingHandsNonWebSchemeToSystem() {
        let result = PopupCoordinator.disposition(
            navigationType: .linkActivated,
            sourceURL: URL(string: "https://example.com"),
            targetURL: URL(string: "mailto:test@example.com")
        )

        XCTAssertEqual(result, .externalBrowser)
    }

    func testExplicitLinkContextMenuOffersUserControlledDestinations() {
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

    func testExplicitUserFloatingWindowKeepsPersistentSessionAndSourceIdentity() {
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

    // MARK: - HTTPS entry fallback to HTTP (inferred scheme, non-443 ports)

    func testHostAppAllowsCleartextOnlyForWebContent() {
        let ats = Bundle.main.object(
            forInfoDictionaryKey: "NSAppTransportSecurity"
        ) as? [String: Any]
        XCTAssertEqual(ats?["NSAllowsArbitraryLoadsInWebContent"] as? Bool, true)
        XCTAssertNil(ats?["NSAllowsArbitraryLoads"])
    }

    func testURLNormalizationTracksInferredVersusExplicitScheme() {
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

    func testHTTPFallbackCandidateRequiresNon443HTTPSShape() {
        XCTAssertEqual(
            WebAppURL.httpFallbackCandidate(for: URL(string: "https://nas.example.com:3010/")!),
            URL(string: "http://nas.example.com:3010/")
        )
        XCTAssertNil(WebAppURL.httpFallbackCandidate(for: URL(string: "https://example.com")!))
        XCTAssertNil(WebAppURL.httpFallbackCandidate(for: URL(string: "https://example.com:443")!))
        XCTAssertNil(WebAppURL.httpFallbackCandidate(for: URL(string: "http://nas.example.com:3010")!))
    }

    func testHTTPFallbackDecisionRequiresConnectionFailureAndMatchingURL() {
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

    func testObserverFallsBackToHTTPOnceOnlyWhenCallerAllowsInferredEntry() {
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

    func testObserverNeverArmsFallbackForExplicitHTTPSPermissionFalse() {
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

    func testObserverCommitCancelsPendingEntryFallback() {
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

    func testPoolNavigationRequiresExplicitFallbackPermission() {
        let pool = makePool()
        let profile = makeProfile(name: "A")
        _ = pool.webView(for: profile)
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

    func testPoolInitialHomeFallbackRequiresPersistedInferredScheme() {
        let pool = makePool()
        let inferred = makeProfile(
            name: "NAS",
            homeURL: URL(string: "https://nas.example.com:3010")!,
            homeURLSchemeWasInferred: true
        )
        _ = pool.webView(for: inferred)
        XCTAssertTrue(pool.isHTTPEntryFallbackPending(slotID: inferred.id))

        let explicit = makeProfile(
            name: "ExplicitNAS",
            homeURL: URL(string: "https://nas.example.com:3010")!,
            homeURLSchemeWasInferred: false
        )
        _ = pool.webView(for: explicit)
        XCTAssertFalse(pool.isHTTPEntryFallbackPending(slotID: explicit.id))
    }

    func testPageCurrentURLDoesNotRegainFallbackAfterRuntimeRecreation() {
        let pool = makePool()
        var profile = makeProfile(
            name: "NAS",
            homeURL: URL(string: "https://nas.example.com:3010")!,
            homeURLSchemeWasInferred: true
        )
        profile.currentURL = URL(string: "https://nas.example.com:3010/account")!

        _ = pool.webView(for: profile)

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

    // MARK: - Hot host owner registry

    private func makeHotContainer() -> WebPanelContainerView {
        WebPanelContainerView(frame: NSRect(x: 0, y: 0, width: 430, height: 820))
    }

    /// Hosts live at container -> clipView -> WebSlotHostView depth.
    private func hotHostViews(in container: NSView) -> [WebSlotHostView] {
        container.subviews.flatMap { subview -> [NSView] in
            [subview] + subview.subviews
        }.compactMap { $0 as? WebSlotHostView }
    }

    /// Spec case: one Slot's Hot WKWebView moved main → companion leaves a
    /// stale (webView-less) host in the main container; release must clean
    /// hosts in every known owner container and drop the registry entry.
    func testReleaseCleansStaleHotHostsInAllKnownOwnerContainers() {
        let pool = makePool()
        var profile = makeProfile(name: "HotBoth")
        profile.residencyPolicy = .hot
        let webView = pool.webView(for: profile)

        let main = makeHotContainer()
        main.show(webView: webView, slotID: profile.id, residencyPolicy: .hot)
        // Production order: registration happens right after `show`, never via
        // an extra `webView(for:)` lookup that real code does not perform.
        pool.recordHotHostOwner(webView: webView, slotID: profile.id)
        XCTAssertEqual(pool.knownHotHostOwnerCount(for: profile.id), 1)

        let companion = makeHotContainer()
        companion.show(webView: webView, slotID: profile.id, residencyPolicy: .hot)
        pool.recordHotHostOwner(webView: webView, slotID: profile.id)
        XCTAssertEqual(pool.knownHotHostOwnerCount(for: profile.id), 2)

        // The main container still holds a stale dedicated host: its weak
        // bookkeeping remembers the WKWebView, but the physical superview has
        // moved to the companion. This is exactly the stale-host gap.
        let staleHosts = hotHostViews(in: main)
        XCTAssertEqual(staleHosts.count, 1)
        XCTAssertTrue(staleHosts[0].webView === webView)
        XCTAssertFalse(webView.superview === staleHosts[0])

        pool.release(slotID: profile.id)

        XCTAssertTrue(hotHostViews(in: main).isEmpty)
        XCTAssertTrue(hotHostViews(in: companion).isEmpty)
        XCTAssertEqual(pool.knownHotHostOwnerCount(for: profile.id), 0)
        XCTAssertFalse(pool.contains(slotID: profile.id))
    }

    /// Spec case: Hot → Warm must clear stale Hot hosts in every known owner
    /// without changing the resident runtime identity.
    /// Spec case: Hot → Warm must clear stale Hot hosts in every known owner
    /// without changing the resident runtime identity — via the authoritative
    /// policy reconciliation, with no `webView(for:)` lookup after the change.
    func testHotToWarmPolicyReconciliationClearsStaleHotHostsInAllKnownOwners() {
        let pool = makePool()
        var profile = makeProfile(name: "HotToWarm")
        profile.residencyPolicy = .hot
        let webView = pool.webView(for: profile)

        let main = makeHotContainer()
        main.show(webView: webView, slotID: profile.id, residencyPolicy: .hot)
        pool.recordHotHostOwner(webView: webView, slotID: profile.id)
        let companion = makeHotContainer()
        companion.show(webView: webView, slotID: profile.id, residencyPolicy: .hot)
        pool.recordHotHostOwner(webView: webView, slotID: profile.id)
        XCTAssertEqual(pool.knownHotHostOwnerCount(for: profile.id), 2)

        profile.residencyPolicy = .warm
        pool.reconcileHotHostOwners(validHotSlotIDs: [])

        XCTAssertEqual(pool.knownHotHostOwnerCount(for: profile.id), 0)
        XCTAssertTrue(hotHostViews(in: main).isEmpty)
        XCTAssertTrue(hotHostViews(in: companion).isEmpty)
    }

    /// Spec case: Hot → Cold follows the same all-owner policy cleanup.
    func testHotToColdPolicyReconciliationClearsStaleHotHostsInAllKnownOwners() {
        let pool = makePool()
        var profile = makeProfile(name: "HotToCold")
        profile.residencyPolicy = .hot
        let webView = pool.webView(for: profile)

        let main = makeHotContainer()
        main.show(webView: webView, slotID: profile.id, residencyPolicy: .hot)
        pool.recordHotHostOwner(webView: webView, slotID: profile.id)
        let companion = makeHotContainer()
        companion.show(webView: webView, slotID: profile.id, residencyPolicy: .hot)
        pool.recordHotHostOwner(webView: webView, slotID: profile.id)

        profile.residencyPolicy = .cold
        pool.reconcileHotHostOwners(validHotSlotIDs: [])

        XCTAssertEqual(pool.knownHotHostOwnerCount(for: profile.id), 0)
        XCTAssertTrue(hotHostViews(in: main).isEmpty)
        XCTAssertTrue(hotHostViews(in: companion).isEmpty)
    }

    /// Spec case: a `webView(for:)` lookup after a policy change still clears
    /// the current physical Hot host defensively when the explicit
    /// post-`show` registration was missed (kept as a fallback path). A stale
    /// host in a *different*, never-registered container cannot be discovered
    /// by this fallback — which is exactly why the production path registers
    /// every owner at `show` time and reconciles by policy.
    func testHotToWarmLookupDefensivelyClearsUnregisteredCurrentHost() {
        let pool = makePool()
        var profile = makeProfile(name: "HotToWarmDefensive")
        profile.residencyPolicy = .hot
        let webView = pool.webView(for: profile)

        let main = makeHotContainer()
        main.show(webView: webView, slotID: profile.id, residencyPolicy: .hot)
        // Registration intentionally skipped: models a missed registration.
        XCTAssertEqual(pool.knownHotHostOwnerCount(for: profile.id), 0)

        profile.residencyPolicy = .warm
        let warmView = pool.webView(for: profile)

        XCTAssertTrue(warmView === webView)
        XCTAssertTrue(pool.contains(slotID: profile.id))
        XCTAssertEqual(pool.knownHotHostOwnerCount(for: profile.id), 0)
        XCTAssertTrue(hotHostViews(in: main).isEmpty)
    }

    /// The key case previous tests missed: Hot slot shown in main, then in the
    /// fullscreen companion, then becomes inactive and changes policy. Cleanup
    /// must happen through policy-owner reconciliation alone — no later
    /// `webView(for:)` call exists — while the runtime stays resident with its
    /// identity intact and release timing still belongs to the lifecycle rules.
    func testInactiveHotPolicyChangeReconcilesOwnersWithoutPrematureRelease() {
        var releaseNotifications = 0
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, _ in },
            isSlotActive: { _ in false }
        )
        pool.onResidentSetChange = { releaseNotifications += 1 }

        var profile = makeProfile(name: "HotInactive")
        profile.residencyPolicy = .hot
        let webView = pool.webView(for: profile)
        XCTAssertEqual(releaseNotifications, 1)

        let main = makeHotContainer()
        main.show(webView: webView, slotID: profile.id, residencyPolicy: .hot)
        pool.recordHotHostOwner(webView: webView, slotID: profile.id)
        let companion = makeHotContainer()
        companion.show(webView: webView, slotID: profile.id, residencyPolicy: .hot)
        pool.recordHotHostOwner(webView: webView, slotID: profile.id)
        XCTAssertEqual(pool.knownHotHostOwnerCount(for: profile.id), 2)

        // The slot goes inactive and its policy drops from Hot. Production
        // responds with reconcileHotHostOwners only — never a fresh lookup.
        profile.residencyPolicy = .warm
        pool.reconcileHotHostOwners(validHotSlotIDs: [])

        XCTAssertTrue(hotHostViews(in: main).isEmpty)
        XCTAssertTrue(hotHostViews(in: companion).isEmpty)
        XCTAssertEqual(pool.knownHotHostOwnerCount(for: profile.id), 0)
        XCTAssertTrue(pool.contains(slotID: profile.id))
        XCTAssertTrue(pool.existingWebView(for: profile.id) === webView)
        // Host cleanup must not look like a runtime release.
        XCTAssertEqual(releaseNotifications, 1)
        // Frozen lifecycle contract untouched by host cleanup.
        XCTAssertEqual(SlotLifecycleCoordinator.defaultWarmReleaseDelay, 120)

        // Hot → Cold variant: same reconciliation, 30s frozen Cold grace.
        profile.residencyPolicy = .cold
        pool.reconcileHotHostOwners(validHotSlotIDs: [])
        XCTAssertTrue(pool.contains(slotID: profile.id))
        XCTAssertTrue(pool.existingWebView(for: profile.id) === webView)
        XCTAssertEqual(releaseNotifications, 1)
        XCTAssertEqual(SlotLifecycleCoordinator.defaultColdReleaseDelay, 30)
    }

    /// Spec case: a rendering-profile rebuild must not keep the old dedicated
    /// hosts alive in any known owner container.
    func testRuntimeRebuildLeavesNoOldHotHostBehind() {
        let pool = makePool()
        var profile = makeProfile(name: "Rebuild")
        profile.residencyPolicy = .hot
        let firstView = pool.webView(for: profile)

        let main = makeHotContainer()
        main.show(webView: firstView, slotID: profile.id, residencyPolicy: .hot)
        pool.recordHotHostOwner(webView: firstView, slotID: profile.id)

        profile.renderingProfile = profile.renderingProfile
            .settingBrowserIdentity(.windowsChrome)
        let rebuiltView = pool.webView(for: profile)

        XCTAssertFalse(rebuiltView === firstView)
        XCTAssertEqual(pool.knownHotHostOwnerCount(for: profile.id), 0)
        XCTAssertTrue(hotHostViews(in: main).isEmpty)
    }

    /// Spec case: the registry must not extend container lifetimes.
    func testOwnerRegistryDoesNotExtendContainerLifetime() {
        let pool = makePool()
        var profile = makeProfile(name: "HotWeak")
        profile.residencyPolicy = .hot
        let webView = pool.webView(for: profile)

        weak var weakMain: WebPanelContainerView?
        autoreleasepool {
            let main = makeHotContainer()
            weakMain = main
            main.show(webView: webView, slotID: profile.id, residencyPolicy: .hot)
            pool.recordHotHostOwner(webView: webView, slotID: profile.id)
            XCTAssertEqual(pool.knownHotHostOwnerCount(for: profile.id), 1)
        }
        XCTAssertNil(weakMain)
        // Dead weak owners are compacted out of the live count.
        XCTAssertEqual(pool.knownHotHostOwnerCount(for: profile.id), 0)

        pool.release(slotID: profile.id)
        XCTAssertEqual(pool.knownHotHostOwnerCount(for: profile.id), 0)
    }

    /// Spec case: reparenting between main and companion containers must not
    /// change runtime identity or residency for a Hot slot.
    func testCompanionReparentingKeepsRuntimeIdentityAndResidency() {
        let pool = makePool()
        var profile = makeProfile(name: "HotMove")
        profile.residencyPolicy = .hot
        let webView = pool.webView(for: profile)

        let main = makeHotContainer()
        main.show(webView: webView, slotID: profile.id, residencyPolicy: .hot)
        pool.recordHotHostOwner(webView: webView, slotID: profile.id)
        let companion = makeHotContainer()
        companion.show(webView: webView, slotID: profile.id, residencyPolicy: .hot)
        pool.recordHotHostOwner(webView: webView, slotID: profile.id)

        XCTAssertTrue(pool.existingWebView(for: profile.id) === webView)
        XCTAssertTrue(pool.contains(slotID: profile.id))
        XCTAssertEqual(pool.knownHotHostOwnerCount(for: profile.id), 2)
    }

    /// WebSlotHostView.attach invariant: when weak bookkeeping still reports
    /// the same WKWebView but the physical superview has moved elsewhere, a
    /// later attach must physically reparent instead of skipping.
    func testHostAttachReparentsWhenPhysicalSuperviewChangedButWeakIdentityMatches() {
        let webView = WKWebView(frame: .zero)
        let host = WebSlotHostView(webView: webView)
        XCTAssertTrue(webView.superview === host)

        // Physically move the WKWebView without telling the old host.
        let otherContainer = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        otherContainer.addSubview(webView)
        XCTAssertFalse(webView.superview === host)

        host.attach(webView)
        XCTAssertTrue(webView.superview === host)
    }

    private func makePool() -> WebViewPool {
        WebViewPool(onURLChange: { _, _ in }, initialLoad: { _, _ in })
    }

    private func makeProfile(
        name: String,
        homeURL: URL? = nil,
        homeURLSchemeWasInferred: Bool = false
    ) -> WebAppProfile {
        WebAppProfile(
            order: 0,
            name: name,
            homeURL: homeURL ?? URL(string: "https://example.com/\(name)")!,
            homeURLSchemeWasInferred: homeURLSchemeWasInferred
        )
    }
}
