import WebKit
import XCTest
@testable import FloatTabs

@MainActor
final class BrowserProfileAddTests: XCTestCase {
    private let homeURL = URL(string: "https://example.com/app")!

    func testAddDefaultsToDefaultProfileInFirstSlot() throws {
        let repository = StageEProfileRepository()
        let store = TabStore(repository: repository)

        let added = try XCTUnwrap(store.add(name: "Default App", homeURL: homeURL))

        XCTAssertNil(added.browserProfileID)
        XCTAssertEqual(repository.savedStates.count, 1)
        XCTAssertNil(repository.savedStates[0].profiles.first?.browserProfileID)
    }

    func testAddCustomPersistsProfileInFirstDurableSave() throws {
        let browserProfile = makeBrowserProfile(name: "Company")
        let repository = StageEProfileRepository(
            state: StoredWebAppState(
                version: StoredWebAppState.currentVersion,
                browserProfiles: [browserProfile],
                profiles: [],
                lastActiveTabID: nil
            )
        )
        let store = TabStore(repository: repository)
        let rendering = WebRenderingProfile(
            websiteMode: .mobile,
            browserIdentity: .androidChrome,
            customUserAgent: nil,
            sizePreset: .small,
            devicePresetID: nil,
            orientation: .portrait,
            viewportWidth: 390,
            viewportHeight: 780,
            zoom: 1.50
        )

        let added = try XCTUnwrap(
            store.add(
                name: "Company App",
                homeURL: homeURL,
                renderingProfile: rendering,
                browserProfileID: browserProfile.id
            )
        )

        XCTAssertEqual(added.browserProfileID, browserProfile.id)
        XCTAssertEqual(repository.savedStates.count, 1)
        XCTAssertEqual(
            repository.savedStates[0].profiles.first?.browserProfileID,
            browserProfile.id
        )
        XCTAssertEqual(
            repository.savedStates[0].profiles.first?.renderingProfile,
            rendering.normalized()
        )
    }

    func testMissingProfileRejectsAddWithoutMutationOrSave() {
        let repository = StageEProfileRepository()
        let store = TabStore(repository: repository)
        let previousActiveID = store.activeTabID
        let missingID = UUID()

        XCTAssertNil(
            store.add(
                name: "Missing Profile App",
                homeURL: homeURL,
                browserProfileID: missingID
            )
        )
        XCTAssertTrue(store.profiles.isEmpty)
        XCTAssertEqual(store.activeTabID, previousActiveID)
        XCTAssertTrue(repository.savedStates.isEmpty)
    }

    func testAddOptionsDefaultFirstAndCustomSelectionCarriesExactUUID() throws {
        let company = makeBrowserProfile(name: "Company")
        let personal = makeBrowserProfile(name: "Personal")
        let options = WebAppEditorController.browserProfileOptions(
            browserProfiles: [company, personal],
            customProfilesSupported: true
        )

        XCTAssertEqual(options.map(\.name), ["Default", "Company", "Personal"])
        let companyOption = try XCTUnwrap(options.first(where: { $0.name == "Company" }))
        let value = WebAppEditorController.makeValue(
            name: "Company App",
            url: homeURL,
            homeURLSchemeWasInferred: false,
            renderingProfile: .canonicalDefault,
            browserProfileID: companyOption.id
        )

        XCTAssertEqual(value.browserProfileID, company.id)
    }

    func testAddOptionsUseRenamedDefaultLabelButKeepNilIdentity() throws {
        let options = WebAppEditorController.browserProfileOptions(
            browserProfiles: [],
            customProfilesSupported: true,
            defaultProfileName: "Jack"
        )

        let defaultOption = try XCTUnwrap(options.first)
        XCTAssertEqual(defaultOption.name, "Jack")
        XCTAssertNil(defaultOption.id)

        let value = WebAppEditorController.makeValue(
            name: "Default App",
            url: homeURL,
            homeURLSchemeWasInferred: false,
            renderingProfile: .canonicalDefault,
            browserProfileID: defaultOption.id
        )
        XCTAssertNil(value.browserProfileID)
    }

    func testUnsupportedCustomOptionsCannotBeSelectedAsEnabledAdd() throws {
        let company = makeBrowserProfile(name: "Company")
        let options = WebAppEditorController.browserProfileOptions(
            browserProfiles: [company],
            customProfilesSupported: false
        )

        XCTAssertTrue(try XCTUnwrap(options.first(where: { $0.id == nil })).isEnabled)
        XCTAssertFalse(try XCTUnwrap(options.first(where: { $0.id == company.id })).isEnabled)
    }

    func testCustomAddOnChangeCreatesFirstWebViewWithCustomStoreBeforeLoad() throws {
        let browserProfile = makeBrowserProfile(name: "Company")
        let repository = StageEProfileRepository(
            state: StoredWebAppState(
                version: StoredWebAppState.currentVersion,
                browserProfiles: [browserProfile],
                profiles: [],
                lastActiveTabID: nil
            )
        )
        let store = TabStore(repository: repository)
        let customStore = WKWebsiteDataStore.nonPersistent()
        var defaultResolverCalls = 0
        var resolvedCustomIDs: [UUID] = []
        var loadedRequests: [URLRequest] = []
        let provider = BrowserProfileDataStoreProvider(
            isCustomProfileSupported: { true },
            defaultStoreResolver: {
                defaultResolverCalls += 1
                return WKWebsiteDataStore.nonPersistent()
            },
            customStoreResolver: { id in
                resolvedCustomIDs.append(id)
                return customStore
            }
        )
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { webView, request in
                XCTAssertTrue(webView.configuration.websiteDataStore === customStore)
                loadedRequests.append(request)
            },
            browserProfileDataStoreProvider: provider
        )
        var onChangeCalls = 0
        store.onChange = {
            onChangeCalls += 1
            guard let activeProfile = store.activeProfile else { return }
            do {
                _ = try pool.webView(for: activeProfile)
            } catch {
                XCTFail("First synchronized WebView creation failed: \(error)")
            }
        }

        let added = try XCTUnwrap(
            store.add(
                name: "Company App",
                homeURL: homeURL,
                browserProfileID: browserProfile.id
            )
        )

        XCTAssertEqual(onChangeCalls, 1)
        XCTAssertEqual(resolvedCustomIDs, [browserProfile.id])
        XCTAssertEqual(defaultResolverCalls, 0)
        XCTAssertEqual(loadedRequests.map(\.url), [homeURL])
        XCTAssertEqual(pool.browserProfileIdentity(for: added.id), .custom(browserProfile.id))
    }

    func testEditValueRetainsExistingProfileWithoutPickerMutation() {
        let existingID = UUID()

        let value = WebAppEditorController.makeValue(
            name: "Edited",
            url: homeURL,
            homeURLSchemeWasInferred: false,
            renderingProfile: .canonicalDefault,
            browserProfileID: existingID
        )

        XCTAssertEqual(value.browserProfileID, existingID)
    }

    private func makeBrowserProfile(name: String) -> BrowserProfile {
        BrowserProfile(
            id: UUID(),
            name: name,
            createdAt: Date(timeIntervalSince1970: 1)
        )
    }
}

private final class StageEProfileRepository: ProfileRepositoryProtocol {
    var state: StoredWebAppState
    var savedStates: [StoredWebAppState] = []

    init(state: StoredWebAppState = .empty) {
        self.state = state
    }

    func load() throws -> StoredWebAppState {
        state
    }

    func save(_ state: StoredWebAppState) throws {
        self.state = state
        savedStates.append(state)
    }
}
