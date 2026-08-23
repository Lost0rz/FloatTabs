import AppKit
import XCTest
@testable import FloatTabs

@MainActor
final class WebAttentionIndicatorTests: XCTestCase {
    private final class SoundPlayerSpy: AttentionSoundPlaying {
        struct Call: Equatable {
            let soundName: String
            let volume: Double
        }

        private(set) var calls: [Call] = []

        func play(soundName: String, volume: Double) {
            calls.append(Call(soundName: soundName, volume: volume))
        }
    }

    func testIdleAndGeneratingSlotsHaveNoReadyDot() {
        let coordinator = WebAttentionCoordinator()
        let profile = makeProfile(name: "GPT")
        let (_, zone) = makeZoneHarness()
        zone.apply(profiles: [profile], activeTabID: profile.id)
        synchronize(zone, from: coordinator)

        let tab = try! XCTUnwrap(zone.tabView(for: profile.id))
        XCTAssertFalse(tab.isShowingReadyAttention)

        coordinator.apply(.generationStarted, for: profile.id)
        synchronize(zone, from: coordinator)
        XCTAssertFalse(tab.isShowingReadyAttention)
    }

    func testGenerationCompletionProjectsReadyDotAndNewGenerationClearsIt() {
        let coordinator = WebAttentionCoordinator()
        let profile = makeProfile(name: "GPT")
        let (_, zone) = makeZoneHarness()
        zone.apply(profiles: [profile], activeTabID: profile.id)

        coordinator.apply(.generationStarted, for: profile.id)
        coordinator.apply(.generationFinished(userVisible: false), for: profile.id)
        synchronize(zone, from: coordinator)

        let tab = try! XCTUnwrap(zone.tabView(for: profile.id))
        XCTAssertTrue(tab.isShowingReadyAttention)

        coordinator.apply(.generationStarted, for: profile.id)
        synchronize(zone, from: coordinator)
        XCTAssertFalse(tab.isShowingReadyAttention)
    }

    func testReadySoundPolicyOnlyTriggersWhenReadyCountIncreases() {
        XCTAssertTrue(
            AppCoordinator.shouldPlayAttentionReadySound(
                previousReadyCount: 0,
                currentReadyCount: 1
            )
        )
        XCTAssertTrue(
            AppCoordinator.shouldPlayAttentionReadySound(
                previousReadyCount: 1,
                currentReadyCount: 2
            )
        )
        XCTAssertFalse(
            AppCoordinator.shouldPlayAttentionReadySound(
                previousReadyCount: 1,
                currentReadyCount: 1
            )
        )
        XCTAssertFalse(
            AppCoordinator.shouldPlayAttentionReadySound(
                previousReadyCount: 2,
                currentReadyCount: 1
            )
        )
        XCTAssertFalse(
            AppCoordinator.shouldPlayAttentionReadySound(
                previousReadyCount: 1,
                currentReadyCount: 0
            )
        )
        XCTAssertFalse(
            AppCoordinator.shouldPlayAttentionReadySound(
                previousReadyCount: 0,
                currentReadyCount: 0
            )
        )
    }

    func testReadySoundPolicyNormalizesInvalidNegativeCounts() {
        XCTAssertFalse(
            AppCoordinator.shouldPlayAttentionReadySound(
                previousReadyCount: -1,
                currentReadyCount: 0
            )
        )
        XCTAssertTrue(
            AppCoordinator.shouldPlayAttentionReadySound(
                previousReadyCount: -1,
                currentReadyCount: 1
            )
        )
    }

    func testReadySoundEnabledGateAndConfiguredValuesAreForwarded() {
        let suiteName = "FloatTabsTests.ReadySound.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.attentionSoundName = "Glass"
        preferences.attentionSoundVolume = 0.42
        let player = SoundPlayerSpy()

        XCTAssertTrue(
            AppCoordinator.playAttentionReadySoundIfNeeded(
                previousReadyCount: 0,
                currentReadyCount: 1,
                preferencesStore: preferences,
                player: player
            )
        )
        XCTAssertEqual(
            player.calls,
            [.init(soundName: "Glass", volume: 0.42)]
        )

        preferences.attentionSoundEnabled = false
        XCTAssertFalse(
            AppCoordinator.playAttentionReadySoundIfNeeded(
                previousReadyCount: 1,
                currentReadyCount: 2,
                preferencesStore: preferences,
                player: player
            )
        )
        XCTAssertEqual(player.calls.count, 1)
    }

    func testAttentionSoundPlayerNormalizesVolumeAndUsesFallbackOnlyForAudibleFailures() {
        var systemCalls: [(String, Float)] = []
        var beepCount = 0
        let player = AttentionSoundPlayer(
            playSystemSound: { name, volume in
                systemCalls.append((name, volume))
                return false
            },
            beep: { beepCount += 1 }
        )

        player.play(soundName: "Ping", volume: 0)
        XCTAssertTrue(systemCalls.isEmpty)
        XCTAssertEqual(beepCount, 0)

        player.play(soundName: "Missing", volume: 4)
        XCTAssertEqual(systemCalls.count, 1)
        XCTAssertEqual(systemCalls[0].0, "Missing")
        XCTAssertEqual(systemCalls[0].1, 1, accuracy: 0.0001)
        XCTAssertEqual(beepCount, 1)
    }

    func testAttentionSoundCandidatesFilterUnavailableSystemSoundsInDisplayOrder() {
        XCTAssertEqual(
            AttentionSound.availableNames { ["Ping", "Pop"].contains($0) },
            ["Ping", "Pop"]
        )
    }

    func testNotificationsPreviewPlaysCurrentSoundAndVolumeWhileAutomaticAlertsAreOff() {
        let suiteName = "FloatTabsTests.NotificationPreview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.attentionSoundEnabled = false
        preferences.attentionSoundName = "Glass"
        preferences.attentionSoundVolume = 0.42
        let player = SoundPlayerSpy()
        let controller = NotificationsSettingsViewController(
            preferencesStore: preferences,
            attentionSoundPlayer: player,
            availableSoundNames: ["Ping", "Glass"]
        )
        controller.loadViewIfNeeded()

        controller.previewButton.performClick(nil)

        XCTAssertEqual(
            player.calls,
            [.init(soundName: "Glass", volume: 0.42)]
        )
        XCTAssertFalse(preferences.attentionSoundEnabled)
        XCTAssertEqual(preferences.attentionSoundName, "Glass")
        XCTAssertEqual(preferences.attentionSoundVolume, 0.42, accuracy: 0.0001)
    }

    /// Invokes an NSControl action exactly the way AppKit would deliver it,
    /// so tests drive the same @objc handler the control is wired to.
    private func performControlAction(on controller: NSObject, control: NSControl) {
        _ = controller.perform(control.action, with: control)
    }

    func testNotificationsSoundSelectionWritesPreferenceAndPreviewsOnce() {
        let suiteName = "FloatTabsTests.SoundSelectionPreview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.attentionSoundName = "Ping"
        preferences.attentionSoundVolume = 0.5
        let player = SoundPlayerSpy()
        let controller = NotificationsSettingsViewController(
            preferencesStore: preferences,
            attentionSoundPlayer: player,
            availableSoundNames: ["Ping", "Glass"]
        )
        controller.loadViewIfNeeded()

        controller.soundPopup.selectItem(withTitle: "Glass")
        performControlAction(on: controller, control: controller.soundPopup)

        XCTAssertEqual(preferences.attentionSoundName, "Glass")
        XCTAssertEqual(
            player.calls,
            [.init(soundName: "Glass", volume: 0.5)]
        )
    }

    func testNotificationsSoundSelectionPreviewsWhileAutomaticAlertsAreOff() {
        let suiteName = "FloatTabsTests.SoundSelectionPreviewOff.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.attentionSoundEnabled = false
        preferences.attentionSoundName = "Ping"
        preferences.attentionSoundVolume = 0.5
        let player = SoundPlayerSpy()
        let controller = NotificationsSettingsViewController(
            preferencesStore: preferences,
            attentionSoundPlayer: player,
            availableSoundNames: ["Ping", "Glass"]
        )
        controller.loadViewIfNeeded()

        controller.soundPopup.selectItem(withTitle: "Glass")
        performControlAction(on: controller, control: controller.soundPopup)

        XCTAssertFalse(preferences.attentionSoundEnabled)
        XCTAssertEqual(preferences.attentionSoundName, "Glass")
        XCTAssertEqual(
            player.calls,
            [.init(soundName: "Glass", volume: 0.5)]
        )
    }

    func testNotificationsVolumeAdjustmentPreviewsOncePerCompletedChange() {
        let suiteName = "FloatTabsTests.VolumePreview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.attentionSoundName = "Purr"
        preferences.attentionSoundVolume = 0.8
        let player = SoundPlayerSpy()
        let controller = NotificationsSettingsViewController(
            preferencesStore: preferences,
            attentionSoundPlayer: player,
            availableSoundNames: ["Purr"]
        )
        controller.loadViewIfNeeded()

        // Non-continuous is what guarantees one preview per completed drag
        // instead of a burst of actions per pixel of movement.
        XCTAssertFalse(controller.volumeSlider.isContinuous)

        controller.volumeSlider.doubleValue = 35
        performControlAction(on: controller, control: controller.volumeSlider)

        XCTAssertEqual(preferences.attentionSoundVolume, 0.35, accuracy: 0.0001)
        XCTAssertEqual(
            player.calls,
            [.init(soundName: "Purr", volume: 0.35)]
        )
    }

    func testNotificationsVolumeZeroAdjustmentStaysCompletelySilent() {
        let suiteName = "FloatTabsTests.VolumeZeroPreview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.attentionSoundName = "Purr"
        preferences.attentionSoundVolume = 0.3
        let player = SoundPlayerSpy()
        let controller = NotificationsSettingsViewController(
            preferencesStore: preferences,
            attentionSoundPlayer: player,
            availableSoundNames: ["Purr"]
        )
        controller.loadViewIfNeeded()

        controller.volumeSlider.doubleValue = 0
        performControlAction(on: controller, control: controller.volumeSlider)

        XCTAssertEqual(preferences.attentionSoundVolume, 0, accuracy: 0.0001)
        // The preview still routes through the shared player seam; the spy
        // observes the request, and the production player contract below is
        // what makes a zero volume inaudible rather than falling back.
        XCTAssertEqual(
            player.calls,
            [.init(soundName: "Purr", volume: 0)]
        )

        var systemCalls: [(String, Float)] = []
        var beepCount = 0
        let realPlayer = AttentionSoundPlayer(
            playSystemSound: { name, volume in
                systemCalls.append((name, volume))
                return false
            },
            beep: { beepCount += 1 }
        )
        realPlayer.play(soundName: "Purr", volume: preferences.attentionSoundVolume)
        XCTAssertTrue(systemCalls.isEmpty)
        XCTAssertEqual(beepCount, 0)
    }

    func testReadyAcknowledgementAndRuntimeResetClearTheDot() {
        let coordinator = WebAttentionCoordinator()
        let profile = makeProfile(name: "GPT")
        let (_, zone) = makeZoneHarness()
        zone.apply(profiles: [profile], activeTabID: profile.id)
        let tab = try! XCTUnwrap(zone.tabView(for: profile.id))

        coordinator.apply(.generationStarted, for: profile.id)
        coordinator.apply(.generationFinished(userVisible: false), for: profile.id)
        synchronize(zone, from: coordinator)
        XCTAssertTrue(tab.isShowingReadyAttention)

        coordinator.acknowledge(slotID: profile.id, userVisible: true)
        synchronize(zone, from: coordinator)
        XCTAssertFalse(tab.isShowingReadyAttention)

        coordinator.apply(.generationStarted, for: profile.id)
        coordinator.apply(.generationFinished(userVisible: false), for: profile.id)
        coordinator.apply(.runtimeReset, for: profile.id)
        synchronize(zone, from: coordinator)
        XCTAssertFalse(tab.isShowingReadyAttention)
    }

    func testMultipleSlotsOnlyReadyIDsDisplayDots() {
        let coordinator = WebAttentionCoordinator()
        let ready = makeProfile(name: "Ready")
        let idle = makeProfile(name: "Idle")
        let generating = makeProfile(name: "Generating")
        let (_, zone) = makeZoneHarness()
        zone.apply(profiles: [ready, idle, generating], activeTabID: ready.id)

        coordinator.apply(.generationStarted, for: ready.id)
        coordinator.apply(.generationFinished(userVisible: false), for: ready.id)
        coordinator.apply(.generationStarted, for: generating.id)
        synchronize(zone, from: coordinator)

        XCTAssertTrue(try! XCTUnwrap(zone.tabView(for: ready.id)).isShowingReadyAttention)
        XCTAssertFalse(try! XCTUnwrap(zone.tabView(for: idle.id)).isShowingReadyAttention)
        XCTAssertFalse(try! XCTUnwrap(zone.tabView(for: generating.id)).isShowingReadyAttention)
    }

    func testReadyProjectionReplacesInsteadOfAccumulating() {
        let first = makeProfile(name: "First")
        let second = makeProfile(name: "Second")
        let (_, zone) = makeZoneHarness()
        zone.apply(profiles: [first, second], activeTabID: first.id)

        zone.setReadySlotIDs([first.id])
        XCTAssertTrue(try! XCTUnwrap(zone.tabView(for: first.id)).isShowingReadyAttention)
        XCTAssertFalse(try! XCTUnwrap(zone.tabView(for: second.id)).isShowingReadyAttention)

        zone.setReadySlotIDs([second.id])
        XCTAssertFalse(try! XCTUnwrap(zone.tabView(for: first.id)).isShowingReadyAttention)
        XCTAssertTrue(try! XCTUnwrap(zone.tabView(for: second.id)).isShowingReadyAttention)

        zone.setReadySlotIDs([])
        XCTAssertFalse(try! XCTUnwrap(zone.tabView(for: first.id)).isShowingReadyAttention)
        XCTAssertFalse(try! XCTUnwrap(zone.tabView(for: second.id)).isShowingReadyAttention)
    }

    func testRemovedSlotHasNoVisibleTabOrReadyDot() {
        let removed = makeProfile(name: "Removed")
        let remaining = makeProfile(name: "Remaining")
        let (_, zone) = makeZoneHarness()
        zone.apply(profiles: [removed, remaining], activeTabID: remaining.id)
        zone.setReadySlotIDs([removed.id])

        zone.apply(profiles: [remaining], activeTabID: remaining.id)

        XCTAssertNil(zone.tabView(for: removed.id))
        XCTAssertNotNil(zone.tabView(for: remaining.id))
    }

    func testRailReapplyKeepsReadyProjectionOnRecreatedAndUpdatedTabs() {
        let coordinator = WebAttentionCoordinator()
        let profile = makeProfile(name: "GPT")
        let (_, zone) = makeZoneHarness()
        coordinator.apply(.generationStarted, for: profile.id)
        coordinator.apply(.generationFinished(userVisible: false), for: profile.id)

        zone.apply(profiles: [profile], activeTabID: profile.id)
        synchronize(zone, from: coordinator)
        XCTAssertTrue(try! XCTUnwrap(zone.tabView(for: profile.id)).isShowingReadyAttention)

        zone.apply(profiles: [profile], activeTabID: nil)
        XCTAssertTrue(try! XCTUnwrap(zone.tabView(for: profile.id)).isShowingReadyAttention)
    }

    func testReadyDotUsesFaviconGeometryAtRestAndMagnifiedWidths() {
        let profile = makeProfile(name: "GPT")
        let (_, zone) = makeZoneHarness()
        zone.apply(profiles: [profile], activeTabID: profile.id)
        zone.setReadySlotIDs([profile.id])
        zone.layoutSubtreeIfNeeded()

        let tab = try! XCTUnwrap(zone.tabView(for: profile.id))
        let restingWidth = tab.frame.width
        let restingIconFrame = tab.iconFrame
        let restingDotFrame = tab.readyAttentionFrame
        XCTAssertEqual(restingWidth, ExternalTabMetrics.collapsedWidth, accuracy: 0.001)
        assertReadyDot(
            restingDotFrame,
            isAttachedTo: restingIconFrame,
            file: #filePath,
            line: #line
        )

        tab.setHovered(true)
        zone.needsLayout = true
        zone.layoutSubtreeIfNeeded()

        let magnifiedIconFrame = tab.iconFrame
        let magnifiedDotFrame = tab.readyAttentionFrame
        XCTAssertEqual(tab.frame.width, ExternalTabMetrics.hoverWidth, accuracy: 0.001)
        XCTAssertEqual(magnifiedIconFrame, restingIconFrame)
        XCTAssertEqual(
            magnifiedDotFrame.offsetBy(
                dx: -magnifiedIconFrame.minX,
                dy: -magnifiedIconFrame.minY
            ),
            restingDotFrame.offsetBy(
                dx: -restingIconFrame.minX,
                dy: -restingIconFrame.minY
            )
        )
        XCTAssertLessThan(magnifiedDotFrame.maxX, tab.bounds.maxX)
    }

    func testReadyDotDoesNotChangeTabWidthOrDockMagnification() {
        let tab = ExternalWebAppTabView(slotID: UUID())
        tab.frame = NSRect(
            x: 0,
            y: 0,
            width: ExternalTabMetrics.collapsedWidth,
            height: ExternalTabMetrics.tabHeight
        )

        tab.setDockInfluence(1)
        let normalWidth = tab.preferredWidth
        tab.setReadyAttention(true)
        XCTAssertEqual(tab.preferredWidth, normalWidth, accuracy: 0.001)

        tab.setHovered(true)
        let hoveredWidth = tab.preferredWidth
        tab.setReadyAttention(false)
        XCTAssertEqual(tab.preferredWidth, hoveredWidth, accuracy: 0.001)
    }

    func testReadyDotIsNonInteractiveAndSemanticRed() {
        let tab = ExternalWebAppTabView(slotID: UUID())
        tab.frame = NSRect(x: 0, y: 0, width: 40, height: 32)
        tab.setReadyAttention(true)
        tab.layoutSubtreeIfNeeded()

        XCTAssertTrue(tab.hitTest(tab.readyAttentionFrame.midPoint) === tab)
        let red = try! XCTUnwrap(
            tab.readyAttentionColor?.usingColorSpace(.deviceRGB)
        )
        XCTAssertGreaterThan(red.redComponent, red.greenComponent)
        XCTAssertGreaterThan(red.redComponent, red.blueComponent)
    }

    func testReadyDotDoesNotChangeResidentOrReleasedFaviconPresentation() {
        let tab = ExternalWebAppTabView(slotID: UUID())

        tab.setResident(true)
        let residentIcon = try! XCTUnwrap(tab.displayedIcon)
        tab.setReadyAttention(true)
        XCTAssertTrue(tab.isResidentRuntime)
        XCTAssertTrue(tab.displayedIcon === residentIcon)

        tab.setResident(false)
        let releasedIcon = try! XCTUnwrap(tab.displayedIcon)
        tab.setReadyAttention(false)
        tab.setReadyAttention(true)
        XCTAssertFalse(tab.isResidentRuntime)
        XCTAssertTrue(tab.displayedIcon === releasedIcon)
        XCTAssertTrue(tab.isShowingReadyAttention)
    }

    func testReadyAttentionIsNotPersistedInWebAppProfile() throws {
        let profile = makeProfile(name: "GPT")
        let data = try JSONEncoder().encode(profile)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertFalse(
            object.keys.contains { key in
                let normalized = key.lowercased()
                return normalized.contains("ready") || normalized.contains("attention")
            }
        )
    }

    private func makeZoneHarness() -> (host: NSView, zone: ExternalControlZoneView) {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 76, height: 820))
        let zone = ExternalControlZoneView(frame: host.bounds)
        host.addSubview(zone)
        zone.layoutSubtreeIfNeeded()
        return (host, zone)
    }

    private func synchronize(
        _ zone: ExternalControlZoneView,
        from coordinator: WebAttentionCoordinator
    ) {
        zone.setReadySlotIDs(coordinator.readySlotIDs)
        zone.layoutSubtreeIfNeeded()
    }

    private func assertReadyDot(
        _ dot: NSRect,
        isAttachedTo icon: NSRect,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(dot.width, 6, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(dot.height, 6, accuracy: 0.001, file: file, line: line)
        XCTAssertGreaterThan(dot.minX, icon.minX, file: file, line: line)
        XCTAssertGreaterThan(dot.minY, icon.minY, file: file, line: line)
        XCTAssertGreaterThanOrEqual(dot.maxX, icon.maxX, file: file, line: line)
        XCTAssertGreaterThanOrEqual(dot.maxY, icon.maxY, file: file, line: line)
    }

    private func makeProfile(name: String) -> WebAppProfile {
        WebAppProfile(
            order: 0,
            name: name,
            homeURL: URL(string: "https://example.com/\(name)")!
        )
    }
}

private extension NSRect {
    var midPoint: NSPoint {
        NSPoint(x: midX, y: midY)
    }
}
