import AppKit
import XCTest
@testable import FloatTabs

@MainActor
final class AttentionSoundTests: XCTestCase {
    func testPreferencesLibraryDefaultsEmptyAndPersistsMultipleAssetsAndSelection() {
        let suite = "FloatTabsTests.AttentionSoundLibrary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = makeAsset(name: "first.aiff")
        let second = makeAsset(name: "second.aiff")

        let store = AppPreferencesStore(defaults: defaults)
        XCTAssertTrue(store.customAttentionSoundLibrary.isEmpty)

        store.customAttentionSoundLibrary = [first, second]
        store.selectedCustomAttentionSoundID = second.id

        let reloaded = AppPreferencesStore(defaults: defaults)
        XCTAssertEqual(reloaded.customAttentionSoundLibrary, [first, second])
        XCTAssertEqual(reloaded.selectedCustomAttentionSoundID, second.id)
    }

    func testBatchImportAddsThreeAssetsWithoutChangingSystemSelection() throws {
        let directory = makeTemporaryDirectory("AttentionSoundBatch")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sources = ["ready-1.wav", "ready-2.m4a", "ready-3.mp3"].map {
            directory.appendingPathComponent($0)
        }
        for source in sources {
            try Data("audio \(source.lastPathComponent)".utf8).write(to: source)
        }
        let assetStore = AttentionSoundAssetStore(
            managedDirectoryURL: directory.appendingPathComponent("managed"),
            audioDurationProbe: { _ in 1 }
        )
        let suite = "FloatTabsTests.AttentionSoundBatchPreferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.attentionSoundName = "Glass"
        let player = SoundSpy()
        let errors = ErrorSpy()
        let controller = NotificationsSettingsViewController(
            preferencesStore: preferences,
            attentionSoundPlayer: player,
            availableSoundNames: ["Ping", "Glass"],
            assetStore: assetStore,
            errorPresenter: { errors.errors.append($0) }
        )
        controller.loadViewIfNeeded()

        controller.importCustomAudio(from: sources)

        XCTAssertEqual(preferences.customAttentionSoundLibrary.count, 3)
        XCTAssertEqual(preferences.attentionSoundSourceKind, .system)
        XCTAssertNil(preferences.selectedCustomAttentionSoundID)
        XCTAssertEqual(preferences.attentionSoundName, "Glass")
        XCTAssertTrue(player.sources.isEmpty)
        XCTAssertTrue(errors.errors.isEmpty)
        XCTAssertTrue(
            preferences.customAttentionSoundLibrary.allSatisfy {
                assetStore.existingURL(for: $0) != nil
            }
        )
    }

    func testBatchImportKeepsValidFilesAndReportsOnlyInvalidFile() throws {
        let directory = makeTemporaryDirectory("AttentionSoundPartialBatch")
        defer { try? FileManager.default.removeItem(at: directory) }
        let validA = directory.appendingPathComponent("valid-a.aiff")
        let invalid = directory.appendingPathComponent("invalid.aiff")
        let validC = directory.appendingPathComponent("valid-c.aiff")
        for source in [validA, invalid, validC] {
            try Data("audio".utf8).write(to: source)
        }
        let assetStore = AttentionSoundAssetStore(
            managedDirectoryURL: directory.appendingPathComponent("managed"),
            audioDurationProbe: { url in
                url.lastPathComponent == "invalid.aiff" ? nil : 1
            }
        )
        let suite = "FloatTabsTests.AttentionSoundPartialBatch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferencesStore(defaults: defaults)
        let errors = ErrorSpy()
        let controller = NotificationsSettingsViewController(
            preferencesStore: preferences,
            attentionSoundPlayer: SoundSpy(),
            availableSoundNames: ["Ping"],
            assetStore: assetStore,
            errorPresenter: { errors.errors.append($0) }
        )
        controller.loadViewIfNeeded()

        controller.importCustomAudio(from: [validA, invalid, validC])

        XCTAssertEqual(preferences.customAttentionSoundLibrary.count, 2)
        XCTAssertEqual(
            Set(preferences.customAttentionSoundLibrary.map(\.displayName)),
            Set(["valid-a.aiff", "valid-c.aiff"])
        )
        XCTAssertEqual(errors.errors.count, 1)
        let batchError = errors.errors.first as? AttentionSoundBatchImportError
        XCTAssertEqual(batchError?.failures.count, 1)
        XCTAssertEqual(batchError?.failures.first?.displayName, "invalid.aiff")
        XCTAssertEqual(preferences.attentionSoundSourceKind, .system)
    }

    func testImportDoesNotDeleteExistingAssetsOrChangeActiveCustomSelection() throws {
        let directory = makeTemporaryDirectory("AttentionSoundAppend")
        defer { try? FileManager.default.removeItem(at: directory) }
        let existing = makeAsset(name: "existing.aiff")
        let existingURL = directory.appendingPathComponent(existing.managedFileName)
        try Data("existing".utf8).write(to: existingURL)
        let newSource = directory.appendingPathComponent("new.aiff")
        try Data("new".utf8).write(to: newSource)
        let managedDirectory = directory.appendingPathComponent("managed")
        let assetStore = AttentionSoundAssetStore(
            managedDirectoryURL: managedDirectory,
            audioDurationProbe: { _ in 1 }
        )
        let suite = "FloatTabsTests.AttentionSoundAppendPreferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.customAttentionSoundLibrary = [existing]
        preferences.attentionSoundSourceKind = .custom
        preferences.selectedCustomAttentionSoundID = existing.id
        let controller = NotificationsSettingsViewController(
            preferencesStore: preferences,
            attentionSoundPlayer: SoundSpy(),
            availableSoundNames: ["Ping"],
            assetStore: assetStore
        )
        controller.loadViewIfNeeded()

        controller.importCustomAudio(from: newSource)

        XCTAssertEqual(preferences.customAttentionSoundLibrary.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: existingURL.path))
        XCTAssertEqual(preferences.attentionSoundSourceKind, .custom)
        XCTAssertEqual(preferences.selectedCustomAttentionSoundID, existing.id)
    }

    func testDuplicateDisplayNamesHaveDistinctIDsAndManagedFiles() throws {
        let directory = makeTemporaryDirectory("AttentionSoundDuplicateNames")
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstDirectory = directory.appendingPathComponent("first")
        let secondDirectory = directory.appendingPathComponent("second")
        try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        let firstSource = firstDirectory.appendingPathComponent("same-name.wav")
        let secondSource = secondDirectory.appendingPathComponent("same-name.wav")
        try Data("first".utf8).write(to: firstSource)
        try Data("second".utf8).write(to: secondSource)
        let store = AttentionSoundAssetStore(
            managedDirectoryURL: directory.appendingPathComponent("managed"),
            audioDurationProbe: { _ in 1 }
        )

        let result = store.importAudio(from: [firstSource, secondSource])

        XCTAssertEqual(result.failures.count, 0)
        XCTAssertEqual(result.assets.map(\.displayName), ["same-name.wav", "same-name.wav"])
        XCTAssertEqual(Set(result.assets.map(\.id)).count, 2)
        XCTAssertEqual(Set(result.assets.map(\.managedFileName)).count, 2)
    }

    func testSelectingCustomAThenBUpdatesActiveIDAndPreviewsEachAsset() throws {
        let directory = makeTemporaryDirectory("AttentionSoundSelection")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try writeAsset(named: "first.aiff", in: directory)
        let second = try writeAsset(named: "second.aiff", in: directory)
        let assetStore = AttentionSoundAssetStore(managedDirectoryURL: directory, audioDurationProbe: { _ in 1 })
        let suite = "FloatTabsTests.AttentionSoundSelectionPreferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.customAttentionSoundLibrary = [first, second]
        let player = SoundSpy()
        let controller = NotificationsSettingsViewController(
            preferencesStore: preferences,
            attentionSoundPlayer: player,
            availableSoundNames: ["Ping"],
            assetStore: assetStore
        )
        controller.loadViewIfNeeded()

        selectCustomAsset(first.id, in: controller)
        XCTAssertEqual(preferences.selectedCustomAttentionSoundID, first.id)
        XCTAssertEqual(player.sources.last, .custom(url: try XCTUnwrap(assetStore.existingURL(for: first))))

        selectCustomAsset(second.id, in: controller)
        XCTAssertEqual(preferences.selectedCustomAttentionSoundID, second.id)
        XCTAssertEqual(player.sources.last, .custom(url: try XCTUnwrap(assetStore.existingURL(for: second))))
    }

    func testRemoveNonActiveAssetLeavesActiveAssetAndSelection() throws {
        let directory = makeTemporaryDirectory("AttentionSoundRemoveNonActive")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try writeAsset(named: "first.aiff", in: directory)
        let second = try writeAsset(named: "second.aiff", in: directory)
        let assetStore = AttentionSoundAssetStore(managedDirectoryURL: directory)
        let suite = "FloatTabsTests.AttentionSoundRemoveNonActivePreferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.customAttentionSoundLibrary = [first, second]
        preferences.attentionSoundSourceKind = .custom
        preferences.selectedCustomAttentionSoundID = second.id
        let controller = NotificationsSettingsViewController(
            preferencesStore: preferences,
            attentionSoundPlayer: SoundSpy(),
            availableSoundNames: ["Ping"],
            assetStore: assetStore
        )
        controller.loadViewIfNeeded()

        controller.removeCustomAudioAsset(id: first.id)

        XCTAssertNil(preferences.customAttentionSoundAsset(id: first.id))
        XCTAssertNotNil(preferences.customAttentionSoundAsset(id: second.id))
        XCTAssertEqual(preferences.attentionSoundSourceKind, .custom)
        XCTAssertEqual(preferences.selectedCustomAttentionSoundID, second.id)
        XCTAssertNotNil(assetStore.existingURL(for: second))
        XCTAssertNil(assetStore.existingURL(for: first))
    }

    func testRemoveActiveAssetFallsBackToConfiguredSystemSound() throws {
        let directory = makeTemporaryDirectory("AttentionSoundRemoveActive")
        defer { try? FileManager.default.removeItem(at: directory) }
        let active = try writeAsset(named: "active.aiff", in: directory)
        let assetStore = AttentionSoundAssetStore(managedDirectoryURL: directory)
        let suite = "FloatTabsTests.AttentionSoundRemoveActivePreferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.customAttentionSoundLibrary = [active]
        preferences.attentionSoundName = "Glass"
        preferences.attentionSoundSourceKind = .custom
        preferences.selectedCustomAttentionSoundID = active.id
        let controller = NotificationsSettingsViewController(
            preferencesStore: preferences,
            attentionSoundPlayer: SoundSpy(),
            availableSoundNames: ["Ping", "Glass"],
            assetStore: assetStore
        )
        controller.loadViewIfNeeded()

        controller.removeCustomAudioAsset(id: active.id)

        XCTAssertTrue(preferences.customAttentionSoundLibrary.isEmpty)
        XCTAssertNil(preferences.selectedCustomAttentionSoundID)
        XCTAssertEqual(preferences.attentionSoundSourceKind, .system)
        XCTAssertEqual(
            AppCoordinator.attentionSoundPlaybackSource(
                preferencesStore: preferences,
                assetStore: assetStore
            ),
            .system(name: "Glass")
        )
    }

    func testMissingSelectedAssetRemainsVisibleAndPreviewUsesPingFallback() throws {
        let directory = makeTemporaryDirectory("AttentionSoundMissing")
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = makeAsset(name: "missing.aiff")
        let assetStore = AttentionSoundAssetStore(managedDirectoryURL: directory)
        let suite = "FloatTabsTests.AttentionSoundMissingPreferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.customAttentionSoundLibrary = [missing]
        preferences.attentionSoundSourceKind = .custom
        preferences.selectedCustomAttentionSoundID = missing.id
        let player = SoundSpy()
        let controller = NotificationsSettingsViewController(
            preferencesStore: preferences,
            attentionSoundPlayer: player,
            availableSoundNames: ["Ping"],
            assetStore: assetStore
        )
        controller.loadViewIfNeeded()

        XCTAssertTrue(controller.soundPopup.itemArray.contains {
            $0.title == "missing.aiff — Missing"
        })
        XCTAssertTrue(controller.removeSelectedAudioButton.isEnabled)
        controller.previewButton.performClick(nil)
        XCTAssertEqual(player.sources.last, .system(name: "Ping"))
        XCTAssertEqual(preferences.customAttentionSoundLibrary, [missing])
    }

    func testUnknownSelectedAssetFallsBackToPingWithoutChangingLibrary() throws {
        let directory = makeTemporaryDirectory("AttentionSoundUnknownSelection")
        defer { try? FileManager.default.removeItem(at: directory) }
        let known = makeAsset(name: "known.aiff")
        let assetStore = AttentionSoundAssetStore(managedDirectoryURL: directory)
        let suite = "FloatTabsTests.AttentionSoundUnknownSelectionPreferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.customAttentionSoundLibrary = [known]
        preferences.attentionSoundSourceKind = .custom
        let unknownID = UUID()
        preferences.selectedCustomAttentionSoundID = unknownID
        let controller = NotificationsSettingsViewController(
            preferencesStore: preferences,
            attentionSoundPlayer: SoundSpy(),
            availableSoundNames: ["Ping", "Glass"],
            assetStore: assetStore
        )
        controller.loadViewIfNeeded()

        XCTAssertEqual(
            AppCoordinator.attentionSoundPlaybackSource(
                preferencesStore: preferences,
                assetStore: assetStore
            ),
            .system(name: "Ping")
        )
        XCTAssertEqual(preferences.selectedCustomAttentionSoundID, unknownID)
        XCTAssertEqual(preferences.customAttentionSoundLibrary, [known])
        XCTAssertEqual(controller.soundPopup.selectedItem?.title, "Ping")
    }

    func testImportedManagedCopySurvivesSourceDeletion() throws {
        let directory = makeTemporaryDirectory("AttentionSoundSourceDeletion")
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.m4a")
        try Data("source audio".utf8).write(to: source)
        let store = AttentionSoundAssetStore(
            managedDirectoryURL: directory.appendingPathComponent("managed"),
            audioDurationProbe: { _ in 1 }
        )

        let asset = try store.importAudio(from: source)
        let managedURL = try XCTUnwrap(store.existingURL(for: asset))
        try FileManager.default.removeItem(at: source)

        XCTAssertTrue(FileManager.default.fileExists(atPath: managedURL.path))
        XCTAssertEqual(store.existingURL(for: asset), managedURL)
    }

    func testImportRejectsSizeDurationAndDecodeLimitsPerFile() throws {
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

    func testMalformedAssetCannotEscapeManagedDirectoryOrDeleteOriginal() throws {
        let directory = makeTemporaryDirectory("AttentionSoundTraversal")
        defer { try? FileManager.default.removeItem(at: directory) }
        let managedDirectory = directory.appendingPathComponent("managed", isDirectory: true)
        try FileManager.default.createDirectory(at: managedDirectory, withIntermediateDirectories: true)
        let outside = directory.appendingPathComponent("outside.aiff")
        try Data("do not delete".utf8).write(to: outside)
        let store = AttentionSoundAssetStore(managedDirectoryURL: managedDirectory)
        let outsideAsset = CustomAttentionSoundAsset(
            managedFileName: "../outside.aiff",
            displayName: "Outside"
        )
        let directoryAsset = CustomAttentionSoundAsset(
            managedFileName: ".",
            displayName: "Managed Directory"
        )

        XCTAssertNil(store.url(for: outsideAsset))
        XCTAssertNil(store.url(for: directoryAsset))
        try store.remove(outsideAsset)
        try store.remove(directoryAsset)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testCustomPlaybackRetainsActiveSoundAndZeroVolumeStaysSilent() throws {
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
    }

    func testRestoreForcesSystemWithoutDeletingLocalLibrary() throws {
        let directory = makeTemporaryDirectory("AttentionSoundRestore")
        defer { try? FileManager.default.removeItem(at: directory) }
        let asset = try writeAsset(named: "local.aiff", in: directory)
        let suite = "FloatTabsTests.AttentionSoundRestorePreferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.customAttentionSoundLibrary = [asset]
        preferences.selectedCustomAttentionSoundID = asset.id
        preferences.attentionSoundSourceKind = .custom
        let backup = FloatTabsBackupPreferences(
            appearanceMode: .system,
            followPreferredSize: true,
            attentionSoundEnabled: true,
            attentionSoundName: "Glass",
            attentionSoundVolume: 0.5
        )

        AppCoordinator.restoreAttentionSoundPreferences(backup, to: preferences)

        XCTAssertEqual(preferences.attentionSoundSourceKind, .system)
        XCTAssertEqual(preferences.customAttentionSoundLibrary, [asset])
        XCTAssertEqual(preferences.selectedCustomAttentionSoundID, asset.id)
    }

    private func makeTemporaryDirectory(_ name: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabs-\(name)-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeAsset(name: String) -> CustomAttentionSoundAsset {
        let id = UUID()
        return CustomAttentionSoundAsset(
            id: id,
            managedFileName: "\(id.uuidString).aiff",
            displayName: name
        )
    }

    private func writeAsset(named name: String, in directory: URL) throws -> CustomAttentionSoundAsset {
        let id = UUID()
        let asset = CustomAttentionSoundAsset(
            id: id,
            managedFileName: "\(id.uuidString).aiff",
            displayName: name
        )
        try Data("managed audio".utf8).write(
            to: directory.appendingPathComponent(asset.managedFileName)
        )
        return asset
    }

    private func selectCustomAsset(
        _ id: UUID,
        in controller: NotificationsSettingsViewController
    ) {
        let selection = "custom:\(id.uuidString)"
        let index = controller.soundPopup.itemArray.firstIndex {
            ($0.representedObject as? String) == selection
        }!
        controller.soundPopup.selectItem(at: index)
        _ = controller.perform(controller.soundPopup.action, with: controller.soundPopup)
    }

    private final class SoundSpy: AttentionSoundPlaying {
        private(set) var sources: [AttentionSoundPlaybackSource] = []

        func play(source: AttentionSoundPlaybackSource, volume: Double) {
            sources.append(source)
        }
    }

    private final class ErrorSpy {
        var errors: [Error] = []
    }
}
