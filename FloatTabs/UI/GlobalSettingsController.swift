import AppKit
import KeyboardShortcuts

enum BrowserProfileManagementError: LocalizedError, Equatable {
    case notFound
    case referenced
    case lastRemainingProfile
    case invalidName
    case duplicateName
    case runtimeStillResident
    case metadataPersistenceFailed

    var errorDescription: String? {
        switch self {
        case .notFound:
            return L10n.tr(
                "That Browser Profile no longer exists.",
                "该浏览器配置文件已不存在。"
            )
        case .referenced:
            return L10n.tr(
                "This Profile is used by one or more Web Apps.",
                "此配置文件正在被一个或多个网页应用使用。"
            )
        case .lastRemainingProfile:
            return L10n.tr(
                "At least one Browser Profile must remain.",
                "至少需要保留一个浏览器配置文件。"
            )
        case .invalidName:
            return L10n.tr(
                "Enter a non-empty Profile name.",
                "请输入非空的配置文件名称。"
            )
        case .duplicateName:
            return L10n.tr(
                "That Profile name is already in use.",
                "该配置文件名称已被占用。"
            )
        case .runtimeStillResident:
            return L10n.tr(
                "The Profile is still in use by a live runtime. Try again.",
                "该配置文件仍有运行中的页面，请稍后再试。"
            )
        case .metadataPersistenceFailed:
            return L10n.tr(
                "FloatTabs could not save the Profile metadata. Your previous settings were kept.",
                "FloatTabs 无法保存配置文件信息，原有设置已保留。"
            )
        }
    }
}

struct BrowserProfileManagementSnapshot: Equatable {
    let customProfiles: [BrowserProfile]
    let defaultProfilePresentation: DefaultBrowserProfilePresentation
    let includesDefaultProfile: Bool
    let referencedProfileIDs: Set<UUID>
    let isDefaultProfileReferenced: Bool
    let referencingWebAppNamesByProfileID: [UUID: [String]]
    let defaultReferencingWebAppNames: [String]

    var totalProfileCount: Int {
        (includesDefaultProfile ? 1 : 0) + customProfiles.count
    }

    init(
        customProfiles: [BrowserProfile],
        defaultProfilePresentation: DefaultBrowserProfilePresentation = .default,
        includesDefaultProfile: Bool = true,
        referencedProfileIDs: Set<UUID>,
        isDefaultProfileReferenced: Bool = false,
        referencingWebAppNamesByProfileID: [UUID: [String]] = [:],
        defaultReferencingWebAppNames: [String] = []
    ) {
        self.customProfiles = customProfiles
        self.defaultProfilePresentation = defaultProfilePresentation
        self.includesDefaultProfile = includesDefaultProfile
        self.referencedProfileIDs = referencedProfileIDs
        self.isDefaultProfileReferenced = isDefaultProfileReferenced
        self.referencingWebAppNamesByProfileID = referencingWebAppNamesByProfileID
        self.defaultReferencingWebAppNames = defaultReferencingWebAppNames
    }
}

@MainActor
struct BrowserProfileManagementClient {
    typealias SnapshotHandler = () -> BrowserProfileManagementSnapshot
    typealias CreateHandler = (String) throws -> BrowserProfile
    typealias RenameHandler = (UUID?, String) throws -> Void
    typealias DeleteHandler = (UUID?) async throws -> Void

    private let snapshotHandler: SnapshotHandler
    private let createHandler: CreateHandler
    private let renameHandler: RenameHandler
    private let deleteHandler: DeleteHandler

    init(
        snapshot: @escaping SnapshotHandler,
        create: @escaping CreateHandler,
        rename: @escaping RenameHandler,
        delete: @escaping DeleteHandler
    ) {
        snapshotHandler = snapshot
        createHandler = create
        renameHandler = rename
        deleteHandler = delete
    }

    static let unavailable = BrowserProfileManagementClient(
        snapshot: {
            BrowserProfileManagementSnapshot(
                customProfiles: [],
                referencedProfileIDs: []
            )
        },
        create: { _ in throw BrowserProfileManagementError.notFound },
        rename: { _, _ in throw BrowserProfileManagementError.notFound },
        delete: { _ in throw BrowserProfileManagementError.notFound }
    )

    func snapshot() -> BrowserProfileManagementSnapshot {
        snapshotHandler()
    }

    @discardableResult
    func create(name: String) throws -> BrowserProfile {
        try createHandler(name)
    }

    func rename(id: UUID?, name: String) throws {
        try renameHandler(id, name)
    }

    func delete(id: UUID?) async throws {
        try await deleteHandler(id)
    }
}

@MainActor
final class GlobalSettingsController: NSObject, NSWindowDelegate {
    typealias ExportBackupHandler = (URL) throws -> Void
    typealias RestoreBackupHandler = (URL) throws -> URL

    private let preferencesStore: AppPreferencesStore
    private let attentionSoundAssetStore: AttentionSoundAssetStore
    private let attentionSoundPlayer: AttentionSoundPlaying
    private let onExportBackup: ExportBackupHandler
    private let onRestoreBackup: RestoreBackupHandler
    private let browserProfileManager: BrowserProfileManagementClient
    private let websiteCacheManager: WebsiteCacheManagementClient
    private let bookmarkManager: BookmarkManagementClient
    private let onExportDiagnostics: RuntimeDiagnosticsExportHandler
    private let onOpenDiagnosticsLogs: () -> Void
    private let onCaptureDiagnosticsIncident: RuntimeDiagnosticsIncidentCaptureHandler?
    private let onProvideDiagnosticsLiveStatus: RuntimeDiagnosticsLiveStatusProvider?
    private let onLoadRecentDiagnosticsEvents: RuntimeDiagnosticsRecentEventsLoader?
    private var bookmarksController: BookmarksSettingsViewController?
    private var hasCreatedSettingsWindow = false
    private var languageObserver: NSObjectProtocol?
    private lazy var settingsWindow: NSWindow = makeWindow()

    init(
        preferencesStore: AppPreferencesStore,
        attentionSoundAssetStore: AttentionSoundAssetStore = AttentionSoundAssetStore(),
        attentionSoundPlayer: AttentionSoundPlaying = AttentionSoundPlayer(),
        onExportBackup: @escaping ExportBackupHandler = { _ in },
        onRestoreBackup: @escaping RestoreBackupHandler = { _ in throw FloatTabsBackupError.restoreFailed },
        browserProfileManager: BrowserProfileManagementClient = .unavailable,
        websiteCacheManager: WebsiteCacheManagementClient = .unavailable,
        bookmarkManager: BookmarkManagementClient = .unavailable,
        onExportDiagnostics: @escaping RuntimeDiagnosticsExportHandler = { _, completion in
            completion(.failure(.writerDisabled))
        },
        onOpenDiagnosticsLogs: @escaping () -> Void = {},
        onCaptureDiagnosticsIncident: RuntimeDiagnosticsIncidentCaptureHandler? = nil,
        onProvideDiagnosticsLiveStatus: RuntimeDiagnosticsLiveStatusProvider? = nil,
        onLoadRecentDiagnosticsEvents: RuntimeDiagnosticsRecentEventsLoader? = nil
    ) {
        self.preferencesStore = preferencesStore
        self.attentionSoundAssetStore = attentionSoundAssetStore
        self.attentionSoundPlayer = attentionSoundPlayer
        self.onExportBackup = onExportBackup
        self.onRestoreBackup = onRestoreBackup
        self.browserProfileManager = browserProfileManager
        self.websiteCacheManager = websiteCacheManager
        self.bookmarkManager = bookmarkManager
        self.onExportDiagnostics = onExportDiagnostics
        self.onOpenDiagnosticsLogs = onOpenDiagnosticsLogs
        self.onCaptureDiagnosticsIncident = onCaptureDiagnosticsIncident
        self.onProvideDiagnosticsLiveStatus = onProvideDiagnosticsLiveStatus
        self.onLoadRecentDiagnosticsEvents = onLoadRecentDiagnosticsEvents
        super.init()
        languageObserver = NotificationCenter.default.addObserver(
            forName: .floatTabsLanguageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.rebuildForLanguageChange()
            }
        }
    }

    deinit {
        if let languageObserver {
            NotificationCenter.default.removeObserver(languageObserver)
        }
    }

    var isVisible: Bool { settingsWindow.isVisible }

    var windowTitleForTesting: String {
        settingsWindow.title
    }

    var toolbarTabTitlesForTesting: [String] {
        (settingsWindow.contentViewController as? NSTabViewController)?.tabViewItems.map(\.label) ?? []
    }

    var selectedTabIndexForTesting: Int {
        (settingsWindow.contentViewController as? NSTabViewController)?.selectedTabViewItemIndex ?? -1
    }

    func show(selecting page: GlobalSettingsPage? = nil) {
        if let page,
           let tabs = settingsWindow.contentViewController as? NSTabViewController,
           let index = GlobalSettingsPage.allCases.firstIndex(of: page),
           tabs.tabViewItems.indices.contains(index) {
            tabs.selectedTabViewItemIndex = index
        }
        bookmarksController?.reloadData()
        // Settings is also opened from the accessory app's status menu, so it
        // needs the same explicit user-presentation activation semantics as the
        // primary FloatTabs window group.
        settingsWindow.orderFrontRegardless()
        NSApp.activate()
        settingsWindow.makeKeyAndOrderFront(nil)
    }

    func refreshBookmarksIfLoaded() {
        bookmarksController?.reloadData()
    }

    private func rebuildForLanguageChange() {
        guard hasCreatedSettingsWindow else { return }
        let selectedIndex = (settingsWindow.contentViewController as? NSTabViewController)?.selectedTabViewItemIndex ?? 0
        let existingFrame = settingsWindow.frame
        bookmarksController = nil
        let rebuiltTabs = makeTabsController()
        if rebuiltTabs.tabViewItems.indices.contains(selectedIndex) {
            rebuiltTabs.selectedTabViewItemIndex = selectedIndex
        }
        settingsWindow.title = L10n.tr("FloatTabs Settings", "FloatTabs 设置")
        settingsWindow.contentViewController = rebuiltTabs
        settingsWindow.setFrame(existingFrame, display: true)
        if isVisible {
            bookmarksController?.reloadData()
        }
    }

    private func makeTabsController() -> NSTabViewController {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = []
        tabs.canPropagateSelectedChildViewControllerTitle = false

        for page in GlobalSettingsPage.allCases {
            addTab(
                title: page.title,
                symbol: page.symbol,
                controller: makeSettingsPage(for: page),
                to: tabs
            )
        }
        return tabs
    }

    private func makeWindow() -> NSWindow {
        hasCreatedSettingsWindow = true
        let tabs = makeTabsController()

        let window = NSWindow(contentViewController: tabs)
        window.title = L10n.tr("FloatTabs Settings", "FloatTabs 设置")
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 620, height: 640))
        window.minSize = NSSize(width: 580, height: 500)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    func makeSettingsPage(for page: GlobalSettingsPage) -> NSViewController {
        let children: [NSViewController]
        switch page {
        case .general:
            children = [
                AppearanceSettingsViewController(preferencesStore: preferencesStore),
            ]
        case .bookmarks:
            let controller = BookmarksSettingsViewController(
                client: bookmarkManager,
                embedsInSettingsPage: true
            )
            bookmarksController = controller
            children = [controller]
        case .profilesStorage:
            children = [
                BrowserProfilesSettingsViewController(
                    browserProfileManager: browserProfileManager,
                    embedsInSettingsPage: true
                ),
                PerformanceSettingsViewController(
                    preferencesStore: preferencesStore,
                    websiteCacheManager: websiteCacheManager,
                    embedsInSettingsPage: true
                ),
            ]
        case .alerts:
            children = [
                UnreadTabAttentionSettingsViewController(preferencesStore: preferencesStore),
                NotificationsSettingsViewController(
                    preferencesStore: preferencesStore,
                    attentionSoundPlayer: attentionSoundPlayer,
                    assetStore: attentionSoundAssetStore
                ),
            ]
        case .shortcuts:
            children = [
                ShortcutsSettingsViewController(
                    preferencesStore: preferencesStore,
                    embedsInSettingsPage: true
                )
            ]
        case .advanced:
            children = [
                RuntimeDiagnosticsSettingsViewController(
                    preferencesStore: preferencesStore,
                    exportHandler: onExportDiagnostics,
                    openLogsHandler: onOpenDiagnosticsLogs,
                    captureIncidentHandler: onCaptureDiagnosticsIncident,
                    liveStatusProvider: onProvideDiagnosticsLiveStatus,
                    recentEventsLoader: onLoadRecentDiagnosticsEvents
                ),
                BackupRestoreSettingsViewController(
                    onExportBackup: onExportBackup,
                    onRestoreBackup: onRestoreBackup
                ),
                AboutSettingsViewController(),
            ]
        }
        return SettingsPageViewController(childViewControllers: children)
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
final class AttentionStyleChoiceButton: NSButton {
    let style: TabAttentionStyle
    let previewSurfaceView: AttentionStyleSurfaceView
    let previewDotView = ClassicUnreadDotView()
    private let previewIconView = NSImageView()
    private let previewTitleLabel = NSTextField(labelWithString: "ChatGPT")
    private let styleNameLabel: NSTextField
    private let selectionMarkView = NSImageView()
    private(set) var isSelectedStyle = false
    private(set) var palette: TabAttentionPalette

    var showsClassicUnreadDot: Bool { !previewDotView.isHidden }

    init(style: TabAttentionStyle, palette: TabAttentionPalette = .red) {
        self.style = style
        self.palette = palette
        styleNameLabel = NSTextField(labelWithString: style.displayName)
        previewSurfaceView = AttentionStyleSurfaceView(
            frame: .zero,
            style: style,
            palette: palette,
            showsAttention: true,
            geometry: .settingsPreview
        )
        super.init(frame: .zero)

        setButtonType(.toggle)
        title = ""
        isBordered = false
        imagePosition = .noImage
        focusRingType = .default
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.62).cgColor
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(
            L10n.tr(
                "\(style.displayName) unread Tab attention style",
                "\(style.displayName) 未读标签提醒样式"
            )
        )

        previewSurfaceView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(previewSurfaceView)

        previewIconView.translatesAutoresizingMaskIntoConstraints = false
        previewIconView.image = NSImage(
            systemSymbolName: "bubble.left.and.bubble.right.fill",
            accessibilityDescription: "ChatGPT"
        )
        previewIconView.contentTintColor = style.configuration(for: palette).foregroundColor
        addSubview(previewIconView)
        previewDotView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(previewDotView, positioned: .above, relativeTo: previewIconView)

        previewTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        previewTitleLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        previewTitleLabel.textColor = style.configuration(for: palette).foregroundColor
        addSubview(previewTitleLabel)

        styleNameLabel.translatesAutoresizingMaskIntoConstraints = false
        styleNameLabel.font = .systemFont(ofSize: 11, weight: .medium)
        styleNameLabel.textColor = .labelColor
        addSubview(styleNameLabel)

        selectionMarkView.translatesAutoresizingMaskIntoConstraints = false
        selectionMarkView.image = NSImage(
            systemSymbolName: "checkmark.circle.fill",
            accessibilityDescription: L10n.tr("Selected", "已选")
        )
        selectionMarkView.contentTintColor = .controlAccentColor
        selectionMarkView.isHidden = true
        addSubview(selectionMarkView)

        NSLayoutConstraint.activate([
            previewSurfaceView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            previewSurfaceView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            previewSurfaceView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            previewSurfaceView.heightAnchor.constraint(equalToConstant: 38),

            previewIconView.leadingAnchor.constraint(
                equalTo: previewSurfaceView.leadingAnchor,
                constant: 10
            ),
            previewIconView.centerYAnchor.constraint(equalTo: previewSurfaceView.centerYAnchor),
            previewIconView.widthAnchor.constraint(equalToConstant: 13),
            previewIconView.heightAnchor.constraint(equalToConstant: 13),
            previewDotView.centerXAnchor.constraint(equalTo: previewIconView.trailingAnchor, constant: -1),
            previewDotView.centerYAnchor.constraint(equalTo: previewIconView.topAnchor, constant: 1),
            previewDotView.widthAnchor.constraint(equalToConstant: ClassicUnreadDotView.diameter),
            previewDotView.heightAnchor.constraint(equalToConstant: ClassicUnreadDotView.diameter),
            previewTitleLabel.leadingAnchor.constraint(
                equalTo: previewIconView.trailingAnchor,
                constant: 5
            ),
            previewTitleLabel.centerYAnchor.constraint(equalTo: previewSurfaceView.centerYAnchor),
            previewTitleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: previewSurfaceView.trailingAnchor,
                constant: -8
            ),

            styleNameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            styleNameLabel.topAnchor.constraint(
                equalTo: previewSurfaceView.bottomAnchor,
                constant: 4
            ),
            styleNameLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            selectionMarkView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
            selectionMarkView.widthAnchor.constraint(equalToConstant: 13),
            selectionMarkView.heightAnchor.constraint(equalToConstant: 13),
            selectionMarkView.centerYAnchor.constraint(equalTo: styleNameLabel.centerYAnchor),
            selectionMarkView.leadingAnchor.constraint(
                greaterThanOrEqualTo: styleNameLabel.trailingAnchor,
                constant: 6
            ),
        ])

        setSelectedStyle(false)
        updateDotVisibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.62).cgColor
            previewIconView.contentTintColor = style.configuration(for: palette).foregroundColor
            previewTitleLabel.textColor = style.configuration(for: palette).foregroundColor
            selectionMarkView.contentTintColor = .controlAccentColor
            setSelectedStyle(isSelectedStyle)
        }
    }

    func setSelectedStyle(_ selected: Bool) {
        isSelectedStyle = selected
        state = selected ? .on : .off
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = selected
                ? NSColor.controlAccentColor.cgColor
                : NSColor.separatorColor.withAlphaComponent(0.55).cgColor
            layer?.borderWidth = selected ? 2 : 1
        }
        selectionMarkView.isHidden = !selected
        setAccessibilityValue(
            selected ? L10n.tr("Selected", "已选") : L10n.tr("Not selected", "未选")
        )
    }

    func setPalette(_ palette: TabAttentionPalette) {
        guard self.palette != palette else { return }
        self.palette = palette
        previewSurfaceView.configure(style: style, palette: palette, showsAttention: true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            previewIconView.contentTintColor = style.configuration(for: palette).foregroundColor
            previewTitleLabel.textColor = style.configuration(for: palette).foregroundColor
        }
        updateDotVisibility()
    }

    private func updateDotVisibility() {
        previewDotView.isHidden = style != .dot
    }
}

@MainActor
final class AttentionPaletteChoiceButton: NSButton {
    let palette: TabAttentionPalette
    private let swatchView = NSView()
    private let paletteNameLabel: NSTextField
    private(set) var isSelectedPalette = false

    init(palette: TabAttentionPalette) {
        self.palette = palette
        paletteNameLabel = NSTextField(labelWithString: palette.displayName)
        super.init(frame: .zero)
        setButtonType(.toggle)
        title = ""
        isBordered = false
        imagePosition = .noImage
        focusRingType = .default
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.55).cgColor
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(
            L10n.tr(
                "\(palette.displayName) unread Tab attention palette",
                "\(palette.displayName) 未读标签配色"
            )
        )

        swatchView.wantsLayer = true
        swatchView.layer?.cornerRadius = 6
        swatchView.layer?.masksToBounds = true
        let gradient = CAGradientLayer()
        gradient.frame = CGRect(x: 0, y: 0, width: 12, height: 12)
        gradient.colors = palette.colors.map(\.cgColor)
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        swatchView.layer?.addSublayer(gradient)
        swatchView.layer?.borderWidth = 1
        swatchView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        swatchView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(swatchView)
        paletteNameLabel.font = .systemFont(ofSize: 11, weight: .medium)
        paletteNameLabel.textColor = .labelColor
        paletteNameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(paletteNameLabel)
        NSLayoutConstraint.activate([
            swatchView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            swatchView.centerYAnchor.constraint(equalTo: centerYAnchor),
            swatchView.widthAnchor.constraint(equalToConstant: 12),
            swatchView.heightAnchor.constraint(equalToConstant: 12),
            paletteNameLabel.leadingAnchor.constraint(equalTo: swatchView.trailingAnchor, constant: 6),
            paletteNameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            paletteNameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
        ])
        setSelectedPalette(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSelectedPalette(_ selected: Bool) {
        isSelectedPalette = selected
        state = selected ? .on : .off
        layer?.borderWidth = selected ? 2 : 1
        layer?.borderColor = selected
            ? NSColor.controlAccentColor.cgColor
            : NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        setAccessibilityValue(
            selected ? L10n.tr("Selected", "已选") : L10n.tr("Not selected", "未选")
        )
    }
}

@MainActor
final class NotificationsSettingsViewController: NSViewController {
    private let preferencesStore: AppPreferencesStore
    private let assetStore: AttentionSoundAssetStore
    private let attentionSoundPlayer: AttentionSoundPlaying
    private let availableSoundNames: [String]
    private let errorPresenter: (Error) -> Void

    private let enabledSwitch = NSSwitch()
    let soundPopup = NSPopUpButton()
    let importAudioButton = NSButton(title: L10n.tr("Import Audio…", "导入音频…"), target: nil, action: nil)
    let removeSelectedAudioButton = NSButton(title: L10n.tr("Remove Selected", "移除所选"), target: nil, action: nil)
    let volumeSlider = NSSlider(value: 100, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let volumeValueLabel = NSTextField(labelWithString: "100%")
    let previewButton = NSButton(title: L10n.tr("Play Preview", "试听"), target: nil, action: nil)

    init(
        preferencesStore: AppPreferencesStore,
        attentionSoundPlayer: AttentionSoundPlaying,
        availableSoundNames: [String]? = nil,
        assetStore: AttentionSoundAssetStore = AttentionSoundAssetStore(),
        errorPresenter: @escaping (Error) -> Void = { error in
            NSAlert(error: error).runModal()
        }
    ) {
        self.preferencesStore = preferencesStore
        self.assetStore = assetStore
        self.attentionSoundPlayer = attentionSoundPlayer
        self.availableSoundNames = availableSoundNames ?? AttentionSound.availableNames()
        self.errorPresenter = errorPresenter
        super.init(nibName: nil, bundle: nil)
        title = L10n.tr("Notifications", "通知")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()

        enabledSwitch.target = self
        enabledSwitch.action = #selector(enabledChanged(_:))

        soundPopup.widthAnchor.constraint(equalToConstant: 300).isActive = true
        soundPopup.target = self
        soundPopup.action = #selector(soundChanged(_:))

        volumeSlider.target = self
        volumeSlider.action = #selector(volumeChanged(_:))
        // Non-continuous on purpose: the action fires once when the user
        // finishes a drag (or taps a position) instead of per-pixel, so the
        // automatic preview below plays exactly once per completed adjustment.
        volumeSlider.isContinuous = false
        volumeSlider.numberOfTickMarks = 11
        volumeSlider.allowsTickMarkValuesOnly = false
        volumeSlider.widthAnchor.constraint(equalToConstant: 280).isActive = true

        volumeValueLabel.alignment = .right
        volumeValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        volumeValueLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true

        previewButton.target = self
        previewButton.action = #selector(playPreview(_:))
        previewButton.bezelStyle = .rounded

        importAudioButton.target = self
        importAudioButton.action = #selector(importAudio(_:))
        removeSelectedAudioButton.target = self
        removeSelectedAudioButton.action = #selector(removeSelectedAudio(_:))

        let enabledRow = makeRow(
            label: L10n.tr("Play sound when ChatGPT is ready", "ChatGPT 回复完成时播放提示音"),
            control: enabledSwitch
        )
        let soundRow = makeRow(
            label: L10n.tr("Ready Sound", "完成提示音"),
            control: soundPopup
        )
        let audioActions = NSStackView(views: [importAudioButton, removeSelectedAudioButton])
        audioActions.orientation = .horizontal
        audioActions.alignment = .centerY
        audioActions.spacing = 8
        let volumeControls = NSStackView(views: [volumeSlider, volumeValueLabel])
        volumeControls.orientation = .horizontal
        volumeControls.alignment = .centerY
        volumeControls.spacing = 10
        let volumeRow = makeRow(label: L10n.tr("Volume", "音量"), control: volumeControls)

        let stack = NSStackView(views: [
            Self.titleLabel(L10n.tr("Ready Alerts", "完成提示音")),
            Self.detailLabel(L10n.tr("Play a sound when ChatGPT is ready.", "在 ChatGPT 回复完成时播放声音提示。")),
            Self.spacer(8),
            enabledRow,
            soundRow,
            audioActions,
            volumeRow,
            Self.spacer(4),
            previewButton,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24),
        ])

        view = root
        synchronizeControls()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        synchronizeControls()
    }

    @objc private func enabledChanged(_ sender: NSSwitch) {
        preferencesStore.attentionSoundEnabled = sender.state == .on
    }

    @objc private func soundChanged(_ sender: NSPopUpButton) {
        guard let selection = sender.selectedItem?.representedObject as? String else { return }
        if selection == Self.importMenuSelection {
            importAudio()
            synchronizeControls()
            return
        }
        if let name = selection.systemSoundName {
            preferencesStore.attentionSoundSourceKind = .system
            preferencesStore.attentionSoundName = name
            synchronizeControls()
            previewCurrentSound()
            return
        }
        guard let id = UUID(uuidString: selection.customAssetID),
              preferencesStore.customAttentionSoundAsset(id: id) != nil else {
            synchronizeControls()
            return
        }
        preferencesStore.attentionSoundSourceKind = .custom
        preferencesStore.selectedCustomAttentionSoundID = id
        synchronizeControls()
        previewCurrentSound()
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        preferencesStore.attentionSoundVolume = sender.doubleValue / 100
        updateVolumeLabel(sender.doubleValue)
        previewCurrentSound()
    }

    @objc private func playPreview(_ sender: NSButton) {
        previewCurrentSound()
    }

    @objc private func importAudio(_ sender: NSButton) {
        importAudio()
    }

    @objc private func removeSelectedAudio(_ sender: NSButton) {
        guard let id = selectedCustomAssetID else { return }
        removeCustomAudioAsset(id: id)
    }

    /// Removes one library asset without touching a different active custom
    /// asset. The popup normally targets the active item, while this method
    /// also gives tests and future library affordances a safe non-active path.
    func removeCustomAudioAsset(id: UUID) {
        guard let asset = preferencesStore.customAttentionSoundAsset(id: id) else {
            synchronizeControls()
            return
        }
        do {
            try assetStore.remove(asset)
        } catch {
            errorPresenter(error)
            return
        }
        _ = preferencesStore.removeCustomAttentionSoundAsset(id: id)
        if preferencesStore.selectedCustomAttentionSoundID == id {
            preferencesStore.selectedCustomAttentionSoundID = nil
            preferencesStore.attentionSoundSourceKind = .system
        }
        synchronizeControls()
    }

    /// Testable import seam used by the panel action and UI-level tests. An
    /// import only appends assets; it never changes the active sound.
    func importCustomAudio(from sourceURLs: [URL]) {
        let result = assetStore.importAudio(from: sourceURLs)
        preferencesStore.appendCustomAttentionSoundAssets(result.assets)
        if !result.failures.isEmpty {
            errorPresenter(AttentionSoundBatchImportError(failures: result.failures))
        }
        synchronizeControls()
    }

    func importCustomAudio(from sourceURL: URL) {
        importCustomAudio(from: [sourceURL])
    }

    /// The single preview path shared by the sound popup, the volume slider,
    /// and the Play Preview button. It always previews the persisted UI
    /// values through the production player, so a zero volume stays a valid
    /// silent configuration and it works even while the automatic Ready
    /// alert switch is off — that switch only gates the real Ready event.
    private func previewCurrentSound() {
        attentionSoundPlayer.play(
            source: AppCoordinator.attentionSoundPlaybackSource(
                preferencesStore: preferencesStore,
                assetStore: assetStore
            ),
            volume: preferencesStore.attentionSoundVolume
        )
    }

    private func importAudio() {
        let panel = NSOpenPanel()
        panel.title = L10n.tr("Import Ready Audio", "导入提示音频")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio]

        let importSelection: (NSApplication.ModalResponse) -> Void = { [weak self, weak panel] response in
            guard let self, response == .OK, let urls = panel?.urls, !urls.isEmpty else {
                self?.synchronizeControls()
                return
            }
            self.importCustomAudio(from: urls)
        }
        if let window = view.window {
            panel.beginSheetModal(for: window, completionHandler: importSelection)
        } else {
            importSelection(panel.runModal())
        }
    }

    private func synchronizeControls() {
        guard isViewLoaded else { return }
        enabledSwitch.state = preferencesStore.attentionSoundEnabled ? .on : .off
        configureSoundPopup()
        if let selection = currentMenuSelection,
           let index = soundPopup.itemArray.firstIndex(where: {
               ($0.representedObject as? String) == selection
           }) {
            soundPopup.selectItem(at: index)
        } else if let firstSystemIndex = soundPopup.itemArray.firstIndex(where: {
            ($0.representedObject as? String)?.systemSoundName != nil
        }) {
            soundPopup.selectItem(at: firstSystemIndex)
        }
        removeSelectedAudioButton.isEnabled = selectedCustomAssetID != nil
        previewButton.isEnabled = true

        let volumePercent = preferencesStore.attentionSoundVolume * 100
        volumeSlider.doubleValue = volumePercent
        updateVolumeLabel(volumePercent)
    }

    private func configureSoundPopup() {
        soundPopup.removeAllItems()

        soundPopup.addItem(withTitle: L10n.tr("System", "系统音效"))
        soundPopup.lastItem?.isEnabled = false
        for name in availableSoundNames {
            soundPopup.addItem(withTitle: name)
            soundPopup.lastItem?.representedObject = Self.systemSelection(name)
        }

        soundPopup.menu?.addItem(NSMenuItem.separator())
        soundPopup.addItem(withTitle: L10n.tr("Custom", "自定义音效"))
        soundPopup.lastItem?.isEnabled = false
        for asset in preferencesStore.customAttentionSoundLibrary {
            let isMissing = assetStore.existingURL(for: asset) == nil
            let title = asset.displayName + (isMissing ? L10n.tr(" — Missing", " — 文件缺失") : "")
            soundPopup.addItem(withTitle: title)
            soundPopup.lastItem?.representedObject = Self.customSelection(asset.id)
        }

        soundPopup.menu?.addItem(NSMenuItem.separator())
        soundPopup.addItem(withTitle: L10n.tr("Import Audio…", "导入音频…"))
        soundPopup.lastItem?.representedObject = Self.importMenuSelection
    }

    private var currentMenuSelection: String? {
        if preferencesStore.attentionSoundSourceKind == .custom {
            if let selectedID = preferencesStore.selectedCustomAttentionSoundID,
               preferencesStore.customAttentionSoundAsset(id: selectedID) != nil {
                return Self.customSelection(selectedID)
            }
            return Self.systemSelection(AppPreferencesStore.defaultAttentionSoundName)
        }
        return Self.systemSelection(preferencesStore.attentionSoundName)
    }

    private var selectedCustomAssetID: UUID? {
        guard let selection = soundPopup.selectedItem?.representedObject as? String else {
            return nil
        }
        return UUID(uuidString: selection.customAssetID)
    }

    private static let importMenuSelection = "import"

    private static func systemSelection(_ name: String) -> String {
        "system:\(name)"
    }

    private static func customSelection(_ id: UUID) -> String {
        "custom:\(id.uuidString)"
    }

    private func makeRow(label text: String, control: NSView) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.widthAnchor.constraint(equalToConstant: 230).isActive = true

        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        return row
    }

    private func updateVolumeLabel(_ value: Double) {
        volumeValueLabel.stringValue = "\(Int(value.rounded()))%"
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
        label.widthAnchor.constraint(lessThanOrEqualToConstant: 540).isActive = true
        return label
    }

    private static func spacer(_ height: CGFloat) -> NSView {
        let view = NSView()
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }
}

@MainActor
final class UnreadTabAttentionSettingsViewController: NSViewController {
    private let preferencesStore: AppPreferencesStore
    private(set) var attentionStyleChoices: [AttentionStyleChoiceButton] = []
    private(set) var attentionPaletteChoices: [AttentionPaletteChoiceButton] = []
    private let attentionPaletteDescriptionLabel = NSTextField(labelWithString: "")

    init(preferencesStore: AppPreferencesStore) {
        self.preferencesStore = preferencesStore
        super.init(nibName: nil, bundle: nil)
        title = L10n.tr("Unread Tab Attention", "未读标签提醒")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        attentionPaletteDescriptionLabel.font = .systemFont(ofSize: 11)
        attentionPaletteDescriptionLabel.textColor = .secondaryLabelColor

        let styleGrid = makeAttentionStyleGrid()
        let paletteGrid = makeAttentionPaletteGrid()
        let stack = NSStackView(views: [
            Self.titleLabel(L10n.tr("Unread Tab Attention", "未读标签提醒")),
            Self.detailLabel(
                L10n.tr(
                    "Choose an effect style. Previews respect Reduce Motion.",
                    "选择标签提醒动效样式，预览将遵循系统的“减弱动态效果”设置。"
                )
            ),
            styleGrid,
            Self.titleLabel(L10n.tr("Palette", "配色方案")),
            attentionPaletteDescriptionLabel,
            paletteGrid,
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
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24),
            styleGrid.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -56),
        ])

        view = root
        synchronizeAttentionStyleChoices()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        synchronizeAttentionStyleChoices()
    }

    @objc private func attentionStyleChanged(_ sender: AttentionStyleChoiceButton) {
        preferencesStore.attentionStyle = sender.style
        synchronizeAttentionStyleChoices()
    }

    @objc private func attentionPaletteChanged(_ sender: AttentionPaletteChoiceButton) {
        preferencesStore.attentionPalette = sender.palette
        synchronizeAttentionStyleChoices()
    }

    private func makeAttentionStyleGrid() -> NSView {
        attentionStyleChoices = TabAttentionStyle.allCases.map { style in
            let choice = AttentionStyleChoiceButton(
                style: style,
                palette: preferencesStore.attentionPalette
            )
            choice.target = self
            choice.action = #selector(attentionStyleChanged(_:))
            choice.heightAnchor.constraint(equalToConstant: 83).isActive = true
            return choice
        }
        let rows = stride(from: 0, to: attentionStyleChoices.count, by: 2).map { start in
            let row = NSStackView(
                views: Array(attentionStyleChoices[start..<min(start + 2, attentionStyleChoices.count)])
            )
            row.orientation = .horizontal
            row.alignment = .centerY
            row.distribution = .fillEqually
            row.spacing = 10
            return row
        }
        let grid = NSStackView(views: rows)
        grid.orientation = .vertical
        grid.alignment = .leading
        grid.spacing = 8
        rows.forEach { $0.widthAnchor.constraint(equalTo: grid.widthAnchor).isActive = true }
        return grid
    }

    private func synchronizeAttentionStyleChoices() {
        let selectedStyle = preferencesStore.attentionStyle
        let selectedPalette = preferencesStore.attentionPalette
        let displayedPalette = selectedStyle == .dot ? .red : selectedPalette
        attentionStyleChoices.forEach { choice in
            choice.setPalette(selectedPalette)
            choice.setSelectedStyle(choice.style == selectedStyle)
        }
        attentionPaletteChoices.forEach { choice in
            choice.isEnabled = selectedStyle != .dot || choice.palette == .red
            choice.setSelectedPalette(choice.palette == displayedPalette)
        }
        attentionPaletteDescriptionLabel.stringValue = selectedStyle == .dot
            ? L10n.tr(
                "Dot always uses the classic red indicator.",
                "圆点样式固定使用经典红色指示点。"
            )
            : L10n.tr(
                "Palette changes color while keeping the selected style.",
                "配色方案会改变当前动效样式的色彩。"
            )
    }

    private func makeAttentionPaletteGrid() -> NSView {
        attentionPaletteChoices = TabAttentionPalette.allCases.map { palette in
            let choice = AttentionPaletteChoiceButton(palette: palette)
            choice.target = self
            choice.action = #selector(attentionPaletteChanged(_:))
            choice.widthAnchor.constraint(equalToConstant: 104).isActive = true
            choice.heightAnchor.constraint(equalToConstant: 34).isActive = true
            return choice
        }
        let rows = stride(from: 0, to: attentionPaletteChoices.count, by: 3).map { start in
            let row = NSStackView(
                views: Array(attentionPaletteChoices[start..<min(start + 3, attentionPaletteChoices.count)])
            )
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            return row
        }
        let grid = NSStackView(views: rows)
        grid.orientation = .vertical
        grid.alignment = .leading
        grid.spacing = 6
        return grid
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
        label.widthAnchor.constraint(lessThanOrEqualToConstant: 540).isActive = true
        return label
    }
}

private extension String {
    var systemSoundName: String? {
        hasPrefix("system:") ? String(dropFirst("system:".count)) : nil
    }

    var customAssetID: String {
        hasPrefix("custom:") ? String(dropFirst("custom:".count)) : ""
    }
}

@MainActor
private final class AppearanceSettingsViewController: NSViewController {
    private let preferencesStore: AppPreferencesStore
    private let languageControl = NSSegmentedControl(
        labels: AppLanguage.allCases.map(\.displayName),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let appearanceControl = NSSegmentedControl(
        labels: AppAppearanceMode.allCases.map(\.displayName),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let menuBarDisplayControl = NSSegmentedControl(
        labels: MenuBarDisplayMode.allCases.map(\.displayName),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let windowSizeControl = NSSegmentedControl(
        labels: PanelWindowSizeMode.allCases.map(\.displayName),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let fixedSizeControl = NSSegmentedControl(
        labels: SimpleViewportPreset.selectableCases.map(\.displayName),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let customFixedWidthField = NSTextField()
    private let customFixedHeightField = NSTextField()
    private let fixedSizeSection = NSStackView()
    private let customFixedSizeRow = NSStackView()
    private var borderThemeButtons: [BorderThemeSwatchButton] = []

    init(preferencesStore: AppPreferencesStore) {
        self.preferencesStore = preferencesStore
        super.init(nibName: nil, bundle: nil)
        title = L10n.tr("Appearance", "外观")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()

        languageControl.segmentStyle = .rounded
        languageControl.target = self
        languageControl.action = #selector(languageChanged(_:))
        languageControl.widthAnchor.constraint(equalToConstant: 290).isActive = true

        appearanceControl.segmentStyle = .rounded
        appearanceControl.target = self
        appearanceControl.action = #selector(appearanceChanged(_:))
        appearanceControl.widthAnchor.constraint(equalToConstant: 250).isActive = true

        menuBarDisplayControl.segmentStyle = .rounded
        menuBarDisplayControl.target = self
        menuBarDisplayControl.action = #selector(menuBarDisplayModeChanged(_:))
        menuBarDisplayControl.widthAnchor.constraint(equalToConstant: 250).isActive = true

        let borderPalette = makeBorderPalette()

        windowSizeControl.segmentStyle = .rounded
        windowSizeControl.target = self
        windowSizeControl.action = #selector(windowSizeModeChanged(_:))
        windowSizeControl.widthAnchor.constraint(equalToConstant: 280).isActive = true

        fixedSizeControl.segmentStyle = .rounded
        fixedSizeControl.target = self
        fixedSizeControl.action = #selector(fixedSizePresetChanged(_:))
        fixedSizeControl.widthAnchor.constraint(equalToConstant: 455).isActive = true

        configureCustomFixedField(customFixedWidthField)
        configureCustomFixedField(customFixedHeightField)
        let multiplication = NSTextField(labelWithString: "×")
        multiplication.textColor = .secondaryLabelColor
        customFixedSizeRow.setViews(
            [
                Self.detailInlineLabel(L10n.tr("Width % × Height %", "宽度 % × 高度 %")),
                customFixedWidthField,
                multiplication,
                customFixedHeightField,
            ],
            in: .leading
        )
        customFixedSizeRow.orientation = .horizontal
        customFixedSizeRow.alignment = .centerY
        customFixedSizeRow.spacing = 8

        fixedSizeSection.setViews([
            Self.titleLabel(L10n.tr("Fixed Window Size", "固定窗口尺寸")),
            Self.detailLabel(
                L10n.tr(
                    "Shared size used by every Tab in Fixed mode.",
                    "固定尺寸模式下所有标签页共用的窗口大小。"
                )
            ),
            fixedSizeControl,
            customFixedSizeRow,
        ], in: .leading)
        fixedSizeSection.orientation = .vertical
        fixedSizeSection.alignment = .leading
        fixedSizeSection.spacing = 7

        let stack = NSStackView(views: [
            Self.titleLabel(L10n.tr("Language / 语言", "语言 / Language")),
            Self.detailLabel(
                L10n.tr(
                    "Choose FloatTabs' interface language.",
                    "切换 FloatTabs 的界面显示语言，即时生效。"
                )
            ),
            languageControl,
            Self.spacer(6),
            Self.titleLabel(L10n.tr("Interface Appearance", "界面外观")),
            Self.detailLabel(L10n.tr("Choose FloatTabs' appearance.", "选择 FloatTabs 的深浅色外观。")),
            appearanceControl,
            Self.spacer(6),
            Self.titleLabel(L10n.tr("Menu Bar", "菜单栏图标")),
            Self.detailLabel(
                L10n.tr(
                    "Show the current Web App name in the menu bar.",
                    "是否在顶部菜单栏显示当前网页应用名称。"
                )
            ),
            menuBarDisplayControl,
            Self.spacer(6),
            Self.titleLabel(L10n.tr("Border Theme", "边框主题")),
            Self.detailLabel(
                L10n.tr(
                    "Choose a border style or custom color.",
                    "选择悬浮窗默认边框样式或自定义颜色。"
                )
            ),
            borderPalette,
            Self.spacer(6),
            Self.titleLabel(L10n.tr("Window Size Behavior", "窗口尺寸策略")),
            Self.detailLabel(
                L10n.tr(
                    "Use each Web App's size or one shared size.",
                    "为每个网页应用记忆独立尺寸，或全局统一固定尺寸。"
                )
            ),
            windowSizeControl,
            fixedSizeSection,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -22),
        ])
        synchronizeControls()
        view = root
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        synchronizeControls()
    }

    @objc private func languageChanged(_ sender: NSSegmentedControl) {
        guard AppLanguage.allCases.indices.contains(sender.selectedSegment) else { return }
        let selected = AppLanguage.allCases[sender.selectedSegment]
        preferencesStore.appLanguage = selected
        AppLocalization.apply(selected)
    }

    @objc private func appearanceChanged(_ sender: NSSegmentedControl) {
        guard AppAppearanceMode.allCases.indices.contains(sender.selectedSegment) else { return }
        preferencesStore.appearanceMode = AppAppearanceMode.allCases[sender.selectedSegment]
    }

    @objc private func menuBarDisplayModeChanged(_ sender: NSSegmentedControl) {
        guard MenuBarDisplayMode.allCases.indices.contains(sender.selectedSegment) else { return }
        preferencesStore.menuBarDisplayMode = MenuBarDisplayMode.allCases[sender.selectedSegment]
    }

    @objc private func borderThemeSwatchPressed(_ sender: BorderThemeSwatchButton) {
        guard PanelBorderTheme.allCases.indices.contains(sender.tag) else { return }
        let theme = PanelBorderTheme.allCases[sender.tag]
        preferencesStore.borderTheme = theme
        synchronizeBorderPalette()
        if theme == .custom {
            presentCustomColorPanel()
        }
    }

    @objc private func customBorderColorChanged(_ sender: NSColorPanel) {
        preferencesStore.customBorderColor = sender.color
        if preferencesStore.borderTheme != .custom {
            preferencesStore.borderTheme = .custom
        }
        synchronizeBorderPalette()
    }

    @objc private func windowSizeModeChanged(_ sender: NSSegmentedControl) {
        guard PanelWindowSizeMode.allCases.indices.contains(sender.selectedSegment) else { return }
        preferencesStore.windowSizeMode = PanelWindowSizeMode.allCases[sender.selectedSegment]
        synchronizeFixedSizeControls()
    }

    @objc private func fixedSizePresetChanged(_ sender: NSSegmentedControl) {
        guard SimpleViewportPreset.selectableCases.indices.contains(sender.selectedSegment) else { return }
        let preset = SimpleViewportPreset.selectableCases[sender.selectedSegment]
        guard let size = preset.size else {
            customFixedSizeRow.isHidden = false
            let fraction = preferencesStore.fixedViewportFraction ?? ViewportFraction(viewport: preferencesStore.fixedViewportSize, visibleFrame: (NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)))
            preferencesStore.fixedViewportFraction = fraction
            customFixedWidthField.stringValue = Self.sizeText(fraction.width * 100)
            customFixedHeightField.stringValue = Self.sizeText(fraction.height * 100)
            view.window?.makeFirstResponder(customFixedWidthField)
            return
        }
        preferencesStore.fixedViewportSize = size
        synchronizeFixedSizeControls()
    }

    @objc private func customFixedSizeChanged(_ sender: NSTextField) {
        guard let width = Double(customFixedWidthField.stringValue),
              let height = Double(customFixedHeightField.stringValue),
              width.isFinite,
              height.isFinite,
              (5...100).contains(width), (5...100).contains(height) else {
            NSSound.beep()
            synchronizeFixedSizeControls()
            return
        }
        preferencesStore.fixedViewportFraction = ViewportFraction(width: width / 100, height: height / 100)
        synchronizeFixedSizeControls()
    }

    private func configureCustomFixedField(_ field: NSTextField) {
        field.alignment = .right
        field.placeholderString = "%"
        field.target = self
        field.action = #selector(customFixedSizeChanged(_:))
        field.widthAnchor.constraint(equalToConstant: 72).isActive = true
    }

    private func makeBorderPalette() -> NSStackView {
        borderThemeButtons = PanelBorderTheme.allCases.enumerated().map { index, theme in
            let button = BorderThemeSwatchButton(
                theme: theme,
                customColor: preferencesStore.customBorderColor
            )
            button.tag = index
            button.target = self
            button.action = #selector(borderThemeSwatchPressed(_:))
            return button
        }
        let palette = NSStackView(views: borderThemeButtons)
        palette.orientation = .horizontal
        palette.alignment = .centerY
        palette.spacing = 7
        return palette
    }

    private func presentCustomColorPanel() {
        let panel = NSColorPanel.shared
        panel.color = preferencesStore.customBorderColor
        panel.setTarget(self)
        panel.setAction(#selector(customBorderColorChanged(_:)))
        panel.makeKeyAndOrderFront(nil)
    }

    private func synchronizeControls() {
        languageControl.selectedSegment = AppLanguage.allCases.firstIndex(
            of: preferencesStore.appLanguage
        ) ?? 0
        appearanceControl.selectedSegment = AppAppearanceMode.allCases.firstIndex(
            of: preferencesStore.appearanceMode
        ) ?? 0
        menuBarDisplayControl.selectedSegment = MenuBarDisplayMode.allCases.firstIndex(
            of: preferencesStore.menuBarDisplayMode
        ) ?? 0
        windowSizeControl.selectedSegment = PanelWindowSizeMode.allCases.firstIndex(
            of: preferencesStore.windowSizeMode
        ) ?? 0
        synchronizeBorderPalette()
        synchronizeFixedSizeControls()
    }

    private func synchronizeBorderPalette() {
        for button in borderThemeButtons {
            button.isThemeSelected = button.theme == preferencesStore.borderTheme
            button.customColor = preferencesStore.customBorderColor
        }
    }

    private func synchronizeFixedSizeControls() {
        let isFixed = preferencesStore.windowSizeMode == .fixed
        fixedSizeSection.isHidden = !isFixed
        guard isFixed else { return }

        let preset = preferencesStore.fixedViewportPreset
        let fraction = preferencesStore.fixedViewportFraction ?? ViewportFraction(
            viewport: preferencesStore.fixedViewportSize,
            visibleFrame: NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        )
        fixedSizeControl.selectedSegment = SimpleViewportPreset.selectableCases.firstIndex(of: preset) ?? 0
        customFixedSizeRow.isHidden = preset != .custom
        customFixedWidthField.stringValue = Self.sizeText(fraction.width * 100)
        customFixedHeightField.stringValue = Self.sizeText(fraction.height * 100)
    }

    private static func sizeText(_ value: CGFloat) -> String {
        String(Int(value.rounded()))
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
        label.widthAnchor.constraint(lessThanOrEqualToConstant: 540).isActive = true
        return label
    }

    private static func detailInlineLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11.5)
        label.textColor = .secondaryLabelColor
        return label
    }

    private static func spacer(_ height: CGFloat) -> NSView {
        let view = NSView()
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }
}

@MainActor
final class BorderThemeSwatchButton: NSButton {
    let theme: PanelBorderTheme
    var customColor: NSColor {
        didSet { needsDisplay = true }
    }
    var isThemeSelected = false {
        didSet { needsDisplay = true }
    }

    init(theme: PanelBorderTheme, customColor: NSColor) {
        self.theme = theme
        self.customColor = customColor
        super.init(frame: .zero)
        title = ""
        isBordered = false
        focusRingType = .none
        toolTip = theme.displayName
        setButtonType(.momentaryChange)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 38).isActive = true
        heightAnchor.constraint(equalToConstant: 38).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let ringRect = bounds.insetBy(dx: 2.5, dy: 2.5)
        if isThemeSelected {
            let ring = NSBezierPath(ovalIn: ringRect)
            ring.lineWidth = 3
            NSColor.controlAccentColor.setStroke()
            ring.stroke()
        }

        let swatchRect = bounds.insetBy(dx: 7, dy: 7)
        let swatch = NSBezierPath(ovalIn: swatchRect)
        if theme == .rainbow {
            NSGraphicsContext.saveGraphicsState()
            swatch.addClip()
            NSGradient(colors: [
                .systemPurple,
                .systemBlue,
                .systemGreen,
                .systemYellow,
                .systemOrange,
                .systemRed,
                .systemPink,
            ])?.draw(in: swatchRect, angle: 0)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            (theme.solidColor ?? customColor).setFill()
            swatch.fill()
        }

        NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
        swatch.lineWidth = 1
        swatch.stroke()
    }
}

@MainActor
private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class ShortcutsSettingsViewController: NSViewController {
    private let preferencesStore: AppPreferencesStore
    private let embedsInSettingsPage: Bool
    private var externalCommandsToggle: NSButton?

    init(
        preferencesStore: AppPreferencesStore = AppPreferencesStore(),
        embedsInSettingsPage: Bool = false
    ) {
        self.preferencesStore = preferencesStore
        self.embedsInSettingsPage = embedsInSettingsPage
        super.init(nibName: nil, bundle: nil)
        title = L10n.tr("Shortcuts", "快捷键")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let document = SettingsDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false

        var views: [NSView] = [
            sectionTitle(L10n.tr("Global", "全局快捷键")),
            detailLabel(
                L10n.tr(
                    "Show / Hide works everywhere; other shortcuts work in FloatTabs.",
                    "“显示 / 隐藏”在系统全局可用，其余快捷键在 FloatTabs 窗口激活时生效。"
                )
            ),
            shortcutRecorderRow(
                L10n.tr("Show / Hide FloatTabs", "显示 / 隐藏 FloatTabs"),
                name: .toggleFloatTabs
            ),
            spacer(10),
            sectionTitle(L10n.tr("Tabs", "标签页")),
        ]
        views.append(contentsOf: AppShortcutCatalog.slotBindings.map(shortcutRecorderRow(for:)))
        views.append(contentsOf: [spacer(10), sectionTitle(L10n.tr("Navigation", "导航与操作"))])
        views.append(contentsOf: AppShortcutCatalog.navigationBindings.map(shortcutRecorderRow(for:)))
        views.append(contentsOf: [spacer(10), sectionTitle(L10n.tr("View", "视图与窗口"))])
        views.append(contentsOf: AppShortcutCatalog.viewBindings.map(shortcutRecorderRow(for:)))
        views.append(contentsOf: [spacer(10), sectionTitle(L10n.tr("Application", "应用"))])
        views.append(contentsOf: AppShortcutCatalog.applicationBindings.map(shortcutRecorderRow(for:)))

        let resetButton = NSButton(
            title: L10n.tr("Reset All to Defaults", "全部恢复默认"),
            target: self,
            action: #selector(resetAllShortcuts)
        )
        resetButton.bezelStyle = .rounded

        let externalCommandsCheckbox = NSButton(
            checkboxWithTitle: L10n.tr(
                "Allow external control commands (e.g. RemoteOrbit)",
                "允许外部控制指令（例如 RemoteOrbit）"
            ),
            target: self,
            action: #selector(externalCommandsToggled(_:))
        )
        externalCommandsCheckbox.state = preferencesStore.externalCommandsEnabled ? .on : .off
        self.externalCommandsToggle = externalCommandsCheckbox

        views.append(contentsOf: [
            spacer(10),
            resetButton,
            spacer(12),
            sectionTitle(L10n.tr("External Automation", "外部控制与自动化")),
            externalCommandsCheckbox,
            detailLabel(
                L10n.tr(
                    "Turn off to ignore distributed notifications from external companion tools while keeping your configured keyboard shortcuts active.",
                    "关闭后将忽略来自外部联动工具的分布式控制指令，但应用内与全局快捷键仍正常工作。"
                )
            ),
            spacer(8),
        ])

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: document.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20),
        ])

        guard !embedsInSettingsPage else {
            view = document
            return
        }

        let root = NSView()
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.documentView = document
        root.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            document.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])

        view = root
    }

    private func shortcutRecorderRow(for binding: AppShortcutBinding) -> NSView {
        shortcutRecorderRow(binding.title, name: binding.name)
    }

    private func shortcutRecorderRow(
        _ title: String,
        name: KeyboardShortcuts.Name
    ) -> NSView {
        let actionLabel = label(title)
        actionLabel.widthAnchor.constraint(equalToConstant: 220).isActive = true

        let recorder = KeyboardShortcuts.RecorderCocoa(for: name)
        recorder.translatesAutoresizingMaskIntoConstraints = false
        recorder.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        recorder.validateShortcut = { [weak self] shortcut in
            guard let self else { return .allow }
            if let conflict = self.conflictingAction(for: shortcut, excluding: name) {
                return .disallow(
                    reason: L10n.tr(
                        "This shortcut is already used by “\(conflict)”.",
                        "该快捷键已被“\(conflict)”占用。"
                    )
                )
            }
            return .allow
        }

        let row = NSStackView(views: [actionLabel, recorder])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        return row
    }

    private func conflictingAction(
        for shortcut: KeyboardShortcuts.Shortcut,
        excluding excludedName: KeyboardShortcuts.Name
    ) -> String? {
        let entries: [(String, KeyboardShortcuts.Name)] = [
            (L10n.tr("Show / Hide FloatTabs", "显示 / 隐藏 FloatTabs"), .toggleFloatTabs),
        ] + AppShortcutCatalog.allBindings.map { ($0.title, $0.name) }

        for (title, name) in entries where name != excludedName {
            if KeyboardShortcuts.getShortcut(for: name) == shortcut {
                return title
            }
        }
        return nil
    }

    @objc private func resetAllShortcuts() {
        KeyboardShortcuts.reset([.toggleFloatTabs] + AppShortcutCatalog.allNames)
    }

    @objc private func externalCommandsToggled(_ sender: NSButton) {
        preferencesStore.externalCommandsEnabled = (sender.state == .on)
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

enum AppReleaseInfo {
    static func displayVersion(shortVersion: String?, build _: String?) -> String {
        let version = shortVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedVersion = version.flatMap { $0.isEmpty ? nil : $0 } ?? L10n.tr("Unknown", "未知")
        return L10n.tr("Version \(resolvedVersion)", "版本 \(resolvedVersion)")
    }

    static var currentVersionDisplay: String {
        displayVersion(
            shortVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
    }

}

@MainActor
private final class ProfileDeleteTooltipView: NSView {
    private let button: NSButton

    init(button: NSButton, toolTip: String) {
        self.button = button
        super.init(frame: .zero)
        self.toolTip = toolTip
        translatesAutoresizingMaskIntoConstraints = false
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        button.intrinsicContentSize
    }

    // Keep the disabled button genuinely non-interactive while making the
    // wrapper the tooltip-tracking view. `hitTest(_:)` receives `point` in
    // superview coordinates, so convert into local bounds before checking.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0 else { return nil }
        let localPoint = superview.map { convert(point, from: $0) } ?? point
        return bounds.contains(localPoint) ? self : nil
    }
}

@MainActor
final class PerformanceSettingsViewController: NSViewController {
    private let preferencesStore: AppPreferencesStore
    private let websiteCacheManager: WebsiteCacheManagementClient
    private let embedsInSettingsPage: Bool

    private let websiteCacheUsageLabel = NSTextField(labelWithString: L10n.tr("Unavailable", "暂不可用"))
    private let websiteCacheLastCleanupLabel = NSTextField(labelWithString: L10n.tr("Never", "从未清理"))
    private let websiteCacheAutomaticSwitch = NSSwitch()
    private let websiteCacheRetentionPopup = NSPopUpButton()
    private let websiteCacheMaximumPopup = NSPopUpButton()
    private let releaseWebsiteCacheButton = NSButton(
        title: L10n.tr("Release Cache…", "立即释放缓存…"),
        target: nil,
        action: nil
    )
    private let websiteCacheResultLabel = NSTextField(wrappingLabelWithString: "")
    private var isWebsiteCacheReleaseInProgress = false
    private var websiteCacheMeasurementTask: Task<Void, Never>?
    private var isWebsiteCacheMeasurementInFlight = false
    private var websiteCacheMeasurementSequence = 0

    private(set) var displayedWebsiteCacheUsage = L10n.tr("Unavailable", "暂不可用")
    private(set) var displayedWebsiteCacheLastCleanup = L10n.tr("Never", "从未清理")
    private(set) var isReleaseCacheEnabled = false
    private(set) var websiteCacheResultMessage = ""

    init(
        preferencesStore: AppPreferencesStore,
        websiteCacheManager: WebsiteCacheManagementClient = .unavailable,
        embedsInSettingsPage: Bool = false
    ) {
        self.preferencesStore = preferencesStore
        self.websiteCacheManager = websiteCacheManager
        self.embedsInSettingsPage = embedsInSettingsPage
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        websiteCacheMeasurementTask?.cancel()
    }

    override func loadView() {
        let document = SettingsDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false


        websiteCacheAutomaticSwitch.target = self
        websiteCacheAutomaticSwitch.action = #selector(websiteCacheAutomaticChanged(_:))

        websiteCacheRetentionPopup.addItems(
            withTitles: WebsiteCacheRetentionOption.allCases.map(\.displayName)
        )
        for (index, option) in WebsiteCacheRetentionOption.allCases.enumerated() {
            websiteCacheRetentionPopup.item(at: index)?.representedObject = option.rawValue
        }
        websiteCacheRetentionPopup.target = self
        websiteCacheRetentionPopup.action = #selector(websiteCacheRetentionChanged(_:))
        websiteCacheRetentionPopup.widthAnchor.constraint(equalToConstant: 150).isActive = true

        websiteCacheMaximumPopup.addItems(
            withTitles: WebsiteCacheLimitOption.allCases.map(\.displayName)
        )
        for (index, option) in WebsiteCacheLimitOption.allCases.enumerated() {
            websiteCacheMaximumPopup.item(at: index)?.representedObject = option.rawValue
        }
        websiteCacheMaximumPopup.target = self
        websiteCacheMaximumPopup.action = #selector(websiteCacheMaximumChanged(_:))
        websiteCacheMaximumPopup.widthAnchor.constraint(equalToConstant: 150).isActive = true

        websiteCacheUsageLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        websiteCacheLastCleanupLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        websiteCacheUsageLabel.widthAnchor.constraint(equalToConstant: 180).isActive = true
        websiteCacheLastCleanupLabel.widthAnchor.constraint(equalToConstant: 180).isActive = true
        releaseWebsiteCacheButton.bezelStyle = .rounded
        releaseWebsiteCacheButton.target = self
        releaseWebsiteCacheButton.action = #selector(releaseWebsiteCache(_:))
        websiteCacheResultLabel.font = .systemFont(ofSize: 12)
        websiteCacheResultLabel.textColor = .secondaryLabelColor
        websiteCacheResultLabel.maximumNumberOfLines = 0
        websiteCacheResultLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 510).isActive = true

        let stack = NSStackView(views: [
            sectionTitle(L10n.tr("Runtime Lifecycle", "运行时生命周期")),
            detailLabel(
                L10n.tr(
                    "Automatic keeps recently used Tabs ready and hibernates inactive, unprotected Tabs after 30 minutes (or earlier under macOS memory pressure). Use Runtime Retention → Keep Loaded on a Tab’s menu when you want an already loaded Tab kept resident in the background.",
                    "“自动管理”会保持近期使用的标签处于就绪状态，并在标签闲置 30 分钟后（或系统内存紧张时更早）休眠释放；如需已加载页面保持后台常驻，可在标签右键菜单的“驻留策略”中选择“保持常驻”。"
                )
            ),
            spacer(10),
            sectionTitle(L10n.tr("Website Storage", "网站存储空间")),
            detailLabel(
                L10n.tr(
                    "Only re-downloadable webpage caches are removed.",
                    "仅清理可重新下载的网页缓存，不影响登录状态与持久数据。"
                )
            ),
            websiteCacheSettingRow(
                L10n.tr("Estimated cache usage", "预计缓存占用"),
                control: websiteCacheUsageLabel
            ),
            websiteCacheSettingRow(
                L10n.tr("Last cleanup", "上次清理时间"),
                control: websiteCacheLastCleanupLabel
            ),
            websiteCacheSettingRow(
                L10n.tr("Automatically manage cache", "自动管理缓存"),
                control: websiteCacheAutomaticSwitch
            ),
            websiteCacheSettingRow(
                L10n.tr("Remove cache unused for", "清理未使用的缓存超过"),
                control: websiteCacheRetentionPopup
            ),
            websiteCacheSettingRow(
                L10n.tr("Maximum cache usage", "最大缓存上限"),
                control: websiteCacheMaximumPopup
            ),
            releaseWebsiteCacheButton,
            websiteCacheResultLabel,
            spacer(8),
            detailLabel(L10n.tr("Cache size is an estimate.", "缓存大小为估算值。")),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: document.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20),
        ])

        let contentView: NSView
        if embedsInSettingsPage {
            contentView = document
        } else {
            let root = NSView()
            let scrollView = NSScrollView()
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            scrollView.hasVerticalScroller = true
            scrollView.drawsBackground = false
            scrollView.borderType = .noBorder
            scrollView.autohidesScrollers = true
            scrollView.documentView = document
            root.addSubview(scrollView)
            NSLayoutConstraint.activate([
                scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                scrollView.topAnchor.constraint(equalTo: root.topAnchor),
                scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

                document.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
                document.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
                document.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
                document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            ])
            contentView = root
        }

        view = contentView
        refreshWebsiteCache()
        startWebsiteCacheMeasurement()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshWebsiteCache()
        startWebsiteCacheMeasurement()
    }

    override func viewWillDisappear() {
        websiteCacheMeasurementTask?.cancel()
        websiteCacheMeasurementTask = nil
        isWebsiteCacheMeasurementInFlight = false
        websiteCacheMeasurementSequence += 1
        super.viewWillDisappear()
    }

    func refreshWebsiteCache() {
        guard isViewLoaded else { return }
        let snapshot = websiteCacheManager.snapshot()
        switch snapshot.measurementState {
        case .calculating:
            displayedWebsiteCacheUsage = L10n.tr("Calculating…", "正在统计…")
        case .available:
            displayedWebsiteCacheUsage = Self.formatByteCount(snapshot.estimatedBytes)
        case .unavailable:
            displayedWebsiteCacheUsage = L10n.tr("Unavailable", "暂不可用")
        }
        displayedWebsiteCacheLastCleanup = Self.formatDate(snapshot.lastSuccessfulCleanupAt)
        websiteCacheUsageLabel.stringValue = displayedWebsiteCacheUsage
        websiteCacheLastCleanupLabel.stringValue = displayedWebsiteCacheLastCleanup

        let retention = WebsiteCacheRetentionOption(days: snapshot.policy.retentionDays)
        websiteCacheRetentionPopup.selectItem(withTitle: retention.displayName)
        websiteCacheMaximumPopup.selectItem(
            withTitle: WebsiteCacheLimitOption(bytes: snapshot.policy.maximumEstimatedBytes).displayName
        )
        websiteCacheAutomaticSwitch.state = snapshot.policy.automaticCleanupEnabled ? .on : .off

        let enabled = websiteCacheManager.isAvailable
            && !snapshot.isOperationInProgress
            && !isWebsiteCacheReleaseInProgress
        websiteCacheAutomaticSwitch.isEnabled = websiteCacheManager.isAvailable
        websiteCacheRetentionPopup.isEnabled = websiteCacheManager.isAvailable
        websiteCacheMaximumPopup.isEnabled = websiteCacheManager.isAvailable
        releaseWebsiteCacheButton.isEnabled = enabled
        isReleaseCacheEnabled = enabled
        websiteCacheResultLabel.stringValue = websiteCacheResultMessage
    }

    private func startWebsiteCacheMeasurement() {
        guard websiteCacheManager.isAvailable, !isWebsiteCacheMeasurementInFlight else { return }
        isWebsiteCacheMeasurementInFlight = true
        websiteCacheMeasurementSequence += 1
        let sequence = websiteCacheMeasurementSequence
        websiteCacheManager.beginMeasurement()
        refreshWebsiteCache()
        websiteCacheMeasurementTask = Task { @MainActor [weak self] in
            defer { self?.endWebsiteCacheMeasurement(sequence: sequence) }
            guard let self else { return }
            await self.websiteCacheManager.refreshMeasurement()
            guard !Task.isCancelled else { return }
            self.refreshWebsiteCache()
        }
    }

    private func endWebsiteCacheMeasurement(sequence: Int) {
        guard websiteCacheMeasurementSequence == sequence else { return }
        isWebsiteCacheMeasurementInFlight = false
    }

    @objc private func websiteCacheAutomaticChanged(_ sender: NSSwitch) {
        var policy = websiteCacheManager.snapshot().policy
        policy.automaticCleanupEnabled = sender.state == .on
        websiteCacheManager.updatePolicy(policy)
        refreshWebsiteCache()
    }

    @objc private func websiteCacheRetentionChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let option = WebsiteCacheRetentionOption(rawValue: raw) else { return }
        var policy = websiteCacheManager.snapshot().policy
        policy.retentionDays = option.days
        websiteCacheManager.updatePolicy(policy)
        refreshWebsiteCache()
    }

    @objc private func websiteCacheMaximumChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let option = WebsiteCacheLimitOption(rawValue: raw) else { return }
        var policy = websiteCacheManager.snapshot().policy
        policy.maximumEstimatedBytes = option.bytes
        policy.targetEstimatedBytes = WebsiteCachePolicy.targetEstimatedBytes(forMaximum: option.bytes)
        websiteCacheManager.updatePolicy(policy)
        refreshWebsiteCache()
    }

    @objc private func releaseWebsiteCache(_ sender: NSButton) {
        guard websiteCacheManager.isAvailable,
              !websiteCacheManager.snapshot().isOperationInProgress,
              !isWebsiteCacheReleaseInProgress,
              let window = view.window else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.tr("Release Website Cache?", "释放网站缓存？")
        alert.informativeText = L10n.tr(
            "This clears only re-downloadable webpage caches. Cookies, login state and persistent website data are not cleared. Currently open pages may reload.",
            "此操作仅清除可重新下载的网页缓存。Cookie、登录状态与本地持久数据不会被清除，当前打开的页面可能会重新加载。"
        )
        alert.addButton(withTitle: L10n.tr("Release Cache", "释放缓存"))
        alert.addButton(withTitle: L10n.tr("Cancel", "取消"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.isWebsiteCacheReleaseInProgress = true
            self.websiteCacheResultMessage = L10n.tr("Releasing cache…", "正在释放缓存…")
            self.refreshWebsiteCache()
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let result = try await self.websiteCacheManager.releaseCache()
                    self.websiteCacheResultMessage = Self.cleanupResultText(result)
                } catch {
                    self.websiteCacheResultMessage = L10n.tr(
                        "Cache release failed: \(error.localizedDescription)",
                        "缓存释放失败：\(error.localizedDescription)"
                    )
                }
                self.isWebsiteCacheReleaseInProgress = false
                self.refreshWebsiteCache()
            }
        }
    }

    static func formatByteCount(_ bytes: Int64?) -> String {
        guard let bytes else { return L10n.tr("Unavailable", "暂不可用") }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    static func formatDate(_ date: Date?) -> String {
        guard let date else { return L10n.tr("Never", "从未清理") }
        let formatter = DateFormatter()
        if AppLocalization.isChinese {
            formatter.locale = Locale(identifier: "zh_Hans")
        }
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func cleanupResultText(_ result: WebsiteCacheCleanupResult) -> String {
        let released = formatByteCount(result.releasedBytes)
        if result.estimatedBytesBefore == nil || result.estimatedBytesAfter == nil {
            return L10n.tr(
                "Cache released from \(result.cleanedProfileCount) Profile(s), \(result.cleanedRecordCount) record(s). Size unavailable.",
                "已从 \(result.cleanedProfileCount) 个配置文件释放 \(result.cleanedRecordCount) 条缓存记录（大小暂不可用）。"
            )
        }
        return L10n.tr(
            "Estimated usage: \(formatByteCount(result.estimatedBytesBefore)) → \(formatByteCount(result.estimatedBytesAfter)). Released \(released) across \(result.cleanedProfileCount) Profile(s), \(result.cleanedRecordCount) record(s).",
            "预计占用：\(formatByteCount(result.estimatedBytesBefore)) → \(formatByteCount(result.estimatedBytesAfter))，共清理 \(result.cleanedProfileCount) 个配置文件的 \(result.cleanedRecordCount) 条记录，释放约 \(released)。"
        )
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

    private func websiteCacheSettingRow(_ text: String, control: NSView) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.widthAnchor.constraint(equalToConstant: 220).isActive = true
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        return row
    }

    private func spacer(_ height: CGFloat) -> NSView {
        let view = NSView()
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }
}

@MainActor
class BrowserProfilesSettingsViewController: NSViewController {
    private let browserProfileManager: BrowserProfileManagementClient
    private let embedsInSettingsPage: Bool

    private let profileRowsStack = NSStackView()
    private let newProfileButton = NSButton(
        title: L10n.tr("+ New Profile", "+ 新建配置文件"),
        target: nil,
        action: nil
    )
    private let profileSupportLabel = NSTextField(wrappingLabelWithString: "")

    // Read-only derived seams keep UI tests focused on the injected snapshot;
    // they are never used as an authoritative Profile model.
    private(set) var displayedBrowserProfileNames: [String] = []
    private(set) var displayedBrowserProfileActionTitles: [[String]] = []
    private(set) var displayedBrowserProfileDeleteEnabled: [Bool] = []
    private(set) var displayedBrowserProfileDeleteToolTips: [String?] = []
    private(set) var isNewProfileEnabled = false
    private(set) var profileSupportDescription = ""

    init(
        browserProfileManager: BrowserProfileManagementClient = .unavailable,
        embedsInSettingsPage: Bool = false
    ) {
        self.browserProfileManager = browserProfileManager
        self.embedsInSettingsPage = embedsInSettingsPage
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let document = SettingsDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false

        profileRowsStack.orientation = .vertical
        profileRowsStack.alignment = .leading
        profileRowsStack.spacing = 6

        profileSupportLabel.font = .systemFont(ofSize: 12)
        profileSupportLabel.textColor = .secondaryLabelColor
        profileSupportLabel.maximumNumberOfLines = 0
        profileSupportLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 510).isActive = true

        newProfileButton.target = self
        newProfileButton.action = #selector(createProfile)
        newProfileButton.bezelStyle = .rounded

        let stack = NSStackView(views: [
            sectionTitle(L10n.tr("Profiles", "浏览器配置文件")),
            profileRowsStack,
            profileSupportLabel,
            newProfileButton,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: document.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20),
        ])

        if embedsInSettingsPage {
            view = document
        } else {
            let root = NSView()
            let scrollView = NSScrollView()
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            scrollView.hasVerticalScroller = true
            scrollView.drawsBackground = false
            scrollView.borderType = .noBorder
            scrollView.autohidesScrollers = true
            scrollView.documentView = document
            root.addSubview(scrollView)
            NSLayoutConstraint.activate([
                scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                scrollView.topAnchor.constraint(equalTo: root.topAnchor),
                scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

                document.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
                document.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
                document.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
                document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            ])
            view = root
        }
        refreshProfiles()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshProfiles()
    }

    /// Refreshes from the injected authority every time Settings appears and
    /// after a successful mutation. No Profile metadata is cached here.
    func refreshProfiles() {
        let snapshot = browserProfileManager.snapshot()
        let hasAnotherProfile = snapshot.totalProfileCount > 1

        var names: [String] = []
        var actionTitles: [[String]] = []
        var deleteEnabled: [Bool] = []
        var deleteToolTips: [String?] = []

        for arrangedSubview in profileRowsStack.arrangedSubviews {
            profileRowsStack.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }

        let renameTitle = L10n.tr("Rename…", "重命名…")
        let deleteTitle = L10n.tr("Delete…", "删除…")

        if snapshot.includesDefaultProfile {
            let canDeleteDefault = !snapshot.isDefaultProfileReferenced && hasAnotherProfile
            let defaultDisplayName = L10n.defaultDisplayName(snapshot.defaultProfilePresentation.name)
            let defaultTooltip = Self.profileDeletionTooltip(
                for: snapshot.defaultReferencingWebAppNames,
                isReferencedWithoutNames: snapshot.isDefaultProfileReferenced
                    && snapshot.defaultReferencingWebAppNames.isEmpty,
                isLastRemaining: !snapshot.isDefaultProfileReferenced && !hasAnotherProfile
            )
            names.append(defaultDisplayName)
            actionTitles.append([renameTitle, deleteTitle])
            deleteEnabled.append(canDeleteDefault)
            deleteToolTips.append(defaultTooltip)

            profileRowsStack.addArrangedSubview(
                makeProfileRow(
                    name: defaultDisplayName,
                    profileID: nil,
                    renameAction: #selector(renameDefaultProfile),
                    deleteAction: #selector(deleteDefaultProfile),
                    isReferenced: snapshot.isDefaultProfileReferenced,
                    referencingWebAppNames: snapshot.defaultReferencingWebAppNames,
                    canDelete: canDeleteDefault,
                    deleteToolTip: defaultTooltip
                )
            )
        }

        for profile in snapshot.customProfiles {
            let isReferenced = snapshot.referencedProfileIDs.contains(profile.id)
            let referencingNames = snapshot.referencingWebAppNamesByProfileID[profile.id] ?? []
            let canDelete = !isReferenced && hasAnotherProfile
            let tooltip = Self.profileDeletionTooltip(
                for: referencingNames,
                isReferencedWithoutNames: isReferenced && referencingNames.isEmpty,
                isLastRemaining: !isReferenced && !hasAnotherProfile
            )
            names.append(profile.name)
            actionTitles.append([renameTitle, deleteTitle])
            deleteEnabled.append(canDelete)
            deleteToolTips.append(tooltip)

            profileRowsStack.addArrangedSubview(
                makeProfileRow(
                    name: profile.name,
                    profileID: profile.id,
                    renameAction: #selector(renameProfile(_:)),
                    deleteAction: #selector(deleteProfile(_:)),
                    isReferenced: isReferenced,
                    referencingWebAppNames: referencingNames,
                    canDelete: canDelete,
                    deleteToolTip: tooltip
                )
            )
        }

        displayedBrowserProfileNames = names
        displayedBrowserProfileActionTitles = actionTitles
        displayedBrowserProfileDeleteEnabled = deleteEnabled
        displayedBrowserProfileDeleteToolTips = deleteToolTips
        isNewProfileEnabled = true
        newProfileButton.isEnabled = true
        profileSupportDescription = L10n.tr(
            "Each Profile uses its own FloatTabs website data.",
            "每个配置文件各自拥有独立的网站数据与登录状态。"
        )
        profileSupportLabel.stringValue = profileSupportDescription
    }

    /// Internal action seam used by focused tests to exercise the same trim
    /// and manager handoff used by the New Profile alert.
    func submitNewProfileNameForTesting(_ rawName: String) {
        submitNewProfileName(rawName)
    }

    static func trimmedProfileName(_ rawName: String) -> String? {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func makeProfileRow(
        name: String,
        profileID: UUID?,
        renameAction: Selector,
        deleteAction: Selector,
        isReferenced: Bool,
        referencingWebAppNames: [String],
        canDelete: Bool,
        deleteToolTip: String?
    ) -> NSView {
        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = .systemFont(ofSize: 12)
        nameLabel.widthAnchor.constraint(equalToConstant: 230).isActive = true

        let renameButton = NSButton(
            title: L10n.tr("Rename…", "重命名…"),
            target: self,
            action: renameAction
        )
        if let profileID {
            renameButton.identifier = NSUserInterfaceItemIdentifier(profileID.uuidString)
        }
        renameButton.bezelStyle = .rounded

        let deleteButton = NSButton(
            title: L10n.tr("Delete…", "删除…"),
            target: self,
            action: deleteAction
        )
        if let profileID {
            deleteButton.identifier = NSUserInterfaceItemIdentifier(profileID.uuidString)
        }
        deleteButton.bezelStyle = .rounded
        deleteButton.isEnabled = canDelete
        deleteButton.toolTip = deleteToolTip

        let deleteControl: NSView
        if !canDelete, let deleteToolTip {
            deleteControl = ProfileDeleteTooltipView(
                button: deleteButton,
                toolTip: deleteToolTip
            )
        } else {
            deleteControl = deleteButton
        }

        let actions = NSStackView(views: [renameButton, deleteControl])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8

        let row = NSStackView(views: [nameLabel, actions])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10

        guard isReferenced else { return row }
        let detailText = referencingWebAppNames.isEmpty
            ? L10n.tr(
                "This Profile is used by one or more Web Apps.",
                "此配置文件正在被一个或多个网页应用使用。"
            )
            : L10n.tr(
                "Used by \(referencingWebAppNames.joined(separator: ", ")).",
                "正用于：\(referencingWebAppNames.joined(separator: "、"))。"
            )
        let detail = detailLabel(detailText)
        let wrapper = NSStackView(views: [row, detail])
        wrapper.orientation = .vertical
        wrapper.alignment = .leading
        wrapper.spacing = 3
        return wrapper
    }

    static var lastRemainingProfileTooltip: String {
        L10n.tr(
            "At least one Browser Profile must remain.",
            "至少需要保留一个浏览器配置文件。"
        )
    }

    static func profileDeletionTooltip(for webAppNames: [String]) -> String? {
        profileDeletionTooltip(
            for: webAppNames,
            isReferencedWithoutNames: false,
            isLastRemaining: false
        )
    }

    static func profileDeletionTooltip(
        for webAppNames: [String],
        isReferencedWithoutNames: Bool,
        isLastRemaining: Bool
    ) -> String? {
        if !webAppNames.isEmpty {
            return L10n.tr(
                "Used by Tabs: \(webAppNames.joined(separator: ", ")). Switch them to another Profile before deleting.",
                "正被标签页使用：\(webAppNames.joined(separator: "、"))。请先将它们切换到其他配置文件后再删除。"
            )
        }
        if isReferencedWithoutNames {
            return L10n.tr(
                "This Profile is used by one or more Web Apps.",
                "此配置文件正在被一个或多个网页应用使用。"
            )
        }
        if isLastRemaining {
            return lastRemainingProfileTooltip
        }
        return nil
    }

    @objc private func createProfile() {
        guard let window = view.window else { return }

        let field = NSTextField(string: "")
        field.placeholderString = L10n.tr("Profile name", "配置文件名称")
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)

        let alert = NSAlert()
        alert.messageText = L10n.tr("New Browser Profile", "新建浏览器配置文件")
        alert.informativeText = L10n.tr(
            "Choose a name for this Profile. It will use separate FloatTabs website data.",
            "为该配置文件命名，它将拥有独立的网页数据与登录会话。"
        )
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.tr("Create", "创建"))
        alert.addButton(withTitle: L10n.tr("Cancel", "取消"))
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            alert.window.endEditing(for: nil)
            guard response == .alertFirstButtonReturn, let self else { return }
            self.submitNewProfileName(field.stringValue)
        }
    }

    private func submitNewProfileName(_ rawName: String) {
        guard let trimmedName = Self.trimmedProfileName(rawName) else {
            showProfileError(BrowserProfileManagementError.invalidName)
            return
        }

        do {
            _ = try browserProfileManager.create(name: trimmedName)
            refreshProfiles()
        } catch {
            showProfileError(error)
        }
    }

    /// UI preflight only prevents an obsolete destructive confirmation. The
    /// manager repeats the reference check authoritatively after confirmation
    /// to protect the deletion race boundary.
    func profileDeletionCandidate(id: UUID) throws -> BrowserProfile {
        let snapshot = browserProfileManager.snapshot()
        guard let profile = snapshot.customProfiles.first(where: { $0.id == id }) else {
            throw BrowserProfileManagementError.notFound
        }
        guard !snapshot.referencedProfileIDs.contains(id) else {
            throw BrowserProfileManagementError.referenced
        }
        guard snapshot.totalProfileCount > 1 else {
            throw BrowserProfileManagementError.lastRemainingProfile
        }
        return profile
    }

    func defaultProfileDeletionCandidate() throws -> DefaultBrowserProfilePresentation {
        let snapshot = browserProfileManager.snapshot()
        guard snapshot.includesDefaultProfile else {
            throw BrowserProfileManagementError.notFound
        }
        guard !snapshot.isDefaultProfileReferenced else {
            throw BrowserProfileManagementError.referenced
        }
        guard snapshot.totalProfileCount > 1 else {
            throw BrowserProfileManagementError.lastRemainingProfile
        }
        return snapshot.defaultProfilePresentation
    }

    @objc private func renameDefaultProfile() {
        presentRenameProfile(
            id: nil,
            currentName: browserProfileManager.snapshot().defaultProfilePresentation.name
        )
    }

    @objc private func deleteDefaultProfile() {
        do {
            let presentation = try defaultProfileDeletionCandidate()
            presentDeleteProfileConfirmation(
                id: nil,
                name: L10n.defaultDisplayName(presentation.name)
            )
        } catch {
            showProfileError(error)
        }
    }

    @objc private func renameProfile(_ sender: NSButton) {
        guard let id = profileID(from: sender),
              let currentName = browserProfileManager.snapshot().customProfiles.first(where: {
                  $0.id == id
              })?.name else { return }
        presentRenameProfile(id: id, currentName: currentName)
    }

    private func presentRenameProfile(id: UUID?, currentName: String) {
        guard let window = view.window else { return }

        let displayedInitial = id == nil ? L10n.defaultDisplayName(currentName) : currentName
        let field = NSTextField(string: displayedInitial)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)

        let alert = NSAlert()
        alert.messageText = L10n.tr("Rename Browser Profile", "重命名浏览器配置文件")
        alert.informativeText = L10n.tr(
            "Choose a new name for this Profile. Its website data and identity will remain unchanged.",
            "输入新的配置文件名称，其已有的网站数据与身份标识不会改变。"
        )
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.tr("Rename", "重命名"))
        alert.addButton(withTitle: L10n.tr("Cancel", "取消"))
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            alert.window.endEditing(for: nil)
            guard response == .alertFirstButtonReturn, let self else { return }
            guard let trimmedName = Self.trimmedProfileName(field.stringValue) else {
                self.showProfileError(BrowserProfileManagementError.invalidName)
                return
            }
            let resolvedName = (id == nil && currentName == "Default" && trimmedName == L10n.tr("Default", "默认"))
                ? "Default"
                : trimmedName
            do {
                try self.browserProfileManager.rename(id: id, name: resolvedName)
                self.refreshProfiles()
            } catch {
                self.showProfileError(error)
            }
        }
    }

    @objc private func deleteProfile(_ sender: NSButton) {
        guard let id = profileID(from: sender) else { return }

        do {
            let profile = try profileDeletionCandidate(id: id)
            presentDeleteProfileConfirmation(id: id, name: profile.name)
        } catch {
            showProfileError(error)
        }
    }

    private func presentDeleteProfileConfirmation(id: UUID?, name: String) {
        guard let window = view.window else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.tr(
            "Delete Browser Profile \"\(name)\"?",
            "删除浏览器配置文件“\(name)”？"
        )
        alert.informativeText = L10n.tr(
            "Deleting this Profile removes its FloatTabs website data, including its saved website sessions for this Profile. This cannot be undone. Apple Passwords and Keychain data are not affected.",
            "删除此配置文件将移除其独立的网站数据及已保存的登录会话，且无法撤销。Apple 密码和钥匙串数据不受影响。"
        )
        alert.addButton(withTitle: L10n.tr("Delete Profile", "删除配置文件"))
        alert.addButton(withTitle: L10n.tr("Cancel", "取消"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await self.browserProfileManager.delete(id: id)
                    self.refreshProfiles()
                } catch {
                    self.showProfileError(error)
                }
            }
        }
    }

    private func profileID(from sender: NSButton) -> UUID? {
        guard let rawValue = sender.identifier?.rawValue else { return nil }
        return UUID(uuidString: rawValue)
    }

    private func showMessage(title: String, detail: String) {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: L10n.tr("OK", "好"))
        alert.beginSheetModal(for: window)
    }

    private func showProfileError(_ error: Error) {
        showMessage(
            title: L10n.tr("Profile Operation Failed", "配置文件操作失败"),
            detail: error.localizedDescription
        )
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
