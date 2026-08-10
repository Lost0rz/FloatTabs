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

        first.followPreferredSize = false
        XCTAssertFalse(AppPreferencesStore(defaults: defaults).followPreferredSize)

        first.followPreferredSize = true
        XCTAssertTrue(AppPreferencesStore(defaults: defaults).followPreferredSize)
    }
}
