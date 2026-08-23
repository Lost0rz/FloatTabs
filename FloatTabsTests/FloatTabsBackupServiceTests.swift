import Foundation
import XCTest
@testable import FloatTabs

final class FloatTabsBackupServiceTests: XCTestCase {
    func testBackupDocumentRoundTripsAllFloatTabsOwnedConfiguration() throws {
        let browserProfile = BrowserProfile(
            id: UUID(),
            name: "Company",
            createdAt: Date(timeIntervalSince1970: 50)
        )
        let profile = WebAppProfile(
            browserProfileID: browserProfile.id,
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
                browserProfiles: [browserProfile],
                profiles: [profile],
                lastActiveTabID: profile.id
            ),
            globalPreferences: FloatTabsBackupPreferences(
                appearanceMode: .dark,
                followPreferredSize: false,
                borderTheme: .green,
                customBorderColorHex: "#123456FF",
                isTabRailCollapsed: true,
                menuBarDisplayMode: .iconOnly,
                attentionSoundEnabled: false,
                attentionSoundName: "Glass",
                attentionSoundVolume: 0.35
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
        XCTAssertEqual(decoded.webAppState.browserProfiles, [browserProfile])
        XCTAssertEqual(decoded.webAppState.profiles.first?.browserProfileID, browserProfile.id)
        XCTAssertEqual(decoded.globalPreferences.appearanceMode, .dark)
        XCTAssertFalse(decoded.globalPreferences.followPreferredSize)
        XCTAssertEqual(decoded.globalPreferences.borderTheme, .green)
        XCTAssertEqual(decoded.globalPreferences.customBorderColorHex, "#123456FF")
        XCTAssertEqual(decoded.globalPreferences.isTabRailCollapsed, true)
        XCTAssertEqual(decoded.globalPreferences.menuBarDisplayMode, .iconOnly)
        XCTAssertEqual(decoded.globalPreferences.attentionSoundEnabled, false)
        XCTAssertEqual(decoded.globalPreferences.attentionSoundName, "Glass")
        XCTAssertEqual(decoded.globalPreferences.attentionSoundVolume, 0.35)
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
        XCTAssertEqual(FloatTabsBackupDocument.currentSchemaVersion, 2)
    }

    func testCurrentSchemaBackupWithoutMenuBarDisplayModeResolvesHistoricalDefault() throws {
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

    func testHistoricalSchemaOneBackupWithoutAttentionSoundFieldsMigratesAndUsesNewDefaults() throws {
        let profile = WebAppProfile(
            order: 0,
            name: "Legacy",
            homeURL: URL(string: "https://legacy.example")!,
            currentURL: URL(string: "https://legacy.example/current")!,
            createdAt: Date(timeIntervalSince1970: 100),
            lastUsedAt: Date(timeIntervalSince1970: 200)
        )
        let document = HistoricalBackupDocumentV1(
            schemaVersion: 1,
            createdAt: Date(timeIntervalSince1970: 300),
            sourceAppVersion: "0.1.0",
            sourceBuild: "1",
            webAppState: HistoricalBackupWebAppStateV1(
                version: 1,
                profiles: [profile],
                lastActiveTabID: profile.id
            ),
            globalPreferences: FloatTabsBackupPreferences(
                appearanceMode: .system,
                followPreferredSize: true,
                attentionSoundEnabled: false,
                attentionSoundName: "Glass",
                attentionSoundVolume: 0.35
            ),
            globalShowHideShortcut: nil
        )
        let service = FloatTabsBackupService()
        let legacyEncoder = JSONEncoder()
        legacyEncoder.dateEncodingStrategy = .iso8601
        let encoded = try legacyEncoder.encode(document)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(object["browserProfiles"])
        var legacyState = try XCTUnwrap(object["webAppState"] as? [String: Any])
        XCTAssertNil(legacyState["browserProfiles"])
        var legacyProfiles = try XCTUnwrap(legacyState["profiles"] as? [[String: Any]])
        XCTAssertNil(legacyProfiles.first?["browserProfileID"])
        legacyProfiles[0]["browserProfileID"] = UUID().uuidString
        legacyState["profiles"] = legacyProfiles
        var preferences = try XCTUnwrap(object["globalPreferences"] as? [String: Any])
        preferences.removeValue(forKey: "attentionSoundEnabled")
        preferences.removeValue(forKey: "attentionSoundName")
        preferences.removeValue(forKey: "attentionSoundVolume")
        var oldObject = object
        oldObject["webAppState"] = legacyState
        oldObject["globalPreferences"] = preferences
        let oldData = try JSONSerialization.data(withJSONObject: oldObject)

        let decoded = try service.decode(oldData)

        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertEqual(decoded.webAppState.version, 2)
        XCTAssertEqual(decoded.webAppState.browserProfiles, [])
        XCTAssertEqual(decoded.webAppState.profiles.map { $0.browserProfileID }, [nil])
        XCTAssertEqual(decoded.webAppState.lastActiveTabID, profile.id)
        XCTAssertEqual(decoded.webAppState.profiles.first?.currentURL, profile.currentURL)
        XCTAssertNil(decoded.globalPreferences.attentionSoundEnabled)
        XCTAssertNil(decoded.globalPreferences.attentionSoundName)
        XCTAssertNil(decoded.globalPreferences.attentionSoundVolume)
        XCTAssertTrue(decoded.globalPreferences.resolvedAttentionSoundEnabled)
        XCTAssertEqual(decoded.globalPreferences.resolvedAttentionSoundName, "Ping")
        XCTAssertEqual(decoded.globalPreferences.resolvedAttentionSoundVolume, 1)
    }

    func testSchemaTwoDanglingProfileReferenceIsRejected() throws {
        let declaredProfile = BrowserProfile(
            id: UUID(),
            name: "Company",
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let missingProfileID = UUID()
        let slot = WebAppProfile(
            browserProfileID: missingProfileID,
            order: 0,
            name: "Web App",
            homeURL: URL(string: "https://example.com")!
        )
        let document = makeDocument(
            browserProfiles: [declaredProfile],
            profiles: [slot]
        )

        XCTAssertThrowsError(try FloatTabsBackupService().decode(try encode(document))) { error in
            XCTAssertEqual(
                error as? ProfileRepositoryError,
                .danglingBrowserProfileReference(missingProfileID)
            )
        }
    }

    func testMismatchedAndUnknownSchemaStateVersionsFailClosed() throws {
        let service = FloatTabsBackupService()
        let currentStateDocument = makeDocument()
        let legacyState = StoredWebAppState(
            version: 1,
            profiles: currentStateDocument.webAppState.profiles,
            lastActiveTabID: nil
        )

        let schemaOneStateTwo = FloatTabsBackupDocument(
            schemaVersion: 1,
            createdAt: currentStateDocument.createdAt,
            sourceAppVersion: currentStateDocument.sourceAppVersion,
            sourceBuild: currentStateDocument.sourceBuild,
            webAppState: currentStateDocument.webAppState,
            globalPreferences: currentStateDocument.globalPreferences,
            globalShowHideShortcut: nil
        )
        XCTAssertThrowsError(try service.decode(try encode(schemaOneStateTwo))) { error in
            XCTAssertEqual(
                error as? FloatTabsBackupError,
                .mismatchedVersions(schemaVersion: 1, webAppStateVersion: 2)
            )
        }

        let schemaTwoStateOne = FloatTabsBackupDocument(
            schemaVersion: 2,
            createdAt: currentStateDocument.createdAt,
            sourceAppVersion: currentStateDocument.sourceAppVersion,
            sourceBuild: currentStateDocument.sourceBuild,
            webAppState: legacyState,
            globalPreferences: currentStateDocument.globalPreferences,
            globalShowHideShortcut: nil
        )
        XCTAssertThrowsError(try service.decode(try encode(schemaTwoStateOne))) { error in
            XCTAssertEqual(
                error as? FloatTabsBackupError,
                .mismatchedVersions(schemaVersion: 2, webAppStateVersion: 1)
            )
        }

        let unknownSchema = FloatTabsBackupDocument(
            schemaVersion: 99,
            createdAt: currentStateDocument.createdAt,
            sourceAppVersion: currentStateDocument.sourceAppVersion,
            sourceBuild: currentStateDocument.sourceBuild,
            webAppState: currentStateDocument.webAppState,
            globalPreferences: currentStateDocument.globalPreferences,
            globalShowHideShortcut: nil
        )
        XCTAssertThrowsError(try service.decode(try encode(unknownSchema))) { error in
            XCTAssertEqual(error as? FloatTabsBackupError, .unsupportedSchema(99))
        }

        let unknownState = FloatTabsBackupDocument(
            schemaVersion: 2,
            createdAt: currentStateDocument.createdAt,
            sourceAppVersion: currentStateDocument.sourceAppVersion,
            sourceBuild: currentStateDocument.sourceBuild,
            webAppState: StoredWebAppState(
                version: 99,
                profiles: currentStateDocument.webAppState.profiles,
                lastActiveTabID: nil
            ),
            globalPreferences: currentStateDocument.globalPreferences,
            globalShowHideShortcut: nil
        )
        XCTAssertThrowsError(try service.decode(try encode(unknownState))) { error in
            XCTAssertEqual(error as? FloatTabsBackupError, .unsupportedWebAppStateVersion(99))
        }
    }

    func testBackupContainsConfigurationOnlyAndNoWebsiteDataKeys() throws {
        let browserProfile = BrowserProfile(
            id: UUID(),
            name: "Company",
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let slot = WebAppProfile(
            browserProfileID: browserProfile.id,
            order: 0,
            name: "Web App",
            homeURL: URL(string: "https://example.com")!
        )
        let data = try encode(makeDocument(browserProfiles: [browserProfile], profiles: [slot]))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data))
        let keys = allJSONKeys(in: object)
        let forbiddenKeys = [
            "cookies", "passwords", "oauthtokens", "tokens", "localstorage",
            "indexeddb", "serviceworkers", "websitedata", "webkitdata"
        ]

        for key in forbiddenKeys {
            XCTAssertFalse(keys.contains(key), "Unexpected website-data key: \(key)")
        }
    }

    func testRollbackBackupPreservesProfileMetadataAndSlotBindings() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsBackupProfileRollback-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = FloatTabsBackupService(backupDirectoryURL: directory)
        let browserProfile = BrowserProfile(
            id: UUID(),
            name: "Company",
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let slot = WebAppProfile(
            browserProfileID: browserProfile.id,
            order: 0,
            name: "Web App",
            homeURL: URL(string: "https://example.com")!
        )
        let document = makeDocument(browserProfiles: [browserProfile], profiles: [slot])

        let rollbackURL = try service.writeRollback(
            document,
            now: Date(timeIntervalSince1970: 20)
        )
        let restored = try service.load(from: rollbackURL)

        XCTAssertEqual(restored.webAppState.browserProfiles, [browserProfile])
        XCTAssertEqual(restored.webAppState.profiles.map(\.browserProfileID), [browserProfile.id])
    }

    func testExportedBackupUsesSchemaTwoAndStateTwoDowngradeBoundary() throws {
        let document = makeDocument()
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encode(document)) as? [String: Any]
        )
        let state = try XCTUnwrap(object["webAppState"] as? [String: Any])

        XCTAssertEqual(object["schemaVersion"] as? Int, 2)
        XCTAssertEqual(state["version"] as? Int, 2)
    }

    @MainActor
    func testRestoreAppliesAndNormalizesAttentionSoundPreferences() {
        let suiteName = "FloatTabsTests.BackupRestoreSound.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AppPreferencesStore(defaults: defaults)
        let backup = FloatTabsBackupPreferences(
            appearanceMode: .system,
            followPreferredSize: true,
            attentionSoundEnabled: false,
            attentionSoundName: "Purr",
            attentionSoundVolume: 4
        )

        AppCoordinator.restoreAttentionSoundPreferences(backup, to: store)

        XCTAssertFalse(store.attentionSoundEnabled)
        XCTAssertEqual(store.attentionSoundName, "Purr")
        XCTAssertEqual(store.attentionSoundVolume, 1, accuracy: 0.0001)
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

    func testLatestValidAutomaticSnapshotAcceptsLegacyAndSkipsFutureSchema() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsBackupLegacyRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = FloatTabsBackupService(backupDirectoryURL: directory)

        let legacyProfile = WebAppProfile(
            order: 0,
            name: "Legacy",
            homeURL: URL(string: "https://legacy.example")!,
            createdAt: Date(timeIntervalSince1970: 100),
            lastUsedAt: Date(timeIntervalSince1970: 100)
        )
        let legacyDocument = HistoricalBackupDocumentV1(
            schemaVersion: 1,
            createdAt: Date(timeIntervalSince1970: 200),
            sourceAppVersion: "0.1.0",
            sourceBuild: "legacy",
            webAppState: HistoricalBackupWebAppStateV1(
                version: 1,
                profiles: [legacyProfile],
                lastActiveTabID: legacyProfile.id
            ),
            globalPreferences: FloatTabsBackupPreferences(
                appearanceMode: .system,
                followPreferredSize: true
            ),
            globalShowHideShortcut: nil
        )
        let legacyEncoder = JSONEncoder()
        legacyEncoder.dateEncodingStrategy = .iso8601
        let legacyURL = directory.appendingPathComponent(
            "FloatTabs-auto-legacy-1.0.\(FloatTabsBackupService.fileExtension)"
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try legacyEncoder.encode(legacyDocument).write(to: legacyURL, options: [.atomic])

        var futureObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encode(makeDocument())) as? [String: Any]
        )
        futureObject["schemaVersion"] = 3
        var futureState = try XCTUnwrap(futureObject["webAppState"] as? [String: Any])
        futureState["version"] = 3
        futureObject["webAppState"] = futureState
        let futureURL = directory.appendingPathComponent(
            "FloatTabs-auto-future-3.0.\(FloatTabsBackupService.fileExtension)"
        )
        try JSONSerialization.data(withJSONObject: futureObject).write(to: futureURL, options: [.atomic])

        let latest = try XCTUnwrap(service.latestValidAutomaticSnapshot())
        XCTAssertEqual(latest.url.resolvingSymlinksInPath(), legacyURL.resolvingSymlinksInPath())
        XCTAssertEqual(latest.document.schemaVersion, 2)
        XCTAssertEqual(latest.document.webAppState.version, 2)
        XCTAssertEqual(latest.document.webAppState.browserProfiles, [])
        XCTAssertEqual(latest.document.webAppState.profiles.first?.browserProfileID, nil)
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

    private func encode(_ document: FloatTabsBackupDocument) throws -> Data {
        try FloatTabsBackupService().encode(document)
    }

    private func makeDocument(
        browserProfiles: [BrowserProfile] = [],
        profiles: [WebAppProfile] = []
    ) -> FloatTabsBackupDocument {
        FloatTabsBackupDocument(
            schemaVersion: FloatTabsBackupDocument.currentSchemaVersion,
            createdAt: Date(timeIntervalSince1970: 300),
            sourceAppVersion: "0.1.0",
            sourceBuild: "1",
            webAppState: StoredWebAppState(
                version: StoredWebAppState.currentVersion,
                browserProfiles: browserProfiles,
                profiles: profiles,
                lastActiveTabID: profiles.first?.id
            ),
            globalPreferences: FloatTabsBackupPreferences(
                appearanceMode: .system,
                followPreferredSize: true
            ),
            globalShowHideShortcut: nil
        )
    }

    private func allJSONKeys(in value: Any) -> Set<String> {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: Set<String>()) { keys, entry in
                keys.insert(entry.key.lowercased())
                keys.formUnion(allJSONKeys(in: entry.value))
            }
        }
        if let array = value as? [Any] {
            return array.reduce(into: Set<String>()) { keys, item in
                keys.formUnion(allJSONKeys(in: item))
            }
        }
        return []
    }
}

private struct HistoricalBackupDocumentV1: Encodable {
    let schemaVersion: Int
    let createdAt: Date
    let sourceAppVersion: String
    let sourceBuild: String
    let webAppState: HistoricalBackupWebAppStateV1
    let globalPreferences: FloatTabsBackupPreferences
    let globalShowHideShortcut: FloatTabsBackupShortcut?
}

private struct HistoricalBackupWebAppStateV1: Encodable {
    let version: Int
    let profiles: [WebAppProfile]
    let lastActiveTabID: UUID?
}
