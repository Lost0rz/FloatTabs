import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
struct BookmarkManagementClient {
    var folders: () -> [BookmarkFolder]
    var bookmarks: () -> [BookmarkItem]
    var browserProfiles: () -> [BrowserProfileMenuOption]
    var createFolder: (String, UUID?) -> BookmarkFolder?
    var renameFolder: (UUID, String) -> Bool
    var deleteFolder: (UUID) -> Bool
    var addBookmark: (String, URL, UUID?, String?, WebsiteMode?, UUID?) -> BookmarkItem?
    var updateBookmark: (UUID, String, URL, UUID?, String?, WebsiteMode?, UUID?) -> Bool
    var deleteBookmark: (UUID) -> Bool
    var importHTML: (String) -> (foldersAdded: Int, bookmarksAdded: Int)
    var exportHTML: () -> String
    var openBookmarkAsTab: (BookmarkItem) -> Void

    static let unavailable = BookmarkManagementClient(
        folders: { [] },
        bookmarks: { [] },
        browserProfiles: { [.defaultProfile()] },
        createFolder: { _, _ in nil },
        renameFolder: { _, _ in false },
        deleteFolder: { _ in false },
        addBookmark: { _, _, _, _, _, _ in nil },
        updateBookmark: { _, _, _, _, _, _, _ in false },
        deleteBookmark: { _ in false },
        importHTML: { _ in (0, 0) },
        exportHTML: { "" },
        openBookmarkAsTab: { _ in }
    )
}

@MainActor
final class BookmarksSettingsViewController: NSViewController {
    private enum FolderSelection: Equatable {
        case all
        case general
        case custom(UUID)
    }

    private let client: BookmarkManagementClient
    private let embedsInSettingsPage: Bool

    private var selectedFolder: FolderSelection = .all
    private let folderPopup = NSPopUpButton()
    private let newFolderButton = NSButton(title: L10n.tr("New Folder…", "新建文件夹…"), target: nil, action: nil)
    private let renameFolderButton = NSButton(title: L10n.tr("Rename Folder…", "重命名文件夹…"), target: nil, action: nil)
    private let deleteFolderButton = NSButton(title: L10n.tr("Delete Folder", "删除文件夹"), target: nil, action: nil)
    private let addBookmarkButton = NSButton(title: L10n.tr("Add Bookmark…", "添加书签…"), target: nil, action: nil)
    private let importHTMLButton = NSButton(title: L10n.tr("Import HTML…", "导入 HTML…"), target: nil, action: nil)
    private let exportHTMLButton = NSButton(title: L10n.tr("Export HTML…", "导出 HTML…"), target: nil, action: nil)
    private let listStack = NSStackView()
    private let countLabel = NSTextField(labelWithString: "")

    init(
        client: BookmarkManagementClient = .unavailable,
        embedsInSettingsPage: Bool = true
    ) {
        self.client = client
        self.embedsInSettingsPage = embedsInSettingsPage
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        let titleLabel = Self.sectionTitle(L10n.tr("Bookmarks", "书签"))
        let subtitleLabel = Self.detailLabel(
            L10n.tr(
                "Save favorite web apps in folders and open or reuse them anytime from Add Web App.",
                "将常用网页应用分类收藏到文件夹中，随时在“添加网页应用”中快速调用或打开。"
            )
        )

        folderPopup.target = self
        folderPopup.action = #selector(folderSelectionChanged(_:))
        folderPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true

        newFolderButton.target = self
        newFolderButton.action = #selector(createFolderClicked)
        renameFolderButton.target = self
        renameFolderButton.action = #selector(renameFolderClicked)
        deleteFolderButton.target = self
        deleteFolderButton.action = #selector(deleteFolderClicked)
        addBookmarkButton.target = self
        addBookmarkButton.action = #selector(addBookmarkClicked)
        addBookmarkButton.bezelStyle = .rounded
        addBookmarkButton.keyEquivalent = ""

        importHTMLButton.target = self
        importHTMLButton.action = #selector(importHTMLClicked)
        importHTMLButton.bezelStyle = .rounded
        importHTMLButton.toolTip = L10n.tr(
            "Import Chrome or Safari Netscape Bookmark HTML file",
            "导入 Chrome 或 Safari 导出的 Netscape 书签 HTML 文件"
        )

        exportHTMLButton.target = self
        exportHTMLButton.action = #selector(exportHTMLClicked)
        exportHTMLButton.bezelStyle = .rounded
        exportHTMLButton.toolTip = L10n.tr(
            "Export all bookmarks & folders in Chrome/Safari HTML format",
            "以 Chrome / Safari 兼容的 HTML 格式导出全部书签与文件夹"
        )

        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor

        let folderToolbar = NSStackView(views: [
            folderPopup,
            newFolderButton,
            renameFolderButton,
            deleteFolderButton,
        ])
        folderToolbar.orientation = .horizontal
        folderToolbar.alignment = .centerY
        folderToolbar.spacing = 6

        let actionRow = NSStackView(views: [
            addBookmarkButton,
            importHTMLButton,
            exportHTMLButton,
            countLabel,
        ])
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 10

        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 6
        listStack.translatesAutoresizingMaskIntoConstraints = false

        let mainStack = NSStackView(views: [
            titleLabel,
            subtitleLabel,
            folderToolbar,
            actionRow,
            listStack,
        ])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 10
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(mainStack)

        let topInset: CGFloat = embedsInSettingsPage ? 20 : 24
        let bottomInset: CGFloat = embedsInSettingsPage ? -16 : -24
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            mainStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            mainStack.topAnchor.constraint(equalTo: root.topAnchor, constant: topInset),
            mainStack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: bottomInset),
            listStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
        ])

        view = root
        reloadData()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        reloadData()
    }

    func reloadData() {
        guard isViewLoaded else { return }
        let folders = client.folders()
        if case let .custom(folderID) = selectedFolder,
           !folders.contains(where: { $0.id == folderID }) {
            selectedFolder = .all
        }

        rebuildFolderPopup(folders: folders)
        let customFolderSelected: Bool = {
            if case .custom = selectedFolder { return true }
            return false
        }()
        renameFolderButton.isEnabled = customFolderSelected
        deleteFolderButton.isEnabled = customFolderSelected

        let allBookmarks = client.bookmarks()
        let filteredBookmarks: [BookmarkItem] = switch selectedFolder {
        case .all:
            allBookmarks
        case .general:
            allBookmarks.filter { $0.folderID == nil }
        case let .custom(folderID):
            allBookmarks.filter { $0.folderID == folderID }
        }
        countLabel.stringValue = filteredBookmarks.count == 1
            ? L10n.tr("1 bookmark", "1 个书签")
            : L10n.tr("\(filteredBookmarks.count) bookmarks", "\(filteredBookmarks.count) 个书签")

        for arranged in listStack.arrangedSubviews {
            listStack.removeArrangedSubview(arranged)
            arranged.removeFromSuperview()
        }

        if filteredBookmarks.isEmpty {
            let emptyCard = makeEmptyStateView()
            listStack.addArrangedSubview(emptyCard)
            emptyCard.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
            return
        }

        let folderTree = Self.hierarchicalFolderEntries(folders: folders)
        let folderPathsByID = Dictionary(
            uniqueKeysWithValues: folderTree.map { ($0.folder.id, $0.displayPath) }
        )
        for bookmark in filteredBookmarks {
            let folderTitle = bookmark.folderID.flatMap { folderPathsByID[$0] }
                ?? L10n.tr("General", "通用")
            let row = BookmarkRowView(
                bookmark: bookmark,
                folderTitle: folderTitle,
                onOpenTab: { [weak self] item in
                    self?.client.openBookmarkAsTab(item)
                },
                onEdit: { [weak self] item in
                    self?.presentBookmarkEditor(editing: item)
                },
                onDelete: { [weak self] item in
                    guard let self else { return }
                    _ = self.client.deleteBookmark(item.id)
                    self.reloadData()
                }
            )
            listStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
        }
    }

    private func rebuildFolderPopup(folders: [BookmarkFolder]) {
        folderPopup.removeAllItems()
        folderPopup.addItem(withTitle: L10n.tr("All Bookmarks", "全部书签"))
        folderPopup.lastItem?.representedObject = "all"

        folderPopup.addItem(withTitle: L10n.tr("General", "通用"))
        folderPopup.lastItem?.representedObject = "general"

        let entries = Self.hierarchicalFolderEntries(folders: folders)
        for entry in entries {
            folderPopup.addItem(withTitle: entry.indentedTitle)
            folderPopup.lastItem?.representedObject = entry.folder.id.uuidString
        }

        switch selectedFolder {
        case .all:
            folderPopup.selectItem(at: 0)
        case .general:
            folderPopup.selectItem(at: 1)
        case let .custom(folderID):
            if let index = entries.firstIndex(where: { $0.folder.id == folderID }) {
                folderPopup.selectItem(at: index + 2)
            } else {
                folderPopup.selectItem(at: 0)
            }
        }
    }

    private static func hierarchicalFolderEntries(
        folders: [BookmarkFolder]
    ) -> [(folder: BookmarkFolder, displayPath: String, indentedTitle: String)] {
        let validIDs = Set(folders.map(\.id))
        var childrenByParent: [UUID?: [BookmarkFolder]] = [:]
        for folder in folders {
            let parentID = folder.parentFolderID.flatMap {
                validIDs.contains($0) && $0 != folder.id ? $0 : nil
            }
            childrenByParent[parentID, default: []].append(folder)
        }
        var results: [(folder: BookmarkFolder, displayPath: String, indentedTitle: String)] = []
        var visited = Set<UUID>()
        func walk(parentID: UUID?, depth: Int, pathPrefix: [String]) {
            for folder in childrenByParent[parentID] ?? [] {
                guard visited.insert(folder.id).inserted else { continue }
                let path = pathPrefix + [folder.name]
                let prefix = depth == 0 ? "" : String(repeating: "  ", count: depth) + "↳ "
                results.append((
                    folder: folder,
                    displayPath: path.joined(separator: " / "),
                    indentedTitle: prefix + folder.name
                ))
                walk(parentID: folder.id, depth: depth + 1, pathPrefix: path)
            }
        }
        walk(parentID: nil, depth: 0, pathPrefix: [])
        return results
    }

    private func makeEmptyStateView() -> NSView {
        let box = NSBox()
        box.boxType = .custom
        box.cornerRadius = 8
        box.borderWidth = 1
        box.borderColor = .separatorColor.withAlphaComponent(0.35)
        box.fillColor = .controlBackgroundColor.withAlphaComponent(0.45)

        let label = NSTextField(
            wrappingLabelWithString: L10n.tr(
                "No bookmarks in this folder yet. Click \"Add Bookmark…\" or right-click any Tab and choose \"Save to Bookmarks…\".",
                "此文件夹中暂无书签。可点击“添加书签…”，或右键任意标签选择“保存到书签…”。"
            )
        )
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12),
        ])
        return box
    }

    @objc private func folderSelectionChanged(_ sender: NSPopUpButton) {
        guard let token = sender.selectedItem?.representedObject as? String else { return }
        if token == "all" {
            selectedFolder = .all
        } else if token == "general" {
            selectedFolder = .general
        } else if let uuid = UUID(uuidString: token) {
            selectedFolder = .custom(uuid)
        }
        reloadData()
    }

    @objc private func createFolderClicked() {
        guard let window = view.window else { return }
        let defaultParentID: UUID? = if case let .custom(folderID) = selectedFolder {
            folderID
        } else {
            nil
        }
        presentCreateFolderAlert(
            folders: client.folders(),
            defaultParentID: defaultParentID,
            attachedTo: window
        ) { [weak self] name, parentID in
            guard let self, let name,
                  let created = self.client.createFolder(name, parentID) else {
                return
            }
            self.selectedFolder = .custom(created.id)
            self.reloadData()
        }
    }

    @objc private func renameFolderClicked() {
        guard let window = view.window,
              case let .custom(folderID) = selectedFolder,
              let folder = client.folders().first(where: { $0.id == folderID }) else {
            return
        }
        presentFolderNameAlert(
            title: L10n.tr("Rename Bookmark Folder", "重命名书签文件夹"),
            actionTitle: L10n.tr("Rename", "重命名"),
            initialName: folder.name,
            attachedTo: window
        ) { [weak self] name in
            guard let self, let name else { return }
            _ = self.client.renameFolder(folderID, name)
            self.reloadData()
        }
    }

    @objc private func deleteFolderClicked() {
        guard let window = view.window,
              case let .custom(folderID) = selectedFolder,
              let folder = client.folders().first(where: { $0.id == folderID }) else {
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.tr("Delete \"\(folder.name)\"?", "删除“\(folder.name)”？")
        alert.informativeText = L10n.tr(
            "Bookmarks and subfolders inside this folder will move safely to its parent folder and will not be deleted.",
            "此文件夹中的书签和子文件夹将安全移动至上级文件夹，不会被删除。"
        )
        alert.addButton(withTitle: L10n.tr("Delete Folder", "删除文件夹"))
        alert.addButton(withTitle: L10n.tr("Cancel", "取消"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            _ = self.client.deleteFolder(folderID)
            if let parentID = folder.parentFolderID {
                self.selectedFolder = .custom(parentID)
            } else {
                self.selectedFolder = .general
            }
            self.reloadData()
        }
    }

    @objc private func addBookmarkClicked() {
        presentBookmarkEditor(editing: nil)
    }

    @objc private func importHTMLClicked() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.title = L10n.tr(
            "Import Chrome or Safari Bookmarks (HTML)",
            "导入 Chrome 或 Safari 书签 (HTML)"
        )
        panel.allowedContentTypes = [.html]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            guard let data = try? Data(contentsOf: url),
                  let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                self.showAlert(
                    title: L10n.tr("Import Failed", "导入失败"),
                    detail: L10n.tr(
                        "FloatTabs could not read that HTML bookmark file.",
                        "FloatTabs 无法读取该 HTML 书签文件。"
                    )
                )
                return
            }
            let result = self.client.importHTML(html)
            self.reloadData()
            self.showAlert(
                title: L10n.tr("Bookmarks Imported", "书签导入完成"),
                detail: L10n.tr(
                    "Added \(result.foldersAdded) folder(s) and \(result.bookmarksAdded) bookmark(s).",
                    "已新增 \(result.foldersAdded) 个文件夹和 \(result.bookmarksAdded) 个书签。"
                )
            )
        }
    }

    @objc private func exportHTMLClicked() {
        guard let window = view.window else { return }
        let panel = NSSavePanel()
        panel.title = L10n.tr(
            "Export Bookmarks (Chrome & Safari HTML)",
            "导出书签（Chrome 与 Safari 兼容 HTML）"
        )
        panel.nameFieldStringValue = "FloatTabs-Bookmarks.html"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.html]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            let html = self.client.exportHTML()
            do {
                try Data(html.utf8).write(to: url, options: [.atomic])
                self.showAlert(
                    title: L10n.tr("Bookmarks Exported", "书签导出成功"),
                    detail: L10n.tr(
                        "Saved Chrome & Safari compatible bookmarks HTML successfully.",
                        "已成功保存 Chrome 与 Safari 兼容的书签 HTML 文件。"
                    )
                )
            } catch {
                self.showAlert(
                    title: L10n.tr("Export Failed", "导出失败"),
                    detail: error.localizedDescription
                )
            }
        }
    }

    private func showAlert(title: String, detail: String) {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: L10n.tr("OK", "好"))
        alert.beginSheetModal(for: window)
    }

    private func presentCreateFolderAlert(
        folders: [BookmarkFolder],
        defaultParentID: UUID?,
        attachedTo window: NSWindow,
        completion: @escaping (String?, UUID?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = L10n.tr("New Bookmark Folder", "新建书签文件夹")
        alert.addButton(withTitle: L10n.tr("Create Folder", "创建文件夹"))
        alert.addButton(withTitle: L10n.tr("Cancel", "取消"))

        let field = NSTextField(string: "")
        field.placeholderString = L10n.tr("Folder name", "文件夹名称")
        let parentPopup = NSPopUpButton()
        parentPopup.addItem(withTitle: L10n.tr("Top Level", "顶层目录"))
        parentPopup.lastItem?.representedObject = NSNull()
        let entries = Self.hierarchicalFolderEntries(folders: folders)
        for entry in entries {
            parentPopup.addItem(withTitle: entry.indentedTitle)
            parentPopup.lastItem?.representedObject = entry.folder.id.uuidString
        }
        if let defaultParentID,
           let idx = entries.firstIndex(where: { $0.folder.id == defaultParentID }) {
            parentPopup.selectItem(at: idx + 1)
        } else {
            parentPopup.selectItem(at: 0)
        }

        let stack = NSStackView(views: [
            Self.fieldLabel(L10n.tr("Folder Name", "文件夹名称")),
            field,
            Self.fieldLabel(L10n.tr("Parent Folder", "父级文件夹")),
            parentPopup,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        field.widthAnchor.constraint(equalToConstant: 300).isActive = true
        parentPopup.widthAnchor.constraint(equalToConstant: 300).isActive = true
        stack.setFrameSize(NSSize(width: 300, height: 1))
        stack.layoutSubtreeIfNeeded()
        stack.setFrameSize(NSSize(width: 300, height: ceil(stack.fittingSize.height)))
        alert.accessoryView = stack

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else {
                completion(nil, nil)
                return
            }
            let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let parentID = (parentPopup.selectedItem?.representedObject as? String)
                .flatMap(UUID.init(uuidString:))
            completion(trimmed.isEmpty ? nil : trimmed, parentID)
        }
    }

    private func presentFolderNameAlert(
        title: String,
        actionTitle: String,
        initialName: String,
        attachedTo window: NSWindow,
        completion: @escaping (String?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: actionTitle)
        alert.addButton(withTitle: L10n.tr("Cancel", "取消"))
        let field = NSTextField(string: initialName)
        field.placeholderString = L10n.tr("Folder name", "文件夹名称")
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else {
                completion(nil)
                return
            }
            let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            completion(trimmed.isEmpty ? nil : trimmed)
        }
    }

    private func presentBookmarkEditor(editing existing: BookmarkItem?) {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = existing == nil
            ? L10n.tr("Add Bookmark", "添加书签")
            : L10n.tr("Edit Bookmark", "编辑书签")
        alert.addButton(
            withTitle: existing == nil
                ? L10n.tr("Add Bookmark", "添加书签")
                : L10n.tr("Save Changes", "保存更改")
        )
        alert.addButton(withTitle: L10n.tr("Cancel", "取消"))

        let titleField = NSTextField(string: existing?.title ?? "")
        titleField.placeholderString = L10n.tr("Bookmark title", "书签标题")
        let urlField = NSTextField(string: existing?.url.absoluteString ?? "")
        urlField.placeholderString = "https://example.com"

        let folderPopup = NSPopUpButton()
        folderPopup.addItem(withTitle: L10n.tr("General", "通用"))
        folderPopup.lastItem?.representedObject = NSNull()
        let folderEntries = Self.hierarchicalFolderEntries(folders: client.folders())
        for entry in folderEntries {
            folderPopup.addItem(withTitle: entry.indentedTitle)
            folderPopup.lastItem?.representedObject = entry.folder.id.uuidString
        }
        let targetFolderID: UUID? = if let existing {
            existing.folderID
        } else if case let .custom(folderID) = selectedFolder {
            folderID
        } else {
            nil
        }
        if let targetFolderID,
           let idx = folderEntries.firstIndex(where: { $0.folder.id == targetFolderID }) {
            folderPopup.selectItem(at: idx + 1)
        } else {
            folderPopup.selectItem(at: 0)
        }

        let modePopup = NSPopUpButton()
        modePopup.addItem(withTitle: L10n.tr("Default (Follow Website Mode)", "默认（跟随网站模式）"))
        modePopup.lastItem?.representedObject = NSNull()
        for mode in WebsiteMode.allCases {
            modePopup.addItem(withTitle: mode.displayName)
            modePopup.lastItem?.representedObject = mode.rawValue
        }
        if let mode = existing?.preferredWebsiteMode,
           let idx = WebsiteMode.allCases.firstIndex(of: mode) {
            modePopup.selectItem(at: idx + 1)
        } else {
            modePopup.selectItem(at: 0)
        }

        let notesField = NSTextField(string: existing?.notes ?? "")
        notesField.placeholderString = L10n.tr("Optional notes", "备注（可选）")

        let stack = NSStackView(views: [
            Self.fieldLabel(L10n.tr("Title", "标题")),
            titleField,
            Self.fieldLabel(L10n.tr("URL", "网址")),
            urlField,
            Self.fieldLabel(L10n.tr("Folder", "文件夹")),
            folderPopup,
            Self.fieldLabel(L10n.tr("Preferred Website Mode", "默认网站模式")),
            modePopup,
            Self.fieldLabel(L10n.tr("Notes", "备注")),
            notesField,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        for control in [titleField, urlField, folderPopup, modePopup, notesField] {
            control.widthAnchor.constraint(equalToConstant: 360).isActive = true
        }
        stack.setFrameSize(NSSize(width: 360, height: 1))
        stack.layoutSubtreeIfNeeded()
        stack.setFrameSize(NSSize(width: 360, height: ceil(stack.fittingSize.height)))
        alert.accessoryView = stack

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let rawURL = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let normalized = WebAppURL.normalizedEntry(from: rawURL) else {
                let err = NSAlert()
                err.alertStyle = .warning
                err.messageText = L10n.tr("Enter a valid http or https URL", "请输入有效的 http 或 https 网址")
                err.beginSheetModal(for: window)
                return
            }
            let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedTitle = title.isEmpty
                ? WebAppURL.defaultDisplayName(for: normalized.url)
                : title
            let folderID = (folderPopup.selectedItem?.representedObject as? String)
                .flatMap(UUID.init(uuidString:))
            let mode = (modePopup.selectedItem?.representedObject as? String)
                .flatMap(WebsiteMode.init(rawValue:))
            let notes = notesField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

            if let existing {
                let validProfileID = existing.browserProfileID.flatMap { profileID in
                    self.client.browserProfiles().contains(where: { $0.id == profileID }) ? profileID : nil
                }
                _ = self.client.updateBookmark(
                    existing.id,
                    resolvedTitle,
                    normalized.url,
                    folderID,
                    notes.isEmpty ? nil : notes,
                    mode,
                    validProfileID
                )
            } else {
                _ = self.client.addBookmark(
                    resolvedTitle,
                    normalized.url,
                    folderID,
                    notes.isEmpty ? nil : notes,
                    mode,
                    nil
                )
            }
            self.reloadData()
        }
    }

    private static func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        return label
    }

    private static func detailLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 0
        return label
    }

    private static func fieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        return label
    }
}

@MainActor
private final class BookmarkRowView: NSView {
    private let bookmark: BookmarkItem
    private let onOpenTab: (BookmarkItem) -> Void
    private let onEdit: (BookmarkItem) -> Void
    private let onDelete: (BookmarkItem) -> Void
    private let iconView = NSImageView()

    init(
        bookmark: BookmarkItem,
        folderTitle: String,
        onOpenTab: @escaping (BookmarkItem) -> Void,
        onEdit: @escaping (BookmarkItem) -> Void,
        onDelete: @escaping (BookmarkItem) -> Void
    ) {
        self.bookmark = bookmark
        self.onOpenTab = onOpenTab
        self.onEdit = onEdit
        self.onDelete = onDelete
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.30).cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.55).cgColor

        iconView.image = NSImage(systemSymbolName: "globe", accessibilityDescription: bookmark.title)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: bookmark.title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail

        var detailParts = [bookmark.url.host ?? bookmark.url.absoluteString, folderTitle]
        if let mode = bookmark.preferredWebsiteMode {
            detailParts.append(mode.displayName)
        }
        let subtitleLabel = NSTextField(labelWithString: detailParts.joined(separator: " · "))
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let openButton = NSButton(title: L10n.tr("Open Tab", "打开标签"), target: self, action: #selector(openTabClicked))
        openButton.bezelStyle = .rounded
        openButton.controlSize = .small

        let editButton = NSButton(title: L10n.tr("Edit", "编辑"), target: self, action: #selector(editClicked))
        editButton.bezelStyle = .rounded
        editButton.controlSize = .small

        let deleteButton = NSButton(title: L10n.tr("Delete", "删除"), target: self, action: #selector(deleteClicked))
        deleteButton.bezelStyle = .rounded
        deleteButton.controlSize = .small

        let row = NSStackView(views: [iconView, textStack, openButton, editButton, deleteButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])

        WebsiteFaviconProvider.shared.load(for: bookmark.url) { [weak self] image in
            guard let self, let image else { return }
            self.iconView.image = image
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func openTabClicked() { onOpenTab(bookmark) }
    @objc private func editClicked() { onEdit(bookmark) }
    @objc private func deleteClicked() { onDelete(bookmark) }
}
