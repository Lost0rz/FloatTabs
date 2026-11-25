import AppKit
import UniformTypeIdentifiers

enum GlobalSettingsSection: String, Equatable {
    case interfaceAppearance
    case bookmarks
    case browserProfiles
    case performance
    case readyAlerts
    case unreadTabAttention
    case shortcuts
    case runtimeDiagnostics
    case backupRestore
    case about
}

enum GlobalSettingsPage: CaseIterable, Equatable {
    case general
    case bookmarks
    case profilesStorage
    case alerts
    case shortcuts
    case advanced

    var title: String {
        switch self {
        case .general:
            return L10n.tr("General", "通用")
        case .bookmarks:
            return L10n.tr("Bookmarks", "书签")
        case .profilesStorage:
            return L10n.tr("Profiles & Storage", "配置与存储")
        case .alerts:
            return L10n.tr("Alerts", "提醒与通知")
        case .shortcuts:
            return L10n.tr("Shortcuts", "快捷键")
        case .advanced:
            return L10n.tr("Advanced", "高级")
        }
    }

    var symbol: String {
        switch self {
        case .general:
            return "slider.horizontal.3"
        case .bookmarks:
            return "bookmark"
        case .profilesStorage:
            return "person.2.badge.gearshape"
        case .alerts:
            return "bell.badge"
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
        case .bookmarks:
            return [.bookmarks]
        case .profilesStorage:
            return [.browserProfiles, .performance]
        case .alerts:
            return [.unreadTabAttention, .readyAlerts]
        case .shortcuts:
            return [.shortcuts]
        case .advanced:
            return [.runtimeDiagnostics, .backupRestore, .about]
        }
    }
}

@MainActor
final class SettingsPageViewController: NSViewController {
    let embeddedControllers: [NSViewController]

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
    let exportButton = NSButton(title: L10n.tr("Export Backup…", "导出备份…"), target: nil, action: nil)
    let restoreButton = NSButton(title: L10n.tr("Restore Backup…", "恢复备份…"), target: nil, action: nil)

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
            Self.sectionTitle(L10n.tr("Backup & Restore", "备份与恢复")),
            Self.detailLabel(
                L10n.tr(
                    "Exports settings and Profiles, not website logins or cookies.",
                    "导出应用设置与配置，不包含网站登录态或 Cookie。"
                )
            ),
            actions,
            Self.detailLabel(
                L10n.tr(
                    "A rollback backup is created before restore.",
                    "恢复前会自动创建回滚备份。"
                )
            ),
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
        panel.title = L10n.tr("Export FloatTabs Backup", "导出 FloatTabs 备份")
        panel.nameFieldStringValue = FloatTabsBackupService.suggestedExportFileName()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [backupContentType]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                try self.onExportBackup(url)
                self.showMessage(
                    title: L10n.tr("Backup Exported", "备份已导出"),
                    detail: L10n.tr(
                        "Your FloatTabs configuration backup was saved successfully.",
                        "已成功保存 FloatTabs 配置备份。"
                    )
                )
            } catch {
                self.showError(error)
            }
        }
    }

    @objc private func restoreBackup() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.title = L10n.tr("Restore FloatTabs Backup", "恢复 FloatTabs 备份")
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
        alert.messageText = L10n.tr(
            "Replace current FloatTabs configuration?",
            "替换当前的 FloatTabs 配置？"
        )
        alert.informativeText = L10n.tr(
            "FloatTabs will create a local rollback backup first, then replace current Slot and global settings with the selected backup. Website login/session data is not changed or restored.",
            "FloatTabs 会先创建一个本地回滚备份，然后用所选备份替换当前的标签与全局设置。网站的登录状态和会话数据不会被修改或覆盖。"
        )
        alert.addButton(withTitle: L10n.tr("Restore and Replace", "恢复并替换"))
        alert.addButton(withTitle: L10n.tr("Cancel", "取消"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            do {
                let rollbackURL = try self.onRestoreBackup(url)
                self.showMessage(
                    title: L10n.tr("Backup Restored", "备份已恢复"),
                    detail: L10n.tr(
                        "FloatTabs configuration was restored. A rollback backup was saved at:\n\(rollbackURL.path)",
                        "FloatTabs 配置已恢复。回滚备份已保存至：\n\(rollbackURL.path)"
                    )
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
        alert.addButton(withTitle: L10n.tr("OK", "好"))
        alert.beginSheetModal(for: window)
    }

    private func showError(_ error: Error) {
        showMessage(
            title: L10n.tr("Backup Operation Failed", "备份操作失败"),
            detail: error.localizedDescription
        )
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
            Self.sectionTitle(L10n.tr("About FloatTabs", "关于 FloatTabs")),
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
