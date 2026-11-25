import AppKit

struct WebAppEditorBrowserProfileOption: Equatable {
    let id: UUID?
    let name: String
    let isEnabled: Bool

    static func defaultProfile(name: String = L10n.tr("Default", "默认")) -> WebAppEditorBrowserProfileOption {
        WebAppEditorBrowserProfileOption(
            id: nil,
            name: L10n.defaultDisplayName(name),
            isEnabled: true
        )
    }
}

struct WebAppEditorValue {
    var name: String
    var url: URL
    var homeURLSchemeWasInferred: Bool
    var renderingProfile: WebRenderingProfile
    var browserProfileID: UUID?
    var runtimeRetentionPreference: SlotRuntimeRetentionPreference

    init(
        name: String,
        url: URL,
        homeURLSchemeWasInferred: Bool,
        renderingProfile: WebRenderingProfile,
        browserProfileID: UUID? = nil,
        runtimeRetentionPreference: SlotRuntimeRetentionPreference = .automatic
    ) {
        self.name = name
        self.url = url
        self.homeURLSchemeWasInferred = homeURLSchemeWasInferred
        self.renderingProfile = renderingProfile
        self.browserProfileID = browserProfileID
        self.runtimeRetentionPreference = runtimeRetentionPreference
    }
}

@MainActor
final class WebAppEditorPresentationCompletionGate {
    private let completion: (WebAppEditorValue?) -> Void
    private var validationWarningPending = false
    private var didComplete = false

    init(completion: @escaping (WebAppEditorValue?) -> Void) {
        self.completion = completion
    }

    func editorDidFinish(with value: WebAppEditorValue?) {
        guard !validationWarningPending else { return }
        finish(with: value)
    }

    func validationWarningDidBegin() {
        guard !didComplete else { return }
        validationWarningPending = true
    }

    func validationWarningDidFinish() {
        guard validationWarningPending else { return }
        validationWarningPending = false
        finish(with: nil)
    }

    private func finish(with value: WebAppEditorValue?) {
        guard !didComplete else { return }
        didComplete = true
        completion(value)
    }
}

@MainActor
enum WebAppEditorController {
    static func browserProfileOptions(
        browserProfiles: [BrowserProfile],
        defaultProfileName: String = "Default",
        includesDefaultProfile: Bool = true
    ) -> [WebAppEditorBrowserProfileOption] {
        var options: [WebAppEditorBrowserProfileOption] = []
        if includesDefaultProfile || browserProfiles.isEmpty {
            options.append(WebAppEditorBrowserProfileOption.defaultProfile(name: defaultProfileName))
        }
        options.append(contentsOf: browserProfiles.map {
            WebAppEditorBrowserProfileOption(
                id: $0.id,
                name: $0.name,
                isEnabled: true
            )
        })
        return options
    }

    static func makeValue(
        name: String,
        url: URL,
        homeURLSchemeWasInferred: Bool,
        renderingProfile: WebRenderingProfile,
        browserProfileID: UUID?,
        runtimeRetentionPreference: SlotRuntimeRetentionPreference = .automatic
    ) -> WebAppEditorValue {
        WebAppEditorValue(
            name: name,
            url: url,
            homeURLSchemeWasInferred: homeURLSchemeWasInferred,
            renderingProfile: renderingProfile,
            browserProfileID: browserProfileID,
            runtimeRetentionPreference: runtimeRetentionPreference
        )
    }

    static func presentAdd(
        browserProfiles: [BrowserProfile] = [],
        defaultProfileName: String = "Default",
        includesDefaultProfile: Bool = true,
        initialBrowserProfileID: UUID? = nil,
        allowsWindowSizeEditing: Bool = true,
        bookmarkFolders: [BookmarkFolder] = [],
        bookmarks: [BookmarkItem] = [],
        onManageBookmarks: (() -> Void)? = nil,
        attachedTo window: NSWindow,
        completion: @escaping (WebAppEditorValue?) -> Void
    ) {
        presentEditor(
            title: L10n.tr("Add Web App", "添加网页应用"),
            actionTitle: L10n.tr("Add Web App", "添加网页应用"),
            initialName: "",
            initialURL: "",
            initialURLSchemeWasInferred: false,
            initialRendering: .canonicalDefault,
            initialRetention: .automatic,
            showsPrimaryRenderingControls: true,
            allowsWindowSizeEditing: allowsWindowSizeEditing,
            allowsBrowserProfileEditing: true,
            nameIsOptional: true,
            browserProfileOptions: browserProfileOptions(
                browserProfiles: browserProfiles,
                defaultProfileName: defaultProfileName,
                includesDefaultProfile: includesDefaultProfile
            ),
            initialBrowserProfileID: initialBrowserProfileID,
            bookmarkFolders: bookmarkFolders,
            bookmarks: bookmarks,
            onManageBookmarks: onManageBookmarks,
            attachedTo: window,
            completion: completion
        )
    }

    static func presentDerivedAdd(
        sourceProfile: WebAppProfile,
        currentURL: URL,
        attachedTo window: NSWindow,
        completion: @escaping (String?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = L10n.tr("Create Web App from Current Page", "从当前页面创建网页应用")
        alert.informativeText = L10n.tr(
            "Creates a new Web App using this page as its Home URL and copies the current Web App's rendering and resource settings.",
            "将当前页面设为主页创建新的网页应用，并复制当前应用的渲染与资源设置。"
        )
        alert.addButton(withTitle: L10n.tr("Create Web App", "创建网页应用"))
        alert.addButton(withTitle: L10n.tr("Cancel", "取消"))

        let nameField = NSTextField(string: "")
        nameField.placeholderString = L10n.tr("Optional · defaults to site host", "可选 · 默认使用网站域名")
        nameField.widthAnchor.constraint(equalToConstant: 400).isActive = true

        let urlField = NSTextField(labelWithString: currentURL.absoluteString)
        urlField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        urlField.textColor = .secondaryLabelColor
        urlField.isSelectable = true
        urlField.cell?.lineBreakMode = .byTruncatingMiddle
        urlField.widthAnchor.constraint(equalToConstant: 400).isActive = true

        let inherited = NSTextField(
            labelWithString: L10n.tr(
                "Settings copied from \(sourceProfile.name)",
                "已从“\(sourceProfile.name)”复制设置"
            )
        )
        inherited.font = .systemFont(ofSize: 11, weight: .regular)
        inherited.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [
            makeLabel(L10n.tr("Name (Optional)", "名称（可选）")),
            nameField,
            makeLabel(L10n.tr("Current Page URL", "当前页面网址")),
            urlField,
            inherited,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        stack.setFrameSize(NSSize(width: 400, height: 125))
        alert.accessoryView = stack

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else {
                completion(nil)
                return
            }

            let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            completion(name.isEmpty ? WebAppURL.defaultDisplayName(for: currentURL) : name)
        }
    }

    static func presentEdit(
        profile: WebAppProfile,
        browserProfiles: [BrowserProfile] = [],
        defaultProfileName: String = "Default",
        includesDefaultProfile: Bool = true,
        allowsBrowserProfileEditing: Bool = true,
        allowsWindowSizeEditing: Bool = true,
        attachedTo window: NSWindow,
        completion: @escaping (WebAppEditorValue?) -> Void
    ) {
        presentEditor(
            title: L10n.tr("Edit Web App", "编辑网页应用"),
            actionTitle: L10n.tr("Save", "保存"),
            initialName: profile.name,
            initialURL: profile.homeURL.absoluteString,
            initialURLSchemeWasInferred: profile.homeURLSchemeWasInferred,
            initialRendering: profile.renderingProfile,
            initialRetention: profile.runtimeRetentionPreference,
            showsPrimaryRenderingControls: true,
            allowsWindowSizeEditing: allowsWindowSizeEditing,
            allowsBrowserProfileEditing: allowsBrowserProfileEditing,
            nameIsOptional: false,
            browserProfileOptions: browserProfileOptions(
                browserProfiles: browserProfiles,
                defaultProfileName: defaultProfileName,
                includesDefaultProfile: includesDefaultProfile
            ),
            initialBrowserProfileID: profile.browserProfileID,
            attachedTo: window,
            completion: completion
        )
    }

    static func confirmRemove(
        profile: WebAppProfile,
        attachedTo window: NSWindow,
        completion: @escaping (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.tr("Remove \(profile.name)?", "移除“\(profile.name)”？")
        alert.informativeText = L10n.tr(
            "The Web App slot will be removed. Shared WebKit website data, cookies, and sessions will not be cleared.",
            "将从列表中移除此网页应用。共享的网站数据、Cookie 与登录会话不会被清除。"
        )
        alert.addButton(withTitle: L10n.tr("Remove Web App", "移除网页应用"))
        alert.addButton(withTitle: L10n.tr("Cancel", "取消"))
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { response in
            completion(response == .alertFirstButtonReturn)
        }
    }

    private static func presentEditor(
        title: String,
        actionTitle: String,
        initialName: String,
        initialURL: String,
        initialURLSchemeWasInferred: Bool,
        initialRendering: WebRenderingProfile,
        initialRetention: SlotRuntimeRetentionPreference,
        showsPrimaryRenderingControls: Bool,
        allowsWindowSizeEditing: Bool,
        allowsBrowserProfileEditing: Bool,
        nameIsOptional: Bool,
        browserProfileOptions: [WebAppEditorBrowserProfileOption]?,
        initialBrowserProfileID: UUID?,
        bookmarkFolders: [BookmarkFolder] = [],
        bookmarks: [BookmarkItem] = [],
        onManageBookmarks: (() -> Void)? = nil,
        attachedTo window: NSWindow,
        completion: @escaping (WebAppEditorValue?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: actionTitle)
        alert.addButton(withTitle: L10n.tr("Cancel", "取消"))

        let nameField = NSTextField(string: initialName)
        nameField.placeholderString = nameIsOptional
            ? L10n.tr("Optional · defaults to site host", "可选 · 默认使用网站域名")
            : L10n.tr("Name", "名称")
        let urlField = NSTextField(string: initialURL)
        urlField.placeholderString = "https://example.com"

        let nameLabel = makeLabel(
            nameIsOptional
                ? L10n.tr("Name (Optional)", "名称（可选）")
                : L10n.tr("Name", "名称")
        )
        let urlLabel = makeLabel(L10n.tr("URL", "网址"))
        let renderingForm = RenderingForm(
            initial: initialRendering,
            initialRetention: initialRetention,
            showsPrimaryRenderingControls: showsPrimaryRenderingControls,
            allowsWindowSizeEditing: allowsWindowSizeEditing
        )

        let profilePicker: NSPopUpButton?
        if let browserProfileOptions {
            let picker = NSPopUpButton()
            let options = browserProfileOptions.isEmpty
                ? [WebAppEditorBrowserProfileOption.defaultProfile()]
                : browserProfileOptions
            for option in options {
                picker.addItem(withTitle: option.name)
                guard let item = picker.lastItem else { continue }
                if let id = option.id {
                    item.representedObject = id.uuidString
                } else {
                    item.representedObject = NSNull()
                }
                item.isEnabled = option.isEnabled || option.id == initialBrowserProfileID
            }
            picker.widthAnchor.constraint(equalToConstant: 400).isActive = true
            let selectedIndex = options.firstIndex(where: {
                $0.id == initialBrowserProfileID
            }) ?? 0
            picker.selectItem(at: selectedIndex)
            picker.isEnabled = allowsBrowserProfileEditing
            picker.toolTip = allowsBrowserProfileEditing
                ? nil
                : L10n.tr(
                    "Profile cannot be changed during fullscreen presentation.",
                    "全屏演示期间无法更改配置文件。"
                )
            profilePicker = picker
        } else {
            profilePicker = nil
        }

        var editorViews: [NSView] = [
            nameLabel,
            nameField,
            urlLabel,
            urlField,
        ]
        if let profilePicker {
            editorViews.append(makeLabel(L10n.tr("Profile", "配置文件")))
            editorViews.append(profilePicker)
        }
        editorViews.append(renderingForm.view)

        var bookmarkPicker: AddWebAppBookmarkPickerView?
        if !bookmarks.isEmpty || !bookmarkFolders.isEmpty || onManageBookmarks != nil {
            let separator = NSBox()
            separator.boxType = .separator
            separator.widthAnchor.constraint(equalToConstant: 400).isActive = true
            editorViews.append(separator)

            let picker = AddWebAppBookmarkPickerView(
                folders: bookmarkFolders,
                bookmarks: bookmarks,
                onSelectBookmark: { bookmark in
                    nameField.stringValue = bookmark.title
                    urlField.stringValue = bookmark.url.absoluteString
                    if let mode = bookmark.preferredWebsiteMode {
                        renderingForm.setWebsiteMode(mode)
                    }
                    if let profilePicker,
                       let targetProfileID = bookmark.browserProfileID,
                       let index = profilePicker.itemArray.firstIndex(where: {
                           ($0.representedObject as? String) == targetProfileID.uuidString
                               && $0.isEnabled
                       }) {
                        profilePicker.selectItem(at: index)
                    }
                    nameField.window?.makeFirstResponder(nameField)
                },
                onManageBookmarks: {
                    if let sheetWindow = alert.window.sheetParent {
                        sheetWindow.endSheet(alert.window, returnCode: .cancel)
                    } else {
                        alert.buttons.dropFirst().first?.performClick(nil)
                    }
                    DispatchQueue.main.async {
                        onManageBookmarks?()
                    }
                }
            )
            picker.widthAnchor.constraint(equalToConstant: 400).isActive = true
            editorViews.append(picker)
            bookmarkPicker = picker
        }

        let stack = NSStackView(views: editorViews)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        stack.setContentHuggingPriority(.required, for: .vertical)
        nameField.widthAnchor.constraint(equalToConstant: 400).isActive = true
        urlField.widthAnchor.constraint(equalToConstant: 400).isActive = true
        renderingForm.view.widthAnchor.constraint(equalToConstant: 400).isActive = true
        bookmarkPicker?.layoutSubtreeIfNeeded()

        // NSAlert sizes its accessory from the view frame. Using the actual
        // fitting height keeps Add/Edit compact when their visible fields differ.
        stack.setFrameSize(NSSize(width: 400, height: 1))
        stack.layoutSubtreeIfNeeded()
        stack.setFrameSize(NSSize(width: 400, height: ceil(stack.fittingSize.height)))
        alert.accessoryView = stack

        let completionGate = WebAppEditorPresentationCompletionGate(completion: completion)

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else {
                completionGate.editorDidFinish(with: nil)
                return
            }

            let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawURL = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let normalized = WebAppURL.normalizedEntry(from: rawURL),
                  let (rendering, retention) = renderingForm.valueWithRetention(),
                  nameIsOptional || !name.isEmpty else {
                completionGate.validationWarningDidBegin()
                presentValidationError(
                    nameIsOptional: nameIsOptional,
                    attachedTo: window,
                    completion: {
                        completionGate.validationWarningDidFinish()
                    }
                )
                return
            }

            // Edit fields display the canonical absolute URL. If an existing
            // profile originally came from a bare address, merely changing its
            // name/rendering and pressing Save must not silently erase that
            // provenance. Any actual URL text change is parsed normally, so an
            // explicit scheme remains explicit and never receives fallback.
            let schemeWasInferred: Bool
            if rawURL == initialURL,
               normalized.url == WebAppURL.normalized(from: initialURL),
               initialURLSchemeWasInferred {
                schemeWasInferred = true
            } else {
                schemeWasInferred = normalized.schemeWasInferred
            }

            let selectedProfileID = profilePicker.map {
                selectedBrowserProfileID(from: $0)
            } ?? initialBrowserProfileID
            completionGate.editorDidFinish(
                with: makeValue(
                    name: name,
                    url: normalized.url,
                    homeURLSchemeWasInferred: schemeWasInferred,
                    renderingProfile: rendering,
                    browserProfileID: selectedProfileID,
                    runtimeRetentionPreference: retention
                )
            )
        }
    }

    private static func selectedBrowserProfileID(from picker: NSPopUpButton) -> UUID? {
        guard let rawID = picker.selectedItem?.representedObject as? String else {
            return nil
        }
        return UUID(uuidString: rawID)
    }

    private static func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        return label
    }

    private static func presentValidationError(
        nameIsOptional: Bool,
        attachedTo window: NSWindow,
        completion: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.tr("Enter a valid Web App", "请输入有效的网页应用信息")
        alert.informativeText = nameIsOptional
            ? L10n.tr(
                "URL must be http/https, Custom Window Size must be at least 320 × 400, and a Custom User Agent cannot be empty.",
                "网址必须为 http 或 https，自定义窗口尺寸至少为 320 × 400，且自定义 User Agent 不能为空。"
            )
            : L10n.tr(
                "Name is required, URL must be http/https, Custom Window Size must be at least 320 × 400, and a Custom User Agent cannot be empty.",
                "名称不能为空，网址必须为 http 或 https，自定义窗口尺寸至少为 320 × 400，且自定义 User Agent 不能为空。"
            )
        alert.addButton(withTitle: L10n.tr("OK", "好"))
        alert.beginSheetModal(for: window) { _ in
            completion()
        }
    }

    private static func presentRenderingValidationError(attachedTo window: NSWindow) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.tr("Check rendering settings", "请检查渲染设置")
        alert.informativeText = L10n.tr(
            "Custom Window Size must be at least 320 × 400 and a Custom User Agent cannot be empty.",
            "自定义窗口尺寸至少为 320 × 400，且自定义 User Agent 不能为空。"
        )
        alert.addButton(withTitle: L10n.tr("OK", "好"))
        alert.beginSheetModal(for: window)
    }
}

@MainActor
private final class RenderingForm: NSObject {
    let view: NSStackView

    private let modePopup = NSPopUpButton()
    private let sizePopup = NSPopUpButton()
    private let initialRendering: WebRenderingProfile
    private let allowsWindowSizeEditing: Bool
    private let widthField = NSTextField()
    private let heightField = NSTextField()
    private let zoomPopup = NSPopUpButton()
    private let retentionPopup = NSPopUpButton()
    private let advancedButton = NSButton(title: L10n.tr("Advanced…", "高级设置…"), target: nil, action: nil)

    private let identityPopup = NSPopUpButton()
    private let devicePopup = NSPopUpButton()
    private let orientationPopup = NSPopUpButton()
    private let customUAField = NSTextField()
    private let effectiveUAField = NSTextField(labelWithString: "")
    private let engineValue = NSTextField(labelWithString: "WebKit")
    private let advancedPopover = NSPopover()

    init(
        initial: WebRenderingProfile,
        initialRetention: SlotRuntimeRetentionPreference = .automatic,
        showsPrimaryRenderingControls: Bool = true,
        allowsWindowSizeEditing: Bool = true
    ) {
        let rendering = initial.normalized()
        self.initialRendering = rendering
        self.allowsWindowSizeEditing = allowsWindowSizeEditing

        modePopup.addItems(withTitles: WebsiteMode.allCases.map(\.displayName))
        if let index = WebsiteMode.allCases.firstIndex(of: rendering.websiteMode) {
            modePopup.selectItem(at: index)
        }

        sizePopup.addItems(withTitles: SimpleViewportPreset.allCases.map(\.menuTitle))
        if let index = SimpleViewportPreset.allCases.firstIndex(of: rendering.sizePreset) {
            sizePopup.selectItem(at: index)
        }

        widthField.stringValue = String(format: "%.0f", Double(rendering.viewportWidth))
        heightField.stringValue = String(format: "%.0f", Double(rendering.viewportHeight))
        widthField.placeholderString = L10n.tr("Width", "宽度")
        heightField.placeholderString = L10n.tr("Height", "高度")

        zoomPopup.addItems(withTitles: ZoomSteps.values.map(ZoomSteps.percentageText))
        let normalizedZoom = ZoomSteps.nearest(to: rendering.zoom)
        if let index = ZoomSteps.values.firstIndex(where: { abs($0 - normalizedZoom) < 0.001 }) {
            zoomPopup.selectItem(at: index)
        }

        retentionPopup.addItems(
            withTitles: SlotRuntimeRetentionPreference.allCases.map(\.displayName)
        )
        if let index = SlotRuntimeRetentionPreference.allCases.firstIndex(of: initialRetention) {
            retentionPopup.selectItem(at: index)
        }

        identityPopup.addItems(withTitles: BrowserIdentity.allCases.map(\.displayName))
        if let index = BrowserIdentity.allCases.firstIndex(of: rendering.browserIdentity) {
            identityPopup.selectItem(at: index)
        }

        devicePopup.addItem(withTitle: L10n.tr("None", "无"))
        devicePopup.addItems(withTitles: DevicePresetCatalog.all.map(\.menuTitle))
        if let deviceID = rendering.devicePresetID,
           let index = DevicePresetCatalog.all.firstIndex(where: { $0.id == deviceID }) {
            devicePopup.selectItem(at: index + 1)
        } else {
            devicePopup.selectItem(at: 0)
        }

        orientationPopup.addItems(withTitles: DeviceOrientation.allCases.map(\.displayName))
        if let index = DeviceOrientation.allCases.firstIndex(of: rendering.orientation) {
            orientationPopup.selectItem(at: index)
        }

        customUAField.placeholderString = "Mozilla/5.0 …"
        customUAField.stringValue = rendering.customUserAgent ?? ""
        effectiveUAField.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        effectiveUAField.textColor = .secondaryLabelColor
        effectiveUAField.cell?.lineBreakMode = .byTruncatingMiddle
        engineValue.textColor = .secondaryLabelColor

        identityPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 270).isActive = true
        devicePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 270).isActive = true
        orientationPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        customUAField.widthAnchor.constraint(equalToConstant: 360).isActive = true
        effectiveUAField.widthAnchor.constraint(equalToConstant: 360).isActive = true

        let sizeRow = NSStackView(views: [
            sizePopup,
            widthField,
            NSTextField(labelWithString: "×"),
            heightField,
        ])
        sizeRow.orientation = .horizontal
        sizeRow.spacing = 6
        widthField.widthAnchor.constraint(equalToConstant: 66).isActive = true
        heightField.widthAnchor.constraint(equalToConstant: 66).isActive = true

        let primaryViews: [NSView] = showsPrimaryRenderingControls
            ? ([
                Self.label(L10n.tr("Website Mode", "网站模式")),
                modePopup,
            ] + (allowsWindowSizeEditing
                ? [Self.label(L10n.tr("Window Size", "窗口尺寸")), sizeRow]
                : [Self.secondaryLabel(L10n.tr(
                    "Window Size is fixed globally. Existing per-App sizes are preserved.",
                    "当前已开启全局固定窗口尺寸，各网页应用的原有尺寸配置已保留。"
                ))]
            ) + [
                Self.label(L10n.tr("Zoom", "页面缩放")),
                zoomPopup,
                Self.label(L10n.tr("Runtime Retention", "运行时驻留")),
                retentionPopup,
                advancedButton,
            ])
            : [
                Self.label(L10n.tr("Browser Identity", "浏览器标识")),
                identityPopup,
                Self.label(L10n.tr("Device Preset", "设备预设")),
                devicePopup,
                Self.label(L10n.tr("Orientation", "屏幕方向")),
                orientationPopup,
                Self.label(L10n.tr("Custom User Agent", "自定义 User Agent")),
                customUAField,
                Self.label(L10n.tr("Effective Engine", "渲染引擎")),
                engineValue,
                Self.label(L10n.tr("Effective User Agent", "生效 User Agent")),
                effectiveUAField,
            ]
        view = NSStackView(views: primaryViews)
        view.orientation = .vertical
        view.alignment = .leading
        view.spacing = 5
        modePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 190).isActive = true
        sizePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 190).isActive = true
        zoomPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        retentionPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 190).isActive = true
        advancedButton.bezelStyle = .rounded

        super.init()

        advancedButton.target = self
        advancedButton.action = #selector(toggleAdvanced(_:))
        modePopup.target = self
        modePopup.action = #selector(modeSelectionChanged(_:))
        sizePopup.target = self
        sizePopup.action = #selector(sizeSelectionChanged(_:))
        identityPopup.target = self
        identityPopup.action = #selector(identitySelectionChanged(_:))
        devicePopup.target = self
        devicePopup.action = #selector(deviceSelectionChanged(_:))
        orientationPopup.target = self
        orientationPopup.action = #selector(orientationSelectionChanged(_:))
        customUAField.target = self
        customUAField.action = #selector(customUAChanged(_:))

        sizePopup.isEnabled = allowsWindowSizeEditing
        widthField.isEnabled = allowsWindowSizeEditing
        heightField.isEnabled = allowsWindowSizeEditing
        devicePopup.isEnabled = allowsWindowSizeEditing
        orientationPopup.isEnabled = allowsWindowSizeEditing
        devicePopup.toolTip = allowsWindowSizeEditing
            ? nil
            : L10n.tr(
                "Device preset is preserved while global Fixed window sizing is active.",
                "全局固定窗口尺寸开启期间会保留设备预设。"
            )
        orientationPopup.toolTip = devicePopup.toolTip

        if showsPrimaryRenderingControls {
            configureAdvancedPopover()
        }
        updateAutomaticIdentityTitle()
        updateCustomFieldEditability()
        updateCustomUAEditability()
        updateEffectiveUAPreview()
    }

    func value() -> WebRenderingProfile? {
        valueWithRetention()?.0
    }

    func valueWithRetention() -> (WebRenderingProfile, SlotRuntimeRetentionPreference)? {
        let modeIndex = modePopup.indexOfSelectedItem
        let sizeIndex = sizePopup.indexOfSelectedItem
        let zoomIndex = zoomPopup.indexOfSelectedItem
        let retentionIndex = retentionPopup.indexOfSelectedItem
        let identityIndex = identityPopup.indexOfSelectedItem
        let orientationIndex = orientationPopup.indexOfSelectedItem

        guard WebsiteMode.allCases.indices.contains(modeIndex),
              SimpleViewportPreset.allCases.indices.contains(sizeIndex),
              ZoomSteps.values.indices.contains(zoomIndex),
              SlotRuntimeRetentionPreference.allCases.indices.contains(retentionIndex),
              BrowserIdentity.allCases.indices.contains(identityIndex),
              DeviceOrientation.allCases.indices.contains(orientationIndex) else {
            return nil
        }

        let mode = WebsiteMode.allCases[modeIndex]
        let selectedPreset = SimpleViewportPreset.allCases[sizeIndex]
        let retention = SlotRuntimeRetentionPreference.allCases[retentionIndex]
        let identity = BrowserIdentity.allCases[identityIndex]
        let selectedOrientation = DeviceOrientation.allCases[orientationIndex]

        let preset: SimpleViewportPreset
        let orientation: DeviceOrientation
        let size: CGSize
        if allowsWindowSizeEditing {
            preset = selectedPreset
            orientation = selectedOrientation
            if let presetSize = preset.size {
                size = presetSize
            } else {
                guard let parsed = parsedCustomSize() else { return nil }
                size = parsed
            }
        } else {
            preset = initialRendering.sizePreset
            orientation = initialRendering.orientation
            size = initialRendering.viewportSize
        }

        let customUA: String?
        if identity == .custom {
            let trimmed = customUAField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            customUA = trimmed
        } else {
            customUA = nil
        }

        let deviceID: String?
        if !allowsWindowSizeEditing {
            deviceID = initialRendering.devicePresetID
        } else if let selectedDevice = selectedDevicePreset() {
            let expected = selectedDevice.size(for: orientation)
            if abs(expected.width - size.width) <= 0.5,
               abs(expected.height - size.height) <= 0.5 {
                deviceID = selectedDevice.id
            } else {
                deviceID = nil
            }
        } else {
            deviceID = nil
        }

        let rendering = WebRenderingProfile(
            websiteMode: mode,
            browserIdentity: identity,
            customUserAgent: customUA,
            sizePreset: deviceID == nil ? preset : .custom,
            devicePresetID: deviceID,
            orientation: orientation,
            viewportWidth: size.width,
            viewportHeight: size.height,
            zoom: ZoomSteps.values[zoomIndex]
        ).normalized()
        return (rendering, retention)
    }

    private func configureAdvancedPopover() {
        let advancedStack = NSStackView(views: [
            Self.label(L10n.tr("Browser Identity", "浏览器标识")),
            identityPopup,
            Self.label(L10n.tr("Device Preset", "设备预设")),
            devicePopup,
            Self.label(L10n.tr("Orientation", "屏幕方向")),
            orientationPopup,
            Self.label(L10n.tr("Custom User Agent", "自定义 User Agent")),
            customUAField,
            Self.label(L10n.tr("Effective Engine", "渲染引擎")),
            engineValue,
            Self.label(L10n.tr("Effective User Agent", "生效 User Agent")),
            effectiveUAField,
        ])
        advancedStack.orientation = .vertical
        advancedStack.alignment = .leading
        advancedStack.spacing = 6
        advancedStack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 390, height: 350))
        advancedStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(advancedStack)
        NSLayoutConstraint.activate([
            advancedStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            advancedStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            advancedStack.topAnchor.constraint(equalTo: container.topAnchor),
            advancedStack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let controller = NSViewController()
        controller.view = container
        advancedPopover.contentViewController = controller
        advancedPopover.contentSize = NSSize(width: 390, height: 350)
        advancedPopover.behavior = .transient
    }

    func setWebsiteMode(_ mode: WebsiteMode) {
        guard let index = WebsiteMode.allCases.firstIndex(of: mode) else { return }
        modePopup.selectItem(at: index)
        updateAutomaticIdentityTitle()
        updateCustomUAEditability()
        updateEffectiveUAPreview()
    }

    @objc private func toggleAdvanced(_ sender: NSButton) {
        if advancedPopover.isShown {
            advancedPopover.performClose(sender)
        } else {
            updateEffectiveUAPreview()
            advancedPopover.show(
                relativeTo: sender.bounds,
                of: sender,
                preferredEdge: .maxX
            )
        }
    }

    @objc private func modeSelectionChanged(_ sender: NSPopUpButton) {
        guard selectedWebsiteMode() != nil else { return }
        updateAutomaticIdentityTitle()
        updateCustomUAEditability()
        updateEffectiveUAPreview()
    }

    @objc private func sizeSelectionChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard SimpleViewportPreset.allCases.indices.contains(index) else { return }
        let preset = SimpleViewportPreset.allCases[index]
        if let size = preset.size {
            setSizeFields(size)
            devicePopup.selectItem(at: 0)
            selectOrientation(size.width > size.height ? .landscape : .portrait)
        }
        updateCustomFieldEditability()
    }

    @objc private func identitySelectionChanged(_ sender: NSPopUpButton) {
        guard selectedBrowserIdentity() != nil else { return }
        updateAutomaticIdentityTitle()
        updateCustomUAEditability()
        updateEffectiveUAPreview()
    }

    @objc private func deviceSelectionChanged(_ sender: NSPopUpButton) {
        guard let device = selectedDevicePreset(),
              let orientation = selectedOrientation() else {
            return
        }
        selectSimplePreset(.custom)
        setSizeFields(device.size(for: orientation))
        updateCustomFieldEditability()
    }

    @objc private func orientationSelectionChanged(_ sender: NSPopUpButton) {
        guard let orientation = selectedOrientation() else { return }
        selectSimplePreset(.custom)
        if let device = selectedDevicePreset() {
            setSizeFields(device.size(for: orientation))
        } else if let current = parsedCustomSize() {
            setSizeFields(CGSize(width: current.height, height: current.width))
        }
        updateCustomFieldEditability()
    }

    @objc private func customUAChanged(_ sender: NSTextField) {
        updateEffectiveUAPreview()
    }

    private func selectedWebsiteMode() -> WebsiteMode? {
        let index = modePopup.indexOfSelectedItem
        guard WebsiteMode.allCases.indices.contains(index) else { return nil }
        return WebsiteMode.allCases[index]
    }

    private func selectedBrowserIdentity() -> BrowserIdentity? {
        let index = identityPopup.indexOfSelectedItem
        guard BrowserIdentity.allCases.indices.contains(index) else { return nil }
        return BrowserIdentity.allCases[index]
    }

    private func selectedOrientation() -> DeviceOrientation? {
        let index = orientationPopup.indexOfSelectedItem
        guard DeviceOrientation.allCases.indices.contains(index) else { return nil }
        return DeviceOrientation.allCases[index]
    }

    private func selectedDevicePreset() -> DevicePreset? {
        let index = devicePopup.indexOfSelectedItem - 1
        guard DevicePresetCatalog.all.indices.contains(index) else { return nil }
        return DevicePresetCatalog.all[index]
    }

    private func parsedCustomSize() -> CGSize? {
        guard let width = Double(widthField.stringValue),
              let height = Double(heightField.stringValue),
              width >= Double(WebRenderingProfile.minimumViewportSize.width),
              height >= Double(WebRenderingProfile.minimumViewportSize.height) else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    private func selectSimplePreset(_ preset: SimpleViewportPreset) {
        guard let index = SimpleViewportPreset.allCases.firstIndex(of: preset) else { return }
        sizePopup.selectItem(at: index)
    }

    private func selectOrientation(_ orientation: DeviceOrientation) {
        guard let index = DeviceOrientation.allCases.firstIndex(of: orientation) else { return }
        orientationPopup.selectItem(at: index)
    }

    private func setSizeFields(_ size: CGSize) {
        widthField.stringValue = String(format: "%.0f", Double(size.width))
        heightField.stringValue = String(format: "%.0f", Double(size.height))
    }

    private func updateAutomaticIdentityTitle() {
        guard let mode = selectedWebsiteMode(),
              let automaticIndex = BrowserIdentity.allCases.firstIndex(of: .automatic),
              let item = identityPopup.item(at: automaticIndex) else {
            return
        }
        let resolved = mode == .desktop ? "macOS Safari" : "iPhone Safari"
        item.title = L10n.tr("Automatic · \(resolved)", "自动 · \(resolved)")
    }

    private func updateCustomFieldEditability() {
        let index = sizePopup.indexOfSelectedItem
        let isCustom = SimpleViewportPreset.allCases.indices.contains(index)
            && SimpleViewportPreset.allCases[index] == .custom
        widthField.isEditable = isCustom
        heightField.isEditable = isCustom
        widthField.textColor = isCustom ? .labelColor : .secondaryLabelColor
        heightField.textColor = isCustom ? .labelColor : .secondaryLabelColor
    }

    private func updateCustomUAEditability() {
        let isCustom = selectedBrowserIdentity() == .custom
        customUAField.isEditable = isCustom
        customUAField.isEnabled = isCustom
        customUAField.textColor = isCustom ? .labelColor : .secondaryLabelColor
    }

    private func updateEffectiveUAPreview() {
        guard let mode = selectedWebsiteMode(),
              let identity = selectedBrowserIdentity() else {
            effectiveUAField.stringValue = L10n.tr("Unavailable", "不可用")
            return
        }

        let custom = customUAField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let ua = UserAgentProvider.userAgent(
            for: identity,
            websiteMode: mode,
            customUserAgent: custom.isEmpty ? nil : custom
        )
        effectiveUAField.stringValue = ua
        effectiveUAField.toolTip = ua
    }

    private static func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        return label
    }

    private static func secondaryLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 0
        label.widthAnchor.constraint(lessThanOrEqualToConstant: 360).isActive = true
        return label
    }
}

struct BookmarkBarSection: Equatable {
    let title: String
    let folderID: UUID?
    let directBookmarks: [BookmarkItem]
    let childFolders: [BookmarkFolder]

    var isEmpty: Bool {
        directBookmarks.isEmpty && childFolders.isEmpty
    }
}

@MainActor
enum WebAppEditorBookmarkMenuBuilder {
    static func rootSections(
        folders: [BookmarkFolder],
        bookmarks: [BookmarkItem]
    ) -> [BookmarkBarSection] {
        let validFolderIDs = Set(folders.map(\.id))
        let rootFolders = folders
            .filter { folder in
                guard let parentID = folder.parentFolderID else { return true }
                return !validFolderIDs.contains(parentID)
            }
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.createdAt < $1.createdAt
            }

        let sortedBookmarks = bookmarks.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.createdAt < $1.createdAt
        }
        let uncategorizedBookmarks = sortedBookmarks.filter { item in
            guard let folderID = item.folderID else { return true }
            return !validFolderIDs.contains(folderID)
        }

        var sections: [BookmarkBarSection] = []
        if !uncategorizedBookmarks.isEmpty {
            sections.append(
                BookmarkBarSection(
                    title: L10n.tr("General", "通用"),
                    folderID: nil,
                    directBookmarks: uncategorizedBookmarks,
                    childFolders: []
                )
            )
        }

        for folder in rootFolders {
            let children = childFolders(of: folder.id, in: folders)
            let direct = sortedBookmarks.filter { $0.folderID == folder.id }
            sections.append(
                BookmarkBarSection(
                    title: folder.name,
                    folderID: folder.id,
                    directBookmarks: direct,
                    childFolders: children
                )
            )
        }

        return sections
    }

    static func makeCascadingMenu(
        for folderID: UUID?,
        title: String,
        folders: [BookmarkFolder],
        bookmarks: [BookmarkItem],
        onSelectBookmark: @escaping (BookmarkItem) -> Void
    ) -> NSMenu {
        var visited = Set<UUID>()
        if let folderID {
            visited.insert(folderID)
        }
        return buildMenu(
            folderID: folderID,
            title: title,
            folders: folders,
            bookmarks: bookmarks,
            visitedFolderIDs: &visited,
            onSelectBookmark: onSelectBookmark
        )
    }

    private static func buildMenu(
        folderID: UUID?,
        title: String,
        folders: [BookmarkFolder],
        bookmarks: [BookmarkItem],
        visitedFolderIDs: inout Set<UUID>,
        onSelectBookmark: @escaping (BookmarkItem) -> Void
    ) -> NSMenu {
        let menu = NSMenu(title: title)
        let validFolderIDs = Set(folders.map(\.id))

        let subfolders = folderID.map { childFolders(of: $0, in: folders) } ?? []
        let directBookmarks = bookmarks
            .filter { item in
                if let folderID {
                    return item.folderID == folderID
                }
                guard let itemFolderID = item.folderID else { return true }
                return !validFolderIDs.contains(itemFolderID)
            }
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.createdAt < $1.createdAt
            }

        for child in subfolders {
            guard !visitedFolderIDs.contains(child.id) else { continue }
            visitedFolderIDs.insert(child.id)
            let submenu = buildMenu(
                folderID: child.id,
                title: child.name,
                folders: folders,
                bookmarks: bookmarks,
                visitedFolderIDs: &visitedFolderIDs,
                onSelectBookmark: onSelectBookmark
            )
            let item = NSMenuItem(title: child.name, action: nil, keyEquivalent: "")
            item.image = NSImage(
                systemSymbolName: "folder",
                accessibilityDescription: nil
            )
            item.submenu = submenu
            menu.addItem(item)
        }

        if !subfolders.isEmpty && !directBookmarks.isEmpty {
            menu.addItem(.separator())
        }

        for bookmark in directBookmarks {
            let host = bookmark.url.host ?? bookmark.url.absoluteString
            let item = NSMenuItem(
                title: "\(bookmark.title) — \(host)",
                action: #selector(BookmarkMenuActionDispatcher.selectBookmark(_:)),
                keyEquivalent: ""
            )
            item.image = NSImage(
                systemSymbolName: "bookmark",
                accessibilityDescription: nil
            )
            item.toolTip = bookmark.url.absoluteString
            item.target = BookmarkMenuActionDispatcher.shared
            item.representedObject = BookmarkMenuSelectionPayload(
                bookmark: bookmark,
                onSelect: onSelectBookmark
            )
            menu.addItem(item)
        }

        if menu.items.isEmpty {
            let emptyItem = NSMenuItem(
                title: L10n.tr("(Empty Folder)", "（空文件夹）"),
                action: nil,
                keyEquivalent: ""
            )
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        }

        return menu
    }

    private static func childFolders(
        of parentID: UUID,
        in folders: [BookmarkFolder]
    ) -> [BookmarkFolder] {
        folders
            .filter { $0.parentFolderID == parentID }
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.createdAt < $1.createdAt
            }
    }
}

@MainActor
private final class BookmarkMenuSelectionPayload: NSObject {
    let bookmark: BookmarkItem
    let onSelect: (BookmarkItem) -> Void

    init(bookmark: BookmarkItem, onSelect: @escaping (BookmarkItem) -> Void) {
        self.bookmark = bookmark
        self.onSelect = onSelect
    }
}

@MainActor
private final class BookmarkMenuActionDispatcher: NSObject {
    static let shared = BookmarkMenuActionDispatcher()

    @objc func selectBookmark(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? BookmarkMenuSelectionPayload else {
            return
        }
        payload.onSelect(payload.bookmark)
    }
}

@MainActor
private final class AddWebAppBookmarkPickerView: NSView {
    private let folders: [BookmarkFolder]
    private let bookmarks: [BookmarkItem]
    private let onSelectBookmark: (BookmarkItem) -> Void
    private let onManageBookmarks: () -> Void
    private var openMenus: [NSMenu] = []

    init(
        folders: [BookmarkFolder],
        bookmarks: [BookmarkItem],
        onSelectBookmark: @escaping (BookmarkItem) -> Void,
        onManageBookmarks: @escaping () -> Void
    ) {
        self.folders = folders
        self.bookmarks = bookmarks
        self.onSelectBookmark = onSelectBookmark
        self.onManageBookmarks = onManageBookmarks
        super.init(frame: .zero)

        let titleLabel = NSTextField(labelWithString: L10n.tr("Bookmarks", "书签"))
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)

        let hintLabel = NSTextField(
            labelWithString: L10n.tr(
                "Hover folder to browse · Click to fill",
                "悬停展开文件夹 · 点击自动填入"
            )
        )
        hintLabel.font = .systemFont(ofSize: 10.5)
        hintLabel.textColor = .secondaryLabelColor

        let manageButton = NSButton(
            title: L10n.tr("Manage…", "管理…"),
            target: self,
            action: #selector(manageClicked)
        )
        manageButton.bezelStyle = .rounded
        manageButton.controlSize = .small
        manageButton.keyEquivalent = ""

        let header = NSStackView(views: [titleLabel, hintLabel, NSView(), manageButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 6

        let container = NSStackView(views: [header])
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 6
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)

        let sections = WebAppEditorBookmarkMenuBuilder.rootSections(
            folders: folders,
            bookmarks: bookmarks
        )

        if sections.isEmpty {
            let emptyLabel = NSTextField(
                wrappingLabelWithString: L10n.tr(
                    "No saved bookmarks yet. Right-click a tab or click Manage… to organize bookmarks.",
                    "暂无保存的书签。右键任意标签页或点击“管理…”即可添加与整理。"
                )
            )
            emptyLabel.font = .systemFont(ofSize: 11)
            emptyLabel.textColor = .secondaryLabelColor
            container.addArrangedSubview(emptyLabel)
            emptyLabel.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
        } else {
            let barRowsStack = NSStackView()
            barRowsStack.orientation = .vertical
            barRowsStack.alignment = .leading
            barRowsStack.spacing = 5
            barRowsStack.translatesAutoresizingMaskIntoConstraints = false

            let maxBarWidth: CGFloat = 388
            var currentRow = makeFolderRowStack()
            var currentRowWidth: CGFloat = 0

            for section in sections {
                let button = BookmarkFolderTriggerButton(
                    section: section,
                    buildMenu: { [weak self] targetSection in
                        guard let self else { return NSMenu(title: targetSection.title) }
                        let menu = WebAppEditorBookmarkMenuBuilder.makeCascadingMenu(
                            for: targetSection.folderID,
                            title: targetSection.title,
                            folders: self.folders,
                            bookmarks: self.bookmarks,
                            onSelectBookmark: self.onSelectBookmark
                        )
                        self.openMenus = [menu]
                        return menu
                    }
                )
                let buttonWidth = max(button.fittingSize.width, 64)
                if currentRowWidth > 0 && currentRowWidth + 6 + buttonWidth > maxBarWidth {
                    barRowsStack.addArrangedSubview(currentRow)
                    currentRow = makeFolderRowStack()
                    currentRowWidth = 0
                }
                currentRow.addArrangedSubview(button)
                currentRowWidth += (currentRowWidth > 0 ? 6 : 0) + buttonWidth
            }
            if !currentRow.arrangedSubviews.isEmpty {
                barRowsStack.addArrangedSubview(currentRow)
            }

            let barSurface = NSView()
            barSurface.wantsLayer = true
            barSurface.layer?.cornerRadius = 7
            barSurface.layer?.backgroundColor = NSColor.controlBackgroundColor
                .withAlphaComponent(0.55)
                .cgColor
            barSurface.layer?.borderColor = NSColor.separatorColor
                .withAlphaComponent(0.35)
                .cgColor
            barSurface.layer?.borderWidth = 1
            barSurface.translatesAutoresizingMaskIntoConstraints = false
            barSurface.addSubview(barRowsStack)

            NSLayoutConstraint.activate([
                barRowsStack.leadingAnchor.constraint(equalTo: barSurface.leadingAnchor, constant: 6),
                barRowsStack.trailingAnchor.constraint(lessThanOrEqualTo: barSurface.trailingAnchor, constant: -6),
                barRowsStack.topAnchor.constraint(equalTo: barSurface.topAnchor, constant: 6),
                barRowsStack.bottomAnchor.constraint(equalTo: barSurface.bottomAnchor, constant: -6),
            ])

            container.addArrangedSubview(barSurface)
            barSurface.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
        }

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            header.widthAnchor.constraint(equalTo: container.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeFolderRowStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        return stack
    }

    @objc private func manageClicked() {
        onManageBookmarks()
    }
}

@MainActor
private final class BookmarkFolderTriggerButton: NSView, NSMenuDelegate {
    private let section: BookmarkBarSection
    private let buildMenu: (BookmarkBarSection) -> NSMenu
    private let titleLabel = NSTextField(labelWithString: "")
    private var trackingAreaReference: NSTrackingArea?
    private var hoverWorkItem: DispatchWorkItem?
    private var isHovered = false
    private var suppressNextHoverOpenUntilExit = false

    init(
        section: BookmarkBarSection,
        buildMenu: @escaping (BookmarkBarSection) -> NSMenu
    ) {
        self.section = section
        self.buildMenu = buildMenu
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 5
        translatesAutoresizingMaskIntoConstraints = false

        let iconName = section.folderID == nil ? "tray.full" : "folder"
        let iconView = NSImageView()
        if let symbol = NSImage(
            systemSymbolName: iconName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 10.5, weight: .medium)
        ) {
            iconView.image = symbol
        }
        iconView.contentTintColor = .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = section.title
        titleLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        let chevron = NSImageView()
        if let symbol = NSImage(
            systemSymbolName: "chevron.right",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 8.5, weight: .semibold)
        ) {
            chevron.image = symbol
        }
        chevron.contentTintColor = .tertiaryLabelColor

        let row = NSStackView(views: [iconView, titleLabel, chevron])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 4
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            widthAnchor.constraint(lessThanOrEqualToConstant: 180),
        ])

        setAccessibilityRole(.menuButton)
        setAccessibilityLabel(section.title)
        applyAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaReference = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        applyAppearance()
        guard !suppressNextHoverOpenUntilExit else { return }
        scheduleHoverMenuOpen()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        suppressNextHoverOpenUntilExit = false
        hoverWorkItem?.cancel()
        hoverWorkItem = nil
        applyAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        hoverWorkItem?.cancel()
        hoverWorkItem = nil
        let local = convert(event.locationInWindow, from: nil)
        guard bounds.contains(local) else { return }
        openCascadingMenu()
    }

    func menuDidClose(_ menu: NSMenu) {
        suppressNextHoverOpenUntilExit = true
        isHovered = false
        applyAppearance()
    }

    private func scheduleHoverMenuOpen() {
        hoverWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isHovered, self.window != nil else { return }
            self.openCascadingMenu()
        }
        hoverWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: work)
    }

    private func openCascadingMenu() {
        guard window != nil else { return }
        let menu = buildMenu(section)
        menu.delegate = self
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: -2),
            in: self
        )
    }

    private func applyAppearance() {
        layer?.backgroundColor = (
            isHovered
                ? NSColor.controlAccentColor.withAlphaComponent(0.14)
                : NSColor.controlBackgroundColor.withAlphaComponent(0.92)
        ).cgColor
        layer?.borderColor = (
            isHovered
                ? NSColor.controlAccentColor.withAlphaComponent(0.45)
                : NSColor.separatorColor.withAlphaComponent(0.35)
        ).cgColor
        layer?.borderWidth = 1
    }
}
