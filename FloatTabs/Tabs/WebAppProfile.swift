import Foundation

struct WebAppProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var order: Int
    var name: String
    var homeURL: URL
    var currentURL: URL?
    var renderingProfile: WebRenderingProfile
    var createdAt: Date
    var lastUsedAt: Date

    init(
        id: UUID = UUID(),
        order: Int,
        name: String,
        homeURL: URL,
        currentURL: URL? = nil,
        renderingProfile: WebRenderingProfile = .canonicalDefault,
        createdAt: Date = Date(),
        lastUsedAt: Date = Date()
    ) {
        self.id = id
        self.order = order
        self.name = name
        self.homeURL = homeURL
        self.currentURL = currentURL
        self.renderingProfile = renderingProfile
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
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
