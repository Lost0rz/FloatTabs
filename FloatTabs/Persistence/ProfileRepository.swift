import Foundation

struct StoredWebAppState: Codable, Equatable {
    static let currentVersion = 2

    var version: Int
    var browserProfiles: [BrowserProfile]
    var profiles: [WebAppProfile]
    var lastActiveTabID: UUID?

    init(
        version: Int,
        browserProfiles: [BrowserProfile] = [],
        profiles: [WebAppProfile],
        lastActiveTabID: UUID?
    ) {
        self.version = version
        self.browserProfiles = browserProfiles
        self.profiles = profiles
        self.lastActiveTabID = lastActiveTabID
    }

    static let empty = StoredWebAppState(
        version: currentVersion,
        browserProfiles: [],
        profiles: [],
        lastActiveTabID: nil
    )
}

enum ProfileRepositoryError: Error, Equatable {
    case unsupportedVersion(Int)
    case startupRecoveryRequired
    case duplicateBrowserProfileID(UUID)
    case invalidBrowserProfileName(UUID)
    case reservedBrowserProfileName(UUID)
    case duplicateBrowserProfileName(String)
    case danglingBrowserProfileReference(UUID)
}

enum BrowserProfileValidation {
    static func validateMetadata(_ profiles: [BrowserProfile]) throws {
        var seenIDs = Set<UUID>()
        var seenNames = Set<String>()

        for profile in profiles {
            guard seenIDs.insert(profile.id).inserted else {
                throw ProfileRepositoryError.duplicateBrowserProfileID(profile.id)
            }

            let trimmedName = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty, trimmedName == profile.name else {
                throw ProfileRepositoryError.invalidBrowserProfileName(profile.id)
            }

            let foldedName = profile.name.lowercased()
            guard foldedName != "default" else {
                throw ProfileRepositoryError.reservedBrowserProfileName(profile.id)
            }

            guard seenNames.insert(foldedName).inserted else {
                throw ProfileRepositoryError.duplicateBrowserProfileName(profile.name)
            }
        }
    }

    static func validate(
        browserProfiles: [BrowserProfile],
        slots: [WebAppProfile]
    ) throws {
        try validateMetadata(browserProfiles)
        let browserProfileIDs = Set(browserProfiles.map(\.id))

        for slot in slots {
            if let browserProfileID = slot.browserProfileID,
               !browserProfileIDs.contains(browserProfileID) {
                throw ProfileRepositoryError.danglingBrowserProfileReference(browserProfileID)
            }
        }
    }
}

private struct StateVersionEnvelope: Decodable {
    let version: Int
}

private struct LegacyStoredWebAppState: Decodable {
    let version: Int
    let profiles: [WebAppProfile]
    let lastActiveTabID: UUID?
}

protocol ProfileRepositoryProtocol: AnyObject {
    func load() throws -> StoredWebAppState
    func save(_ state: StoredWebAppState) throws
}

final class ProfileRepository: ProfileRepositoryProtocol {
    private let fileManager: FileManager
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private(set) var startupRecoveryRequired = false
    private(set) var startupRecoveryArchiveURL: URL?

    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() throws -> StoredWebAppState {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            startupRecoveryRequired = false
            startupRecoveryArchiveURL = nil
            return .empty
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let version = try decoder.decode(StateVersionEnvelope.self, from: data).version

            let state: StoredWebAppState
            switch version {
            case 1:
                let legacy = try decoder.decode(LegacyStoredWebAppState.self, from: data)
                let migratedProfiles = legacy.profiles.map { profile -> WebAppProfile in
                    var migrated = profile
                    migrated.browserProfileID = nil
                    return migrated
                }
                state = StoredWebAppState(
                    version: StoredWebAppState.currentVersion,
                    browserProfiles: [],
                    profiles: migratedProfiles,
                    lastActiveTabID: legacy.lastActiveTabID
                )
                let migratedState = try state.sanitizedForUse()
                try save(migratedState)
                startupRecoveryRequired = false
                startupRecoveryArchiveURL = nil
                return migratedState
            case StoredWebAppState.currentVersion:
                state = try decoder.decode(StoredWebAppState.self, from: data)
            default:
                throw ProfileRepositoryError.unsupportedVersion(version)
            }

            startupRecoveryRequired = false
            startupRecoveryArchiveURL = nil
            return try state.sanitizedForUse()
        } catch {
            // An unreadable on-disk profile store is never treated as permission
            // to replace it with the empty in-memory fallback. All writes remain
            // blocked until the startup recovery flow has copied the exact bytes
            // aside for manual recovery.
            startupRecoveryRequired = true
            startupRecoveryArchiveURL = nil
            throw error
        }
    }

    @discardableResult
    func preserveUnreadableStoreForRecovery(now: Date = Date()) throws -> URL? {
        guard startupRecoveryRequired else { return startupRecoveryArchiveURL }
        if let startupRecoveryArchiveURL {
            return startupRecoveryArchiveURL
        }
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let archiveURL = directory.appendingPathComponent(
            "WebAppProfiles-recovery-\(Self.timestamp(now))-\(UUID().uuidString.prefix(8)).json",
            isDirectory: false
        )
        try fileManager.copyItem(at: fileURL, to: archiveURL)
        startupRecoveryArchiveURL = archiveURL
        return archiveURL
    }

    func save(_ state: StoredWebAppState) throws {
        if startupRecoveryRequired, startupRecoveryArchiveURL == nil {
            throw ProfileRepositoryError.startupRecoveryRequired
        }

        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        guard state.version == StoredWebAppState.currentVersion else {
            throw ProfileRepositoryError.unsupportedVersion(state.version)
        }
        let normalizedState = try state.sanitizedForUse()
        let data = try encoder.encode(normalizedState)
        try data.write(to: fileURL, options: [.atomic])

        // A successful atomic replacement is the only transition that clears
        // recovery mode. If the save throws, the protected copy remains and the
        // app continues to block further ordinary persistence.
        startupRecoveryRequired = false
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let applicationSupport = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)

        return applicationSupport
            .appendingPathComponent("FloatTabs", isDirectory: true)
            .appendingPathComponent("WebAppProfiles.json", isDirectory: false)
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}

extension StoredWebAppState {
    func sanitizedForUse() throws -> StoredWebAppState {
        // Validate references before URL sanitation can remove an unsafe Slot;
        // otherwise a dangling custom Profile ID could disappear as an
        // accidental side effect of unrelated URL repair.
        try BrowserProfileValidation.validate(
            browserProfiles: browserProfiles,
            slots: profiles
        )

        let sanitizedProfiles = profiles.compactMap { profile -> WebAppProfile? in
            guard WebAppURL.isSafe(profile.homeURL) else { return nil }
            var sanitized = profile
            if let currentURL = sanitized.currentURL, !WebAppURL.isSafe(currentURL) {
                sanitized.currentURL = nil
            }
            return sanitized
        }

        let sanitizedState = StoredWebAppState(
            version: StoredWebAppState.currentVersion,
            browserProfiles: browserProfiles,
            profiles: sanitizedProfiles,
            lastActiveTabID: lastActiveTabID
        )
        try BrowserProfileValidation.validate(
            browserProfiles: sanitizedState.browserProfiles,
            slots: sanitizedState.profiles
        )
        return sanitizedState
    }
}
