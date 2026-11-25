import Foundation

enum SlotResidencyPolicy: String, Codable, CaseIterable, Equatable {
    case hot
    case warm
    case cold

    var displayName: String {
        switch self {
        case .hot: return L10n.tr("Hot", "热驻留")
        case .warm: return L10n.tr("Warm", "温驻留")
        case .cold: return L10n.tr("Cold", "冷释放")
        }
    }

    var detailText: String {
        switch self {
        case .hot:
            return L10n.tr(
                "Keep the live WebView attached. Cache is not automatically released; manual Release Cache remains available.",
                "保持实时 WebView 常驻，不会自动清理缓存；仍可随时手动释放缓存。"
            )
        case .warm:
            return L10n.tr(
                "Keep recent inactive WebViews; runtime release follows the Warm limit, and cache follows the Website Storage retention setting.",
                "保留近期使用的非活动 WebView；运行时释放遵循上限策略，缓存遵循网站存储保留设置。"
            )
        case .cold:
            return L10n.tr(
                "Release 30 seconds after leaving the Slot; once detached, its safe website cache is released promptly.",
                "离开标签页 30 秒后释放运行时；分离后及时清理可重下载缓存。"
            )
        }
    }

    /// A Browser Profile can be shared by multiple Tabs. The most protective
    /// Tab wins so a Hot Tab cannot be evicted indirectly by a Cold sibling.
    var cacheProtectionRank: Int {
        switch self {
        case .cold: return 0
        case .warm: return 1
        case .hot: return 2
        }
    }

    static func mostProtective(
        _ lhs: SlotResidencyPolicy,
        _ rhs: SlotResidencyPolicy
    ) -> SlotResidencyPolicy {
        lhs.cacheProtectionRank >= rhs.cacheProtectionRank ? lhs : rhs
    }
}

enum SlotRuntimeRetentionPreference: String, Codable, CaseIterable, Equatable {
    case automatic
    case keepLoaded

    var displayName: String {
        switch self {
        case .automatic: return L10n.tr("Automatic", "自动管理")
        case .keepLoaded: return L10n.tr("Keep Loaded", "保持常驻")
        }
    }

    var detailText: String {
        switch self {
        case .automatic:
            return L10n.tr(
                "Manage this Runtime automatically. Inactive Runtime may be reclaimed and restored on demand.",
                "自动管理当前标签运行时；长时间未使用的页面会在需要时自动回收并按需恢复。"
            )
        case .keepLoaded:
            return L10n.tr(
                "Prefer to keep an already loaded inactive Runtime during normal operation. Critical memory pressure may still reclaim it.",
                "正常情况下尽量保持已加载的后台运行时常驻；系统内存严重不足时仍可能回收。"
            )
        }
    }

    init(legacy residencyPolicy: SlotResidencyPolicy) {
        self = residencyPolicy == .hot ? .keepLoaded : .automatic
    }

    var legacyProjection: SlotResidencyPolicy {
        switch self {
        case .automatic: return .warm
        case .keepLoaded: return .hot
        }
    }
}

enum BackgroundMediaPolicy: String, Codable, CaseIterable, Equatable {
    case pauseWhenInactive
    case allowBackgroundAudio

    var displayName: String {
        switch self {
        case .pauseWhenInactive: return L10n.tr("Pause When Inactive", "后台自动暂停")
        case .allowBackgroundAudio: return L10n.tr("Allow Background Audio", "允许后台音频")
        }
    }
}

struct WebAppProfile: Codable, Identifiable, Equatable {
    let id: UUID
    /// `nil` is the virtual Default Profile; a value must resolve to a custom
    /// BrowserProfile in the persisted state.
    var browserProfileID: UUID?
    /// `nil` belongs to the built-in Default Group; a UUID binds the tab to a custom `WebAppGroup`.
    var groupID: UUID?
    var order: Int
    var name: String
    var homeURL: URL
    var currentURL: URL?
    /// True only when FloatTabs itself supplied the `https://` scheme for the
    /// configured Home URL because the user entered a bare address. This is
    /// persisted so a later app launch or Cold rebuild can still correct that
    /// *inferred* scheme, while an explicitly entered `https://` URL is never
    /// eligible for automatic downgrade.
    var homeURLSchemeWasInferred: Bool
    var renderingProfile: WebRenderingProfile
    var runtimeRetentionPreference: SlotRuntimeRetentionPreference

    /// Rollback/protocol compatibility only. Current product lifecycle decisions
    /// must use `runtimeRetentionPreference`.
    var residencyPolicy: SlotResidencyPolicy {
        get { runtimeRetentionPreference.legacyProjection }
        set { runtimeRetentionPreference = SlotRuntimeRetentionPreference(legacy: newValue) }
    }
    var backgroundMediaPolicy: BackgroundMediaPolicy
    var createdAt: Date
    var lastUsedAt: Date

    init(
        id: UUID = UUID(),
        browserProfileID: UUID? = nil,
        groupID: UUID? = nil,
        order: Int,
        name: String,
        homeURL: URL,
        currentURL: URL? = nil,
        homeURLSchemeWasInferred: Bool = false,
        renderingProfile: WebRenderingProfile = .canonicalDefault,
        runtimeRetentionPreference: SlotRuntimeRetentionPreference = .automatic,
        residencyPolicy: SlotResidencyPolicy? = nil,
        backgroundMediaPolicy: BackgroundMediaPolicy = .pauseWhenInactive,
        createdAt: Date = Date(),
        lastUsedAt: Date = Date()
    ) {
        self.id = id
        self.browserProfileID = browserProfileID
        self.groupID = groupID
        self.order = order
        self.name = name
        self.homeURL = homeURL
        self.currentURL = currentURL
        self.homeURLSchemeWasInferred = homeURLSchemeWasInferred
        self.renderingProfile = renderingProfile
        self.runtimeRetentionPreference = residencyPolicy.map {
            SlotRuntimeRetentionPreference(legacy: $0)
        } ?? runtimeRetentionPreference
        self.backgroundMediaPolicy = backgroundMediaPolicy
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}

extension WebAppProfile {
    private enum CodingKeys: String, CodingKey {
        case id
        case browserProfileID
        case groupID
        case order
        case name
        case homeURL
        case currentURL
        case homeURLSchemeWasInferred
        case renderingProfile
        case runtimeRetentionPreference
        case residencyPolicy
        case backgroundMediaPolicy
        case createdAt
        case lastUsedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        browserProfileID = try container.decodeIfPresent(UUID.self, forKey: .browserProfileID)
        groupID = try container.decodeIfPresent(UUID.self, forKey: .groupID)
        order = try container.decode(Int.self, forKey: .order)
        name = try container.decode(String.self, forKey: .name)
        homeURL = try container.decode(URL.self, forKey: .homeURL)
        currentURL = try container.decodeIfPresent(URL.self, forKey: .currentURL)
        // Existing v0.1.1 profiles predate entry-provenance persistence. Treat
        // them as explicit by default rather than silently weakening HTTPS.
        homeURLSchemeWasInferred = try container.decodeIfPresent(
            Bool.self,
            forKey: .homeURLSchemeWasInferred
        ) ?? false
        renderingProfile = try container.decode(WebRenderingProfile.self, forKey: .renderingProfile)
        if let currentPreference = try container.decodeIfPresent(
            SlotRuntimeRetentionPreference.self,
            forKey: .runtimeRetentionPreference
        ) {
            runtimeRetentionPreference = currentPreference
        } else if let legacyPolicy = try container.decodeIfPresent(
            SlotResidencyPolicy.self,
            forKey: .residencyPolicy
        ) {
            runtimeRetentionPreference = SlotRuntimeRetentionPreference(legacy: legacyPolicy)
        } else {
            runtimeRetentionPreference = .automatic
        }
        backgroundMediaPolicy = try container.decodeIfPresent(
            BackgroundMediaPolicy.self,
            forKey: .backgroundMediaPolicy
        ) ?? .pauseWhenInactive
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastUsedAt = try container.decode(Date.self, forKey: .lastUsedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(browserProfileID, forKey: .browserProfileID)
        try container.encodeIfPresent(groupID, forKey: .groupID)
        try container.encode(order, forKey: .order)
        try container.encode(name, forKey: .name)
        try container.encode(homeURL, forKey: .homeURL)
        try container.encodeIfPresent(currentURL, forKey: .currentURL)
        try container.encode(homeURLSchemeWasInferred, forKey: .homeURLSchemeWasInferred)
        try container.encode(renderingProfile, forKey: .renderingProfile)
        try container.encode(
            runtimeRetentionPreference,
            forKey: .runtimeRetentionPreference
        )
        try container.encode(
            runtimeRetentionPreference.legacyProjection,
            forKey: .residencyPolicy
        )
        try container.encode(backgroundMediaPolicy, forKey: .backgroundMediaPolicy)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(lastUsedAt, forKey: .lastUsedAt)
    }
}

struct WebAppURLNormalization: Equatable {
    let url: URL
    /// True only when FloatTabs prepended `https://` because the raw user entry
    /// did not contain a scheme.
    let schemeWasInferred: Bool
}

enum WebAppURL {
    static func normalizedEntry(from rawValue: String) -> WebAppURLNormalization? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let schemeWasInferred = !trimmed.contains("://")
        let candidate = schemeWasInferred ? "https://\(trimmed)" : trimmed

        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host,
              !host.isEmpty,
              let url = components.url,
              isSafe(url) else {
            return nil
        }

        return WebAppURLNormalization(
            url: url,
            schemeWasInferred: schemeWasInferred
        )
    }

    /// Compatibility helper for call sites that only need a validated URL and
    /// do not participate in entry-protocol fallback decisions.
    static func normalized(from rawValue: String) -> URL? {
        normalizedEntry(from: rawValue)?.url
    }

    static func defaultDisplayName(for url: URL) -> String {
        guard let host = url.host?.lowercased(), !host.isEmpty else {
            return "Web App"
        }
        if host.hasPrefix("www."), host.count > 4 {
            return String(host.dropFirst(4))
        }
        return host
    }

    static func isSafe(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host,
              !host.isEmpty else {
            return false
        }
        return true
    }

    /// The single-retry http:// candidate for a caller-approved inferred entry.
    ///
    /// Eligibility here deliberately checks only URL shape. The caller must also
    /// prove that the user omitted the scheme. An explicitly entered `https://`
    /// URL is therefore never downgraded, even on a custom port.
    static func httpFallbackCandidate(for url: URL) -> URL? {
        guard url.scheme?.lowercased() == "https",
              (url.port ?? 443) != 443,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = "http"
        return components.url
    }
}
