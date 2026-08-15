import Foundation

struct StoredWebAppState: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var profiles: [WebAppProfile]
    var lastActiveTabID: UUID?

    static let empty = StoredWebAppState(
        version: currentVersion,
        profiles: [],
        lastActiveTabID: nil
    )
}

enum ProfileRepositoryError: Error, Equatable {
    case unsupportedVersion(Int)
    case startupRecoveryRequired
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
            let decoded = try decoder.decode(StoredWebAppState.self, from: data)
            guard decoded.version == StoredWebAppState.currentVersion else {
                throw ProfileRepositoryError.unsupportedVersion(decoded.version)
            }

            startupRecoveryRequired = false
            startupRecoveryArchiveURL = nil
            return decoded.sanitizedForUse()
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

        // The exact corrupt bytes are now protected, but an empty recovery can
        // span multiple launches. Persist a tiny marker beside the profile store
        // so a later clean launch cannot overwrite the last known-good automatic
        // backup until a non-empty configuration has actually been rebuilt.
        let markerURL = directory.appendingPathComponent(
            FloatTabsBackupService.startupRecoverySnapshotPreservationMarkerFileName,
            isDirectory: false
        )
        try Data().write(to: markerURL, options: [.atomic])

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

        let normalizedState = StoredWebAppState(
            version: StoredWebAppState.currentVersion,
            profiles: state.profiles,
            lastActiveTabID: state.lastActiveTabID
        )
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
    func sanitizedForUse() -> StoredWebAppState {
        let sanitizedProfiles = profiles.compactMap { profile -> WebAppProfile? in
            guard WebAppURL.isSafe(profile.homeURL) else { return nil }
            var sanitized = profile
            if let currentURL = sanitized.currentURL, !WebAppURL.isSafe(currentURL) {
                sanitized.currentURL = nil
            }
            return sanitized
        }

        return StoredWebAppState(
            version: StoredWebAppState.currentVersion,
            profiles: sanitizedProfiles,
            lastActiveTabID: lastActiveTabID
        )
    }
}
