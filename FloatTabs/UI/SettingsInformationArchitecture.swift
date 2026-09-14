import AppKit
import UniformTypeIdentifiers

enum GlobalSettingsSection: String, Equatable {
    case interfaceAppearance
    case browserProfiles
    case performance
    case readyAlerts
    case speech
    case shortcuts
    case runtimeDiagnostics
    case backupRestore
    case about
}

enum GlobalSettingsPage: CaseIterable, Equatable {
    case general
    case browserPerformance
    case audio
    case shortcuts
    case advanced

    var title: String {
        switch self {
        case .general:
            return "General"
        case .browserPerformance:
            return "Browser"
        case .audio:
            return "Audio"
        case .shortcuts:
            return "Shortcuts"
        case .advanced:
            return "Advanced"
        }
    }

    var symbol: String {
        switch self {
        case .general:
            return "circle.lefthalf.filled"
        case .browserPerformance:
            return "gauge.with.dots.needle.67percent"
        case .audio:
            return "speaker.wave.2"
        case .shortcuts:
            return "keyboard"
        case .advanced:
            return "gearshape.2"
        }
    }

    var sections: [GlobalSettingsSection] {
        switch self {
        case .general:
            return [.interfaceAppearance]
        case .browserPerformance:
            return [.browserProfiles, .performance]
        case .audio:
            return [.readyAlerts, .speech]
        case .shortcuts:
            return [.shortcuts]
        case .advanced:
            return [.runtimeDiagnostics, .backupRestore, .about]
        }
    }
}

@MainActor
final class SettingsPageViewController: NSViewController {
    private let embeddedControllers: [NSViewController]

    init(childViewControllers: [NSViewController]) {
        self.embeddedControllers = childViewControllers
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

        let document = SettingsPageDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = document

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        document.addSubview(stack)

        for childViewController in embeddedControllers {
            addChild(childViewController)
            let childView = childViewController.view
            childView.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(childView)
            childView.widthAnchor.constraint(equalTo: document.widthAnchor).isActive = true
        }

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

            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
        ])

        view = root
    }
}

@MainActor
private final class SettingsPageDocumentView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class BackupRestoreSettingsViewController: NSViewController {
    let exportButton = NSButton(title: "Export Backup…", target: nil, action: nil)
    let restoreButton = NSButton(title: "Restore Backup…", target: nil, action: nil)

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
        exportButton.target = self
        exportButton.action = #selector(exportBackup)
        restoreButton.target = self
        restoreButton.action = #selector(restoreBackup)

        let actions = NSStackView(views: [exportButton, restoreButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 10

        let stack = NSStackView(views: [
            Self.sectionTitle("Backup & Restore"),
            Self.detailLabel("Exports settings and Profiles, not website logins or cookies."),
            actions,
            Self.detailLabel("A rollback backup is created before restore."),
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
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
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

    private static func sectionTitle(_ text: String) -> NSTextField {
        let value = NSTextField(labelWithString: text)
        value.font = .systemFont(ofSize: 13, weight: .semibold)
        return value
    }

    private static func detailLabel(_ text: String) -> NSTextField {
        let value = NSTextField(wrappingLabelWithString: text)
        value.font = .systemFont(ofSize: 12)
        value.textColor = .secondaryLabelColor
        value.maximumNumberOfLines = 0
        value.widthAnchor.constraint(lessThanOrEqualToConstant: 510).isActive = true
        return value
    }
}

@MainActor
final class AboutSettingsViewController: NSViewController {
    private(set) var displayedVersion = ""
    private(set) var displayedLatestFixes = ""

    override func loadView() {
        let root = NSView()
        let versionLabel = NSTextField(labelWithString: AppReleaseInfo.currentVersionDisplay)
        versionLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        versionLabel.textColor = .labelColor
        displayedVersion = versionLabel.stringValue

        displayedLatestFixes = ""

        let stack = NSStackView(views: [
            Self.sectionTitle("About FloatTabs"),
            versionLabel,
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
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
        ])
        view = root
    }

    private static func sectionTitle(_ text: String) -> NSTextField {
        let value = NSTextField(labelWithString: text)
        value.font = .systemFont(ofSize: 13, weight: .semibold)
        return value
    }

    private static func detailLabel(_ text: String) -> NSTextField {
        let value = NSTextField(wrappingLabelWithString: text)
        value.font = .systemFont(ofSize: 12)
        value.textColor = .secondaryLabelColor
        value.maximumNumberOfLines = 0
        value.widthAnchor.constraint(lessThanOrEqualToConstant: 510).isActive = true
        return value
    }
}
