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
            return .empty
        }

        let data = try Data(contentsOf: fileURL)
        let decoded = try decoder.decode(StoredWebAppState.self, from: data)
        guard decoded.version == StoredWebAppState.currentVersion else {
            throw ProfileRepositoryError.unsupportedVersion(decoded.version)
        }

        let sanitizedProfiles = decoded.profiles.compactMap(Self.sanitizedProfile)
        return StoredWebAppState(
            version: StoredWebAppState.currentVersion,
            profiles: sanitizedProfiles,
            lastActiveTabID: decoded.lastActiveTabID
        )
    }

    func save(_ state: StoredWebAppState) throws {
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

    private static func sanitizedProfile(_ profile: WebAppProfile) -> WebAppProfile? {
        guard WebAppURL.isSafe(profile.homeURL) else { return nil }

        var sanitized = profile
        if let currentURL = sanitized.currentURL, !WebAppURL.isSafe(currentURL) {
            sanitized.currentURL = nil
        }
        return sanitized
    }
}
