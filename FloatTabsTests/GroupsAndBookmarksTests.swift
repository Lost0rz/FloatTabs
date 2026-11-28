import AppKit
import XCTest
@testable import FloatTabs

@MainActor
final class GroupsAndBookmarksTests: XCTestCase {
    private final class MemoryProfileRepository: ProfileRepositoryProtocol {
        var state: StoredWebAppState

        init(state: StoredWebAppState = .empty) {
            self.state = state
        }

        func load() throws -> StoredWebAppState {
            state
        }

        func save(_ state: StoredWebAppState) throws {
            self.state = state
        }
    }

    func testDesktopToMobileAndBackRestoresDesktopURLWithoutStaleMobileRedirect() throws {
        var loadedRequests: [URLRequest] = []
        var updatedURLs: [(UUID, URL)] = []
        let pool = WebViewPool(
            onURLChange: { id, url in updatedURLs.append((id, url)) },
            initialLoad: { _, request in loadedRequests.append(request) }
        )

        let desktopHome = URL(string: "https://v.qq.com/")!
        let mobileRedirected = URL(string: "https://m.v.qq.com/x/cover/abc.html")!
        var profile = WebAppProfile(
            order: 0,
            name: "Tencent Video",
            homeURL: desktopHome,
            currentURL: desktopHome
        )

        let initialWebView = try pool.webView(for: profile)
        XCTAssertEqual(loadedRequests.last?.url, desktopHome)
        XCTAssertTrue(initialWebView.customUserAgent?.isEmpty ?? true)

        profile.renderingProfile = profile.renderingProfile.settingWebsiteMode(.mobile)
        let mobileWebView = try pool.webView(for: profile)
        XCTAssertFalse(initialWebView === mobileWebView)
        XCTAssertTrue(mobileWebView.customUserAgent?.contains("iPhone") == true)

        // Simulate mobile site redirecting and persisting `currentURL = https://m.v.qq.com/...`.
        profile.currentURL = mobileRedirected
        profile.renderingProfile = profile.renderingProfile.settingWebsiteMode(.desktop)
        let restoredDesktop = try pool.webView(for: profile)
        XCTAssertFalse(mobileWebView === restoredDesktop)
        XCTAssertTrue(restoredDesktop.customUserAgent?.isEmpty ?? true)
        XCTAssertEqual(loadedRequests.last?.url?.host, "v.qq.com")
        XCTAssertEqual(loadedRequests.last?.url?.path, "/x/cover/abc.html")
        XCTAssertEqual(loadedRequests.last?.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(updatedURLs.last?.0, profile.id)
        XCTAssertEqual(updatedURLs.last?.1.host, "v.qq.com")
    }

    func testColdLaunchInDesktopModeRepairsPersistedMobileURL() throws {
        var loadedRequests: [URLRequest] = []
        var updatedURLs: [URL] = []
        let pool = WebViewPool(
            onURLChange: { _, url in updatedURLs.append(url) },
            initialLoad: { _, request in loadedRequests.append(request) }
        )
        let profile = WebAppProfile(
            order: 0,
            name: "QQ",
            homeURL: URL(string: "https://v.qq.com/")!,
            currentURL: URL(string: "https://m.v.qq.com/")!,
            renderingProfile: WebRenderingProfile.canonicalDefault.settingWebsiteMode(.desktop)
        )

        let webView = try pool.webView(for: profile)
        XCTAssertTrue(webView.customUserAgent?.isEmpty ?? true)
        XCTAssertEqual(loadedRequests.last?.url, URL(string: "https://v.qq.com/")!)
        XCTAssertEqual(loadedRequests.last?.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(updatedURLs.last, URL(string: "https://v.qq.com/")!)
    }

    func testSameSiteFamilyMatchesSubdomainsAndMultiLabelSuffixes() {
        XCTAssertTrue(
            WebsiteFaviconProvider.belongsToSameSiteFamily(
                URL(string: "https://v.qq.com/")!,
                URL(string: "https://m.v.qq.com/")!
            )
        )
        XCTAssertTrue(
            WebsiteFaviconProvider.belongsToSameSiteFamily(
                URL(string: "https://app.notion.so/workspace")!,
                URL(string: "https://www.notion.so/")!
            )
        )
        XCTAssertTrue(
            WebsiteFaviconProvider.belongsToSameSiteFamily(
                URL(string: "https://m.news.bbc.co.uk/")!,
                URL(string: "https://www.bbc.co.uk/")!
            )
        )
        XCTAssertFalse(
            WebsiteFaviconProvider.belongsToSameSiteFamily(
                URL(string: "https://v.qq.com/")!,
                URL(string: "https://www.bilibili.com/")!
            )
        )
        XCTAssertFalse(
            WebsiteFaviconProvider.belongsToSameSiteFamily(
                URL(string: "https://evil.co.uk/")!,
                URL(string: "https://bbc.co.uk/")!
            )
        )
    }

    func testSessionFaviconExtractionAcceptsDataURIPayload() throws {
        let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        let payload: [String: Any] = [
            "candidates": [],
            "renderedDataURL": "data:image/png;base64,\(pngBase64)",
            "renderedKind": "icon",
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let parsed = WebsiteFaviconProvider.parseSessionFaviconExtractionResult(.success(json))
        XCTAssertTrue(parsed.readSucceeded)
        XCTAssertEqual(parsed.renderedKind, .icon)
        XCTAssertNotNil(parsed.renderedPNGData)
        XCTAssertNil(parsed.renderedResourceURL)
    }

    func testPruneSlotIconsRemovesOrphansAndPreservesActiveAndOriginRecords() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabs-PruneSlotTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = WebsiteFaviconAssetStore(directoryURL: dir)
        let activeSlot = UUID()
        let orphanSlot = UUID()
        let pngData = Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        )!
        let sha = String(repeating: "a", count: 64)

        XCTAssertEqual(
            store.saveSlotIcon(
                WebsiteFaviconAssetStore.SlotRecord(
                    slotID: activeSlot,
                    scopeKey: "https://example.com",
                    imageData: pngData,
                    pixelSHA256: sha,
                    kind: "icon"
                )
            ),
            .saved
        )
        XCTAssertEqual(
            store.saveSlotIcon(
                WebsiteFaviconAssetStore.SlotRecord(
                    slotID: orphanSlot,
                    scopeKey: "https://orphan.com",
                    imageData: pngData,
                    pixelSHA256: sha,
                    kind: "icon"
                )
            ),
            .saved
        )
        XCTAssertEqual(
            store.save(
                WebsiteFaviconAssetStore.Record(
                    originKey: "https://example.com",
                    imageData: pngData,
                    pixelSHA256: sha,
                    priority: 0,
                    kind: "icon",
                    isLocked: false
                )
            ),
            .saved
        )

        store.pruneSlotIcons(keeping: [activeSlot])

        XCTAssertNil(store.loadSlotIcon(slotID: orphanSlot, scopeKey: "https://orphan.com"))
        XCTAssertNotNil(store.loadSlotIcon(slotID: activeSlot, scopeKey: "https://example.com"))
        if case .record = store.load(originKey: "https://example.com") {
            // Expected.
        } else {
            XCTFail("Origin cache record should remain.")
        }
    }

    func testTabGroupsScopeTabsSwitchPerGroupAccentAndPreserveTabsOnDelete() throws {
        let repo = MemoryProfileRepository()
        let store = TabStore(repository: repo)

        let tabA1 = try XCTUnwrap(store.add(name: "A1", homeURL: URL(string: "https://a1.example.com")!))
        let tabA2 = try XCTUnwrap(store.add(name: "A2", homeURL: URL(string: "https://a2.example.com")!))
        XCTAssertTrue(
            store.updateGroup(
                id: nil,
                name: "Work",
                borderTheme: .rainbow,
                customBorderColorHex: nil
            )
        )

        let groupB = try XCTUnwrap(
            store.createGroup(
                name: "Media",
                borderTheme: .green,
                customBorderColorHex: nil,
                selectImmediately: true
            )
        )
        XCTAssertEqual(store.activeGroupID, groupB.id)
        XCTAssertTrue(store.activeGroupProfiles.isEmpty)

        let tabB1 = try XCTUnwrap(store.add(name: "B1", homeURL: URL(string: "https://b1.example.com")!))
        XCTAssertEqual(store.activeGroupProfiles.map(\.id), [tabB1.id])
        XCTAssertEqual(store.slotByKeyboardIndex(1)?.id, tabB1.id)
        XCTAssertNil(store.slotByKeyboardIndex(2))

        // Per-group accent remains stored independently of the global frame.
        XCTAssertEqual(store.activeGroupOption.borderTheme, .green)

        XCTAssertTrue(store.selectGroup(id: nil))
        XCTAssertEqual(store.activeGroupOption.borderTheme, .rainbow)
        XCTAssertEqual(store.activeTabID, tabA2.id)
        XCTAssertEqual(store.activeGroupProfiles.map(\.id), [tabA1.id, tabA2.id])
        XCTAssertEqual(store.slotByKeyboardIndex(1)?.id, tabA1.id)
        XCTAssertEqual(store.slotByKeyboardIndex(2)?.id, tabA2.id)

        // Moving a slot into Group B hides it from Default and shows it in Group B.
        XCTAssertTrue(store.moveSlotToGroup(slotID: tabA1.id, groupID: groupB.id))
        XCTAssertEqual(store.activeGroupProfiles.map(\.id), [tabA2.id])

        // Deleting Group B preserves its tabs back in Default Group.
        XCTAssertTrue(store.deleteGroup(id: groupB.id))
        XCTAssertNil(store.activeGroupID)
        XCTAssertEqual(Set(store.activeGroupProfiles.map(\.id)), Set([tabA1.id, tabA2.id, tabB1.id]))
    }

    func testBookmarkFoldersAndItemsPersistAcrossReloadAndSanitizeOnFolderDelete() throws {
        let repo = MemoryProfileRepository()
        let store = TabStore(repository: repo)

        let folder = try XCTUnwrap(store.createBookmarkFolder(name: "Reading"))
        XCTAssertTrue(store.renameBookmarkFolder(id: folder.id, name: "Docs & Specs"))

        let url = URL(string: "https://developer.apple.com/documentation")!
        let item = try XCTUnwrap(
            store.addBookmark(
                title: "Apple Docs",
                url: url,
                folderID: folder.id,
                notes: "API Reference",
                preferredWebsiteMode: .desktop
            )
        )
        XCTAssertEqual(store.bookmarks(in: folder.id).map(\.id), [item.id])

        let reloaded = TabStore(repository: repo)
        XCTAssertEqual(reloaded.orderedBookmarkFolders.first?.name, "Docs & Specs")
        XCTAssertEqual(reloaded.orderedBookmarks.first?.title, "Apple Docs")
        XCTAssertEqual(reloaded.orderedBookmarks.first?.preferredWebsiteMode, .desktop)

        XCTAssertTrue(reloaded.deleteBookmarkFolder(id: folder.id))
        XCTAssertEqual(reloaded.orderedBookmarks.count, 1)
        XCTAssertNil(reloaded.orderedBookmarks.first?.folderID)
        XCTAssertTrue(reloaded.deleteBookmark(id: item.id))
        XCTAssertTrue(reloaded.orderedBookmarks.isEmpty)
    }

    func testBookmarksSettingsControllerUsesOuterScrollViewOnly() throws {
        let bookmarksVC = BookmarksSettingsViewController(
            client: .unavailable,
            embedsInSettingsPage: true
        )
        bookmarksVC.loadView()
        XCTAssertFalse(bookmarksVC.view.subviews.contains(where: { $0 is NSScrollView }))

        let settings = GlobalSettingsController(preferencesStore: AppPreferencesStore())
        let page = try XCTUnwrap(
            settings.makeSettingsPage(for: .bookmarks) as? SettingsPageViewController
        )
        XCTAssertTrue(page.embeddedControllers.first is BookmarksSettingsViewController)
    }

    func testTabContextMenuIncludesMoveToGroupSubmenuWhenMultipleGroupsExist() throws {
        let groupB = UUID()
        let tab = ExternalWebAppTabView(slotID: UUID())
        tab.update(
            profile: WebAppProfile(
                groupID: nil,
                order: 0,
                name: "Docs",
                homeURL: URL(string: "https://example.com")!
            ),
            isActive: true,
            isResident: true
        )
        tab.setGroupMenuSnapshot(options: [
            WebAppGroupMenuOption(
                id: nil,
                name: "Default",
                borderTheme: .rainbow,
                customBorderColorHex: nil,
                isDefault: true,
                isActive: true,
                slotCount: 1
            ),
            WebAppGroupMenuOption(
                id: groupB,
                name: "Media",
                borderTheme: .green,
                customBorderColorHex: nil,
                isDefault: false,
                isActive: false,
                slotCount: 0
            ),
        ])

        let menu = tab.makeContextMenu()
        let moveItem = try XCTUnwrap(menu.item(withTitle: "Move to Group"))
        let submenu = try XCTUnwrap(moveItem.submenu)
        XCTAssertEqual(submenu.items.map(\.title), ["Default", "Media"])
        XCTAssertEqual(submenu.item(withTitle: "Default")?.state, .on)
        XCTAssertEqual(submenu.item(withTitle: "Media")?.state, .off)
        XCTAssertNotNil(menu.item(withTitle: "Save to Bookmarks…"))
    }

    func testNestedBookmarkFoldersCyclePreventionAndPromotionOnDelete() throws {
        let repo = MemoryProfileRepository()
        let store = TabStore(repository: repo)

        let root = try XCTUnwrap(store.createBookmarkFolder(name: "Engineering"))
        let child = try XCTUnwrap(store.createBookmarkFolder(name: "AI", parentFolderID: root.id))
        let leaf = try XCTUnwrap(store.createBookmarkFolder(name: "Agents", parentFolderID: child.id))

        XCTAssertEqual(store.bookmarkFolderDisplayPath(id: leaf.id), "Engineering / AI / Agents")
        XCTAssertTrue(store.isBookmarkFolder(leaf.id, descendantOf: root.id))
        XCTAssertFalse(store.isBookmarkFolder(root.id, descendantOf: leaf.id))
        // Duplicate sibling name blocked under same parent, allowed under a different parent.
        XCTAssertNil(store.createBookmarkFolder(name: "ai", parentFolderID: root.id))
        XCTAssertNotNil(store.createBookmarkFolder(name: "AI", parentFolderID: nil))

        let saved = try XCTUnwrap(
            store.addBookmark(
                title: "Spec",
                url: URL(string: "https://example.com/spec")!,
                folderID: child.id
            )
        )

        // Deleting intermediate folder promotes child folder & direct bookmarks to its parent.
        XCTAssertTrue(store.deleteBookmarkFolder(id: child.id))
        let reloadedLeaf = try XCTUnwrap(store.orderedBookmarkFolders.first(where: { $0.id == leaf.id }))
        let reloadedSaved = try XCTUnwrap(store.orderedBookmarks.first(where: { $0.id == saved.id }))
        XCTAssertEqual(reloadedLeaf.parentFolderID, root.id)
        XCTAssertEqual(reloadedSaved.folderID, root.id)
        XCTAssertEqual(store.bookmarkFolderDisplayPath(id: leaf.id), "Engineering / Agents")
    }

    func testBookmarkHTMLImportAndExportRoundTripsNestedFoldersForChromeAndSafari() throws {
        let chromeSafariHTML = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
            <DT><H3 FOLDED>Work &amp; Research</H3>
            <DL><p>
                <DT><H3>LLM Tools</H3>
                <DL><p>
                    <DT><A HREF="https://chatgpt.com/" ADD_DATE="1700000000">ChatGPT</A>
                    <DD>Primary assistant
                    <DT><A HREF="javascript:alert(1)">Unsafe Script</A>
                </DL><p>
                <DT><A HREF="https://developer.apple.com/">Apple Developer</A>
            </DL><p>
            <DT><A HREF="https://news.ycombinator.com/">Hacker News</A>
        </DL><p>
        """

        let parsed = BookmarkHTMLCodec.parseHTML(chromeSafariHTML)
        XCTAssertEqual(parsed.folders.map(\.name), ["Work & Research"])
        XCTAssertEqual(parsed.folders.first?.folders.map(\.name), ["LLM Tools"])
        XCTAssertEqual(parsed.folders.first?.folders.first?.bookmarks.map(\.title), ["ChatGPT"])
        XCTAssertEqual(parsed.folders.first?.folders.first?.bookmarks.first?.notes, "Primary assistant")
        XCTAssertEqual(parsed.folders.first?.bookmarks.map(\.title), ["Apple Developer"])
        XCTAssertEqual(parsed.rootBookmarks.map(\.title), ["Hacker News"])

        let repo = MemoryProfileRepository()
        let store = TabStore(repository: repo)
        let firstImport = store.importBookmarksHTML(chromeSafariHTML)
        XCTAssertEqual(firstImport.foldersAdded, 2)
        XCTAssertEqual(firstImport.bookmarksAdded, 3)

        // Importing the same file again merges without duplicating URLs in the same folder.
        let repeatImport = store.importBookmarksHTML(chromeSafariHTML)
        XCTAssertEqual(repeatImport.foldersAdded, 0)
        XCTAssertEqual(repeatImport.bookmarksAdded, 0)

        let exportedHTML = store.exportBookmarksHTML()
        XCTAssertTrue(exportedHTML.contains("<!DOCTYPE NETSCAPE-Bookmark-file-1>"))
        XCTAssertTrue(exportedHTML.contains("Work &amp; Research"))
        XCTAssertTrue(exportedHTML.contains("LLM Tools"))
        XCTAssertTrue(exportedHTML.contains("https://chatgpt.com/"))

        let secondRepo = MemoryProfileRepository()
        let roundTripStore = TabStore(repository: secondRepo)
        let roundTripResult = roundTripStore.importBookmarksHTML(exportedHTML)
        XCTAssertEqual(roundTripResult.foldersAdded, 2)
        XCTAssertEqual(roundTripResult.bookmarksAdded, 3)
        let llmFolder = try XCTUnwrap(roundTripStore.orderedBookmarkFolders.first(where: { $0.name == "LLM Tools" }))
        XCTAssertEqual(roundTripStore.bookmarkFolderDisplayPath(id: llmFolder.id), "Work & Research / LLM Tools")
    }

    func testCascadingBookmarkMenuBuilderPopulatesNestedSubmenusAndInvokesSelection() throws {
        let rootID = UUID()
        let childID = UUID()
        let folders = [
            BookmarkFolder(id: rootID, parentFolderID: nil, name: "Work", order: 0),
            BookmarkFolder(id: childID, parentFolderID: rootID, name: "Docs", order: 1),
        ]
        let bookmark = BookmarkItem(
            folderID: childID,
            order: 0,
            title: "Swift Docs",
            url: URL(string: "https://swift.org/documentation/")!
        )

        var selected: BookmarkItem?
        let sections = WebAppEditorBookmarkMenuBuilder.rootSections(
            folders: folders,
            bookmarks: [bookmark]
        )
        XCTAssertEqual(sections.map(\.title), ["Work"])

        let rootMenu = WebAppEditorBookmarkMenuBuilder.makeCascadingMenu(
            for: rootID,
            title: "Work",
            folders: folders,
            bookmarks: [bookmark],
            onSelectBookmark: { item in
                selected = item
            }
        )
        let docsItem = try XCTUnwrap(rootMenu.item(withTitle: "Docs"))
        let docsSubmenu = try XCTUnwrap(docsItem.submenu)
        let swiftItem = try XCTUnwrap(docsSubmenu.items.first)
        XCTAssertTrue(swiftItem.title.contains("Swift Docs"))

        _ = swiftItem.target?.perform(swiftItem.action, with: swiftItem)
        XCTAssertEqual(selected?.id, bookmark.id)
    }

    func testGroupControlDisplaysIndependentColorStripeAndUnreadBadge() {
        let groupBID = UUID()
        let defaultOption = WebAppGroupMenuOption(
            id: nil,
            name: "Default",
            borderTheme: nil,
            customBorderColorHex: nil,
            isDefault: true,
            isActive: false,
            slotCount: 1,
            unreadCount: 2
        )
        let activeOption = WebAppGroupMenuOption(
            id: groupBID,
            name: "Work",
            borderTheme: .green,
            customBorderColorHex: nil,
            isDefault: false,
            isActive: true,
            slotCount: 1,
            unreadCount: 1
        )
        let defaultControl = WebAppGroupControl(
            option: defaultOption,
            allOptions: [defaultOption, activeOption],
            globalBorderTheme: .orange,
            globalCustomBorderColor: .systemOrange
        )
        let activeControl = WebAppGroupControl(
            option: activeOption,
            allOptions: [defaultOption, activeOption],
            globalBorderTheme: .orange,
            globalCustomBorderColor: .systemOrange
        )

        XCTAssertEqual(defaultControl.effectiveAccentThemeForTesting, .rainbow)
        XCTAssertEqual(activeControl.effectiveAccentThemeForTesting, .green)
        XCTAssertTrue(defaultControl.hasVisibleUnreadIndicator)
        XCTAssertFalse(activeControl.hasVisibleUnreadIndicator)
        XCTAssertGreaterThan(activeControl.preferredWidth, defaultControl.preferredWidth)
        XCTAssertGreaterThan(defaultControl.preferredWidth, ExternalTabMetrics.systemControlNormalWidth)
    }

    func testCrossGroupUnreadNotificationRoutingAndStatusMenuTitle() throws {
        let repo = MemoryProfileRepository()
        let store = TabStore(repository: repo)
        let workTab = try XCTUnwrap(
            store.add(name: "ChatGPT", homeURL: URL(string: "https://chatgpt.com/")!)
        )
        let mediaGroup = try XCTUnwrap(
            store.createGroup(name: "Media", borderTheme: .purple, selectImmediately: true)
        )
        let mediaTab = try XCTUnwrap(
            store.add(name: "YouTube", homeURL: URL(string: "https://www.youtube.com/")!)
        )
        XCTAssertEqual(store.activeGroupID, mediaGroup.id)
        XCTAssertEqual(store.activeTabID, mediaTab.id)

        let pool = WebViewPool(onURLChange: { _, _ in }, initialLoad: { _, _ in })
        let controller = PanelController(
            tabStore: store,
            webViewPool: pool,
            frameStore: PanelFrameStore(),
            preferencesStore: AppPreferencesStore()
        )
        let titles = controller.statusItemMenuSnapshot.slots.map(\.title)
        XCTAssertEqual(titles, ["Default · ChatGPT", "Media · YouTube"])

        XCTAssertTrue(controller.presentSlotFromCompletionNotification(workTab.id))
        XCTAssertNil(store.activeGroupID)
        XCTAssertEqual(store.activeTabID, workTab.id)
    }

    func testEmptyWebAppViewClickInvokesAddWebAppAndPanelControllerHooksBothContainers() {
        let emptyView = EmptyWebAppView()
        XCTAssertTrue(emptyView.acceptsFirstMouse(for: nil))
        XCTAssertFalse(emptyView.mouseDownCanMoveWindow)
        XCTAssertEqual(emptyView.accessibilityRole(), .button)
        XCTAssertEqual(emptyView.accessibilityIdentifier(), "floatTabs.emptyState.addWebApp")

        var directClicks = 0
        emptyView.onAddWebApp = { directClicks += 1 }
        emptyView.performAddWebApp()
        XCTAssertTrue(emptyView.accessibilityPerformPress())
        XCTAssertEqual(directClicks, 2)

        let container = WebPanelContainerView()
        var containerClicks = 0
        container.onAddWebAppRequested = { containerClicks += 1 }
        container.debugTriggerEmptyStateAddWebApp()
        XCTAssertEqual(containerClicks, 1)

        let repo = MemoryProfileRepository()
        let store = TabStore(repository: repo)
        let pool = WebViewPool(onURLChange: { _, _ in }, initialLoad: { _, _ in })
        let controller = PanelController(
            tabStore: store,
            webViewPool: pool,
            frameStore: PanelFrameStore(),
            preferencesStore: AppPreferencesStore()
        )
        XCTAssertTrue(controller.isEmptyStateActionVisibleForTesting)

        var controllerRequests = 0
        controller.emptyStateAddWebAppHandlerForTesting = { controllerRequests += 1 }
        controller.debugTriggerEmptyStateAddWebApp(in: .standard)
        controller.debugTriggerEmptyStateAddWebApp(in: .fullscreenCompanion)
        XCTAssertEqual(controllerRequests, 2)
    }

    func testAppLocalizationSystemResolutionAndPreferencesPersistence() throws {
        defer { AppLocalization.resetForTesting() }

        XCTAssertEqual(
            AppLocalization.resolveSystemLanguage(preferredLanguages: ["zh-Hans-CN", "en-US"]),
            .simplifiedChinese
        )
        XCTAssertEqual(
            AppLocalization.resolveSystemLanguage(preferredLanguages: ["zh-Hant-HK"]),
            .simplifiedChinese
        )
        XCTAssertEqual(
            AppLocalization.resolveSystemLanguage(preferredLanguages: ["en-US", "zh-Hans"]),
            .english
        )
        XCTAssertEqual(
            AppLocalization.resolveSystemLanguage(preferredLanguages: ["ja-JP"]),
            .english
        )

        AppLocalization.setPreferredLanguagesProviderForTesting { ["zh-Hans-CN", "en-US"] }
        AppLocalization.apply(.system, postNotification: false)
        XCTAssertEqual(AppLocalization.effectiveLanguage, .simplifiedChinese)

        let suiteName = "FloatTabsTests.AppLanguage.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppPreferencesStore(defaults: defaults)
        XCTAssertEqual(store.appLanguage, .system)

        var notifications = 0
        let observer = NotificationCenter.default.addObserver(
            forName: .floatTabsAppLanguageDidChange,
            object: store,
            queue: .main
        ) { _ in
            notifications += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        store.appLanguage = .simplifiedChinese
        XCTAssertEqual(store.appLanguage, .simplifiedChinese)
        XCTAssertEqual(AppPreferencesStore(defaults: defaults).appLanguage, .simplifiedChinese)
        XCTAssertEqual(notifications, 1)

        store.appLanguage = .english
        XCTAssertEqual(AppPreferencesStore(defaults: defaults).appLanguage, .english)
        XCTAssertEqual(notifications, 2)
    }

    func testLiveLanguageSwitchUpdatesEmptyStateSettingsPagesAndMenusWithoutRestart() async {
        defer { AppLocalization.resetForTesting() }

        let emptyView = EmptyWebAppView()
        let container = WebPanelContainerView()
        let tab = ExternalWebAppTabView(slotID: UUID())
        tab.update(
            profile: WebAppProfile(
                order: 0,
                name: "ChatGPT",
                homeURL: URL(string: "https://chatgpt.com/")!
            ),
            isActive: true,
            isResident: true
        )
        let statusItem = StatusItemController(
            onToggle: {},
            isVisible: { false },
            onSettings: {},
            onQuit: {}
        )
        let settings = GlobalSettingsController(preferencesStore: AppPreferencesStore())
        settings.show(selecting: .alerts)
        XCTAssertEqual(settings.selectedTabIndexForTesting, 3)

        AppLocalization.apply(.simplifiedChinese)
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        XCTAssertEqual(emptyView.titleText, "添加网页应用")
        XCTAssertEqual(container.emptyStateActionTitleForTesting, "添加网页应用")
        XCTAssertEqual(
            GlobalSettingsPage.allCases.map(\.title),
            ["通用", "书签", "配置与存储", "提醒与通知", "快捷键", "高级"]
        )
        XCTAssertEqual(settings.windowTitleForTesting, "FloatTabs 设置")
        XCTAssertEqual(
            settings.toolbarTabTitlesForTesting,
            ["通用", "书签", "配置与存储", "提醒与通知", "快捷键", "高级"]
        )
        XCTAssertEqual(settings.selectedTabIndexForTesting, 3)
        XCTAssertNotNil(tab.makeContextMenu().item(withTitle: "返回主页"))
        XCTAssertNotNil(statusItem.rebuildMenu().item(withTitle: "显示 FloatTabs"))
        XCTAssertEqual(L10n.defaultDisplayName("Default"), "默认")
        XCTAssertEqual(L10n.defaultDisplayName("Work"), "Work")

        AppLocalization.apply(.english)
        await Task.yield()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        XCTAssertEqual(emptyView.titleText, "Add a Web App")
        XCTAssertEqual(container.emptyStateActionTitleForTesting, "Add a Web App")
        XCTAssertEqual(settings.windowTitleForTesting, "FloatTabs Settings")
        XCTAssertEqual(
            settings.toolbarTabTitlesForTesting,
            ["General", "Bookmarks", "Profiles & Storage", "Alerts", "Shortcuts", "Advanced"]
        )
        XCTAssertEqual(settings.selectedTabIndexForTesting, 3)
        XCTAssertNotNil(tab.makeContextMenu().item(withTitle: "Return to Home"))
        XCTAssertNotNil(statusItem.rebuildMenu().item(withTitle: "Show FloatTabs"))
        XCTAssertEqual(L10n.defaultDisplayName("Default"), "Default")
    }

    func testDeletingCustomBrowserProfileClearsInMemoryBookmarkReferenceAndAllowsSubsequentEdit() throws {
        let repo = MemoryProfileRepository()
        let store = TabStore(repository: repo)
        let customProfile = try XCTUnwrap(store.createBrowserProfile(name: "Work"))
        let bookmark = try XCTUnwrap(
            store.addBookmark(
                title: "GitHub",
                url: URL(string: "https://github.com")!,
                browserProfileID: customProfile.id
            )
        )
        XCTAssertEqual(bookmark.browserProfileID, customProfile.id)

        XCTAssertTrue(store.deleteBrowserProfileMetadata(id: customProfile.id))
        let orphanedInMemory = try XCTUnwrap(store.bookmarks.first(where: { $0.id == bookmark.id }))
        XCTAssertNil(orphanedInMemory.browserProfileID)

        // Updating the bookmark in the same session must succeed with sanitized profile binding.
        XCTAssertTrue(
            store.updateBookmark(
                id: bookmark.id,
                title: "GitHub Enterprise",
                url: URL(string: "https://github.com/lost0rz")!,
                folderID: nil,
                notes: "Updated",
                preferredWebsiteMode: .desktop,
                browserProfileID: nil
            )
        )
        let updated = try XCTUnwrap(store.bookmarks.first(where: { $0.id == bookmark.id }))
        XCTAssertEqual(updated.title, "GitHub Enterprise")
        XCTAssertNil(updated.browserProfileID)
    }

    func testFifthHiddenGroupWithUnreadShowsOverflowUnreadIndicatorOnVisibleGroupControls() {
        let zone = ExternalControlZoneView(frame: NSRect(x: 0, y: 0, width: 120, height: 600))
        let hiddenGroupID = UUID()
        let options = [
            WebAppGroupMenuOption(
                id: nil,
                name: "Default",
                borderTheme: nil,
                customBorderColorHex: nil,
                isDefault: true,
                isActive: true,
                slotCount: 1,
                unreadCount: 0
            ),
            WebAppGroupMenuOption(
                id: UUID(),
                name: "Group 2",
                borderTheme: .blue,
                customBorderColorHex: nil,
                isDefault: false,
                isActive: false,
                slotCount: 1,
                unreadCount: 0
            ),
            WebAppGroupMenuOption(
                id: UUID(),
                name: "Group 3",
                borderTheme: .green,
                customBorderColorHex: nil,
                isDefault: false,
                isActive: false,
                slotCount: 1,
                unreadCount: 0
            ),
            WebAppGroupMenuOption(
                id: UUID(),
                name: "Group 4",
                borderTheme: .orange,
                customBorderColorHex: nil,
                isDefault: false,
                isActive: false,
                slotCount: 1,
                unreadCount: 0
            ),
            WebAppGroupMenuOption(
                id: hiddenGroupID,
                name: "Hidden Unread Group",
                borderTheme: .purple,
                customBorderColorHex: nil,
                isDefault: false,
                isActive: false,
                slotCount: 1,
                unreadCount: 2
            ),
        ]

        zone.setGroupsSnapshot(options: options, activeGroupID: nil)
        zone.layoutSubtreeIfNeeded()

        let visible = zone.visibleGroupControlsForTesting
        XCTAssertEqual(visible.count, 4)
        XCTAssertTrue(
            visible.contains { $0.hasVisibleUnreadIndicator && $0.isShowingHiddenGroupUnreadForTesting }
        )
    }
}
