import AppKit

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
