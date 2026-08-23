import AppKit
import KeyboardShortcuts
import UniformTypeIdentifiers

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
            return "Enter a non-empty Profile name other than Default."
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
    let referencedProfileIDs: Set<UUID>
    let customProfilesSupported: Bool
}

@MainActor
struct BrowserProfileManagementClient {
    typealias SnapshotHandler = () -> BrowserProfileManagementSnapshot
    typealias CreateHandler = (String) throws -> BrowserProfile
    typealias RenameHandler = (UUID, String) throws -> Void
    typealias DeleteHandler = (UUID) async throws -> Void

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

    func rename(id: UUID, name: String) throws {
        try renameHandler(id, name)
    }

    func delete(id: UUID) async throws {
        try await deleteHandler(id)
    }
}

@MainActor
final class GlobalSettingsController: NSObject, NSWindowDelegate {
    typealias ExportBackupHandler = (URL) throws -> Void
    typealias RestoreBackupHandler = (URL) throws -> URL

    private let preferencesStore: AppPreferencesStore
    private let attentionSoundPlayer: AttentionSoundPlaying
    private let onExportBackup: ExportBackupHandler
    private let onRestoreBackup: RestoreBackupHandler
    private let browserProfileManager: BrowserProfileManagementClient
    private lazy var settingsWindow: NSWindow = makeWindow()

    init(
        preferencesStore: AppPreferencesStore,
        attentionSoundPlayer: AttentionSoundPlaying = AttentionSoundPlayer(),
        onExportBackup: @escaping ExportBackupHandler = { _ in },
        onRestoreBackup: @escaping RestoreBackupHandler = { _ in throw FloatTabsBackupError.restoreFailed },
        browserProfileManager: BrowserProfileManagementClient = .unavailable
    ) {
        self.preferencesStore = preferencesStore
        self.attentionSoundPlayer = attentionSoundPlayer
        self.onExportBackup = onExportBackup
        self.onRestoreBackup = onRestoreBackup
        self.browserProfileManager = browserProfileManager
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

        addTab(
            title: "Appearance",
            symbol: "circle.lefthalf.filled",
            controller: AppearanceSettingsViewController(preferencesStore: preferencesStore),
            to: tabs
        )
        addTab(
            title: "Notifications",
            symbol: "bell.badge",
            controller: NotificationsSettingsViewController(
                preferencesStore: preferencesStore,
                attentionSoundPlayer: attentionSoundPlayer
            ),
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
                onRestoreBackup: onRestoreBackup,
                browserProfileManager: browserProfileManager
            ),
            to: tabs
        )

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
final class NotificationsSettingsViewController: NSViewController {
    private let preferencesStore: AppPreferencesStore
    private let attentionSoundPlayer: AttentionSoundPlaying
    private let availableSoundNames: [String]

    private let enabledSwitch = NSSwitch()
    let soundPopup = NSPopUpButton()
    let volumeSlider = NSSlider(value: 100, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let volumeValueLabel = NSTextField(labelWithString: "100%")
    let previewButton = NSButton(title: "Play Preview", target: nil, action: nil)

    init(
        preferencesStore: AppPreferencesStore,
        attentionSoundPlayer: AttentionSoundPlaying,
        availableSoundNames: [String]? = nil
    ) {
        self.preferencesStore = preferencesStore
        self.attentionSoundPlayer = attentionSoundPlayer
        self.availableSoundNames = availableSoundNames ?? AttentionSound.availableNames()
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

        soundPopup.addItems(withTitles: availableSoundNames)
        soundPopup.target = self
        soundPopup.action = #selector(soundChanged(_:))
        soundPopup.widthAnchor.constraint(equalToConstant: 180).isActive = true

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

        let enabledRow = makeRow(label: "Play sound when ChatGPT is ready", control: enabledSwitch)
        let soundRow = makeRow(label: "Sound", control: soundPopup)
        let volumeControls = NSStackView(views: [volumeSlider, volumeValueLabel])
        volumeControls.orientation = .horizontal
        volumeControls.alignment = .centerY
        volumeControls.spacing = 10
        let volumeRow = makeRow(label: "Volume", control: volumeControls)

        let stack = NSStackView(views: [
            Self.titleLabel("ChatGPT Ready Alerts"),
            Self.detailLabel(
                "Plays when a new ChatGPT completion enters Ready attention.\nNo sound is played when the completion is already being viewed."
            ),
            Self.spacer(8),
            enabledRow,
            soundRow,
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
        guard let name = sender.selectedItem?.title else { return }
        preferencesStore.attentionSoundName = name
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

    /// The single preview path shared by the sound popup, the volume slider,
    /// and the Play Preview button. It always previews the persisted UI
    /// values through the production player, so a zero volume stays a valid
    /// silent configuration and it works even while the automatic Ready
    /// alert switch is off — that switch only gates the real Ready event.
    private func previewCurrentSound() {
        attentionSoundPlayer.play(
            soundName: preferencesStore.attentionSoundName,
            volume: preferencesStore.attentionSoundVolume
        )
    }

    private func synchronizeControls() {
        guard isViewLoaded else { return }
        enabledSwitch.state = preferencesStore.attentionSoundEnabled ? .on : .off

        let preferredName = preferencesStore.attentionSoundName
        let selectedName: String?
        if availableSoundNames.contains(preferredName) {
            selectedName = preferredName
        } else if availableSoundNames.contains(AppPreferencesStore.defaultAttentionSoundName) {
            selectedName = AppPreferencesStore.defaultAttentionSoundName
        } else {
            selectedName = availableSoundNames.first
        }
        if let selectedName {
            soundPopup.selectItem(withTitle: selectedName)
            if selectedName != preferredName {
                preferencesStore.attentionSoundName = selectedName
            }
        }
        soundPopup.isEnabled = selectedName != nil
        previewButton.isEnabled = selectedName != nil

        let volumePercent = preferencesStore.attentionSoundVolume * 100
        volumeSlider.doubleValue = volumePercent
        updateVolumeLabel(volumePercent)
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
            Self.detailLabel(
                "This is the shared viewport used by every Tab in Fixed mode. Resizing the FloatTabs window outside Settings updates this same saved value."
            ),
            fixedSizeControl,
            customFixedSizeRow,
        ], in: .leading)
        fixedSizeSection.orientation = .vertical
        fixedSizeSection.alignment = .leading
        fixedSizeSection.spacing = 7

        let stack = NSStackView(views: [
            Self.titleLabel("Interface Appearance"),
            Self.detailLabel(
                "Changes FloatTabs' native appearance. Websites keep their own CSS and may still respond to WebKit's effective light/dark appearance."
            ),
            appearanceControl,
            Self.spacer(6),
            Self.titleLabel("Menu Bar"),
            Self.detailLabel(
                "Choose whether the status item shows the current Web App name beside its favicon."
            ),
            menuBarDisplayControl,
            Self.spacer(6),
            Self.titleLabel("Border Theme"),
            Self.detailLabel(
                "Choose the outline directly. Rainbow keeps the animated outline; the final swatch is your custom color."
            ),
            borderPalette,
            Self.spacer(6),
            Self.titleLabel("Window Size Behavior"),
            Self.detailLabel(
                "Per Web App follows each Tab's saved size. Fixed uses one shared size without overwriting any saved individual Web App size."
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
private final class ShortcutsSettingsViewController: NSViewController {
    override func loadView() {
        let root = NSView()
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true

        let document = SettingsDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = document

        var views: [NSView] = [
            sectionTitle("Global"),
            detailLabel(
                "Show / Hide works from other apps. All remaining shortcuts below are app-local and only act while FloatTabs is active."
            ),
            shortcutRecorderRow("Show / Hide FloatTabs", name: .toggleFloatTabs),
            spacer(10),
            sectionTitle("Slots"),
        ]
        views.append(contentsOf: AppShortcutCatalog.slotBindings.map(shortcutRecorderRow(for:)))
        views.append(contentsOf: [spacer(10), sectionTitle("Navigation")])
        views.append(contentsOf: AppShortcutCatalog.navigationBindings.map(shortcutRecorderRow(for:)))
        views.append(contentsOf: [spacer(10), sectionTitle("View")])
        views.append(contentsOf: AppShortcutCatalog.viewBindings.map(shortcutRecorderRow(for:)))
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

            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: document.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20),
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
    static let latestFixes = [
        "ChatGPT completions now enter an unseen Ready state with a red Tab indicator and menu-bar attention count.",
        "Ready alerts can use a configurable macOS system sound, per-alert volume, and instant Settings previews.",
        "Committed ChatGPT navigation now rejects stale document observations until the current page re-establishes its authorized baseline.",
        "The menu-bar favicon follows the selected Slot's committed site while attention remains runtime-only.",
    ]

    static func displayVersion(shortVersion: String?, build: String?) -> String {
        let version = shortVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        let buildNumber = build?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedVersion = version.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown"
        guard let buildNumber, !buildNumber.isEmpty else {
            return "Version \(resolvedVersion)"
        }
        return "Version \(resolvedVersion) (Build \(buildNumber))"
    }

    static var currentVersionDisplay: String {
        displayVersion(
            shortVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
    }

    static var latestFixesDisplay: String {
        latestFixes.map { "• \($0)" }.joined(separator: "\n")
    }
}

@MainActor
final class AccountLanguageSettingsViewController: NSViewController {
    private let onExportBackup: GlobalSettingsController.ExportBackupHandler
    private let onRestoreBackup: GlobalSettingsController.RestoreBackupHandler
    private let browserProfileManager: BrowserProfileManagementClient

    private let profileRowsStack = NSStackView()
    private let newProfileButton = NSButton(title: "+ New Profile", target: nil, action: nil)
    private let profileSupportLabel = NSTextField(wrappingLabelWithString: "")

    // Read-only derived seams keep UI tests focused on the injected snapshot;
    // they are never used as an authoritative Profile model.
    private(set) var displayedBrowserProfileNames: [String] = []
    private(set) var displayedBrowserProfileActionTitles: [[String]] = []
    private(set) var isNewProfileEnabled = false
    private(set) var profileSupportDescription = ""

    init(
        onExportBackup: @escaping GlobalSettingsController.ExportBackupHandler,
        onRestoreBackup: @escaping GlobalSettingsController.RestoreBackupHandler,
        browserProfileManager: BrowserProfileManagementClient = .unavailable
    ) {
        self.onExportBackup = onExportBackup
        self.onRestoreBackup = onRestoreBackup
        self.browserProfileManager = browserProfileManager
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true

        let document = SettingsDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = document

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

        let versionLabel = NSTextField(labelWithString: AppReleaseInfo.currentVersionDisplay)
        versionLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        versionLabel.textColor = .labelColor

        let stack = NSStackView(views: [
            sectionTitle("Account"),
            detailLabel(
                "FloatTabs V1 is local-only. It does not require a FloatTabs cloud account or sync service."
            ),
            spacer(8),
            sectionTitle("Profiles"),
            profileRowsStack,
            profileSupportLabel,
            newProfileButton,
            spacer(8),
            sectionTitle("Backup & Restore"),
            detailLabel(
                "Backups include Web App/Slot configuration, rendering and resource settings, global appearance, ChatGPT Ready notification settings, Fixed shared window size, window-size switching preference, and the global Show/Hide shortcut."
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
            spacer(14),
            sectionTitle("About FloatTabs"),
            versionLabel,
            detailLabel("Latest fixes in this build:"),
            detailLabel(AppReleaseInfo.latestFixesDisplay),
            spacer(8),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
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

            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: document.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20),
        ])
        view = root
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
        displayedBrowserProfileNames = ["Default"] + snapshot.customProfiles.map(\.name)
        displayedBrowserProfileActionTitles = [[]] + snapshot.customProfiles.map { _ in
            ["Rename…", "Delete…"]
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

        profileRowsStack.addArrangedSubview(makeDefaultProfileRow())
        for profile in snapshot.customProfiles {
            profileRowsStack.addArrangedSubview(
                makeCustomProfileRow(
                    profile,
                    isReferenced: snapshot.referencedProfileIDs.contains(profile.id)
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

    private func makeDefaultProfileRow() -> NSView {
        let label = NSTextField(labelWithString: "Default")
        label.font = .systemFont(ofSize: 12)
        label.widthAnchor.constraint(equalToConstant: 230).isActive = true
        let row = NSStackView(views: [label])
        row.orientation = .horizontal
        row.alignment = .centerY
        return row
    }

    private func makeCustomProfileRow(
        _ profile: BrowserProfile,
        isReferenced: Bool
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

        let actions = NSStackView(views: [renameButton, deleteButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8

        let row = NSStackView(views: [nameLabel, actions])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10

        guard isReferenced else { return row }
        let detail = detailLabel("This Profile is used by one or more Web Apps.")
        let wrapper = NSStackView(views: [row, detail])
        wrapper.orientation = .vertical
        wrapper.alignment = .leading
        wrapper.spacing = 3
        return wrapper
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

    @objc private func renameProfile(_ sender: NSButton) {
        guard let id = profileID(from: sender),
              let currentName = browserProfileManager.snapshot().customProfiles.first(where: {
                  $0.id == id
              })?.name,
              let window = view.window else { return }

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

    @objc private func deleteProfile(_ sender: NSButton) {
        guard let id = profileID(from: sender),
              let profile = browserProfileManager.snapshot().customProfiles.first(where: {
                  $0.id == id
              }),
              let window = view.window else { return }

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
                    detail: "FloatTabs configuration was restored. A rollback backup was saved at:\n\(rollbackURL.path)"
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
