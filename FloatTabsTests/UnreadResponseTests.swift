import AppKit
import XCTest
@testable import FloatTabs

@MainActor
final class UnreadResponseTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var slotA = UUID()
    private var slotB = UUID()

    override func setUp() {
        super.setUp()
        suiteName = "FloatTabsTests.UnreadResponse.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        slotA = UUID()
        slotB = UUID()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testStoreDefaultsEmptyAndPersistsAcrossStoreInstances() {
        let store = UnreadResponseStore(defaults: defaults)
        XCTAssertTrue(store.unreadSlotIDs.isEmpty)

        store.markUnread(slotA)
        store.markUnread(slotA)

        XCTAssertEqual(store.unreadSlotIDs, [slotA])
        XCTAssertEqual(
            UnreadResponseStore(defaults: defaults).unreadSlotIDs,
            [slotA]
        )
    }

    func testMalformedUUIDEntriesAreIgnoredWithoutHidingValidEntries() {
        defaults.set(
            ["not-a-uuid", slotA.uuidString, "also-invalid"],
            forKey: UnreadResponseStore.slotIDsKey
        )

        XCTAssertEqual(
            UnreadResponseStore(defaults: defaults).unreadSlotIDs,
            [slotA]
        )
    }

    func testPruneRemovesUnknownSlotIDsAndPersistsThePrunedSet() {
        let store = UnreadResponseStore(defaults: defaults)
        store.markUnread(slotA)
        store.markUnread(slotB)

        store.prune(validSlotIDs: [slotA])

        XCTAssertEqual(store.unreadSlotIDs, [slotA])
        XCTAssertEqual(
            UnreadResponseStore(defaults: defaults).unreadSlotIDs,
            [slotA]
        )
    }

    func testCoordinatorGenerationFinishedAlwaysMarksUnread() {
        let coordinator = ChatGPTUnreadResponseCoordinator(
            store: UnreadResponseStore(defaults: defaults)
        )

        coordinator.handle(.generationFinished, for: slotA)

        XCTAssertEqual(coordinator.unreadSlotIDs, [slotA])
    }

    func testGenerationStartedDoesNotClearExistingUnread() {
        let coordinator = makeCoordinator()
        coordinator.markUnread(slotID: slotA)

        coordinator.handle(.generationStarted, for: slotA)

        XCTAssertEqual(coordinator.unreadSlotIDs, [slotA])
    }

    func testRuntimeResetDoesNotClearExistingUnread() {
        let coordinator = makeCoordinator()
        coordinator.markUnread(slotID: slotA)

        coordinator.handle(.runtimeReset, for: slotA)

        XCTAssertEqual(coordinator.unreadSlotIDs, [slotA])
    }

    func testNewGenerationDoesNotClearPreviousUnreadResponse() {
        let coordinator = makeCoordinator()
        coordinator.handle(.generationFinished, for: slotA)
        coordinator.handle(.generationStarted, for: slotA)
        coordinator.handle(.generationFinished, for: slotA)

        XCTAssertEqual(coordinator.unreadSlotIDs, [slotA])
    }

    func testAcknowledgeAndRemoveAreIdempotent() {
        let coordinator = makeCoordinator()
        coordinator.markUnread(slotID: slotA)

        coordinator.acknowledge(slotID: slotA)
        coordinator.acknowledge(slotID: slotA)
        coordinator.removeSlot(slotID: slotA)

        XCTAssertTrue(coordinator.unreadSlotIDs.isEmpty)
        XCTAssertTrue(
            UnreadResponseStore(defaults: defaults).unreadSlotIDs.isEmpty
        )
    }

    func testUnreadProjectionIncludesActiveAndInactiveTabsAndAccessibility() {
        let profileA = makeProfile(name: "Active")
        let profileB = makeProfile(name: "Inactive")
        let zone = ExternalControlZoneView(
            frame: NSRect(x: 0, y: 0, width: 240, height: 500)
        )
        zone.apply(profiles: [profileA, profileB], activeTabID: profileA.id)
        zone.setUnreadSlotIDs([profileA.id, profileB.id])
        zone.layoutSubtreeIfNeeded()

        let active = try! XCTUnwrap(zone.tabView(for: profileA.id))
        let inactive = try! XCTUnwrap(zone.tabView(for: profileB.id))
        XCTAssertTrue(active.isShowingUnreadResponse)
        XCTAssertTrue(inactive.isShowingUnreadResponse)
        XCTAssertTrue(
            active.accessibilityLabel()?.contains("Unread response") == true
        )

        zone.setUnreadSlotIDs([])
        XCTAssertFalse(active.isShowingUnreadResponse)
        XCTAssertFalse(inactive.isShowingUnreadResponse)
        XCTAssertFalse(
            active.accessibilityLabel()?.contains("Unread response") == true
        )
    }

    func testOverflowProjectsUnreadMarkerWithoutChangingMenuTitle() {
        let profiles = (0..<8).map { index in
            makeProfile(name: "Tab \(index)")
        }
        let zone = ExternalControlZoneView(
            frame: NSRect(x: 0, y: 0, width: 80, height: 270)
        )
        zone.apply(profiles: profiles, activeTabID: profiles[0].id)
        zone.setUnreadSlotIDs([profiles.last!.id])
        zone.layoutSubtreeIfNeeded()

        let overflow = try! XCTUnwrap(
            zone.subviews.compactMap { $0 as? RailOverflowControl }.first
        )
        let item = try! XCTUnwrap(
            overflow.menuItems.first(where: { $0.slotID == profiles.last!.id })
        )
        XCTAssertTrue(item.isUnread)
        XCTAssertEqual(item.title, profiles.last!.name)
        XCTAssertTrue(overflow.isShowingUnreadResponse)
        let menuItem = overflow.makeMenu().items.last
        XCTAssertEqual(menuItem?.title, item.title)
        XCTAssertNotNil(menuItem?.image)
    }

    private func makeCoordinator() -> ChatGPTUnreadResponseCoordinator {
        ChatGPTUnreadResponseCoordinator(
            store: UnreadResponseStore(defaults: defaults)
        )
    }

    private func makeProfile(name: String) -> WebAppProfile {
        WebAppProfile(
            order: 0,
            name: name,
            homeURL: URL(string: "https://example.com/\(name)")!
        )
    }
}
