import AppKit
import Foundation

enum WebAppGroupColorHex {
    static func normalizedHex(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard hex.count == 6 || hex.count == 8,
              hex.allSatisfy({ ("0"..."9").contains($0) || ("a"..."f").contains($0) || ("A"..."F").contains($0) }) else {
            return nil
        }
        return "#" + hex.uppercased() + (hex.count == 6 ? "FF" : "")
    }

    static func color(fromHex raw: String) -> NSColor? {
        guard let normalized = normalizedHex(raw) else { return nil }
        let body = String(normalized.dropFirst())
        guard let value = UInt64(body, radix: 16) else { return nil }
        let red = CGFloat((value >> 24) & 0xFF) / 255
        let green = CGFloat((value >> 16) & 0xFF) / 255
        let blue = CGFloat((value >> 8) & 0xFF) / 255
        let alpha = CGFloat(value & 0xFF) / 255
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

/// Presentation and optional border override metadata for the built-in Default Group (`groupID == nil`).
struct DefaultWebAppGroupPresentation: Codable, Equatable {
    static let defaultName = "Default"

    static let `default` = DefaultWebAppGroupPresentation(
        name: defaultName,
        borderTheme: nil,
        customBorderColorHex: nil
    )

    var name: String
    var borderTheme: PanelBorderTheme?
    var customBorderColorHex: String?

    init(
        name: String = Self.defaultName,
        borderTheme: PanelBorderTheme? = nil,
        customBorderColorHex: String? = nil
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmed.isEmpty ? Self.defaultName : trimmed
        self.borderTheme = borderTheme
        self.customBorderColorHex = WebAppGroupColorHex.normalizedHex(customBorderColorHex ?? "")
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedName = try container.decodeIfPresent(String.self, forKey: .name)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        name = decodedName.isEmpty ? Self.defaultName : decodedName
        borderTheme = try container.decodeIfPresent(PanelBorderTheme.self, forKey: .borderTheme)
        if let rawHex = try container.decodeIfPresent(String.self, forKey: .customBorderColorHex) {
            customBorderColorHex = WebAppGroupColorHex.normalizedHex(rawHex)
        } else {
            customBorderColorHex = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(borderTheme, forKey: .borderTheme)
        try container.encodeIfPresent(customBorderColorHex, forKey: .customBorderColorHex)
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case borderTheme
        case customBorderColorHex
    }
}

/// Persisted user-defined Tab Group with its own tab list and optional window border theme override.
struct WebAppGroup: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var order: Int
    var borderTheme: PanelBorderTheme?
    var customBorderColorHex: String?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        order: Int = 0,
        borderTheme: PanelBorderTheme? = nil,
        customBorderColorHex: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.order = order
        self.borderTheme = borderTheme
        self.customBorderColorHex = WebAppGroupColorHex.normalizedHex(customBorderColorHex ?? "")
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
        borderTheme = try container.decodeIfPresent(PanelBorderTheme.self, forKey: .borderTheme)
        if let rawHex = try container.decodeIfPresent(String.self, forKey: .customBorderColorHex) {
            customBorderColorHex = WebAppGroupColorHex.normalizedHex(rawHex)
        } else {
            customBorderColorHex = nil
        }
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(order, forKey: .order)
        try container.encodeIfPresent(borderTheme, forKey: .borderTheme)
        try container.encodeIfPresent(customBorderColorHex, forKey: .customBorderColorHex)
        try container.encode(createdAt, forKey: .createdAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case order
        case borderTheme
        case customBorderColorHex
        case createdAt
    }
}

/// UI projection for one group item shown in the bottom-left switcher and context menus.
struct WebAppGroupMenuOption: Equatable, Identifiable {
    let id: UUID?
    let name: String
    let borderTheme: PanelBorderTheme?
    let customBorderColorHex: String?
    let isDefault: Bool
    let isActive: Bool
    let slotCount: Int
    var unreadCount: Int = 0

    var stableIdentifier: String {
        id?.uuidString ?? "default-group"
    }

    var resolvedCustomColor: NSColor? {
        guard let customBorderColorHex else { return nil }
        return WebAppGroupColorHex.color(fromHex: customBorderColorHex)
    }

    var swatchColor: NSColor? {
        guard let borderTheme else { return nil }
        switch borderTheme {
        case .rainbow:
            return .systemPurple
        case .custom:
            return resolvedCustomColor ?? .systemBlue
        default:
            return borderTheme.solidColor
        }
    }
}

/// User-defined folder for organizing bookmarks in Settings and Add Web App.
struct BookmarkFolder: Codable, Identifiable, Equatable {
    let id: UUID
    var parentFolderID: UUID?
    var name: String
    var order: Int
    let createdAt: Date

    init(
        id: UUID = UUID(),
        parentFolderID: UUID? = nil,
        name: String,
        order: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.parentFolderID = parentFolderID
        self.name = name
        self.order = order
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        parentFolderID = try container.decodeIfPresent(UUID.self, forKey: .parentFolderID)
        name = try container.decode(String.self, forKey: .name)
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(parentFolderID, forKey: .parentFolderID)
        try container.encode(name, forKey: .name)
        try container.encode(order, forKey: .order)
        try container.encode(createdAt, forKey: .createdAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case parentFolderID
        case name
        case order
        case createdAt
    }
}

/// Reusable web app bookmark persisted alongside tabs and profiles.
struct BookmarkItem: Codable, Identifiable, Equatable {
    let id: UUID
    var folderID: UUID?
    var order: Int
    var title: String
    var url: URL
    var notes: String?
    var preferredWebsiteMode: WebsiteMode?
    var browserProfileID: UUID?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        folderID: UUID? = nil,
        order: Int = 0,
        title: String,
        url: URL,
        notes: String? = nil,
        preferredWebsiteMode: WebsiteMode? = nil,
        browserProfileID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.folderID = folderID
        self.order = order
        self.title = title
        self.url = url
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.notes = (trimmedNotes?.isEmpty == false) ? trimmedNotes : nil
        self.preferredWebsiteMode = preferredWebsiteMode
        self.browserProfileID = browserProfileID
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        folderID = try container.decodeIfPresent(UUID.self, forKey: .folderID)
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
        title = try container.decode(String.self, forKey: .title)
        url = try container.decode(URL.self, forKey: .url)
        let decodedNotes = try container.decodeIfPresent(String.self, forKey: .notes)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        notes = (decodedNotes?.isEmpty == false) ? decodedNotes : nil
        preferredWebsiteMode = try container.decodeIfPresent(WebsiteMode.self, forKey: .preferredWebsiteMode)
        browserProfileID = try container.decodeIfPresent(UUID.self, forKey: .browserProfileID)
        let decodedCreatedAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        createdAt = decodedCreatedAt
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? decodedCreatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case folderID
        case order
        case title
        case url
        case notes
        case preferredWebsiteMode
        case browserProfileID
        case createdAt
        case updatedAt
    }
}
