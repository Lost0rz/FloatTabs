import AppKit

enum MenuBarDisplayMode: String, CaseIterable, Equatable, Codable {
    case iconAndName
    case iconOnly

    var displayName: String {
        switch self {
        case .iconAndName: return "Icon + Name"
        case .iconOnly: return "Icon Only"
        }
    }
}

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

enum WarmWebViewRetentionOption: Int, CaseIterable, Equatable {
    case twoMinutes = 120
    case fiveMinutes = 300
    case tenMinutes = 600
    case thirtyMinutes = 1_800

    var seconds: TimeInterval { TimeInterval(rawValue) }

    var displayName: String {
        switch self {
        case .twoMinutes: return "2 minutes"
        case .fiveMinutes: return "5 minutes"
        case .tenMinutes: return "10 minutes"
        case .thirtyMinutes: return "30 minutes"
        }
    }

    init(seconds: TimeInterval) {
        self = Self.allCases.min {
            abs($0.seconds - seconds) < abs($1.seconds - seconds)
        } ?? .twoMinutes
    }
}

enum ColdWebViewReleaseOption: Int, CaseIterable, Equatable {
    case thirtySeconds = 30
    case oneMinute = 60
    case twoMinutes = 120

    var seconds: TimeInterval { TimeInterval(rawValue) }

    var displayName: String {
        switch self {
        case .thirtySeconds: return "30 seconds"
        case .oneMinute: return "1 minute"
        case .twoMinutes: return "2 minutes"
        }
    }

    init(seconds: TimeInterval) {
        self = Self.allCases.min {
            abs($0.seconds - seconds) < abs($1.seconds - seconds)
        } ?? .thirtySeconds
    }
}

extension Notification.Name {
    static let floatTabsAppearanceDidChange = Notification.Name(
        "FloatTabs.appearanceDidChange"
    )
    static let floatTabsBorderPreferenceDidChange = Notification.Name(
        "FloatTabs.borderPreferenceDidChange"
    )
    static let floatTabsWindowSizeModeDidChange = Notification.Name(
        "FloatTabs.windowSizeModeDidChange"
    )
    static let floatTabsFixedWindowSizeDidChange = Notification.Name(
        "FloatTabs.fixedWindowSizeDidChange"
    )
    static let floatTabsMenuBarDisplayModeDidChange = Notification.Name(
        "FloatTabs.menuBarDisplayModeDidChange"
    )
    static let floatTabsSlotRetentionDidChange = Notification.Name(
        "FloatTabs.slotRetentionDidChange"
    )
}

@MainActor
final class AppPreferencesStore {
    static let appearanceKey = "FloatTabs.appearanceMode"
    static let followPreferredSizeKey = "FloatTabs.followTabPreferredSize"
    static let borderThemeKey = "FloatTabs.borderTheme"
    static let customBorderColorKey = "FloatTabs.customBorderColor"
    static let railCollapsedKey = "FloatTabs.railCollapsed"
    static let fixedViewportWidthKey = "FloatTabs.fixedViewportWidth"
    static let fixedViewportHeightKey = "FloatTabs.fixedViewportHeight"
    static let menuBarDisplayModeKey = "FloatTabs.menuBarDisplayMode"
    static let attentionSoundEnabledKey = "FloatTabs.attentionSoundEnabled"
    static let attentionSoundNameKey = "FloatTabs.attentionSoundName"
    static let attentionSoundVolumeKey = "FloatTabs.attentionSoundVolume"
    static let websiteCacheAutomaticCleanupEnabledKey =
        "FloatTabs.websiteCache.automaticCleanupEnabled"
    static let websiteCacheRetentionDaysKey = "FloatTabs.websiteCache.retentionDays"
    static let websiteCacheMaximumEstimatedBytesKey =
        "FloatTabs.websiteCache.maximumEstimatedBytes"
    static let websiteCacheTargetEstimatedBytesKey =
        "FloatTabs.websiteCache.targetEstimatedBytes"
    static let websiteCacheMinimumCleanupIntervalKey =
        "FloatTabs.websiteCache.minimumCleanupInterval"
    static let websiteCacheRecentUseProtectionKey =
        "FloatTabs.websiteCache.recentUseProtection"
    static let warmWebViewRetentionDelayKey =
        "FloatTabs.performance.warmWebViewRetentionDelay"
    static let coldWebViewReleaseDelayKey =
        "FloatTabs.performance.coldWebViewReleaseDelay"
    static let defaultCustomBorderColorHex = "#0A84FFFF"
    static let defaultFixedViewportSize = CGSize(width: 600, height: 820)
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

    var menuBarDisplayMode: MenuBarDisplayMode {
        get {
            guard let raw = defaults.string(forKey: Self.menuBarDisplayModeKey),
                  let mode = MenuBarDisplayMode(rawValue: raw) else {
                return .iconAndName
            }
            return mode
        }
        set {
            guard newValue != menuBarDisplayMode else { return }
            defaults.set(newValue.rawValue, forKey: Self.menuBarDisplayModeKey)
            NotificationCenter.default.post(
                name: .floatTabsMenuBarDisplayModeDidChange,
                object: self
            )
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

    var isTabRailCollapsed: Bool {
        get { defaults.bool(forKey: Self.railCollapsedKey) }
        set { defaults.set(newValue, forKey: Self.railCollapsedKey) }
    }

    /// The shipped default for `attentionSoundName`. Nonisolated so backup
    /// resolution can share the exact same constant as the live store.
    nonisolated static var defaultAttentionSoundName: String { "Ping" }

    var attentionSoundEnabled: Bool {
        get {
            guard defaults.object(forKey: Self.attentionSoundEnabledKey) != nil else {
                return true
            }
            return defaults.bool(forKey: Self.attentionSoundEnabledKey)
        }
        set { defaults.set(newValue, forKey: Self.attentionSoundEnabledKey) }
    }

    var attentionSoundName: String {
        get {
            let raw = defaults.string(forKey: Self.attentionSoundNameKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let raw, !raw.isEmpty else {
                return Self.defaultAttentionSoundName
            }
            return raw
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            defaults.set(trimmed, forKey: Self.attentionSoundNameKey)
        }
    }

    /// Stored and exposed as 0...1; the Settings slider maps to 0...100.
    var attentionSoundVolume: Double {
        get {
            guard defaults.object(forKey: Self.attentionSoundVolumeKey) != nil else {
                return 1
            }
            return Self.normalizedAttentionSoundVolume(
                defaults.double(forKey: Self.attentionSoundVolumeKey)
            )
        }
        set {
            defaults.set(
                Self.normalizedAttentionSoundVolume(newValue),
                forKey: Self.attentionSoundVolumeKey
            )
        }
    }

    /// Cache policy is persisted as operational app preferences, separate from
    /// FloatTabsBackupPreferences so website-data metadata never enters a user
    /// backup. Every value is normalized on read and write.
    var websiteCachePolicy: WebsiteCachePolicy {
        get {
            let enabled: Bool
            if defaults.object(forKey: Self.websiteCacheAutomaticCleanupEnabledKey) == nil {
                enabled = WebsiteCachePolicy.default.automaticCleanupEnabled
            } else {
                enabled = defaults.bool(forKey: Self.websiteCacheAutomaticCleanupEnabledKey)
            }

            let retention: Int?
            if defaults.object(forKey: Self.websiteCacheRetentionDaysKey) == nil {
                retention = WebsiteCachePolicy.default.retentionDays
            } else {
                let raw = defaults.integer(forKey: Self.websiteCacheRetentionDaysKey)
                retention = raw == -1 ? nil : raw
            }

            let maximum: Int64?
            if defaults.object(forKey: Self.websiteCacheMaximumEstimatedBytesKey) == nil {
                maximum = WebsiteCachePolicy.default.maximumEstimatedBytes
            } else {
                let raw = defaults.integer(forKey: Self.websiteCacheMaximumEstimatedBytesKey)
                maximum = raw == -1
                    ? nil
                    : (raw > 0 ? Int64(raw) : WebsiteCachePolicy.defaultMaximumEstimatedBytes)
            }

            let target = normalizedPositiveInteger(
                forKey: Self.websiteCacheTargetEstimatedBytesKey,
                fallback: WebsiteCachePolicy.defaultTargetEstimatedBytes
            )
            let interval = normalizedNonNegativeDouble(
                forKey: Self.websiteCacheMinimumCleanupIntervalKey,
                fallback: WebsiteCachePolicy.defaultMinimumCleanupInterval
            )
            let recentProtection = normalizedNonNegativeDouble(
                forKey: Self.websiteCacheRecentUseProtectionKey,
                fallback: WebsiteCachePolicy.defaultRecentUseProtection
            )

            return WebsiteCachePolicy(
                automaticCleanupEnabled: enabled,
                retentionDays: retention,
                maximumEstimatedBytes: maximum,
                targetEstimatedBytes: target,
                minimumCleanupInterval: interval,
                recentUseProtection: recentProtection
            ).normalized()
        }
        set {
            let policy = newValue.normalized()
            defaults.set(
                policy.automaticCleanupEnabled,
                forKey: Self.websiteCacheAutomaticCleanupEnabledKey
            )
            defaults.set(
                policy.retentionDays ?? -1,
                forKey: Self.websiteCacheRetentionDaysKey
            )
            defaults.set(
                policy.maximumEstimatedBytes ?? -1,
                forKey: Self.websiteCacheMaximumEstimatedBytesKey
            )
            defaults.set(
                policy.targetEstimatedBytes,
                forKey: Self.websiteCacheTargetEstimatedBytesKey
            )
            defaults.set(
                policy.minimumCleanupInterval,
                forKey: Self.websiteCacheMinimumCleanupIntervalKey
            )
            defaults.set(
                policy.recentUseProtection,
                forKey: Self.websiteCacheRecentUseProtectionKey
            )
        }
    }

    var warmWebViewRetentionDelay: TimeInterval {
        get {
            let raw = normalizedNonNegativeDouble(
                forKey: Self.warmWebViewRetentionDelayKey,
                fallback: SlotLifecycleCoordinator.defaultWarmReleaseDelay
            )
            return WarmWebViewRetentionOption(seconds: raw).seconds
        }
        set {
            let normalized = WarmWebViewRetentionOption(seconds: newValue).seconds
            guard normalized != warmWebViewRetentionDelay else { return }
            defaults.set(normalized, forKey: Self.warmWebViewRetentionDelayKey)
            NotificationCenter.default.post(
                name: .floatTabsSlotRetentionDidChange,
                object: self
            )
        }
    }

    var coldWebViewReleaseDelay: TimeInterval {
        get {
            let raw = normalizedNonNegativeDouble(
                forKey: Self.coldWebViewReleaseDelayKey,
                fallback: SlotLifecycleCoordinator.defaultColdReleaseDelay
            )
            return ColdWebViewReleaseOption(seconds: raw).seconds
        }
        set {
            let normalized = ColdWebViewReleaseOption(seconds: newValue).seconds
            guard normalized != coldWebViewReleaseDelay else { return }
            defaults.set(normalized, forKey: Self.coldWebViewReleaseDelayKey)
            NotificationCenter.default.post(
                name: .floatTabsSlotRetentionDidChange,
                object: self
            )
        }
    }

    /// The canonical clamp every attention-sound volume passes through —
    /// store access, backup restore, and playback. Out-of-range values
    /// clamp to the nearest bound; non-finite values resolve to full
    /// volume so a corrupt value can never poison `NSSound` with NaN.
    nonisolated static func normalizedAttentionSoundVolume(_ raw: Double) -> Double {
        guard raw.isFinite else { return 1 }
        return min(max(raw, 0), 1)
    }

    private func normalizedPositiveInteger(forKey key: String, fallback: Int64) -> Int64 {
        guard defaults.object(forKey: key) != nil else { return fallback }
        let value = defaults.integer(forKey: key)
        return value > 0 ? Int64(value) : fallback
    }

    private func normalizedNonNegativeDouble(forKey key: String, fallback: Double) -> Double {
        guard let value = defaults.object(forKey: key) as? NSNumber else { return fallback }
        let doubleValue = value.doubleValue
        guard doubleValue.isFinite, doubleValue >= 0 else { return fallback }
        return doubleValue
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
        // AppKit updates effectiveAppearance on the following run-loop turn.
        // Notify layer-backed controls after that propagation so their cached
        // CGColors are resolved in the new Light/Dark appearance immediately.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NotificationCenter.default.post(
                name: .floatTabsAppearanceDidChange,
                object: self
            )
        }
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
