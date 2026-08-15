import Foundation
import XCTest
@testable import FloatTabs

final class FloatTabsBackupServiceTests: XCTestCase {
    func testBackupDocumentRoundTripsAllFloatTabsOwnedConfiguration() throws {
        let profile = WebAppProfile(
            order: 3,
            name: "Docs",
            homeURL: URL(string: "https://example.com")!,
            currentURL: URL(string: "https://example.com/current")!,
            renderingProfile: WebRenderingProfile.canonicalDefault
                .settingWebsiteMode(.mobile)
                .settingBrowserIdentity(.windowsChrome)
                .settingViewport(CGSize(width: 612, height: 777))
                .settingZoom(1.5),
            residencyPolicy: .hot,
            backgroundMediaPolicy: .allowBackgroundAudio,
            createdAt: Date(timeIntervalSince1970: 100),
            lastUsedAt: Date(timeIntervalSince1970: 200)
        )
        let document = FloatTabsBackupDocument(
            schemaVersion: FloatTabsBackupDocument.currentSchemaVersion,
            createdAt: Date(timeIntervalSince1970: 300),
            sourceAppVersion: "0.1.0",
            sourceBuild: "1",
            webAppState: StoredWebAppState(
                version: StoredWebAppState.currentVersion,
                profiles: [profile],
                lastActiveTabID: profile.id
            ),
            globalPreferences: FloatTabsBackupPreferences(
                appearanceMode: .dark,
                followPreferredSize: false,
                borderTheme: .green,
                customBorderColorHex: "#123456FF",
                isTabRailCollapsed: true
            ),
            globalShowHideShortcut: FloatTabsBackupShortcut(
                carbonKeyCode: 50,
                carbonModifiers: 256
            )
        )
        let service = FloatTabsBackupService()

        let decoded = try service.decode(service.encode(document))

        XCTAssertEqual(decoded, document)
        XCTAssertEqual(decoded.webAppState.profiles.first?.renderingProfile.zoom, 1.5)
        XCTAssertEqual(decoded.webAppState.profiles.first?.residencyPolicy, .hot)
        XCTAssertEqual(decoded.webAppState.profiles.first?.backgroundMediaPolicy, .allowBackgroundAudio)
        XCTAssertEqual(decoded.globalPreferences.appearanceMode, .dark)
        XCTAssertFalse(decoded.globalPreferences.followPreferredSize)
        XCTAssertEqual(decoded.globalPreferences.borderTheme, .green)
        XCTAssertEqual(decoded.globalPreferences.customBorderColorHex, "#123456FF")
        XCTAssertEqual(decoded.globalPreferences.isTabRailCollapsed, true)
        XCTAssertEqual(decoded.globalShowHideShortcut?.carbonKeyCode, 50)
    }

    func testUnsupportedBackupSchemaIsRejected() throws {
        let document = FloatTabsBackupDocument(
            schemaVersion: 99,
            createdAt: Date(),
            sourceAppVersion: "0.1.0",
            sourceBuild: "1",
            webAppState: .empty,
            globalPreferences: FloatTabsBackupPreferences(
                appearanceMode: .system,
                followPreferredSize: true
            ),
            globalShowHideShortcut: nil
        )
        let service = FloatTabsBackupService()
        let data = try service.encode(document)

        XCTAssertThrowsError(try service.decode(data)) { error in
            XCTAssertEqual(error as? FloatTabsBackupError, .unsupportedSchema(99))
        }
    }

    func testRollbackAndAutomaticVersionSnapshotsUseSeparateLocalFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsBackupServiceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = FloatTabsBackupService(backupDirectoryURL: directory)
        let document = FloatTabsBackupDocument(
            schemaVersion: FloatTabsBackupDocument.currentSchemaVersion,
            createdAt: Date(timeIntervalSince1970: 100),
            sourceAppVersion: "0.1.0",
            sourceBuild: "1",
            webAppState: .empty,
            globalPreferences: FloatTabsBackupPreferences(
                appearanceMode: .system,
                followPreferredSize: true
            ),
            globalShowHideShortcut: nil
        )

        let automatic = try service.writeAutomaticVersionSnapshot(document)
        let rollback = try service.writeRollback(
            document,
            now: Date(timeIntervalSince1970: 200)
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: automatic.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rollback.path))
        XCTAssertTrue(automatic.lastPathComponent.hasPrefix("FloatTabs-auto-0.1.0-1"))
        XCTAssertTrue(rollback.lastPathComponent.hasPrefix("FloatTabs-before-restore-"))
        XCTAssertEqual(try service.load(from: automatic), document)
    }

    func testLatestValidAutomaticSnapshotSkipsCorruptAndRollbackFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsBackupRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = FloatTabsBackupService(backupDirectoryURL: directory)

        func document(version: String, build: String, createdAt: TimeInterval) -> FloatTabsBackupDocument {
            FloatTabsBackupDocument(
                schemaVersion: FloatTabsBackupDocument.currentSchemaVersion,
                createdAt: Date(timeIntervalSince1970: createdAt),
                sourceAppVersion: version,
                sourceBuild: build,
                webAppState: .empty,
                globalPreferences: FloatTabsBackupPreferences(
                    appearanceMode: .system,
                    followPreferredSize: true
                ),
                globalShowHideShortcut: nil
            )
        }

        let older = document(version: "0.1.0", build: "1", createdAt: 100)
        let newest = document(version: "0.1.1", build: "2", createdAt: 300)
        let rollbackOnly = document(version: "0.1.2", build: "3", createdAt: 900)
        _ = try service.writeAutomaticVersionSnapshot(older)
        let newestURL = try service.writeAutomaticVersionSnapshot(newest)
        _ = try service.writeRollback(rollbackOnly, now: Date(timeIntervalSince1970: 900))

        let corruptURL = directory.appendingPathComponent(
            "FloatTabs-auto-corrupt-999.\(FloatTabsBackupService.fileExtension)"
        )
        try Data("not a backup".utf8).write(to: corruptURL, options: [.atomic])

        let latest = try XCTUnwrap(service.latestValidAutomaticSnapshot())
        XCTAssertEqual(
            latest.url.resolvingSymlinksInPath(),
            newestURL.resolvingSymlinksInPath()
        )
        XCTAssertEqual(latest.document, newest)
    }

    func testEmptyStartupRecoveryPreservesAutomaticBackupUntilConfigurationExists() {
        XCTAssertFalse(
            AppCoordinator.shouldWriteAutomaticVersionSnapshot(
                startupRecoveryRequired: true,
                preserveExistingAutomaticBackupAfterEmptyStartupRecovery: false,
                webAppState: .empty
            )
        )
        XCTAssertFalse(
            AppCoordinator.shouldWriteAutomaticVersionSnapshot(
                startupRecoveryRequired: false,
                preserveExistingAutomaticBackupAfterEmptyStartupRecovery: true,
                webAppState: .empty
            )
        )
        XCTAssertTrue(
            AppCoordinator.shouldWriteAutomaticVersionSnapshot(
                startupRecoveryRequired: false,
                preserveExistingAutomaticBackupAfterEmptyStartupRecovery: false,
                webAppState: .empty
            )
        )

        let profile = WebAppProfile(
            order: 0,
            name: "Recovered",
            homeURL: URL(string: "https://example.com")!
        )
        let recoveredState = StoredWebAppState(
            version: StoredWebAppState.currentVersion,
            profiles: [profile],
            lastActiveTabID: profile.id
        )
        XCTAssertTrue(
            AppCoordinator.shouldWriteAutomaticVersionSnapshot(
                startupRecoveryRequired: false,
                preserveExistingAutomaticBackupAfterEmptyStartupRecovery: true,
                webAppState: recoveredState
            )
        )
    }

    func testRecoverySnapshotProtectionSurvivesRelaunchUntilNonEmptyConfigurationExists() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsPersistentRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        let profileURL = root.appendingPathComponent("WebAppProfiles.json")
        let backupDirectory = root.appendingPathComponent("Backups", isDirectory: true)
        let markerURL = backupDirectory.appendingPathComponent(
            FloatTabsBackupService.startupRecoverySnapshotPreservationMarkerFileName
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = ProfileRepository(fileURL: profileURL)
        let service = FloatTabsBackupService(backupDirectoryURL: backupDirectory)
        let knownGoodProfile = WebAppProfile(
            order: 0,
            name: "Known Good",
            homeURL: URL(string: "https://example.com/good")!,
            // Pin profile timestamps to whole seconds. The backup encoder uses
            // ISO8601 dates, which truncate sub-second precision, so comparing
            // a decoded document against one built from `Date()` defaults can
            // never compare equal even though both debug descriptions match.
            createdAt: Date(timeIntervalSince1970: 10),
            lastUsedAt: Date(timeIntervalSince1970: 10)
        )
        let knownGoodState = StoredWebAppState(
            version: StoredWebAppState.currentVersion,
            profiles: [knownGoodProfile],
            lastActiveTabID: knownGoodProfile.id
        )

        func document(state: StoredWebAppState, createdAt: TimeInterval) -> FloatTabsBackupDocument {
            FloatTabsBackupDocument(
                schemaVersion: FloatTabsBackupDocument.currentSchemaVersion,
                createdAt: Date(timeIntervalSince1970: createdAt),
                sourceAppVersion: "0.1.1",
                sourceBuild: "2",
                webAppState: state,
                globalPreferences: FloatTabsBackupPreferences(
                    appearanceMode: .system,
                    followPreferredSize: true
                ),
                globalShowHideShortcut: nil
            )
        }

        let knownGoodDocument = document(state: knownGoodState, createdAt: 100)
        let automaticURL = try service.writeAutomaticVersionSnapshot(knownGoodDocument)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("broken-profile-store".utf8).write(to: profileURL, options: [.atomic])
        XCTAssertThrowsError(try repository.load())
        _ = try repository.preserveUnreadableStoreForRecovery(
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        // Preserving corrupt bytes alone must not broaden the snapshot policy.
        // Only the explicit Start Empty path arms durable backup protection.
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
        try service.beginEmptyStartupRecoverySnapshotPreservation()
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path))
        try repository.save(.empty)

        let emptyDocument = document(state: .empty, createdAt: 200)
        _ = try service.writeAutomaticVersionSnapshot(emptyDocument)
        XCTAssertEqual(try service.load(from: automaticURL), knownGoodDocument)

        // A fresh service instance models the next app launch. The on-disk
        // marker, rather than AppCoordinator process memory, must keep the same
        // automatic snapshot protected while configuration is still empty.
        let relaunchedService = FloatTabsBackupService(backupDirectoryURL: backupDirectory)
        _ = try relaunchedService.writeAutomaticVersionSnapshot(
            document(state: .empty, createdAt: 300)
        )
        XCTAssertEqual(try relaunchedService.load(from: automaticURL), knownGoodDocument)

        let rebuiltProfile = WebAppProfile(
            order: 0,
            name: "Rebuilt",
            homeURL: URL(string: "https://example.com/rebuilt")!,
            // Same whole-second pinning as above: this document is compared in
            // decoded form after being committed through the ISO8601 encoder.
            createdAt: Date(timeIntervalSince1970: 20),
            lastUsedAt: Date(timeIntervalSince1970: 20)
        )
        let rebuiltState = StoredWebAppState(
            version: StoredWebAppState.currentVersion,
            profiles: [rebuiltProfile],
            lastActiveTabID: rebuiltProfile.id
        )
        let rebuiltDocument = document(state: rebuiltState, createdAt: 400)
        _ = try relaunchedService.writeAutomaticVersionSnapshot(rebuiltDocument)
        XCTAssertEqual(try relaunchedService.load(from: automaticURL), rebuiltDocument)
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))

        // Once a real configuration has been committed, normal automatic
        // snapshot behavior resumes; a later intentional empty state is valid.
        let laterEmptyDocument = document(state: .empty, createdAt: 500)
        _ = try relaunchedService.writeAutomaticVersionSnapshot(laterEmptyDocument)
        XCTAssertEqual(try relaunchedService.load(from: automaticURL), laterEmptyDocument)
    }

    // MARK: - Start Empty preservation marker contract

    private func makeMarkerTestService(
        root: URL
    ) throws -> (service: FloatTabsBackupService, directory: URL, markerURL: URL) {
        let directory = root.appendingPathComponent("Backups", isDirectory: true)
        let markerURL = directory.appendingPathComponent(
            FloatTabsBackupService.startupRecoverySnapshotPreservationMarkerFileName
        )
        return (FloatTabsBackupService(backupDirectoryURL: directory), directory, markerURL)
    }

    private func makeMarkerTestDocument(
        state: StoredWebAppState = .empty,
        createdAt: TimeInterval
    ) -> FloatTabsBackupDocument {
        FloatTabsBackupDocument(
            schemaVersion: FloatTabsBackupDocument.currentSchemaVersion,
            createdAt: Date(timeIntervalSince1970: createdAt),
            sourceAppVersion: "0.1.1",
            sourceBuild: "2",
            webAppState: state,
            globalPreferences: FloatTabsBackupPreferences(
                appearanceMode: .system,
                followPreferredSize: true
            ),
            globalShowHideShortcut: nil
        )
    }

    /// Spec: marker creation must fail loudly instead of silently proceeding
    /// with an unprotected Start Empty. A directory occupying the marker path
    /// makes the atomic marker write throw.
    func testFailedMarkerCreationThrowsInsteadOfArmingSilently() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsMarkerFailureTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, _, markerURL) = try makeMarkerTestService(root: root)
        try FileManager.default.createDirectory(at: markerURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try makeMarkerTestService(root: root).service
                .beginEmptyStartupRecoverySnapshotPreservation()
        )
    }

    /// Spec: the marker is a hidden file inside the (possibly custom) backup
    /// directory and must never surface as a backup during enumeration.
    func testPreservationMarkerIsHiddenAndExcludedFromBackupEnumeration() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsMarkerEnumerationTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let (service, directory, markerURL) = try makeMarkerTestService(root: root)

        let snapshotURL = try service.writeAutomaticVersionSnapshot(
            makeMarkerTestDocument(state: .empty, createdAt: 100)
        )
        // Arm after the known-good snapshot exists, mirroring Start Empty.
        try service.beginEmptyStartupRecoverySnapshotPreservation()
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path))

        let listed = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        XCTAssertFalse(listed.contains { $0 == markerURL })
        let latest = try XCTUnwrap(service.latestValidAutomaticSnapshot())
        XCTAssertEqual(latest.url.lastPathComponent, snapshotURL.lastPathComponent)
    }

    /// Spec: a non-empty automatic snapshot commit failure must leave the
    /// marker armed so a later empty state still cannot erase the last valid
    /// recovery snapshot.
    func testFailedNonEmptySnapshotCommitKeepsPreservationMarkerArmed() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsMarkerWriteFailureTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let (service, _, markerURL) = try makeMarkerTestService(root: root)
        try service.beginEmptyStartupRecoverySnapshotPreservation()

        let profile = WebAppProfile(
            order: 0,
            name: "Rebuilt",
            homeURL: URL(string: "https://example.com/rebuilt")!,
            createdAt: Date(timeIntervalSince1970: 10),
            lastUsedAt: Date(timeIntervalSince1970: 10)
        )
        let state = StoredWebAppState(
            version: StoredWebAppState.currentVersion,
            profiles: [profile],
            lastActiveTabID: profile.id
        )
        // A directory at the snapshot path makes the atomic data write fail.
        let snapshotPath = markerURL.deletingLastPathComponent()
            .appendingPathComponent("FloatTabs-auto-0.1.1-2.floattabsbackup")
        try FileManager.default.createDirectory(at: snapshotPath, withIntermediateDirectories: true)
        XCTAssertThrowsError(
            try service.writeAutomaticVersionSnapshot(
                makeMarkerTestDocument(state: state, createdAt: 200)
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path))

        // After the failure is resolved, a successful commit clears the marker.
        try FileManager.default.removeItem(at: snapshotPath)
        _ = try service.writeAutomaticVersionSnapshot(
            makeMarkerTestDocument(state: state, createdAt: 300)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
    }

    /// Spec: ordinary empty snapshots and restore-related writes must never
    /// arm the preservation marker. Only the explicit Start Empty path arms it.
    func testOrdinaryEmptyAndRestorePathsNeverArmPreservationMarker() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsMarkerScopingTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let (service, _, markerURL) = try makeMarkerTestService(root: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
        let emptyURL = try service.writeAutomaticVersionSnapshot(
            makeMarkerTestDocument(state: .empty, createdAt: 100)
        )
        XCTAssertEqual(
            try service.load(from: emptyURL),
            makeMarkerTestDocument(state: .empty, createdAt: 100)
        )
        _ = try service.writeRollback(
            makeMarkerTestDocument(state: .empty, createdAt: 150),
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        _ = service.latestValidAutomaticSnapshot()
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
    }

    /// Spec: the in-memory Start Empty guard is disarmed only after a
    /// non-empty automatic snapshot was durably committed.
    func testInMemoryGuardDisarmsOnlyAfterCommittedNonEmptySnapshot() {
        let profile = WebAppProfile(
            order: 0,
            name: "Guard",
            homeURL: URL(string: "https://example.com/guard")!,
            createdAt: Date(timeIntervalSince1970: 10),
            lastUsedAt: Date(timeIntervalSince1970: 10)
        )
        let nonEmptyState = StoredWebAppState(
            version: StoredWebAppState.currentVersion,
            profiles: [profile],
            lastActiveTabID: profile.id
        )

        XCTAssertFalse(AppCoordinator.shouldDisarmEmptyStartupRecoveryPreservation(
            preserveExistingAutomaticBackupAfterEmptyStartupRecovery: true,
            webAppState: .empty
        ))
        XCTAssertTrue(AppCoordinator.shouldDisarmEmptyStartupRecoveryPreservation(
            preserveExistingAutomaticBackupAfterEmptyStartupRecovery: true,
            webAppState: nonEmptyState
        ))
        XCTAssertFalse(AppCoordinator.shouldDisarmEmptyStartupRecoveryPreservation(
            preserveExistingAutomaticBackupAfterEmptyStartupRecovery: false,
            webAppState: nonEmptyState
        ))
    }
}
