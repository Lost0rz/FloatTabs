import Foundation

struct FloatTabsBackupShortcut: Codable, Equatable {
    let carbonKeyCode: Int
    let carbonModifiers: Int
}

struct FloatTabsBackupPreferences: Codable, Equatable {
    let appearanceMode: AppAppearanceMode
    let followPreferredSize: Bool
    let borderTheme: PanelBorderTheme?
    let customBorderColorHex: String?
    let fixedViewportWidth: Double?
    let fixedViewportHeight: Double?
    let isTabRailCollapsed: Bool?
    let menuBarDisplayMode: MenuBarDisplayMode?
    let attentionSoundEnabled: Bool?
    let attentionSoundName: String?
    let attentionSoundVolume: Double?

    var resolvedMenuBarDisplayMode: MenuBarDisplayMode {
        menuBarDisplayMode ?? .iconAndName
    }

    var resolvedAttentionSoundEnabled: Bool {
        attentionSoundEnabled ?? true
    }

    var resolvedAttentionSoundName: String {
        let trimmed = attentionSoundName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return AppPreferencesStore.defaultAttentionSoundName
        }
        return trimmed
    }

    var resolvedAttentionSoundVolume: Double {
        AppPreferencesStore.normalizedAttentionSoundVolume(attentionSoundVolume ?? 1)
    }

    init(
        appearanceMode: AppAppearanceMode,
        followPreferredSize: Bool,
        borderTheme: PanelBorderTheme? = nil,
        customBorderColorHex: String? = nil,
        fixedViewportWidth: Double? = nil,
        fixedViewportHeight: Double? = nil,
        isTabRailCollapsed: Bool? = nil,
        menuBarDisplayMode: MenuBarDisplayMode? = nil,
        attentionSoundEnabled: Bool? = nil,
        attentionSoundName: String? = nil,
        attentionSoundVolume: Double? = nil
    ) {
        self.appearanceMode = appearanceMode
        self.followPreferredSize = followPreferredSize
        self.borderTheme = borderTheme
        self.customBorderColorHex = customBorderColorHex
        self.fixedViewportWidth = fixedViewportWidth
        self.fixedViewportHeight = fixedViewportHeight
        self.isTabRailCollapsed = isTabRailCollapsed
        self.menuBarDisplayMode = menuBarDisplayMode
        self.attentionSoundEnabled = attentionSoundEnabled
        self.attentionSoundName = attentionSoundName
        self.attentionSoundVolume = attentionSoundVolume
    }
}

struct FloatTabsBackupDocument: Codable, Equatable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let createdAt: Date
    let sourceAppVersion: String
    let sourceBuild: String
    let webAppState: StoredWebAppState
    let globalPreferences: FloatTabsBackupPreferences
    let globalShowHideShortcut: FloatTabsBackupShortcut?
}

enum FloatTabsBackupError: LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case unsupportedWebAppStateVersion(Int)
    case mismatchedVersions(schemaVersion: Int, webAppStateVersion: Int)
    case restoreFailed
    case startupRecoveryFailed

    var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version):
            return "This FloatTabs backup uses unsupported backup schema version \(version)."
        case let .unsupportedWebAppStateVersion(version):
            return "This backup contains unsupported Web App state version \(version)."
        case let .mismatchedVersions(schemaVersion, webAppStateVersion):
            return "This backup combines unsupported schema/state versions (\(schemaVersion)/\(webAppStateVersion))."
        case .restoreFailed:
            return "FloatTabs could not replace the current configuration. The rollback backup was kept."
        case .startupRecoveryFailed:
            return "FloatTabs could not safely preserve and replace the unreadable startup configuration. The original profile store remains protected."
        }
    }
}

private struct BackupVersionEnvelope: Decodable {
    let schemaVersion: Int
    let webAppState: WebAppStateVersionEnvelope
}

private struct WebAppStateVersionEnvelope: Decodable {
    let version: Int
}

/// The v1 backup shape intentionally stays local to the backup authority.
/// ProfileRepository has a separate on-disk state migration contract and must
/// not be made permissive merely because backups need to read old data.
private struct LegacyBackupDocumentV1: Decodable {
    let schemaVersion: Int
    let createdAt: Date
    let sourceAppVersion: String
    let sourceBuild: String
    let webAppState: LegacyBackupWebAppStateV1
    let globalPreferences: FloatTabsBackupPreferences
    let globalShowHideShortcut: FloatTabsBackupShortcut?
}

private struct LegacyBackupWebAppStateV1: Decodable {
    let version: Int
    let profiles: [WebAppProfile]
    let lastActiveTabID: UUID?
}

struct FloatTabsBackupService {
    static let fileExtension = "floattabsbackup"

    private let fileManager: FileManager
    private let backupDirectoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileManager: FileManager = .default,
        backupDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.backupDirectoryURL = backupDirectoryURL
            ?? Self.defaultBackupDirectory(fileManager: fileManager)

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func encode(_ document: FloatTabsBackupDocument) throws -> Data {
        try encoder.encode(document)
    }

    func decode(_ data: Data) throws -> FloatTabsBackupDocument {
        let envelope = try decoder.decode(BackupVersionEnvelope.self, from: data)
        let schemaVersion = envelope.schemaVersion
        let webAppStateVersion = envelope.webAppState.version

        guard schemaVersion == 1 || schemaVersion == FloatTabsBackupDocument.currentSchemaVersion else {
            throw FloatTabsBackupError.unsupportedSchema(schemaVersion)
        }
        guard webAppStateVersion == 1 || webAppStateVersion == StoredWebAppState.currentVersion else {
            throw FloatTabsBackupError.unsupportedWebAppStateVersion(webAppStateVersion)
        }
        guard schemaVersion == webAppStateVersion else {
            throw FloatTabsBackupError.mismatchedVersions(
                schemaVersion: schemaVersion,
                webAppStateVersion: webAppStateVersion
            )
        }

        if schemaVersion == 1 {
            let legacy = try decoder.decode(LegacyBackupDocumentV1.self, from: data)
            let migratedProfiles = legacy.webAppState.profiles.map { profile -> WebAppProfile in
                var migrated = profile
                // Historical backups never had Profile isolation. Even if a
                // non-standard v1 payload smuggles in a binding field, the
                // frozen migration semantics explicitly map it to Default.
                migrated.browserProfileID = nil
                return migrated
            }
            let migratedState = try StoredWebAppState(
                version: StoredWebAppState.currentVersion,
                browserProfiles: [],
                profiles: migratedProfiles,
                lastActiveTabID: legacy.webAppState.lastActiveTabID
            ).sanitizedForUse()
            return FloatTabsBackupDocument(
                schemaVersion: FloatTabsBackupDocument.currentSchemaVersion,
                createdAt: legacy.createdAt,
                sourceAppVersion: legacy.sourceAppVersion,
                sourceBuild: legacy.sourceBuild,
                webAppState: migratedState,
                globalPreferences: legacy.globalPreferences,
                globalShowHideShortcut: legacy.globalShowHideShortcut
            )
        }

        let document = try decoder.decode(FloatTabsBackupDocument.self, from: data)
        let normalizedState = try document.webAppState.sanitizedForUse()
        return FloatTabsBackupDocument(
            schemaVersion: FloatTabsBackupDocument.currentSchemaVersion,
            createdAt: document.createdAt,
            sourceAppVersion: document.sourceAppVersion,
            sourceBuild: document.sourceBuild,
            webAppState: normalizedState,
            globalPreferences: document.globalPreferences,
            globalShowHideShortcut: document.globalShowHideShortcut
        )
    }

    func load(from url: URL) throws -> FloatTabsBackupDocument {
        try decode(Data(contentsOf: url))
    }

    func write(_ document: FloatTabsBackupDocument, to url: URL) throws {
        let data = try encode(document)
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
    }

    @discardableResult
    func writeRollback(
        _ document: FloatTabsBackupDocument,
        now: Date = Date()
    ) throws -> URL {
        try fileManager.createDirectory(
            at: backupDirectoryURL,
            withIntermediateDirectories: true
        )
        let url = backupDirectoryURL.appendingPathComponent(
            "FloatTabs-before-restore-\(Self.timestamp(now))-\(UUID().uuidString.prefix(8)).\(Self.fileExtension)"
        )
        try write(document, to: url)
        return url
    }

    @discardableResult
    func writeAutomaticVersionSnapshot(
        _ document: FloatTabsBackupDocument
    ) throws -> URL {
        try fileManager.createDirectory(
            at: backupDirectoryURL,
            withIntermediateDirectories: true
        )
        let version = Self.safeFileComponent(document.sourceAppVersion)
        let build = Self.safeFileComponent(document.sourceBuild)
        let url = backupDirectoryURL.appendingPathComponent(
            "FloatTabs-auto-\(version)-\(build).\(Self.fileExtension)"
        )
        try write(document, to: url)
        return url
    }

    /// Returns the newest decodable automatic snapshot by the timestamp stored
    /// inside the document. Corrupt or incompatible snapshots are skipped so a
    /// damaged backup can never become the default startup recovery choice.
    func latestValidAutomaticSnapshot() -> (url: URL, document: FloatTabsBackupDocument)? {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: backupDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return urls
            .filter {
                $0.pathExtension == Self.fileExtension
                    && $0.lastPathComponent.hasPrefix("FloatTabs-auto-")
            }
            .compactMap { url -> (url: URL, document: FloatTabsBackupDocument)? in
                guard let document = try? load(from: url) else { return nil }
                return (url, document)
            }
            .max { lhs, rhs in
                lhs.document.createdAt < rhs.document.createdAt
            }
    }

    static func suggestedExportFileName(now: Date = Date()) -> String {
        "FloatTabs-Backup-\(timestamp(now)).\(fileExtension)"
    }

    private static func defaultBackupDirectory(fileManager: FileManager) -> URL {
        let applicationSupport = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)

        return applicationSupport
            .appendingPathComponent("FloatTabs", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private static func safeFileComponent(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let scalars = raw.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        let value = String(scalars)
        return value.isEmpty ? "unknown" : value
    }
}
