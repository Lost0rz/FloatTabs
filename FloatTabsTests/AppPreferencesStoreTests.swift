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
}
