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
                isTabRailCollapsed: true,
                menuBarDisplayMode: .iconOnly
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
        XCTAssertEqual(decoded.globalPreferences.menuBarDisplayMode, .iconOnly)
        XCTAssertEqual(decoded.globalShowHideShortcut?.carbonKeyCode, 50)
    }

    func testBackupDocumentRoundTripsIconAndNameMenuBarPreference() throws {
        let document = FloatTabsBackupDocument(
            schemaVersion: FloatTabsBackupDocument.currentSchemaVersion,
            createdAt: Date(timeIntervalSince1970: 300),
            sourceAppVersion: "0.1.0",
            sourceBuild: "1",
            webAppState: .empty,
            globalPreferences: FloatTabsBackupPreferences(
                appearanceMode: .system,
                followPreferredSize: true,
                menuBarDisplayMode: .iconAndName
            ),
            globalShowHideShortcut: nil
        )

        let service = FloatTabsBackupService()
        let decoded = try service.decode(service.encode(document))

        XCTAssertEqual(decoded.globalPreferences.menuBarDisplayMode, .iconAndName)
        XCTAssertEqual(FloatTabsBackupDocument.currentSchemaVersion, 1)
    }

    func testOldBackupWithoutMenuBarDisplayModeDecodesAndResolvesHistoricalDefault() throws {
        let document = FloatTabsBackupDocument(
            schemaVersion: FloatTabsBackupDocument.currentSchemaVersion,
            createdAt: Date(timeIntervalSince1970: 300),
            sourceAppVersion: "0.1.0",
            sourceBuild: "1",
            webAppState: .empty,
            globalPreferences: FloatTabsBackupPreferences(
                appearanceMode: .system,
                followPreferredSize: true,
                menuBarDisplayMode: .iconOnly
            ),
            globalShowHideShortcut: nil
        )
        let service = FloatTabsBackupService()
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: service.encode(document))
                as? [String: Any]
        )
        var preferences = try XCTUnwrap(object["globalPreferences"] as? [String: Any])
        preferences.removeValue(forKey: "menuBarDisplayMode")
        var oldObject = object
        oldObject["globalPreferences"] = preferences
        let oldData = try JSONSerialization.data(withJSONObject: oldObject)

        let decoded = try service.decode(oldData)

        XCTAssertNil(decoded.globalPreferences.menuBarDisplayMode)
        XCTAssertEqual(
            decoded.globalPreferences.resolvedMenuBarDisplayMode,
            .iconAndName
        )
    }

    func testNewIconOnlyBackupDecodesWithoutAttentionState() throws {
        let document = FloatTabsBackupDocument(
            schemaVersion: FloatTabsBackupDocument.currentSchemaVersion,
            createdAt: Date(),
            sourceAppVersion: "0.1.0",
            sourceBuild: "1",
            webAppState: .empty,
            globalPreferences: FloatTabsBackupPreferences(
                appearanceMode: .system,
                followPreferredSize: true,
                menuBarDisplayMode: .iconOnly
            ),
            globalShowHideShortcut: nil
        )
        let service = FloatTabsBackupService()
        let data = try service.encode(document)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertEqual(
            try service.decode(data).globalPreferences.resolvedMenuBarDisplayMode,
            .iconOnly
        )
        XCTAssertFalse(json.localizedCaseInsensitiveContains("ready"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("generating"))
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
}
