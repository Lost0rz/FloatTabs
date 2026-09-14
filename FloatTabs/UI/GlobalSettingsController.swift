import AppKit
import KeyboardShortcuts

enum BrowserProfileManagementError: LocalizedError, Equatable {
    case unsupported
    case notFound
    case referenced
    case invalidName
    case duplicateName
    case runtimeStillResident
    case metadataPersistenceFailed

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "Additional Browser Profiles require macOS 14 or later."
        case .notFound:
            return "That Browser Profile no longer exists."
        case .referenced:
            return "This Profile is used by one or more Web Apps."
        case .invalidName:
            return "Enter a non-empty Profile name."
        case .duplicateName:
            return "That Profile name is already in use."
        case .runtimeStillResident:
            return "The Profile is still in use by a live runtime. Try again."
        case .metadataPersistenceFailed:
            return "FloatTabs could not save the Profile metadata. Your previous settings were kept."
        }
    }
}

struct BrowserProfileManagementSnapshot: Equatable {
    let customProfiles: [BrowserProfile]
    let defaultProfilePresentation: DefaultBrowserProfilePresentation
    let referencedProfileIDs: Set<UUID>
    let referencingWebAppNamesByProfileID: [UUID: [String]]
    let customProfilesSupported: Bool

    init(
        customProfiles: [BrowserProfile],
        defaultProfilePresentation: DefaultBrowserProfilePresentation = .default,
        referencedProfileIDs: Set<UUID>,
        referencingWebAppNamesByProfileID: [UUID: [String]] = [:],
        customProfilesSupported: Bool
    ) {
        self.customProfiles = customProfiles
        self.defaultProfilePresentation = defaultProfilePresentation
        self.referencedProfileIDs = referencedProfileIDs
        self.referencingWebAppNamesByProfileID = referencingWebAppNamesByProfileID
        self.customProfilesSupported = customProfilesSupported
    }
}

@MainActor
struct BrowserProfileManagementClient {
    typealias SnapshotHandler = () -> BrowserProfileManagementSnapshot
    typealias CreateHandler = (String) throws -> BrowserProfile
    typealias RenameHandler = (UUID?, String) throws -> Void
    typealias ColorHandler = (UUID?, BrowserProfileColor) throws -> Void
    typealias DeleteHandler = (UUID) async throws -> Void

    private let snapshotHandler: SnapshotHandler
    private let createHandler: CreateHandler
    private let renameHandler: RenameHandler
    private let colorHandler: ColorHandler
    private let deleteHandler: DeleteHandler

    init(
        snapshot: @escaping SnapshotHandler,
        create: @escaping CreateHandler,
        rename: @escaping RenameHandler,
        setColor: @escaping ColorHandler = { _, _ in },
        delete: @escaping DeleteHandler
    ) {
        snapshotHandler = snapshot
        createHandler = create
        renameHandler = rename
        colorHandler = setColor
        deleteHandler = delete
    }

    static let unavailable = BrowserProfileManagementClient(
        snapshot: {
            BrowserProfileManagementSnapshot(
                customProfiles: [],
                referencedProfileIDs: [],
                customProfilesSupported: false
            )
        },
        create: { _ in throw BrowserProfileManagementError.unsupported },
        rename: { _, _ in throw BrowserProfileManagementError.unsupported },
        delete: { _ in throw BrowserProfileManagementError.unsupported }
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

    func setColor(id: UUID?, color: BrowserProfileColor) throws {
        try colorHandler(id, color)
    }

    func delete(id: UUID) async throws {
        try await deleteHandler(id)
    }
}

typealias SpeechPreviewHandler = @MainActor ([SpeechUtteranceRequest]) -> Void

@MainActor
final class GlobalSettingsController: NSObject, NSWindowDelegate {
    typealias ExportBackupHandler = (URL) throws -> Void
    typealias RestoreBackupHandler = (URL) throws -> URL

    private let preferencesStore: AppPreferencesStore
    private let speechPreferencesStore: SpeechPreferencesStore
    private let speechVoiceCatalog: SpeechVoiceCatalogProviding
    private let speechPreviewHandler: SpeechPreviewHandler?
    private let attentionSoundAssetStore: AttentionSoundAssetStore
    private let attentionSoundPlayer: AttentionSoundPlaying
    private let onExportBackup: ExportBackupHandler
    private let onRestoreBackup: RestoreBackupHandler
    private let browserProfileManager: BrowserProfileManagementClient
    private let websiteCacheManager: WebsiteCacheManagementClient
    private let onExportDiagnostics: RuntimeDiagnosticsExportHandler
    private let onOpenDiagnosticsLogs: () -> Void
    private lazy var settingsWindow: NSWindow = makeWindow()

    init(
        preferencesStore: AppPreferencesStore,
        speechPreferencesStore: SpeechPreferencesStore = SpeechPreferencesStore(),
        speechVoiceCatalog: SpeechVoiceCatalogProviding = SpeechVoiceCatalog(),
        speechPreviewHandler: SpeechPreviewHandler? = nil,
        attentionSoundAssetStore: AttentionSoundAssetStore = AttentionSoundAssetStore(),
        attentionSoundPlayer: AttentionSoundPlaying = AttentionSoundPlayer(),
        onExportBackup: @escaping ExportBackupHandler = { _ in },
        onRestoreBackup: @escaping RestoreBackupHandler = { _ in throw FloatTabsBackupError.restoreFailed },
        browserProfileManager: BrowserProfileManagementClient = .unavailable,
        websiteCacheManager: WebsiteCacheManagementClient = .unavailable,
        onExportDiagnostics: @escaping RuntimeDiagnosticsExportHandler = { _, completion in
            completion(.failure(.writerDisabled))
        },
        onOpenDiagnosticsLogs: @escaping () -> Void = {}
    ) {
        self.preferencesStore = preferencesStore
        self.speechPreferencesStore = speechPreferencesStore
        self.speechVoiceCatalog = speechVoiceCatalog
        self.speechPreviewHandler = speechPreviewHandler
        self.attentionSoundAssetStore = attentionSoundAssetStore
        self.attentionSoundPlayer = attentionSoundPlayer
        self.onExportBackup = onExportBackup
        self.onRestoreBackup = onRestoreBackup
        self.browserProfileManager = browserProfileManager
        self.websiteCacheManager = websiteCacheManager
        self.onExportDiagnostics = onExportDiagnostics
        self.onOpenDiagnosticsLogs = onOpenDiagnosticsLogs
        super.init()
    }

    var isVisible: Bool { settingsWindow.isVisible }

    func show() {
        // Settings is also opened from the accessory app's status menu, so it
        // needs the same explicit user-presentation activation semantics as the
        // primary FloatTabs window group.
        settingsWindow.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
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

        let window = NSWindow(contentViewController: tabs)
        window.title = "FloatTabs Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 620, height: 580))
        window.minSize = NSSize(width: 580, height: 500)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    private func makeSettingsPage(for page: GlobalSettingsPage) -> NSViewController {
        let children: [NSViewController]
        switch page {
        case .general:
            children = [
                AppearanceSettingsViewController(preferencesStore: preferencesStore)
            ]
        case .browserPerformance:
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
        case .audio:
            children = [
                NotificationsSettingsViewController(
                    preferencesStore: preferencesStore,
                    attentionSoundPlayer: attentionSoundPlayer,
                    assetStore: attentionSoundAssetStore
                ),
                SpeechSettingsViewController(
                    preferencesStore: speechPreferencesStore,
                    voiceCatalog: speechVoiceCatalog,
                    previewHandler: speechPreviewHandler
                ),
            ]
        case .shortcuts:
            children = [
                ShortcutsSettingsViewController(embedsInSettingsPage: true)
            ]
        case .advanced:
            children = [
                RuntimeDiagnosticsSettingsViewController(
                    preferencesStore: preferencesStore,
                    exportHandler: onExportDiagnostics,
                    openLogsHandler: onOpenDiagnosticsLogs
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
final class SpeechSettingsViewController: NSViewController {
    private let preferencesStore: SpeechPreferencesStore
    private let voiceCatalog: SpeechVoiceCatalogProviding
    private let previewHandler: SpeechPreviewHandler?
    private let systemSettingsOpener: (URL) -> Bool

    let chineseVoicePopup = NSPopUpButton()
    let englishVoicePopup = NSPopUpButton()
    let speechRateSlider = NSSlider(
        value: Double(SpeechPreferencesStore.defaultSpeechRate),
        minValue: Double(SpeechPreferencesStore.minimumSpeechRate),
        maxValue: Double(SpeechPreferencesStore.maximumSpeechRate),
        target: nil,
        action: nil
    )
    let followSpeechSwitch = NSSwitch()
    let chinesePreviewButton = NSButton(title: "中文试听", target: nil, action: nil)
    let englishPreviewButton = NSButton(title: "English Preview", target: nil, action: nil)
    let mixedPreviewButton = NSButton(title: "Mixed Language Preview", target: nil, action: nil)
    let refreshVoicesButton = NSButton(title: "Refresh Voices", target: nil, action: nil)
    let manageHighQualityVoicesButton = NSButton(
        title: "Manage High-Quality Voices…",
        target: nil,
        action: nil
    )
    private let speechRateValueLabel = NSTextField(labelWithString: "0.50")
    private(set) var lastSystemSettingsOpenResult = false

    init(
        preferencesStore: SpeechPreferencesStore = SpeechPreferencesStore(),
        voiceCatalog: SpeechVoiceCatalogProviding = SpeechVoiceCatalog(),
        previewHandler: SpeechPreviewHandler? = nil,
        systemSettingsOpener: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        self.preferencesStore = preferencesStore
        self.voiceCatalog = voiceCatalog
        self.previewHandler = previewHandler
        self.systemSettingsOpener = systemSettingsOpener
        super.init(nibName: nil, bundle: nil)
        title = "Speech"
        voiceCatalog.onVoicesChanged = { [weak self] in
            self?.synchronizeControls()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()

        configureVoicePopup(chineseVoicePopup, role: .chinese)
        configureVoicePopup(englishVoicePopup, role: .english)
        chineseVoicePopup.target = self
        chineseVoicePopup.action = #selector(chineseVoiceChanged(_:))
        englishVoicePopup.target = self
        englishVoicePopup.action = #selector(englishVoiceChanged(_:))

        speechRateSlider.target = self
        speechRateSlider.action = #selector(speechRateChanged(_:))
        speechRateSlider.isContinuous = false
        speechRateSlider.widthAnchor.constraint(equalToConstant: 250).isActive = true
        speechRateValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        speechRateValueLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        followSpeechSwitch.target = self
        followSpeechSwitch.action = #selector(followSpeechChanged(_:))

        chinesePreviewButton.target = self
        chinesePreviewButton.action = #selector(chinesePreview(_:))
        englishPreviewButton.target = self
        englishPreviewButton.action = #selector(englishPreview(_:))
        mixedPreviewButton.target = self
        mixedPreviewButton.action = #selector(mixedPreview(_:))
        refreshVoicesButton.target = self
        refreshVoicesButton.action = #selector(refreshVoices(_:))
        manageHighQualityVoicesButton.target = self
        manageHighQualityVoicesButton.action = #selector(manageHighQualityVoices(_:))

        let rateControls = NSStackView(views: [
            NSTextField(labelWithString: "Slow"),
            speechRateSlider,
            NSTextField(labelWithString: "Fast"),
            speechRateValueLabel,
        ])
        rateControls.orientation = .horizontal
        rateControls.alignment = .centerY
        rateControls.spacing = 8

        let previewControls = NSStackView(views: [
            chinesePreviewButton,
            englishPreviewButton,
            mixedPreviewButton,
        ])
        previewControls.orientation = .horizontal
        previewControls.alignment = .centerY
        previewControls.spacing = 8

        let voiceActions = NSStackView(views: [
            refreshVoicesButton,
            manageHighQualityVoicesButton,
        ])
        voiceActions.orientation = .horizontal
        voiceActions.alignment = .centerY
        voiceActions.spacing = 8

        let stack = NSStackView(views: [
            Self.titleLabel("ChatGPT Speech"),
            Self.detailLabel("Choose voices and speaking rate."),
            Self.spacer(8),
            makeRow(label: "Chinese Voice", control: chineseVoicePopup),
            makeRow(label: "English Voice", control: englishVoicePopup),
            makeRow(label: "Speech Rate", control: rateControls),
            makeRow(label: "Follow Speech on Page", control: followSpeechSwitch),
            Self.detailLabel("Follow spoken content on the active page."),
            Self.spacer(4),
            previewControls,
            Self.spacer(4),
            voiceActions,
            Self.detailLabel("Opens macOS voice settings."),
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
        voiceCatalog.refresh()
        synchronizeControls()
    }

    @objc func chineseVoiceChanged(_ sender: NSPopUpButton) {
        preferencesStore.setVoiceIdentifier(
            sender.selectedItem?.representedObject as? String,
            for: .chinese
        )
    }

    @objc func englishVoiceChanged(_ sender: NSPopUpButton) {
        preferencesStore.setVoiceIdentifier(
            sender.selectedItem?.representedObject as? String,
            for: .english
        )
    }

    @objc func speechRateChanged(_ sender: NSSlider) {
        preferencesStore.speechRate = Float(sender.doubleValue)
        updateSpeechRateLabel()
    }

    @objc func followSpeechChanged(_ sender: NSSwitch) {
        preferencesStore.followSpeechOnPage = sender.state == .on
    }

    @objc func chinesePreview(_ sender: NSButton) {
        playPreview("这是 FloatTabs 中文语音测试。")
    }

    @objc func englishPreview(_ sender: NSButton) {
        playPreview("This is a FloatTabs English voice test.")
    }

    @objc func mixedPreview(_ sender: NSButton) {
        playPreview("这是中文测试。This is an English test.继续中文内容。")
    }

    @objc func refreshVoices(_ sender: NSButton) {
        voiceCatalog.refresh()
        synchronizeControls()
    }

    @objc func manageHighQualityVoices(_ sender: NSButton) {
        lastSystemSettingsOpenResult = SpeechSystemSettings.openHighQualityVoices(
            using: systemSettingsOpener
        )
    }

    private func playPreview(_ text: String) {
        guard let previewHandler else { return }
        let requests = SpeechLanguageRouter.utteranceRequests(for: text)
        previewHandler(requests)
    }

    private func configureVoicePopup(
        _ popup: NSPopUpButton,
        role: SpeechLanguageRole
    ) {
        popup.removeAllItems()
        popup.addItem(withTitle: SpeechVoiceCatalog.defaultVoiceDisplayName(for: role))
        for voice in voiceCatalog.voices(for: role) {
            popup.addItem(withTitle: voice.displayName(for: role))
            popup.lastItem?.representedObject = voice.identifier
        }
    }

    private func synchronizeControls() {
        guard isViewLoaded else { return }
        configureVoicePopup(chineseVoicePopup, role: .chinese)
        configureVoicePopup(englishVoicePopup, role: .english)
        selectVoice(
            in: chineseVoicePopup,
            identifier: preferencesStore.chineseVoiceIdentifier,
            role: .chinese
        )
        selectVoice(
            in: englishVoicePopup,
            identifier: preferencesStore.englishVoiceIdentifier,
            role: .english
        )
        speechRateSlider.doubleValue = Double(preferencesStore.speechRate)
        updateSpeechRateLabel()
        followSpeechSwitch.state = preferencesStore.followSpeechOnPage ? .on : .off
        // System Automatic remains a valid route even when the catalog is
        // temporarily empty while macOS refreshes its downloadable voices.
        let hasPreviewHandler = previewHandler != nil
        chinesePreviewButton.isEnabled = hasPreviewHandler
        englishPreviewButton.isEnabled = hasPreviewHandler
        mixedPreviewButton.isEnabled = hasPreviewHandler
    }

    private func selectVoice(
        in popup: NSPopUpButton,
        identifier: String?,
        role: SpeechLanguageRole
    ) {
        guard let identifier else {
            popup.selectItem(at: 0)
            return
        }
        guard let index = popup.itemArray.firstIndex(where: {
            ($0.representedObject as? String) == identifier
        }) else {
            popup.selectItem(at: 0)
            return
        }
        popup.selectItem(at: index)
    }

    private func updateSpeechRateLabel() {
        speechRateValueLabel.stringValue = String(format: "%.2f", preferencesStore.speechRate)
    }

    private func makeRow(label text: String, control: NSView) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.widthAnchor.constraint(equalToConstant: 150).isActive = true
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        return row
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
final class NotificationsSettingsViewController: NSViewController {
    private let preferencesStore: AppPreferencesStore
    private let assetStore: AttentionSoundAssetStore
    private let attentionSoundPlayer: AttentionSoundPlaying
    private let availableSoundNames: [String]
    private let errorPresenter: (Error) -> Void

    private let enabledSwitch = NSSwitch()
    let soundPopup = NSPopUpButton()
    let importAudioButton = NSButton(title: "Import Audio…", target: nil, action: nil)
    let removeSelectedAudioButton = NSButton(title: "Remove Selected", target: nil, action: nil)
    let volumeSlider = NSSlider(value: 100, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let volumeValueLabel = NSTextField(labelWithString: "100%")
    let previewButton = NSButton(title: "Play Preview", target: nil, action: nil)

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
        title = "Notifications"
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

        let enabledRow = makeRow(label: "Play sound when ChatGPT is ready", control: enabledSwitch)
        let soundRow = makeRow(label: "Ready Sound", control: soundPopup)
        let audioActions = NSStackView(views: [importAudioButton, removeSelectedAudioButton])
        audioActions.orientation = .horizontal
        audioActions.alignment = .centerY
        audioActions.spacing = 8
        let volumeControls = NSStackView(views: [volumeSlider, volumeValueLabel])
        volumeControls.orientation = .horizontal
        volumeControls.alignment = .centerY
        volumeControls.spacing = 10
        let volumeRow = makeRow(label: "Volume", control: volumeControls)

        let stack = NSStackView(views: [
            Self.titleLabel("Ready Alerts"),
            Self.detailLabel("Play a sound when ChatGPT is ready."),
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
        panel.title = "Import Ready Audio"
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

        soundPopup.addItem(withTitle: "System")
        soundPopup.lastItem?.isEnabled = false
        for name in availableSoundNames {
            soundPopup.addItem(withTitle: name)
            soundPopup.lastItem?.representedObject = Self.systemSelection(name)
        }

        soundPopup.menu?.addItem(NSMenuItem.separator())
        soundPopup.addItem(withTitle: "Custom")
        soundPopup.lastItem?.isEnabled = false
        for asset in preferencesStore.customAttentionSoundLibrary {
            let isMissing = assetStore.existingURL(for: asset) == nil
            let title = asset.displayName + (isMissing ? " — Missing" : "")
            soundPopup.addItem(withTitle: title)
            soundPopup.lastItem?.representedObject = Self.customSelection(asset.id)
        }

        soundPopup.menu?.addItem(NSMenuItem.separator())
        soundPopup.addItem(withTitle: "Import Audio…")
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
        labels: SimpleViewportPreset.allCases.map(\.displayName),
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
        title = "Appearance"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()

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
            [Self.detailInlineLabel("Custom viewport"), customFixedWidthField, multiplication, customFixedHeightField],
            in: .leading
        )
        customFixedSizeRow.orientation = .horizontal
        customFixedSizeRow.alignment = .centerY
        customFixedSizeRow.spacing = 8

        fixedSizeSection.setViews([
            Self.titleLabel("Fixed Window Size"),
            Self.detailLabel("Shared size used by every Tab in Fixed mode."),
            fixedSizeControl,
            customFixedSizeRow,
        ], in: .leading)
        fixedSizeSection.orientation = .vertical
        fixedSizeSection.alignment = .leading
        fixedSizeSection.spacing = 7

        let stack = NSStackView(views: [
            Self.titleLabel("Interface Appearance"),
            Self.detailLabel("Choose FloatTabs' appearance."),
            appearanceControl,
            Self.spacer(6),
            Self.titleLabel("Menu Bar"),
            Self.detailLabel("Show the current Web App name in the menu bar."),
            menuBarDisplayControl,
            Self.spacer(6),
            Self.titleLabel("Border Theme"),
            Self.detailLabel("Choose a border style or custom color."),
            borderPalette,
            Self.spacer(6),
            Self.titleLabel("Window Size Behavior"),
            Self.detailLabel("Use each Web App's size or one shared size."),
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
        guard SimpleViewportPreset.allCases.indices.contains(sender.selectedSegment) else { return }
        let preset = SimpleViewportPreset.allCases[sender.selectedSegment]
        guard let size = preset.size else {
            customFixedSizeRow.isHidden = false
            customFixedWidthField.stringValue = Self.sizeText(preferencesStore.fixedViewportSize.width)
            customFixedHeightField.stringValue = Self.sizeText(preferencesStore.fixedViewportSize.height)
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
              width >= Double(AppPreferencesStore.minimumFixedViewportSize.width),
              height >= Double(AppPreferencesStore.minimumFixedViewportSize.height) else {
            NSSound.beep()
            synchronizeFixedSizeControls()
            return
        }
        preferencesStore.fixedViewportSize = CGSize(width: width, height: height)
        synchronizeFixedSizeControls()
    }

    private func configureCustomFixedField(_ field: NSTextField) {
        field.alignment = .right
        field.placeholderString = "px"
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

        let size = preferencesStore.fixedViewportSize
        let preset = SimpleViewportPreset.matching(size) ?? .custom
        fixedSizeControl.selectedSegment = SimpleViewportPreset.allCases.firstIndex(of: preset) ?? 0
        customFixedSizeRow.isHidden = preset != .custom
        customFixedWidthField.stringValue = Self.sizeText(size.width)
        customFixedHeightField.stringValue = Self.sizeText(size.height)
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
private final class BorderThemeSwatchButton: NSButton {
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
    private let embedsInSettingsPage: Bool

    init(embedsInSettingsPage: Bool = false) {
        self.embedsInSettingsPage = embedsInSettingsPage
        super.init(nibName: nil, bundle: nil)
        title = "Shortcuts"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let document = SettingsDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false

        var views: [NSView] = [
            sectionTitle("Global"),
            detailLabel("Show / Hide works everywhere; other shortcuts work in FloatTabs."),
            shortcutRecorderRow("Show / Hide FloatTabs", name: .toggleFloatTabs),
            spacer(10),
            sectionTitle("Slots"),
        ]
        views.append(contentsOf: AppShortcutCatalog.slotBindings.map(shortcutRecorderRow(for:)))
        views.append(contentsOf: [spacer(10), sectionTitle("Navigation")])
        views.append(contentsOf: AppShortcutCatalog.navigationBindings.map(shortcutRecorderRow(for:)))
        views.append(contentsOf: [spacer(10), sectionTitle("View")])
        views.append(contentsOf: AppShortcutCatalog.viewBindings.map(shortcutRecorderRow(for:)))
        views.append(contentsOf: [spacer(10), sectionTitle("Speech")])
        views.append(contentsOf: AppShortcutCatalog.speechBindings.map(shortcutRecorderRow(for:)))
        views.append(contentsOf: [spacer(10), sectionTitle("Mode")])
        views.append(contentsOf: AppShortcutCatalog.residencyBindings.map(shortcutRecorderRow(for:)))
        views.append(contentsOf: [spacer(10), sectionTitle("Application")])
        views.append(contentsOf: AppShortcutCatalog.applicationBindings.map(shortcutRecorderRow(for:)))

        let resetButton = NSButton(
            title: "Reset All to Defaults",
            target: self,
            action: #selector(resetAllShortcuts)
        )
        resetButton.bezelStyle = .rounded
        views.append(contentsOf: [spacer(10), resetButton, spacer(8)])

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
                return .disallow(reason: "This shortcut is already used by “\(conflict)”.")
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
            ("Show / Hide FloatTabs", .toggleFloatTabs),
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
        let resolvedVersion = version.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown"
        return "Version \(resolvedVersion)"
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
    // wrapper the tooltip-tracking view.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }
}

@MainActor
final class PerformanceSettingsViewController: NSViewController {
    private let preferencesStore: AppPreferencesStore
    private let websiteCacheManager: WebsiteCacheManagementClient
    private let embedsInSettingsPage: Bool

    private let warmRetentionPopup = NSPopUpButton()
    private let coldReleasePopup = NSPopUpButton()
    private let websiteCacheUsageLabel = NSTextField(labelWithString: "Unavailable")
    private let websiteCacheLastCleanupLabel = NSTextField(labelWithString: "Never")
    private let websiteCacheAutomaticSwitch = NSSwitch()
    private let websiteCacheRetentionPopup = NSPopUpButton()
    private let websiteCacheMaximumPopup = NSPopUpButton()
    private let releaseWebsiteCacheButton = NSButton(title: "Release Cache…", target: nil, action: nil)
    private let websiteCacheResultLabel = NSTextField(wrappingLabelWithString: "")
    private var isWebsiteCacheReleaseInProgress = false
    private var websiteCacheMeasurementTask: Task<Void, Never>?
    private var isWebsiteCacheMeasurementInFlight = false
    private var websiteCacheMeasurementSequence = 0

    private(set) var displayedWebsiteCacheUsage = "Unavailable"
    private(set) var displayedWebsiteCacheLastCleanup = "Never"
    private(set) var isReleaseCacheEnabled = false
    private(set) var websiteCacheResultMessage = ""
    private(set) var displayedWarmRetention = WarmWebViewRetentionOption.twoMinutes.displayName
    private(set) var displayedColdRelease = ColdWebViewReleaseOption.thirtySeconds.displayName

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

        warmRetentionPopup.addItems(withTitles: WarmWebViewRetentionOption.allCases.map(\.displayName))
        for (index, option) in WarmWebViewRetentionOption.allCases.enumerated() {
            warmRetentionPopup.item(at: index)?.representedObject = option.rawValue
        }
        warmRetentionPopup.target = self
        warmRetentionPopup.action = #selector(warmRetentionChanged(_:))
        warmRetentionPopup.widthAnchor.constraint(equalToConstant: 150).isActive = true

        coldReleasePopup.addItems(withTitles: ColdWebViewReleaseOption.allCases.map(\.displayName))
        for (index, option) in ColdWebViewReleaseOption.allCases.enumerated() {
            coldReleasePopup.item(at: index)?.representedObject = option.rawValue
        }
        coldReleasePopup.target = self
        coldReleasePopup.action = #selector(coldReleaseChanged(_:))
        coldReleasePopup.widthAnchor.constraint(equalToConstant: 150).isActive = true

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
            sectionTitle("Tab Residency"),
            detailLabel("Hot keeps the page active; Warm and Cold release it after idle time."),
            websiteCacheSettingRow("Warm WebView retention", control: warmRetentionPopup),
            websiteCacheSettingRow("Cold release delay", control: coldReleasePopup),
            detailLabel("Choose Hot, Warm, or Cold from each Tab's menu."),
            spacer(10),
            sectionTitle("Website Storage"),
            detailLabel("Only re-downloadable webpage caches are removed."),
            websiteCacheSettingRow("Estimated cache usage", control: websiteCacheUsageLabel),
            websiteCacheSettingRow("Last cleanup", control: websiteCacheLastCleanupLabel),
            websiteCacheSettingRow("Automatically manage cache", control: websiteCacheAutomaticSwitch),
            websiteCacheSettingRow("Remove cache unused for", control: websiteCacheRetentionPopup),
            websiteCacheSettingRow("Maximum cache usage", control: websiteCacheMaximumPopup),
            releaseWebsiteCacheButton,
            websiteCacheResultLabel,
            spacer(8),
            detailLabel("Cache size is an estimate."),
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
        refreshPerformanceSettings()
        refreshWebsiteCache()
        startWebsiteCacheMeasurement()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshPerformanceSettings()
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

    func refreshPerformanceSettings() {
        guard isViewLoaded else { return }
        let warm = WarmWebViewRetentionOption(seconds: preferencesStore.warmWebViewRetentionDelay)
        let cold = ColdWebViewReleaseOption(seconds: preferencesStore.coldWebViewReleaseDelay)
        displayedWarmRetention = warm.displayName
        displayedColdRelease = cold.displayName
        warmRetentionPopup.selectItem(withTitle: warm.displayName)
        coldReleasePopup.selectItem(withTitle: cold.displayName)
    }

    func refreshWebsiteCache() {
        guard isViewLoaded else { return }
        let snapshot = websiteCacheManager.snapshot()
        switch snapshot.measurementState {
        case .calculating:
            displayedWebsiteCacheUsage = "Calculating…"
        case .available:
            displayedWebsiteCacheUsage = Self.formatByteCount(snapshot.estimatedBytes)
        case .unavailable:
            displayedWebsiteCacheUsage = "Unavailable"
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

    @objc private func warmRetentionChanged(_ sender: NSPopUpButton) {
        guard let raw = (sender.selectedItem?.representedObject as? NSNumber)?.intValue
                ?? (sender.selectedItem?.representedObject as? Int),
              let option = WarmWebViewRetentionOption(rawValue: raw) else { return }
        preferencesStore.warmWebViewRetentionDelay = option.seconds
        refreshPerformanceSettings()
    }

    @objc private func coldReleaseChanged(_ sender: NSPopUpButton) {
        guard let raw = (sender.selectedItem?.representedObject as? NSNumber)?.intValue
                ?? (sender.selectedItem?.representedObject as? Int),
              let option = ColdWebViewReleaseOption(rawValue: raw) else { return }
        preferencesStore.coldWebViewReleaseDelay = option.seconds
        refreshPerformanceSettings()
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
        alert.messageText = "Release Website Cache?"
        alert.informativeText = "This clears only re-downloadable webpage caches. Cookies, login state and persistent website data are not cleared. Currently open pages may reload."
        alert.addButton(withTitle: "Release Cache")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.isWebsiteCacheReleaseInProgress = true
            self.websiteCacheResultMessage = "Releasing cache…"
            self.refreshWebsiteCache()
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let result = try await self.websiteCacheManager.releaseCache()
                    self.websiteCacheResultMessage = Self.cleanupResultText(result)
                } catch {
                    self.websiteCacheResultMessage = "Cache release failed: \(error.localizedDescription)"
                }
                self.isWebsiteCacheReleaseInProgress = false
                self.refreshWebsiteCache()
            }
        }
    }

    static func formatByteCount(_ bytes: Int64?) -> String {
        guard let bytes else { return "Unavailable" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    static func formatDate(_ date: Date?) -> String {
        guard let date else { return "Never" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func cleanupResultText(_ result: WebsiteCacheCleanupResult) -> String {
        let released = formatByteCount(result.releasedBytes)
        if result.estimatedBytesBefore == nil || result.estimatedBytesAfter == nil {
            return "Cache released from \(result.cleanedProfileCount) Profile(s), \(result.cleanedRecordCount) record(s). Size unavailable."
        }
        return "Estimated usage: \(formatByteCount(result.estimatedBytesBefore)) → \(formatByteCount(result.estimatedBytesAfter)). Released \(released) across \(result.cleanedProfileCount) Profile(s), \(result.cleanedRecordCount) record(s)."
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
    private let newProfileButton = NSButton(title: "+ New Profile", target: nil, action: nil)
    private let profileSupportLabel = NSTextField(wrappingLabelWithString: "")

    // Read-only derived seams keep UI tests focused on the injected snapshot;
    // they are never used as an authoritative Profile model.
    private(set) var displayedBrowserProfileNames: [String] = []
    private(set) var displayedBrowserProfileColors: [BrowserProfileColor] = []
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
            sectionTitle("Profiles"),
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
        displayedBrowserProfileNames = [snapshot.defaultProfilePresentation.name]
            + snapshot.customProfiles.map(\.name)
        displayedBrowserProfileColors = [snapshot.defaultProfilePresentation.color]
            + snapshot.customProfiles.map(\.color)
        displayedBrowserProfileActionTitles = [["Rename…"]] + snapshot.customProfiles.map { _ in
            ["Rename…", "Delete…"]
        }
        displayedBrowserProfileDeleteEnabled = [false] + snapshot.customProfiles.map {
            !snapshot.referencedProfileIDs.contains($0.id)
        }
        displayedBrowserProfileDeleteToolTips = [nil] + snapshot.customProfiles.map { profile in
            Self.profileDeletionTooltip(
                for: snapshot.referencingWebAppNamesByProfileID[profile.id] ?? []
            )
        }
        isNewProfileEnabled = snapshot.customProfilesSupported
        newProfileButton.isEnabled = snapshot.customProfilesSupported
        profileSupportDescription = snapshot.customProfilesSupported
            ? "Each Profile uses its own FloatTabs website data."
            : "Additional Profiles require macOS 14 or later."
        profileSupportLabel.stringValue = profileSupportDescription

        for arrangedSubview in profileRowsStack.arrangedSubviews {
            profileRowsStack.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }

        profileRowsStack.addArrangedSubview(
            makeDefaultProfileRow(snapshot.defaultProfilePresentation)
        )
        for profile in snapshot.customProfiles {
            profileRowsStack.addArrangedSubview(
                makeCustomProfileRow(
                    profile,
                    isReferenced: snapshot.referencedProfileIDs.contains(profile.id),
                    referencingWebAppNames: snapshot.referencingWebAppNamesByProfileID[profile.id] ?? []
                )
            )
        }
    }

    /// Internal action seam used by focused tests to exercise the same trim
    /// and manager handoff used by the New Profile alert.
    func submitNewProfileNameForTesting(_ rawName: String) {
        guard browserProfileManager.snapshot().customProfilesSupported else { return }
        submitNewProfileName(rawName)
    }

    static func trimmedProfileName(_ rawName: String) -> String? {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func makeDefaultProfileRow(
        _ presentation: DefaultBrowserProfilePresentation
    ) -> NSView {
        let label = NSTextField(labelWithString: presentation.name)
        label.font = .systemFont(ofSize: 12)
        label.widthAnchor.constraint(equalToConstant: 230).isActive = true

        let renameButton = NSButton(
            title: "Rename…",
            target: self,
            action: #selector(renameDefaultProfile)
        )
        renameButton.bezelStyle = .rounded

        let colorPopup = makeProfileColorPopup(
            profileID: nil,
            color: presentation.color
        )
        let row = NSStackView(views: [label, renameButton, colorPopup])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func makeCustomProfileRow(
        _ profile: BrowserProfile,
        isReferenced: Bool,
        referencingWebAppNames: [String]
    ) -> NSView {
        let nameLabel = NSTextField(labelWithString: profile.name)
        nameLabel.font = .systemFont(ofSize: 12)
        nameLabel.widthAnchor.constraint(equalToConstant: 230).isActive = true

        let renameButton = NSButton(
            title: "Rename…",
            target: self,
            action: #selector(renameProfile(_:))
        )
        renameButton.identifier = NSUserInterfaceItemIdentifier(profile.id.uuidString)
        renameButton.bezelStyle = .rounded

        let deleteButton = NSButton(
            title: "Delete…",
            target: self,
            action: #selector(deleteProfile(_:))
        )
        deleteButton.identifier = NSUserInterfaceItemIdentifier(profile.id.uuidString)
        deleteButton.bezelStyle = .rounded
        deleteButton.isEnabled = !isReferenced
        let deleteToolTip = Self.profileDeletionTooltip(for: referencingWebAppNames)
        deleteButton.toolTip = deleteToolTip

        let deleteControl: NSView
        if isReferenced, let deleteToolTip {
            deleteControl = ProfileDeleteTooltipView(
                button: deleteButton,
                toolTip: deleteToolTip
            )
        } else {
            deleteControl = deleteButton
        }

        let colorPopup = makeProfileColorPopup(
            profileID: profile.id,
            color: profile.color
        )
        let actions = NSStackView(views: [renameButton, colorPopup, deleteControl])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8

        let row = NSStackView(views: [nameLabel, actions])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10

        guard isReferenced else { return row }
        let detailText = referencingWebAppNames.isEmpty
            ? "This Profile is used by one or more Web Apps."
            : "Used by \(referencingWebAppNames.joined(separator: ", "))."
        let detail = detailLabel(detailText)
        let wrapper = NSStackView(views: [row, detail])
        wrapper.orientation = .vertical
        wrapper.alignment = .leading
        wrapper.spacing = 3
        return wrapper
    }

    static func profileDeletionTooltip(for webAppNames: [String]) -> String? {
        guard !webAppNames.isEmpty else { return nil }
        return "Used by Tabs: \(webAppNames.joined(separator: ", ")). Switch them to another Profile before deleting."
    }

    private func makeProfileColorPopup(
        profileID: UUID?,
        color: BrowserProfileColor
    ) -> NSPopUpButton {
        let popup = NSPopUpButton()
        popup.identifier = NSUserInterfaceItemIdentifier(
            profileID?.uuidString ?? "default"
        )
        popup.target = self
        popup.action = #selector(profileColorPopupChanged(_:))
        popup.toolTip = "Profile label color"
        popup.addItems(withTitles: BrowserProfileColorPreset.allCases.map(\.displayName))
        for (index, preset) in BrowserProfileColorPreset.allCases.enumerated() {
            popup.item(at: index)?.representedObject = preset.rawValue
        }
        let selectedPreset = color.preset
        if let index = BrowserProfileColorPreset.allCases.firstIndex(of: selectedPreset) {
            popup.selectItem(at: index)
        }
        popup.widthAnchor.constraint(equalToConstant: 120).isActive = true
        return popup
    }

    @objc private func createProfile() {
        guard browserProfileManager.snapshot().customProfilesSupported,
              let window = view.window else { return }

        let field = NSTextField(string: "")
        field.placeholderString = "Profile name"
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)

        let alert = NSAlert()
        alert.messageText = "New Browser Profile"
        alert.informativeText = "Choose a name for this Profile. It will use separate FloatTabs website data."
        alert.accessoryView = field
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
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
        return profile
    }

    @objc private func renameDefaultProfile() {
        presentRenameProfile(
            id: nil,
            currentName: browserProfileManager.snapshot().defaultProfilePresentation.name
        )
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

        let field = NSTextField(string: currentName)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)

        let alert = NSAlert()
        alert.messageText = "Rename Browser Profile"
        alert.informativeText = "Choose a new name for this Profile. Its website data and identity will remain unchanged."
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            guard let trimmedName = Self.trimmedProfileName(field.stringValue) else {
                self.showProfileError(BrowserProfileManagementError.invalidName)
                return
            }
            do {
                try self.browserProfileManager.rename(id: id, name: trimmedName)
                self.refreshProfiles()
            } catch {
                self.showProfileError(error)
            }
        }
    }

    @objc private func profileColorPopupChanged(_ sender: NSPopUpButton) {
        guard let rawPreset = sender.selectedItem?.representedObject as? String,
              let preset = BrowserProfileColorPreset(rawValue: rawPreset) else {
            return
        }
        let profileIdentifier = sender.identifier?.rawValue ?? "default"
        let profileID = UUID(uuidString: profileIdentifier)
        if preset == .custom {
            let currentColor = browserProfileManager.snapshot().customProfiles.first(where: {
                $0.id == profileID
            })?.color ?? browserProfileManager.snapshot().defaultProfilePresentation.color
            pendingProfileColorIdentifier = profileIdentifier
            let panel = NSColorPanel.shared
            panel.color = currentColor.appKitColor
            panel.isContinuous = true
            panel.setTarget(self)
            panel.setAction(#selector(profileColorPanelChanged(_:)))
            panel.orderFront(nil)
            return
        }

        submitProfileColor(
            profileIdentifier: profileIdentifier,
            color: BrowserProfileColor(preset: preset)
        )
    }

    @objc private func profileColorPanelChanged(_ sender: NSColorPanel) {
        guard let profileIdentifier = pendingProfileColorIdentifier,
              let hex = AppPreferencesStore.hex(from: sender.color) else {
            return
        }
        submitProfileColor(
            profileIdentifier: profileIdentifier,
            color: BrowserProfileColor(preset: .custom, customSRGBHex: hex)
        )
    }

    private var pendingProfileColorIdentifier: String?

    private func submitProfileColor(
        profileIdentifier: String,
        color: BrowserProfileColor
    ) {
        let profileID = UUID(uuidString: profileIdentifier)
        do {
            try browserProfileManager.setColor(id: profileID, color: color)
            refreshProfiles()
        } catch {
            showProfileError(error)
        }
    }

    @objc private func deleteProfile(_ sender: NSButton) {
        guard let id = profileID(from: sender) else { return }

        let profile: BrowserProfile
        do {
            profile = try profileDeletionCandidate(id: id)
        } catch {
            showProfileError(error)
            return
        }

        guard let window = view.window else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete Browser Profile \"\(profile.name)\"?"
        alert.informativeText = "Deleting this Profile removes its FloatTabs website data, including its saved website sessions for this Profile. This cannot be undone. Apple Passwords and Keychain data are not affected."
        alert.addButton(withTitle: "Delete Profile")
        alert.addButton(withTitle: "Cancel")
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
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }

    private func showProfileError(_ error: Error) {
        showMessage(title: "Profile Operation Failed", detail: error.localizedDescription)
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

/// Compatibility name for existing Profile settings tests and callers. The
/// consolidated Settings UI renders BrowserProfilesSettingsViewController;
/// the legacy backup closures are intentionally ignored because Backup &
/// Restore now has its own presentation controller.
@MainActor
final class AccountLanguageSettingsViewController: BrowserProfilesSettingsViewController {
    init(
        onExportBackup: @escaping GlobalSettingsController.ExportBackupHandler,
        onRestoreBackup: @escaping GlobalSettingsController.RestoreBackupHandler,
        browserProfileManager: BrowserProfileManagementClient = .unavailable
    ) {
        super.init(browserProfileManager: browserProfileManager)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
