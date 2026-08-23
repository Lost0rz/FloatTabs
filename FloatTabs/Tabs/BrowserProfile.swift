import Foundation

enum BrowserProfileColorPreset: String, CaseIterable, Codable, Equatable {
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
}

struct BrowserProfileColor: Codable, Equatable {
    static let `default` = BrowserProfileColor(preset: .blue)

    let preset: BrowserProfileColorPreset
    let customSRGBHex: String?

    init(
        preset: BrowserProfileColorPreset,
        customSRGBHex: String? = nil
    ) {
        guard preset == .custom else {
            self.preset = preset
            self.customSRGBHex = nil
            return
        }

        guard let normalized = Self.normalizedSRGBHex(customSRGBHex) else {
            self = .default
            return
        }
        self.preset = .custom
        self.customSRGBHex = normalized
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawPreset = try container.decodeIfPresent(String.self, forKey: .preset)
        let preset = rawPreset.flatMap(BrowserProfileColorPreset.init(rawValue:)) ?? .blue
        let customSRGBHex = try container.decodeIfPresent(String.self, forKey: .customSRGBHex)
        self.init(preset: preset, customSRGBHex: customSRGBHex)
    }

    private enum CodingKeys: String, CodingKey {
        case preset
        case customSRGBHex
    }

    static func normalizedSRGBHex(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let body = value.hasPrefix("#") ? String(value.dropFirst()) : value
        let validHex = CharacterSet(charactersIn: "0123456789ABCDEF")
        guard body.count == 6 || body.count == 8,
              body.unicodeScalars.allSatisfy({ validHex.contains($0) }) else {
            return nil
        }
        return "#" + body + (body.count == 6 ? "FF" : "")
    }
}

struct DefaultBrowserProfilePresentation: Codable, Equatable {
    static let `default` = DefaultBrowserProfilePresentation(
        name: "Default",
        color: .default
    )

    var name: String
    var color: BrowserProfileColor

    init(
        name: String = "Default",
        color: BrowserProfileColor = .default
    ) {
        self.name = name
        self.color = color
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Default"
        color = try container.decodeIfPresent(BrowserProfileColor.self, forKey: .color) ?? .default
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case color
    }
}

/// Persisted metadata for one custom browser data identity.
///
/// The built-in Default Profile is virtual and is intentionally not represented
/// by this type. A BrowserProfile's UUID is also the future WebKit data-store
/// identifier; the name is presentation metadata only.
struct BrowserProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    let createdAt: Date
    var color: BrowserProfileColor

    init(
        id: UUID,
        name: String,
        createdAt: Date,
        color: BrowserProfileColor = .default
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.color = color
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        color = try container.decodeIfPresent(BrowserProfileColor.self, forKey: .color) ?? .default
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt
        case color
    }
}
