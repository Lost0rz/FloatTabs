import AppKit
import WebKit
import XCTest
@testable import FloatTabs

@MainActor
final class UnsupportedBrowserProfileTests: XCTestCase {
    private let homeURL = URL(string: "https://example.com/home")!

    func testUnsupportedCustomSlotShowsNamedPlaceholderWithoutRuntimeFallbackOrSave() throws {
        let repository = StageIProfileRepository()
        let store = TabStore(repository: repository)
        let company = try XCTUnwrap(store.createBrowserProfile(name: "Company"))
        let slot = try XCTUnwrap(
            store.add(
                name: "Web App",
                homeURL: homeURL,
                browserProfileID: company.id
            )
        )
        repository.events.removeAll()

        var defaultResolverCalls = 0
        var customResolverCalls = 0
        var initialLoadCalls = 0
        let pool = makePool(
            customProfilesSupported: false,
            defaultStoreResolver: {
                defaultResolverCalls += 1
                return WKWebsiteDataStore.nonPersistent()
            },
            customStoreResolver: { _ in
                customResolverCalls += 1
                return WKWebsiteDataStore.nonPersistent()
            },
            initialLoad: { _, _ in initialLoadCalls += 1 }
        )

        let controller = makePanelController(store: store, pool: pool)

        XCTAssertTrue(controller.isShowingUnsupportedBrowserProfile)
        XCTAssertEqual(controller.displayedUnsupportedBrowserProfileName, "Company")
        XCTAssertEqual(store.activeProfile?.browserProfileID, company.id)
        XCTAssertEqual(store.browserProfiles, [company])
        XCTAssertTrue(repository.events.isEmpty)
        XCTAssertEqual(defaultResolverCalls, 0)
        XCTAssertEqual(customResolverCalls, 0)
        XCTAssertEqual(initialLoadCalls, 0)
        XCTAssertTrue(pool.residentSlotIDs.isEmpty)
        XCTAssertNil(pool.browserProfileIdentity(for: slot.id))
        XCTAssertNil(pool.existingWebView(for: slot.id))
    }

    func testDefaultSlotRemainsNormalWhenCustomProfilesAreUnsupported() throws {
        let repository = StageIProfileRepository()
        let store = TabStore(repository: repository)
        let slot = try XCTUnwrap(store.add(name: "Web App", homeURL: homeURL))

        var defaultResolverCalls = 0
        var customResolverCalls = 0
        var initialLoadCalls = 0
        let pool = makePool(
            customProfilesSupported: false,
            defaultStoreResolver: {
                defaultResolverCalls += 1
                return WKWebsiteDataStore.nonPersistent()
            },
            customStoreResolver: { _ in
                customResolverCalls += 1
                return WKWebsiteDataStore.nonPersistent()
            },
            initialLoad: { _, _ in initialLoadCalls += 1 }
        )

        let controller = makePanelController(store: store, pool: pool)

        XCTAssertFalse(controller.isShowingUnsupportedBrowserProfile)
        XCTAssertNotNil(pool.existingWebView(for: slot.id))
        XCTAssertEqual(pool.browserProfileIdentity(for: slot.id), .default)
        XCTAssertEqual(defaultResolverCalls, 1)
        XCTAssertEqual(customResolverCalls, 0)
        XCTAssertEqual(initialLoadCalls, 1)
    }

    func testExplicitDefaultReassignmentReplacesUnsupportedPlaceholderAndKeepsMetadata() throws {
        let repository = StageIProfileRepository()
        let store = TabStore(repository: repository)
        let company = try XCTUnwrap(store.createBrowserProfile(name: "Company"))
        let slot = try XCTUnwrap(
            store.add(
                name: "Web App",
                homeURL: homeURL,
                browserProfileID: company.id
            )
        )
        repository.events.removeAll()

        var defaultResolverCalls = 0
        var initialLoadCalls = 0
        let pool = makePool(
            customProfilesSupported: false,
            defaultStoreResolver: {
                defaultResolverCalls += 1
                return WKWebsiteDataStore.nonPersistent()
            },
            initialLoad: { _, _ in initialLoadCalls += 1 }
        )
        let controller = makePanelController(store: store, pool: pool)

        XCTAssertTrue(controller.isShowingUnsupportedBrowserProfile)
        XCTAssertTrue(
            controller.requestBrowserProfileSwitch(
                slotID: slot.id,
                targetProfileID: nil
            )
        )

        XCTAssertNil(store.activeProfile?.browserProfileID)
        XCTAssertEqual(store.browserProfiles, [company])
        XCTAssertEqual(repository.events, ["save-target"])
        XCTAssertEqual(defaultResolverCalls, 1)
        XCTAssertEqual(initialLoadCalls, 1)
        XCTAssertEqual(pool.browserProfileIdentity(for: slot.id), .default)
        XCTAssertNotNil(pool.existingWebView(for: slot.id))
        XCTAssertFalse(controller.isShowingUnsupportedBrowserProfile)
        XCTAssertNil(controller.displayedUnsupportedBrowserProfileName)
    }

    func testUnsupportedCustomProfileMenuKeepsCurrentCheckAndEnablesDefault() throws {
        let slotID = UUID()
        let company = BrowserProfile(
            id: UUID(),
            name: "Company",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let tab = ExternalWebAppTabView(slotID: slotID)
        tab.update(
            profile: WebAppProfile(
                id: slotID,
                browserProfileID: company.id,
                order: 0,
                name: "Web App",
                homeURL: homeURL
            ),
            isActive: true,
            isResident: false
        )
        tab.setBrowserProfileMenuSnapshot(
            options: [
                .defaultProfile,
                BrowserProfileMenuOption(
                    id: company.id,
                    name: company.name,
                    isEnabled: false
                ),
            ],
            assignmentEnabled: true
        )

        let event = NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: NSPoint(x: 20, y: 20),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        )!
        let menu = try XCTUnwrap(tab.menu(for: event))
        let items = try XCTUnwrap(menu.item(withTitle: "Profile")?.submenu?.items)

        XCTAssertTrue(items[0].isEnabled)
        XCTAssertEqual(items[0].state, .off)
        XCTAssertFalse(items[1].isEnabled)
        XCTAssertEqual(items[1].state, .on)
    }

    func testUnsupportedClassificationRequiresCustomBindingAndSpecificProviderError() {
        let company = BrowserProfile(
            id: UUID(),
            name: "Company",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let customSlot = WebAppProfile(
            browserProfileID: company.id,
            order: 0,
            name: "Custom Slot",
            homeURL: homeURL
        )
        let defaultSlot = WebAppProfile(
            order: 1,
            name: "Default Slot",
            homeURL: homeURL
        )

        XCTAssertEqual(
            PanelController.unsupportedBrowserProfileName(
                for: customSlot,
                error: BrowserProfileDataStoreProviderError.customProfilesUnsupported,
                browserProfiles: [company]
            ),
            "Company"
        )
        XCTAssertEqual(
            PanelController.unsupportedBrowserProfileName(
                for: customSlot,
                error: BrowserProfileDataStoreProviderError.customProfilesUnsupported,
                browserProfiles: []
            ),
            "Selected Profile"
        )
        XCTAssertNil(
            PanelController.unsupportedBrowserProfileName(
                for: defaultSlot,
                error: BrowserProfileDataStoreProviderError.customProfilesUnsupported,
                browserProfiles: [company]
            )
        )
        XCTAssertNil(
            PanelController.unsupportedBrowserProfileName(
                for: customSlot,
                error: StageIUnrelatedError.failure,
                browserProfiles: [company]
            )
        )
    }

    func testContainerReplacesUnsupportedPlaceholderWithWebViewAndClearsItForEmptyState() {
        let container = WebPanelContainerView(
            frame: NSRect(x: 0, y: 0, width: 500, height: 400)
        )
        container.showUnsupportedBrowserProfile(profileName: "Company")

        XCTAssertTrue(container.isShowingUnsupportedBrowserProfile)
        XCTAssertEqual(container.displayedUnsupportedBrowserProfileName, "Company")

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        container.show(webView: webView)

        XCTAssertFalse(container.isShowingUnsupportedBrowserProfile)
        XCTAssertNil(container.displayedUnsupportedBrowserProfileName)
        XCTAssertTrue(container.currentWebView === webView)

        container.showUnsupportedBrowserProfile(profileName: "Company")
        container.showEmptyState()

        XCTAssertFalse(container.isShowingUnsupportedBrowserProfile)
        XCTAssertNil(container.displayedUnsupportedBrowserProfileName)
        XCTAssertNil(container.currentWebView)
    }

    func testPlaceholderExplainsBindingCapabilityAndExplicitDefaultRecovery() {
        let view = UnsupportedBrowserProfileView()
        view.show(profileName: "Company")

        XCTAssertEqual(view.titleText, "Profile Requires macOS 14 or Later")
        XCTAssertTrue(view.detailText.contains("Company"))
        XCTAssertTrue(view.detailText.contains("still assigned"))
        XCTAssertTrue(view.detailText.contains("requires macOS 14 or later"))
        XCTAssertTrue(view.detailText.contains("did not open it with Default"))
        XCTAssertTrue(view.detailText.contains("Profile > Default"))
    }

    func testFullscreenCompanionCanPhysicallyPresentUnsupportedPlaceholder() {
        let root = PanelRootView()
        let companion = WebPanelContainerView()

        root.installFullscreenCompanionContainer(companion)
        companion.showUnsupportedBrowserProfile(profileName: "Company")

        XCTAssertTrue(companion.superview === root)
        XCTAssertTrue(companion.isShowingUnsupportedBrowserProfile)
        XCTAssertEqual(companion.displayedUnsupportedBrowserProfileName, "Company")
        XCTAssertNil(root.fullscreenExitPlaceholderView.superview)
    }

    private func makePanelController(
        store: TabStore,
        pool: WebViewPool
    ) -> PanelController {
        PanelController(
            tabStore: store,
            webViewPool: pool,
            attentionCoordinator: WebAttentionCoordinator(),
            frameStore: PanelFrameStore(),
            preferencesStore: AppPreferencesStore(),
            confirmBrowserProfileSwitch: { _, _ in true }
        )
    }

    private func makePool(
        customProfilesSupported: Bool,
        defaultStoreResolver: @escaping () -> WKWebsiteDataStore = {
            WKWebsiteDataStore.nonPersistent()
        },
        customStoreResolver: @escaping (UUID) -> WKWebsiteDataStore = { _ in
            WKWebsiteDataStore.nonPersistent()
        },
        initialLoad: @escaping WebViewPool.LoadHandler = { _, _ in }
    ) -> WebViewPool {
        let provider = BrowserProfileDataStoreProvider(
            isCustomProfileSupported: { customProfilesSupported },
            defaultStoreResolver: defaultStoreResolver,
            customStoreResolver: customStoreResolver
        )
        return WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: initialLoad,
            browserProfileDataStoreProvider: provider
        )
    }
}

private enum StageIUnrelatedError: Error {
    case failure
}

private final class StageIProfileRepository: ProfileRepositoryProtocol {
    var state: StoredWebAppState = .empty
    var events: [String] = []

    func load() throws -> StoredWebAppState {
        state
    }

    func save(_ state: StoredWebAppState) throws {
        self.state = state
        events.append("save-target")
    }
}
