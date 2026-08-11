import AppKit
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
        labels: AppAppearanceMode.allCases.map(\.displayName),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let borderThemePopup = NSPopUpButton()
    private let customColorWell = NSColorWell()
    private let windowSizeControl = NSSegmentedControl(
        labels: PanelWindowSizeMode.allCases.map(\.displayName),
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

        appearanceControl.segmentStyle = .rounded
        appearanceControl.target = self
        appearanceControl.action = #selector(appearanceChanged(_:))
        appearanceControl.widthAnchor.constraint(equalToConstant: 250).isActive = true

        borderThemePopup.addItems(withTitles: PanelBorderTheme.allCases.map(\.displayName))
        borderThemePopup.target = self
        borderThemePopup.action = #selector(borderThemeChanged(_:))
        borderThemePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true

        customColorWell.target = self
        customColorWell.action = #selector(customBorderColorChanged(_:))
        customColorWell.widthAnchor.constraint(equalToConstant: 56).isActive = true
        customColorWell.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let borderRow = NSStackView(views: [borderThemePopup, customColorWell])
        borderRow.orientation = .horizontal
        borderRow.alignment = .centerY
        borderRow.spacing = 10

        windowSizeControl.segmentStyle = .rounded
        windowSizeControl.target = self
        windowSizeControl.action = #selector(windowSizeModeChanged(_:))
        windowSizeControl.widthAnchor.constraint(equalToConstant: 280).isActive = true

        let stack = NSStackView(views: [
            Self.titleLabel("Interface Appearance"),
            Self.detailLabel(
                "Changes FloatTabs' native appearance. Websites keep their own CSS and may still respond to WebKit's effective light/dark appearance."
            ),
            appearanceControl,
            Self.spacer(8),
            Self.titleLabel("Border Theme"),
            Self.detailLabel(
                "Rainbow is the default animated outline. Choose a macOS accent color or use Custom for a personal border color."
            ),
            borderRow,
            Self.spacer(8),
            Self.titleLabel("Window Size Behavior"),
            Self.detailLabel(
                "Per Web App follows each Tab's saved size. Fixed keeps one shared window size across all Tabs without overwriting their saved individual sizes."
            ),
            windowSizeControl,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
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

    @objc private func borderThemeChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard PanelBorderTheme.allCases.indices.contains(index) else { return }
        preferencesStore.borderTheme = PanelBorderTheme.allCases[index]
        synchronizeCustomColorState()
    }

    @objc private func customBorderColorChanged(_ sender: NSColorWell) {
        preferencesStore.customBorderColor = sender.color
        if preferencesStore.borderTheme != .custom {
            preferencesStore.borderTheme = .custom
        }
        synchronizeControls()
    }

    @objc private func windowSizeModeChanged(_ sender: NSSegmentedControl) {
        guard PanelWindowSizeMode.allCases.indices.contains(sender.selectedSegment) else { return }
        preferencesStore.windowSizeMode = PanelWindowSizeMode.allCases[sender.selectedSegment]
    }

    private func synchronizeControls() {
        appearanceControl.selectedSegment = AppAppearanceMode.allCases.firstIndex(
            of: preferencesStore.appearanceMode
        ) ?? 0
        borderThemePopup.selectItem(
            at: PanelBorderTheme.allCases.firstIndex(of: preferencesStore.borderTheme) ?? 0
        )
        customColorWell.color = preferencesStore.customBorderColor
        windowSizeControl.selectedSegment = PanelWindowSizeMode.allCases.firstIndex(
            of: preferencesStore.windowSizeMode
        ) ?? 0
        synchronizeCustomColorState()
    }

    private func synchronizeCustomColorState() {
        customColorWell.isEnabled = preferencesStore.borderTheme == .custom
        customColorWell.alphaValue = customColorWell.isEnabled ? 1 : 0.45
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

    private static func spacer(_ height: CGFloat) -> NSView {
        let view = NSView()
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
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
