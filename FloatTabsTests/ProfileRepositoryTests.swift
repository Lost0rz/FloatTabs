import Foundation
import XCTest
@testable import FloatTabs

@MainActor
final class ProfileRepositoryTests: XCTestCase {
    func testProfilesActiveIDAndCurrentURLRoundTrip() throws {
        try withRepository { repository, _ in
            let id = UUID()
            let profile = WebAppProfile(
                id: id,
                order: 0,
                name: "Docs",
                homeURL: URL(string: "https://example.com")!,
                currentURL: URL(string: "https://example.com/current")!,
                residencyPolicy: .hot,
                backgroundMediaPolicy: .allowBackgroundAudio,
                createdAt: Date(timeIntervalSince1970: 100),
                lastUsedAt: Date(timeIntervalSince1970: 200)
            )
            let state = StoredWebAppState(
                version: StoredWebAppState.currentVersion,
                profiles: [profile],
                lastActiveTabID: id
            )

            try repository.save(state)
            let restored = try repository.load()

            XCTAssertEqual(restored, state)
            XCTAssertEqual(restored.profiles.first?.currentURL, profile.currentURL)
            XCTAssertEqual(restored.profiles.first?.residencyPolicy, .hot)
            XCTAssertEqual(restored.profiles.first?.backgroundMediaPolicy, .allowBackgroundAudio)
            XCTAssertEqual(restored.lastActiveTabID, id)
        }
    }

    func testLegacyStage3StoredProfileMigratesThroughRepository() throws {
        try withRepository { repository, fileURL in
            let id = UUID()
            let json = """
            {
              "version": 1,
              "profiles": [
                {
                  "id": "\(id.uuidString)",
                  "order": 0,
                  "name": "Legacy",
                  "homeURL": "https://example.com",
                  "currentURL": "https://example.com/current",
                  "renderingProfile": {
                    "browserCompatibility": "chrome",
                    "contentMode": "mobile",
                    "viewportWidth": 390,
                    "viewportHeight": 780,
                    "zoom": 1.25
                  },
                  "createdAt": "2026-08-08T00:00:00Z",
                  "lastUsedAt": "2026-08-08T00:00:01Z"
                }
              ],
              "lastActiveTabID": "\(id.uuidString)"
            }
            """
            try Data(json.utf8).write(to: fileURL, options: [.atomic])

            let restored = try repository.load()
            let profile = try XCTUnwrap(restored.profiles.first)
            XCTAssertEqual(profile.id, id)
            XCTAssertEqual(profile.currentURL, URL(string: "https://example.com/current"))
            XCTAssertEqual(profile.renderingProfile.websiteMode, .mobile)
            XCTAssertEqual(profile.renderingProfile.browserIdentity, .iphoneChrome)
            // Legacy records without a named preset keep their exact old
            // geometry instead of being silently reinterpreted as the new Small.
            XCTAssertEqual(profile.renderingProfile.sizePreset, .custom)
            XCTAssertEqual(profile.renderingProfile.viewportSize, CGSize(width: 390, height: 780))
            XCTAssertEqual(profile.renderingProfile.zoom, 1.0, accuracy: 0.001)
            XCTAssertEqual(profile.residencyPolicy, .warm)
            XCTAssertEqual(profile.backgroundMediaPolicy, .pauseWhenInactive)
        }
    }

    func testCorruptMetadataFailsSafelyAndTabStoreStartsEmpty() throws {
        try withRepository { repository, fileURL in
            try Data("{ definitely-not-json".utf8).write(to: fileURL, options: [.atomic])

            XCTAssertThrowsError(try repository.load())
            XCTAssertTrue(repository.startupRecoveryRequired)

            let store = TabStore(repository: repository)
            XCTAssertTrue(store.profiles.isEmpty)
            XCTAssertNil(store.activeTabID)
            XCTAssertTrue(repository.startupRecoveryRequired)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        }
    }

    func testPreservingUnreadableStoreDoesNotAuthorizeOrdinaryEmptySave() throws {
        try withRepository { repository, fileURL in
            let original = Data("{ broken-but-important-profile-data".utf8)
            try original.write(to: fileURL, options: [.atomic])

            XCTAssertThrowsError(try repository.load())
            XCTAssertTrue(repository.startupRecoveryRequired)

            XCTAssertThrowsError(try repository.save(.empty)) { error in
                XCTAssertEqual(error as? ProfileRepositoryError, .startupRecoveryRequired)
            }
            XCTAssertEqual(try Data(contentsOf: fileURL), original)

            let archiveURL = try XCTUnwrap(
                repository.preserveUnreadableStoreForRecovery(
                    now: Date(timeIntervalSince1970: 1_700_000_000)
                )
            )
            XCTAssertTrue(archiveURL.lastPathComponent.hasPrefix("WebAppProfiles-recovery-"))
            XCTAssertEqual(try Data(contentsOf: archiveURL), original)
            XCTAssertEqual(repository.startupRecoveryArchiveURL, archiveURL)

            XCTAssertThrowsError(try repository.save(.empty)) { error in
                XCTAssertEqual(error as? ProfileRepositoryError, .startupRecoveryRequired)
            }

            XCTAssertTrue(repository.startupRecoveryRequired)
            XCTAssertEqual(try Data(contentsOf: fileURL), original)
            XCTAssertEqual(try Data(contentsOf: archiveURL), original)
        }
    }

    func testExplicitStartupRecoveryStartEmptyReplacementWritesOnceAndKeepsArchive() throws {
        try withRepository { repository, fileURL in
            let original = Data("{ broken-but-important-profile-data".utf8)
            try original.write(to: fileURL, options: [.atomic])

            XCTAssertThrowsError(try repository.load())
            let archiveURL = try XCTUnwrap(
                repository.preserveUnreadableStoreForRecovery(
                    now: Date(timeIntervalSince1970: 1_700_000_000)
                )
            )

            try repository.performStartupRecoveryReplacement {
                try repository.save(.empty)
            }

            XCTAssertFalse(repository.startupRecoveryRequired)
            let replacement = try decodePersistedState(from: fileURL)
            XCTAssertEqual(replacement, .empty)
            XCTAssertEqual(try Data(contentsOf: archiveURL), original)
        }
    }

    func testExplicitStartupRecoveryRestoreReplacementPreservesOriginalBytes() throws {
        try withRepository { repository, fileURL in
            let original = Data("{ broken-but-important-profile-data".utf8)
            try original.write(to: fileURL, options: [.atomic])

            XCTAssertThrowsError(try repository.load())
            let archiveURL = try XCTUnwrap(
                repository.preserveUnreadableStoreForRecovery(
                    now: Date(timeIntervalSince1970: 1_700_000_000)
                )
            )
            let restoredProfile = WebAppProfile(
                order: 0,
                name: "Restored",
                homeURL: URL(string: "https://example.com/restored")!,
                createdAt: Date(timeIntervalSince1970: 100),
                lastUsedAt: Date(timeIntervalSince1970: 200)
            )
            let restoredState = StoredWebAppState(
                version: StoredWebAppState.currentVersion,
                profiles: [restoredProfile],
                lastActiveTabID: restoredProfile.id
            )

            try repository.performStartupRecoveryReplacement {
                try repository.save(restoredState)
            }

            XCTAssertFalse(repository.startupRecoveryRequired)
            let replacement = try decodePersistedState(from: fileURL)
            XCTAssertEqual(replacement, restoredState)
            XCTAssertEqual(try Data(contentsOf: archiveURL), original)
        }
    }

    func testFailedStartupRecoveryReplacementKeepsWriteLockAndBytesRecoverable() throws {
        try withRepository { repository, fileURL in
            let original = Data("{ broken-but-important-profile-data".utf8)
            try original.write(to: fileURL, options: [.atomic])

            XCTAssertThrowsError(try repository.load())
            let archiveURL = try XCTUnwrap(
                repository.preserveUnreadableStoreForRecovery(
                    now: Date(timeIntervalSince1970: 1_700_000_000)
                )
            )

            XCTAssertThrowsError(
                try repository.performStartupRecoveryReplacement {
                    try repository.save(
                        StoredWebAppState(
                            version: 99,
                            profiles: [],
                            lastActiveTabID: nil
                        )
                    )
                }
            ) { error in
                XCTAssertEqual(error as? ProfileRepositoryError, .unsupportedVersion(99))
            }

            XCTAssertTrue(repository.startupRecoveryRequired)
            XCTAssertThrowsError(try repository.save(.empty)) { error in
                XCTAssertEqual(error as? ProfileRepositoryError, .startupRecoveryRequired)
            }
            XCTAssertEqual(try Data(contentsOf: fileURL), original)
            XCTAssertEqual(try Data(contentsOf: archiveURL), original)
        }
    }

    func testFailedStartupLoadCannotBeSilentlyOverwrittenByTabMutation() throws {
        try withRepository { repository, fileURL in
            let original = Data("not-json".utf8)
            try original.write(to: fileURL, options: [.atomic])
            let store = TabStore(repository: repository)
            var failureCount = 0
            store.onPersistenceFailure = { failureCount += 1 }

            XCTAssertTrue(repository.startupRecoveryRequired)
            XCTAssertNil(
                store.add(
                    name: "Should Not Replace Corrupt Store",
                    homeURL: URL(string: "https://example.com")!
                )
            )

            XCTAssertTrue(store.profiles.isEmpty)
            XCTAssertEqual(failureCount, 1)
            XCTAssertEqual(try Data(contentsOf: fileURL), original)
        }
    }

    func testInvalidCurrentURLIsDroppedWithoutDroppingValidProfile() throws {
        try withRepository { repository, _ in
            var profile = WebAppProfile(
                order: 0,
                name: "Safe",
                homeURL: URL(string: "https://example.com")!,
                currentURL: URL(string: "file:///tmp/secret")!
            )
            profile.currentURL = URL(string: "file:///tmp/secret")
            try repository.save(
                StoredWebAppState(
                    version: StoredWebAppState.currentVersion,
                    profiles: [profile],
                    lastActiveTabID: profile.id
                )
            )

            let restored = try repository.load()
            XCTAssertEqual(restored.profiles.count, 1)
            XCTAssertNil(restored.profiles[0].currentURL)
        }
    }

    func testRelaunchRestoresOrderActiveSlotAndCurrentURL() throws {
        try withRepository { firstRepository, fileURL in
            let firstStore = TabStore(repository: firstRepository)
            let a = firstStore.add(name: "A", homeURL: URL(string: "https://example.com/a")!)!
            let b = firstStore.add(name: "B", homeURL: URL(string: "https://example.com/b")!)!
            let c = firstStore.add(name: "C", homeURL: URL(string: "https://example.com/c")!)!

            _ = firstStore.move(id: c.id, toIndex: 0)
            _ = firstStore.select(id: a.id)
            let current = URL(string: "https://example.com/a/deeper")!
            firstStore.updateCurrentURL(id: a.id, url: current)

            let secondStore = TabStore(repository: ProfileRepository(fileURL: fileURL))

            XCTAssertEqual(secondStore.orderedProfiles.map(\.id), [c.id, a.id, b.id])
            XCTAssertEqual(secondStore.activeTabID, a.id)
            XCTAssertEqual(secondStore.profiles.first(where: { $0.id == a.id })?.currentURL, current)
        }
    }

    private func withRepository(
        _ body: (ProfileRepository, URL) throws -> Void
    ) throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsProfileRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("WebAppProfiles.json")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        try body(ProfileRepository(fileURL: fileURL), fileURL)
    }

    private func decodePersistedState(from fileURL: URL) throws -> StoredWebAppState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            StoredWebAppState.self,
            from: Data(contentsOf: fileURL)
        )
    }
}

private enum TestProfilePersistenceError: Error {
    case forcedFailure
}

private final class FailingProfileRepository: ProfileRepositoryProtocol {
    var state: StoredWebAppState
    var shouldFailSaves = false
    private(set) var saveAttempts = 0

    init(state: StoredWebAppState = .empty) {
        self.state = state
    }

    func load() throws -> StoredWebAppState {
        state
    }

    func save(_ state: StoredWebAppState) throws {
        saveAttempts += 1
        if shouldFailSaves {
            throw TestProfilePersistenceError.forcedFailure
        }
        self.state = state
    }
}

@MainActor
final class TabStorePersistenceFailureTests: XCTestCase {
    private let urlA = URL(string: "https://example.com/a")!
    private let urlB = URL(string: "https://example.com/b")!

    func testConfigurationSaveFailureRollsBackModelAndReportsOnce() throws {
        let repository = FailingProfileRepository()
        let store = TabStore(repository: repository)
        let profile = try XCTUnwrap(store.add(name: "A", homeURL: urlA))
        let durableBefore = repository.state
        var changeCount = 0
        var failureCount = 0
        store.onChange = { changeCount += 1 }
        store.onPersistenceFailure = { failureCount += 1 }
        repository.shouldFailSaves = true

        XCTAssertFalse(store.rename(id: profile.id, name: "Renamed"))

        XCTAssertEqual(store.profiles.first?.name, "A")
        XCTAssertEqual(repository.state, durableBefore)
        XCTAssertEqual(changeCount, 0)
        XCTAssertEqual(failureCount, 1)
    }

    func testFailedAddAndRemoveLeaveIdentityAndSelectionUntouched() throws {
        let repository = FailingProfileRepository()
        let store = TabStore(repository: repository)
        let original = try XCTUnwrap(store.add(name: "A", homeURL: urlA))
        let durableBefore = repository.state
        var failureCount = 0
        store.onPersistenceFailure = { failureCount += 1 }
        repository.shouldFailSaves = true

        XCTAssertNil(store.add(name: "B", homeURL: urlB))
        XCTAssertFalse(store.remove(id: original.id))

        XCTAssertEqual(store.profiles.map(\.id), [original.id])
        XCTAssertEqual(store.activeTabID, original.id)
        XCTAssertEqual(repository.state, durableBefore)
        XCTAssertEqual(failureCount, 2)
    }

    func testRuntimeSelectionStaysLiveWhenPersistenceFails() throws {
        let repository = FailingProfileRepository()
        let store = TabStore(repository: repository)
        let first = try XCTUnwrap(store.add(name: "A", homeURL: urlA))
        let second = try XCTUnwrap(store.add(name: "B", homeURL: urlB))
        XCTAssertEqual(store.activeTabID, second.id)
        let durableBefore = repository.state
        var failureCount = 0
        store.onPersistenceFailure = { failureCount += 1 }
        repository.shouldFailSaves = true

        XCTAssertTrue(store.select(id: first.id))

        XCTAssertEqual(store.activeTabID, first.id)
        XCTAssertEqual(repository.state, durableBefore)
        XCTAssertEqual(failureCount, 0)
    }

    func testCurrentURLStaysLiveWhenPersistenceFails() throws {
        let repository = FailingProfileRepository()
        let store = TabStore(repository: repository)
        let profile = try XCTUnwrap(store.add(name: "A", homeURL: urlA))
        let durableBefore = repository.state
        var failureCount = 0
        store.onPersistenceFailure = { failureCount += 1 }
        repository.shouldFailSaves = true

        store.updateCurrentURL(id: profile.id, url: urlB)

        XCTAssertEqual(store.profiles.first?.currentURL, urlB)
        XCTAssertEqual(repository.state, durableBefore)
        XCTAssertEqual(failureCount, 0)
    }

    func testRenderingAndResourceChangesRollbackOnSaveFailure() throws {
        let repository = FailingProfileRepository()
        let store = TabStore(repository: repository)
        let profile = try XCTUnwrap(store.add(name: "A", homeURL: urlA))
        let before = try XCTUnwrap(store.profiles.first)
        repository.shouldFailSaves = true

        XCTAssertFalse(
            store.updateRenderingProfile(
                id: profile.id,
                renderingProfile: before.renderingProfile.settingWebsiteMode(.mobile)
            )
        )
        XCTAssertFalse(
            store.updateResourcePolicy(
                id: profile.id,
                residencyPolicy: .hot,
                backgroundMediaPolicy: .allowBackgroundAudio
            )
        )

        let after = try XCTUnwrap(store.profiles.first)
        XCTAssertEqual(after.renderingProfile, before.renderingProfile)
        XCTAssertEqual(after.residencyPolicy, before.residencyPolicy)
        XCTAssertEqual(after.backgroundMediaPolicy, before.backgroundMediaPolicy)
    }
}
