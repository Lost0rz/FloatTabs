from pathlib import Path
import re


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


# AppCommandController: rename the command/overlay semantics from Quick URL to Address Bar.
path = Path("FloatTabs/Hotkeys/AppCommandController.swift")
text = path.read_text()
for old, new in [
    ("case quickURL", "case addressBar"),
    (".quickURL", ".addressBar"),
    ("QuickURLOverlayView", "AddressOverlayView"),
    ("presentedQuickURLOverlay", "presentedAddressOverlay"),
    ("shouldDismissQuickURL", "shouldDismissAddressBar"),
    ("firstPresentedQuickURLOverlay", "firstPresentedAddressOverlay"),
]:
    text = text.replace(old, new)
path.write_text(text)


# TabStore: explicit derived-Web-App API that copies source configuration only.
path = Path("FloatTabs/Tabs/TabStore.swift")
text = path.read_text()
anchor = """    @discardableResult
    func update(
"""
insert = """    @discardableResult
    func addDerived(
        from sourceID: UUID,
        name: String,
        homeURL: URL,
        now: Date = Date()
    ) -> WebAppProfile? {
        guard WebAppURL.isSafe(homeURL),
              let source = profiles.first(where: { $0.id == sourceID }) else {
            return nil
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        let profile = WebAppProfile(
            order: orderedProfiles.count,
            name: trimmedName,
            homeURL: homeURL,
            currentURL: homeURL,
            renderingProfile: source.renderingProfile.normalized(),
            residencyPolicy: source.residencyPolicy,
            backgroundMediaPolicy: source.backgroundMediaPolicy,
            createdAt: now,
            lastUsedAt: now
        )

        profiles.append(profile)
        normalizeInPlace()
        activeTabID = profile.id
        persistAndNotify()
        return profiles.first(where: { $0.id == profile.id })
    }

""" + anchor
text = replace_once(text, anchor, insert, "TabStore addDerived insertion")
path.write_text(text)


# WebAppEditorController: compact name-only creation flow for current-page derivation.
path = Path("FloatTabs/UI/WebAppEditorController.swift")
text = path.read_text()
anchor = """    static func presentEdit(
"""
method = '''    static func presentDerivedAdd(
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

''' + anchor
text = replace_once(text, anchor, method, "presentDerivedAdd insertion")
path.write_text(text)


# PanelController: replace Quick URL with an address bar + copy + derive actions.
path = Path("FloatTabs/Panel/PanelController.swift")
text = path.read_text()

# Identifier-level semantic rename.
for old, new in [
    ("quickURLOverlayView", "addressOverlayView"),
    ("QuickURLOverlayView", "AddressOverlayView"),
    ("presentQuickURL", "presentAddressBar"),
    ("commitQuickURL", "commitAddress"),
    ("case .quickURL:", "case .addressBar:"),
]:
    text = text.replace(old, new)

old_callbacks = '''        addressOverlayView.onCommit = { [weak self] rawValue in
            self?.commitAddress(rawValue) ?? false
        }
        addressOverlayView.onDismiss = { [weak self] in
            self?.focusActiveWebViewIfAvailable()
        }
'''
new_callbacks = '''        addressOverlayView.onCommit = { [weak self] rawValue in
            self?.commitAddress(rawValue) ?? false
        }
        addressOverlayView.onCopy = { [weak self] rawValue in
            self?.copyAddressToPasteboard(rawValue) ?? false
        }
        addressOverlayView.onCreateWebApp = { [weak self] in
            self?.presentDerivedWebAppFromCurrentPage()
        }
        addressOverlayView.onDismiss = { [weak self] in
            self?.focusActiveWebViewIfAvailable()
        }
'''
text = replace_once(text, old_callbacks, new_callbacks, "address overlay callbacks")

pattern = re.compile(
    r'''    private func presentAddressBar\(\) \{.*?(?=    private func handleManualResizeEnded\(\))''',
    re.S,
)
replacement = '''    private func presentAddressBar() {
        guard let url = currentAddressURL() else { return }
        addressOverlayView.present(url: url, in: panel)
    }

    private func currentAddressURL() -> URL? {
        if let webURL = rootView.webPanelContainerView.currentWebView?.url,
           WebAppURL.isSafe(webURL) {
            return webURL
        }
        guard let profile = tabStore.activeProfile else { return nil }
        if let currentURL = profile.currentURL, WebAppURL.isSafe(currentURL) {
            return currentURL
        }
        return WebAppURL.isSafe(profile.homeURL) ? profile.homeURL : nil
    }

    private func commitAddress(_ rawValue: String) -> Bool {
        guard let id = tabStore.activeTabID,
              let url = WebAppURL.normalized(from: rawValue) else {
            NSSound.beep()
            addressOverlayView.markInvalid()
            return false
        }

        tabStore.updateCurrentURL(id: id, url: url)
        webViewPool.navigate(slotID: id, to: url)
        addressOverlayView.dismiss()
        focusActiveWebViewIfAvailable()
        return true
    }

    private func copyAddressToPasteboard(_ rawValue: String) -> Bool {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(value, forType: .string)
    }

    private func presentDerivedWebAppFromCurrentPage() {
        guard panel.attachedSheet == nil,
              let source = tabStore.activeProfile,
              let currentURL = currentAddressURL() else {
            return
        }

        let sourceID = source.id
        addressOverlayView.dismiss()
        WebAppEditorController.presentDerivedAdd(
            sourceProfile: source,
            currentURL: currentURL,
            attachedTo: panel
        ) { [weak self] name in
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.focusActiveWebViewIfAvailable() }
                guard let name else { return }
                _ = self.tabStore.addDerived(
                    from: sourceID,
                    name: name,
                    homeURL: currentURL
                )
            }
        }
    }

'''
text, count = pattern.subn(replacement, text, count=1)
if count != 1:
    raise SystemExit(f"PanelController address actions: expected one block, found {count}")

# Replace the old overlay implementation and field subclass entirely.
overlay_pattern = re.compile(
    r'''@MainActor\nfinal class AddressOverlayView: NSVisualEffectView \{.*?(?=@MainActor\nfinal class ZoomHUDView)''',
    re.S,
)
new_overlay = '''@MainActor
final class AddressOverlayView: NSVisualEffectView, NSTextFieldDelegate {
    var onCommit: ((String) -> Bool)?
    var onCopy: ((String) -> Bool)?
    var onCreateWebApp: (() -> Void)?
    var onDismiss: (() -> Void)?

    let field = NSTextField()
    private let icon = NSImageView()
    private let copyButton = NSButton()
    private let createButton = NSButton(title: "New App", target: nil, action: nil)
    private var copyFeedbackWorkItem: DispatchWorkItem?
    private(set) var isPresented = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true

        icon.image = NSImage(systemSymbolName: "link", accessibilityDescription: "URL")
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = .systemFont(ofSize: 14, weight: .medium)
        field.placeholderString = "https://example.com"
        field.focusRingType = .none
        field.delegate = self

        copyButton.image = NSImage(
            systemSymbolName: "doc.on.doc",
            accessibilityDescription: "Copy URL"
        )
        copyButton.toolTip = "Copy URL"
        copyButton.bezelStyle = .inline
        copyButton.isBordered = false
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.target = self
        copyButton.action = #selector(copyPressed(_:))

        createButton.toolTip = "Create a new Web App from the current page"
        createButton.bezelStyle = .rounded
        createButton.controlSize = .small
        createButton.translatesAutoresizingMaskIntoConstraints = false
        createButton.target = self
        createButton.action = #selector(createPressed(_:))

        addSubview(icon)
        addSubview(field)
        addSubview(copyButton)
        addSubview(createButton)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),

            field.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),

            copyButton.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: 8),
            copyButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            copyButton.widthAnchor.constraint(equalToConstant: 26),
            copyButton.heightAnchor.constraint(equalToConstant: 26),

            createButton.leadingAnchor.constraint(equalTo: copyButton.trailingAnchor, constant: 6),
            createButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            createButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            createButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 66),
        ])

        isHidden = true
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(url: URL, in window: NSWindow) {
        copyFeedbackWorkItem?.cancel()
        restoreCopyIcon()
        field.textColor = .labelColor
        field.stringValue = url.absoluteString
        isHidden = false
        isPresented = true
        window.makeFirstResponder(field)
        field.selectText(nil)
    }

    func dismiss() {
        copyFeedbackWorkItem?.cancel()
        restoreCopyIcon()
        isHidden = true
        isPresented = false
        field.textColor = .labelColor
    }

    func markInvalid() {
        field.textColor = .systemRed
        field.selectText(nil)
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        let commandName = NSStringFromSelector(commandSelector)
        if commandSelector == #selector(NSResponder.insertNewline(_:))
            || commandName == "insertNewlineIgnoringFieldEditor:" {
            _ = onCommit?(field.stringValue)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            dismiss()
            onDismiss?()
            return true
        }
        return false
    }

    @objc private func copyPressed(_ sender: NSButton) {
        guard onCopy?(field.stringValue) == true else { return }
        copyFeedbackWorkItem?.cancel()
        copyButton.image = NSImage(
            systemSymbolName: "checkmark",
            accessibilityDescription: "Copied"
        )
        let workItem = DispatchWorkItem { [weak self] in
            self?.restoreCopyIcon()
        }
        copyFeedbackWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }

    @objc private func createPressed(_ sender: NSButton) {
        onCreateWebApp?()
    }

    private func restoreCopyIcon() {
        copyButton.image = NSImage(
            systemSymbolName: "doc.on.doc",
            accessibilityDescription: "Copy URL"
        )
    }
}

'''
text, count = overlay_pattern.subn(new_overlay, text, count=1)
if count != 1:
    raise SystemExit(f"AddressOverlay replacement: expected one block, found {count}")
path.write_text(text)


# AppCommandControllerTests: semantic rename + real Field Editor return regression.
path = Path("FloatTabsTests/AppCommandControllerTests.swift")
text = path.read_text()
for old, new in [
    (".quickURL", ".addressBar"),
    ("QuickURL", "AddressBar"),
    ("QuickURLOverlayView", "AddressOverlayView"),
    ("presentedQuickURLOverlay", "presentedAddressOverlay"),
    ("shouldDismissQuickURL", "shouldDismissAddressBar"),
]:
    text = text.replace(old, new)
marker = '''        XCTAssertTrue(AppCommandController.shouldDismissAddressBar(for: outsideClick, overlay: overlay))
    }
}
'''
addition = '''        XCTAssertTrue(AppCommandController.shouldDismissAddressBar(for: outsideClick, overlay: overlay))
    }

    func testAddressOverlayFieldEditorReturnCommitsEnteredValue() {
        let overlay = AddressOverlayView()
        let editor = NSTextView()
        var committed: String?
        overlay.onCommit = { value in
            committed = value
            return true
        }
        overlay.field.stringValue = "example.com/project"

        XCTAssertTrue(
            overlay.control(
                overlay.field,
                textView: editor,
                doCommandBy: #selector(NSResponder.insertNewline(_:))
            )
        )
        XCTAssertEqual(committed, "example.com/project")
    }
}
'''
text = replace_once(text, marker, addition, "AddressOverlay return test insertion")
path.write_text(text)


# TabStoreTests: clone semantics and validation.
path = Path("FloatTabsTests/TabStoreTests.swift")
text = path.read_text()
anchor = '''    func testActiveSelectionUpdatesIdentity() {
'''
test = '''    func testDerivedWebAppCopiesSourceConfigurationAndUsesCurrentPageAsHome() {
        let repository = MemoryProfileRepository()
        let store = TabStore(repository: repository)
        let rendering = WebRenderingProfile(
            websiteMode: .mobile,
            browserIdentity: .androidChrome,
            customUserAgent: nil,
            sizePreset: .small,
            devicePresetID: nil,
            orientation: .landscape,
            viewportWidth: 780,
            viewportHeight: 390,
            zoom: 1.25
        )
        let source = store.add(
            name: "Source",
            homeURL: urlA,
            renderingProfile: rendering
        )!
        XCTAssertTrue(
            store.updateResourcePolicy(
                id: source.id,
                residencyPolicy: .hot,
                backgroundMediaPolicy: .allowBackgroundAudio
            )
        )

        let derived = store.addDerived(
            from: source.id,
            name: "Project",
            homeURL: urlC,
            now: Date(timeIntervalSince1970: 999)
        )!

        let updatedSource = try! XCTUnwrap(store.profiles.first(where: { $0.id == source.id }))
        XCTAssertNotEqual(derived.id, source.id)
        XCTAssertEqual(derived.name, "Project")
        XCTAssertEqual(derived.homeURL, urlC)
        XCTAssertEqual(derived.currentURL, urlC)
        XCTAssertEqual(derived.renderingProfile, updatedSource.renderingProfile)
        XCTAssertEqual(derived.residencyPolicy, .hot)
        XCTAssertEqual(derived.backgroundMediaPolicy, .allowBackgroundAudio)
        XCTAssertEqual(store.activeTabID, derived.id)
        XCTAssertEqual(store.orderedProfiles.map(\\.order), [0, 1])

        let relaunched = TabStore(repository: repository)
        let restored = try! XCTUnwrap(relaunched.profiles.first(where: { $0.id == derived.id }))
        XCTAssertEqual(restored.homeURL, urlC)
        XCTAssertEqual(restored.currentURL, urlC)
        XCTAssertEqual(restored.renderingProfile, updatedSource.renderingProfile)
        XCTAssertEqual(restored.residencyPolicy, .hot)
        XCTAssertEqual(restored.backgroundMediaPolicy, .allowBackgroundAudio)
    }

    func testDerivedWebAppRejectsInvalidSourceNameOrURL() {
        let store = TabStore(repository: MemoryProfileRepository())
        let source = store.add(name: "Source", homeURL: urlA)!

        XCTAssertNil(store.addDerived(from: UUID(), name: "Missing", homeURL: urlB))
        XCTAssertNil(store.addDerived(from: source.id, name: "   ", homeURL: urlB))
        XCTAssertNil(
            store.addDerived(
                from: source.id,
                name: "Unsafe",
                homeURL: URL(string: "file:///tmp/not-safe")!
            )
        )
        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.activeTabID, source.id)
    }

''' + anchor
text = replace_once(text, anchor, test, "TabStore derived tests insertion")
path.write_text(text)
