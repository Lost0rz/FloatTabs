from pathlib import Path
import re


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    return text.replace(old, new, 1)


def replace_block(text: str, pattern: str, replacement: str, label: str) -> str:
    result, count = re.subn(pattern, replacement, text, count=1, flags=re.S | re.M)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 block, found {count}")
    return result


# -----------------------------------------------------------------------------
# AppPreferencesStore.swift — shared Fixed viewport becomes explicit persisted
# state, separate from every Web App's own saved viewport.
# -----------------------------------------------------------------------------
Path("FloatTabs/Persistence/AppPreferencesStore.swift").write_text(r'''import AppKit

enum AppAppearanceMode: String, CaseIterable, Equatable, Codable {
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

enum PanelBorderTheme: String, CaseIterable, Equatable, Codable {
    case rainbow
    case blue
    case purple
    case pink
    case red
    case orange
    case yellow
    case green
    case graphite
    case custom

    var displayName: String {
        switch self {
        case .rainbow: return "Rainbow"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .red: return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .graphite: return "Graphite"
        case .custom: return "Custom…"
        }
    }

    var solidColor: NSColor? {
        switch self {
        case .rainbow, .custom: return nil
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .pink: return .systemPink
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .graphite: return .systemGray
        }
    }
}

enum PanelWindowSizeMode: String, CaseIterable, Equatable, Codable {
    case perWebApp
    case fixed

    var displayName: String {
        switch self {
        case .perWebApp: return "Per Web App"
        case .fixed: return "Fixed"
        }
    }
}

extension Notification.Name {
    static let floatTabsBorderPreferenceDidChange = Notification.Name(
        "FloatTabs.borderPreferenceDidChange"
    )
    static let floatTabsWindowSizeModeDidChange = Notification.Name(
        "FloatTabs.windowSizeModeDidChange"
    )
    static let floatTabsFixedWindowSizeDidChange = Notification.Name(
        "FloatTabs.fixedWindowSizeDidChange"
    )
}

@MainActor
final class AppPreferencesStore {
    static let appearanceKey = "FloatTabs.appearanceMode"
    static let followPreferredSizeKey = "FloatTabs.followTabPreferredSize"
    static let borderThemeKey = "FloatTabs.borderTheme"
    static let customBorderColorKey = "FloatTabs.customBorderColor"
    static let fixedViewportWidthKey = "FloatTabs.fixedViewportWidth"
    static let fixedViewportHeightKey = "FloatTabs.fixedViewportHeight"
    static let defaultCustomBorderColorHex = "#0A84FFFF"
    static let defaultFixedViewportSize = CGSize(width: 430, height: 820)
    static let minimumFixedViewportSize = CGSize(width: 320, height: 400)

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

    /// Compatibility property retained for RC1 backup documents and callers.
    /// true == each Web App owns a preferred viewport; false == one fixed panel.
    var followPreferredSize: Bool {
        get {
            guard defaults.object(forKey: Self.followPreferredSizeKey) != nil else {
                return true
            }
            return defaults.bool(forKey: Self.followPreferredSizeKey)
        }
        set {
            guard newValue != followPreferredSize else { return }
            defaults.set(newValue, forKey: Self.followPreferredSizeKey)
            NotificationCenter.default.post(
                name: .floatTabsWindowSizeModeDidChange,
                object: self
            )
        }
    }

    var windowSizeMode: PanelWindowSizeMode {
        get { followPreferredSize ? .perWebApp : .fixed }
        set { followPreferredSize = newValue == .perWebApp }
    }

    /// The shared viewport used only while Fixed mode is active. It never
    /// replaces or normalizes any Web App's own renderingProfile viewport.
    var fixedViewportSize: CGSize {
        get {
            guard hasStoredFixedViewportSize else {
                return Self.defaultFixedViewportSize
            }
            let value = CGSize(
                width: defaults.double(forKey: Self.fixedViewportWidthKey),
                height: defaults.double(forKey: Self.fixedViewportHeightKey)
            )
            return Self.normalizedFixedViewportSize(value)
        }
        set {
            let normalized = Self.normalizedFixedViewportSize(newValue)
            let current = fixedViewportSize
            guard !hasStoredFixedViewportSize
                    || abs(current.width - normalized.width) > 0.001
                    || abs(current.height - normalized.height) > 0.001 else {
                return
            }
            defaults.set(Double(normalized.width), forKey: Self.fixedViewportWidthKey)
            defaults.set(Double(normalized.height), forKey: Self.fixedViewportHeightKey)
            NotificationCenter.default.post(
                name: .floatTabsFixedWindowSizeDidChange,
                object: self
            )
        }
    }

    var hasStoredFixedViewportSize: Bool {
        defaults.object(forKey: Self.fixedViewportWidthKey) != nil
            && defaults.object(forKey: Self.fixedViewportHeightKey) != nil
    }

    var borderTheme: PanelBorderTheme {
        get {
            guard let raw = defaults.string(forKey: Self.borderThemeKey),
                  let value = PanelBorderTheme(rawValue: raw) else {
                return .rainbow
            }
            return value
        }
        set {
            guard newValue != borderTheme else { return }
            defaults.set(newValue.rawValue, forKey: Self.borderThemeKey)
            notifyBorderChange()
        }
    }

    var customBorderColorHex: String {
        get {
            let raw = defaults.string(forKey: Self.customBorderColorKey)
                ?? Self.defaultCustomBorderColorHex
            return Self.normalizedColorHex(raw) ?? Self.defaultCustomBorderColorHex
        }
        set {
            guard let normalized = Self.normalizedColorHex(newValue),
                  normalized != customBorderColorHex else { return }
            defaults.set(normalized, forKey: Self.customBorderColorKey)
            notifyBorderChange()
        }
    }

    var customBorderColor: NSColor {
        get { Self.color(fromHex: customBorderColorHex) ?? .systemBlue }
        set {
            guard let hex = Self.hex(from: newValue) else { return }
            customBorderColorHex = hex
        }
    }

    func applyStoredAppearance() {
        applyAppearance(appearanceMode)
    }

    private func applyAppearance(_ mode: AppAppearanceMode) {
        NSApp.appearance = mode.appKitAppearance
    }

    private func notifyBorderChange() {
        NotificationCenter.default.post(
            name: .floatTabsBorderPreferenceDidChange,
            object: self
        )
    }

    static func normalizedFixedViewportSize(_ proposed: CGSize) -> CGSize {
        guard proposed.width.isFinite,
              proposed.height.isFinite,
              proposed.width > 0,
              proposed.height > 0 else {
            return defaultFixedViewportSize
        }
        return CGSize(
            width: max(proposed.width, minimumFixedViewportSize.width),
            height: max(proposed.height, minimumFixedViewportSize.height)
        )
    }

    static func normalizedColorHex(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let body = value.hasPrefix("#") ? String(value.dropFirst()) : value
        let validHex = CharacterSet(charactersIn: "0123456789ABCDEF")
        guard body.count == 6 || body.count == 8,
              body.unicodeScalars.allSatisfy({ validHex.contains($0) }) else {
            return nil
        }
        return "#" + body + (body.count == 6 ? "FF" : "")
    }

    static func color(fromHex raw: String) -> NSColor? {
        guard let normalized = normalizedColorHex(raw) else { return nil }
        let body = String(normalized.dropFirst())
        guard let value = UInt64(body, radix: 16) else { return nil }
        let red = CGFloat((value >> 24) & 0xFF) / 255
        let green = CGFloat((value >> 16) & 0xFF) / 255
        let blue = CGFloat((value >> 8) & 0xFF) / 255
        let alpha = CGFloat(value & 0xFF) / 255
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    static func hex(from color: NSColor) -> String? {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        let red = Int(round(srgb.redComponent * 255))
        let green = Int(round(srgb.greenComponent * 255))
        let blue = Int(round(srgb.blueComponent * 255))
        let alpha = Int(round(srgb.alphaComponent * 255))
        return String(format: "#%02X%02X%02X%02X", red, green, blue, alpha)
    }
}
''')


# -----------------------------------------------------------------------------
# GlobalSettingsController.swift — native flat color palette and Fixed size
# total control.
# -----------------------------------------------------------------------------
settings_path = Path("FloatTabs/UI/GlobalSettingsController.swift")
settings = settings_path.read_text()
settings = replace_once(
    settings,
    'window.setContentSize(NSSize(width: 580, height: 440))\n        window.minSize = NSSize(width: 540, height: 400)',
    'window.setContentSize(NSSize(width: 620, height: 520))\n        window.minSize = NSSize(width: 580, height: 460)',
    'settings window size',
)

appearance_block = r'''@MainActor
private final class AppearanceSettingsViewController: NSViewController {
    private let preferencesStore: AppPreferencesStore
    private let appearanceControl = NSSegmentedControl(
        labels: AppAppearanceMode.allCases.map(\.displayName),
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
private final class SettingsDocumentView'''

settings = replace_block(
    settings,
    r'@MainActor\nprivate final class AppearanceSettingsViewController: NSViewController \{.*?\n\}\n\n@MainActor\nprivate final class SettingsDocumentView',
    appearance_block,
    'appearance settings controller',
)
settings = settings.replace(
    'global appearance, window-size switching preference, and the global Show/Hide shortcut.',
    'global appearance, Fixed shared window size, window-size switching preference, and the global Show/Hide shortcut.',
)
settings_path.write_text(settings)


# -----------------------------------------------------------------------------
# PanelController.swift — Settings and manual resize share one Fixed size source
# of truth while per-Web-App sizes remain untouched.
# -----------------------------------------------------------------------------
panel_path = Path("FloatTabs/Panel/PanelController.swift")
panel = panel_path.read_text()
panel = replace_once(
    panel,
    '''        capturePreviousApplication()\n        positionPanelForCurrentScreens()\n        slotLifecycleCoordinator.setPanelVisible(true, activeProfile: tabStore.activeProfile)'''.replace('\\n', '\n'),
    '''        capturePreviousApplication()\n        positionPanelForCurrentScreens()\n        synchronizeFixedViewportAfterPositioning()\n        slotLifecycleCoordinator.setPanelVisible(true, activeProfile: tabStore.activeProfile)'''.replace('\\n', '\n'),
    'show fixed size sync',
)
panel = replace_once(
    panel,
    '''        NotificationCenter.default.addObserver(\n            self,\n            selector: #selector(windowSizeModeDidChange(_:)),\n            name: .floatTabsWindowSizeModeDidChange,\n            object: preferencesStore\n        )\n    }'''.replace('\\n', '\n'),
    '''        NotificationCenter.default.addObserver(\n            self,\n            selector: #selector(windowSizeModeDidChange(_:)),\n            name: .floatTabsWindowSizeModeDidChange,\n            object: preferencesStore\n        )\n        NotificationCenter.default.addObserver(\n            self,\n            selector: #selector(fixedWindowSizeDidChange(_:)),\n            name: .floatTabsFixedWindowSizeDidChange,\n            object: preferencesStore\n        )\n    }'''.replace('\\n', '\n'),
    'fixed size observer',
)
panel = replace_once(
    panel,
    '''    @objc private func windowSizeModeDidChange(_ notification: Notification) {\n        synchronizeWindowSizeMode()\n        if preferencesStore.windowSizeMode == .perWebApp,\n           let active = tabStore.activeProfile {\n            applyPreferredViewport(active.renderingProfile.viewportSize)\n        }\n    }'''.replace('\\n', '\n'),
    '''    @objc private func windowSizeModeDidChange(_ notification: Notification) {\n        synchronizeWindowSizeMode()\n        switch preferencesStore.windowSizeMode {\n        case .perWebApp:\n            if let active = tabStore.activeProfile {\n                applyPreferredViewport(active.renderingProfile.viewportSize)\n            }\n        case .fixed:\n            guard hasPositionedPanel else { return }\n            if preferencesStore.hasStoredFixedViewportSize {\n                applySharedFixedViewport(preferencesStore.fixedViewportSize, animated: panel.isVisible)\n            } else {\n                let viewport = PanelMetrics.viewportSize(forPanelSize: panel.frame.size)\n                preferencesStore.fixedViewportSize = viewport\n            }\n        }\n    }\n\n    @objc private func fixedWindowSizeDidChange(_ notification: Notification) {\n        guard preferencesStore.windowSizeMode == .fixed else { return }\n        applySharedFixedViewport(preferencesStore.fixedViewportSize, animated: panel.isVisible)\n    }'''.replace('\\n', '\n'),
    'window mode handler',
)
panel = replace_once(
    panel,
    '''    private func handleManualResizeEnded() {\n        clampPanelToConnectedScreens()\n        if Self.shouldPersistManualViewportToActiveTab(\n            windowSizeMode: preferencesStore.windowSizeMode\n        ) {\n            let viewport = PanelMetrics.viewportSize(forPanelSize: panel.frame.size)\n            if let id = tabStore.activeTabID {\n                _ = tabStore.updatePreferredViewport(\n                    id: id,\n                    size: CGSize(width: viewport.width, height: viewport.height)\n                )\n            }\n        }\n        // Fixed mode intentionally persists only the shared panel frame. The\n        // hidden per-Web-App viewport values remain untouched for later restore.\n        persistPanelFrame()\n    }'''.replace('\\n', '\n'),
    '''    private func handleManualResizeEnded() {\n        clampPanelToConnectedScreens()\n        let viewport = PanelMetrics.viewportSize(forPanelSize: panel.frame.size)\n\n        switch preferencesStore.windowSizeMode {\n        case .perWebApp:\n            if let id = tabStore.activeTabID {\n                _ = tabStore.updatePreferredViewport(\n                    id: id,\n                    size: CGSize(width: viewport.width, height: viewport.height)\n                )\n            }\n        case .fixed:\n            // Manual resizing updates only the shared Fixed viewport. Every Web\n            // App keeps its own hidden preferred size for Per Web App mode.\n            preferencesStore.fixedViewportSize = viewport\n        }\n        persistPanelFrame()\n    }'''.replace('\\n', '\n'),
    'manual resize persistence',
)
panel = replace_once(
    panel,
    '''    private func applyPreferredViewport(_ viewportSize: CGSize) {\n        guard preferencesStore.windowSizeMode == .perWebApp,\n              hasPositionedPanel else { return }\n        let visibleFrame = panel.screen?.visibleFrame\n            ?? ScreenPositioning.targetScreen()?.visibleFrame\n        guard let visibleFrame else { return }\n\n        let target = ScreenPositioning.frameFollowingPreferredViewport(\n            currentFrame: panel.frame,\n            preferredViewportSize: NSSize(\n                width: viewportSize.width,\n                height: viewportSize.height\n            ),\n            followPreferredSize: true,\n            visibleFrame: visibleFrame\n        )\n        guard target != panel.frame else { return }\n        panel.setFrame(target, display: true, animate: true)\n        persistPanelFrame()\n    }'''.replace('\\n', '\n'),
    '''    private func applyPreferredViewport(_ viewportSize: CGSize) {\n        guard preferencesStore.windowSizeMode == .perWebApp,\n              hasPositionedPanel else { return }\n        applyViewportSize(viewportSize, animated: true)\n    }\n\n    private func applySharedFixedViewport(_ viewportSize: CGSize, animated: Bool) {\n        guard preferencesStore.windowSizeMode == .fixed,\n              hasPositionedPanel else { return }\n        applyViewportSize(viewportSize, animated: animated)\n    }\n\n    private func applyViewportSize(_ viewportSize: CGSize, animated: Bool) {\n        let visibleFrame = panel.screen?.visibleFrame\n            ?? ScreenPositioning.targetScreen()?.visibleFrame\n        guard let visibleFrame else { return }\n\n        let target = ScreenPositioning.frameFollowingPreferredViewport(\n            currentFrame: panel.frame,\n            preferredViewportSize: NSSize(\n                width: viewportSize.width,\n                height: viewportSize.height\n            ),\n            followPreferredSize: true,\n            visibleFrame: visibleFrame\n        )\n        guard target != panel.frame else { return }\n        panel.setFrame(target, display: true, animate: animated)\n        persistPanelFrame()\n    }\n\n    private func synchronizeFixedViewportAfterPositioning() {\n        guard preferencesStore.windowSizeMode == .fixed,\n              hasPositionedPanel else { return }\n        if preferencesStore.hasStoredFixedViewportSize {\n            applySharedFixedViewport(preferencesStore.fixedViewportSize, animated: false)\n        } else {\n            let viewport = PanelMetrics.viewportSize(forPanelSize: panel.frame.size)\n            preferencesStore.fixedViewportSize = viewport\n        }\n    }'''.replace('\\n', '\n'),
    'viewport application helpers',
)
panel_path.write_text(panel)


# -----------------------------------------------------------------------------
# Backup model + coordinator — include optional Fixed viewport without changing
# schema version, preserving old schema-1 compatibility.
# -----------------------------------------------------------------------------
backup_path = Path("FloatTabs/Persistence/FloatTabsBackupService.swift")
backup = backup_path.read_text()
backup = replace_once(
    backup,
    '''    let borderTheme: PanelBorderTheme?\n    let customBorderColorHex: String?\n\n    init(\n        appearanceMode: AppAppearanceMode,\n        followPreferredSize: Bool,\n        borderTheme: PanelBorderTheme? = nil,\n        customBorderColorHex: String? = nil\n    ) {\n        self.appearanceMode = appearanceMode\n        self.followPreferredSize = followPreferredSize\n        self.borderTheme = borderTheme\n        self.customBorderColorHex = customBorderColorHex\n    }'''.replace('\\n', '\n'),
    '''    let borderTheme: PanelBorderTheme?\n    let customBorderColorHex: String?\n    let fixedViewportWidth: Double?\n    let fixedViewportHeight: Double?\n\n    init(\n        appearanceMode: AppAppearanceMode,\n        followPreferredSize: Bool,\n        borderTheme: PanelBorderTheme? = nil,\n        customBorderColorHex: String? = nil,\n        fixedViewportWidth: Double? = nil,\n        fixedViewportHeight: Double? = nil\n    ) {\n        self.appearanceMode = appearanceMode\n        self.followPreferredSize = followPreferredSize\n        self.borderTheme = borderTheme\n        self.customBorderColorHex = customBorderColorHex\n        self.fixedViewportWidth = fixedViewportWidth\n        self.fixedViewportHeight = fixedViewportHeight\n    }'''.replace('\\n', '\n'),
    'backup fixed viewport fields',
)
backup_path.write_text(backup)

coordinator_path = Path("FloatTabs/App/AppCoordinator.swift")
coordinator = coordinator_path.read_text()
coordinator = replace_once(
    coordinator,
    '''                appearanceMode: preferencesStore.appearanceMode,\n                followPreferredSize: preferencesStore.followPreferredSize,\n                borderTheme: preferencesStore.borderTheme,\n                customBorderColorHex: preferencesStore.customBorderColorHex\n            ),'''.replace('\\n', '\n'),
    '''                appearanceMode: preferencesStore.appearanceMode,\n                followPreferredSize: preferencesStore.followPreferredSize,\n                borderTheme: preferencesStore.borderTheme,\n                customBorderColorHex: preferencesStore.customBorderColorHex,\n                fixedViewportWidth: Double(preferencesStore.fixedViewportSize.width),\n                fixedViewportHeight: Double(preferencesStore.fixedViewportSize.height)\n            ),'''.replace('\\n', '\n'),
    'backup fixed viewport capture',
)
coordinator = replace_once(
    coordinator,
    '''        preferencesStore.followPreferredSize = imported.globalPreferences.followPreferredSize\n        preferencesStore.appearanceMode = imported.globalPreferences.appearanceMode\n        preferencesStore.customBorderColorHex = imported.globalPreferences.customBorderColorHex\n            ?? AppPreferencesStore.defaultCustomBorderColorHex\n        preferencesStore.borderTheme = imported.globalPreferences.borderTheme ?? .rainbow'''.replace('\\n', '\n'),
    '''        preferencesStore.followPreferredSize = imported.globalPreferences.followPreferredSize\n        preferencesStore.appearanceMode = imported.globalPreferences.appearanceMode\n        preferencesStore.customBorderColorHex = imported.globalPreferences.customBorderColorHex\n            ?? AppPreferencesStore.defaultCustomBorderColorHex\n        preferencesStore.borderTheme = imported.globalPreferences.borderTheme ?? .rainbow\n        if let width = imported.globalPreferences.fixedViewportWidth,\n           let height = imported.globalPreferences.fixedViewportHeight {\n            preferencesStore.fixedViewportSize = CGSize(width: width, height: height)\n        }'''.replace('\\n', '\n'),
    'backup fixed viewport restore',
)
coordinator_path.write_text(coordinator)


# -----------------------------------------------------------------------------
# Focused persistence tests.
# -----------------------------------------------------------------------------
tests_path = Path("FloatTabsTests/AppPreferencesStoreTests.swift")
tests = tests_path.read_text()
marker = '\n}'
head, sep, tail = tests.rpartition(marker)
if not sep:
    raise SystemExit('AppPreferencesStoreTests: final class brace not found')
addition = r'''

    func testFixedViewportDefaultsToMediumAndPersistsSeparately() {
        let first = AppPreferencesStore(defaults: defaults)
        XCTAssertFalse(first.hasStoredFixedViewportSize)
        XCTAssertEqual(first.fixedViewportSize.width, 430, accuracy: 0.001)
        XCTAssertEqual(first.fixedViewportSize.height, 820, accuracy: 0.001)

        first.fixedViewportSize = CGSize(width: 777, height: 666)
        XCTAssertTrue(first.hasStoredFixedViewportSize)

        let second = AppPreferencesStore(defaults: defaults)
        XCTAssertEqual(second.fixedViewportSize.width, 777, accuracy: 0.001)
        XCTAssertEqual(second.fixedViewportSize.height, 666, accuracy: 0.001)
        XCTAssertNil(SimpleViewportPreset.matching(second.fixedViewportSize))
    }

    func testFixedViewportUsesStandardPresetAndClampsUnsafeSmallValues() {
        let store = AppPreferencesStore(defaults: defaults)
        let wide = try! XCTUnwrap(SimpleViewportPreset.wide.size)
        store.fixedViewportSize = wide
        XCTAssertEqual(SimpleViewportPreset.matching(store.fixedViewportSize), .wide)

        store.fixedViewportSize = CGSize(width: 100, height: 200)
        XCTAssertEqual(store.fixedViewportSize.width, 320, accuracy: 0.001)
        XCTAssertEqual(store.fixedViewportSize.height, 400, accuracy: 0.001)
    }
'''
tests_path.write_text(head + addition + '\n}' + tail)

print('PR17 appearance polish applied')
