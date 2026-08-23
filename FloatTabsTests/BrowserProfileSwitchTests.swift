import AppKit
import WebKit
import XCTest
@testable import FloatTabs

@MainActor
final class BrowserProfileSwitchTests: XCTestCase {
    private let homeURL = URL(string: "https://example.com/home")!
    private let currentURL = URL(string: "https://example.com/live")!

    func testProfileSubmenuUsesPersistedOrderAndCurrentIdentity() throws {
        let slotID = UUID()
        let company = makeBrowserProfile(name: "Company")
        let personal = makeBrowserProfile(name: "Personal")
        let tab = ExternalWebAppTabView(slotID: slotID)
        tab.update(
            profile: makeWebApp(
                id: slotID,
                browserProfileID: personal.id,
                name: "Web App"
            ),
            isActive: true,
            isResident: true
        )
        tab.setBrowserProfileMenuSnapshot(
            options: [
                .defaultProfile(),
                BrowserProfileMenuOption(id: company.id, name: company.name, isEnabled: true),
                BrowserProfileMenuOption(id: personal.id, name: personal.name, isEnabled: true),
            ],
            assignmentEnabled: true
        )

        let menu = try XCTUnwrap(tab.menu(for: makeMenuEvent()))
        let profileMenu = try XCTUnwrap(menu.item(withTitle: "Profile")?.submenu)

        XCTAssertEqual(
            profileMenu.items.filter { !$0.isSeparatorItem }.map(\.title),
            ["Default", "Company", "Personal", "Manage Profiles…"]
        )
        XCTAssertTrue(profileMenu.items[2].state == .on)
        XCTAssertTrue(profileMenu.items[4].target === tab)
        XCTAssertEqual(profileMenu.items[4].title, "Manage Profiles…")
    }

    func testRenamedDefaultAppearsDynamicallyInMenusHoverAccessibilityAndTooltip() throws {
        let tab = ExternalWebAppTabView(slotID: UUID())
        tab.update(
            profile: makeWebApp(browserProfileID: nil, name: "YouTube"),
            isActive: true,
            isResident: true
        )
        tab.setBrowserProfileMenuSnapshot(
            options: [
                .defaultProfile(name: "Jack"),
                BrowserProfileMenuOption(id: UUID(), name: "Company", isEnabled: true),
            ],
            assignmentEnabled: true
        )
        tab.setHovered(true)

        let menu = try XCTUnwrap(tab.menu(for: makeMenuEvent()))
        let profileMenu = try XCTUnwrap(menu.item(withTitle: "Profile")?.submenu)
        let duplicateMenu = try XCTUnwrap(
            menu.item(withTitle: "Open in New Tab with Profile")?.submenu
        )

        XCTAssertEqual(profileMenu.items.filter { !$0.isSeparatorItem }.map(\.title), [
            "Jack", "Company", "Manage Profiles…"
        ])
        XCTAssertEqual(duplicateMenu.items.map(\.title), ["Jack", "Company"])
        XCTAssertEqual(profileMenu.items[0].state, .on)
        XCTAssertEqual(tab.displayedLabelText, "YouTube · Jack")
        XCTAssertEqual(tab.accessibilityLabel(), "YouTube · Jack")
        XCTAssertEqual(tab.toolTip, "YouTube · Jack · Open")
    }

    func testDefaultRenamePreservesNilIdentityAndExistingWebView() throws {
        let repository = StageFProfileRepository()
        let store = TabStore(repository: repository)
        let slot = try XCTUnwrap(store.add(name: "Default App", homeURL: homeURL))
        var defaultResolverCalls = 0
        let pool = makePool(defaultStoreResolver: {
            defaultResolverCalls += 1
            return WKWebsiteDataStore.nonPersistent()
        })
        let controller = makePanelController(store: store, pool: pool)
        let oldWebView = try XCTUnwrap(pool.existingWebView(for: slot.id))
        let callsBeforeRename = defaultResolverCalls

        try controller.renameBrowserProfile(id: nil, name: "Jack")

        XCTAssertEqual(store.defaultBrowserProfilePresentation.name, "Jack")
        XCTAssertNil(store.profiles.first?.browserProfileID)
        XCTAssertEqual(pool.browserProfileIdentity(for: slot.id), .default)
        XCTAssertTrue(pool.existingWebView(for: slot.id) === oldWebView)
        XCTAssertEqual(defaultResolverCalls, callsBeforeRename)
    }

    func testActiveTabUsesProfileColorAndSwitchRefreshesWithoutChangingInactiveVisual() throws {
        let defaultColor = BrowserProfileColor(preset: .blue)
        let customColor = BrowserProfileColor(preset: .custom, customSRGBHex: "#3366CC")
        let customID = UUID()
        let tab = ExternalWebAppTabView(slotID: UUID())
        tab.frame = NSRect(x: 0, y: 0, width: 40, height: 32)
        tab.update(
            profile: makeWebApp(browserProfileID: nil, name: "YouTube"),
            isActive: true,
            isResident: true
        )
        tab.setBrowserProfileMenuSnapshot(
            options: [
                .defaultProfile(name: "Jack", color: defaultColor),
                BrowserProfileMenuOption(
                    id: customID,
                    name: "Company",
                    color: customColor,
                    isEnabled: true
                ),
            ],
            assignmentEnabled: true
        )
        tab.layoutSubtreeIfNeeded()
        assertActiveFill(tab, matches: defaultColor)

        let custom = makeWebApp(browserProfileID: customID, name: "YouTube")
        tab.update(profile: custom, isActive: true, isResident: true)
        assertActiveFill(tab, matches: customColor)
        XCTAssertEqual(tab.displayedBrowserProfileColor, customColor)
    }

    func testActiveTabUsesEightyPercentPurpleBlendAndInactiveTabStaysNeutral() throws {
        let purple = BrowserProfileColor(preset: .purple)
        let profileID = UUID()
        let tab = ExternalWebAppTabView(slotID: UUID())
        tab.frame = NSRect(x: 0, y: 0, width: 40, height: 32)
        tab.update(
            profile: makeWebApp(browserProfileID: profileID, name: "Purple"),
            isActive: true,
            isResident: true
        )
        tab.setBrowserProfileMenuSnapshot(
            options: [
                .defaultProfile(),
                BrowserProfileMenuOption(id: profileID, name: "Purple", color: purple, isEnabled: true),
            ],
            assignmentEnabled: true
        )
        tab.layoutSubtreeIfNeeded()
        assertActiveFill(tab, matches: purple)

        tab.update(
            profile: makeWebApp(browserProfileID: profileID, name: "Purple"),
            isActive: false,
            isResident: true
        )
        let actual = try XCTUnwrap(
            tab.displayedTabFillColor?.usingColorSpace(.deviceRGB)
        )
        let expected = try XCTUnwrap(
            NSColor.controlBackgroundColor.withAlphaComponent(0.82).usingColorSpace(.deviceRGB)
        )
        XCTAssertEqual(actual.redComponent, expected.redComponent, accuracy: 0.01)
        XCTAssertEqual(actual.greenComponent, expected.greenComponent, accuracy: 0.01)
        XCTAssertEqual(actual.blueComponent, expected.blueComponent, accuracy: 0.01)
        XCTAssertEqual(actual.alphaComponent, expected.alphaComponent, accuracy: 0.01)
    }

    func testActiveForegroundUsesContrastForBrightAndDarkProfileColors() throws {
        let tab = ExternalWebAppTabView(slotID: UUID())
        tab.frame = NSRect(x: 0, y: 0, width: 40, height: 32)
        let yellowID = UUID()
        tab.update(
            profile: makeWebApp(browserProfileID: yellowID, name: "Yellow"),
            isActive: true,
            isResident: true
        )
        tab.setBrowserProfileMenuSnapshot(
            options: [
                .defaultProfile(),
                BrowserProfileMenuOption(
                    id: yellowID,
                    name: "Yellow",
                    color: BrowserProfileColor(preset: .yellow),
                    isEnabled: true
                ),
            ],
            assignmentEnabled: true
        )
        assertColor(tab.displayedActiveTabForegroundColor, matches: .black)
        assertColor(tab.displayedIconTintColor, matches: .black)

        let graphiteID = UUID()
        tab.update(
            profile: makeWebApp(browserProfileID: graphiteID, name: "Graphite"),
            isActive: true,
            isResident: true
        )
        tab.setBrowserProfileMenuSnapshot(
            options: [
                .defaultProfile(),
                BrowserProfileMenuOption(
                    id: graphiteID,
                    name: "Graphite",
                    color: BrowserProfileColor(preset: .graphite),
                    isEnabled: true
                ),
            ],
            assignmentEnabled: true
        )
        assertColor(tab.displayedActiveTabForegroundColor, matches: .white)
        assertColor(tab.displayedIconTintColor, matches: .white)
    }

    func testReadyDotRemainsSystemRedAndFaviconSourceIsUnchanged() throws {
        let tab = ExternalWebAppTabView(slotID: UUID())
        tab.update(
            profile: makeWebApp(browserProfileID: nil, name: "Default"),
            isActive: true,
            isResident: true
        )
        let sourceIcon = try XCTUnwrap(tab.displayedIcon)
        tab.setReadyAttention(true)
        assertColor(tab.readyAttentionColor, matches: .systemRed)

        tab.setBrowserProfileMenuSnapshot(
            options: [
                .defaultProfile(color: BrowserProfileColor(preset: .yellow)),
            ],
            assignmentEnabled: true
        )

        XCTAssertTrue(tab.displayedIcon === sourceIcon)
        assertColor(tab.readyAttentionColor, matches: .systemRed)
    }

    func testUnsupportedAndFullscreenLockedAssignmentItemsAreDisabledButManageRemainsAvailable() throws {
        let slotID = UUID()
        let company = makeBrowserProfile(name: "Company")
        let tab = ExternalWebAppTabView(slotID: slotID)
        tab.update(
            profile: makeWebApp(id: slotID, browserProfileID: nil, name: "Web App"),
            isActive: true,
            isResident: true
        )
        tab.setBrowserProfileMenuSnapshot(
            options: [
                .defaultProfile(),
                BrowserProfileMenuOption(id: company.id, name: company.name, isEnabled: false),
            ],
            assignmentEnabled: true
        )

        var menu = try XCTUnwrap(tab.menu(for: makeMenuEvent()))
        var profileItems = try XCTUnwrap(menu.item(withTitle: "Profile")?.submenu?.items)
        XCTAssertTrue(profileItems[0].isEnabled)
        XCTAssertFalse(profileItems[1].isEnabled)
        XCTAssertTrue(profileItems.last?.isEnabled == true)

        tab.setBrowserProfileAssignmentEnabled(false)
        menu = try XCTUnwrap(tab.menu(for: makeMenuEvent()))
        profileItems = try XCTUnwrap(menu.item(withTitle: "Profile")?.submenu?.items)
        XCTAssertFalse(profileItems[0].isEnabled)
        XCTAssertFalse(profileItems[1].isEnabled)
        XCTAssertTrue(profileItems.last?.isEnabled == true)
    }

    func testTabStoreSetBrowserProfileCanCommitWithoutOnChangeNotification() throws {
        let repository = StageFProfileRepository()
        let store = TabStore(repository: repository)
        let browserProfile = try XCTUnwrap(store.createBrowserProfile(name: "Company"))
        let slot = try XCTUnwrap(store.add(name: "Web App", homeURL: homeURL))
        repository.events.removeAll()
        var onChangeCalls = 0
        store.onChange = { onChangeCalls += 1 }

        XCTAssertTrue(
            store.setBrowserProfile(
                slotID: slot.id,
                profileID: browserProfile.id,
                notifyOnSuccess: false
            )
        )

        XCTAssertEqual(onChangeCalls, 0)
        XCTAssertEqual(store.profiles.first?.browserProfileID, browserProfile.id)
        XCTAssertEqual(repository.events, ["save-target"])
    }

    func testPersistenceFailureLeavesOldRuntimeAttentionLifecycleAndModelUntouched() throws {
        let repository = StageFProfileRepository()
        let store = TabStore(repository: repository)
        let browserProfile = try XCTUnwrap(store.createBrowserProfile(name: "Company"))
        let slot = try XCTUnwrap(store.add(name: "Web App", homeURL: currentURL))
        repository.events.removeAll()

        var targetResolverCalls = 0
        var loadURLs: [URL] = []
        let pool = makePool(
            customStoreResolver: { _ in
                targetResolverCalls += 1
                return WKWebsiteDataStore.nonPersistent()
            },
            initialLoad: { _, request in loadURLs.append(request.url!) }
        )
        let attention = WebAttentionCoordinator()
        let controller = makePanelController(
            store: store,
            pool: pool,
            attention: attention,
            confirmation: { _, _, _ in true }
        )
        let oldWebView = try XCTUnwrap(pool.existingWebView(for: slot.id))
        let oldBridge = try XCTUnwrap(pool.attentionBridge(for: slot.id))
        attention.apply(.generationStarted, for: slot.id)
        repository.failNextSave = true
        repository.events.removeAll()
        loadURLs.removeAll()

        XCTAssertFalse(
            controller.requestBrowserProfileSwitch(
                slotID: slot.id,
                targetProfileID: browserProfile.id
            )
        )

        XCTAssertNil(store.profiles.first?.browserProfileID)
        XCTAssertTrue(pool.existingWebView(for: slot.id) === oldWebView)
        XCTAssertTrue(pool.attentionBridge(for: slot.id) === oldBridge)
        XCTAssertEqual(pool.browserProfileIdentity(for: slot.id), .default)
        XCTAssertEqual(pool.residentSlotIDs, [slot.id])
        XCTAssertTrue(attention.isAttentionProtected(slot.id))
        XCTAssertFalse(oldBridge.isInvalidated)
        XCTAssertEqual(targetResolverCalls, 0)
        XCTAssertTrue(loadURLs.isEmpty)
        XCTAssertTrue(repository.events.isEmpty)
    }

    func testSuccessfulInactiveSwitchPersistsAndReleasesOldRuntimeWithoutCreatingTarget() throws {
        let repository = StageFProfileRepository()
        let store = TabStore(repository: repository)
        let browserProfile = try XCTUnwrap(store.createBrowserProfile(name: "Company"))
        let inactive = try XCTUnwrap(store.add(name: "Inactive", homeURL: currentURL))
        let active = try XCTUnwrap(store.add(name: "Active", homeURL: homeURL))
        repository.events.removeAll()

        var targetResolverCalls = 0
        let pool = makePool(
            customStoreResolver: { _ in
                targetResolverCalls += 1
                return WKWebsiteDataStore.nonPersistent()
            }
        )
        let oldInactiveWebView = try pool.webView(for: inactive)
        let attention = WebAttentionCoordinator()
        let controller = makePanelController(store: store, pool: pool, attention: attention)
        XCTAssertTrue(pool.existingWebView(for: active.id) != nil)
        attention.apply(.generationStarted, for: inactive.id)
        repository.events.removeAll()

        XCTAssertTrue(
            controller.requestBrowserProfileSwitch(
                slotID: inactive.id,
                targetProfileID: browserProfile.id
            )
        )

        XCTAssertEqual(store.profiles.first(where: { $0.id == inactive.id })?.browserProfileID, browserProfile.id)
        XCTAssertNil(pool.existingWebView(for: inactive.id))
        XCTAssertTrue(oldInactiveWebView.superview == nil)
        XCTAssertEqual(pool.browserProfileIdentity(for: active.id), .default)
        XCTAssertEqual(targetResolverCalls, 0)
        XCTAssertFalse(attention.isAttentionProtected(inactive.id))
        XCTAssertEqual(repository.events, ["save-target"])
    }

    func testSuccessfulActiveSwitchUsesCurrentURLAndCreatesExactlyOneTargetRuntime() throws {
        let repository = StageFProfileRepository()
        let store = TabStore(repository: repository)
        let browserProfile = try XCTUnwrap(store.createBrowserProfile(name: "Company"))
        let slot = try XCTUnwrap(store.add(name: "Web App", homeURL: homeURL))
        store.updateCurrentURL(id: slot.id, url: currentURL)
        repository.events.removeAll()

        var events: [String] = []
        var targetResolverCalls = 0
        var targetLoadURLs: [URL] = []
        let pool = makePool(
            customStoreResolver: { id in
                targetResolverCalls += 1
                events.append("resolve-custom-\(id.uuidString)")
                return WKWebsiteDataStore.nonPersistent()
            },
            initialLoad: { _, request in
                targetLoadURLs.append(request.url!)
                events.append("target-load")
            }
        )
        let attention = WebAttentionCoordinator()
        let controller = makePanelController(store: store, pool: pool, attention: attention)
        let oldWebView = try XCTUnwrap(pool.existingWebView(for: slot.id))
        let oldBridge = try XCTUnwrap(pool.attentionBridge(for: slot.id))
        targetLoadURLs.removeAll()
        repository.events.removeAll()
        events.removeAll()
        pool.onResidentSetChange = { events.append("runtime-change") }

        XCTAssertTrue(
            controller.requestBrowserProfileSwitch(
                slotID: slot.id,
                targetProfileID: browserProfile.id
            )
        )

        let expectedEvents = [
            "save-target",
            "runtime-change",
            "resolve-custom-\(browserProfile.id.uuidString)",
            "runtime-change",
            "target-load",
        ]
        XCTAssertEqual(repository.events + events, expectedEvents)
        XCTAssertEqual(targetResolverCalls, 1)
        XCTAssertEqual(targetLoadURLs, [currentURL])
        XCTAssertFalse(pool.existingWebView(for: slot.id) === oldWebView)
        XCTAssertTrue(oldBridge.isInvalidated)
        XCTAssertEqual(pool.browserProfileIdentity(for: slot.id), .custom(browserProfile.id))
        XCTAssertFalse(attention.isAttentionProtected(slot.id))
        XCTAssertEqual(store.profiles.first(where: { $0.id == slot.id })?.currentURL, currentURL)
    }

    func testAttentionProtectedSwitchRequiresConfirmationAndCancelIsMutationFree() throws {
        let repository = StageFProfileRepository()
        let store = TabStore(repository: repository)
        let browserProfile = try XCTUnwrap(store.createBrowserProfile(name: "Company"))
        let slot = try XCTUnwrap(store.add(name: "Web App", homeURL: homeURL))
        repository.events.removeAll()

        var confirmationCalls = 0
        var confirmationResult = false
        var targetResolverCalls = 0
        let pool = makePool(
            customStoreResolver: { _ in
                targetResolverCalls += 1
                return WKWebsiteDataStore.nonPersistent()
            }
        )
        let attention = WebAttentionCoordinator()
        let controller = makePanelController(
            store: store,
            pool: pool,
            attention: attention,
            confirmation: { _, _, _ in
                confirmationCalls += 1
                return confirmationResult
            }
        )
        let oldWebView = try XCTUnwrap(pool.existingWebView(for: slot.id))
        attention.apply(.generationStarted, for: slot.id)

        XCTAssertFalse(
            controller.requestBrowserProfileSwitch(
                slotID: slot.id,
                targetProfileID: browserProfile.id
            )
        )
        XCTAssertEqual(confirmationCalls, 1)
        XCTAssertTrue(pool.existingWebView(for: slot.id) === oldWebView)
        XCTAssertNil(store.profiles.first?.browserProfileID)
        XCTAssertTrue(attention.isAttentionProtected(slot.id))
        XCTAssertEqual(targetResolverCalls, 0)
        XCTAssertTrue(repository.events.isEmpty)

        confirmationResult = true
        XCTAssertTrue(
            controller.requestBrowserProfileSwitch(
                slotID: slot.id,
                targetProfileID: browserProfile.id
            )
        )
        XCTAssertEqual(confirmationCalls, 2)
        XCTAssertEqual(pool.browserProfileIdentity(for: slot.id), .custom(browserProfile.id))
    }

    func testSameProfileSwitchIsNoOpWithoutConfirmationOrRuntimeMutation() throws {
        let repository = StageFProfileRepository()
        let store = TabStore(repository: repository)
        let browserProfile = try XCTUnwrap(store.createBrowserProfile(name: "Company"))
        let slot = try XCTUnwrap(
            store.add(
                name: "Web App",
                homeURL: homeURL,
                browserProfileID: browserProfile.id
            )
        )
        repository.events.removeAll()
        var confirmationCalls = 0
        let pool = makePool()
        let attention = WebAttentionCoordinator()
        let controller = makePanelController(
            store: store,
            pool: pool,
            attention: attention,
            confirmation: { _, _, _ in
                confirmationCalls += 1
                return false
            }
        )
        let webView = try XCTUnwrap(pool.existingWebView(for: slot.id))
        attention.apply(.generationStarted, for: slot.id)
        repository.events.removeAll()

        XCTAssertTrue(
            controller.requestBrowserProfileSwitch(
                slotID: slot.id,
                targetProfileID: browserProfile.id
            )
        )

        XCTAssertEqual(confirmationCalls, 0)
        XCTAssertTrue(pool.existingWebView(for: slot.id) === webView)
        XCTAssertTrue(attention.isAttentionProtected(slot.id))
        XCTAssertTrue(repository.events.isEmpty)
    }

    func testMissingOrUnsupportedProfileFailsClosedWithoutDefaultFallback() throws {
        let repository = StageFProfileRepository()
        let store = TabStore(repository: repository)
        let unsupportedProfile = try XCTUnwrap(store.createBrowserProfile(name: "Company"))
        let slot = try XCTUnwrap(store.add(name: "Web App", homeURL: homeURL))
        repository.events.removeAll()
        var defaultResolverCalls = 0
        var customResolverCalls = 0
        let pool = makePool(
            customProfilesSupported: false,
            defaultStoreResolver: {
                defaultResolverCalls += 1
                return WKWebsiteDataStore.nonPersistent()
            },
            customStoreResolver: { _ in
                customResolverCalls += 1
                return WKWebsiteDataStore.nonPersistent()
            }
        )
        let controller = makePanelController(store: store, pool: pool)
        let oldWebView = try XCTUnwrap(pool.existingWebView(for: slot.id))
        let missingID = UUID()
        defaultResolverCalls = 0
        customResolverCalls = 0
        repository.events.removeAll()

        XCTAssertFalse(
            controller.requestBrowserProfileSwitch(
                slotID: slot.id,
                targetProfileID: missingID
            )
        )
        XCTAssertFalse(
            controller.requestBrowserProfileSwitch(
                slotID: slot.id,
                targetProfileID: unsupportedProfile.id
            )
        )
        XCTAssertNil(store.profiles.first?.browserProfileID)
        XCTAssertTrue(pool.existingWebView(for: slot.id) === oldWebView)
        XCTAssertEqual(defaultResolverCalls, 0)
        XCTAssertEqual(customResolverCalls, 0)
        XCTAssertTrue(repository.events.isEmpty)
    }

    func testFullscreenLockRejectsSwitchAndRailAssignmentItemsAreDisabled() throws {
        let currentID = UUID()
        let targetID = UUID()
        XCTAssertFalse(
            PanelController.canRequestBrowserProfileSwitch(
                currentProfileID: nil,
                targetProfileID: targetID,
                targetExists: true,
                customProfilesSupported: true,
                sessionIsLocked: true
            )
        )
        XCTAssertTrue(
            PanelController.canRequestBrowserProfileSwitch(
                currentProfileID: currentID,
                targetProfileID: currentID,
                targetExists: true,
                customProfilesSupported: false,
                sessionIsLocked: true
            )
        )

        let tab = ExternalWebAppTabView(slotID: UUID())
        tab.update(
            profile: makeWebApp(id: UUID(), browserProfileID: nil, name: "Web App"),
            isActive: true,
            isResident: true
        )
        tab.setBrowserProfileMenuSnapshot(
            options: [
                .defaultProfile(),
                BrowserProfileMenuOption(id: targetID, name: "Company", isEnabled: true),
            ],
            assignmentEnabled: false
        )
        let menu = try XCTUnwrap(tab.menu(for: makeMenuEvent()))
        let items = try XCTUnwrap(menu.item(withTitle: "Profile")?.submenu?.items)
        XCTAssertFalse(items[0].isEnabled)
        XCTAssertFalse(items[1].isEnabled)
        XCTAssertTrue(items.last?.isEnabled == true)
    }

    private func makePanelController(
        store: TabStore,
        pool: WebViewPool,
        attention: WebAttentionCoordinator = WebAttentionCoordinator(),
        confirmation: @escaping BrowserProfileSwitchConfirmation = { _, _, _ in true }
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
            currentURL: currentURL
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

    private func assertActiveFill(
        _ tab: ExternalWebAppTabView,
        matches profileColor: BrowserProfileColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actual = try! XCTUnwrap(
            tab.displayedActiveTabFillColor?.usingColorSpace(.deviceRGB),
            file: file,
            line: line
        )
        var expected: NSColor?
        tab.effectiveAppearance.performAsCurrentDrawingAppearance {
            expected = ExternalWebAppTabView.activeBackgroundColor(
                profileColor: profileColor.appKitColor
            )
                .usingColorSpace(.deviceRGB)
        }
        let resolvedExpected = try! XCTUnwrap(expected, file: file, line: line)
        XCTAssertEqual(actual.redComponent, resolvedExpected.redComponent, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(actual.greenComponent, resolvedExpected.greenComponent, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(actual.blueComponent, resolvedExpected.blueComponent, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(actual.alphaComponent, resolvedExpected.alphaComponent, accuracy: 0.01, file: file, line: line)
    }

    private func assertColor(
        _ actual: NSColor?,
        matches expected: NSColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actual = try! XCTUnwrap(
            try! XCTUnwrap(actual, file: file, line: line).usingColorSpace(.deviceRGB),
            file: file,
            line: line
        )
        let expected = try! XCTUnwrap(expected.usingColorSpace(.deviceRGB), file: file, line: line)
        XCTAssertEqual(actual.redComponent, expected.redComponent, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(actual.greenComponent, expected.greenComponent, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(actual.blueComponent, expected.blueComponent, accuracy: 0.01, file: file, line: line)
    }
}

private enum StageFRepositoryError: Error {
    case saveFailed
}

private final class StageFProfileRepository: ProfileRepositoryProtocol {
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
            throw StageFRepositoryError.saveFailed
        }
        self.state = state
        events.append("save-target")
    }
}
