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
        let markerURL = root.appendingPathComponent(
            FloatTabsBackupService.startupRecoverySnapshotPreservationMarkerFileName
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = ProfileRepository(fileURL: profileURL)
        let service = FloatTabsBackupService(backupDirectoryURL: backupDirectory)
        let knownGoodProfile = WebAppProfile(
            order: 0,
            name: "Known Good",
            homeURL: URL(string: "https://example.com/good")!
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
            homeURL: URL(string: "https://example.com/rebuilt")!
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
}
