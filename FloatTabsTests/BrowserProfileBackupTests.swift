import AppKit
import WebKit
import XCTest
@testable import FloatTabs

@MainActor
final class BrowserProfileBackupTests: XCTestCase {
    private let homeURL = URL(string: "https://example.com/home")!

    func testRestorePersistenceFailureLeavesLiveModelAndRuntimeUntouched() throws {
        let repository = StageHProfileRepository()
        let store = TabStore(repository: repository)
        let slot = try XCTUnwrap(store.add(name: "Original", homeURL: homeURL))
        let pool = makePool()
        let controller = makePanelController(store: store, pool: pool)
        let oldWebView = try XCTUnwrap(pool.existingWebView(for: slot.id))
        let beforeState = store.storedStateSnapshot()
        let beforeActiveID = store.activeTabID
        let beforeIdentity = pool.browserProfileIdentity(for: slot.id)
        let beforeResidents = pool.residentSlotIDs

        let replacementSlot = WebAppProfile(
            id: UUID(),
            order: 0,
            name: "Replacement",
            homeURL: URL(string: "https://replacement.example")!
        )
        let replacement = StoredWebAppState(
            version: StoredWebAppState.currentVersion,
            profiles: [replacementSlot],
            lastActiveTabID: replacementSlot.id
        )
        repository.failNextSave = true

        XCTAssertFalse(controller.restoreStoredWebAppState(replacement))
        XCTAssertEqual(store.storedStateSnapshot(), beforeState)
        XCTAssertEqual(store.activeTabID, beforeActiveID)
        XCTAssertTrue(pool.existingWebView(for: slot.id) === oldWebView)
        XCTAssertEqual(pool.browserProfileIdentity(for: slot.id), beforeIdentity)
        XCTAssertEqual(pool.residentSlotIDs, beforeResidents)
    }

    func testValidProfileAwareRestoreRebuildsRuntimeWithRestoredProfileIdentity() throws {
        let repository = StageHProfileRepository()
        let store = TabStore(repository: repository)
        let slot = try XCTUnwrap(store.add(name: "Original", homeURL: homeURL))
        var resolvedCustomIDs: [UUID] = []
        let pool = makePool(customStoreResolver: { id in
            resolvedCustomIDs.append(id)
            return WKWebsiteDataStore.nonPersistent()
        })
        let controller = makePanelController(store: store, pool: pool)
        let browserProfile = BrowserProfile(
            id: UUID(),
            name: "Company",
            createdAt: Date(timeIntervalSince1970: 10)
        )
        var restoredSlot = slot
        restoredSlot.browserProfileID = browserProfile.id
        let restoredState = StoredWebAppState(
            version: StoredWebAppState.currentVersion,
            browserProfiles: [browserProfile],
            profiles: [restoredSlot],
            lastActiveTabID: slot.id
        )

        XCTAssertTrue(controller.restoreStoredWebAppState(restoredState))
        XCTAssertEqual(store.storedStateSnapshot(), restoredState)
        XCTAssertEqual(pool.browserProfileIdentity(for: slot.id), .custom(browserProfile.id))
        XCTAssertEqual(resolvedCustomIDs, [browserProfile.id])
    }

    private func makePanelController(store: TabStore, pool: WebViewPool) -> PanelController {
        PanelController(
            tabStore: store,
            webViewPool: pool,
            attentionCoordinator: WebAttentionCoordinator(),
            frameStore: PanelFrameStore(),
            preferencesStore: AppPreferencesStore(),
            confirmBrowserProfileSwitch: { _, _, _ in true }
        )
    }

    private func makePool(
        customStoreResolver: @escaping (UUID) -> WKWebsiteDataStore = { _ in
            WKWebsiteDataStore.nonPersistent()
        }
    ) -> WebViewPool {
        let provider = BrowserProfileDataStoreProvider(
            isCustomProfileSupported: { true },
            defaultStoreResolver: { WKWebsiteDataStore.nonPersistent() },
            customStoreResolver: customStoreResolver
        )
        return WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, _ in },
            browserProfileDataStoreProvider: provider
        )
    }
}

private enum StageHRepositoryError: Error {
    case saveFailed
}

private final class StageHProfileRepository: ProfileRepositoryProtocol {
    var state: StoredWebAppState
    var failNextSave = false

    init(state: StoredWebAppState = .empty) {
        self.state = state
    }

    func load() throws -> StoredWebAppState {
        state
    }

    func save(_ state: StoredWebAppState) throws {
        if failNextSave {
            failNextSave = false
            throw StageHRepositoryError.saveFailed
        }
        self.state = state
    }
}
