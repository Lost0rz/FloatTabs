import AppKit
import XCTest
@testable import FloatTabs

@MainActor
final class AttentionSoundTests: XCTestCase {
    func testPreferencesDefaultToSystemAndPersistTypedCustomReference() {
        let suite = "FloatTabsTests.AttentionSoundPreferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppPreferencesStore(defaults: defaults)

        XCTAssertEqual(store.attentionSoundSourceKind, .system)
        defaults.set("future-source", forKey: AppPreferencesStore.attentionSoundSourceKindKey)
        XCTAssertEqual(store.attentionSoundSourceKind, .system)

        let reference = CustomAttentionSoundReference(
            managedFileName: "managed.aiff",
            displayName: "My Ready Sound.aiff"
        )
        store.setCustomAttentionSoundReference(reference)
        store.attentionSoundSourceKind = .custom

        XCTAssertEqual(store.customAttentionSoundReference, reference)
        XCTAssertEqual(
            AppPreferencesStore(defaults: defaults).customAttentionSoundReference,
            reference
        )
    }

    func testImportCopiesAudioAndNeverDependsOnOriginalPath() throws {
        let directory = makeTemporaryDirectory("AttentionSoundImport")
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("ready tone.aiff")
        try Data("audio source".utf8).write(to: source)
        let managedDirectory = directory.appendingPathComponent("managed", isDirectory: true)
        let store = AttentionSoundAssetStore(
            managedDirectoryURL: managedDirectory,
            audioDurationProbe: { _ in 1 }
        )

        let reference = try store.importAudio(from: source)
        let managedURL = try XCTUnwrap(store.existingURL(for: reference))
        XCTAssertNotEqual(managedURL, source)
        XCTAssertEqual(try Data(contentsOf: managedURL), Data("audio source".utf8))

        try FileManager.default.removeItem(at: source)
        XCTAssertTrue(FileManager.default.fileExists(atPath: managedURL.path))
        XCTAssertEqual(store.existingURL(for: reference), managedURL)
    }

    func testValidImportsAlwaysUseUniqueManagedNamesAndPreserveExtension() throws {
        let directory = makeTemporaryDirectory("AttentionSoundUniqueImport")
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstSource = directory.appendingPathComponent("first.aiff")
        let secondSource = directory.appendingPathComponent("second.aiff")
        try Data("first audio".utf8).write(to: firstSource)
        try Data("second audio".utf8).write(to: secondSource)
        let managedDirectory = directory.appendingPathComponent("managed", isDirectory: true)
        let store = AttentionSoundAssetStore(
            managedDirectoryURL: managedDirectory,
            audioDurationProbe: { _ in 1 }
        )

        let first = try store.importAudio(from: firstSource)
        let second = try store.importAudio(from: secondSource)
        let firstURL = try XCTUnwrap(store.existingURL(for: first))
        let secondURL = try XCTUnwrap(store.existingURL(for: second))

        XCTAssertNotEqual(first.managedFileName, second.managedFileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))
        XCTAssertEqual(URL(fileURLWithPath: first.managedFileName).pathExtension, "aiff")
        XCTAssertEqual(URL(fileURLWithPath: second.managedFileName).pathExtension, "aiff")
        XCTAssertNotEqual(
            first.managedFileName,
            "(UUID().uuidString).(sanitizedExtension)"
        )
        XCTAssertNotEqual(
            second.managedFileName,
            "(UUID().uuidString).(sanitizedExtension)"
        )
    }

    func testSuccessfulReplacementActivatesNewAssetAndRemovesOldAsset() throws {
        let directory = makeTemporaryDirectory("AttentionSoundSuccessfulReplacement")
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstSource = directory.appendingPathComponent("first.aiff")
        let secondSource = directory.appendingPathComponent("second.aiff")
        try Data("first audio".utf8).write(to: firstSource)
        try Data("second audio".utf8).write(to: secondSource)
        let managedDirectory = directory.appendingPathComponent("managed", isDirectory: true)
        let assetStore = AttentionSoundAssetStore(
            managedDirectoryURL: managedDirectory,
            audioDurationProbe: { _ in 1 }
        )
        let suite = "FloatTabsTests.AttentionSoundSuccessfulReplacement.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferencesStore(defaults: defaults)
        let player = SoundSpy()
        let controller = NotificationsSettingsViewController(
            preferencesStore: preferences,
            attentionSoundPlayer: player,
            availableSoundNames: ["Ping"],
            assetStore: assetStore
        )
        controller.loadViewIfNeeded()

        controller.importCustomAudio(from: firstSource)
        let firstReference = try XCTUnwrap(preferences.customAttentionSoundReference)
        let firstURL = try XCTUnwrap(assetStore.existingURL(for: firstReference))

        controller.importCustomAudio(from: secondSource)
        let secondReference = try XCTUnwrap(preferences.customAttentionSoundReference)
        let secondURL = try XCTUnwrap(assetStore.existingURL(for: secondReference))

        XCTAssertNotEqual(firstReference, secondReference)
        XCTAssertEqual(preferences.attentionSoundSourceKind, .custom)
        XCTAssertEqual(secondReference, preferences.customAttentionSoundReference)
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertEqual(player.sources.last, .custom(url: secondURL))
    }

    func testReadyResolutionUsesManagedCustomURLAndBackupForcesSystemSource() throws {
        let directory = makeTemporaryDirectory("AttentionSoundReady")
        defer { try? FileManager.default.removeItem(at: directory) }
        let managedDirectory = directory.appendingPathComponent("managed", isDirectory: true)
        try FileManager.default.createDirectory(at: managedDirectory, withIntermediateDirectories: true)
        let managedURL = managedDirectory.appendingPathComponent("ready.aiff")
        try Data("managed audio".utf8).write(to: managedURL)
        let assetStore = AttentionSoundAssetStore(managedDirectoryURL: managedDirectory)
        let suite = "FloatTabsTests.AttentionSoundReady.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.setCustomAttentionSoundReference(
            CustomAttentionSoundReference(managedFileName: "ready.aiff", displayName: "Ready")
        )
        preferences.attentionSoundSourceKind = .custom

        XCTAssertEqual(
            AppCoordinator.attentionSoundPlaybackSource(
                preferencesStore: preferences,
                assetStore: assetStore
            ),
            .custom(url: managedURL)
        )

        let backup = FloatTabsBackupPreferences(
            appearanceMode: .system,
            followPreferredSize: true,
            attentionSoundEnabled: true,
            attentionSoundName: "Glass",
            attentionSoundVolume: 0.5
        )
        AppCoordinator.restoreAttentionSoundPreferences(backup, to: preferences)
        XCTAssertEqual(preferences.attentionSoundSourceKind, .system)
        XCTAssertEqual(preferences.attentionSoundName, "Glass")
        XCTAssertTrue(FileManager.default.fileExists(atPath: managedURL.path))
    }

    func testFailedReplacementKeepsPreviousCustomReferenceAndAsset() throws {
        let directory = makeTemporaryDirectory("AttentionSoundReplacement")
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstSource = directory.appendingPathComponent("first.aiff")
        let invalidSource = directory.appendingPathComponent("too-large.aiff")
        try Data("first".utf8).write(to: firstSource)
        try Data(repeating: 0, count: Int(AttentionSoundAssetStore.maxFileSizeBytes) + 1)
            .write(to: invalidSource)
        let managedDirectory = directory.appendingPathComponent("managed", isDirectory: true)
        let assetStore = AttentionSoundAssetStore(
            managedDirectoryURL: managedDirectory,
            audioDurationProbe: { _ in 1 }
        )
        let suite = "FloatTabsTests.AttentionSoundReplacement.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferencesStore(defaults: defaults)
        let player = SoundSpy()
        var errors: [Error] = []
        let controller = NotificationsSettingsViewController(
            preferencesStore: preferences,
            attentionSoundPlayer: player,
            availableSoundNames: ["Ping"],
            assetStore: assetStore,
            errorPresenter: { errors.append($0) }
        )
        controller.loadViewIfNeeded()

        controller.importCustomAudio(from: firstSource)
        let oldReference = try XCTUnwrap(preferences.customAttentionSoundReference)
        let oldURL = try XCTUnwrap(assetStore.existingURL(for: oldReference))
        controller.importCustomAudio(from: invalidSource)

        XCTAssertEqual(preferences.customAttentionSoundReference, oldReference)
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertEqual(errors.count, 1)
    }

    func testImportRejectsSizeDurationAndDecodeLimits() throws {
        let directory = makeTemporaryDirectory("AttentionSoundLimits")
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("tone.wav")
        try Data(repeating: 0, count: 32).write(to: source)

        let tooLongStore = AttentionSoundAssetStore(
            managedDirectoryURL: directory.appendingPathComponent("long"),
            audioDurationProbe: { _ in 30.1 }
        )
        XCTAssertThrowsError(try tooLongStore.importAudio(from: source)) { error in
            XCTAssertEqual(
                error as? AttentionSoundAssetError,
                .durationTooLong(maxSeconds: AttentionSoundAssetStore.maxDuration)
            )
        }

        let undecodableStore = AttentionSoundAssetStore(
            managedDirectoryURL: directory.appendingPathComponent("decode"),
            audioDurationProbe: { _ in nil }
        )
        XCTAssertThrowsError(try undecodableStore.importAudio(from: source)) { error in
            XCTAssertEqual(error as? AttentionSoundAssetError, .cannotDecode)
        }

        let largeSource = directory.appendingPathComponent("large.wav")
        try Data(repeating: 0, count: Int(AttentionSoundAssetStore.maxFileSizeBytes) + 1)
            .write(to: largeSource)
        let sizeStore = AttentionSoundAssetStore(
            managedDirectoryURL: directory.appendingPathComponent("size"),
            audioDurationProbe: { _ in 1 }
        )
        XCTAssertThrowsError(try sizeStore.importAudio(from: largeSource)) { error in
            XCTAssertEqual(
                error as? AttentionSoundAssetError,
                .fileTooLarge(maxBytes: AttentionSoundAssetStore.maxFileSizeBytes)
            )
        }
    }

    func testMalformedReferenceCannotEscapeManagedDirectoryOrDeleteOriginal() throws {
        let directory = makeTemporaryDirectory("AttentionSoundTraversal")
        defer { try? FileManager.default.removeItem(at: directory) }
        let managedDirectory = directory.appendingPathComponent("managed", isDirectory: true)
        try FileManager.default.createDirectory(at: managedDirectory, withIntermediateDirectories: true)
        let outside = directory.appendingPathComponent("outside.aiff")
        try Data("do not delete".utf8).write(to: outside)
        let store = AttentionSoundAssetStore(managedDirectoryURL: managedDirectory)
        let reference = CustomAttentionSoundReference(
            managedFileName: "../outside.aiff",
            displayName: "Outside"
        )
        let directoryReference = CustomAttentionSoundReference(
            managedFileName: ".",
            displayName: "Managed Directory"
        )

        XCTAssertNil(store.url(for: reference))
        XCTAssertNil(store.url(for: directoryReference))
        try store.remove(reference)
        try store.remove(directoryReference)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testCustomPlaybackFallsBackButZeroVolumeStaysSilent() throws {
        var systemCalls: [(String, Float)] = []
        var beepCount = 0
        guard let sound = NSSound(named: NSSound.Name("Ping")) else {
            throw XCTSkip("Ping is unavailable in this test environment")
        }
        let player = AttentionSoundPlayer(
            playSystemSound: { name, volume in
                systemCalls.append((name, volume))
                return false
            },
            loadCustomSound: { _ in sound },
            playCustomSound: { _, _ in true },
            beep: { beepCount += 1 }
        )

        player.play(source: .custom(url: URL(fileURLWithPath: "/missing")), volume: 0.5)
        XCTAssertIdentical(player.activeSound, sound)

        player.play(source: .custom(url: URL(fileURLWithPath: "/missing")), volume: 0)
        XCTAssertNil(player.activeSound)
        XCTAssertTrue(systemCalls.isEmpty)
        XCTAssertEqual(beepCount, 0)

        let failingPlayer = AttentionSoundPlayer(
            playSystemSound: { name, volume in
                systemCalls.append((name, volume))
                return false
            },
            loadCustomSound: { _ in nil },
            beep: { beepCount += 1 }
        )
        failingPlayer.play(source: .custom(url: URL(fileURLWithPath: "/missing")), volume: 1)
        XCTAssertEqual(systemCalls.last?.0, AppPreferencesStore.defaultAttentionSoundName)
        XCTAssertEqual(beepCount, 1)
    }

    func testNotificationsShowsMissingCustomAndPreviewsThroughFallbackPath() {
        let suite = "FloatTabsTests.AttentionSoundUI.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.setCustomAttentionSoundReference(
            CustomAttentionSoundReference(
                managedFileName: "missing.aiff",
                displayName: "My Alert.aiff"
            )
        )
        preferences.attentionSoundSourceKind = .custom
        let managedDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsSoundUI-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: managedDirectory) }
        let assetStore = AttentionSoundAssetStore(managedDirectoryURL: managedDirectory)
        let player = SoundSpy()
        let controller = NotificationsSettingsViewController(
            preferencesStore: preferences,
            attentionSoundPlayer: player,
            availableSoundNames: ["Ping"],
            assetStore: assetStore
        )
        controller.loadViewIfNeeded()

        XCTAssertEqual(controller.sourcePopup.indexOfSelectedItem, 1)
        XCTAssertEqual(controller.customSoundLabel.stringValue, "My Alert.aiff — Missing")
        controller.previewButton.performClick(nil)
        XCTAssertEqual(player.sources, [.system(name: "Ping")])
    }

    private func makeTemporaryDirectory(_ name: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabs-\(name)-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private final class SoundSpy: AttentionSoundPlaying {
        private(set) var sources: [AttentionSoundPlaybackSource] = []

        func play(source: AttentionSoundPlaybackSource, volume: Double) {
            sources.append(source)
        }
    }
}
