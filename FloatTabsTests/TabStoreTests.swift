import Foundation
import XCTest
@testable import FloatTabs

final class MemoryProfileRepository: ProfileRepositoryProtocol {
    var state: StoredWebAppState
    var savedStates: [StoredWebAppState] = []
    var loadError: Error?

    init(state: StoredWebAppState = .empty) {
        self.state = state
    }

    func load() throws -> StoredWebAppState {
        if let loadError { throw loadError }
        return state
    }

    func save(_ state: StoredWebAppState) throws {
        self.state = state
        savedStates.append(state)
    }
}

@MainActor
final class TabStoreTests: XCTestCase {
    private let urlA = URL(string: "https://example.com/a")!
    private let urlB = URL(string: "https://example.com/b")!
    private let urlC = URL(string: "https://example.com/c")!

    func testAddProducesStableContinuousOrderAndSelectsNewSlot() {
        let repository = MemoryProfileRepository()
        let store = TabStore(repository: repository)

        let first = store.add(name: "A", homeURL: urlA)!
        let second = store.add(name: "B", homeURL: urlB)!
        let third = store.add(name: "C", homeURL: urlC)!

        XCTAssertEqual(store.orderedProfiles.map(\.order), [0, 1, 2])
        XCTAssertEqual(store.orderedProfiles.map(\.id), [first.id, second.id, third.id])
        XCTAssertEqual(store.activeTabID, third.id)
    }

    func testActiveSelectionUpdatesIdentity() {
        let store = TabStore(repository: MemoryProfileRepository())
        let first = store.add(name: "A", homeURL: urlA)!
        _ = store.add(name: "B", homeURL: urlB)!

        XCTAssertTrue(store.select(id: first.id))
        XCTAssertEqual(store.activeTabID, first.id)
    }

    func testRemovingActiveSlotSelectsNearestNeighborAtOriginalPosition() {
        let store = TabStore(repository: MemoryProfileRepository())
        _ = store.add(name: "A", homeURL: urlA)!
        let middle = store.add(name: "B", homeURL: urlB)!
        let last = store.add(name: "C", homeURL: urlC)!
        _ = store.select(id: middle.id)

        XCTAssertTrue(store.remove(id: middle.id))
        XCTAssertEqual(store.activeTabID, last.id)
        XCTAssertEqual(store.orderedProfiles.map(\.order), [0, 1])
    }

    func testRemovingFinalSlotProducesValidEmptyState() {
        let store = TabStore(repository: MemoryProfileRepository())
        let only = store.add(name: "A", homeURL: urlA)!

        XCTAssertTrue(store.remove(id: only.id))
        XCTAssertTrue(store.profiles.isEmpty)
        XCTAssertNil(store.activeTabID)
        XCTAssertNil(store.activeProfile)
    }

    func testReorderNormalizesOrderWithoutChangingSlotIDs() {
        let store = TabStore(repository: MemoryProfileRepository())
        let first = store.add(name: "A", homeURL: urlA)!
        let second = store.add(name: "B", homeURL: urlB)!
        let third = store.add(name: "C", homeURL: urlC)!
        let idsBefore = Set(store.profiles.map(\.id))

        XCTAssertTrue(store.move(id: third.id, toIndex: 0))

        XCTAssertEqual(store.orderedProfiles.map(\.id), [third.id, first.id, second.id])
        XCTAssertEqual(store.orderedProfiles.map(\.order), [0, 1, 2])
        XCTAssertEqual(Set(store.profiles.map(\.id)), idsBefore)
    }

    func testKeyboardIndexMappingFollowsVisibleOrderImmediately() {
        let store = TabStore(repository: MemoryProfileRepository())
        let first = store.add(name: "A", homeURL: urlA)!
        let second = store.add(name: "B", homeURL: urlB)!
        let third = store.add(name: "C", homeURL: urlC)!

        _ = store.move(id: third.id, toIndex: 0)

        XCTAssertEqual(store.slotByKeyboardIndex(1)?.id, third.id)
        XCTAssertEqual(store.slotByKeyboardIndex(2)?.id, first.id)
        XCTAssertEqual(store.slotByKeyboardIndex(3)?.id, second.id)
        XCTAssertNil(store.slotByKeyboardIndex(4))
        XCTAssertNil(store.slotByKeyboardIndex(0))
    }

    func testNextAndPreviousWrapAround() {
        let store = TabStore(repository: MemoryProfileRepository())
        let first = store.add(name: "A", homeURL: urlA)!
        _ = store.add(name: "B", homeURL: urlB)!
        let third = store.add(name: "C", homeURL: urlC)!

        _ = store.select(id: third.id)
        XCTAssertEqual(store.selectNext()?.id, first.id)
        XCTAssertEqual(store.selectPrevious()?.id, third.id)
    }

    func testPersistedDuplicateAndInvalidOrdersAreNormalizedContinuously() {
        let early = WebAppProfile(
            order: -4,
            name: "Early",
            homeURL: urlA,
            createdAt: Date(timeIntervalSince1970: 10),
            lastUsedAt: Date(timeIntervalSince1970: 10)
        )
        let duplicateA = WebAppProfile(
            order: 7,
            name: "Duplicate A",
            homeURL: urlB,
            createdAt: Date(timeIntervalSince1970: 20),
            lastUsedAt: Date(timeIntervalSince1970: 20)
        )
        let duplicateB = WebAppProfile(
            order: 7,
            name: "Duplicate B",
            homeURL: urlC,
            createdAt: Date(timeIntervalSince1970: 30),
            lastUsedAt: Date(timeIntervalSince1970: 30)
        )
        let repository = MemoryProfileRepository(
            state: StoredWebAppState(
                version: StoredWebAppState.currentVersion,
                profiles: [duplicateB, early, duplicateA],
                lastActiveTabID: duplicateB.id
            )
        )

        let store = TabStore(repository: repository)

        XCTAssertEqual(store.orderedProfiles.map(\.id), [early.id, duplicateA.id, duplicateB.id])
        XCTAssertEqual(store.orderedProfiles.map(\.order), [0, 1, 2])
        XCTAssertEqual(store.activeTabID, duplicateB.id)
    }

    func testDuplicatePersistedSlotIDsAreDeduplicatedBeforeUse() {
        let id = UUID()
        let first = WebAppProfile(
            id: id,
            order: 0,
            name: "First",
            homeURL: urlA,
            createdAt: Date(timeIntervalSince1970: 10),
            lastUsedAt: Date(timeIntervalSince1970: 10)
        )
        let duplicateIdentity = WebAppProfile(
            id: id,
            order: 4,
            name: "Duplicate identity",
            homeURL: urlB,
            createdAt: Date(timeIntervalSince1970: 20),
            lastUsedAt: Date(timeIntervalSince1970: 20)
        )
        let other = WebAppProfile(
            order: 9,
            name: "Other",
            homeURL: urlC,
            createdAt: Date(timeIntervalSince1970: 30),
            lastUsedAt: Date(timeIntervalSince1970: 30)
        )
        let repository = MemoryProfileRepository(
            state: StoredWebAppState(
                version: StoredWebAppState.currentVersion,
                profiles: [duplicateIdentity, other, first],
                lastActiveTabID: id
            )
        )

        let store = TabStore(repository: repository)

        XCTAssertEqual(store.orderedProfiles.count, 2)
        XCTAssertEqual(store.orderedProfiles.map(\.id), [id, other.id])
        XCTAssertEqual(store.orderedProfiles.map(\.order), [0, 1])
        XCTAssertEqual(store.orderedProfiles.first?.name, "First")
        XCTAssertEqual(store.activeTabID, id)
        XCTAssertEqual(repository.savedStates.last?.profiles.count, 2)
    }

    func testInvalidPersistedActiveIDIsRepairedAndPersisted() {
        let first = makeProfile(order: 7, name: "A", url: urlA)
        let second = makeProfile(order: 20, name: "B", url: urlB)
        let repository = MemoryProfileRepository(
            state: StoredWebAppState(
                version: StoredWebAppState.currentVersion,
                profiles: [second, first],
                lastActiveTabID: UUID()
            )
        )

        let store = TabStore(repository: repository)

        XCTAssertEqual(store.orderedProfiles.map(\.order), [0, 1])
        XCTAssertEqual(store.activeTabID, first.id)
        XCTAssertEqual(repository.savedStates.last?.lastActiveTabID, first.id)
        XCTAssertEqual(repository.savedStates.last?.profiles.map(\.order), [0, 1])
    }

    private func makeProfile(order: Int, name: String, url: URL) -> WebAppProfile {
        WebAppProfile(
            order: order,
            name: name,
            homeURL: url,
            createdAt: Date(timeIntervalSince1970: TimeInterval(order)),
            lastUsedAt: Date(timeIntervalSince1970: TimeInterval(order))
        )
    }
}

final class WebAppURLTests: XCTestCase {
    func testNormalizesBareHostToHTTPSAndRejectsUnsafeSchemes() {
        XCTAssertEqual(
            WebAppURL.normalized(from: "example.com")?.absoluteString,
            "https://example.com"
        )
        XCTAssertEqual(
            WebAppURL.normalized(from: "https://example.com/path")?.absoluteString,
            "https://example.com/path"
        )
        XCTAssertNil(WebAppURL.normalized(from: "javascript:alert(1)"))
        XCTAssertNil(WebAppURL.normalized(from: "file:///tmp/test.html"))
        XCTAssertNil(WebAppURL.normalized(from: "ftp://example.com/file"))
    }
}
