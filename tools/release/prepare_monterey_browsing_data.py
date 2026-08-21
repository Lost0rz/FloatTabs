#!/usr/bin/env python3
"""Stage 10: Monterey browsing-data reset transaction.

MC-B3 is deliberately a build-time compatibility transform. The normal
FloatTabs sources keep their existing WebKit behavior; this stage injects the
Monterey-only data-store manager, reset barrier, Privacy settings surface, and
focused regression tests into the already-generated compatibility sources.
"""

import os
from pathlib import Path

from monterey_transform_lib import (
    read_source,
    replace_exact_once,
    replace_once_regex,
    require_absent,
    require_present,
    write_source,
)

ROOT = Path(
    os.environ.get(
        "FLOATTABS_TRANSFORM_ROOT",
        str(Path(__file__).resolve().parents[2]),
    )
)

DATA_STORE_MANAGER = r'''enum MontereyBrowsingDataResetError: LocalizedError {
    case configurationSaveFailed
    case unavailable

    var errorDescription: String? {
        switch self {
        case .configurationSaveFailed:
            return "FloatTabs could not save the reset navigation state."
        case .unavailable:
            return "The FloatTabs reset controller is unavailable."
        }
    }
}

/// The sole authority for the Monterey Compatibility Edition's persistent
/// WebKit data store and its user-initiated removal transaction.
@MainActor
final class MontereyBrowserDataStoreManager {
    typealias RemovalHandler = (
        WKWebsiteDataStore,
        Set<String>,
        Date,
        @escaping () -> Void
    ) -> Void

    static let shared = MontereyBrowserDataStoreManager()

    let websiteDataStore: WKWebsiteDataStore
    private let removalHandler: RemovalHandler

    init(
        websiteDataStore: WKWebsiteDataStore = .default(),
        removalHandler: RemovalHandler? = nil
    ) {
        self.websiteDataStore = websiteDataStore
        self.removalHandler = removalHandler ?? { store, types, _, completion in
            store.removeData(
                ofTypes: types,
                modifiedSince: .distantPast,
                completionHandler: completion
            )
        }
    }

    /// Completion is forwarded only after the underlying WebKit removal
    /// completion. Tests inject the removalHandler and never call real removal.
    func resetAllBrowsingData(completion: @escaping () -> Void) {
        removalHandler(
            websiteDataStore,
            WKWebsiteDataStore.allWebsiteDataTypes(),
            .distantPast,
            completion
        )
    }
}

/// Keeps confirmation/reset state deterministic without coupling tests to an
/// AppKit alert or to the user's real WebsiteDataStore.
@MainActor
final class MontereyPrivacyResetCoordinator {
    private(set) var isResetInProgress = false

    @discardableResult
    func beginConfirmedReset() -> Bool {
        guard !isResetInProgress else { return false }
        isResetInProgress = true
        return true
    }

    func cancelConfirmation() {
        // Cancel is intentionally a no-op: no data-store call has started.
    }

    func completeReset() {
        isResetInProgress = false
    }
}

'''

PRIVACY_CONTROLLER = r'''@MainActor
final class PrivacySettingsViewController: NSViewController {
    typealias ResetHandler = (@escaping (Result<Void, Error>) -> Void) -> Void

    private let onResetBrowsingData: ResetHandler
    private let resetCoordinator = MontereyPrivacyResetCoordinator()
    private let resetButton = NSButton(title: "Reset All Browsing Data…", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private var confirmationPresented = false

    init(onResetBrowsingData: @escaping ResetHandler) {
        self.onResetBrowsingData = onResetBrowsingData
        super.init(nibName: nil, bundle: nil)
        title = "Privacy"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        resetButton.bezelStyle = .rounded
        resetButton.image = NSImage(
            systemSymbolName: "trash",
            accessibilityDescription: "Reset browsing data"
        )
        resetButton.imagePosition = .imageLeading
        resetButton.target = self
        resetButton.action = #selector(resetButtonPressed(_:))

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 0
        statusLabel.isHidden = true

        let stack = NSStackView(views: [
            sectionTitle("Browsing Data"),
            detailLabel(
                "Reset removes cookies, website storage, caches, and other persistent WebKit browsing data for FloatTabs. Web App names, Home URLs, rendering profiles, residency policies, and other configuration are preserved. Downloads are not restored by this operation."
            ),
            resetButton,
            statusLabel,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 34),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -34),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 30),
        ])
        view = root
    }

    @objc private func resetButtonPressed(_ sender: NSButton) {
        guard !resetCoordinator.isResetInProgress, !confirmationPresented else { return }
        guard let window = view.window else { return }

        confirmationPresented = true
        let alert = NSAlert()
        alert.messageText = "Reset All Browsing Data?"
        alert.informativeText = "This removes FloatTabs' WebKit cookies, website storage, caches, and related browsing data. Your configured Web Apps and their settings will be preserved."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.confirmationPresented = false
            guard response == .alertFirstButtonReturn else {
                self.resetCoordinator.cancelConfirmation()
                return
            }
            self.beginReset()
        }
    }

    private func beginReset() {
        guard resetCoordinator.beginConfirmedReset() else { return }
        resetButton.isEnabled = false
        resetButton.title = "Resetting…"
        statusLabel.stringValue = "Waiting for WebKit to finish removing browsing data…"
        statusLabel.isHidden = false

        onResetBrowsingData { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.resetCoordinator.completeReset()
                self.resetButton.isEnabled = true
                self.resetButton.title = "Reset All Browsing Data…"
                switch result {
                case .success:
                    self.statusLabel.stringValue = "Browsing Data Reset"
                case .failure(let error):
                    self.statusLabel.stringValue = "Browsing Data Reset Failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let value = NSTextField(labelWithString: text)
        value.font = .systemFont(ofSize: 13, weight: .semibold)
        return value
    }

    private func detailLabel(_ text: String) -> NSTextField {
        let value = NSTextField(wrappingLabelWithString: text)
        value.font = .systemFont(ofSize: 12)
        value.textColor = .secondaryLabelColor
        value.maximumNumberOfLines = 0
        value.widthAnchor.constraint(lessThanOrEqualToConstant: 510).isActive = true
        return value
    }
}

'''

def patch_web_view_factory() -> None:
    path = ROOT / "FloatTabs/Web/WebViewFactory.swift"
    text = read_source(path)
    text = replace_once_regex(
        text,
        r"^struct BrowserVersionCatalog",
        DATA_STORE_MANAGER + "struct BrowserVersionCatalog",
        label="MC-B3 browser data-store manager declaration",
    )
    text = replace_exact_once(
        text,
        """    static func makeWebView(
        renderingProfile: WebRenderingProfile = .canonicalDefault
    ) -> WKWebView {
""",
        """    static func makeWebView(
        renderingProfile: WebRenderingProfile = .canonicalDefault,
        browserDataStoreManager: MontereyBrowserDataStoreManager = .shared
    ) -> WKWebView {
""",
        label="MC-B3 injectable WebView data-store seam",
    )
    text = replace_exact_once(
        text,
        "        configuration.websiteDataStore = .default()\n",
        "        configuration.websiteDataStore = browserDataStoreManager.websiteDataStore\n",
        label="MC-B3 shared persistent WebsiteDataStore wiring",
    )
    write_source(path, text)

def patch_web_view_pool() -> None:
    path = ROOT / "FloatTabs/Web/WebViewPool.swift"
    text = read_source(path)
    text = replace_exact_once(
        text,
        "    var onResidentSetChange: (() -> Void)?\n\n",
        """    var onResidentSetChange: (() -> Void)?

    let browserDataStoreManager: MontereyBrowserDataStoreManager

""",
        label="MC-B3 WebViewPool manager ownership",
    )
    text = replace_exact_once(
        text,
        """        isSlotActive: @escaping IsSlotActiveHandler = { _ in true },
        downloadCoordinator: DownloadCoordinator? = nil
    ) {
        self.onURLChange = onURLChange
""",
        """        isSlotActive: @escaping IsSlotActiveHandler = { _ in true },
        downloadCoordinator: DownloadCoordinator? = nil,
        browserDataStoreManager: MontereyBrowserDataStoreManager = .shared
    ) {
        self.onURLChange = onURLChange
        self.browserDataStoreManager = browserDataStoreManager
""",
        label="MC-B3 WebViewPool manager injection",
    )
    text = replace_exact_once(
        text,
        "        let webView = WebViewFactory.makeWebView(renderingProfile: runtimeRendering)\n",
        """        let webView = WebViewFactory.makeWebView(
            renderingProfile: runtimeRendering,
            browserDataStoreManager: browserDataStoreManager
        )
""",
        label="MC-B3 WebViewPool-to-factory manager wiring",
    )
    release_anchor = """    /// Pauses currently playing media without putting the page into WebKit's
"""
    release_all = """    /// Releases every transient runtime and popup before WebsiteDataStore
    /// removal. The resident-set callback fires once after the final state is
    /// coherent, including when the pool was already empty.
    func releaseAll() {
        for coordinator in popupCoordinators.values {
            coordinator.closeAll()
        }
        popupCoordinators.removeAll()
        navigationObservers.removeAll()
        appliedRenderingProfiles.removeAll()
        lastKnownURLs.removeAll()
        deferredReloadSlotIDs.removeAll()

        for webView in webViews.values {
            webView.removeFromSuperview()
        }
        webViews.removeAll()
        onResidentSetChange?()
    }

    /// Internal diagnostics used by the generated MC-B3 lifecycle tests.
    var transientRuntimeSlotIDs: Set<UUID> {
        var ids = Set(webViews.keys)
        ids.formUnion(navigationObservers.keys)
        ids.formUnion(popupCoordinators.keys)
        ids.formUnion(appliedRenderingProfiles.keys)
        ids.formUnion(lastKnownURLs.keys)
        ids.formUnion(deferredReloadSlotIDs)
        return ids
    }

"""
    text = replace_exact_once(
        text,
        release_anchor,
        release_all + release_anchor,
        label="MC-B3 WebViewPool releaseAll insertion",
    )
    write_source(path, text)

def patch_tab_store() -> None:
    path = ROOT / "FloatTabs/Tabs/TabStore.swift"
    text = read_source(path)
    text = replace_exact_once(
        text,
        "    func storedStateSnapshot() -> StoredWebAppState {\n",
        """    /// Resets only volatile navigation positions. All Web App configuration
    /// fields remain byte-for-byte equivalent in the durable state.
    @discardableResult
    func resetCurrentURLsToHome() -> Bool {
        persistConfigurationMutation {
            for index in profiles.indices {
                profiles[index].currentURL = profiles[index].homeURL
            }
            return true
        }
    }

    func storedStateSnapshot() -> StoredWebAppState {
""",
        label="MC-B3 transactional currentURL normalization",
    )
    write_source(path, text)

def patch_panel_controller() -> None:
    path = ROOT / "FloatTabs/Panel/PanelController.swift"
    text = read_source(path)
    text = replace_exact_once(
        text,
        "    private var lastSynchronizedActiveProfile: WebAppProfile?\n",
        """    private var lastSynchronizedActiveProfile: WebAppProfile?
    private var browsingDataResetInProgress = false
""",
        label="MC-B3 Panel reset barrier state",
    )
    text = replace_exact_once(
        text,
        """    private let webViewPool: WebViewPool
    private let frameStore: PanelFrameStore
""",
        """    private let webViewPool: WebViewPool
    private let browserDataStoreManager: MontereyBrowserDataStoreManager
    private let frameStore: PanelFrameStore
""",
        label="MC-B3 Panel manager property",
    )
    text = replace_exact_once(
        text,
        """        webViewPool: WebViewPool,
        frameStore: PanelFrameStore = PanelFrameStore(),
        preferencesStore: AppPreferencesStore? = nil
    ) {
        self.tabStore = tabStore
        self.webViewPool = webViewPool
        self.frameStore = frameStore
""",
        """        webViewPool: WebViewPool,
        frameStore: PanelFrameStore = PanelFrameStore(),
        preferencesStore: AppPreferencesStore? = nil,
        browserDataStoreManager: MontereyBrowserDataStoreManager? = nil
    ) {
        self.tabStore = tabStore
        self.webViewPool = webViewPool
        self.browserDataStoreManager = browserDataStoreManager ?? webViewPool.browserDataStoreManager
        self.frameStore = frameStore
""",
        label="MC-B3 Panel manager injection",
    )
    reset_method = r'''    @discardableResult
    func resetAllBrowsingData(
        completion: @escaping (Result<Void, Error>) -> Void
    ) -> Bool {
        guard !browsingDataResetInProgress else { return false }
        browsingDataResetInProgress = true

        let existingIDs = Set(tabStore.profiles.map(\.id))
        slotLifecycleCoordinator.reset(slotIDs: existingIDs)
        webViewPool.releaseAll()
        pendingSlotSynchronization = false
        lastSynchronizedActiveID = nil
        lastSynchronizedActiveProfile = nil

        browserDataStoreManager.resetAllBrowsingData { [weak self] in
            guard let self else { return }
            guard self.tabStore.resetCurrentURLsToHome() else {
                self.browsingDataResetInProgress = false
                completion(.failure(MontereyBrowsingDataResetError.configurationSaveFailed))
                return
            }

            // The barrier stays up through data removal and URL persistence.
            // Only this final path may recreate the active runtime; reconcile
            // never creates inactive slots.
            self.browsingDataResetInProgress = false
            self.synchronizeSlotState()
            completion(.success(()))
        }
        return true
    }

    var isBrowsingDataResetInProgress: Bool {
        browsingDataResetInProgress
    }

    static func shouldSynchronizeSlotState(
        browsingDataResetInProgress: Bool
    ) -> Bool {
        !browsingDataResetInProgress
    }

'''
    text = replace_once_regex(
        text,
        r"^    static func shouldAutoHide\(",
        reset_method + "    static func shouldAutoHide(",
        label="MC-B3 Panel reset transaction",
    )
    text = replace_exact_once(
        text,
        """    private func synchronizeSlotState() {
        guard !sourceHostController.isSessionLocked else {
""",
        """    private func synchronizeSlotState() {
        guard !browsingDataResetInProgress else { return }
        guard !sourceHostController.isSessionLocked else {
""",
        label="MC-B3 synchronizeSlotState reset barrier",
    )
    write_source(path, text)

def patch_app_coordinator() -> None:
    path = ROOT / "FloatTabs/App/AppCoordinator.swift"
    text = read_source(path)
    text = replace_exact_once(
        text,
        """            let tabStore = TabStore(repository: profileRepository)
            tabStore.onPersistenceFailure = {
""",
        """            let tabStore = TabStore(repository: profileRepository)
            let browserDataStoreManager = MontereyBrowserDataStoreManager.shared
            tabStore.onPersistenceFailure = {
""",
        label="MC-B3 AppCoordinator manager creation",
    )
    text = replace_exact_once(
        text,
        """                isSlotActive: { slotID in
                    tabStore.activeTabID == slotID
                }
            )
""",
        """                isSlotActive: { slotID in
                    tabStore.activeTabID == slotID
                },
                browserDataStoreManager: browserDataStoreManager
            )
""",
        label="MC-B3 AppCoordinator-to-WebViewPool manager wiring",
    )
    text = replace_exact_once(
        text,
        """                webViewPool: webViewPool,
                preferencesStore: resolvedPreferencesStore
            )
""",
        """                webViewPool: webViewPool,
                preferencesStore: resolvedPreferencesStore,
                browserDataStoreManager: browserDataStoreManager
            )
""",
        label="MC-B3 AppCoordinator-to-Panel manager wiring",
    )
    text = replace_exact_once(
        text,
        """            onRestoreBackup: { [weak self] url in
                guard let self else { throw FloatTabsBackupError.restoreFailed }
                return try self.restoreBackup(from: url)
            }
""",
        """            onRestoreBackup: { [weak self] url in
                guard let self else { throw FloatTabsBackupError.restoreFailed }
                return try self.restoreBackup(from: url)
            },
            onResetBrowsingData: { [weak self] completion in
                guard let self else {
                    completion(.failure(MontereyBrowsingDataResetError.unavailable))
                    return
                }
                _ = self.panelController.resetAllBrowsingData(completion: completion)
            }
""",
        label="MC-B3 GlobalSettings reset handler wiring",
    )
    write_source(path, text)

def patch_global_settings() -> None:
    path = ROOT / "FloatTabs/UI/GlobalSettingsController.swift"
    text = read_source(path)
    text = replace_exact_once(
        text,
        """    typealias RestoreBackupHandler = (URL) throws -> URL

    private let preferencesStore: AppPreferencesStore
""",
        """    typealias RestoreBackupHandler = (URL) throws -> URL
    typealias ResetBrowsingDataHandler = (@escaping (Result<Void, Error>) -> Void) -> Void

    private let preferencesStore: AppPreferencesStore
""",
        label="MC-B3 GlobalSettings reset handler type",
    )
    text = replace_exact_once(
        text,
        """    private let onRestoreBackup: RestoreBackupHandler
    private lazy var settingsWindow: NSWindow = makeWindow()
""",
        """    private let onRestoreBackup: RestoreBackupHandler
    private let onResetBrowsingData: ResetBrowsingDataHandler
    private lazy var settingsWindow: NSWindow = makeWindow()
""",
        label="MC-B3 GlobalSettings reset handler storage",
    )
    text = replace_exact_once(
        text,
        """        onExportBackup: @escaping ExportBackupHandler = { _ in },
        onRestoreBackup: @escaping RestoreBackupHandler = { _ in throw FloatTabsBackupError.restoreFailed }
    ) {
        self.preferencesStore = preferencesStore
        self.onExportBackup = onExportBackup
        self.onRestoreBackup = onRestoreBackup
""",
        """        onExportBackup: @escaping ExportBackupHandler = { _ in },
        onRestoreBackup: @escaping RestoreBackupHandler = { _ in throw FloatTabsBackupError.restoreFailed },
        onResetBrowsingData: @escaping ResetBrowsingDataHandler = { completion in
            completion(.success(()))
        }
    ) {
        self.preferencesStore = preferencesStore
        self.onExportBackup = onExportBackup
        self.onRestoreBackup = onRestoreBackup
        self.onResetBrowsingData = onResetBrowsingData
""",
        label="MC-B3 GlobalSettings reset handler initialization",
    )
    text = replace_exact_once(
        text,
        """        addTab(
            title: "Account & Language",
            symbol: "person.crop.circle",
            controller: AccountLanguageSettingsViewController(
                onExportBackup: onExportBackup,
                onRestoreBackup: onRestoreBackup
            ),
            to: tabs
        )

""",
        """        addTab(
            title: "Account & Language",
            symbol: "person.crop.circle",
            controller: AccountLanguageSettingsViewController(
                onExportBackup: onExportBackup,
                onRestoreBackup: onRestoreBackup
            ),
            to: tabs
        )
        addTab(
            title: "Privacy",
            symbol: "hand.raised",
            controller: PrivacySettingsViewController(
                onResetBrowsingData: onResetBrowsingData
            ),
            to: tabs
        )

""",
        label="MC-B3 Privacy settings tab",
    )
    text = replace_once_regex(
        text,
        r"^@MainActor\nprivate final class AppearanceSettingsViewController",
        PRIVACY_CONTROLLER + "@MainActor\nprivate final class AppearanceSettingsViewController",
        label="MC-B3 Privacy settings controller",
    )
    write_source(path, text)

TAB_STORE_TESTS = r'''

@MainActor
final class MontereyBrowsingDataPersistenceTests: XCTestCase {
    func testResetCurrentURLsToHomePreservesEveryConfigurationField() {
        let homeURL = URL(string: "https://example.com/home")!
        let currentURL = URL(string: "https://example.com/visited")!
        let rendering = WebRenderingProfile(
            websiteMode: .mobile,
            browserIdentity: .androidChrome,
            customUserAgent: nil,
            sizePreset: .small,
            devicePresetID: nil,
            orientation: .landscape,
            viewportWidth: 780,
            viewportHeight: 390,
            zoom: 1.25
        )
        let original = WebAppProfile(
            order: 0,
            name: "Configured",
            homeURL: homeURL,
            currentURL: currentURL,
            homeURLSchemeWasInferred: true,
            renderingProfile: rendering,
            residencyPolicy: .cold,
            backgroundMediaPolicy: .allowBackgroundAudio,
            createdAt: Date(timeIntervalSince1970: 100),
            lastUsedAt: Date(timeIntervalSince1970: 200)
        )
        let repository = MemoryProfileRepository(state: StoredWebAppState(
            version: StoredWebAppState.currentVersion,
            profiles: [original],
            lastActiveTabID: original.id
        ))
        let store = TabStore(repository: repository)
        let persistedBeforeReset = store.profiles

        XCTAssertTrue(store.resetCurrentURLsToHome())
        var expected = persistedBeforeReset[0]
        expected.currentURL = expected.homeURL
        XCTAssertEqual(store.profiles, [expected])
        XCTAssertEqual(repository.state.profiles, [expected])
    }
}
'''

DATA_STORE_TESTS = r'''

@MainActor
final class MontereyBrowsingDataResetTests: XCTestCase {
    func testManagerUsesAllTypesAndDistantPastAndWaitsForInjectedCompletion() {
        var capturedTypes: Set<String>?
        var capturedDate: Date?
        var underlyingCompletion: (() -> Void)?
        var completed = false
        let manager = MontereyBrowserDataStoreManager(
            websiteDataStore: .default(),
            removalHandler: { _, types, modifiedSince, completion in
                capturedTypes = types
                capturedDate = modifiedSince
                underlyingCompletion = completion
            }
        )

        manager.resetAllBrowsingData { completed = true }
        XCTAssertFalse(completed)
        XCTAssertEqual(capturedTypes, WKWebsiteDataStore.allWebsiteDataTypes())
        XCTAssertEqual(capturedDate, .distantPast)
        XCTAssertNotNil(underlyingCompletion)

        underlyingCompletion?()
        XCTAssertTrue(completed)
    }

    func testPrivacyConfirmationCoordinatorCancelsAndIgnoresDuplicateReset() {
        let coordinator = MontereyPrivacyResetCoordinator()
        coordinator.cancelConfirmation()
        XCTAssertFalse(coordinator.isResetInProgress)
        XCTAssertTrue(coordinator.beginConfirmedReset())
        XCTAssertFalse(coordinator.beginConfirmedReset())
        XCTAssertTrue(coordinator.isResetInProgress)
        coordinator.completeReset()
        XCTAssertFalse(coordinator.isResetInProgress)
        XCTAssertTrue(coordinator.beginConfirmedReset())
    }

    func testWebViewPoolReleaseAllClearsTransientRuntimeAndNotifiesOnce() {
        var residentChanges = 0
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, _ in }
        )
        pool.onResidentSetChange = { residentChanges += 1 }
        let first = WebAppProfile(
            order: 0,
            name: "First",
            homeURL: URL(string: "https://example.com/first")!
        )
        let second = WebAppProfile(
            order: 1,
            name: "Second",
            homeURL: URL(string: "https://example.com/second")!
        )
        _ = pool.webView(for: first)
        _ = pool.webView(for: second)
        XCTAssertEqual(pool.transientRuntimeSlotIDs, Set([first.id, second.id]))

        pool.releaseAll()

        XCTAssertEqual(pool.count, 0)
        XCTAssertTrue(pool.residentSlotIDs.isEmpty)
        XCTAssertTrue(pool.transientRuntimeSlotIDs.isEmpty)
        XCTAssertEqual(residentChanges, 3)
    }

    func testPanelSynchronizationIsBlockedDuringResetBarrier() {
        XCTAssertFalse(
            PanelController.shouldSynchronizeSlotState(
                browsingDataResetInProgress: true
            )
        )
        XCTAssertTrue(
            PanelController.shouldSynchronizeSlotState(
                browsingDataResetInProgress: false
            )
        )
    }
}
'''

def patch_tab_store_tests() -> None:
    path = ROOT / "FloatTabsTests/TabStoreTests.swift"
    text = read_source(path)
    require_absent(text, "MontereyBrowsingDataPersistenceTests", label="MC-B3 duplicate TabStore test injection")
    write_source(path, text + TAB_STORE_TESTS)

def patch_data_store_tests() -> None:
    path = ROOT / "FloatTabsTests/WebViewFactoryTests.swift"
    text = read_source(path)
    require_absent(text, "MontereyBrowsingDataResetTests", label="MC-B3 duplicate data reset test injection")
    write_source(path, text + DATA_STORE_TESTS)

def verify_contract() -> None:
    build_script = read_source(ROOT / "tools/release/build_monterey_dmg.sh")
    factory = read_source(ROOT / "FloatTabs/Web/WebViewFactory.swift")
    pool = read_source(ROOT / "FloatTabs/Web/WebViewPool.swift")
    panel = read_source(ROOT / "FloatTabs/Panel/PanelController.swift")
    store = read_source(ROOT / "FloatTabs/Tabs/TabStore.swift")
    settings = read_source(ROOT / "FloatTabs/UI/GlobalSettingsController.swift")
    app = read_source(ROOT / "FloatTabs/App/AppCoordinator.swift")
    factory_tests = read_source(ROOT / "FloatTabsTests/WebViewFactoryTests.swift")
    tab_tests = read_source(ROOT / "FloatTabsTests/TabStoreTests.swift")

    require_present(
        build_script,
        "python3 tools/release/prepare_monterey_browser_identity.py\n"
        "python3 tools/release/prepare_monterey_browsing_data.py\n",
        label="MC-B3 transform ordering after MC-B2",
    )
    require_present(factory, "final class MontereyBrowserDataStoreManager", label="MC-B3 data-store manager")
    require_present(factory, "WKWebsiteDataStore.allWebsiteDataTypes()", label="MC-B3 all WebKit data types")
    require_present(factory, "modifiedSince: .distantPast", label="MC-B3 distant-past removal")
    require_present(factory, "configuration.websiteDataStore = browserDataStoreManager.websiteDataStore", label="MC-B3 shared store assignment")
    require_present(factory, "static let shared = MontereyBrowserDataStoreManager()", label="MC-B3 one shared manager")
    require_present(pool, "func releaseAll()", label="MC-B3 pool releaseAll")
    for field in [
        "webViews.removeAll()",
        "navigationObservers.removeAll()",
        "popupCoordinators.removeAll()",
        "appliedRenderingProfiles.removeAll()",
        "lastKnownURLs.removeAll()",
        "deferredReloadSlotIDs.removeAll()",
        "coordinator.closeAll()",
    ]:
        require_present(pool, field, label=f"MC-B3 releaseAll field: {field}")
    require_present(panel, "browsingDataResetInProgress", label="MC-B3 Panel reset barrier")
    require_present(panel, "guard !browsingDataResetInProgress else { return }", label="MC-B3 synchronization barrier")
    require_present(panel, "slotLifecycleCoordinator.reset(slotIDs: existingIDs)", label="MC-B3 lifecycle reset")
    require_present(panel, "webViewPool.releaseAll()", label="MC-B3 runtime release transaction")
    require_present(panel, "resetCurrentURLsToHome()", label="MC-B3 post-removal URL normalization")
    require_present(store, "func resetCurrentURLsToHome()", label="MC-B3 durable URL normalization")
    require_present(settings, "title: \"Privacy\"", label="MC-B3 Privacy tab")
    require_present(settings, "symbol: \"hand.raised\"", label="MC-B3 Privacy icon")
    require_present(settings, "Reset All Browsing Data…", label="MC-B3 Privacy reset button")
    require_present(settings, "Resetting…", label="MC-B3 pending UI state")
    require_present(settings, "Browsing Data Reset", label="MC-B3 completed UI state")
    require_present(app, "onResetBrowsingData:", label="MC-B3 AppCoordinator reset wiring")
    require_present(factory_tests, "testManagerUsesAllTypesAndDistantPastAndWaitsForInjectedCompletion", label="MC-B3 manager test")
    require_present(factory_tests, "testWebViewPoolReleaseAllClearsTransientRuntimeAndNotifiesOnce", label="MC-B3 releaseAll test")
    require_present(tab_tests, "testResetCurrentURLsToHomePreservesEveryConfigurationField", label="MC-B3 persistence test")
    require_absent(factory, "WKWebsiteDataStore(forIdentifier:", label="MC-B3 isolated non-default data store")
    require_absent(factory, "fetchDataRecords", label="MC-B3 private data-record API")
    for source, label in [(factory, "WebViewFactory"), (pool, "WebViewPool"), (panel, "PanelController")]:
        for forbidden in ["chatgpt.com", "chat.openai.com", "openai.com", "bilibili.com", "b23.tv", "ChatGPT"]:
            require_absent(source, forbidden, label=f"MC-B3 host-specific runtime logic in {label}: {forbidden}")

def main() -> None:
    patch_web_view_factory()
    patch_web_view_pool()
    patch_tab_store()
    patch_panel_controller()
    patch_app_coordinator()
    patch_global_settings()
    patch_tab_store_tests()
    patch_data_store_tests()
    verify_contract()
    print("Monterey browsing-data reset source preparation complete")

if __name__ == "__main__":
    main()
