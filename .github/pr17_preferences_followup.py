from pathlib import Path
import re


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    return text.replace(old, new, 1)


def replace_block(text, pattern, replacement, label):
    text, count = re.subn(pattern, replacement, text, count=1, flags=re.S | re.M)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 block, found {count}")
    return text

# AppPreferencesStore.swift
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
}

@MainActor
final class AppPreferencesStore {
    static let appearanceKey = "FloatTabs.appearanceMode"
    static let followPreferredSizeKey = "FloatTabs.followTabPreferredSize"
    static let borderThemeKey = "FloatTabs.borderTheme"
    static let customBorderColorKey = "FloatTabs.customBorderColor"
    static let defaultCustomBorderColorHex = "#0A84FFFF"

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

    static func normalizedColorHex(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let body = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard body.count == 6 || body.count == 8,
              body.unicodeScalars.allSatisfy({ CharacterSet.hexadecimalDigits.contains($0) }) else {
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

# GlobalSettingsController.swift — replace Appearance tab only.
p = Path("FloatTabs/UI/GlobalSettingsController.swift")
t = p.read_text()
appearance = r'''@MainActor
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

'''
t = replace_block(
    t,
    r'@MainActor\nprivate final class AppearanceSettingsViewController: NSViewController \{.*?(?=@MainActor\nprivate final class SettingsDocumentView)',
    appearance,
    "AppearanceSettingsViewController"
)
p.write_text(t)

# WebViewContainer.swift — runtime border theme.
p = Path("FloatTabs/Web/WebViewContainer.swift")
t = p.read_text()
t = replace_once(t,
'''final class PanelInteractionBorderView: NSView {
    private let gradientLayer = CAGradientLayer()
    private let borderMask = CAShapeLayer()
''',
'''final class PanelInteractionBorderView: NSView {
    private let gradientLayer = CAGradientLayer()
    private let borderMask = CAShapeLayer()
    private var borderTheme: PanelBorderTheme = .rainbow
    private var customBorderColor: NSColor = .systemBlue
''', "border properties")

t = replace_once(t,
'''        gradientLayer.type = .conic
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.opacity = 0.72

        let palettes = Self.flowPalettes
        gradientLayer.colors = palettes.first
        gradientLayer.locations = [0, 0.22, 0.48, 0.74, 1]

        borderMask.fillColor = NSColor.clear.cgColor
        borderMask.strokeColor = NSColor.white.cgColor
        borderMask.lineWidth = PanelMetrics.interactionBorderLineWidth
        borderMask.lineJoin = .round
        borderMask.lineCap = .round
        gradientLayer.mask = borderMask
        layer?.addSublayer(gradientLayer)

        let flow = CAKeyframeAnimation(keyPath: "colors")
        flow.values = palettes
        flow.keyTimes = [0, 0.25, 0.5, 0.75, 1]
        flow.duration = 3.2
        flow.repeatCount = .infinity
        flow.calculationMode = .linear
        gradientLayer.add(flow, forKey: "FloatTabs.interactionBorderFlow")
''',
'''        gradientLayer.opacity = 0.72

        borderMask.fillColor = NSColor.clear.cgColor
        borderMask.strokeColor = NSColor.white.cgColor
        borderMask.lineWidth = PanelMetrics.interactionBorderLineWidth
        borderMask.lineJoin = .round
        borderMask.lineCap = .round
        gradientLayer.mask = borderMask
        layer?.addSublayer(gradientLayer)
        applyBorderAppearance()
''', "border init")

t = replace_once(t,
'''    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
''',
'''    override var isOpaque: Bool { false }

    func apply(theme: PanelBorderTheme, customColor: NSColor) {
        borderTheme = theme
        customBorderColor = customColor
        applyBorderAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyBorderAppearance()
    }

    private func applyBorderAppearance() {
        gradientLayer.removeAnimation(forKey: "FloatTabs.interactionBorderFlow")

        if borderTheme == .rainbow {
            gradientLayer.type = .conic
            gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)
            let palettes = Self.flowPalettes
            gradientLayer.colors = palettes.first
            gradientLayer.locations = [0, 0.22, 0.48, 0.74, 1]

            let flow = CAKeyframeAnimation(keyPath: "colors")
            flow.values = palettes
            flow.keyTimes = [0, 0.25, 0.5, 0.75, 1]
            flow.duration = 3.2
            flow.repeatCount = .infinity
            flow.calculationMode = .linear
            gradientLayer.add(flow, forKey: "FloatTabs.interactionBorderFlow")
        } else {
            let color = borderTheme.solidColor ?? customBorderColor
            gradientLayer.type = .axial
            gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
            gradientLayer.colors = [color.cgColor, color.cgColor]
            gradientLayer.locations = [0, 1]
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
''', "border appearance functions")
p.write_text(t)

# ExternalTabRail.swift — disable per-tab Window Size while Fixed.
p = Path("FloatTabs/UI/ExternalTabRail.swift")
t = p.read_text()
t = replace_once(t,
'''    private var pointerLocation: NSPoint?
    private var pointerY: CGFloat?
''',
'''    private var pointerLocation: NSPoint?
    private var pointerY: CGFloat?
    private var windowSizeEditingEnabled = true
''', "rail preference")
t = replace_once(t,
'''    func setPinned(_ isPinned: Bool) {
        pinControl.setPinned(isPinned)
    }

    func setResidentSlotIDs(_ slotIDs: Set<UUID>) {
''',
'''    func setPinned(_ isPinned: Bool) {
        pinControl.setPinned(isPinned)
    }

    func setWindowSizeEditingEnabled(_ enabled: Bool) {
        windowSizeEditingEnabled = enabled
        for tab in tabViews.values {
            tab.setWindowSizeEditingEnabled(enabled)
        }
    }

    func setResidentSlotIDs(_ slotIDs: Set<UUID>) {
''', "rail setter")
t = replace_once(t,
'''        let view = ExternalWebAppTabView(slotID: id)
        tabViews[id] = view
''',
'''        let view = ExternalWebAppTabView(slotID: id)
        view.setWindowSizeEditingEnabled(windowSizeEditingEnabled)
        tabViews[id] = view
''', "new tab setter")
t = replace_once(t,
'''    private var renderingProfile: WebRenderingProfile = .canonicalDefault
    private var residencyPolicy: SlotResidencyPolicy = .warm
''',
'''    private var renderingProfile: WebRenderingProfile = .canonicalDefault
    private var residencyPolicy: SlotResidencyPolicy = .warm
    private var windowSizeEditingEnabled = true
''', "tab preference")
t = replace_once(t,
'''    func setResident(_ resident: Bool) {
        guard isResident != resident else { return }
        isResident = resident
        updateAppearance()
        updateRuntimeToolTip()
    }

    func update(profile: WebAppProfile, isActive: Bool, isResident: Bool) {
''',
'''    func setResident(_ resident: Bool) {
        guard isResident != resident else { return }
        isResident = resident
        updateAppearance()
        updateRuntimeToolTip()
    }

    func setWindowSizeEditingEnabled(_ enabled: Bool) {
        windowSizeEditingEnabled = enabled
    }

    func update(profile: WebAppProfile, isActive: Bool, isResident: Bool) {
''', "tab setter")
t = replace_once(t,
'''        windowSize.submenu = windowSizeMenu
        menu.addItem(windowSize)
''',
'''        windowSize.submenu = windowSizeMenu
        windowSize.isEnabled = windowSizeEditingEnabled
        windowSize.toolTip = windowSizeEditingEnabled
            ? nil
            : "Window size is fixed globally in Settings → Appearance."
        menu.addItem(windowSize)
''', "window menu disabled")
p.write_text(t)

# WebAppEditorController.swift — Fixed mode preserves hidden per-App size fields.
p = Path("FloatTabs/UI/WebAppEditorController.swift")
t = p.read_text()
t = replace_once(t,
'''    static func presentAdd(
        attachedTo window: NSWindow,
        completion: @escaping (WebAppEditorValue?) -> Void
    ) {
''',
'''    static func presentAdd(
        allowsWindowSizeEditing: Bool = true,
        attachedTo window: NSWindow,
        completion: @escaping (WebAppEditorValue?) -> Void
    ) {
''', "presentAdd signature")
t = replace_once(t,
'''            initialRendering: .canonicalDefault,
            showsPrimaryRenderingControls: true,
            attachedTo: window,
''',
'''            initialRendering: .canonicalDefault,
            showsPrimaryRenderingControls: true,
            allowsWindowSizeEditing: allowsWindowSizeEditing,
            attachedTo: window,
''', "presentAdd pass")
t = replace_once(t,
'''    static func presentEdit(
        profile: WebAppProfile,
        attachedTo window: NSWindow,
        completion: @escaping (WebAppEditorValue?) -> Void
    ) {
''',
'''    static func presentEdit(
        profile: WebAppProfile,
        allowsWindowSizeEditing: Bool = true,
        attachedTo window: NSWindow,
        completion: @escaping (WebAppEditorValue?) -> Void
    ) {
''', "presentEdit signature")
t = replace_once(t,
'''            initialRendering: profile.renderingProfile,
            showsPrimaryRenderingControls: false,
            attachedTo: window,
''',
'''            initialRendering: profile.renderingProfile,
            showsPrimaryRenderingControls: false,
            allowsWindowSizeEditing: allowsWindowSizeEditing,
            attachedTo: window,
''', "presentEdit pass")
t = replace_once(t,
'''        initialRendering: WebRenderingProfile,
        showsPrimaryRenderingControls: Bool,
        attachedTo window: NSWindow,
''',
'''        initialRendering: WebRenderingProfile,
        showsPrimaryRenderingControls: Bool,
        allowsWindowSizeEditing: Bool,
        attachedTo window: NSWindow,
''', "presentEditor signature")
t = replace_once(t,
'''        let renderingForm = RenderingForm(
            initial: initialRendering,
            showsPrimaryRenderingControls: showsPrimaryRenderingControls
        )
''',
'''        let renderingForm = RenderingForm(
            initial: initialRendering,
            showsPrimaryRenderingControls: showsPrimaryRenderingControls,
            allowsWindowSizeEditing: allowsWindowSizeEditing
        )
''', "rendering form pass")
t = replace_once(t,
'''    private let modePopup = NSPopUpButton()
    private let sizePopup = NSPopUpButton()
''',
'''    private let modePopup = NSPopUpButton()
    private let sizePopup = NSPopUpButton()
    private let initialRendering: WebRenderingProfile
    private let allowsWindowSizeEditing: Bool
''', "render form props")
t = replace_once(t,
'''    init(
        initial: WebRenderingProfile,
        showsPrimaryRenderingControls: Bool = true
    ) {
        let rendering = initial.normalized()
''',
'''    init(
        initial: WebRenderingProfile,
        showsPrimaryRenderingControls: Bool = true,
        allowsWindowSizeEditing: Bool = true
    ) {
        let rendering = initial.normalized()
        self.initialRendering = rendering
        self.allowsWindowSizeEditing = allowsWindowSizeEditing
''', "render init")
t = replace_once(t,
'''        let primaryViews: [NSView] = showsPrimaryRenderingControls
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
''',
'''        let primaryViews: [NSView] = showsPrimaryRenderingControls
            ? ([
                Self.label("Website Mode"),
                modePopup,
            ] + (allowsWindowSizeEditing
                ? [Self.label("Window Size"), sizeRow]
                : [Self.secondaryLabel("Window Size is fixed globally. Existing per-App sizes are preserved.")]
            ) + [
                Self.label("Zoom"),
                zoomPopup,
                advancedButton,
            ])
            : [
''', "primary views")
t = replace_once(t,
'''        customUAField.target = self
        customUAField.action = #selector(customUAChanged(_:))

        if showsPrimaryRenderingControls {
''',
'''        customUAField.target = self
        customUAField.action = #selector(customUAChanged(_:))

        sizePopup.isEnabled = allowsWindowSizeEditing
        widthField.isEnabled = allowsWindowSizeEditing
        heightField.isEnabled = allowsWindowSizeEditing
        devicePopup.isEnabled = allowsWindowSizeEditing
        orientationPopup.isEnabled = allowsWindowSizeEditing
        devicePopup.toolTip = allowsWindowSizeEditing
            ? nil
            : "Device preset is preserved while global Fixed window sizing is active."
        orientationPopup.toolTip = devicePopup.toolTip

        if showsPrimaryRenderingControls {
''', "disable size-linked fields")
# Replace value size/device/orientation derivation with preserved values in Fixed mode.
t = replace_once(t,
'''        let preset = SimpleViewportPreset.allCases[sizeIndex]
        let identity = BrowserIdentity.allCases[identityIndex]
        let orientation = DeviceOrientation.allCases[orientationIndex]

        let size: CGSize
        if let presetSize = preset.size {
            size = presetSize
        } else {
            guard let parsed = parsedCustomSize() else { return nil }
            size = parsed
        }
''',
'''        let selectedPreset = SimpleViewportPreset.allCases[sizeIndex]
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
''', "value preserved size")
t = replace_once(t,
'''        let deviceID: String?
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
''',
'''        let deviceID: String?
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
''', "device preserved")
t = replace_once(t,
'''    private static func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        return label
    }
''',
'''    private static func label(_ text: String) -> NSTextField {
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
''', "secondary label")
p.write_text(t)

# PanelController.swift — preference observers + Fixed semantics.
p = Path("FloatTabs/Panel/PanelController.swift")
t = p.read_text()
t = replace_once(t,
'''        configureSlotInteractions()
        rootView.externalControlZoneView.setPinned(isPinned)
''',
'''        configureSlotInteractions()
        configurePreferenceObservers()
        synchronizePreferencePresentation()
        rootView.externalControlZoneView.setPinned(isPinned)
''', "panel init preferences")
t = replace_once(t,
'''    static func shouldAutoHide(panelIsVisible: Bool, isPinned: Bool) -> Bool {
        panelIsVisible && !isPinned
    }
''',
'''    static func shouldAutoHide(panelIsVisible: Bool, isPinned: Bool) -> Bool {
        panelIsVisible && !isPinned
    }

    static func shouldPersistManualViewportToActiveTab(
        windowSizeMode: PanelWindowSizeMode
    ) -> Bool {
        windowSizeMode == .perWebApp
    }
''', "panel test helper")
t = replace_once(t,
'''    private func configureSlotInteractions() {
        let rail = rootView.externalControlZoneView
''',
'''    private func configurePreferenceObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(borderPreferenceDidChange(_:)),
            name: .floatTabsBorderPreferenceDidChange,
            object: preferencesStore
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowSizeModeDidChange(_:)),
            name: .floatTabsWindowSizeModeDidChange,
            object: preferencesStore
        )
    }

    @objc private func borderPreferenceDidChange(_ notification: Notification) {
        synchronizeBorderTheme()
    }

    @objc private func windowSizeModeDidChange(_ notification: Notification) {
        synchronizeWindowSizeMode()
        if preferencesStore.windowSizeMode == .perWebApp,
           let active = tabStore.activeProfile {
            applyPreferredViewport(active.renderingProfile.viewportSize)
        }
    }

    private func synchronizePreferencePresentation() {
        synchronizeBorderTheme()
        synchronizeWindowSizeMode()
    }

    private func synchronizeBorderTheme() {
        rootView.interactionBorderView.apply(
            theme: preferencesStore.borderTheme,
            customColor: preferencesStore.customBorderColor
        )
    }

    private func synchronizeWindowSizeMode() {
        rootView.externalControlZoneView.setWindowSizeEditingEnabled(
            preferencesStore.windowSizeMode == .perWebApp
        )
    }

    private func configureSlotInteractions() {
        let rail = rootView.externalControlZoneView
''', "panel preference methods")
t = replace_once(t,
'''        rail.onSetWindowSize = { [weak self] id, preset in
            guard let self,
                  let profile = self.tabStore.profiles.first(where: { $0.id == id }),
                  let size = preset.size else { return }
''',
'''        rail.onSetWindowSize = { [weak self] id, preset in
            guard let self,
                  self.preferencesStore.windowSizeMode == .perWebApp,
                  let profile = self.tabStore.profiles.first(where: { $0.id == id }),
                  let size = preset.size else { return }
''', "right-click size guard")
t = replace_once(t,
'''        WebAppEditorController.presentAdd(attachedTo: panel) { [weak self] value in
''',
'''        WebAppEditorController.presentAdd(
            allowsWindowSizeEditing: preferencesStore.windowSizeMode == .perWebApp,
            attachedTo: panel
        ) { [weak self] value in
''', "add editor mode")
t = replace_once(t,
'''                // The user explicitly chose this new Slot's size. Apply it now;
                // the follow preference only governs later automatic Slot switches.
                self.applyPreferredViewport(added.renderingProfile.viewportSize)
''',
'''                if self.preferencesStore.windowSizeMode == .perWebApp {
                    self.applyPreferredViewport(added.renderingProfile.viewportSize)
                }
''', "add apply size")
t = replace_once(t,
'''        WebAppEditorController.presentEdit(profile: profile, attachedTo: panel) { [weak self] value in
''',
'''        WebAppEditorController.presentEdit(
            profile: profile,
            allowsWindowSizeEditing: preferencesStore.windowSizeMode == .perWebApp,
            attachedTo: panel
        ) { [weak self] value in
''', "edit editor mode")
t = replace_once(t,
'''                if self.tabStore.activeTabID == id {
                    // Editing the current Slot is an explicit size request and
                    // must not depend on the automatic switch-follow preference.
                    self.applyPreferredViewport(value.renderingProfile.viewportSize)
                }
''',
'''                if self.tabStore.activeTabID == id,
                   self.preferencesStore.windowSizeMode == .perWebApp {
                    self.applyPreferredViewport(value.renderingProfile.viewportSize)
                }
''', "edit apply size")
t = replace_once(t,
'''    private func handleManualResizeEnded() {
        clampPanelToConnectedScreens()
        let viewport = PanelMetrics.viewportSize(forPanelSize: panel.frame.size)
        if let id = tabStore.activeTabID {
            _ = tabStore.updatePreferredViewport(
                id: id,
                size: CGSize(width: viewport.width, height: viewport.height)
            )
        }
        persistPanelFrame()
    }
''',
'''    private func handleManualResizeEnded() {
        clampPanelToConnectedScreens()
        if Self.shouldPersistManualViewportToActiveTab(
            windowSizeMode: preferencesStore.windowSizeMode
        ) {
            let viewport = PanelMetrics.viewportSize(forPanelSize: panel.frame.size)
            if let id = tabStore.activeTabID {
                _ = tabStore.updatePreferredViewport(
                    id: id,
                    size: CGSize(width: viewport.width, height: viewport.height)
                )
            }
        }
        // Fixed mode intentionally persists only the shared panel frame. The
        // hidden per-Web-App viewport values remain untouched for later restore.
        persistPanelFrame()
    }
''', "manual resize semantics")
t = replace_once(t,
'''    private func applyPreferredViewport(_ viewportSize: CGSize) {
        guard hasPositionedPanel else { return }
''',
'''    private func applyPreferredViewport(_ viewportSize: CGSize) {
        guard preferencesStore.windowSizeMode == .perWebApp,
              hasPositionedPanel else { return }
''', "apply preferred guard")
p.write_text(t)

# Backup model: optional border fields keep schema-1 backups backward compatible.
p = Path("FloatTabs/Persistence/FloatTabsBackupService.swift")
t = p.read_text()
t = replace_once(t,
'''struct FloatTabsBackupPreferences: Codable, Equatable {
    let appearanceMode: AppAppearanceMode
    let followPreferredSize: Bool
}
''',
'''struct FloatTabsBackupPreferences: Codable, Equatable {
    let appearanceMode: AppAppearanceMode
    let followPreferredSize: Bool
    let borderTheme: PanelBorderTheme?
    let customBorderColorHex: String?

    init(
        appearanceMode: AppAppearanceMode,
        followPreferredSize: Bool,
        borderTheme: PanelBorderTheme? = nil,
        customBorderColorHex: String? = nil
    ) {
        self.appearanceMode = appearanceMode
        self.followPreferredSize = followPreferredSize
        self.borderTheme = borderTheme
        self.customBorderColorHex = customBorderColorHex
    }
}
''', "backup preference fields")
p.write_text(t)

# AppCoordinator backup/restore.
p = Path("FloatTabs/App/AppCoordinator.swift")
t = p.read_text()
t = replace_once(t,
'''            globalPreferences: FloatTabsBackupPreferences(
                appearanceMode: preferencesStore.appearanceMode,
                followPreferredSize: preferencesStore.followPreferredSize
            ),
''',
'''            globalPreferences: FloatTabsBackupPreferences(
                appearanceMode: preferencesStore.appearanceMode,
                followPreferredSize: preferencesStore.followPreferredSize,
                borderTheme: preferencesStore.borderTheme,
                customBorderColorHex: preferencesStore.customBorderColorHex
            ),
''', "backup make")
t = replace_once(t,
'''        preferencesStore.followPreferredSize = imported.globalPreferences.followPreferredSize
        preferencesStore.appearanceMode = imported.globalPreferences.appearanceMode
''',
'''        preferencesStore.followPreferredSize = imported.globalPreferences.followPreferredSize
        preferencesStore.appearanceMode = imported.globalPreferences.appearanceMode
        preferencesStore.customBorderColorHex = imported.globalPreferences.customBorderColorHex
            ?? AppPreferencesStore.defaultCustomBorderColorHex
        preferencesStore.borderTheme = imported.globalPreferences.borderTheme ?? .rainbow
''', "backup restore")
p.write_text(t)

# Tests — AppPreferencesStore.
p = Path("FloatTabsTests/AppPreferencesStoreTests.swift")
t = p.read_text()
t = replace_once(t,
'''    func testFollowPreferredSizeDefaultsTrueAndPersists() {
        let first = AppPreferencesStore(defaults: defaults)
        XCTAssertTrue(first.followPreferredSize)

        first.followPreferredSize = false
        XCTAssertFalse(AppPreferencesStore(defaults: defaults).followPreferredSize)

        first.followPreferredSize = true
        XCTAssertTrue(AppPreferencesStore(defaults: defaults).followPreferredSize)
    }
''',
'''    func testFollowPreferredSizeDefaultsTrueAndPersists() {
        let first = AppPreferencesStore(defaults: defaults)
        XCTAssertTrue(first.followPreferredSize)
        XCTAssertEqual(first.windowSizeMode, .perWebApp)

        first.windowSizeMode = .fixed
        XCTAssertFalse(AppPreferencesStore(defaults: defaults).followPreferredSize)
        XCTAssertEqual(AppPreferencesStore(defaults: defaults).windowSizeMode, .fixed)

        first.windowSizeMode = .perWebApp
        XCTAssertTrue(AppPreferencesStore(defaults: defaults).followPreferredSize)
        XCTAssertEqual(AppPreferencesStore(defaults: defaults).windowSizeMode, .perWebApp)
    }

    func testBorderThemeDefaultsRainbowAndPersists() {
        let first = AppPreferencesStore(defaults: defaults)
        XCTAssertEqual(first.borderTheme, .rainbow)

        first.borderTheme = .orange
        XCTAssertEqual(AppPreferencesStore(defaults: defaults).borderTheme, .orange)

        first.borderTheme = .custom
        first.customBorderColorHex = "#12AB34"
        let restored = AppPreferencesStore(defaults: defaults)
        XCTAssertEqual(restored.borderTheme, .custom)
        XCTAssertEqual(restored.customBorderColorHex, "#12AB34FF")
    }

    func testCustomBorderColorRoundTripsThroughSRGBHex() {
        let store = AppPreferencesStore(defaults: defaults)
        store.customBorderColor = NSColor(srgbRed: 1, green: 0.25, blue: 0, alpha: 1)
        XCTAssertEqual(store.customBorderColorHex, "#FF4000FF")
        XCTAssertEqual(store.customBorderColor.usingColorSpace(.sRGB)?.redComponent ?? 0, 1, accuracy: 0.01)
    }
''', "preferences tests")
p.write_text(t)

# ExternalShellTests — disabled Window Size + writeback rule.
p = Path("FloatTabsTests/ExternalShellTests.swift")
t = p.read_text()
anchor = '''    func testReleasedTabDisablesReloadWithoutCreatingRuntime() {
'''
insert = '''    func testFixedWindowModeDisablesPerTabWindowSizeMenu() {
        let (_, zone) = makeZoneHarness()
        let active = makeProfile(order: 0, name: "GPT")
        zone.apply(profiles: [active], activeTabID: active.id)
        zone.setWindowSizeEditingEnabled(false)
        zone.layoutSubtreeIfNeeded()

        let tab = try! XCTUnwrap(zone.tabView(for: active.id))
        let event = NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: NSPoint(x: tab.frame.midX, y: tab.frame.midY),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 91,
            clickCount: 1,
            pressure: 1
        )!
        let menu = try! XCTUnwrap(tab.menu(for: event))
        XCTAssertFalse(try! XCTUnwrap(menu.item(withTitle: "Window Size")).isEnabled)
    }

    func testFixedWindowModeNeverWritesManualResizeIntoActiveWebApp() {
        XCTAssertTrue(
            PanelController.shouldPersistManualViewportToActiveTab(
                windowSizeMode: .perWebApp
            )
        )
        XCTAssertFalse(
            PanelController.shouldPersistManualViewportToActiveTab(
                windowSizeMode: .fixed
            )
        )
    }

'''
t = replace_once(t, anchor, insert + anchor, "shell fixed tests")
p.write_text(t)

# TabStoreTests — domain regression: global Fixed mode never mutates saved sizes.
p = Path("FloatTabsTests/TabStoreTests.swift")
t = p.read_text()
anchor = '''    func testActiveSelectionUpdatesIdentity() {
'''
insert = '''    func testGlobalFixedWindowPreferenceDoesNotMutateSavedPerWebAppSizes() {
        let repository = MemoryProfileRepository()
        let store = TabStore(repository: repository)
        let first = store.add(
            name: "First",
            homeURL: urlA,
            renderingProfile: .canonicalDefault.settingViewport(CGSize(width: 390, height: 780))
        )!
        let second = store.add(
            name: "Second",
            homeURL: urlB,
            renderingProfile: .canonicalDefault.settingViewport(CGSize(width: 900, height: 850))
        )!
        let before = Dictionary(uniqueKeysWithValues: store.profiles.map {
            ($0.id, $0.renderingProfile.viewportSize)
        })

        let suite = "FloatTabsTests.FixedWindow.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.windowSizeMode = .fixed
        _ = store.select(id: first.id)
        _ = store.select(id: second.id)
        preferences.windowSizeMode = .perWebApp

        let after = Dictionary(uniqueKeysWithValues: store.profiles.map {
            ($0.id, $0.renderingProfile.viewportSize)
        })
        XCTAssertEqual(after[first.id], before[first.id])
        XCTAssertEqual(after[second.id], before[second.id])
    }

'''
t = replace_once(t, anchor, insert + anchor, "tabstore fixed preservation")
p.write_text(t)

# Backup tests: verify new fields round-trip while old constructor defaults stay valid.
p = Path("FloatTabsTests/FloatTabsBackupServiceTests.swift")
t = p.read_text()
t = replace_once(t,
'''            globalPreferences: FloatTabsBackupPreferences(
                appearanceMode: .dark,
                followPreferredSize: false
            ),
''',
'''            globalPreferences: FloatTabsBackupPreferences(
                appearanceMode: .dark,
                followPreferredSize: false,
                borderTheme: .green,
                customBorderColorHex: "#123456FF"
            ),
''', "backup test prefs")
t = replace_once(t,
'''        XCTAssertFalse(decoded.globalPreferences.followPreferredSize)
        XCTAssertEqual(decoded.globalShowHideShortcut?.carbonKeyCode, 50)
''',
'''        XCTAssertFalse(decoded.globalPreferences.followPreferredSize)
        XCTAssertEqual(decoded.globalPreferences.borderTheme, .green)
        XCTAssertEqual(decoded.globalPreferences.customBorderColorHex, "#123456FF")
        XCTAssertEqual(decoded.globalShowHideShortcut?.carbonKeyCode, 50)
''', "backup test asserts")
p.write_text(t)
