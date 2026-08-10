import AppKit

struct WebAppEditorValue {
    var name: String
    var url: URL
    var renderingProfile: WebRenderingProfile
}

@MainActor
enum WebAppEditorController {
    static func presentAdd(
        attachedTo window: NSWindow,
        completion: @escaping (WebAppEditorValue?) -> Void
    ) {
        presentEditor(
            title: "Add Web App",
            actionTitle: "Add Web App",
            initialName: "",
            initialURL: "",
            initialRendering: .canonicalDefault,
            showsPrimaryRenderingControls: true,
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
        alert.messageText = "Create Web App from Current Page"
        alert.informativeText = "Creates a new Web App using this page as its Home URL and copies the current Web App's rendering and resource settings."
        alert.addButton(withTitle: "Create Web App")
        alert.addButton(withTitle: "Cancel")

        let nameField = NSTextField(string: "")
        nameField.placeholderString = "New Web App name"
        nameField.widthAnchor.constraint(equalToConstant: 400).isActive = true

        let urlField = NSTextField(labelWithString: currentURL.absoluteString)
        urlField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        urlField.textColor = .secondaryLabelColor
        urlField.isSelectable = true
        urlField.cell?.lineBreakMode = .byTruncatingMiddle
        urlField.widthAnchor.constraint(equalToConstant: 400).isActive = true

        let inherited = NSTextField(
            labelWithString: "Settings copied from \(sourceProfile.name)"
        )
        inherited.font = .systemFont(ofSize: 11, weight: .regular)
        inherited.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [
            makeLabel("Name"),
            nameField,
            makeLabel("Current Page URL"),
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
            guard !name.isEmpty else {
                NSSound.beep()
                completion(nil)
                return
            }

            completion(name)
        }
    }

    static func presentEdit(
        profile: WebAppProfile,
        attachedTo window: NSWindow,
        completion: @escaping (WebAppEditorValue?) -> Void
    ) {
        presentEditor(
            title: "Edit Web App",
            actionTitle: "Save",
            initialName: profile.name,
            initialURL: profile.homeURL.absoluteString,
            initialRendering: profile.renderingProfile,
            showsPrimaryRenderingControls: false,
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
        alert.messageText = "Remove \(profile.name)?"
        alert.informativeText = "The Web App slot will be removed. Shared WebKit website data, cookies, and sessions will not be cleared."
        alert.addButton(withTitle: "Remove Web App")
        alert.addButton(withTitle: "Cancel")
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
        initialRendering: WebRenderingProfile,
        showsPrimaryRenderingControls: Bool,
        attachedTo window: NSWindow,
        completion: @escaping (WebAppEditorValue?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: actionTitle)
        alert.addButton(withTitle: "Cancel")

        let nameField = NSTextField(string: initialName)
        nameField.placeholderString = "Name"
        let urlField = NSTextField(string: initialURL)
        urlField.placeholderString = "https://example.com"

        let nameLabel = makeLabel("Name")
        let urlLabel = makeLabel("URL")
        let renderingForm = RenderingForm(
            initial: initialRendering,
            showsPrimaryRenderingControls: showsPrimaryRenderingControls
        )

        let stack = NSStackView(views: [
            nameLabel,
            nameField,
            urlLabel,
            urlField,
            renderingForm.view,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        stack.setFrameSize(NSSize(
            width: 400,
            height: showsPrimaryRenderingControls ? 350 : 520
        ))
        nameField.widthAnchor.constraint(equalToConstant: 400).isActive = true
        urlField.widthAnchor.constraint(equalToConstant: 400).isActive = true
        renderingForm.view.widthAnchor.constraint(equalToConstant: 400).isActive = true
        alert.accessoryView = stack

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else {
                completion(nil)
                return
            }

            let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty,
                  let url = WebAppURL.normalized(from: urlField.stringValue),
                  let rendering = renderingForm.value() else {
                presentValidationError(attachedTo: window)
                completion(nil)
                return
            }

            completion(
                WebAppEditorValue(
                    name: name,
                    url: url,
                    renderingProfile: rendering
                )
            )
        }
    }

    private static func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        return label
    }

    private static func presentValidationError(attachedTo window: NSWindow) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Enter a valid Web App"
        alert.informativeText = "Name is required, URL must be http/https, Custom Window Size must be at least 320 × 400, and a Custom User Agent cannot be empty."
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }

    private static func presentRenderingValidationError(attachedTo window: NSWindow) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Check rendering settings"
        alert.informativeText = "Custom Window Size must be at least 320 × 400 and a Custom User Agent cannot be empty."
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }
}

@MainActor
private final class RenderingForm: NSObject {
    let view: NSStackView

    private let modePopup = NSPopUpButton()
    private let sizePopup = NSPopUpButton()
    private let widthField = NSTextField()
    private let heightField = NSTextField()
    private let zoomPopup = NSPopUpButton()
    private let advancedButton = NSButton(title: "Advanced…", target: nil, action: nil)

    private let identityPopup = NSPopUpButton()
    private let devicePopup = NSPopUpButton()
    private let orientationPopup = NSPopUpButton()
    private let customUAField = NSTextField()
    private let effectiveUAField = NSTextField(labelWithString: "")
    private let engineValue = NSTextField(labelWithString: "WebKit")
    private let advancedPopover = NSPopover()

    init(
        initial: WebRenderingProfile,
        showsPrimaryRenderingControls: Bool = true
    ) {
        let rendering = initial.normalized()

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
        widthField.placeholderString = "Width"
        heightField.placeholderString = "Height"

        zoomPopup.addItems(withTitles: ZoomSteps.values.map(ZoomSteps.percentageText))
        let normalizedZoom = ZoomSteps.nearest(to: rendering.zoom)
        if let index = ZoomSteps.values.firstIndex(where: { abs($0 - normalizedZoom) < 0.001 }) {
            zoomPopup.selectItem(at: index)
        }

        identityPopup.addItems(withTitles: BrowserIdentity.allCases.map(\.displayName))
        if let index = BrowserIdentity.allCases.firstIndex(of: rendering.browserIdentity) {
            identityPopup.selectItem(at: index)
        }

        devicePopup.addItem(withTitle: "None")
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
            ? [
                Self.label("Website Mode"),
                modePopup,
                Self.label("Window Size"),
                sizeRow,
                Self.label("Zoom"),
                zoomPopup,
                advancedButton,
            ]
            : [
                Self.label("Browser Identity"),
                identityPopup,
                Self.label("Device Preset"),
                devicePopup,
                Self.label("Orientation"),
                orientationPopup,
                Self.label("Custom User Agent"),
                customUAField,
                Self.label("Effective Engine"),
                engineValue,
                Self.label("Effective User Agent"),
                effectiveUAField,
            ]
        view = NSStackView(views: primaryViews)
        view.orientation = .vertical
        view.alignment = .leading
        view.spacing = 5
        modePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 190).isActive = true
        sizePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 190).isActive = true
        zoomPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
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

        if showsPrimaryRenderingControls {
            configureAdvancedPopover()
        }
        updateAutomaticIdentityTitle()
        updateCustomFieldEditability()
        updateCustomUAEditability()
        updateEffectiveUAPreview()
    }

    func value() -> WebRenderingProfile? {
        let modeIndex = modePopup.indexOfSelectedItem
        let sizeIndex = sizePopup.indexOfSelectedItem
        let zoomIndex = zoomPopup.indexOfSelectedItem
        let identityIndex = identityPopup.indexOfSelectedItem
        let orientationIndex = orientationPopup.indexOfSelectedItem

        guard WebsiteMode.allCases.indices.contains(modeIndex),
              SimpleViewportPreset.allCases.indices.contains(sizeIndex),
              ZoomSteps.values.indices.contains(zoomIndex),
              BrowserIdentity.allCases.indices.contains(identityIndex),
              DeviceOrientation.allCases.indices.contains(orientationIndex) else {
            return nil
        }

        let mode = WebsiteMode.allCases[modeIndex]
        let preset = SimpleViewportPreset.allCases[sizeIndex]
        let identity = BrowserIdentity.allCases[identityIndex]
        let orientation = DeviceOrientation.allCases[orientationIndex]

        let size: CGSize
        if let presetSize = preset.size {
            size = presetSize
        } else {
            guard let parsed = parsedCustomSize() else { return nil }
            size = parsed
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
        if let selectedDevice = selectedDevicePreset() {
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

        return WebRenderingProfile(
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
    }

    private func configureAdvancedPopover() {
        let advancedStack = NSStackView(views: [
            Self.label("Browser Identity"),
            identityPopup,
            Self.label("Device Preset"),
            devicePopup,
            Self.label("Orientation"),
            orientationPopup,
            Self.label("Custom User Agent"),
            customUAField,
            Self.label("Effective Engine"),
            engineValue,
            Self.label("Effective User Agent"),
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
        item.title = "Automatic · \(resolved)"
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
            effectiveUAField.stringValue = "Unavailable"
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
}
