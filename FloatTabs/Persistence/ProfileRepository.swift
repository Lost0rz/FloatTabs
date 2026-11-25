import Foundation

struct StoredBookmarksDocument: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var bookmarkFolders: [BookmarkFolder]
    var bookmarks: [BookmarkItem]

    init(
        version: Int = currentVersion,
        bookmarkFolders: [BookmarkFolder] = [],
        bookmarks: [BookmarkItem] = []
    ) {
        self.version = version
        self.bookmarkFolders = bookmarkFolders
        self.bookmarks = bookmarks
    }

    static let empty = StoredBookmarksDocument(
        version: currentVersion,
        bookmarkFolders: [],
        bookmarks: []
    )
}

struct StoredWebAppState: Codable, Equatable {
    static let currentVersion = 2

    var version: Int
    var browserProfiles: [BrowserProfile]
    var defaultBrowserProfilePresentation: DefaultBrowserProfilePresentation
    var isDefaultBrowserProfileDeleted: Bool
    var profiles: [WebAppProfile]
    var lastActiveTabID: UUID?
    var defaultGroupPresentation: DefaultWebAppGroupPresentation
    var groups: [WebAppGroup]
    var activeGroupID: UUID?
    var bookmarkFolders: [BookmarkFolder]
    var bookmarks: [BookmarkItem]

    init(
        version: Int,
        browserProfiles: [BrowserProfile] = [],
        defaultBrowserProfilePresentation: DefaultBrowserProfilePresentation = .default,
        isDefaultBrowserProfileDeleted: Bool = false,
        profiles: [WebAppProfile],
        lastActiveTabID: UUID?,
        defaultGroupPresentation: DefaultWebAppGroupPresentation = .default,
        groups: [WebAppGroup] = [],
        activeGroupID: UUID? = nil,
        bookmarkFolders: [BookmarkFolder] = [],
        bookmarks: [BookmarkItem] = []
    ) {
        self.version = version
        self.browserProfiles = browserProfiles
        self.defaultBrowserProfilePresentation = defaultBrowserProfilePresentation
        self.isDefaultBrowserProfileDeleted = isDefaultBrowserProfileDeleted
        self.profiles = profiles
        self.lastActiveTabID = lastActiveTabID
        self.defaultGroupPresentation = defaultGroupPresentation
        self.groups = groups
        self.activeGroupID = activeGroupID
        self.bookmarkFolders = bookmarkFolders
        self.bookmarks = bookmarks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        browserProfiles = try container.decode([BrowserProfile].self, forKey: .browserProfiles)
        defaultBrowserProfilePresentation = try container.decodeIfPresent(
            DefaultBrowserProfilePresentation.self,
            forKey: .defaultBrowserProfilePresentation
        ) ?? .default
        isDefaultBrowserProfileDeleted = try container.decodeIfPresent(
            Bool.self,
            forKey: .isDefaultBrowserProfileDeleted
        ) ?? false
        profiles = try container.decode([WebAppProfile].self, forKey: .profiles)
        lastActiveTabID = try container.decodeIfPresent(UUID.self, forKey: .lastActiveTabID)
        defaultGroupPresentation = try container.decodeIfPresent(
            DefaultWebAppGroupPresentation.self,
            forKey: .defaultGroupPresentation
        ) ?? .default
        groups = try container.decodeIfPresent([WebAppGroup].self, forKey: .groups) ?? []
        activeGroupID = try container.decodeIfPresent(UUID.self, forKey: .activeGroupID)
        bookmarkFolders = try container.decodeIfPresent([BookmarkFolder].self, forKey: .bookmarkFolders) ?? []
        bookmarks = try container.decodeIfPresent([BookmarkItem].self, forKey: .bookmarks) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(browserProfiles, forKey: .browserProfiles)
        try container.encode(defaultBrowserProfilePresentation, forKey: .defaultBrowserProfilePresentation)
        if isDefaultBrowserProfileDeleted {
            try container.encode(true, forKey: .isDefaultBrowserProfileDeleted)
        }
        try container.encode(profiles, forKey: .profiles)
        try container.encodeIfPresent(lastActiveTabID, forKey: .lastActiveTabID)
        if defaultGroupPresentation != .default {
            try container.encode(defaultGroupPresentation, forKey: .defaultGroupPresentation)
        }
        if !groups.isEmpty {
            try container.encode(groups, forKey: .groups)
        }
        try container.encodeIfPresent(activeGroupID, forKey: .activeGroupID)
        if !bookmarkFolders.isEmpty {
            try container.encode(bookmarkFolders, forKey: .bookmarkFolders)
        }
        if !bookmarks.isEmpty {
            try container.encode(bookmarks, forKey: .bookmarks)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case browserProfiles
        case defaultBrowserProfilePresentation
        case isDefaultBrowserProfileDeleted
        case profiles
        case lastActiveTabID
        case defaultGroupPresentation
        case groups
        case activeGroupID
        case bookmarkFolders
        case bookmarks
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
    case bookmarksRecoveryRequired
    case duplicateBrowserProfileID(UUID)
    case invalidBrowserProfileName(UUID)
    case invalidDefaultBrowserProfileName
    case reservedBrowserProfileName(UUID)
    case duplicateBrowserProfileName(String)
    case danglingBrowserProfileReference(UUID)
    case danglingDefaultBrowserProfileReference
}

enum BrowserProfileValidation {
    static func validateMetadata(
        _ profiles: [BrowserProfile],
        defaultDisplayName: String = DefaultBrowserProfilePresentation.default.name,
        includeDefaultProfile: Bool = true
    ) throws {
        var seenIDs = Set<UUID>()
        var seenNames = Set<String>()

        if includeDefaultProfile {
            let trimmedDefaultName = defaultDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedDefaultName.isEmpty, trimmedDefaultName == defaultDisplayName else {
                throw ProfileRepositoryError.invalidDefaultBrowserProfileName
            }
            seenNames.insert(defaultDisplayName.lowercased())
        }

        for profile in profiles {
            guard seenIDs.insert(profile.id).inserted else {
                throw ProfileRepositoryError.duplicateBrowserProfileID(profile.id)
            }

            let trimmedName = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty, trimmedName == profile.name else {
                throw ProfileRepositoryError.invalidBrowserProfileName(profile.id)
            }

            let foldedName = profile.name.lowercased()
            guard seenNames.insert(foldedName).inserted else {
                throw ProfileRepositoryError.duplicateBrowserProfileName(profile.name)
            }
        }
    }

    static func validate(
        browserProfiles: [BrowserProfile],
        defaultDisplayName: String = DefaultBrowserProfilePresentation.default.name,
        includeDefaultProfile: Bool = true,
        slots: [WebAppProfile]
    ) throws {
        try validateMetadata(
            browserProfiles,
            defaultDisplayName: defaultDisplayName,
            includeDefaultProfile: includeDefaultProfile
        )
        let browserProfileIDs = Set(browserProfiles.map(\.id))

        for slot in slots {
            if let browserProfileID = slot.browserProfileID {
                if !browserProfileIDs.contains(browserProfileID) {
                    throw ProfileRepositoryError.danglingBrowserProfileReference(browserProfileID)
                }
            } else if !includeDefaultProfile {
                throw ProfileRepositoryError.danglingDefaultBrowserProfileReference
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
    let bookmarksFileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private enum SidecarBookmarksLoadOutcome {
        case absent
        case loaded(StoredBookmarksDocument)
        case unreadable(archiveURL: URL?)
    }

    private(set) var startupRecoveryRequired = false
    private(set) var startupRecoveryArchiveURL: URL?
    private(set) var bookmarksRecoveryRequired = false
    private(set) var bookmarksRecoveryArchiveURL: URL?
    private var startupRecoveryReplacementInProgress = false
    private var startupRecoveryReplacementDidWrite = false
    private var lastPersistedBookmarks: StoredBookmarksDocument?
    private var lastPersistedBrowserProfileIDs = Set<UUID>()

    init(
        fileManager: FileManager = .default,
        fileURL: URL? = nil,
        bookmarksFileURL: URL? = nil
    ) {
        self.fileManager = fileManager
        let resolvedFileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        self.fileURL = resolvedFileURL
        self.bookmarksFileURL = bookmarksFileURL
            ?? resolvedFileURL.deletingLastPathComponent().appendingPathComponent(
                "Bookmarks.json",
                isDirectory: false
            )

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
            bookmarksRecoveryRequired = false
            bookmarksRecoveryArchiveURL = nil
            lastPersistedBookmarks = nil
            lastPersistedBrowserProfileIDs.removeAll()
            return .empty
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let version = try decoder.decode(StateVersionEnvelope.self, from: data).version

            var state: StoredWebAppState
            var shouldMigrateToSplitFiles = false
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
                    defaultBrowserProfilePresentation: .default,
                    profiles: migratedProfiles,
                    lastActiveTabID: legacy.lastActiveTabID
                )
                shouldMigrateToSplitFiles = true
            case StoredWebAppState.currentVersion:
                state = try decoder.decode(StoredWebAppState.self, from: data)
            default:
                throw ProfileRepositoryError.unsupportedVersion(version)
            }

            let legacyInlineHadBookmarks = !state.bookmarkFolders.isEmpty || !state.bookmarks.isEmpty
            let sidecarOutcome = loadSidecarBookmarksIfPresent()
            var hasSidecarBookmarks = false
            switch sidecarOutcome {
            case let .loaded(loadedSplitBookmarks):
                state.bookmarkFolders = loadedSplitBookmarks.bookmarkFolders
                state.bookmarks = loadedSplitBookmarks.bookmarks
                bookmarksRecoveryRequired = false
                bookmarksRecoveryArchiveURL = nil
                hasSidecarBookmarks = true
                if legacyInlineHadBookmarks {
                    shouldMigrateToSplitFiles = true
                }
            case .absent:
                bookmarksRecoveryRequired = false
                bookmarksRecoveryArchiveURL = nil
                if legacyInlineHadBookmarks {
                    shouldMigrateToSplitFiles = true
                }
            case let .unreadable(archiveURL):
                state.bookmarkFolders = []
                state.bookmarks = []
                bookmarksRecoveryRequired = true
                bookmarksRecoveryArchiveURL = archiveURL
            }

            startupRecoveryRequired = false
            startupRecoveryArchiveURL = nil
            let sanitized = try state.sanitizedForUse()
            let sanitizedBookmarksDoc = StoredBookmarksDocument(
                version: StoredBookmarksDocument.currentVersion,
                bookmarkFolders: sanitized.bookmarkFolders,
                bookmarks: sanitized.bookmarks
            )
            if shouldMigrateToSplitFiles && !bookmarksRecoveryRequired {
                try save(sanitized)
            } else {
                lastPersistedBookmarks = hasSidecarBookmarks ? sanitizedBookmarksDoc : nil
                lastPersistedBrowserProfileIDs = Set(sanitized.browserProfiles.map(\.id))
            }
            return sanitized
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

    @discardableResult
    func performStartupRecoveryReplacement<T>(
        _ operation: () throws -> T
    ) throws -> T {
        guard startupRecoveryRequired,
              !startupRecoveryReplacementInProgress,
              let archiveURL = startupRecoveryArchiveURL,
              fileManager.fileExists(atPath: archiveURL.path) else {
            throw ProfileRepositoryError.startupRecoveryRequired
        }

        startupRecoveryReplacementInProgress = true
        startupRecoveryReplacementDidWrite = false
        defer {
            startupRecoveryReplacementInProgress = false
            startupRecoveryReplacementDidWrite = false
        }

        do {
            let result = try operation()
            guard startupRecoveryReplacementDidWrite else {
                startupRecoveryRequired = true
                throw ProfileRepositoryError.startupRecoveryRequired
            }
            return result
        } catch {
            startupRecoveryRequired = true
            throw error
        }
    }

    func save(_ state: StoredWebAppState) throws {
        if startupRecoveryReplacementInProgress,
           startupRecoveryReplacementDidWrite {
            throw ProfileRepositoryError.startupRecoveryRequired
        }
        if startupRecoveryRequired, !startupRecoveryReplacementInProgress {
            throw ProfileRepositoryError.startupRecoveryRequired
        }
        if bookmarksRecoveryRequired && (!state.bookmarkFolders.isEmpty || !state.bookmarks.isEmpty) {
            throw ProfileRepositoryError.bookmarksRecoveryRequired
        }

        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        guard state.version == StoredWebAppState.currentVersion else {
            throw ProfileRepositoryError.unsupportedVersion(state.version)
        }
        let coreState = try state.sanitizedCoreStateForUse()
        let validBrowserProfileIDs = Set(coreState.browserProfiles.map(\.id))

        let targetBookmarksDocument: StoredBookmarksDocument
        if let cached = lastPersistedBookmarks,
           cached.bookmarkFolders == state.bookmarkFolders,
           cached.bookmarks == state.bookmarks,
           lastPersistedBrowserProfileIDs == validBrowserProfileIDs {
            targetBookmarksDocument = cached
        } else {
            let sanitized = StoredWebAppState.sanitizedBookmarks(
                folders: state.bookmarkFolders,
                bookmarks: state.bookmarks,
                validBrowserProfileIDs: validBrowserProfileIDs
            )
            targetBookmarksDocument = StoredBookmarksDocument(
                version: StoredBookmarksDocument.currentVersion,
                bookmarkFolders: sanitized.folders,
                bookmarks: sanitized.bookmarks
            )
        }

        let coreData = try encoder.encode(coreState)
        try coreData.write(to: fileURL, options: [.atomic])

        if !bookmarksRecoveryRequired {
            let bookmarksFileExists = fileManager.fileExists(atPath: bookmarksFileURL.path)
            let hasBookmarks = !targetBookmarksDocument.bookmarkFolders.isEmpty
                || !targetBookmarksDocument.bookmarks.isEmpty
            if lastPersistedBookmarks != targetBookmarksDocument || (hasBookmarks && !bookmarksFileExists) {
                if hasBookmarks || bookmarksFileExists {
                    let bookmarksDirectory = bookmarksFileURL.deletingLastPathComponent()
                    try fileManager.createDirectory(
                        at: bookmarksDirectory,
                        withIntermediateDirectories: true
                    )
                    let bookmarksData = try encoder.encode(targetBookmarksDocument)
                    try bookmarksData.write(to: bookmarksFileURL, options: [.atomic])
                }
                lastPersistedBookmarks = targetBookmarksDocument
            }
        }
        lastPersistedBrowserProfileIDs = validBrowserProfileIDs

        if startupRecoveryReplacementInProgress {
            startupRecoveryReplacementDidWrite = true
        }
        // A successful atomic replacement is the only transition that clears
        // recovery mode. If the save throws, the protected copy remains and the
        // app continues to block further ordinary persistence.
        startupRecoveryRequired = false
    }

    @discardableResult
    func preserveUnreadableBookmarksFileForRecovery(now: Date = Date()) -> URL? {
        if let bookmarksRecoveryArchiveURL,
           fileManager.fileExists(atPath: bookmarksRecoveryArchiveURL.path) {
            return bookmarksRecoveryArchiveURL
        }
        guard fileManager.fileExists(atPath: bookmarksFileURL.path) else { return nil }
        let directory = bookmarksFileURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let archiveURL = directory.appendingPathComponent(
            "Bookmarks-recovery-\(Self.timestamp(now))-\(UUID().uuidString.prefix(8)).json",
            isDirectory: false
        )
        do {
            try fileManager.copyItem(at: bookmarksFileURL, to: archiveURL)
            bookmarksRecoveryArchiveURL = archiveURL
            return archiveURL
        } catch {
            return nil
        }
    }

    func acceptEmptyBookmarksAfterRecovery(now: Date = Date()) throws {
        guard bookmarksRecoveryRequired else { return }
        if fileManager.fileExists(atPath: bookmarksFileURL.path),
           preserveUnreadableBookmarksFileForRecovery(now: now) == nil {
            throw ProfileRepositoryError.bookmarksRecoveryRequired
        }
        let bookmarksDirectory = bookmarksFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: bookmarksDirectory, withIntermediateDirectories: true)
        let data = try encoder.encode(StoredBookmarksDocument.empty)
        try data.write(to: bookmarksFileURL, options: [.atomic])
        lastPersistedBookmarks = .empty
        bookmarksRecoveryRequired = false
    }

    func allowBookmarksReplacementAfterBackupRestore(now: Date = Date()) throws {
        guard bookmarksRecoveryRequired else { return }
        if fileManager.fileExists(atPath: bookmarksFileURL.path),
           preserveUnreadableBookmarksFileForRecovery(now: now) == nil {
            throw ProfileRepositoryError.bookmarksRecoveryRequired
        }
        lastPersistedBookmarks = nil
        bookmarksRecoveryRequired = false
    }

    func emptyCoreStatePreservingSidecarBookmarks() -> StoredWebAppState {
        var emptyState = StoredWebAppState.empty
        switch loadSidecarBookmarksIfPresent() {
        case let .loaded(loadedSplitBookmarks):
            let sanitized = StoredWebAppState.sanitizedBookmarks(
                folders: loadedSplitBookmarks.bookmarkFolders,
                bookmarks: loadedSplitBookmarks.bookmarks,
                validBrowserProfileIDs: []
            )
            emptyState.bookmarkFolders = sanitized.folders
            emptyState.bookmarks = sanitized.bookmarks
            lastPersistedBookmarks = StoredBookmarksDocument(
                version: StoredBookmarksDocument.currentVersion,
                bookmarkFolders: sanitized.folders,
                bookmarks: sanitized.bookmarks
            )
            lastPersistedBrowserProfileIDs.removeAll()
            bookmarksRecoveryRequired = false
            bookmarksRecoveryArchiveURL = nil
        case .absent:
            lastPersistedBookmarks = nil
            bookmarksRecoveryRequired = false
            bookmarksRecoveryArchiveURL = nil
        case let .unreadable(archiveURL):
            bookmarksRecoveryRequired = true
            bookmarksRecoveryArchiveURL = archiveURL
        }
        return emptyState
    }

    private func loadSidecarBookmarksIfPresent() -> SidecarBookmarksLoadOutcome {
        guard fileManager.fileExists(atPath: bookmarksFileURL.path) else {
            return .absent
        }
        do {
            let data = try Data(contentsOf: bookmarksFileURL)
            let document = try decoder.decode(StoredBookmarksDocument.self, from: data)
            guard document.version == StoredBookmarksDocument.currentVersion else {
                let archiveURL = preserveUnreadableBookmarksFileForRecovery()
                return .unreadable(archiveURL: archiveURL)
            }
            return .loaded(document)
        } catch {
            let archiveURL = preserveUnreadableBookmarksFileForRecovery()
            return .unreadable(archiveURL: archiveURL)
        }
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
    func sanitizedCoreStateForUse() throws -> StoredWebAppState {
        // Reserve at least one Browser Profile even if a manually edited file omits custom profiles.
        let effectiveDefaultDeleted = isDefaultBrowserProfileDeleted && !browserProfiles.isEmpty

        // Validate references before URL sanitation can remove an unsafe Slot;
        // otherwise a dangling custom Profile ID could disappear as an
        // accidental side effect of unrelated URL repair.
        try BrowserProfileValidation.validate(
            browserProfiles: browserProfiles,
            defaultDisplayName: defaultBrowserProfilePresentation.name,
            includeDefaultProfile: !effectiveDefaultDeleted,
            slots: profiles
        )

        var seenGroupIDs = Set<UUID>()
        let sanitizedGroups: [WebAppGroup] = groups
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.createdAt < $1.createdAt
            }
            .compactMap { group -> WebAppGroup? in
                let trimmed = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, seenGroupIDs.insert(group.id).inserted else {
                    return nil
                }
                var updated = group
                updated.name = trimmed
                updated.customBorderColorHex = WebAppGroupColorHex.normalizedHex(
                    group.customBorderColorHex ?? ""
                )
                return updated
            }
            .enumerated()
            .map { index, group in
                var reordered = group
                reordered.order = index
                return reordered
            }

        let validGroupIDs = Set(sanitizedGroups.map(\.id))
        let sanitizedActiveGroupID = activeGroupID.flatMap {
            validGroupIDs.contains($0) ? $0 : nil
        }

        let trimmedDefaultGroupName = defaultGroupPresentation.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedDefaultGroup = DefaultWebAppGroupPresentation(
            name: trimmedDefaultGroupName.isEmpty
                ? DefaultWebAppGroupPresentation.defaultName
                : trimmedDefaultGroupName,
            borderTheme: defaultGroupPresentation.borderTheme,
            customBorderColorHex: defaultGroupPresentation.customBorderColorHex
        )

        let sanitizedProfiles = profiles.compactMap { profile -> WebAppProfile? in
            guard WebAppURL.isSafe(profile.homeURL) else {
                return nil
            }
            var sanitized = profile
            if let currentURL = profile.currentURL, !WebAppURL.isSafe(currentURL) {
                sanitized.currentURL = nil
            }
            if let groupID = profile.groupID, !validGroupIDs.contains(groupID) {
                sanitized.groupID = nil
            }
            return sanitized
        }

        let coreState = StoredWebAppState(
            version: StoredWebAppState.currentVersion,
            browserProfiles: browserProfiles,
            defaultBrowserProfilePresentation: defaultBrowserProfilePresentation,
            isDefaultBrowserProfileDeleted: effectiveDefaultDeleted,
            profiles: sanitizedProfiles,
            lastActiveTabID: lastActiveTabID,
            defaultGroupPresentation: sanitizedDefaultGroup,
            groups: sanitizedGroups,
            activeGroupID: sanitizedActiveGroupID,
            bookmarkFolders: [],
            bookmarks: []
        )
        try BrowserProfileValidation.validate(
            browserProfiles: coreState.browserProfiles,
            defaultDisplayName: coreState.defaultBrowserProfilePresentation.name,
            includeDefaultProfile: !coreState.isDefaultBrowserProfileDeleted,
            slots: coreState.profiles
        )
        return coreState
    }

    static func sanitizedBookmarks(
        folders: [BookmarkFolder],
        bookmarks: [BookmarkItem],
        validBrowserProfileIDs: Set<UUID>
    ) -> (folders: [BookmarkFolder], bookmarks: [BookmarkItem]) {
        var seenFolderIDs = Set<UUID>()
        var rawSanitizedFolders: [BookmarkFolder] = folders
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.createdAt < $1.createdAt
            }
            .compactMap { folder -> BookmarkFolder? in
                let trimmed = folder.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, seenFolderIDs.insert(folder.id).inserted else {
                    return nil
                }
                var updated = folder
                updated.name = trimmed
                return updated
            }
            .enumerated()
            .map { index, folder in
                var reordered = folder
                reordered.order = index
                return reordered
            }

        let validFolderIDs = Set(rawSanitizedFolders.map(\.id))
        var parentByFolderID: [UUID: UUID?] = [:]
        for index in rawSanitizedFolders.indices {
            let folderID = rawSanitizedFolders[index].id
            if let parentID = rawSanitizedFolders[index].parentFolderID,
               parentID != folderID,
               validFolderIDs.contains(parentID) {
                parentByFolderID[folderID] = parentID
            } else {
                rawSanitizedFolders[index].parentFolderID = nil
                parentByFolderID[folderID] = nil
            }
        }
        // Break any parent cycles cleanly back to root.
        let sanitizedBookmarkFolders: [BookmarkFolder] = rawSanitizedFolders.map { folder in
            var copy = folder
            var visited: Set<UUID> = [folder.id]
            var cursor = folder.parentFolderID
            while let current = cursor {
                if !visited.insert(current).inserted {
                    copy.parentFolderID = nil
                    break
                }
                cursor = parentByFolderID[current] ?? nil
            }
            return copy
        }

        var seenBookmarkIDs = Set<UUID>()
        let sanitizedBookmarks: [BookmarkItem] = bookmarks
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.createdAt < $1.createdAt
            }
            .compactMap { bookmark -> BookmarkItem? in
                guard WebAppURL.isSafe(bookmark.url),
                      seenBookmarkIDs.insert(bookmark.id).inserted else {
                    return nil
                }
                var updated = bookmark
                let trimmedTitle = bookmark.title.trimmingCharacters(in: .whitespacesAndNewlines)
                updated.title = trimmedTitle.isEmpty
                    ? WebAppURL.defaultDisplayName(for: bookmark.url)
                    : trimmedTitle
                if let folderID = bookmark.folderID, !validFolderIDs.contains(folderID) {
                    updated.folderID = nil
                }
                if let browserProfileID = bookmark.browserProfileID,
                   !validBrowserProfileIDs.contains(browserProfileID) {
                    updated.browserProfileID = nil
                }
                return updated
            }
            .enumerated()
            .map { index, bookmark in
                var reordered = bookmark
                reordered.order = index
                return reordered
            }

        return (sanitizedBookmarkFolders, sanitizedBookmarks)
    }

    func sanitizedForUse() throws -> StoredWebAppState {
        var sanitized = try sanitizedCoreStateForUse()
        let validBrowserProfileIDs = Set(sanitized.browserProfiles.map(\.id))
        let sanitizedBookmarks = Self.sanitizedBookmarks(
            folders: bookmarkFolders,
            bookmarks: bookmarks,
            validBrowserProfileIDs: validBrowserProfileIDs
        )
        sanitized.bookmarkFolders = sanitizedBookmarks.folders
        sanitized.bookmarks = sanitizedBookmarks.bookmarks
        return sanitized
    }
}
