import AppKit
import WebKit
import XCTest
@testable import FloatTabs

@MainActor
final class BrowserProfileDuplicateTests: XCTestCase {
    private let homeURL = URL(string: "https://example.com/home")!
    private let sourceURL = URL(string: "https://example.com/source-live")!
    private let duplicateURL = URL(string: "https://example.com/duplicate-only")!

    func testDuplicateMenuIsSiblingAndCarriesExactProfileIDs() throws {
        let slotID = UUID()
        let company = makeBrowserProfile(name: "Company")
        let personal = makeBrowserProfile(name: "Personal")
        let tab = ExternalWebAppTabView(slotID: slotID)
        tab.update(
            profile: makeWebApp(id: slotID, browserProfileID: company.id, name: "YouTube"),
            isActive: true,
            isResident: true
        )
        tab.setBrowserProfileMenuSnapshot(
            options: [
                .defaultProfile,
                BrowserProfileMenuOption(id: company.id, name: company.name, isEnabled: true),
                BrowserProfileMenuOption(id: personal.id, name: personal.name, isEnabled: true),
            ],
            assignmentEnabled: true,
            duplicationEnabled: true
        )

        let menu = try XCTUnwrap(tab.menu(for: makeMenuEvent()))
        let profile = try XCTUnwrap(menu.item(withTitle: "Profile"))
        let duplicate = try XCTUnwrap(
            menu.item(withTitle: "Open in New Tab with Profile")
        )
        let duplicateMenu = try XCTUnwrap(duplicate.submenu)

        XCTAssertEqual(
            menu.items.filter { !$0.isSeparatorItem }.map(\.title),
            [
                "Return to Home", "Reload", "Website Mode", "Window Size", "Zoom",
                "Profile", "Open in New Tab with Profile", "Residency",
                "Background Media", "Edit Web App…", "Remove Web App…",
            ]
        )
        XCTAssertEqual(
            duplicateMenu.items.map(\.title),
            ["Default", "Company", "Personal"]
        )
        XCTAssertEqual(
            duplicateMenu.item(withTitle: "Company")?.representedObject as? String,
            company.id.uuidString
        )
        XCTAssertTrue(duplicateMenu.item(withTitle: "Default")?.representedObject is NSNull)
        XCTAssertNil(duplicateMenu.item(withTitle: "Manage Profiles…"))
        XCTAssertTrue(profile.submenu?.item(withTitle: "Manage Profiles…") != nil)
    }

    func testUnsupportedAndFullscreenDuplicateTargetsFailClosedWithoutDefaultFallback() throws {
        let companyID = UUID()
        let tab = ExternalWebAppTabView(slotID: UUID())
        tab.update(
            profile: makeWebApp(name: "YouTube"),
            isActive: true,
            isResident: true
        )
        tab.setBrowserProfileMenuSnapshot(
            options: [
                .defaultProfile,
                BrowserProfileMenuOption(id: companyID, name: "Company", isEnabled: false),
            ],
            assignmentEnabled: true,
            duplicationEnabled: true
        )

        var menu = try XCTUnwrap(tab.menu(for: makeMenuEvent()))
        var items = try XCTUnwrap(
            menu.item(withTitle: "Open in New Tab with Profile")?.submenu?.items
        )
        XCTAssertTrue(items[0].isEnabled)
        XCTAssertFalse(items[1].isEnabled)

        tab.setBrowserProfileDuplicationEnabled(false)
        menu = try XCTUnwrap(tab.menu(for: makeMenuEvent()))
        items = try XCTUnwrap(
            menu.item(withTitle: "Open in New Tab with Profile")?.submenu?.items
        )
        XCTAssertFalse(items[0].isEnabled)
        XCTAssertFalse(items[1].isEnabled)

        XCTAssertFalse(
            PanelController.canRequestOpenInNewTabWithBrowserProfile(
                sourceExists: true,
                targetProfileID: companyID,
                targetExists: true,
                customProfilesSupported: false,
                sessionIsLocked: false
            )
        )
        XCTAssertFalse(
            PanelController.canRequestOpenInNewTabWithBrowserProfile(
                sourceExists: true,
                targetProfileID: nil,
                targetExists: true,
                customProfilesSupported: false,
                sessionIsLocked: true
            )
        )
        XCTAssertTrue(
            PanelController.canRequestOpenInNewTabWithBrowserProfile(
                sourceExists: true,
                targetProfileID: nil,
                targetExists: true,
                customProfilesSupported: false,
                sessionIsLocked: false
            )
        )
    }

    func testProfileSuffixUpdatesHoverAccessibilityAndTooltipAfterRename() throws {
        let companyID = UUID()
        let tab = ExternalWebAppTabView(slotID: UUID())
        let webApp = makeWebApp(browserProfileID: companyID, name: "YouTube")
        tab.update(profile: webApp, isActive: true, isResident: true)
        tab.setBrowserProfileMenuSnapshot(
            options: [
                .defaultProfile,
                BrowserProfileMenuOption(id: companyID, name: "Company", isEnabled: true),
            ],
            assignmentEnabled: true,
            duplicationEnabled: true
        )
        tab.setHovered(true)

        XCTAssertEqual(tab.displayedLabelText, "YouTube · Company")
        XCTAssertEqual(tab.accessibilityLabel(), "YouTube · Company")
        XCTAssertEqual(tab.toolTip, "YouTube · Company · Open")
        XCTAssertEqual(webApp.name, "YouTube")

        tab.setBrowserProfileMenuSnapshot(
            options: [
                .defaultProfile,
                BrowserProfileMenuOption(id: companyID, name: "Renamed", isEnabled: true),
            ],
            assignmentEnabled: true,
            duplicationEnabled: true
        )

        XCTAssertEqual(tab.displayedLabelText, "YouTube · Renamed")
        XCTAssertEqual(tab.accessibilityLabel(), "YouTube · Renamed")
        XCTAssertEqual(tab.toolTip, "YouTube · Renamed · Open")
        XCTAssertEqual(webApp.name, "YouTube")
    }

    func testDuplicatePersistsTargetBeforeFirstResolverAndLoadsSourceCurrentURL() throws {
        let repository = StageGProfileRepository()
        let store = TabStore(repository: repository)
        let company = try XCTUnwrap(store.createBrowserProfile(name: "Company"))
        let source = try XCTUnwrap(store.add(name: "YouTube", homeURL: homeURL))
        store.updateCurrentURL(id: source.id, url: sourceURL)
        repository.events.removeAll()

        var runtimeEvents: [String] = []
        let pool = makePool(
            customStoreResolver: { id in
                runtimeEvents.append("resolve-custom-\(id.uuidString)")
                return WKWebsiteDataStore.nonPersistent()
            },
            initialLoad: { _, request in
                runtimeEvents.append("load-\(request.url!.absoluteString)")
            }
        )
        let controller = makePanelController(store: store, pool: pool)
        runtimeEvents.removeAll()
        repository.events.removeAll()

        let duplicate = try XCTUnwrap(
            controller.requestOpenInNewTabWithBrowserProfile(
                sourceSlotID: source.id,
                targetProfileID: company.id
            )
        )

        XCTAssertEqual(
            repository.events + runtimeEvents,
            [
                "save-\(duplicate.id.uuidString)",
                "resolve-custom-\(company.id.uuidString)",
                "load-\(sourceURL.absoluteString)",
            ]
        )
        XCTAssertEqual(repository.state.profiles.last?.browserProfileID, company.id)
        XCTAssertEqual(duplicate.currentURL, sourceURL)
        XCTAssertEqual(pool.browserProfileIdentity(for: duplicate.id), .custom(company.id))
    }

    func testSuccessfulDuplicateLeavesSourceRuntimeAndReadyAttentionUntouched() throws {
        let repository = StageGProfileRepository()
        let store = TabStore(repository: repository)
        let company = try XCTUnwrap(store.createBrowserProfile(name: "Company"))
        let source = try XCTUnwrap(store.add(name: "ChatGPT", homeURL: homeURL))
        XCTAssertTrue(store.updateResourcePolicy(id: source.id, residencyPolicy: .hot))
        repository.events.removeAll()

        let attention = WebAttentionCoordinator()
        let pool = makePool()
        let controller = makePanelController(
            store: store,
            pool: pool,
            attention: attention
        )
        let sourceWebView = try XCTUnwrap(pool.existingWebView(for: source.id))
        let sourceBridge = try XCTUnwrap(pool.attentionBridge(for: source.id))
        attention.apply(.generationStarted, for: source.id)
        attention.apply(.generationFinished(userVisible: false), for: source.id)
        XCTAssertEqual(attention.readySlotIDs, [source.id])

        let duplicate = try XCTUnwrap(
            controller.requestOpenInNewTabWithBrowserProfile(
                sourceSlotID: source.id,
                targetProfileID: company.id
            )
        )

        XCTAssertTrue(pool.existingWebView(for: source.id) === sourceWebView)
        XCTAssertTrue(pool.attentionBridge(for: source.id) === sourceBridge)
        XCTAssertEqual(pool.browserProfileIdentity(for: source.id), .default)
        XCTAssertEqual(attention.readySlotIDs, [source.id])
        XCTAssertTrue(attention.isAttentionProtected(source.id))
        XCTAssertFalse(attention.readySlotIDs.contains(duplicate.id))
        XCTAssertFalse(attention.isAttentionProtected(duplicate.id))
        XCTAssertTrue(pool.residentSlotIDs.contains(source.id))
        XCTAssertTrue(pool.residentSlotIDs.contains(duplicate.id))
    }

    func testProtectedSourceDuplicateDoesNotAskSwitchConfirmation() throws {
        let repository = StageGProfileRepository()
        let store = TabStore(repository: repository)
        let company = try XCTUnwrap(store.createBrowserProfile(name: "Company"))
        let source = try XCTUnwrap(store.add(name: "ChatGPT", homeURL: homeURL))
        let attention = WebAttentionCoordinator()
        attention.apply(.generationStarted, for: source.id)
        var confirmationCalls = 0
        let controller = makePanelController(
            store: store,
            pool: makePool(),
            attention: attention,
            confirmation: { _, _ in
                confirmationCalls += 1
                return false
            }
        )

        XCTAssertNotNil(
            controller.requestOpenInNewTabWithBrowserProfile(
                sourceSlotID: source.id,
                targetProfileID: company.id
            )
        )
        XCTAssertEqual(confirmationCalls, 0)
        XCTAssertTrue(attention.isAttentionProtected(source.id))
    }

    func testDuplicateCopiesHomeProvenanceRenderingAndResourceConfiguration() throws {
        let repository = StageGProfileRepository()
        let store = TabStore(repository: repository)
        let company = try XCTUnwrap(store.createBrowserProfile(name: "Company"))
        let rendering = WebRenderingProfile.canonicalDefault
            .settingWebsiteMode(.mobile)
            .settingBrowserIdentity(.macosChrome)
            .settingSimplePreset(.wide)
            .settingZoom(1.25)
        var source = try XCTUnwrap(
            store.add(
                name: "Configured App",
                homeURL: homeURL,
                homeURLSchemeWasInferred: true,
                renderingProfile: rendering,
                browserProfileID: nil
            )
        )
        XCTAssertTrue(
            store.updateResourcePolicy(
                id: source.id,
                residencyPolicy: .cold,
                backgroundMediaPolicy: .allowBackgroundAudio
            )
        )
        source = try XCTUnwrap(store.profiles.first(where: { $0.id == source.id }))

        let duplicate = try XCTUnwrap(
            store.duplicateSlot(
                sourceID: source.id,
                targetBrowserProfileID: company.id
            )
        )

        XCTAssertEqual(duplicate.homeURL, source.homeURL)
        XCTAssertEqual(duplicate.homeURLSchemeWasInferred, source.homeURLSchemeWasInferred)
        XCTAssertEqual(duplicate.renderingProfile, source.renderingProfile)
        XCTAssertEqual(duplicate.residencyPolicy, source.residencyPolicy)
        XCTAssertEqual(duplicate.backgroundMediaPolicy, source.backgroundMediaPolicy)
        XCTAssertEqual(duplicate.browserProfileID, company.id)
    }

    func testDuplicateGetsIndependentSlotIdentityOrderAndKeyboardIndex() throws {
        let repository = StageGProfileRepository()
        let store = TabStore(repository: repository)
        let source = try XCTUnwrap(store.add(name: "YouTube", homeURL: homeURL))
        let second = try XCTUnwrap(store.add(name: "Gmail", homeURL: homeURL))
        let duplicate = try XCTUnwrap(
            store.duplicateSlot(sourceID: source.id, targetBrowserProfileID: nil)
        )

        XCTAssertNotEqual(duplicate.id, source.id)
        XCTAssertEqual(source.order, 0)
        XCTAssertEqual(second.order, 1)
        XCTAssertEqual(duplicate.order, 2)
        XCTAssertEqual(store.activeTabID, duplicate.id)
        XCTAssertEqual(store.slotByKeyboardIndex(1)?.id, source.id)
        XCTAssertEqual(store.slotByKeyboardIndex(2)?.id, second.id)
        XCTAssertEqual(store.slotByKeyboardIndex(3)?.id, duplicate.id)
        XCTAssertEqual(store.profiles.first(where: { $0.id == source.id })?.name, "YouTube")
    }

    func testSameProfileDuplicateUsesTwoSeparateRuntimesWithOneLogicalIdentity() throws {
        let repository = StageGProfileRepository()
        let store = TabStore(repository: repository)
        let company = try XCTUnwrap(store.createBrowserProfile(name: "Company"))
        let source = try XCTUnwrap(
            store.add(name: "YouTube", homeURL: homeURL, browserProfileID: company.id)
        )
        let pool = makePool()
        let controller = makePanelController(store: store, pool: pool)
        let sourceWebView = try XCTUnwrap(pool.existingWebView(for: source.id))

        let duplicate = try XCTUnwrap(
            controller.requestOpenInNewTabWithBrowserProfile(
                sourceSlotID: source.id,
                targetProfileID: company.id
            )
        )

        let duplicateWebView = try XCTUnwrap(pool.existingWebView(for: duplicate.id))
        XCTAssertTrue(pool.existingWebView(for: source.id) === sourceWebView)
        XCTAssertFalse(sourceWebView === duplicateWebView)
        XCTAssertEqual(pool.browserProfileIdentity(for: source.id), .custom(company.id))
        XCTAssertEqual(pool.browserProfileIdentity(for: duplicate.id), .custom(company.id))
        XCTAssertTrue(pool.residentSlotIDs.contains(source.id))
        XCTAssertTrue(pool.residentSlotIDs.contains(duplicate.id))
    }

    func testDifferentProfilesRemainResidentWithIsolatedRuntimeIdentities() throws {
        let repository = StageGProfileRepository()
        let store = TabStore(repository: repository)
        let accountA = try XCTUnwrap(store.createBrowserProfile(name: "Account A"))
        let accountB = try XCTUnwrap(store.createBrowserProfile(name: "Account B"))
        let source = try XCTUnwrap(
            store.add(name: "YouTube", homeURL: homeURL, browserProfileID: accountA.id)
        )
        let pool = makePool()
        let controller = makePanelController(store: store, pool: pool)
        let sourceWebView = try XCTUnwrap(pool.existingWebView(for: source.id))

        let duplicate = try XCTUnwrap(
            controller.requestOpenInNewTabWithBrowserProfile(
                sourceSlotID: source.id,
                targetProfileID: accountB.id
            )
        )

        XCTAssertTrue(pool.existingWebView(for: source.id) === sourceWebView)
        XCTAssertEqual(pool.browserProfileIdentity(for: source.id), .custom(accountA.id))
        XCTAssertEqual(pool.browserProfileIdentity(for: duplicate.id), .custom(accountB.id))
        XCTAssertEqual(
            pool.residentSlotIDs.intersection([source.id, duplicate.id]),
            [source.id, duplicate.id]
        )
    }

    func testDuplicateCurrentURLBecomesIndependentAfterCreation() throws {
        let repository = StageGProfileRepository()
        let store = TabStore(repository: repository)
        let source = try XCTUnwrap(store.add(name: "YouTube", homeURL: homeURL))
        store.updateCurrentURL(id: source.id, url: sourceURL)

        let duplicate = try XCTUnwrap(
            store.duplicateSlot(sourceID: source.id, targetBrowserProfileID: nil)
        )
        XCTAssertEqual(duplicate.currentURL, sourceURL)

        store.updateCurrentURL(id: duplicate.id, url: duplicateURL)
        XCTAssertEqual(store.profiles.first(where: { $0.id == source.id })?.currentURL, sourceURL)
        XCTAssertEqual(
            store.profiles.first(where: { $0.id == duplicate.id })?.currentURL,
            duplicateURL
        )
    }

    func testPersistenceFailureLeavesSourceAndCreatesNoTargetRuntime() throws {
        let repository = StageGProfileRepository()
        let store = TabStore(repository: repository)
        let company = try XCTUnwrap(store.createBrowserProfile(name: "Company"))
        let source = try XCTUnwrap(store.add(name: "YouTube", homeURL: homeURL))
        let resolverCalls = ResolverCallCounter()
        let pool = makePool(
            customStoreResolver: { id in
                resolverCalls.customIDs.append(id)
                return WKWebsiteDataStore.nonPersistent()
            }
        )
        let controller = makePanelController(store: store, pool: pool)
        let sourceWebView = try XCTUnwrap(pool.existingWebView(for: source.id))
        let sourceBridge = try XCTUnwrap(pool.attentionBridge(for: source.id))
        repository.events.removeAll()
        resolverCalls.customIDs.removeAll()
        repository.failNextSave = true

        XCTAssertNil(
            controller.requestOpenInNewTabWithBrowserProfile(
                sourceSlotID: source.id,
                targetProfileID: company.id
            )
        )
        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.activeTabID, source.id)
        XCTAssertTrue(pool.existingWebView(for: source.id) === sourceWebView)
        XCTAssertTrue(pool.attentionBridge(for: source.id) === sourceBridge)
        XCTAssertTrue(resolverCalls.customIDs.isEmpty)
        XCTAssertTrue(repository.events.isEmpty)
        XCTAssertEqual(pool.residentSlotIDs, [source.id])
    }

    func testMissingTargetFailsClosedWithoutDefaultFallback() throws {
        let repository = StageGProfileRepository()
        let store = TabStore(repository: repository)
        let source = try XCTUnwrap(store.add(name: "YouTube", homeURL: homeURL))
        let defaultResolverCalls = ResolverCallCounter()
        let pool = makePool(
            defaultStoreResolver: {
                defaultResolverCalls.defaultCalls += 1
                return WKWebsiteDataStore.nonPersistent()
            }
        )
        let controller = makePanelController(store: store, pool: pool)
        let sourceWebView = try XCTUnwrap(pool.existingWebView(for: source.id))
        repository.events.removeAll()
        defaultResolverCalls.defaultCalls = 0

        XCTAssertNil(
            controller.requestOpenInNewTabWithBrowserProfile(
                sourceSlotID: source.id,
                targetProfileID: UUID()
            )
        )
        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.activeTabID, source.id)
        XCTAssertTrue(pool.existingWebView(for: source.id) === sourceWebView)
        XCTAssertEqual(defaultResolverCalls.defaultCalls, 0)
        XCTAssertTrue(repository.events.isEmpty)
    }

    private func makePanelController(
        store: TabStore,
        pool: WebViewPool,
        attention: WebAttentionCoordinator = WebAttentionCoordinator(),
        confirmation: @escaping BrowserProfileSwitchConfirmation = { _, _ in true }
    ) -> PanelController {
        PanelController(
            tabStore: store,
            webViewPool: pool,
            attentionCoordinator: attention,
            frameStore: PanelFrameStore(),
            preferencesStore: AppPreferencesStore(),
            confirmBrowserProfileSwitch: confirmation
        )
    }

    private func makePool(
        customProfilesSupported: Bool = true,
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

    private func makeBrowserProfile(name: String) -> BrowserProfile {
        BrowserProfile(
            id: UUID(),
            name: name,
            createdAt: Date(timeIntervalSince1970: 1)
        )
    }

    private func makeWebApp(
        id: UUID = UUID(),
        browserProfileID: UUID? = nil,
        name: String
    ) -> WebAppProfile {
        WebAppProfile(
            id: id,
            browserProfileID: browserProfileID,
            order: 0,
            name: name,
            homeURL: homeURL,
            currentURL: sourceURL
        )
    }

    private func makeMenuEvent() -> NSEvent {
        NSEvent.mouseEvent(
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
    }
}

private enum StageGRepositoryError: Error {
    case saveFailed
}

private final class StageGProfileRepository: ProfileRepositoryProtocol {
    var state: StoredWebAppState
    var events: [String] = []
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
            throw StageGRepositoryError.saveFailed
        }
        self.state = state
        if let lastProfile = state.profiles.last {
            events.append("save-\(lastProfile.id.uuidString)")
        } else {
            events.append("save")
        }
    }
}

@MainActor
private final class ResolverCallCounter {
    var defaultCalls = 0
    var customIDs: [UUID] = []
}
