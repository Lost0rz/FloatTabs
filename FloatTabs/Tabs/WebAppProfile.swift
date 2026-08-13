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
    var order: Int
    var name: String
    var homeURL: URL
    var currentURL: URL?
    var renderingProfile: WebRenderingProfile
    var residencyPolicy: SlotResidencyPolicy
    var backgroundMediaPolicy: BackgroundMediaPolicy
    var createdAt: Date
    var lastUsedAt: Date

    init(
        id: UUID = UUID(),
        order: Int,
        name: String,
        homeURL: URL,
        currentURL: URL? = nil,
        renderingProfile: WebRenderingProfile = .canonicalDefault,
        residencyPolicy: SlotResidencyPolicy = .warm,
        backgroundMediaPolicy: BackgroundMediaPolicy = .pauseWhenInactive,
        createdAt: Date = Date(),
        lastUsedAt: Date = Date()
    ) {
        self.id = id
        self.order = order
        self.name = name
        self.homeURL = homeURL
        self.currentURL = currentURL
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
        case order
        case name
        case homeURL
        case currentURL
        case renderingProfile
        case residencyPolicy
        case backgroundMediaPolicy
        case createdAt
        case lastUsedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        order = try container.decode(Int.self, forKey: .order)
        name = try container.decode(String.self, forKey: .name)
        homeURL = try container.decode(URL.self, forKey: .homeURL)
        currentURL = try container.decodeIfPresent(URL.self, forKey: .currentURL)
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
        try container.encode(order, forKey: .order)
        try container.encode(name, forKey: .name)
        try container.encode(homeURL, forKey: .homeURL)
        try container.encodeIfPresent(currentURL, forKey: .currentURL)
        try container.encode(renderingProfile, forKey: .renderingProfile)
        try container.encode(residencyPolicy, forKey: .residencyPolicy)
        try container.encode(backgroundMediaPolicy, forKey: .backgroundMediaPolicy)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(lastUsedAt, forKey: .lastUsedAt)
    }
}

enum WebAppURL {
    static func normalized(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate: String
        if trimmed.contains("://") {
            candidate = trimmed
        } else {
            candidate = "https://\(trimmed)"
        }

        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host,
              !host.isEmpty,
              let url = components.url,
              isSafe(url) else {
            return nil
        }

        return url
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
}