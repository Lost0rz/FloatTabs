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
            XCTAssertEqual(profile.renderingProfile.sizePreset, .small)
            XCTAssertEqual(profile.renderingProfile.viewportSize, CGSize(width: 390, height: 780))
            XCTAssertEqual(profile.renderingProfile.zoom, 1.25, accuracy: 0.001)
            XCTAssertEqual(profile.residencyPolicy, .warm)
            XCTAssertEqual(profile.backgroundMediaPolicy, .pauseWhenInactive)
        }
    }

    func testCorruptMetadataFailsSafelyAndTabStoreStartsEmpty() throws {
        try withRepository { repository, fileURL in
            try Data("{ definitely-not-json".utf8).write(to: fileURL, options: [.atomic])

            XCTAssertThrowsError(try repository.load())

            let store = TabStore(repository: repository)
            XCTAssertTrue(store.profiles.isEmpty)
            XCTAssertNil(store.activeTabID)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
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
}
