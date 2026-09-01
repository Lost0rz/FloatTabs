import Foundation
import XCTest
@testable import FloatTabs

private final class StageAProfileRepository: ProfileRepositoryProtocol {
    var state: StoredWebAppState
    var shouldFailSaves = false
    private(set) var savedStates: [StoredWebAppState] = []

    init(state: StoredWebAppState = .empty) {
        self.state = state
    }

    func load() throws -> StoredWebAppState {
        state
    }

    func save(_ state: StoredWebAppState) throws {
        if shouldFailSaves {
            throw StageAProfileRepositoryError.forcedFailure
        }
        self.state = state
        savedStates.append(state)
    }
}

private enum StageAProfileRepositoryError: Error {
    case forcedFailure
}

@MainActor
final class BrowserProfilePersistenceTests: XCTestCase {
    private let urlA = URL(string: "https://example.com/a")!
    private let urlB = URL(string: "https://example.com/b")!

    func testV1LoadMigratesEverySlotToDefaultAndAtomicallyWritesV2() throws {
        try withFileRepository { repository, fileURL in
            let firstID = UUID()
            let secondID = UUID()
            let json = """
            {
              "version": 1,
              "profiles": [
                {
                  "id": "\(firstID.uuidString)",
                  "order": 0,
                  "name": "Legacy A",
                  "homeURL": "https://example.com/a",
                  "currentURL": "https://example.com/a/current",
                  "renderingProfile": {
                    "browserCompatibility": "chrome",
                    "contentMode": "mobile",
                    "viewportWidth": 390,
                    "viewportHeight": 780,
                    "zoom": 1.25
                  },
                  "createdAt": "2026-08-23T00:00:00Z",
                  "lastUsedAt": "2026-08-23T00:00:01Z"
                },
                {
                  "id": "\(secondID.uuidString)",
                  "order": 1,
                  "name": "Legacy B",
                  "homeURL": "https://example.com/b",
                  "renderingProfile": {
                    "browserCompatibility": "safari",
                    "contentMode": "desktop",
                    "viewportWidth": 600,
                    "viewportHeight": 820,
                    "zoom": 1.0
                  },
                  "createdAt": "2026-08-23T00:00:02Z",
                  "lastUsedAt": "2026-08-23T00:00:03Z"
                }
              ],
              "lastActiveTabID": "\(secondID.uuidString)"
            }
            """
            try Data(json.utf8).write(to: fileURL, options: [.atomic])

            let migrated = try repository.load()

            XCTAssertEqual(migrated.version, StoredWebAppState.currentVersion)
            XCTAssertTrue(migrated.browserProfiles.isEmpty)
            XCTAssertEqual(migrated.profiles.map(\.browserProfileID), [nil, nil])
            XCTAssertEqual(migrated.lastActiveTabID, secondID)

            let persisted = try Data(contentsOf: fileURL)
            let object = try XCTUnwrap(
                try JSONSerialization.jsonObject(with: persisted) as? [String: Any]
            )
            XCTAssertEqual(object["version"] as? Int, 2)
            XCTAssertNotNil(object["browserProfiles"])
            let reloaded = try JSONDecoder.profileState().decode(StoredWebAppState.self, from: persisted)
            XCTAssertEqual(reloaded, migrated)
        }
    }

    func testV2CustomProfileAndSlotBindingRoundTrip() throws {
        try withFileRepository { repository, _ in
            let browserProfile = BrowserProfile(
                id: UUID(),
                name: "Company",
                createdAt: Date(timeIntervalSince1970: 100)
            )
            let createdAt = Date(timeIntervalSince1970: 200)
            let slot = WebAppProfile(
                browserProfileID: browserProfile.id,
                order: 0,
                name: "Docs",
                homeURL: urlA,
                currentURL: urlB,
                createdAt: createdAt,
                lastUsedAt: createdAt
            )
            let state = StoredWebAppState(
                version: StoredWebAppState.currentVersion,
                browserProfiles: [browserProfile],
                profiles: [slot],
                lastActiveTabID: slot.id
            )

            try repository.save(state)

            XCTAssertEqual(try repository.load(), state)
        }
    }

    func testInvalidProfileMetadataAndDanglingReferencesFailClosed() throws {
        try withFileRepository { repository, _ in
            let duplicateID = UUID()
            let duplicateIDState = StoredWebAppState(
                version: StoredWebAppState.currentVersion,
                browserProfiles: [
                    BrowserProfile(id: duplicateID, name: "One", createdAt: Date()),
                    BrowserProfile(id: duplicateID, name: "Two", createdAt: Date())
                ],
                profiles: [],
                lastActiveTabID: nil
            )
            XCTAssertThrowsError(try repository.save(duplicateIDState)) { error in
                XCTAssertEqual(error as? ProfileRepositoryError, .duplicateBrowserProfileID(duplicateID))
            }

            let first = BrowserProfile(id: UUID(), name: "Personal", createdAt: Date())
            let duplicateNameState = StoredWebAppState(
                version: StoredWebAppState.currentVersion,
                browserProfiles: [
                    first,
                    BrowserProfile(id: UUID(), name: "PERSONAL", createdAt: Date())
                ],
                profiles: [],
                lastActiveTabID: nil
            )
            XCTAssertThrowsError(try repository.save(duplicateNameState)) { error in
                XCTAssertEqual(
                    error as? ProfileRepositoryError,
                    .duplicateBrowserProfileName("PERSONAL")
                )
            }

            let defaultCollision = BrowserProfile(id: UUID(), name: "dEfAuLt", createdAt: Date())
            let defaultCollisionState = StoredWebAppState(
                version: StoredWebAppState.currentVersion,
                browserProfiles: [defaultCollision],
                profiles: [],
                lastActiveTabID: nil
            )
            XCTAssertThrowsError(try repository.save(defaultCollisionState)) { error in
                XCTAssertEqual(error as? ProfileRepositoryError, .duplicateBrowserProfileName("dEfAuLt"))
            }

            let danglingID = UUID()
            let danglingSlot = WebAppProfile(
                browserProfileID: danglingID,
                order: 0,
                name: "Dangling",
                homeURL: urlA
            )
            let danglingState = StoredWebAppState(
                version: StoredWebAppState.currentVersion,
                browserProfiles: [],
                profiles: [danglingSlot],
                lastActiveTabID: danglingSlot.id
            )
            XCTAssertThrowsError(try repository.save(danglingState)) { error in
                XCTAssertEqual(error as? ProfileRepositoryError, .danglingBrowserProfileReference(danglingID))
            }
        }
    }

    func testProfileCRUDTrimsNamesPreservesIdentityAndBlocksReferencedDeletion() {
        let repository = StageAProfileRepository()
        let store = TabStore(repository: repository)
        let slot = store.add(name: "Docs", homeURL: urlA)!
        let createdAt = Date(timeIntervalSince1970: 321)
        let browserProfile = store.createBrowserProfile(name: "  Company  ", now: createdAt)!

        XCTAssertEqual(browserProfile.name, "Company")
        XCTAssertTrue(store.setBrowserProfile(slotID: slot.id, profileID: browserProfile.id))
        XCTAssertFalse(store.deleteBrowserProfileMetadata(id: browserProfile.id))

        XCTAssertTrue(store.renameBrowserProfile(id: browserProfile.id, name: "  Company Renamed  "))
        let renamed = store.browserProfiles.first { $0.id == browserProfile.id }
        XCTAssertEqual(renamed?.id, browserProfile.id)
        XCTAssertEqual(renamed?.createdAt, createdAt)
        XCTAssertEqual(renamed?.name, "Company Renamed")

        XCTAssertTrue(store.setBrowserProfile(slotID: slot.id, profileID: nil))
        XCTAssertTrue(store.deleteBrowserProfileMetadata(id: browserProfile.id))
        XCTAssertTrue(store.browserProfiles.isEmpty)
    }

    func testProfileNamesShareCaseInsensitiveNamespaceWithRenameableDefault() {
        let store = TabStore(repository: StageAProfileRepository())

        XCTAssertNil(store.createBrowserProfile(name: "   "))
        XCTAssertNotNil(store.createBrowserProfile(name: "Personal"))
        XCTAssertNil(store.createBrowserProfile(name: " personal "))
        XCTAssertNil(store.createBrowserProfile(name: " DEFAULT "))

        XCTAssertTrue(store.renameDefaultBrowserProfile(name: "Jack"))
        XCTAssertNotNil(store.createBrowserProfile(name: "Default"))
        XCTAssertNil(store.createBrowserProfile(name: " jack "))
    }

    func testDefaultPresentationRenameAndColorPersistWithoutChangingNilBinding() throws {
        let repository = StageAProfileRepository()
        let store = TabStore(repository: repository)
        let slot = try XCTUnwrap(store.add(name: "Default Web App", homeURL: urlA))
        var onChangeCalls = 0
        store.onChange = { onChangeCalls += 1 }

        XCTAssertTrue(store.renameDefaultBrowserProfile(name: "Jack"))
        XCTAssertTrue(store.setBrowserProfileColor(
            profileID: nil,
            color: BrowserProfileColor(preset: .purple)
        ))

        XCTAssertEqual(store.defaultBrowserProfilePresentation.name, "Jack")
        XCTAssertEqual(
            store.defaultBrowserProfilePresentation.color,
            BrowserProfileColor(preset: .purple)
        )
        XCTAssertNil(store.profiles.first(where: { $0.id == slot.id })?.browserProfileID)
        XCTAssertEqual(repository.state.defaultBrowserProfilePresentation.name, "Jack")
        XCTAssertEqual(onChangeCalls, 2)

        let before = store.storedStateSnapshot()
        repository.shouldFailSaves = true
        XCTAssertFalse(store.renameDefaultBrowserProfile(name: "Broken"))
        XCTAssertFalse(store.setBrowserProfileColor(
            profileID: nil,
            color: BrowserProfileColor(preset: .green)
        ))
        XCTAssertEqual(store.storedStateSnapshot(), before)
        XCTAssertEqual(onChangeCalls, 2)
    }

    func testCustomColorPersistsWithoutChangingUUIDCreatedAtOrBinding() throws {
        let repository = StageAProfileRepository()
        let store = TabStore(repository: repository)
        let custom = try XCTUnwrap(store.createBrowserProfile(name: "Company"))
        let slot = try XCTUnwrap(store.add(
            name: "Company Web App",
            homeURL: urlA,
            browserProfileID: custom.id
        ))
        let color = BrowserProfileColor(preset: .custom, customSRGBHex: "#123456")

        XCTAssertTrue(store.setBrowserProfileColor(profileID: custom.id, color: color))

        let persisted = try XCTUnwrap(store.browserProfiles.first(where: { $0.id == custom.id }))
        XCTAssertEqual(persisted.id, custom.id)
        XCTAssertEqual(persisted.createdAt, custom.createdAt)
        XCTAssertEqual(persisted.color, color)
        XCTAssertEqual(store.profiles.first(where: { $0.id == slot.id })?.browserProfileID, custom.id)
        XCTAssertEqual(repository.state.browserProfiles.first?.color, color)
    }

    func testOldV2StateMissingPresentationFieldsLoadsDeterministicDefaults() throws {
        try withFileRepository { repository, fileURL in
            let custom = BrowserProfile(id: UUID(), name: "Company", createdAt: Date(timeIntervalSince1970: 10))
            let state = StoredWebAppState(
                version: StoredWebAppState.currentVersion,
                browserProfiles: [custom],
                profiles: [],
                lastActiveTabID: nil
            )
            try repository.save(state)

            var object = try XCTUnwrap(
                try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
            )
            object.removeValue(forKey: "defaultBrowserProfilePresentation")
            var browserProfiles = try XCTUnwrap(object["browserProfiles"] as? [[String: Any]])
            browserProfiles[0].removeValue(forKey: "color")
            object["browserProfiles"] = browserProfiles
            try JSONSerialization.data(withJSONObject: object).write(to: fileURL, options: [.atomic])

            let loaded = try repository.load()

            XCTAssertEqual(loaded.defaultBrowserProfilePresentation, .default)
            XCTAssertEqual(loaded.browserProfiles.first?.color, .default)
        }
    }

    func testProfileAndBindingMutationsRollbackTogetherOnSaveFailure() {
        let repository = StageAProfileRepository()
        let store = TabStore(repository: repository)
        let slot = store.add(name: "Docs", homeURL: urlA)!
        let browserProfile = store.createBrowserProfile(name: "Company")!
        let unusedProfile = store.createBrowserProfile(name: "Unused")!
        XCTAssertTrue(store.setBrowserProfile(slotID: slot.id, profileID: browserProfile.id))
        let before = store.storedStateSnapshot()

        repository.shouldFailSaves = true

        XCTAssertFalse(store.setBrowserProfile(slotID: slot.id, profileID: nil))
        XCTAssertFalse(store.renameBrowserProfile(id: browserProfile.id, name: "Renamed"))
        XCTAssertFalse(store.deleteBrowserProfileMetadata(id: unusedProfile.id))
        XCTAssertNil(store.createBrowserProfile(name: "New"))

        XCTAssertEqual(store.storedStateSnapshot(), before)
        XCTAssertEqual(repository.state, before)
    }

    func testDuplicateSlotPreservesStableConfigurationAndUsesTargetProfile() {
        let repository = StageAProfileRepository()
        let store = TabStore(repository: repository)
        let source = store.add(
            name: "Source",
            homeURL: urlA,
            homeURLSchemeWasInferred: true,
            renderingProfile: .canonicalDefault.settingZoom(1.50),
            now: Date(timeIntervalSince1970: 10)
        )!
        store.updateCurrentURL(id: source.id, url: urlB)
        XCTAssertTrue(
            store.updateResourcePolicy(
                id: source.id,
                residencyPolicy: .hot,
                backgroundMediaPolicy: .allowBackgroundAudio
            )
        )
        let target = store.createBrowserProfile(name: "Company")!
        let sourceBefore = sourceSnapshot(store, id: source.id)

        let duplicate = store.duplicateSlot(
            sourceID: source.id,
            targetBrowserProfileID: target.id,
            now: Date(timeIntervalSince1970: 20)
        )!

        XCTAssertNotEqual(duplicate.id, source.id)
        XCTAssertEqual(sourceSnapshot(store, id: source.id), sourceBefore)
        XCTAssertEqual(duplicate.name, sourceBefore.name)
        XCTAssertEqual(duplicate.homeURL, sourceBefore.homeURL)
        XCTAssertEqual(duplicate.currentURL, urlB)
        XCTAssertEqual(duplicate.homeURLSchemeWasInferred, sourceBefore.homeURLSchemeWasInferred)
        XCTAssertEqual(duplicate.renderingProfile, sourceBefore.renderingProfile)
        XCTAssertEqual(duplicate.residencyPolicy, sourceBefore.residencyPolicy)
        XCTAssertEqual(duplicate.backgroundMediaPolicy, sourceBefore.backgroundMediaPolicy)
        XCTAssertEqual(duplicate.browserProfileID, target.id)
        XCTAssertEqual(store.activeTabID, duplicate.id)
        XCTAssertEqual(store.orderedProfiles.map(\.order), [0, 1])
        XCTAssertEqual(repository.state.profiles.last?.browserProfileID, target.id)
    }

    func testDuplicateSlotFallsBackToHomeAndRejectsMissingTarget() {
        let repository = StageAProfileRepository()
        let store = TabStore(repository: repository)
        let source = store.add(name: "Source", homeURL: urlA)!
        let before = store.storedStateSnapshot()

        XCTAssertNil(store.duplicateSlot(sourceID: source.id, targetBrowserProfileID: UUID()))
        XCTAssertEqual(store.storedStateSnapshot(), before)

        let duplicate = store.duplicateSlot(sourceID: source.id, targetBrowserProfileID: nil)!
        XCTAssertEqual(duplicate.currentURL, source.homeURL)
    }

    func testSetMissingTargetAndReplaceDanglingStateNeverFallbackToDefault() {
        let repository = StageAProfileRepository()
        let store = TabStore(repository: repository)
        let slot = store.add(name: "Source", homeURL: urlA)!
        let before = store.storedStateSnapshot()
        let missingID = UUID()

        XCTAssertFalse(store.setBrowserProfile(slotID: slot.id, profileID: missingID))
        XCTAssertEqual(store.storedStateSnapshot(), before)

        let danglingSlot = WebAppProfile(
            id: slot.id,
            browserProfileID: missingID,
            order: 0,
            name: "Source",
            homeURL: urlA
        )
        let invalidState = StoredWebAppState(
            version: StoredWebAppState.currentVersion,
            browserProfiles: [],
            profiles: [danglingSlot],
            lastActiveTabID: slot.id
        )

        XCTAssertFalse(store.replaceStoredState(invalidState))
        XCTAssertEqual(store.storedStateSnapshot(), before)
        XCTAssertEqual(repository.state, before)
    }

    private func sourceSnapshot(_ store: TabStore, id: UUID) -> WebAppProfile {
        store.profiles.first { $0.id == id }!
    }

    private func withFileRepository(
        _ body: (ProfileRepository, URL) throws -> Void
    ) throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsBrowserProfileTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("WebAppProfiles.json")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        try body(ProfileRepository(fileURL: fileURL), fileURL)
    }
}

private extension JSONDecoder {
    static func profileState() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
