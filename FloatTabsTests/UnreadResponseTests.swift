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

    func testMixedTypeCorruptStoreKeepsEveryValidUUID() {
        defaults.set(
            [slotA.uuidString, NSNumber(value: 7), "invalid", slotB.uuidString],
            forKey: UnreadResponseStore.slotIDsKey
        )

        XCTAssertEqual(
            UnreadResponseStore(defaults: defaults).unreadSlotIDs,
            [slotA, slotB]
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

    func testValidInvisibleCompletionMarksUnread() {
        let coordinator = ChatGPTUnreadResponseCoordinator(
            store: UnreadResponseStore(defaults: defaults)
        )

        coordinator.handle(
            .generationFinished,
            for: slotA,
            isValidGenerationCompletion: true,
            userVisible: false
        )

        XCTAssertEqual(coordinator.unreadSlotIDs, [slotA])
    }

    func testValidVisibleCompletionMarksAndPersistsUnread() {
        let coordinator = makeCoordinator()

        XCTAssertEqual(coordinator.handle(
            .generationFinished,
            for: slotA,
            isValidGenerationCompletion: true,
            userVisible: true
        ), .marked(identityAvailable: false))

        XCTAssertEqual(coordinator.unreadSlotIDs, [slotA])
        XCTAssertEqual(UnreadResponseStore(defaults: defaults).unreadSlotIDs, [slotA])
    }

    func testStrayGenerationFinishDoesNotMarkUnread() {
        let coordinator = makeCoordinator()

        coordinator.handle(
            .generationFinished,
            for: slotA,
            isValidGenerationCompletion: false,
            userVisible: false
        )

        XCTAssertTrue(coordinator.unreadSlotIDs.isEmpty)
    }

    func testGenerationStartedDoesNotClearExistingUnread() {
        let coordinator = makeCoordinator()
        coordinator.markUnread(slotID: slotA)

        coordinator.handle(
            .generationStarted,
            for: slotA,
            isValidGenerationCompletion: false,
            userVisible: false
        )

        XCTAssertEqual(coordinator.unreadSlotIDs, [slotA])
    }

    func testRuntimeResetDoesNotClearExistingUnread() {
        let coordinator = makeCoordinator()
        coordinator.markUnread(slotID: slotA)

        coordinator.handle(
            .runtimeReset,
            for: slotA,
            isValidGenerationCompletion: false,
            userVisible: false
        )

        XCTAssertEqual(coordinator.unreadSlotIDs, [slotA])
    }

    func testNewGenerationDoesNotClearPreviousUnreadResponse() {
        let coordinator = makeCoordinator()
        coordinator.handle(
            .generationFinished,
            for: slotA,
            isValidGenerationCompletion: true,
            userVisible: false
        )
        coordinator.handle(
            .generationStarted,
            for: slotA,
            isValidGenerationCompletion: false,
            userVisible: false
        )
        coordinator.handle(
            .generationFinished,
            for: slotA,
            isValidGenerationCompletion: true,
            userVisible: false
        )

        XCTAssertEqual(coordinator.unreadSlotIDs, [slotA])
    }

    func testLaterUnseenCompletionReMarksAfterAcknowledgement() {
        let coordinator = makeCoordinator()

        coordinator.handle(
            .generationFinished,
            for: slotA,
            isValidGenerationCompletion: true,
            userVisible: false
        )
        coordinator.acknowledge(slotID: slotA)
        XCTAssertTrue(coordinator.unreadSlotIDs.isEmpty)

        coordinator.handle(
            .generationFinished,
            for: slotA,
            isValidGenerationCompletion: true,
            userVisible: false
        )

        XCTAssertEqual(coordinator.unreadSlotIDs, [slotA])
        XCTAssertEqual(
            UnreadResponseStore(defaults: defaults).unreadSlotIDs,
            [slotA]
        )
    }

    func testResponseIdentityOwnershipPersistsAndAdvancesForNewCompletion() throws {
        let coordinator = makeCoordinator()
        let first = try XCTUnwrap(ChatGPTResponseIdentity(rawValue: "message:response-a"))
        let second = try XCTUnwrap(ChatGPTResponseIdentity(rawValue: "message:response-b"))

        XCTAssertEqual(
            coordinator.handle(
                ChatGPTAttentionEvent(observation: .generationFinished, responseIdentity: first),
                for: slotA,
                isValidGenerationCompletion: true,
                userVisible: false
            ),
            .marked(identityAvailable: true)
        )
        XCTAssertEqual(coordinator.unreadResponseIdentity(for: slotA), first)
        XCTAssertEqual(
            UnreadResponseStore(defaults: defaults).unreadResponseIdentityBySlot[slotA],
            first
        )

        XCTAssertEqual(
            coordinator.handle(
                ChatGPTAttentionEvent(observation: .generationFinished, responseIdentity: second),
                for: slotA,
                isValidGenerationCompletion: true,
                userVisible: false
            ),
            .marked(identityAvailable: true)
        )
        XCTAssertEqual(coordinator.unreadResponseIdentity(for: slotA), second)
        XCTAssertEqual(coordinator.unreadSlotIDs, [slotA])
    }

    func testDiagnosticHandledLookupDistinguishesHitMissAndUnavailable() throws {
        let coordinator = makeCoordinator()
        let identity = try XCTUnwrap(ChatGPTResponseIdentity(rawValue: "message:lookup"))

        XCTAssertEqual(
            coordinator.diagnosticHandledLookup(slotID: slotA, responseIdentity: nil),
            .unavailable
        )
        XCTAssertEqual(
            coordinator.diagnosticHandledLookup(slotID: slotA, responseIdentity: identity),
            .miss
        )

        coordinator.recordHandled(slotID: slotA, responseIdentity: identity)

        XCTAssertEqual(
            coordinator.diagnosticHandledLookup(slotID: slotA, responseIdentity: identity),
            .hit
        )
    }

    func testVisibleCompletionIsNotRecordedAsHandled() throws {
        let coordinator = makeCoordinator()
        let identity = try XCTUnwrap(ChatGPTResponseIdentity(rawValue: "message:visible"))

        XCTAssertEqual(
            coordinator.handle(
                ChatGPTAttentionEvent(observation: .generationFinished, responseIdentity: identity),
                for: slotA,
                isValidGenerationCompletion: true,
                userVisible: true
            ),
            .marked(identityAvailable: true)
        )
        XCTAssertFalse(coordinator.isHandled(slotID: slotA, responseIdentity: identity))
        XCTAssertEqual(coordinator.unreadResponseIdentity(for: slotA), identity)

        coordinator.recordHandled(slotID: slotA, responseIdentity: identity)
        coordinator.acknowledge(slotID: slotA, responseIdentity: identity)
        XCTAssertEqual(
            coordinator.handle(
                ChatGPTAttentionEvent(observation: .generationFinished, responseIdentity: identity),
                for: slotA,
                isValidGenerationCompletion: true,
                userVisible: false
            ),
            .alreadyHandled
        )
        XCTAssertTrue(coordinator.unreadSlotIDs.isEmpty)
    }

    func testHIDDEN_COMPLETION_NOT_HANDLED() throws {
        let coordinator = makeCoordinator()
        let identity = try XCTUnwrap(
            ChatGPTResponseIdentity(rawValue: "message:hidden-not-handled")
        )

        XCTAssertEqual(
            coordinator.handle(
                ChatGPTAttentionEvent(
                    observation: .generationFinished,
                    responseIdentity: identity
                ),
                for: slotA,
                isValidGenerationCompletion: true,
                userVisible: false
            ),
            .marked(identityAvailable: true)
        )
        XCTAssertTrue(coordinator.unreadSlotIDs.contains(slotA))
        XCTAssertFalse(coordinator.isHandled(slotID: slotA, responseIdentity: identity))
    }

    func testHIDDEN_DUPLICATE_BEFORE_ACK_STAYS_UNREAD() throws {
        let coordinator = makeCoordinator()
        let identity = try XCTUnwrap(
            ChatGPTResponseIdentity(rawValue: "message:hidden-duplicate")
        )
        let event = ChatGPTAttentionEvent(
            observation: .generationFinished,
            responseIdentity: identity
        )

        XCTAssertEqual(
            coordinator.handle(
                event,
                for: slotA,
                isValidGenerationCompletion: true,
                userVisible: false
            ),
            .marked(identityAvailable: true)
        )
        XCTAssertEqual(
            coordinator.handle(
                event,
                for: slotA,
                isValidGenerationCompletion: true,
                userVisible: false
            ),
            .marked(identityAvailable: true)
        )
        XCTAssertEqual(coordinator.unreadResponseIdentity(for: slotA), identity)
        XCTAssertFalse(coordinator.isHandled(slotID: slotA, responseIdentity: identity))
    }

    func testDUPLICATE_AFTER_ACK_SKIPPED() throws {
        let coordinator = makeCoordinator()
        let identity = try XCTUnwrap(
            ChatGPTResponseIdentity(rawValue: "message:duplicate-after-ack")
        )
        let event = ChatGPTAttentionEvent(
            observation: .generationFinished,
            responseIdentity: identity
        )

        _ = coordinator.handle(
            event,
            for: slotA,
            isValidGenerationCompletion: true,
            userVisible: false
        )
        XCTAssertEqual(
            coordinator.acknowledge(slotID: slotA, responseIdentity: identity),
            .cleared(responseIdentity: identity)
        )
        XCTAssertEqual(
            coordinator.handle(
                event,
                for: slotA,
                isValidGenerationCompletion: true,
                userVisible: false
            ),
            .alreadyHandled
        )
        XCTAssertTrue(coordinator.unreadSlotIDs.isEmpty)
    }

    func testSNAPSHOT_LEGACY_UNREAD_IDENTITY_IS_PRESERVED() throws {
        let coordinator = makeCoordinator()
        let identity = try XCTUnwrap(
            ChatGPTResponseIdentity(rawValue: "message:legacy-snapshot")
        )
        coordinator.markUnread(slotID: slotA)

        XCTAssertEqual(
            coordinator.reconcileHandledSnapshot(
                slotID: slotA,
                responseIdentity: identity
            ),
            .preservedLegacyIdentity
        )
        XCTAssertTrue(coordinator.unreadSlotIDs.contains(slotA))
        XCTAssertTrue(coordinator.isHandled(slotID: slotA, responseIdentity: identity))
    }

    func testHIDDEN_COMPLETIONS_DO_NOT_POLLUTE_HANDLED_HISTORY() throws {
        let coordinator = makeCoordinator()
        let handled = try (0..<16).map { index in
            try XCTUnwrap(
                ChatGPTResponseIdentity(rawValue: "message:handled-history-\(index)")
            )
        }
        let hidden = try (0..<3).map { index in
            try XCTUnwrap(
                ChatGPTResponseIdentity(rawValue: "message:hidden-history-\(index)")
            )
        }

        for identity in handled {
            coordinator.recordHandled(slotID: slotA, responseIdentity: identity)
        }
        for identity in hidden {
            _ = coordinator.handle(
                ChatGPTAttentionEvent(
                    observation: .generationFinished,
                    responseIdentity: identity
                ),
                for: slotA,
                isValidGenerationCompletion: true,
                userVisible: false
            )
        }

        XCTAssertTrue(
            handled.allSatisfy {
                coordinator.isHandled(slotID: slotA, responseIdentity: $0)
            }
        )
        XCTAssertTrue(
            hidden.allSatisfy {
                !coordinator.isHandled(slotID: slotA, responseIdentity: $0)
            }
        )
    }

    func testLEGACY_STORE_COMPAT() {
        defaults.set([slotA.uuidString], forKey: UnreadResponseStore.slotIDsKey)
        let coordinator = makeCoordinator()

        XCTAssertEqual(coordinator.unreadSlotIDs, [slotA])
        XCTAssertNil(coordinator.unreadResponseIdentity(for: slotA))
        XCTAssertEqual(
            coordinator.acknowledge(slotID: slotA, responseIdentity: nil),
            .cleared(responseIdentity: nil)
        )
        XCTAssertTrue(coordinator.unreadSlotIDs.isEmpty)
    }

    func testSIDE_CAR_CORRUPTION_FAILS_SAFE() {
        defaults.set([slotA.uuidString], forKey: UnreadResponseStore.slotIDsKey)
        defaults.set(
            [
                slotA.uuidString: "message:not valid",
                "not-a-uuid": "message:orphan",
                slotB.uuidString: NSNumber(value: 7)
            ],
            forKey: UnreadResponseStore.responseIdentityBySlotKey
        )
        let coordinator = makeCoordinator()

        XCTAssertEqual(coordinator.unreadSlotIDs, [slotA])
        XCTAssertNil(coordinator.unreadResponseIdentity(for: slotA))
        XCTAssertEqual(
            coordinator.acknowledge(slotID: slotA, responseIdentity: nil),
            .cleared(responseIdentity: nil)
        )
        XCTAssertTrue(coordinator.unreadSlotIDs.isEmpty)
    }

    func testPruneAndRemoveClearSidecarAndHandledHistory() throws {
        let coordinator = makeCoordinator()
        let identityA = try XCTUnwrap(
            ChatGPTResponseIdentity(rawValue: "message:prune-a")
        )
        let identityB = try XCTUnwrap(
            ChatGPTResponseIdentity(rawValue: "message:remove-b")
        )
        coordinator.markUnread(slotID: slotA, responseIdentity: identityA)
        coordinator.markUnread(slotID: slotB, responseIdentity: identityB)
        coordinator.recordHandled(slotID: slotA, responseIdentity: identityA)

        coordinator.prune(validSlotIDs: [slotB])
        XCTAssertNil(coordinator.unreadResponseIdentity(for: slotA))
        XCTAssertFalse(coordinator.isHandled(slotID: slotA, responseIdentity: identityA))
        XCTAssertEqual(coordinator.unreadResponseIdentity(for: slotB), identityB)

        coordinator.removeSlot(slotID: slotB)
        XCTAssertNil(coordinator.unreadResponseIdentity(for: slotB))
        XCTAssertTrue(
            UnreadResponseStore(defaults: defaults)
                .unreadResponseIdentityBySlot
                .isEmpty
        )
    }

    func testROLLBACK_SLOT_KEY_COMPAT() throws {
        let coordinator = makeCoordinator()
        let identity = try XCTUnwrap(
            ChatGPTResponseIdentity(rawValue: "message:rollback-compatible")
        )

        coordinator.markUnread(slotID: slotA, responseIdentity: identity)

        let legacySlotIDs = defaults.array(forKey: UnreadResponseStore.slotIDsKey)
        XCTAssertEqual(legacySlotIDs as? [String], [slotA.uuidString])
        XCTAssertEqual(coordinator.unreadResponseIdentity(for: slotA), identity)
    }

    func testU1_REGRESSION() {
        let coordinator = makeCoordinator()

        coordinator.handle(
            .generationFinished,
            for: slotA,
            isValidGenerationCompletion: true,
            userVisible: false
        )
        XCTAssertEqual(coordinator.unreadSlotIDs, [slotA])

        coordinator.acknowledge(slotID: slotA)
        XCTAssertTrue(coordinator.unreadSlotIDs.isEmpty)
    }

    func testU2_REGRESSION() {
        let coordinator = makeCoordinator()

        coordinator.handle(
            .generationFinished,
            for: slotA,
            isValidGenerationCompletion: false,
            userVisible: false
        )
        XCTAssertTrue(coordinator.unreadSlotIDs.isEmpty)

        coordinator.handle(
            .generationFinished,
            for: slotA,
            isValidGenerationCompletion: true,
            userVisible: false
        )
        XCTAssertEqual(coordinator.unreadSlotIDs, [slotA])
    }

    func testMismatchedOldPointerDoesNotClearNewerUnreadOwnership() throws {
        let coordinator = makeCoordinator()
        let current = try XCTUnwrap(ChatGPTResponseIdentity(rawValue: "message:new"))
        let old = try XCTUnwrap(ChatGPTResponseIdentity(rawValue: "message:old"))
        coordinator.markUnread(slotID: slotA, responseIdentity: current)

        XCTAssertEqual(
            coordinator.acknowledge(slotID: slotA, responseIdentity: old),
            .preservedIdentityMismatch
        )
        XCTAssertEqual(coordinator.unreadResponseIdentity(for: slotA), current)
        XCTAssertEqual(
            coordinator.acknowledge(slotID: slotA, responseIdentity: current),
            .cleared(responseIdentity: current)
        )
        XCTAssertTrue(coordinator.unreadSlotIDs.isEmpty)
    }

    func testIdentityUnavailableUsesLegacySlotLevelFallback() {
        let coordinator = makeCoordinator()

        XCTAssertEqual(
            coordinator.handle(
                ChatGPTAttentionEvent(observation: .generationFinished, responseIdentity: nil),
                for: slotA,
                isValidGenerationCompletion: true,
                userVisible: false
            ),
            .marked(identityAvailable: false)
        )
        XCTAssertNil(coordinator.unreadResponseIdentity(for: slotA))
    }

    func testHandledIdentityHistoryIsBoundedToRecentSixteen() throws {
        let coordinator = makeCoordinator()
        let identities = try (0..<17).map { index in
            try XCTUnwrap(ChatGPTResponseIdentity(rawValue: "message:history-\(index)"))
        }

        for identity in identities {
            coordinator.recordHandled(slotID: slotA, responseIdentity: identity)
        }

        XCTAssertFalse(coordinator.isHandled(slotID: slotA, responseIdentity: identities[0]))
        XCTAssertTrue(coordinator.isHandled(slotID: slotA, responseIdentity: identities[1]))
        XCTAssertTrue(coordinator.isHandled(slotID: slotA, responseIdentity: identities[16]))
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
        XCTAssertEqual(overflow.unreadResponseFrame.width, 9, accuracy: 0.001)
        XCTAssertEqual(overflow.unreadResponseFrame.height, 9, accuracy: 0.001)
        XCTAssertTrue(overflow.bounds.contains(overflow.unreadResponseFrame))
        let unreadCenter = NSPoint(
            x: overflow.unreadResponseFrame.midX,
            y: overflow.unreadResponseFrame.midY
        )
        XCTAssertTrue(overflow.hitTest(unreadCenter) === overflow)
        let menuItem = overflow.makeMenu().items.last
        XCTAssertEqual(menuItem?.title, item.title)
        XCTAssertNotNil(menuItem?.image)
        XCTAssertEqual(menuItem?.image?.size, NSSize(width: 12, height: 12))
        XCTAssertEqual(menuItem?.image?.isTemplate, false)
    }

    func testOverflowUnreadProjectionRefreshesWithoutRelayout() throws {
        let profiles = (0..<8).map { index in
            makeProfile(name: "Overflow \(index)")
        }
        let zone = ExternalControlZoneView(
            frame: NSRect(x: 0, y: 0, width: 80, height: 270)
        )
        zone.apply(profiles: profiles, activeTabID: profiles[0].id)
        zone.layoutSubtreeIfNeeded()

        let overflow = try XCTUnwrap(
            zone.subviews.compactMap { $0 as? RailOverflowControl }.first
        )
        XCTAssertFalse(zone.overflowTabIDs.isEmpty)
        let hiddenSlotID = try XCTUnwrap(zone.overflowTabIDs.last)
        let initialItem = try XCTUnwrap(
            overflow.menuItems.first(where: { $0.slotID == hiddenSlotID })
        )
        XCTAssertFalse(initialItem.isUnread)
        XCTAssertFalse(overflow.isShowingUnreadResponse)
        XCTAssertFalse(
            overflow.accessibilityLabel()?.contains("Unread response") == true
        )

        // The compact geometry is intentionally not recalculated here. The
        // unread projection must refresh the existing overflow snapshot alone.
        zone.setUnreadSlotIDs([hiddenSlotID])

        let unreadItem = try XCTUnwrap(
            overflow.menuItems.first(where: { $0.slotID == hiddenSlotID })
        )
        XCTAssertTrue(unreadItem.isUnread)
        XCTAssertTrue(overflow.isShowingUnreadResponse)
        XCTAssertTrue(
            overflow.accessibilityLabel()?.contains("Unread response") == true
        )
        let unreadMenuItem = try XCTUnwrap(
            overflow.makeMenu().items.first {
                $0.representedObject as? String == hiddenSlotID.uuidString
            }
        )
        XCTAssertNotNil(unreadMenuItem.image)
        XCTAssertTrue(
            unreadMenuItem.accessibilityLabel()?.contains("Unread response") == true
        )

        zone.setUnreadSlotIDs([])

        let clearedItem = try XCTUnwrap(
            overflow.menuItems.first(where: { $0.slotID == hiddenSlotID })
        )
        XCTAssertFalse(clearedItem.isUnread)
        XCTAssertFalse(overflow.isShowingUnreadResponse)
        XCTAssertFalse(
            overflow.accessibilityLabel()?.contains("Unread response") == true
        )
        let clearedMenuItem = try XCTUnwrap(
            overflow.makeMenu().items.first {
                $0.representedObject as? String == hiddenSlotID.uuidString
            }
        )
        XCTAssertNil(clearedMenuItem.image)
        XCTAssertFalse(
            clearedMenuItem.accessibilityLabel()?.contains("Unread response") == true
        )
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
