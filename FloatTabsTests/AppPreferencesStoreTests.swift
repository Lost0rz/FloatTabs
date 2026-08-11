import AppKit
import WebKit
import XCTest
@testable import FloatTabs

@MainActor
final class AppPreferencesStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "FloatTabsTests.AppPreferencesStore.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        NSApp.appearance = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testAppearanceDefaultsToSystem() {
        let store = AppPreferencesStore(defaults: defaults)
        XCTAssertEqual(store.appearanceMode, .system)
    }

    func testAppearancePersistsAcrossStoreInstances() {
        let first = AppPreferencesStore(defaults: defaults)
        first.appearanceMode = .dark

        let second = AppPreferencesStore(defaults: defaults)
        XCTAssertEqual(second.appearanceMode, .dark)

        second.appearanceMode = .light
        XCTAssertEqual(AppPreferencesStore(defaults: defaults).appearanceMode, .light)
    }

    func testUnknownAppearanceFallsBackToSystem() {
        defaults.set("future-value", forKey: AppPreferencesStore.appearanceKey)
        XCTAssertEqual(AppPreferencesStore(defaults: defaults).appearanceMode, .system)
    }

    func testFollowPreferredSizeDefaultsTrueAndPersists() {
        let first = AppPreferencesStore(defaults: defaults)
        XCTAssertTrue(first.followPreferredSize)
        XCTAssertEqual(first.windowSizeMode, .perWebApp)

        first.windowSizeMode = .fixed
        XCTAssertFalse(AppPreferencesStore(defaults: defaults).followPreferredSize)
        XCTAssertEqual(AppPreferencesStore(defaults: defaults).windowSizeMode, .fixed)

        first.windowSizeMode = .perWebApp
        XCTAssertTrue(AppPreferencesStore(defaults: defaults).followPreferredSize)
        XCTAssertEqual(AppPreferencesStore(defaults: defaults).windowSizeMode, .perWebApp)
    }

    func testBorderThemeDefaultsRainbowAndPersists() {
        let first = AppPreferencesStore(defaults: defaults)
        XCTAssertEqual(first.borderTheme, .rainbow)

        first.borderTheme = .orange
        XCTAssertEqual(AppPreferencesStore(defaults: defaults).borderTheme, .orange)

        first.borderTheme = .custom
        first.customBorderColorHex = "#12AB34"
        let restored = AppPreferencesStore(defaults: defaults)
        XCTAssertEqual(restored.borderTheme, .custom)
        XCTAssertEqual(restored.customBorderColorHex, "#12AB34FF")
    }

    func testCustomBorderColorRoundTripsThroughSRGBHex() {
        let store = AppPreferencesStore(defaults: defaults)
        store.customBorderColor = NSColor(srgbRed: 1, green: 0.25, blue: 0, alpha: 1)
        XCTAssertEqual(store.customBorderColorHex, "#FF4000FF")
        XCTAssertEqual(store.customBorderColor.usingColorSpace(.sRGB)?.redComponent ?? 0, 1, accuracy: 0.01)
    }

    func testFixedViewportDefaultsToMediumAndPersistsSeparately() {
        let first = AppPreferencesStore(defaults: defaults)
        XCTAssertFalse(first.hasStoredFixedViewportSize)
        XCTAssertEqual(first.fixedViewportSize.width, 600, accuracy: 0.001)
        XCTAssertEqual(first.fixedViewportSize.height, 820, accuracy: 0.001)

        first.fixedViewportSize = CGSize(width: 777, height: 666)
        XCTAssertTrue(first.hasStoredFixedViewportSize)

        let second = AppPreferencesStore(defaults: defaults)
        XCTAssertEqual(second.fixedViewportSize.width, 777, accuracy: 0.001)
        XCTAssertEqual(second.fixedViewportSize.height, 666, accuracy: 0.001)
        XCTAssertNil(SimpleViewportPreset.matching(second.fixedViewportSize))
    }

    func testFixedViewportUsesStandardPresetAndClampsUnsafeSmallValues() {
        let store = AppPreferencesStore(defaults: defaults)
        let wide = try! XCTUnwrap(SimpleViewportPreset.wide.size)
        store.fixedViewportSize = wide
        XCTAssertEqual(SimpleViewportPreset.matching(store.fixedViewportSize), .wide)

        store.fixedViewportSize = CGSize(width: 100, height: 200)
        XCTAssertEqual(store.fixedViewportSize.width, 320, accuracy: 0.001)
        XCTAssertEqual(store.fixedViewportSize.height, 400, accuracy: 0.001)
    }

    func testFloatingWindowSizingUsesVisibleViewportInsteadOfDesktopLogicalFrame() {
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

        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        container.show(webView: webView)
        container.layoutSubtreeIfNeeded()
        webView.layoutSubtreeIfNeeded()

        XCTAssertEqual(webView.frame.width, 1024, accuracy: 0.001)
        XCTAssertGreaterThan(webView.frame.height, 820)

        let visibleSize = PopupCoordinator.visibleSourceSize(for: webView)
        XCTAssertEqual(visibleSize.width, 600, accuracy: 0.001)
        XCTAssertEqual(visibleSize.height, 820, accuracy: 0.001)
    }

    func testFloatingWindowSizingFallsBackToStandaloneWebViewFrame() {
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        webView.frame = NSRect(x: 0, y: 0, width: 640, height: 720)

        let visibleSize = PopupCoordinator.visibleSourceSize(for: webView)
        XCTAssertEqual(visibleSize.width, 640, accuracy: 0.001)
        XCTAssertEqual(visibleSize.height, 720, accuracy: 0.001)
    }

    func testPanelStaysFloatingAboveOrdinaryApplicationsRegardlessOfPin() {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 760)
        )

        XCTAssertEqual(panel.level, .floating)
        XCTAssertFalse(panel.isPresentationPinned)

        panel.setPresentationPinned(true)
        XCTAssertEqual(panel.level, .floating)
        XCTAssertTrue(panel.isPresentationPinned)

        panel.setPresentationPinned(false)
        XCTAssertEqual(panel.level, .floating)
        XCTAssertFalse(panel.isPresentationPinned)
    }

    func testUnpinnedOwnFullscreenLeavesFullscreenSpaceButPinnedCanRemain() {
        let ordinary = FloatingPanel.presentationCollectionBehavior(
            isPinned: false,
            fullscreenState: .notInFullscreen
        )
        XCTAssertTrue(ordinary.contains(.canJoinAllSpaces))
        XCTAssertTrue(ordinary.contains(.canJoinAllApplications))
        XCTAssertTrue(ordinary.contains(.fullScreenAuxiliary))

        let unpinnedFullscreen = FloatingPanel.presentationCollectionBehavior(
            isPinned: false,
            fullscreenState: .inFullscreen
        )
        XCTAssertTrue(unpinnedFullscreen.contains(.fullScreenNone))
        XCTAssertFalse(unpinnedFullscreen.contains(.canJoinAllSpaces))
        XCTAssertFalse(unpinnedFullscreen.contains(.canJoinAllApplications))
        XCTAssertFalse(unpinnedFullscreen.contains(.fullScreenAuxiliary))

        let pinnedFullscreen = FloatingPanel.presentationCollectionBehavior(
            isPinned: true,
            fullscreenState: .inFullscreen
        )
        XCTAssertTrue(pinnedFullscreen.contains(.canJoinAllSpaces))
        XCTAssertTrue(pinnedFullscreen.contains(.canJoinAllApplications))
        XCTAssertTrue(pinnedFullscreen.contains(.fullScreenAuxiliary))
        XCTAssertFalse(pinnedFullscreen.contains(.fullScreenNone))
    }

    func testMouseDownAnchorsKeyboardFocusOnlyBeforeFullscreenTransition() {
        XCTAssertTrue(
            FloatingPanel.shouldAnchorKeyboardFocus(
                eventType: .leftMouseDown,
                isKeyWindow: false,
                fullscreenState: .notInFullscreen
            )
        )
        XCTAssertTrue(
            FloatingPanel.shouldAnchorKeyboardFocus(
                eventType: .rightMouseDown,
                isKeyWindow: false,
                fullscreenState: .notInFullscreen
            )
        )
        XCTAssertFalse(
            FloatingPanel.shouldAnchorKeyboardFocus(
                eventType: .leftMouseDown,
                isKeyWindow: true,
                fullscreenState: .notInFullscreen
            )
        )
        XCTAssertFalse(
            FloatingPanel.shouldAnchorKeyboardFocus(
                eventType: .mouseMoved,
                isKeyWindow: false,
                fullscreenState: .notInFullscreen
            )
        )
        XCTAssertFalse(
            FloatingPanel.shouldAnchorKeyboardFocus(
                eventType: .leftMouseDown,
                isKeyWindow: false,
                fullscreenState: .enteringFullscreen
            )
        )
        XCTAssertFalse(
            FloatingPanel.shouldAnchorKeyboardFocus(
                eventType: .leftMouseDown,
                isKeyWindow: false,
                fullscreenState: .inFullscreen
            )
        )
        XCTAssertFalse(
            FloatingPanel.shouldAnchorKeyboardFocus(
                eventType: .leftMouseDown,
                isKeyWindow: false,
                fullscreenState: .exitingFullscreen
            )
        )
    }

    func testWebFullscreenStateProtectionCoversTransitions() {
        XCTAssertFalse(WebViewPool.isActiveFullscreenState(.notInFullscreen))
        XCTAssertTrue(WebViewPool.isActiveFullscreenState(.enteringFullscreen))
        XCTAssertTrue(WebViewPool.isActiveFullscreenState(.inFullscreen))
        XCTAssertTrue(WebViewPool.isActiveFullscreenState(.exitingFullscreen))
    }

    func testHiddenFullscreenSlotSurvivesGraceAndGetsFreshGraceAfterExit() async throws {
        let profile = WebAppProfile(
            order: 0,
            name: "Fullscreen",
            homeURL: URL(string: "https://example.com")!,
            residencyPolicy: .cold,
            backgroundMediaPolicy: .pauseWhenInactive
        )
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, _ in }
        )
        _ = pool.webView(for: profile)

        let container = WebPanelContainerView(
            frame: NSRect(x: 0, y: 0, width: 600, height: 820)
        )
        var isFullscreen = true
        let lifecycle = SlotLifecycleCoordinator(
            webViewPool: pool,
            container: container,
            coldReleaseDelay: 0.01,
            hiddenActiveGraceDelay: 0.01,
            mediaProtectionPollDelay: 0.005,
            mediaPlayingQuery: { _, completion in completion(false) },
            elementFullscreenQuery: { _ in isFullscreen },
            installsMemoryPressureSource: false
        )

        lifecycle.setPanelVisible(true, activeProfile: profile)
        lifecycle.activate(profile: profile)
        lifecycle.setPanelVisible(false, activeProfile: profile)

        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(pool.contains(slotID: profile.id))
        XCTAssertTrue(lifecycle.isHiddenActiveGracePending)

        isFullscreen = false
        try await Task.sleep(nanoseconds: 8_000_000)
        XCTAssertTrue(
            pool.contains(slotID: profile.id),
            "leaving fullscreen should start a fresh hidden-active grace, not release immediately"
        )

        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertFalse(pool.contains(slotID: profile.id))
    }
}
