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
                customBorderColorHex: "#123456FF"
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
}
