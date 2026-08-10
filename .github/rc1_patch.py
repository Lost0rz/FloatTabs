from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected one match, found {count}: {old[:160]!r}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")


def write(path: str, content: str) -> None:
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content, encoding="utf-8")


# ---------------------------------------------------------------------------
# Global preferences become one data owner so backup/restore does not copy
# private UserDefaults keys across controllers.
# ---------------------------------------------------------------------------
write(
    "FloatTabs/Persistence/AppPreferencesStore.swift",
    '''import AppKit


enum AppAppearanceMode: String, CaseIterable, Equatable, Codable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var appKitAppearance: NSAppearance? {
        switch self {
        case .system:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
final class AppPreferencesStore {
    static let appearanceKey = "FloatTabs.appearanceMode"
    static let followPreferredSizeKey = "FloatTabs.followTabPreferredSize"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var appearanceMode: AppAppearanceMode {
        get {
            guard let raw = defaults.string(forKey: Self.appearanceKey),
                  let mode = AppAppearanceMode(rawValue: raw) else {
                return .system
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.appearanceKey)
            applyAppearance(newValue)
        }
    }

    var followPreferredSize: Bool {
        get {
            guard defaults.object(forKey: Self.followPreferredSizeKey) != nil else {
                return true
            }
            return defaults.bool(forKey: Self.followPreferredSizeKey)
        }
        set {
            defaults.set(newValue, forKey: Self.followPreferredSizeKey)
        }
    }

    func applyStoredAppearance() {
        applyAppearance(appearanceMode)
    }

    private func applyAppearance(_ mode: AppAppearanceMode) {
        NSApp.appearance = mode.appKitAppearance
    }
}
''',
)

# ---------------------------------------------------------------------------
# Versioned FloatTabs-owned configuration backup. Website credentials/session
# state are deliberately outside this document.
# ---------------------------------------------------------------------------
write(
    "FloatTabs/Persistence/FloatTabsBackupService.swift",
    '''import Foundation

struct FloatTabsBackupShortcut: Codable, Equatable {
    let carbonKeyCode: Int
    let carbonModifiers: Int
}

struct FloatTabsBackupPreferences: Codable, Equatable {
    let appearanceMode: AppAppearanceMode
    let followPreferredSize: Bool
}

struct FloatTabsBackupDocument: Codable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let createdAt: Date
    let sourceAppVersion: String
    let sourceBuild: String
    let webAppState: StoredWebAppState
    let globalPreferences: FloatTabsBackupPreferences
    let globalShowHideShortcut: FloatTabsBackupShortcut?
}

enum FloatTabsBackupError: LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case unsupportedWebAppStateVersion(Int)
    case restoreFailed

    var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version):
            return "This FloatTabs backup uses unsupported backup schema version \\(version)."
        case let .unsupportedWebAppStateVersion(version):
            return "This backup contains unsupported Web App state version \\(version)."
        case .restoreFailed:
            return "FloatTabs could not replace the current configuration. The rollback backup was kept."
        }
    }
}

struct FloatTabsBackupService {
    static let fileExtension = "floattabsbackup"

    private let fileManager: FileManager
    private let backupDirectoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileManager: FileManager = .default,
        backupDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.backupDirectoryURL = backupDirectoryURL
            ?? Self.defaultBackupDirectory(fileManager: fileManager)

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func encode(_ document: FloatTabsBackupDocument) throws -> Data {
        try encoder.encode(document)
    }

    func decode(_ data: Data) throws -> FloatTabsBackupDocument {
        let document = try decoder.decode(FloatTabsBackupDocument.self, from: data)
        guard document.schemaVersion == FloatTabsBackupDocument.currentSchemaVersion else {
            throw FloatTabsBackupError.unsupportedSchema(document.schemaVersion)
        }
        guard document.webAppState.version == StoredWebAppState.currentVersion else {
            throw FloatTabsBackupError.unsupportedWebAppStateVersion(document.webAppState.version)
        }
        return document
    }

    func load(from url: URL) throws -> FloatTabsBackupDocument {
        try decode(Data(contentsOf: url))
    }

    func write(_ document: FloatTabsBackupDocument, to url: URL) throws {
        let data = try encode(document)
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
    }

    @discardableResult
    func writeRollback(
        _ document: FloatTabsBackupDocument,
        now: Date = Date()
    ) throws -> URL {
        try fileManager.createDirectory(
            at: backupDirectoryURL,
            withIntermediateDirectories: true
        )
        let url = backupDirectoryURL.appendingPathComponent(
            "FloatTabs-before-restore-\\(Self.timestamp(now))-\\(UUID().uuidString.prefix(8)).\\(Self.fileExtension)"
        )
        try write(document, to: url)
        return url
    }

    @discardableResult
    func writeAutomaticVersionSnapshot(
        _ document: FloatTabsBackupDocument
    ) throws -> URL {
        try fileManager.createDirectory(
            at: backupDirectoryURL,
            withIntermediateDirectories: true
        )
        let version = Self.safeFileComponent(document.sourceAppVersion)
        let build = Self.safeFileComponent(document.sourceBuild)
        let url = backupDirectoryURL.appendingPathComponent(
            "FloatTabs-auto-\\(version)-\\(build).\\(Self.fileExtension)"
        )
        try write(document, to: url)
        return url
    }

    static func suggestedExportFileName(now: Date = Date()) -> String {
        "FloatTabs-Backup-\\(timestamp(now)).\\(fileExtension)"
    }

    private static func defaultBackupDirectory(fileManager: FileManager) -> URL {
        let applicationSupport = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)

        return applicationSupport
            .appendingPathComponent("FloatTabs", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private static func safeFileComponent(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let scalars = raw.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        let value = String(scalars)
        return value.isEmpty ? "unknown" : value
    }
}
''',
)

# ---------------------------------------------------------------------------
# Profile sanitizer is reusable by disk load and backup import.
# ---------------------------------------------------------------------------
replace_once(
    "FloatTabs/Persistence/ProfileRepository.swift",
    '''        let sanitizedProfiles = decoded.profiles.compactMap(Self.sanitizedProfile)\n        return StoredWebAppState(\n            version: StoredWebAppState.currentVersion,\n            profiles: sanitizedProfiles,\n            lastActiveTabID: decoded.lastActiveTabID\n        )\n''',
    '''        return decoded.sanitizedForUse()\n''',
)
replace_once(
    "FloatTabs/Persistence/ProfileRepository.swift",
    '''    private static func sanitizedProfile(_ profile: WebAppProfile) -> WebAppProfile? {\n        guard WebAppURL.isSafe(profile.homeURL) else { return nil }\n\n        var sanitized = profile\n        if let currentURL = sanitized.currentURL, !WebAppURL.isSafe(currentURL) {\n            sanitized.currentURL = nil\n        }\n        return sanitized\n    }\n}\n''',
    '''}\n\nextension StoredWebAppState {\n    func sanitizedForUse() -> StoredWebAppState {\n        let sanitizedProfiles = profiles.compactMap { profile -> WebAppProfile? in\n            guard WebAppURL.isSafe(profile.homeURL) else { return nil }\n            var sanitized = profile\n            if let currentURL = sanitized.currentURL, !WebAppURL.isSafe(currentURL) {\n                sanitized.currentURL = nil\n            }\n            return sanitized\n        }\n\n        return StoredWebAppState(\n            version: StoredWebAppState.currentVersion,\n            profiles: sanitizedProfiles,\n            lastActiveTabID: lastActiveTabID\n        )\n    }\n}\n''',
)

# ---------------------------------------------------------------------------
# TabStore exposes explicit state snapshot/replace APIs; callers never mutate
# profile arrays directly during restore.
# ---------------------------------------------------------------------------
replace_once(
    "FloatTabs/Tabs/TabStore.swift",
    '''    private func touchLastUsed(id: UUID?, now: Date = Date()) {\n''',
    '''    func storedStateSnapshot() -> StoredWebAppState {\n        StoredWebAppState(\n            version: StoredWebAppState.currentVersion,\n            profiles: orderedProfiles,\n            lastActiveTabID: activeTabID\n        )\n    }\n\n    @discardableResult\n    func replaceStoredState(_ state: StoredWebAppState) -> Bool {\n        guard state.version == StoredWebAppState.currentVersion else { return false }\n\n        let sanitized = state.sanitizedForUse()\n        let normalized = Self.normalizedProfiles(sanitized.profiles)\n        let restoredActiveID: UUID?\n        if let requested = sanitized.lastActiveTabID,\n           normalized.contains(where: { $0.id == requested }) {\n            restoredActiveID = requested\n        } else {\n            restoredActiveID = normalized.first?.id\n        }\n\n        let replacement = StoredWebAppState(\n            version: StoredWebAppState.currentVersion,\n            profiles: normalized,\n            lastActiveTabID: restoredActiveID\n        )\n\n        do {\n            try repository.save(replacement)\n        } catch {\n            return false\n        }\n\n        profiles = normalized\n        activeTabID = restoredActiveID\n        onChange?()\n        return true\n    }\n\n    private func touchLastUsed(id: UUID?, now: Date = Date()) {\n''',
)

# ---------------------------------------------------------------------------
# Lifecycle reset invalidates every old async plan before imported Slot IDs are
# installed. This prevents stale timers/media callbacks from touching restored
# runtime state.
# ---------------------------------------------------------------------------
replace_once(
    "FloatTabs/Web/SlotLifecycleCoordinator.swift",
    '''    func handleMemoryPressure(_ level: SlotMemoryPressureLevel) {\n''',
    '''    func reset(slotIDs: Set<UUID>) {\n        hiddenActiveToken = nil\n        activeSlotID = nil\n        inactivePlans.removeAll()\n        mediaProtectedSlotIDs.removeAll()\n        inactiveWarmRecency.removeAll()\n        warmRecencyCounter = 0\n        for slotID in slotIDs {\n            container.removeSlot(slotID)\n        }\n    }\n\n    func handleMemoryPressure(_ level: SlotMemoryPressureLevel) {\n''',
)

# ---------------------------------------------------------------------------
# PanelController uses AppPreferencesStore as the global preference owner and
# owns live-runtime teardown around TabStore replacement.
# ---------------------------------------------------------------------------
p = Path("FloatTabs/Panel/PanelController.swift")
text = p.read_text(encoding="utf-8")
text = text.replace('    private static let followPreferredSizeKey = "FloatTabs.followTabPreferredSize"\n\n', '', 1)
text = text.replace('    private var followPreferredSize: Bool\n', '    private let preferencesStore: AppPreferencesStore\n', 1)
old = '''        webViewPool: WebViewPool,\n        frameStore: PanelFrameStore = PanelFrameStore()\n    ) {\n        self.tabStore = tabStore\n        self.webViewPool = webViewPool\n        self.frameStore = frameStore\n        restoredFrame = frameStore.loadFrame()\n        if UserDefaults.standard.object(forKey: Self.followPreferredSizeKey) == nil {\n            followPreferredSize = true\n        } else {\n            followPreferredSize = UserDefaults.standard.bool(forKey: Self.followPreferredSizeKey)\n        }\n'''
new = '''        webViewPool: WebViewPool,\n        frameStore: PanelFrameStore = PanelFrameStore(),\n        preferencesStore: AppPreferencesStore = AppPreferencesStore()\n    ) {\n        self.tabStore = tabStore\n        self.webViewPool = webViewPool\n        self.frameStore = frameStore\n        self.preferencesStore = preferencesStore\n        restoredFrame = frameStore.loadFrame()\n'''
if text.count(old) != 1:
    raise RuntimeError("PanelController initializer block not found exactly once")
text = text.replace(old, new, 1)
text = text.replace('followPreferredSize', 'preferencesStore.followPreferredSize')
# The broad replacement above intentionally applies to argument values/comments,
# but must not create a double preference-store path.
text = text.replace('preferencesStore.preferencesStore.followPreferredSize', 'preferencesStore.followPreferredSize')
marker = '''    func prepareForTermination() {\n        persistPanelFrame()\n    }\n'''
insert = '''    func prepareForTermination() {\n        persistPanelFrame()\n    }\n\n    func storedWebAppStateSnapshot() -> StoredWebAppState {\n        tabStore.storedStateSnapshot()\n    }\n\n    @discardableResult\n    func restoreStoredWebAppState(_ state: StoredWebAppState) -> Bool {\n        let existingIDs = Set(tabStore.profiles.map(\\.id))\n        slotLifecycleCoordinator.reset(slotIDs: existingIDs)\n        for slotID in existingIDs {\n            webViewPool.release(slotID: slotID)\n        }\n        lastSynchronizedActiveID = nil\n        lastSynchronizedActiveProfile = nil\n\n        guard tabStore.replaceStoredState(state) else {\n            synchronizeSlotState()\n            return false\n        }\n        return true\n    }\n'''
if text.count(marker) != 1:
    raise RuntimeError("PanelController termination marker missing")
text = text.replace(marker, insert, 1)
p.write_text(text, encoding="utf-8")

# ---------------------------------------------------------------------------
# AppCoordinator composes backup data from authoritative owners, creates local
# per-version snapshots, and applies restores only after backup validation.
# ---------------------------------------------------------------------------
write(
    "FloatTabs/App/AppCoordinator.swift",
    '''import AppKit
import KeyboardShortcuts

@MainActor
final class AppCoordinator {
    private let panelController: PanelController
    private var statusItemController: StatusItemController?
    private var globalHotkeyController: GlobalHotkeyController?
    private var appCommandController: AppCommandController?
    private let preferencesStore: AppPreferencesStore
    private let backupService: FloatTabsBackupService
    private var globalSettingsController: GlobalSettingsController?
#if DEBUG
    private var benchmarkControlServer: BenchmarkControlServer?
#endif

    init(
        panelController: PanelController? = nil,
        preferencesStore: AppPreferencesStore = AppPreferencesStore(),
        backupService: FloatTabsBackupService = FloatTabsBackupService()
    ) {
        self.preferencesStore = preferencesStore
        self.backupService = backupService

        if let panelController {
            self.panelController = panelController
        } else {
            let tabStore = TabStore(repository: ProfileRepository())
            let webViewPool = WebViewPool(
                onURLChange: { slotID, url in
                    tabStore.updateCurrentURL(id: slotID, url: url)
                },
                isSlotActive: { slotID in
                    tabStore.activeTabID == slotID
                }
            )
            self.panelController = PanelController(
                tabStore: tabStore,
                webViewPool: webViewPool,
                preferencesStore: preferencesStore
            )
        }
    }

    func start() {
        preferencesStore.applyStoredAppearance()
        globalSettingsController = GlobalSettingsController(
            preferencesStore: preferencesStore,
            onExportBackup: { [weak self] url in
                guard let self else { throw FloatTabsBackupError.restoreFailed }
                try self.exportBackup(to: url)
            },
            onRestoreBackup: { [weak self] url in
                guard let self else { throw FloatTabsBackupError.restoreFailed }
                return try self.restoreBackup(from: url)
            }
        )
        panelController.onOpenGlobalSettings = { [weak self] in
            self?.showGlobalSettings()
        }

        statusItemController = StatusItemController(
            onToggle: { [weak self] in self?.toggleFloatTabs() },
            isVisible: { [weak self] in self?.panelController.isVisible ?? false },
            onSettings: { [weak self] in self?.showGlobalSettings() },
            onQuit: { NSApp.terminate(nil) }
        )
        statusItemController?.setActiveWebApp(
            name: panelController.selectedSlotName,
            homeURL: panelController.selectedSlotHomeURL
        )
        panelController.onSelectedSlotPresentationChange = { [weak self] name, homeURL in
            self?.statusItemController?.setActiveWebApp(name: name, homeURL: homeURL)
        }

        globalHotkeyController = GlobalHotkeyController(
            onToggle: { [weak self] in self?.toggleFloatTabs() }
        )

        appCommandController = AppCommandController(
            isEnabled: { [weak self] in
                NSApp.isActive && (self?.panelController.isVisible ?? false)
            },
            onCommand: { [weak self] command in
                guard let self else { return }
                if command == .settings {
                    self.showGlobalSettings()
                } else {
                    self.panelController.handle(command)
                }
            }
        )

        // Keep one local snapshot per app version/build. It is overwritten by
        // the same version on clean starts/exits, while older-version snapshots
        // remain available when a newer app build is installed.
        try? backupService.writeAutomaticVersionSnapshot(makeBackupDocument())

#if DEBUG
        let benchmarkControlServer = BenchmarkControlServer { [weak self] request in
            self?.handleBenchmarkControl(request) ?? ["ok": false, "error": "coordinator_unavailable"]
        }
        self.benchmarkControlServer = benchmarkControlServer
        try? benchmarkControlServer.start()
#endif
    }

    func prepareForTermination() {
#if DEBUG
        benchmarkControlServer?.stop()
#endif
        panelController.prepareForTermination()
        try? backupService.writeAutomaticVersionSnapshot(makeBackupDocument())
    }

#if DEBUG
    private func handleBenchmarkControl(_ request: [String: Any]) -> [String: Any] {
        guard let action = request["action"] as? String else {
            return ["ok": false, "error": "missing_action"]
        }

        switch action {
        case "status", "ping":
            return ["ok": true, "status": panelController.benchmarkControlSnapshot()]

        case "configure":
            guard let slotIDs = request["slot_ids"] as? [String] else {
                return ["ok": false, "error": "missing_slot_ids"]
            }
            let succeeded = panelController.benchmarkSetResourcePolicy(
                slotIDStrings: slotIDs,
                residencyRawValue: request["residency"] as? String,
                backgroundMediaRawValue: request["background_media"] as? String
            )
            return succeeded
                ? ["ok": true, "status": panelController.benchmarkControlSnapshot()]
                : ["ok": false, "error": "configure_failed"]

        case "activate":
            guard let slotID = request["slot_id"] as? String,
                  panelController.benchmarkSelect(slotIDString: slotID) else {
                return ["ok": false, "error": "activate_failed"]
            }
            return ["ok": true, "status": panelController.benchmarkControlSnapshot()]

        case "show":
            if !panelController.isVisible {
                panelController.showFloatTabs()
            }
            return ["ok": true, "status": panelController.benchmarkControlSnapshot()]

        case "hide":
            if panelController.isVisible {
                panelController.hideFloatTabs()
            }
            return ["ok": true, "status": panelController.benchmarkControlSnapshot()]

        default:
            return ["ok": false, "error": "unknown_action"]
        }
    }
#endif

    private func makeBackupDocument(now: Date = Date()) -> FloatTabsBackupDocument {
        let shortcut = KeyboardShortcuts.getShortcut(for: .toggleFloatTabs)
        let shortcutBackup = shortcut.map {
            FloatTabsBackupShortcut(
                carbonKeyCode: $0.carbonKeyCode,
                carbonModifiers: $0.carbonModifiers
            )
        }
        let appVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "unknown"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "unknown"

        return FloatTabsBackupDocument(
            schemaVersion: FloatTabsBackupDocument.currentSchemaVersion,
            createdAt: now,
            sourceAppVersion: appVersion,
            sourceBuild: build,
            webAppState: panelController.storedWebAppStateSnapshot(),
            globalPreferences: FloatTabsBackupPreferences(
                appearanceMode: preferencesStore.appearanceMode,
                followPreferredSize: preferencesStore.followPreferredSize
            ),
            globalShowHideShortcut: shortcutBackup
        )
    }

    private func exportBackup(to url: URL) throws {
        try backupService.write(makeBackupDocument(), to: url)
    }

    private func restoreBackup(from url: URL) throws -> URL {
        let imported = try backupService.load(from: url)
        let rollbackURL = try backupService.writeRollback(makeBackupDocument())

        guard panelController.restoreStoredWebAppState(imported.webAppState) else {
            throw FloatTabsBackupError.restoreFailed
        }

        preferencesStore.followPreferredSize = imported.globalPreferences.followPreferredSize
        preferencesStore.appearanceMode = imported.globalPreferences.appearanceMode

        let shortcut = imported.globalShowHideShortcut.map {
            KeyboardShortcuts.Shortcut(
                carbonKeyCode: $0.carbonKeyCode,
                carbonModifiers: $0.carbonModifiers
            )
        }
        KeyboardShortcuts.setShortcut(shortcut, for: .toggleFloatTabs)
        return rollbackURL
    }

    private func showGlobalSettings() {
        globalSettingsController?.show()
    }

    private func toggleFloatTabs() {
        if panelController.isVisible {
            panelController.hideFloatTabs()
        } else {
            panelController.showFloatTabs()
        }
    }
}
''',
)

# ---------------------------------------------------------------------------
# Settings UI adds real local Backup & Restore actions under Account. Language
# stays informational and no cloud/login controls are fabricated.
# ---------------------------------------------------------------------------
write(
    "FloatTabs/UI/GlobalSettingsController.swift",
    '''import AppKit
import KeyboardShortcuts
import UniformTypeIdentifiers

@MainActor
final class GlobalSettingsController: NSObject, NSWindowDelegate {
    typealias ExportBackupHandler = (URL) throws -> Void
    typealias RestoreBackupHandler = (URL) throws -> URL

    private let preferencesStore: AppPreferencesStore
    private let onExportBackup: ExportBackupHandler
    private let onRestoreBackup: RestoreBackupHandler
    private lazy var settingsWindow: NSWindow = makeWindow()

    init(
        preferencesStore: AppPreferencesStore,
        onExportBackup: @escaping ExportBackupHandler = { _ in },
        onRestoreBackup: @escaping RestoreBackupHandler = { _ in throw FloatTabsBackupError.restoreFailed }
    ) {
        self.preferencesStore = preferencesStore
        self.onExportBackup = onExportBackup
        self.onRestoreBackup = onRestoreBackup
        super.init()
    }

    var isVisible: Bool { settingsWindow.isVisible }

    func show() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            _ = NSRunningApplication.current.activate(options: [])
        }
        settingsWindow.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = []
        tabs.canPropagateSelectedChildViewControllerTitle = false

        addTab(
            title: "Appearance",
            symbol: "circle.lefthalf.filled",
            controller: AppearanceSettingsViewController(preferencesStore: preferencesStore),
            to: tabs
        )
        addTab(
            title: "Shortcuts",
            symbol: "keyboard",
            controller: ShortcutsSettingsViewController(),
            to: tabs
        )
        addTab(
            title: "Account & Language",
            symbol: "person.crop.circle",
            controller: AccountLanguageSettingsViewController(
                onExportBackup: onExportBackup,
                onRestoreBackup: onRestoreBackup
            ),
            to: tabs
        )

        let window = NSWindow(contentViewController: tabs)
        window.title = "FloatTabs Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 580, height: 440))
        window.minSize = NSSize(width: 540, height: 400)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    private func addTab(
        title: String,
        symbol: String,
        controller: NSViewController,
        to tabs: NSTabViewController
    ) {
        let item = NSTabViewItem(viewController: controller)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        tabs.addTabViewItem(item)
    }
}

@MainActor
private final class AppearanceSettingsViewController: NSViewController {
    private let preferencesStore: AppPreferencesStore
    private let appearanceControl = NSSegmentedControl(
        labels: AppAppearanceMode.allCases.map(\\.displayName),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )

    init(preferencesStore: AppPreferencesStore) {
        self.preferencesStore = preferencesStore
        super.init(nibName: nil, bundle: nil)
        title = "Appearance"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()

        let titleLabel = Self.titleLabel("Interface Appearance")
        let detail = Self.detailLabel(
            "Changes FloatTabs' native appearance. FloatTabs injects no page CSS; websites may still respond to WebKit's effective light/dark appearance."
        )
        appearanceControl.segmentStyle = .rounded
        appearanceControl.target = self
        appearanceControl.action = #selector(appearanceChanged(_:))
        synchronizeControl()

        let stack = NSStackView(views: [titleLabel, detail, appearanceControl])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            appearanceControl.widthAnchor.constraint(equalToConstant: 250),
        ])
        view = root
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        synchronizeControl()
    }

    @objc private func appearanceChanged(_ sender: NSSegmentedControl) {
        guard AppAppearanceMode.allCases.indices.contains(sender.selectedSegment) else { return }
        preferencesStore.appearanceMode = AppAppearanceMode.allCases[sender.selectedSegment]
    }

    private func synchronizeControl() {
        appearanceControl.selectedSegment = AppAppearanceMode.allCases.firstIndex(
            of: preferencesStore.appearanceMode
        ) ?? 0
    }

    private static func titleLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private static func detailLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 0
        label.widthAnchor.constraint(lessThanOrEqualToConstant: 500).isActive = true
        return label
    }
}

@MainActor
private final class ShortcutsSettingsViewController: NSViewController {
    override func loadView() {
        let root = NSView()
        let heading = sectionTitle("Global Show / Hide")
        let detail = detailLabel(
            "This shortcut works from other apps. Changing it replaces the previous global binding immediately."
        )
        let recorder = KeyboardShortcuts.RecorderCocoa(for: .toggleFloatTabs)
        recorder.translatesAutoresizingMaskIntoConstraints = false

        let recorderRow = NSStackView(views: [label("Show / Hide FloatTabs"), recorder])
        recorderRow.orientation = .horizontal
        recorderRow.alignment = .centerY
        recorderRow.spacing = 12
        recorderRow.distribution = .fill

        let fixedHeading = sectionTitle("FloatTabs Shortcuts")
        let fixedDetail = detailLabel("Page shortcuts are fixed in V1; only global Show / Hide is configurable here.")
        let rows = [
            shortcutRow("Select Slot", "⌘1…⌘9"),
            shortcutRow("Next / Previous Slot", "⌃Tab / ⌃⇧Tab"),
            shortcutRow("Add Web App", "⌘T"),
            shortcutRow("Quick URL", "⌘L"),
            shortcutRow("Return Home", "⌘⇧H"),
            shortcutRow("Reload", "⌘R"),
            shortcutRow("Zoom", "⌘+ / ⌘- / ⌘0"),
            shortcutRow("Pin / Auto-hide", "⌘⇧P"),
            shortcutRow("Global Settings", "⌘,"),
        ]

        let stack = NSStackView(views: [heading, detail, recorderRow, spacer(8), fixedHeading, fixedDetail] + rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            recorder.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
        ])
        view = root
    }

    private func shortcutRow(_ action: String, _ shortcut: String) -> NSView {
        let actionLabel = label(action)
        actionLabel.widthAnchor.constraint(equalToConstant: 190).isActive = true
        let shortcutLabel = NSTextField(labelWithString: shortcut)
        shortcutLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        shortcutLabel.textColor = .secondaryLabelColor
        let row = NSStackView(views: [actionLabel, shortcutLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let value = label(text)
        value.font = .systemFont(ofSize: 13, weight: .semibold)
        return value
    }

    private func detailLabel(_ text: String) -> NSTextField {
        let value = NSTextField(wrappingLabelWithString: text)
        value.font = .systemFont(ofSize: 11.5)
        value.textColor = .secondaryLabelColor
        value.maximumNumberOfLines = 0
        value.widthAnchor.constraint(lessThanOrEqualToConstant: 500).isActive = true
        return value
    }

    private func label(_ text: String) -> NSTextField {
        let value = NSTextField(labelWithString: text)
        value.font = .systemFont(ofSize: 12)
        return value
    }

    private func spacer(_ height: CGFloat) -> NSView {
        let view = NSView()
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }
}

@MainActor
private final class AccountLanguageSettingsViewController: NSViewController {
    private let onExportBackup: GlobalSettingsController.ExportBackupHandler
    private let onRestoreBackup: GlobalSettingsController.RestoreBackupHandler

    init(
        onExportBackup: @escaping GlobalSettingsController.ExportBackupHandler,
        onRestoreBackup: @escaping GlobalSettingsController.RestoreBackupHandler
    ) {
        self.onExportBackup = onExportBackup
        self.onRestoreBackup = onRestoreBackup
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        let exportButton = NSButton(
            title: "Export Backup…",
            target: self,
            action: #selector(exportBackup)
        )
        let restoreButton = NSButton(
            title: "Restore Backup…",
            target: self,
            action: #selector(restoreBackup)
        )
        let actions = NSStackView(views: [exportButton, restoreButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 10

        let stack = NSStackView(views: [
            sectionTitle("Account"),
            detailLabel(
                "FloatTabs V1 is local-only. It does not require a FloatTabs cloud account or sync service."
            ),
            spacer(8),
            sectionTitle("Backup & Restore"),
            detailLabel(
                "Backups include Web App/Slot configuration, rendering and resource settings, global appearance, window-size switching preference, and the global Show/Hide shortcut."
            ),
            detailLabel(
                "Website passwords, cookies, OAuth/login sessions, WebKit caches, and page runtime state are not exported. A new Mac may require website sign-in again."
            ),
            actions,
            detailLabel(
                "FloatTabs also keeps a local automatic snapshot for each app version/build and creates a rollback backup before every manual restore."
            ),
            spacer(10),
            sectionTitle("Language"),
            detailLabel(
                "A per-app language override is not exposed in V1. No non-functional language selector is shown."
            ),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
        ])
        view = root
    }

    @objc private func exportBackup() {
        guard let window = view.window else { return }
        let panel = NSSavePanel()
        panel.title = "Export FloatTabs Backup"
        panel.nameFieldStringValue = FloatTabsBackupService.suggestedExportFileName()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [backupContentType]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                try self.onExportBackup(url)
                self.showMessage(
                    title: "Backup Exported",
                    detail: "Your FloatTabs configuration backup was saved successfully."
                )
            } catch {
                self.showError(error)
            }
        }
    }

    @objc private func restoreBackup() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.title = "Restore FloatTabs Backup"
        panel.allowedContentTypes = [backupContentType]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.confirmRestore(url: url)
        }
    }

    private var backupContentType: UTType {
        UTType(filenameExtension: FloatTabsBackupService.fileExtension) ?? .json
    }

    private func confirmRestore(url: URL) {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Replace current FloatTabs configuration?"
        alert.informativeText = "FloatTabs will create a local rollback backup first, then replace current Slot and global settings with the selected backup. Website login/session data is not changed or restored."
        alert.addButton(withTitle: "Restore and Replace")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            do {
                let rollbackURL = try self.onRestoreBackup(url)
                self.showMessage(
                    title: "Backup Restored",
                    detail: "FloatTabs configuration was restored. A rollback backup was saved at:\n\\(rollbackURL.path)"
                )
            } catch {
                self.showError(error)
            }
        }
    }

    private func showMessage(title: String, detail: String) {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }

    private func showError(_ error: Error) {
        showMessage(title: "Backup Operation Failed", detail: error.localizedDescription)
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

    private func spacer(_ height: CGFloat) -> NSView {
        let view = NSView()
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }
}
''',
)

# ---------------------------------------------------------------------------
# Tests: preferences + backup format + explicit TabStore replace semantics.
# ---------------------------------------------------------------------------
replace_once(
    "FloatTabsTests/AppPreferencesStoreTests.swift",
    '''    func testUnknownAppearanceFallsBackToSystem() {\n        defaults.set("future-value", forKey: AppPreferencesStore.appearanceKey)\n        XCTAssertEqual(AppPreferencesStore(defaults: defaults).appearanceMode, .system)\n    }\n}\n''',
    '''    func testUnknownAppearanceFallsBackToSystem() {\n        defaults.set("future-value", forKey: AppPreferencesStore.appearanceKey)\n        XCTAssertEqual(AppPreferencesStore(defaults: defaults).appearanceMode, .system)\n    }\n\n    func testFollowPreferredSizeDefaultsTrueAndPersists() {\n        let first = AppPreferencesStore(defaults: defaults)\n        XCTAssertTrue(first.followPreferredSize)\n\n        first.followPreferredSize = false\n        XCTAssertFalse(AppPreferencesStore(defaults: defaults).followPreferredSize)\n\n        first.followPreferredSize = true\n        XCTAssertTrue(AppPreferencesStore(defaults: defaults).followPreferredSize)\n    }\n}\n''',
)

write(
    "FloatTabsTests/FloatTabsBackupServiceTests.swift",
    '''import Foundation
import XCTest
@testable import FloatTabs

final class FloatTabsBackupServiceTests: XCTestCase {
    func testBackupDocumentRoundTripsAllFloatTabsOwnedConfiguration() throws {
        let profile = WebAppProfile(
            order: 3,
            name: "Docs",
            homeURL: URL(string: "https://example.com")!,
            currentURL: URL(string: "https://example.com/current")!,
            renderingProfile: WebRenderingProfile.canonicalDefault
                .settingWebsiteMode(.mobile)
                .settingBrowserIdentity(.windowsChrome)
                .settingViewport(CGSize(width: 612, height: 777))
                .settingZoom(1.5),
            residencyPolicy: .hot,
            backgroundMediaPolicy: .allowBackgroundAudio,
            createdAt: Date(timeIntervalSince1970: 100),
            lastUsedAt: Date(timeIntervalSince1970: 200)
        )
        let document = FloatTabsBackupDocument(
            schemaVersion: FloatTabsBackupDocument.currentSchemaVersion,
            createdAt: Date(timeIntervalSince1970: 300),
            sourceAppVersion: "0.1.0",
            sourceBuild: "1",
            webAppState: StoredWebAppState(
                version: StoredWebAppState.currentVersion,
                profiles: [profile],
                lastActiveTabID: profile.id
            ),
            globalPreferences: FloatTabsBackupPreferences(
                appearanceMode: .dark,
                followPreferredSize: false
            ),
            globalShowHideShortcut: FloatTabsBackupShortcut(
                carbonKeyCode: 50,
                carbonModifiers: 256
            )
        )
        let service = FloatTabsBackupService()

        let decoded = try service.decode(service.encode(document))

        XCTAssertEqual(decoded, document)
        XCTAssertEqual(decoded.webAppState.profiles.first?.renderingProfile.zoom, 1.5)
        XCTAssertEqual(decoded.webAppState.profiles.first?.residencyPolicy, .hot)
        XCTAssertEqual(decoded.webAppState.profiles.first?.backgroundMediaPolicy, .allowBackgroundAudio)
        XCTAssertEqual(decoded.globalPreferences.appearanceMode, .dark)
        XCTAssertFalse(decoded.globalPreferences.followPreferredSize)
        XCTAssertEqual(decoded.globalShowHideShortcut?.carbonKeyCode, 50)
    }

    func testUnsupportedBackupSchemaIsRejected() throws {
        let document = FloatTabsBackupDocument(
            schemaVersion: 99,
            createdAt: Date(),
            sourceAppVersion: "0.1.0",
            sourceBuild: "1",
            webAppState: .empty,
            globalPreferences: FloatTabsBackupPreferences(
                appearanceMode: .system,
                followPreferredSize: true
            ),
            globalShowHideShortcut: nil
        )
        let service = FloatTabsBackupService()
        let data = try service.encode(document)

        XCTAssertThrowsError(try service.decode(data)) { error in
            XCTAssertEqual(error as? FloatTabsBackupError, .unsupportedSchema(99))
        }
    }

    func testRollbackAndAutomaticVersionSnapshotsUseSeparateLocalFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsBackupServiceTests-\\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = FloatTabsBackupService(backupDirectoryURL: directory)
        let document = FloatTabsBackupDocument(
            schemaVersion: FloatTabsBackupDocument.currentSchemaVersion,
            createdAt: Date(timeIntervalSince1970: 100),
            sourceAppVersion: "0.1.0",
            sourceBuild: "1",
            webAppState: .empty,
            globalPreferences: FloatTabsBackupPreferences(
                appearanceMode: .system,
                followPreferredSize: true
            ),
            globalShowHideShortcut: nil
        )

        let automatic = try service.writeAutomaticVersionSnapshot(document)
        let rollback = try service.writeRollback(
            document,
            now: Date(timeIntervalSince1970: 200)
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: automatic.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rollback.path))
        XCTAssertTrue(automatic.lastPathComponent.hasPrefix("FloatTabs-auto-0.1.0-1"))
        XCTAssertTrue(rollback.lastPathComponent.hasPrefix("FloatTabs-before-restore-"))
        XCTAssertEqual(try service.load(from: automatic), document)
    }
}
''',
)

replace_once(
    "FloatTabsTests/TabStoreTests.swift",
    '''    private func makeProfile(order: Int, name: String, url: URL) -> WebAppProfile {\n''',
    '''    func testStoredStateSnapshotAndReplaceSanitizeImportedState() {\n        let repository = MemoryProfileRepository()\n        let store = TabStore(repository: repository)\n        let original = store.add(name: "Original", homeURL: urlA)!\n        XCTAssertEqual(store.storedStateSnapshot().lastActiveTabID, original.id)\n\n        var safe = WebAppProfile(\n            order: 9,\n            name: "Safe",\n            homeURL: urlB,\n            currentURL: URL(string: "file:///tmp/not-safe")!\n        )\n        safe.currentURL = URL(string: "file:///tmp/not-safe")\n        let invalidHome = WebAppProfile(\n            order: 0,\n            name: "Invalid",\n            homeURL: URL(string: "file:///tmp/invalid")!\n        )\n        let imported = StoredWebAppState(\n            version: StoredWebAppState.currentVersion,\n            profiles: [safe, invalidHome],\n            lastActiveTabID: UUID()\n        )\n\n        XCTAssertTrue(store.replaceStoredState(imported))\n        XCTAssertEqual(store.orderedProfiles.map(\\.id), [safe.id])\n        XCTAssertEqual(store.orderedProfiles.map(\\.order), [0])\n        XCTAssertNil(store.orderedProfiles.first?.currentURL)\n        XCTAssertEqual(store.activeTabID, safe.id)\n        XCTAssertEqual(repository.state.lastActiveTabID, safe.id)\n    }\n\n    func testReplaceStoredStateRejectsUnsupportedVersionWithoutMutation() {\n        let repository = MemoryProfileRepository()\n        let store = TabStore(repository: repository)\n        let original = store.add(name: "Original", homeURL: urlA)!\n        let before = store.storedStateSnapshot()\n        let unsupported = StoredWebAppState(\n            version: StoredWebAppState.currentVersion + 1,\n            profiles: [],\n            lastActiveTabID: nil\n        )\n\n        XCTAssertFalse(store.replaceStoredState(unsupported))\n        XCTAssertEqual(store.storedStateSnapshot(), before)\n        XCTAssertEqual(store.activeTabID, original.id)\n    }\n\n    private func makeProfile(order: Int, name: String, url: URL) -> WebAppProfile {\n''',
)

# ---------------------------------------------------------------------------
# Xcode project membership for backup service/tests.
# ---------------------------------------------------------------------------
replace_once(
    "FloatTabs.xcodeproj/project.pbxproj",
    '\t\tA00000000000000000000025 /* AppPreferencesStoreTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = B00000000000000000000025 /* AppPreferencesStoreTests.swift */; };\n',
    '\t\tA00000000000000000000025 /* AppPreferencesStoreTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = B00000000000000000000025 /* AppPreferencesStoreTests.swift */; };\n\t\tA00000000000000000000026 /* FloatTabsBackupService.swift in Sources */ = {isa = PBXBuildFile; fileRef = B00000000000000000000026 /* FloatTabsBackupService.swift */; };\n\t\tA00000000000000000000027 /* FloatTabsBackupServiceTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = B00000000000000000000027 /* FloatTabsBackupServiceTests.swift */; };\n',
)
replace_once(
    "FloatTabs.xcodeproj/project.pbxproj",
    '\t\tB00000000000000000000025 /* AppPreferencesStoreTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AppPreferencesStoreTests.swift; sourceTree = "<group>"; };\n',
    '\t\tB00000000000000000000025 /* AppPreferencesStoreTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AppPreferencesStoreTests.swift; sourceTree = "<group>"; };\n\t\tB00000000000000000000026 /* FloatTabsBackupService.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = FloatTabsBackupService.swift; sourceTree = "<group>"; };\n\t\tB00000000000000000000027 /* FloatTabsBackupServiceTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = FloatTabsBackupServiceTests.swift; sourceTree = "<group>"; };\n',
)
replace_once(
    "FloatTabs.xcodeproj/project.pbxproj",
    '\t\t\t\tB00000000000000000000023 /* AppPreferencesStore.swift */,\n',
    '\t\t\t\tB00000000000000000000023 /* AppPreferencesStore.swift */,\n\t\t\t\tB00000000000000000000026 /* FloatTabsBackupService.swift */,\n',
)
replace_once(
    "FloatTabs.xcodeproj/project.pbxproj",
    '\t\t\t\tB00000000000000000000025 /* AppPreferencesStoreTests.swift */,\n',
    '\t\t\t\tB00000000000000000000025 /* AppPreferencesStoreTests.swift */,\n\t\t\t\tB00000000000000000000027 /* FloatTabsBackupServiceTests.swift */,\n',
)
replace_once(
    "FloatTabs.xcodeproj/project.pbxproj",
    '\t\t\t\tA00000000000000000000024 /* GlobalSettingsController.swift in Sources */,\n',
    '\t\t\t\tA00000000000000000000024 /* GlobalSettingsController.swift in Sources */,\n\t\t\t\tA00000000000000000000026 /* FloatTabsBackupService.swift in Sources */,\n',
)
replace_once(
    "FloatTabs.xcodeproj/project.pbxproj",
    '\t\t\t\tA00000000000000000000025 /* AppPreferencesStoreTests.swift in Sources */,\n',
    '\t\t\t\tA00000000000000000000025 /* AppPreferencesStoreTests.swift in Sources */,\n\t\t\t\tA00000000000000000000027 /* FloatTabsBackupServiceTests.swift in Sources */,\n',
)

# ---------------------------------------------------------------------------
# Release build is now a permanent CI gate.
# ---------------------------------------------------------------------------
replace_once(
    ".github/workflows/macos-ci.yml",
    '''      - name: Unit tests\n''',
    '''      - name: Release build\n        run: >-\n          xcodebuild\n          -project FloatTabs.xcodeproj\n          -scheme FloatTabs\n          -configuration Release\n          -destination 'platform=macOS,arch=arm64'\n          -derivedDataPath \"$RUNNER_TEMP/FloatTabsReleaseDerivedData\"\n          CODE_SIGNING_ALLOWED=NO\n          build\n\n      - name: Unit tests\n''',
)
# Run permanent CI when release tooling changes too.
replace_once(
    ".github/workflows/macos-ci.yml",
    "      - '.github/workflows/macos-ci.yml'\n  pull_request:\n",
    "      - '.github/workflows/macos-ci.yml'\n      - 'tools/release/**'\n  pull_request:\n",
)
replace_once(
    ".github/workflows/macos-ci.yml",
    "      - '.github/workflows/macos-ci.yml'\n  workflow_dispatch:\n",
    "      - '.github/workflows/macos-ci.yml'\n      - 'tools/release/**'\n  workflow_dispatch:\n",
)

# ---------------------------------------------------------------------------
# Repeatable local/CI DMG builder. Developer ID/notary support is optional and
# credential-driven; default is an unsigned QA artifact.
# ---------------------------------------------------------------------------
write(
    "tools/release/build_dmg.sh",
    '''#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

OUTPUT_DIR="${FLOATTABS_OUTPUT_DIR:-$ROOT_DIR/.release}"
DERIVED_DATA="$OUTPUT_DIR/DerivedData"
STAGE_DIR="$OUTPUT_DIR/dmg-root"
APP_PATH="$DERIVED_DATA/Build/Products/Release/FloatTabs.app"
SIGN_IDENTITY="${FLOATTABS_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${FLOATTABS_NOTARY_PROFILE:-}"

rm -rf "$DERIVED_DATA" "$STAGE_DIR"
mkdir -p "$OUTPUT_DIR" "$STAGE_DIR"

xcodebuild \
  -project FloatTabs.xcodeproj \
  -scheme FloatTabs \
  -resolvePackageDependencies \
  -onlyUsePackageVersionsFromResolvedFile

xcodebuild \
  -project FloatTabs.xcodeproj \
  -scheme FloatTabs \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: Release app not found at $APP_PATH" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
DMG_PATH="$OUTPUT_DIR/FloatTabs-$VERSION.dmg"

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "Signing FloatTabs.app with Developer ID identity: $SIGN_IDENTITY"
  codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --sign "$SIGN_IDENTITY" \
    "$APP_PATH"
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
else
  echo "Building unsigned QA app (no FLOATTABS_SIGN_IDENTITY supplied)."
fi

/usr/bin/ditto "$APP_PATH" "$STAGE_DIR/FloatTabs.app"
ln -s /Applications "$STAGE_DIR/Applications"
rm -f "$DMG_PATH"

hdiutil create \
  -volname "FloatTabs $VERSION" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

hdiutil verify "$DMG_PATH"

if [[ -n "$NOTARY_PROFILE" ]]; then
  if [[ -z "$SIGN_IDENTITY" ]]; then
    echo "error: FLOATTABS_NOTARY_PROFILE requires FLOATTABS_SIGN_IDENTITY." >&2
    exit 1
  fi
  echo "Submitting DMG for notarization with keychain profile: $NOTARY_PROFILE"
  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  echo "Signed/notarized DMG ready: $DMG_PATH"
else
  echo "QA DMG ready: $DMG_PATH"
  echo "Version: $VERSION ($BUILD)"
  echo "NOTE: This is not a public notarized release unless Developer ID + notary credentials were supplied."
fi
''',
)

write(
    ".github/workflows/qa-dmg.yml",
    '''name: QA DMG

on:
  workflow_dispatch:
  pull_request:
    branches:
      - main
    paths:
      - 'FloatTabs/**'
      - 'FloatTabs.xcodeproj/**'
      - 'tools/release/**'
      - '.github/workflows/qa-dmg.yml'

jobs:
  build-dmg:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v5

      - name: Build and verify QA DMG
        env:
          FLOATTABS_OUTPUT_DIR: ${{ runner.temp }}/FloatTabsRelease
        run: |
          chmod +x tools/release/build_dmg.sh
          tools/release/build_dmg.sh

      - name: Upload QA DMG
        uses: actions/upload-artifact@v4
        with:
          name: FloatTabs-0.1.0-QA-DMG
          if-no-files-found: error
          path: ${{ runner.temp }}/FloatTabsRelease/FloatTabs-*.dmg
''',
)

# Distribution outputs should never enter Git.
replace_once(
    ".gitignore",
    '''# Distribution\ndist/\n*.dmg\n''',
    '''# Distribution\ndist/\n.release/\n*.dmg\n''',
)

# README status/release reality should no longer claim Stage 4 is current.
replace_once(
    "README.md",
    '''Stage 4 Web Compatibility, Navigation, Sessions & OAuth: IN PROGRESS\n→ current Stage 4 slice: 4B popup / OAuth / external-link routing\n''',
    '''Stage 4 Web Compatibility, Navigation, Sessions & OAuth: PASSED\nStage 5 Resource Lifecycle & Interaction Refinement: PASSED\nStage 6 Menus, Commands & Global Settings: PASSED\nv0.1.0 Release Candidate: IN PROGRESS\n''',
)
replace_once(
    "README.md",
    '''Release architecture includes Developer ID signing, Hardened Runtime, Apple notarization, ticket stapling, and Gatekeeper validation.\n''',
    '''Release architecture includes Developer ID signing, Hardened Runtime, Apple notarization, ticket stapling, and Gatekeeper validation. `tools/release/build_dmg.sh` also supports an unsigned QA-DMG mode for developer-machine acceptance before public signing credentials are configured.\n\nFloatTabs configuration is stored outside the app bundle and survives normal app replacement. v0.1.0 RC1 adds explicit `.floattabsbackup` export/restore plus local per-version configuration snapshots. Website passwords/cookies/login sessions are intentionally not exported.\n''',
)

# RC1 contract gains automatic per-version snapshot semantics.
replace_once(
    "docs/release/FloatTabs_v0.1.0_RC1.md",
    '''## 7. Automatic rollback backup\n\nBefore every successful manual restore, write the current configuration to:\n\n```text\n~/Library/Application Support/FloatTabs/Backups/\nFloatTabs-before-restore-<timestamp>.floattabsbackup\n```\n\nKeep rollback backups local. RC1 does not implement background cloud sync.\n''',
    '''## 7. Local automatic safety backups\n\nBefore every successful manual restore, write the current configuration to:\n\n```text\n~/Library/Application Support/FloatTabs/Backups/\nFloatTabs-before-restore-<timestamp>-<id>.floattabsbackup\n```\n\nIn addition, on app start and clean termination, update one local configuration snapshot for the current app version/build:\n\n```text\nFloatTabs-auto-<version>-<build>.floattabsbackup\n```\n\nA newer build uses a different filename, so the previous version's latest snapshot remains available during upgrades. These are local configuration backups only; RC1 does not implement background cloud sync or website credential/session migration.\n''',
)

# Sanity checks before runner build.
for obsolete in [
    'private static let followPreferredSizeKey',
    'private var followPreferredSize: Bool',
]:
    if obsolete in Path('FloatTabs/Panel/PanelController.swift').read_text(encoding='utf-8'):
        raise RuntimeError(f'obsolete PanelController preference ownership remains: {obsolete}')
