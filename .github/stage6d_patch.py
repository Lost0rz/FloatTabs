from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected one match, found {count}: {old[:120]!r}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")


def write(path: str, content: str) -> None:
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content, encoding="utf-8")


# ---------------------------------------------------------------------------
# App-level shortcut model: Settings is global app chrome, not a page command.
# ---------------------------------------------------------------------------
replace_once(
    "FloatTabs/Hotkeys/AppCommandController.swift",
    "    case reload\n    case togglePin\n",
    "    case reload\n    case settings\n    case togglePin\n",
)
replace_once(
    "FloatTabs/Hotkeys/AppCommandController.swift",
    "            guard event.type == .keyDown,\n                  self.isEnabled(),\n                  let command = Self.command(for: event) else {\n                return event\n            }\n\n            self.onCommand(command)\n            return nil\n",
    "            guard event.type == .keyDown,\n                  let command = Self.command(for: event) else {\n                return event\n            }\n\n            // Global Settings is application-level chrome. Allow Cmd+, while\n            // FloatTabs is active even when the floating panel itself is hidden.\n            if command == .settings {\n                self.onCommand(command)\n                return nil\n            }\n\n            guard self.isEnabled() else { return event }\n            self.onCommand(command)\n            return nil\n",
)
replace_once(
    "FloatTabs/Hotkeys/AppCommandController.swift",
    "            case \"r\":\n                return .reload\n            case \"-\":\n",
    "            case \"r\":\n                return .reload\n            case \",\":\n                return .settings\n            case \"-\":\n",
)

# ---------------------------------------------------------------------------
# Named configurable global shortcut. Existing Cmd+` is retained as migration
# initial value so accepted Stage 5C behavior does not silently change.
# ---------------------------------------------------------------------------
write(
    "FloatTabs/Hotkeys/GlobalHotkeyController.swift",
    '''import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleFloatTabs = Self(
        "toggleFloatTabs",
        initial: .init(.backtick, modifiers: [.command])
    )
}

@MainActor
final class GlobalHotkeyController {
    private let onToggle: () -> Void

    init(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
        KeyboardShortcuts.onKeyUp(for: .toggleFloatTabs) { [weak self] in
            self?.onToggle()
        }
    }
}
''',
)

# ---------------------------------------------------------------------------
# Dedicated global preference persistence.
# ---------------------------------------------------------------------------
write(
    "FloatTabs/Persistence/AppPreferencesStore.swift",
    '''import AppKit


enum AppAppearanceMode: String, CaseIterable, Equatable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var appKitAppearance: NSAppearance? {
        switch self {
        case .system:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
final class AppPreferencesStore {
    static let appearanceKey = "FloatTabs.appearanceMode"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var appearanceMode: AppAppearanceMode {
        get {
            guard let raw = defaults.string(forKey: Self.appearanceKey),
                  let mode = AppAppearanceMode(rawValue: raw) else {
                return .system
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.appearanceKey)
            applyAppearance(newValue)
        }
    }

    func applyStoredAppearance() {
        applyAppearance(appearanceMode)
    }

    private func applyAppearance(_ mode: AppAppearanceMode) {
        NSApp.appearance = mode.appKitAppearance
    }
}
''',
)

# ---------------------------------------------------------------------------
# One reusable native Settings window. No per-Slot controls live here.
# ---------------------------------------------------------------------------
write(
    "FloatTabs/UI/GlobalSettingsController.swift",
    '''import AppKit
import KeyboardShortcuts

@MainActor
final class GlobalSettingsController: NSObject, NSWindowDelegate {
    private let preferencesStore: AppPreferencesStore
    private lazy var settingsWindow: NSWindow = makeWindow()

    init(preferencesStore: AppPreferencesStore) {
        self.preferencesStore = preferencesStore
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
            controller: AccountLanguageSettingsViewController(),
            to: tabs
        )

        let window = NSWindow(contentViewController: tabs)
        window.title = "FloatTabs Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 560, height: 390))
        window.minSize = NSSize(width: 520, height: 360)
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
        labels: AppAppearanceMode.allCases.map(\\.displayName),
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
        root.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = Self.titleLabel("Interface Appearance")
        let detail = Self.detailLabel(
            "Controls FloatTabs chrome only. Website content is not restyled or injected."
        )
        appearanceControl.segmentStyle = .rounded
        appearanceControl.target = self
        appearanceControl.action = #selector(appearanceChanged(_:))
        appearanceControl.selectedSegment = AppAppearanceMode.allCases.firstIndex(
            of: preferencesStore.appearanceMode
        ) ?? 0

        let stack = NSStackView(views: [titleLabel, detail, appearanceControl])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            appearanceControl.widthAnchor.constraint(equalToConstant: 250),
        ])
        view = root
    }

    @objc private func appearanceChanged(_ sender: NSSegmentedControl) {
        guard AppAppearanceMode.allCases.indices.contains(sender.selectedSegment) else { return }
        preferencesStore.appearanceMode = AppAppearanceMode.allCases[sender.selectedSegment]
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
        label.widthAnchor.constraint(lessThanOrEqualToConstant: 470).isActive = true
        return label
    }
}

@MainActor
private final class ShortcutsSettingsViewController: NSViewController {
    override func loadView() {
        let root = NSView()
        let heading = sectionTitle("Global Show / Hide")
        let detail = detailLabel(
            "This shortcut works from other apps. Changing it replaces the previous global binding immediately."
        )
        let recorder = KeyboardShortcuts.RecorderCocoa(for: .toggleFloatTabs)
        recorder.translatesAutoresizingMaskIntoConstraints = false

        let recorderRow = NSStackView(views: [label("Show / Hide FloatTabs"), recorder])
        recorderRow.orientation = .horizontal
        recorderRow.alignment = .centerY
        recorderRow.spacing = 12
        recorderRow.distribution = .fill

        let fixedHeading = sectionTitle("FloatTabs Shortcuts")
        let fixedDetail = detailLabel("Page shortcuts are fixed in V1; only global Show / Hide is configurable here.")
        let rows = [
            shortcutRow("Select Slot", "⌘1…⌘9"),
            shortcutRow("Next / Previous Slot", "⌃Tab / ⌃⇧Tab"),
            shortcutRow("Add Web App", "⌘T"),
            shortcutRow("Quick URL", "⌘L"),
            shortcutRow("Return Home", "⌘⇧H"),
            shortcutRow("Reload", "⌘R"),
            shortcutRow("Zoom", "⌘+ / ⌘- / ⌘0"),
            shortcutRow("Pin / Auto-hide", "⌘⇧P"),
            shortcutRow("Global Settings", "⌘,"),
        ]

        let stack = NSStackView(views: [heading, detail, recorderRow, spacer(8), fixedHeading, fixedDetail] + rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            recorder.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
        ])
        view = root
    }

    private func shortcutRow(_ action: String, _ shortcut: String) -> NSView {
        let actionLabel = label(action)
        actionLabel.widthAnchor.constraint(equalToConstant: 190).isActive = true
        let shortcutLabel = NSTextField(labelWithString: shortcut)
        shortcutLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        shortcutLabel.textColor = .secondaryLabelColor
        let row = NSStackView(views: [actionLabel, shortcutLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
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
        value.widthAnchor.constraint(lessThanOrEqualToConstant: 490).isActive = true
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
    override func loadView() {
        let root = NSView()
        let stack = NSStackView(views: [
            sectionTitle("Account"),
            detailLabel(
                "FloatTabs V1 is local-only. It does not require a FloatTabs cloud account or sync service."
            ),
            detailLabel(
                "Web App profiles and app preferences stay on this Mac. Website login/session data remains in the persistent WebKit website data store."
            ),
            spacer(12),
            sectionTitle("Language"),
            detailLabel(
                "A per-app language override is not exposed in this stage. No non-functional language selector is shown."
            ),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
        ])
        view = root
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
        value.widthAnchor.constraint(lessThanOrEqualToConstant: 490).isActive = true
        return value
    }

    private func spacer(_ height: CGFloat) -> NSView {
        let view = NSView()
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }
}
''',
)

# ---------------------------------------------------------------------------
# AppCoordinator owns global settings and routes all application-level entries.
# ---------------------------------------------------------------------------
replace_once(
    "FloatTabs/App/AppCoordinator.swift",
    "    private var appCommandController: AppCommandController?\n",
    "    private var appCommandController: AppCommandController?\n    private let preferencesStore = AppPreferencesStore()\n    private var globalSettingsController: GlobalSettingsController?\n",
)
replace_once(
    "FloatTabs/App/AppCoordinator.swift",
    "    func start() {\n        statusItemController = StatusItemController(\n            onToggle: { [weak self] in self?.toggleFloatTabs() },\n            isVisible: { [weak self] in self?.panelController.isVisible ?? false },\n            onQuit: { NSApp.terminate(nil) }\n        )\n",
    "    func start() {\n        preferencesStore.applyStoredAppearance()\n        globalSettingsController = GlobalSettingsController(preferencesStore: preferencesStore)\n        panelController.onOpenGlobalSettings = { [weak self] in\n            self?.showGlobalSettings()\n        }\n\n        statusItemController = StatusItemController(\n            onToggle: { [weak self] in self?.toggleFloatTabs() },\n            isVisible: { [weak self] in self?.panelController.isVisible ?? false },\n            onSettings: { [weak self] in self?.showGlobalSettings() },\n            onQuit: { NSApp.terminate(nil) }\n        )\n",
)
replace_once(
    "FloatTabs/App/AppCoordinator.swift",
    "            onCommand: { [weak self] command in\n                self?.panelController.handle(command)\n            }\n",
    "            onCommand: { [weak self] command in\n                guard let self else { return }\n                if command == .settings {\n                    self.showGlobalSettings()\n                } else {\n                    self.panelController.handle(command)\n                }\n            }\n",
)
replace_once(
    "FloatTabs/App/AppCoordinator.swift",
    "    private func toggleFloatTabs() {\n",
    "    private func showGlobalSettings() {\n        globalSettingsController?.show()\n    }\n\n    private func toggleFloatTabs() {\n",
)

# ---------------------------------------------------------------------------
# Status item: Settings is a first-class app-level menu command.
# ---------------------------------------------------------------------------
replace_once(
    "FloatTabs/MenuBar/StatusItemController.swift",
    "    private let onToggle: () -> Void\n    private let isVisible: () -> Bool\n    private let onQuit: () -> Void\n",
    "    private let onToggle: () -> Void\n    private let isVisible: () -> Bool\n    private let onSettings: () -> Void\n    private let onQuit: () -> Void\n",
)
replace_once(
    "FloatTabs/MenuBar/StatusItemController.swift",
    "        onToggle: @escaping () -> Void,\n        isVisible: @escaping () -> Bool,\n        onQuit: @escaping () -> Void\n    ) {\n        self.onToggle = onToggle\n        self.isVisible = isVisible\n        self.onQuit = onQuit\n",
    "        onToggle: @escaping () -> Void,\n        isVisible: @escaping () -> Bool,\n        onSettings: @escaping () -> Void,\n        onQuit: @escaping () -> Void\n    ) {\n        self.onToggle = onToggle\n        self.isVisible = isVisible\n        self.onSettings = onSettings\n        self.onQuit = onQuit\n",
)
replace_once(
    "FloatTabs/MenuBar/StatusItemController.swift",
    "        menu.addItem(toggleMenuItem)\n        menu.addItem(.separator())\n\n        let quitItem = NSMenuItem(\n",
    "        menu.addItem(toggleMenuItem)\n        menu.addItem(.separator())\n\n        let settingsItem = NSMenuItem(\n            title: \"Settings…\",\n            action: #selector(openSettings),\n            keyEquivalent: \",\"\n        )\n        settingsItem.keyEquivalentModifierMask = [.command]\n        settingsItem.target = self\n        menu.addItem(settingsItem)\n        menu.addItem(.separator())\n\n        let quitItem = NSMenuItem(\n",
)
replace_once(
    "FloatTabs/MenuBar/StatusItemController.swift",
    "    @objc private func quit() {\n        onQuit()\n    }\n",
    "    @objc private func openSettings() {\n        onSettings()\n    }\n\n    @objc private func quit() {\n        onQuit()\n    }\n",
)

# ---------------------------------------------------------------------------
# Gear becomes Global Settings and is independent of active Slot state.
# ---------------------------------------------------------------------------
p = Path("FloatTabs/UI/ExternalTabRail.swift")
text = p.read_text(encoding="utf-8")
text = text.replace("onCurrentControls", "onSettings")
text = text.replace("currentControls", "settingsControl")
text = text.replace("CurrentWebAppControl", "GlobalSettingsControl")
text = text.replace("Current Web App Controls", "Global Settings")
text = text.replace("currentControlsFrame", "settingsControlFrame")
text = text.replace("        settingsControl.isEnabled = activeTabID != nil\n", "")
marker = "@MainActor\nfinal class GlobalSettingsControl: NSView {"
idx = text.find(marker)
if idx == -1:
    raise RuntimeError("ExternalTabRail.swift: GlobalSettingsControl marker missing after rename")
text = text[:idx] + '''@MainActor
final class GlobalSettingsControl: NSView {
    var onActivate: (() -> Void)?
    var onPointerMoved: ((NSEvent) -> Void)?

    private let imageView = NSImageView()
    private var trackingAreaReference: NSTrackingArea?
    private var isHovered = false
    private var dockInfluence: CGFloat = 0

    var preferredWidth: CGFloat {
        ExternalTabMetrics.systemControlWidth(dockInfluence: dockInfluence)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = ExternalTabMetrics.tabRadius
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        toolTip = "FloatTabs Settings · ⌘,"

        imageView.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Global Settings")
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 13),
            imageView.heightAnchor.constraint(equalToConstant: 13),
        ])
        updateAppearance()
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    func setDockInfluence(_ influence: CGFloat) {
        dockInfluence = min(max(influence, 0), 1)
    }

    func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        updateAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        trackingAreaReference = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        setHovered(true)
        onPointerMoved?(event)
    }

    override func mouseMoved(with event: NSEvent) {
        onPointerMoved?(event)
    }

    override func mouseExited(with event: NSEvent) {
        setHovered(false)
        onPointerMoved?(event)
    }

    override func mouseUp(with event: NSEvent) {
        onActivate?()
    }

    private func updateAppearance() {
        let fraction: CGFloat = isHovered ? 0.10 : 0.02
        layer?.backgroundColor = NSColor.controlBackgroundColor
            .blended(withFraction: fraction, of: .labelColor)?
            .withAlphaComponent(0.94)
            .cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.30).cgColor
        layer?.borderWidth = 1
        imageView.contentTintColor = .labelColor
    }
}
'''
p.write_text(text, encoding="utf-8")

# Panel emits settings intent; obsolete per-slot Current Controls sheet is removed.
replace_once(
    "FloatTabs/Panel/PanelController.swift",
    "    var onSelectedSlotPresentationChange: ((String?, URL?) -> Void)?\n",
    "    var onSelectedSlotPresentationChange: ((String?, URL?) -> Void)?\n    var onOpenGlobalSettings: (() -> Void)?\n",
)
replace_once(
    "FloatTabs/Panel/PanelController.swift",
    "        rail.onCurrentControls = { [weak self] in\n            self?.presentCurrentWebAppControls()\n        }\n",
    "        rail.onSettings = { [weak self] in\n            self?.onOpenGlobalSettings?()\n        }\n",
)
# Handle the already-renamed variant if ExternalTabRail rename doesn't affect PanelController.
panel = Path("FloatTabs/Panel/PanelController.swift")
panel_text = panel.read_text(encoding="utf-8")
panel_text = panel_text.replace(
    "        rail.onCurrentControls = { [weak self] in\n            self?.presentCurrentWebAppControls()\n        }\n",
    "        rail.onSettings = { [weak self] in\n            self?.onOpenGlobalSettings?()\n        }\n"
)
start = panel_text.find("    private func presentCurrentWebAppControls() {")
end = panel_text.find("    private func presentRemoveConfirmation", start)
if start == -1 or end == -1:
    raise RuntimeError("PanelController.swift: current controls method boundaries not found")
panel_text = panel_text[:start] + panel_text[end:]
panel.write_text(panel_text, encoding="utf-8")

# Delete obsolete CurrentWebAppControlsValue + presenter from WebAppEditorController.
p = Path("FloatTabs/UI/WebAppEditorController.swift")
text = p.read_text(encoding="utf-8")
text = text.replace(
    "struct CurrentWebAppControlsValue {\n    var renderingProfile: WebRenderingProfile\n    var followPreferredSize: Bool\n}\n\n",
    ""
)
start = text.find("    static func presentCurrentControls(")
end = text.find("    static func confirmRemove(", start)
if start == -1 or end == -1:
    raise RuntimeError("WebAppEditorController.swift: current controls presenter boundaries not found")
text = text[:start] + text[end:]
p.write_text(text, encoding="utf-8")

# ---------------------------------------------------------------------------
# Tests.
# ---------------------------------------------------------------------------
replace_once(
    "FloatTabsTests/AppCommandControllerTests.swift",
    "        XCTAssertEqual(\n            AppCommandController.command(characters: \"r\", keyCode: 15, modifiers: [.command]),\n            .reload\n        )\n",
    "        XCTAssertEqual(\n            AppCommandController.command(characters: \"r\", keyCode: 15, modifiers: [.command]),\n            .reload\n        )\n        XCTAssertEqual(\n            AppCommandController.command(characters: \",\", keyCode: 43, modifiers: [.command]),\n            .settings\n        )\n",
)
p = Path("FloatTabsTests/ExternalShellTests.swift")
text = p.read_text(encoding="utf-8")
text = text.replace("currentControlsFrame", "settingsControlFrame")
text = text.replace("CurrentWebAppControl", "GlobalSettingsControl")
old_test = '''    func testCurrentWebAppGearUsesActualVisibleHitAreaWhenSlotIsActive() {
        let (_, zone) = makeZoneHarness()
        let active = makeProfile(order: 0, name: "GPT")
        zone.apply(profiles: [active], activeTabID: active.id)
        zone.layoutSubtreeIfNeeded()

        let pointInZone = NSPoint(
            x: zone.settingsControlFrame.midX,
            y: zone.settingsControlFrame.midY
        )
        let pointInSuperview = zone.convert(pointInZone, to: zone.superview)
        XCTAssertTrue(zone.hitTest(pointInSuperview) is GlobalSettingsControl)
    }
'''
new_test = '''    func testGlobalSettingsGearUsesActualVisibleHitAreaWithoutActiveSlot() {
        let (_, zone) = makeZoneHarness()
        zone.apply(profiles: [], activeTabID: nil)
        zone.layoutSubtreeIfNeeded()

        let pointInZone = NSPoint(
            x: zone.settingsControlFrame.midX,
            y: zone.settingsControlFrame.midY
        )
        let pointInSuperview = zone.convert(pointInZone, to: zone.superview)
        XCTAssertTrue(zone.hitTest(pointInSuperview) is GlobalSettingsControl)
    }
'''
if old_test not in text:
    raise RuntimeError("ExternalShellTests.swift: gear test not found")
text = text.replace(old_test, new_test, 1)
p.write_text(text, encoding="utf-8")

write(
    "FloatTabsTests/AppPreferencesStoreTests.swift",
    '''import XCTest
@testable import FloatTabs

@MainActor
final class AppPreferencesStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "FloatTabsTests.AppPreferencesStore.\\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        NSApp.appearance = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testAppearanceDefaultsToSystem() {
        let store = AppPreferencesStore(defaults: defaults)
        XCTAssertEqual(store.appearanceMode, .system)
    }

    func testAppearancePersistsAcrossStoreInstances() {
        let first = AppPreferencesStore(defaults: defaults)
        first.appearanceMode = .dark

        let second = AppPreferencesStore(defaults: defaults)
        XCTAssertEqual(second.appearanceMode, .dark)

        second.appearanceMode = .light
        XCTAssertEqual(AppPreferencesStore(defaults: defaults).appearanceMode, .light)
    }

    func testUnknownAppearanceFallsBackToSystem() {
        defaults.set("future-value", forKey: AppPreferencesStore.appearanceKey)
        XCTAssertEqual(AppPreferencesStore(defaults: defaults).appearanceMode, .system)
    }
}
''',
)

# ---------------------------------------------------------------------------
# Xcode project membership for the new structured files.
# ---------------------------------------------------------------------------
replace_once(
    "FloatTabs.xcodeproj/project.pbxproj",
    "\t\tA0000000000000000000001F /* PopupCoordinator.swift in Sources */ = {isa = PBXBuildFile; fileRef = B00000000000000000000020 /* PopupCoordinator.swift */; };\n",
    "\t\tA0000000000000000000001F /* PopupCoordinator.swift in Sources */ = {isa = PBXBuildFile; fileRef = B00000000000000000000020 /* PopupCoordinator.swift */; };\n\t\tA00000000000000000000023 /* AppPreferencesStore.swift in Sources */ = {isa = PBXBuildFile; fileRef = B00000000000000000000023 /* AppPreferencesStore.swift */; };\n\t\tA00000000000000000000024 /* GlobalSettingsController.swift in Sources */ = {isa = PBXBuildFile; fileRef = B00000000000000000000024 /* GlobalSettingsController.swift */; };\n\t\tA00000000000000000000025 /* AppPreferencesStoreTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = B00000000000000000000025 /* AppPreferencesStoreTests.swift */; };\n",
)
replace_once(
    "FloatTabs.xcodeproj/project.pbxproj",
    "\t\tB00000000000000000000020 /* PopupCoordinator.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PopupCoordinator.swift; sourceTree = \"<group>\"; };\n",
    "\t\tB00000000000000000000020 /* PopupCoordinator.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PopupCoordinator.swift; sourceTree = \"<group>\"; };\n\t\tB00000000000000000000023 /* AppPreferencesStore.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AppPreferencesStore.swift; sourceTree = \"<group>\"; };\n\t\tB00000000000000000000024 /* GlobalSettingsController.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GlobalSettingsController.swift; sourceTree = \"<group>\"; };\n\t\tB00000000000000000000025 /* AppPreferencesStoreTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AppPreferencesStoreTests.swift; sourceTree = \"<group>\"; };\n",
)
replace_once(
    "FloatTabs.xcodeproj/project.pbxproj",
    "\t\t\t\tB00000000000000000000014 /* ProfileRepository.swift */,\n",
    "\t\t\t\tB00000000000000000000014 /* ProfileRepository.swift */,\n\t\t\t\tB00000000000000000000023 /* AppPreferencesStore.swift */,\n",
)
replace_once(
    "FloatTabs.xcodeproj/project.pbxproj",
    "\t\t\t\tB00000000000000000000019 /* EmptyWebAppView.swift */,\n",
    "\t\t\t\tB00000000000000000000019 /* EmptyWebAppView.swift */,\n\t\t\t\tB00000000000000000000024 /* GlobalSettingsController.swift */,\n",
)
replace_once(
    "FloatTabs.xcodeproj/project.pbxproj",
    "\t\t\t\tB0000000000000000000001E /* AppCommandControllerTests.swift */,\n",
    "\t\t\t\tB0000000000000000000001E /* AppCommandControllerTests.swift */,\n\t\t\t\tB00000000000000000000025 /* AppPreferencesStoreTests.swift */,\n",
)
replace_once(
    "FloatTabs.xcodeproj/project.pbxproj",
    "\t\t\t\tA00000000000000000000003 /* AppCoordinator.swift in Sources */,\n",
    "\t\t\t\tA00000000000000000000003 /* AppCoordinator.swift in Sources */,\n\t\t\t\tA00000000000000000000023 /* AppPreferencesStore.swift in Sources */,\n\t\t\t\tA00000000000000000000024 /* GlobalSettingsController.swift in Sources */,\n",
)
replace_once(
    "FloatTabs.xcodeproj/project.pbxproj",
    "\t\t\t\tA0000000000000000000001D /* AppCommandControllerTests.swift in Sources */,\n",
    "\t\t\t\tA0000000000000000000001D /* AppCommandControllerTests.swift in Sources */,\n\t\t\t\tA00000000000000000000025 /* AppPreferencesStoreTests.swift in Sources */,\n",
)

# ---------------------------------------------------------------------------
# Source-of-truth updates: Gear semantic + concrete Stage 6D global settings.
# ---------------------------------------------------------------------------
replace_once(
    "docs/product/FloatTabs_Product_Development_Spec_v0.5.md",
    "- `⚙` = Current Web App / Window Controls；\n",
    "- `⚙` = Global Settings；\n",
)
replace_once(
    "docs/product/FloatTabs_Product_Development_Spec_v0.5.md",
    "# 8. Current Web App Controls (`⚙`)\n\nGear Popover 不是 Global Settings。\n\nPersist per Slot：\n\n```text\nBrowser\nView Mode\nWindow Size\nZoom\n```\n\nWindow/session action：\n\n```text\nPin Window\n```\n\nOne-shot actions：\n\n```text\nReload\nOpen in Default Browser\nEdit Web App…\n```\n\nDo not include：\n\n```text\nFloatTabs Settings…\nLaunch at Login\nGlobal Shortcut\nPerformance\nAppearance\nAbout\nUpdate\n```\n\nGlobal Settings 通过 Menu Bar / `⌘,` 打开。\n\nPin 是当前 panel session state，不写入 WebAppProfile。\n",
    "# 8. Global Settings Gear (`⚙`)\n\nGear 是 FloatTabs application-level Global Settings 的固定入口，不再承担 Current Web App Controls。\n\nEntry：\n\n```text\n⚙\nMenu Bar → Settings…\n⌘,\n```\n\n三者必须进入同一个 native Settings window。Gear 在没有 active Slot 时也保持可用。\n\nPer-Slot 高频控制继续由 Slot context menu + `Edit Web App…` 负责；Pin 继续由独立 Pin control + `⌘⇧P` 负责。不要在 Global Settings 再复制 Website Mode / Window Size / Zoom / Residency / Background Media。\n",
)
replace_once(
    "docs/product/FloatTabs_Product_Development_Spec_v0.5.md",
    "Possible groups：\n\n- Launch at Login；\n- Global Show/Hide shortcut；\n- hide-on-focus-loss behavior；\n- restore last Web App；\n- pause background media；\n- Memory Saver when/if implemented；\n- appearance；\n- Website Data / clear data；\n- About / Version；\n- Update。\n\n不要求额外画完整 UIUX 图；使用 native macOS settings pattern + Design System 即可。\n",
    "Stage 6D root groups：\n\n```text\nAppearance\nShortcuts\nAccount & Language\n```\n\nStage 6D implements：\n\n- Appearance: System / Light / Dark，UserDefaults 持久化并即时应用于 FloatTabs chrome；\n- Shortcuts: Global Show/Hide 使用 KeyboardShortcuts 原生 recorder，现有 `⌘`` 作为迁移初始值；\n- fixed page shortcuts 只读展示，不改语义；\n- Account & Language 只陈述真实 V1 local-only / no cloud account / no per-app language override 边界，不展示假的 Sign In、Sync 或 Language control。\n\nLaunch at Login、Website Data clearing、Update、账号/云同步、语言覆盖与 Accent picker 后续单独进入有真实实现的数据链路后再开放。\n\n不要求额外画完整 UIUX 图；使用 native macOS settings pattern + Design System 即可。\n",
)

replace_once(
    "docs/design/FloatTabs_UI_Design_System_v1.2.md",
    "⚙\n= Current Web App / Window Controls\n",
    "⚙\n= Global Settings\n",
)
replace_once(
    "docs/architecture/FloatTabs_Technical_Architecture_v1.2.md",
    "    ├── Current Web App Controls\n    ├── Add/Edit Web App\n",
    "    ├── Global Settings\n    ├── Add/Edit Web App\n",
)

# Ensure obsolete semantics are gone from production code in this stage.
for path in [
    "FloatTabs/Panel/PanelController.swift",
    "FloatTabs/UI/WebAppEditorController.swift",
    "FloatTabs/UI/ExternalTabRail.swift",
]:
    content = Path(path).read_text(encoding="utf-8")
    if "presentCurrentWebAppControls" in content or "CurrentWebAppControlsValue" in content:
        raise RuntimeError(f"{path}: obsolete Current Web App Controls code remains")
