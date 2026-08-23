import AppKit
import WebKit
import XCTest
@testable import FloatTabs

@MainActor
final class BrowserProfileSettingsTests: XCTestCase {
    func testDefaultListedFirstAndPreservesCustomOrder() {
        let company = makeBrowserProfile(name: "Company")
        let personal = makeBrowserProfile(name: "Personal")
        let controller = makeSettingsController(
            snapshot: {
                BrowserProfileManagementSnapshot(
                    customProfiles: [company, personal],
                    referencedProfileIDs: [],
                    customProfilesSupported: true
                )
            }
        )

        controller.loadView()

        XCTAssertEqual(controller.displayedBrowserProfileNames, ["Default", "Company", "Personal"])
    }

    func testEmptySnapshotHasDefaultOnlyAndNoPresets() {
        let controller = makeSettingsController()

        controller.loadView()

        XCTAssertEqual(controller.displayedBrowserProfileNames, ["Default"])
        XCTAssertEqual(controller.displayedBrowserProfileActionTitles, [[]])
        XCTAssertEqual(controller.displayedBrowserProfileDeleteEnabled, [false])
    }

    func testReferencedProfilePreflightThrowsReferenced() {
        let profile = makeBrowserProfile(name: "Company")
        let controller = makeSettingsController(
            snapshot: {
                BrowserProfileManagementSnapshot(
                    customProfiles: [profile],
                    referencedProfileIDs: [profile.id],
                    customProfilesSupported: true
                )
            }
        )

        controller.loadView()

        XCTAssertThrowsError(try controller.profileDeletionCandidate(id: profile.id)) { error in
            XCTAssertEqual(error as? BrowserProfileManagementError, .referenced)
        }
    }

    func testReferencedProfileDeleteActionIsDisabled() {
        let profile = makeBrowserProfile(name: "Company")
        let controller = makeSettingsController(
            snapshot: {
                BrowserProfileManagementSnapshot(
                    customProfiles: [profile],
                    referencedProfileIDs: [profile.id],
                    customProfilesSupported: true
                )
            }
        )

        controller.loadView()

        XCTAssertEqual(controller.displayedBrowserProfileDeleteEnabled, [false, false])
    }

    func testUnreferencedProfilePreflightSucceeds() throws {
        let profile = makeBrowserProfile(name: "Company")
        let controller = makeSettingsController(
            snapshot: {
                BrowserProfileManagementSnapshot(
                    customProfiles: [profile],
                    referencedProfileIDs: [],
                    customProfilesSupported: true
                )
            }
        )

        controller.loadView()

        XCTAssertEqual(try controller.profileDeletionCandidate(id: profile.id), profile)
    }

    func testCreatePassesExactTrimmedNameToManager() {
        var receivedName: String?
        let controller = makeSettingsController(
            create: { name in
                receivedName = name
                return self.makeBrowserProfile(name: name)
            }
        )
        controller.loadView()

        controller.submitNewProfileNameForTesting("   Company   ")

        XCTAssertEqual(receivedName, "Company")
    }

    func testRenamePreservesIDThroughManagerContract() throws {
        let profile = makeBrowserProfile(name: "Company")
        var receivedID: UUID?
        var receivedName: String?
        let manager = BrowserProfileManagementClient(
            snapshot: {
                BrowserProfileManagementSnapshot(
                    customProfiles: [profile],
                    referencedProfileIDs: [],
                    customProfilesSupported: true
                )
            },
            create: { _ in profile },
            rename: { id, name in
                receivedID = id
                receivedName = name
            },
            delete: { _ in }
        )

        try manager.rename(id: profile.id, name: "Renamed")

        XCTAssertEqual(receivedID, profile.id)
        XCTAssertEqual(receivedName, "Renamed")
    }

    func testReferencedDeleteRejectedBeforeWebKitRemovalAndMetadataDelete() async throws {
        let repository = StageDProfileRepository()
        let store = TabStore(repository: repository)
        let browserProfile = try XCTUnwrap(store.createBrowserProfile(name: "Company"))
        let slot = try XCTUnwrap(
            store.add(name: "Web App", homeURL: URL(string: "https://example.com")!)
        )
        XCTAssertTrue(store.setBrowserProfile(slotID: slot.id, profileID: browserProfile.id))
        _ = store.add(name: "Active Web App", homeURL: URL(string: "https://example.com/active")!)
        repository.events.removeAll()

        var removerCallCount = 0
        let pool = makePool { _ in removerCallCount += 1 }
        let controller = makePanelController(store: store, pool: pool)

        do {
            try await controller.deleteBrowserProfile(id: browserProfile.id)
            XCTFail("Referenced Profile deletion must fail")
        } catch let error as BrowserProfileManagementError {
            XCTAssertEqual(error, .referenced)
        }

        XCTAssertEqual(removerCallCount, 0)
        XCTAssertTrue(store.browserProfiles.contains(where: { $0.id == browserProfile.id }))
        XCTAssertTrue(repository.events.isEmpty)
    }

    func testWebKitDeletionFailureLeavesMetadata() async throws {
        let repository = StageDProfileRepository()
        let store = TabStore(repository: repository)
        let browserProfile = try XCTUnwrap(store.createBrowserProfile(name: "Company"))
        repository.events.removeAll()
        let pool = makePool { _ in throw StageDError.removalFailed }
        let controller = makePanelController(store: store, pool: pool)

        do {
            try await controller.deleteBrowserProfile(id: browserProfile.id)
            XCTFail("WebKit removal failure must be reported")
        } catch let error as StageDError {
            XCTAssertEqual(error, .removalFailed)
        }

        XCTAssertTrue(store.browserProfiles.contains(where: { $0.id == browserProfile.id }))
        XCTAssertTrue(repository.events.isEmpty)
    }

    func testUnsupportedOSShowsDefaultExplanationAndNeverCallsCreate() {
        var createCallCount = 0
        let controller = makeSettingsController(
            customProfilesSupported: false,
            create: { _ in
                createCallCount += 1
                return self.makeBrowserProfile(name: "Unexpected")
            }
        )
        controller.loadView()

        controller.submitNewProfileNameForTesting("Company")

        XCTAssertEqual(controller.displayedBrowserProfileNames, ["Default"])
        XCTAssertFalse(controller.isNewProfileEnabled)
        XCTAssertEqual(
            controller.profileSupportDescription,
            "Additional Profiles require macOS 14 or later."
        )
        XCTAssertEqual(createCallCount, 0)
    }

    func testSuccessfulDeleteOrdersRuntimeReleaseStoreRemovalThenMetadataDelete() async throws {
        let repository = StageDProfileRepository()
        let store = TabStore(repository: repository)
        let browserProfile = try XCTUnwrap(store.createBrowserProfile(name: "Company"))
        let slot = try XCTUnwrap(
            store.add(name: "Web App", homeURL: URL(string: "https://example.com")!)
        )
        XCTAssertTrue(store.setBrowserProfile(slotID: slot.id, profileID: browserProfile.id))
        _ = store.add(name: "Active Web App", homeURL: URL(string: "https://example.com/active")!)

        var events: [String] = []
        let pool = makePool { _ in events.append("remove-webkit-store") }
        let runtimeProfile = try XCTUnwrap(store.profiles.first(where: { $0.id == slot.id }))
        _ = try pool.webView(for: runtimeProfile)
        XCTAssertEqual(pool.browserProfileIdentity(for: runtimeProfile.id), .custom(browserProfile.id))

        // The persisted reference is removed without touching the already-live
        // runtime, modeling the stale identity boundary in Stage C.
        XCTAssertTrue(store.setBrowserProfile(slotID: slot.id, profileID: nil))
        repository.events.removeAll()
        XCTAssertNotEqual(store.activeTabID, slot.id)
        XCTAssertTrue(pool.contains(slotID: slot.id))
        XCTAssertEqual(pool.residentSlotIDs(using: .custom(browserProfile.id)), [slot.id])

        let controller = makePanelController(store: store, pool: pool)
        XCTAssertTrue(pool.contains(slotID: slot.id))
        XCTAssertEqual(pool.residentSlotIDs(using: .custom(browserProfile.id)), [slot.id])
        pool.onResidentSetChange = { events.append("release-runtime") }
        try await controller.deleteBrowserProfile(id: browserProfile.id)

        XCTAssertEqual(
            events + repository.events,
            ["release-runtime", "remove-webkit-store", "delete-metadata"]
        )
        XCTAssertTrue(pool.residentSlotIDs(using: .custom(browserProfile.id)).isEmpty)
        XCTAssertFalse(store.browserProfiles.contains(where: { $0.id == browserProfile.id }))
    }

    func testStaleRuntimeIsReleasedBeforeCustomStoreRemoval() async throws {
        let repository = StageDProfileRepository()
        let store = TabStore(repository: repository)
        let browserProfile = try XCTUnwrap(store.createBrowserProfile(name: "Company"))
        let slot = try XCTUnwrap(
            store.add(name: "Web App", homeURL: URL(string: "https://example.com")!)
        )
        XCTAssertTrue(store.setBrowserProfile(slotID: slot.id, profileID: browserProfile.id))
        _ = store.add(name: "Active Web App", homeURL: URL(string: "https://example.com/active")!)
        let pool = makePool { _ in }
        let runtimeProfile = try XCTUnwrap(store.profiles.first(where: { $0.id == slot.id }))
        _ = try pool.webView(for: runtimeProfile)
        XCTAssertTrue(store.setBrowserProfile(slotID: slot.id, profileID: nil))
        XCTAssertTrue(pool.contains(slotID: slot.id))
        XCTAssertEqual(pool.residentSlotIDs(using: .custom(browserProfile.id)), [slot.id])

        let controller = makePanelController(store: store, pool: pool)
        try await controller.deleteBrowserProfile(id: browserProfile.id)

        XCTAssertFalse(pool.contains(slotID: slot.id))
        XCTAssertTrue(pool.residentSlotIDs(using: .custom(browserProfile.id)).isEmpty)
    }

    func testDefaultRowHasNoRenameOrDeleteActions() {
        let profile = makeBrowserProfile(name: "Company")
        let controller = makeSettingsController(
            snapshot: {
                BrowserProfileManagementSnapshot(
                    customProfiles: [profile],
                    referencedProfileIDs: [],
                    customProfilesSupported: true
                )
            }
        )
        controller.loadView()

        XCTAssertEqual(controller.displayedBrowserProfileActionTitles.first, [])
        XCTAssertEqual(controller.displayedBrowserProfileActionTitles.dropFirst().first, ["Rename…", "Delete…"])
        XCTAssertEqual(controller.displayedBrowserProfileDeleteEnabled, [false, true])
    }

    private func makeSettingsController(
        snapshot: (() -> BrowserProfileManagementSnapshot)? = nil,
        customProfilesSupported: Bool = true,
        create: ((String) throws -> BrowserProfile)? = nil
    ) -> AccountLanguageSettingsViewController {
        let resolvedSnapshot = snapshot ?? {
            BrowserProfileManagementSnapshot(
                customProfiles: [],
                referencedProfileIDs: [],
                customProfilesSupported: customProfilesSupported
            )
        }
        let manager = BrowserProfileManagementClient(
            snapshot: resolvedSnapshot,
            create: create ?? { name in self.makeBrowserProfile(name: name) },
            rename: { _, _ in },
            delete: { _ in }
        )
        return AccountLanguageSettingsViewController(
            onExportBackup: { _ in },
            onRestoreBackup: { _ in URL(fileURLWithPath: "/tmp/rollback.json") },
            browserProfileManager: manager
        )
    }

    private func makeBrowserProfile(name: String) -> BrowserProfile {
        BrowserProfile(id: UUID(), name: name, createdAt: Date(timeIntervalSince1970: 1))
    }

    private func makePanelController(store: TabStore, pool: WebViewPool) -> PanelController {
        let controller = PanelController(
            tabStore: store,
            webViewPool: pool,
            frameStore: PanelFrameStore(),
            preferencesStore: AppPreferencesStore()
        )
        return controller
    }

    private func makePool(
        _ remover: @escaping (UUID) async throws -> Void
    ) -> WebViewPool {
        let store = WKWebsiteDataStore.nonPersistent()
        let provider = BrowserProfileDataStoreProvider(
            isCustomProfileSupported: { true },
            customStoreResolver: { _ in store },
            customStoreRemover: remover
        )
        return WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, _ in },
            browserProfileDataStoreProvider: provider
        )
    }
}

private enum StageDError: Error, Equatable {
    case removalFailed
}

private final class StageDProfileRepository: ProfileRepositoryProtocol {
    var state: StoredWebAppState
    var events: [String] = []

    init(state: StoredWebAppState = .empty) {
        self.state = state
    }

    func load() throws -> StoredWebAppState {
        state
    }

    func save(_ state: StoredWebAppState) throws {
        self.state = state
        events.append("delete-metadata")
    }
}
