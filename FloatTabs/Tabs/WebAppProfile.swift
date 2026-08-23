import Foundation

enum SlotResidencyPolicy: String, Codable, CaseIterable, Equatable {
    case hot
    case warm
    case cold

    var displayName: String {
        switch self {
        case .hot: return "Hot"
        case .warm: return "Warm"
        case .cold: return "Cold"
        }
    }

    var detailText: String {
        switch self {
        case .hot:
            return "Keep the live WebView attached. FloatTabs does not proactively evict it."
        case .warm:
            return "Cache recent inactive WebViews; release after 2 minutes, beyond the two-Slot Warm cache, or under memory pressure."
        case .cold:
            return "Release 30 seconds after leaving the Slot; a selected hidden Slot gets a short recent-active grace first."
        }
    }
}

enum BackgroundMediaPolicy: String, Codable, CaseIterable, Equatable {
    case pauseWhenInactive
    case allowBackgroundAudio

    var displayName: String {
        switch self {
        case .pauseWhenInactive: return "Pause When Inactive"
        case .allowBackgroundAudio: return "Allow Background Audio"
        }
    }
}

struct WebAppProfile: Codable, Identifiable, Equatable {
    let id: UUID
    /// `nil` is the virtual Default Profile; a value must resolve to a custom
    /// BrowserProfile in the persisted state.
    var browserProfileID: UUID?
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
    var residencyPolicy: SlotResidencyPolicy
    var backgroundMediaPolicy: BackgroundMediaPolicy
    var createdAt: Date
    var lastUsedAt: Date

    init(
        id: UUID = UUID(),
        browserProfileID: UUID? = nil,
        order: Int,
        name: String,
        homeURL: URL,
        currentURL: URL? = nil,
        homeURLSchemeWasInferred: Bool = false,
        renderingProfile: WebRenderingProfile = .canonicalDefault,
        residencyPolicy: SlotResidencyPolicy = .warm,
        backgroundMediaPolicy: BackgroundMediaPolicy = .pauseWhenInactive,
        createdAt: Date = Date(),
        lastUsedAt: Date = Date()
    ) {
        self.id = id
        self.browserProfileID = browserProfileID
        self.order = order
        self.name = name
        self.homeURL = homeURL
        self.currentURL = currentURL
        self.homeURLSchemeWasInferred = homeURLSchemeWasInferred
        self.renderingProfile = renderingProfile
        self.residencyPolicy = residencyPolicy
        self.backgroundMediaPolicy = backgroundMediaPolicy
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}

extension WebAppProfile {
    private enum CodingKeys: String, CodingKey {
        case id
        case browserProfileID
        case order
        case name
        case homeURL
        case currentURL
        case homeURLSchemeWasInferred
        case renderingProfile
        case residencyPolicy
        case backgroundMediaPolicy
        case createdAt
        case lastUsedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        browserProfileID = try container.decodeIfPresent(UUID.self, forKey: .browserProfileID)
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
        residencyPolicy = try container.decodeIfPresent(
            SlotResidencyPolicy.self,
            forKey: .residencyPolicy
        ) ?? .warm
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
        try container.encode(order, forKey: .order)
        try container.encode(name, forKey: .name)
        try container.encode(homeURL, forKey: .homeURL)
        try container.encodeIfPresent(currentURL, forKey: .currentURL)
        try container.encode(homeURLSchemeWasInferred, forKey: .homeURLSchemeWasInferred)
        try container.encode(renderingProfile, forKey: .renderingProfile)
        try container.encode(residencyPolicy, forKey: .residencyPolicy)
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
