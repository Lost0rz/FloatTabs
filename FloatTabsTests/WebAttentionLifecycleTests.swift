import AppKit
import XCTest
@testable import FloatTabs

@MainActor
final class WebAttentionLifecycleTests: XCTestCase {
    private var retainedContainers: [WebPanelContainerView] = []

    func testInactiveColdAttentionProtectedSurvivesColdDelay() async throws {
        let pool = makePool()
        let profile = makeProfile(name: "ProtectedCold", policy: .cold)
        _ = pool.webView(for: profile)
        var attentionProtected = true
        let lifecycle = makeLifecycle(
            pool: pool,
            coldReleaseDelay: 0.02,
            attentionProtectionQuery: { _ in attentionProtected }
        )

        makeInactive(lifecycle, profile: profile)
        try await wait(milliseconds: 70)

        XCTAssertTrue(pool.contains(slotID: profile.id))
        attentionProtected = false
    }

    func testInactiveWarmAttentionProtectedSurvivesWarmTTL() async throws {
        let pool = makePool()
        let profile = makeProfile(name: "ProtectedWarm", policy: .warm)
        _ = pool.webView(for: profile)
        let lifecycle = makeLifecycle(
            pool: pool,
            warmReleaseDelay: 0.02,
            attentionProtectionQuery: { _ in true }
        )

        makeInactive(lifecycle, profile: profile)
        try await wait(milliseconds: 70)

        XCTAssertTrue(pool.contains(slotID: profile.id))
    }

    func testGeneratingToReadyWhileInactiveRemainsProtected() async throws {
        let pool = makePool()
        let profile = makeProfile(name: "GeneratingReady", policy: .cold)
        _ = pool.webView(for: profile)
        let coordinator = WebAttentionCoordinator()
        let lifecycle = makeLifecycle(
            pool: pool,
            coldReleaseDelay: 0.02,
            attentionProtectionQuery: { _ in coordinator.isAttentionProtected(profile.id) }
        )

        coordinator.apply(.generationStarted, for: profile.id)
        makeInactive(lifecycle, profile: profile)
        coordinator.apply(
            .generationFinished(userVisible: false),
            for: profile.id
        )
        try await wait(milliseconds: 70)

        XCTAssertEqual(coordinator.state(for: profile.id), .ready)
        XCTAssertTrue(pool.contains(slotID: profile.id))
    }

    func testReleaseTimerCreatedBeforeGenerationStartsCannotReleaseProtectedSlot() async throws {
        let pool = makePool()
        let profile = makeProfile(name: "LateGeneration", policy: .cold)
        _ = pool.webView(for: profile)
        let coordinator = WebAttentionCoordinator()
        let lifecycle = makeLifecycle(
            pool: pool,
            coldReleaseDelay: 0.03,
            attentionProtectionQuery: { _ in coordinator.isAttentionProtected(profile.id) }
        )

        makeInactive(lifecycle, profile: profile)
        coordinator.apply(.generationStarted, for: profile.id)
        try await wait(milliseconds: 80)

        XCTAssertTrue(pool.contains(slotID: profile.id))
        XCTAssertEqual(coordinator.state(for: profile.id), .generating)
    }

    func testAttentionProtectedWarmIsExcludedAndOldestEligibleWarmIsEvicted() {
        let pool = makePool()
        let protected = makeProfile(name: "Protected", policy: .warm)
        let eligibleB = makeProfile(name: "EligibleB", policy: .warm)
        let eligibleC = makeProfile(name: "EligibleC", policy: .warm)
        [protected, eligibleB, eligibleC].forEach { _ = pool.webView(for: $0) }
        let protectedIDs: Set<UUID> = [protected.id]
        let lifecycle = makeLifecycle(
            pool: pool,
            warmReleaseDelay: 60,
            warmResidentLimit: 1,
            attentionProtectionQuery: { protectedIDs.contains($0) }
        )

        makeInactive(lifecycle, profile: protected)
        makeInactive(lifecycle, profile: eligibleB)
        makeInactive(lifecycle, profile: eligibleC)

        XCTAssertTrue(pool.contains(slotID: protected.id))
        XCTAssertFalse(pool.contains(slotID: eligibleB.id))
        XCTAssertTrue(pool.contains(slotID: eligibleC.id))
    }

    func testMemoryWarningEvictsEligibleWarmButNotAttentionProtectedWarm() {
        let pool = makePool()
        let protected = makeProfile(name: "WarningProtected", policy: .warm)
        let eligibleB = makeProfile(name: "WarningB", policy: .warm)
        let eligibleC = makeProfile(name: "WarningC", policy: .warm)
        [protected, eligibleB, eligibleC].forEach { _ = pool.webView(for: $0) }
        let lifecycle = makeLifecycle(
            pool: pool,
            warmResidentLimit: 2,
            attentionProtectionQuery: { $0 == protected.id }
        )

        makeInactive(lifecycle, profile: protected)
        makeInactive(lifecycle, profile: eligibleB)
        makeInactive(lifecycle, profile: eligibleC)
        lifecycle.handleMemoryPressure(.warning)

        XCTAssertTrue(pool.contains(slotID: protected.id))
        XCTAssertFalse(pool.contains(slotID: eligibleB.id))
        XCTAssertTrue(pool.contains(slotID: eligibleC.id))
    }

    func testMemoryCriticalEvictsEligibleWarmButNotAttentionProtectedWarm() {
        let pool = makePool()
        let protected = makeProfile(name: "CriticalProtected", policy: .warm)
        let eligible = makeProfile(name: "CriticalEligible", policy: .warm)
        [protected, eligible].forEach { _ = pool.webView(for: $0) }
        let lifecycle = makeLifecycle(
            pool: pool,
            warmResidentLimit: 2,
            attentionProtectionQuery: { $0 == protected.id }
        )

        makeInactive(lifecycle, profile: protected)
        makeInactive(lifecycle, profile: eligible)
        lifecycle.handleMemoryPressure(.critical)

        XCTAssertTrue(pool.contains(slotID: protected.id))
        XCTAssertFalse(pool.contains(slotID: eligible.id))
    }

    func testAttentionOnlyProtectionBlocksRelease() async throws {
        let pool = makePool()
        let profile = makeProfile(name: "AttentionOnly", policy: .cold)
        _ = pool.webView(for: profile)
        let lifecycle = makeLifecycle(
            pool: pool,
            coldReleaseDelay: 0.02,
            attentionProtectionQuery: { _ in true }
        )

        makeInactive(lifecycle, profile: profile)
        try await wait(milliseconds: 70)

        XCTAssertTrue(pool.contains(slotID: profile.id))
        XCTAssertTrue(lifecycle.mediaProtectedIDs.isEmpty)
    }

    func testMediaOnlyProtectionStillWorks() async throws {
        let pool = makePool()
        var profile = makeProfile(name: "MediaOnly", policy: .cold)
        profile.backgroundMediaPolicy = .allowBackgroundAudio
        _ = pool.webView(for: profile)
        var mediaPlaying = true
        let lifecycle = makeLifecycle(
            pool: pool,
            coldReleaseDelay: 0.03,
            mediaProtectionPollDelay: 0.005,
            mediaPlayingQuery: { _, completion in completion(mediaPlaying) }
        )

        makeInactive(lifecycle, profile: profile)
        try await wait(milliseconds: 70)
        XCTAssertTrue(pool.contains(slotID: profile.id))

        mediaPlaying = false
        try await wait(milliseconds: 15)
        XCTAssertTrue(pool.contains(slotID: profile.id))
        try await wait(milliseconds: 60)
        XCTAssertFalse(pool.contains(slotID: profile.id))
    }

    func testRemovingAttentionAloneDoesNotBypassMediaProtection() async throws {
        let pool = makePool()
        var profile = makeProfile(name: "MediaWins", policy: .cold)
        profile.backgroundMediaPolicy = .allowBackgroundAudio
        _ = pool.webView(for: profile)
        var attentionProtected = true
        var mediaPlaying = true
        let lifecycle = makeLifecycle(
            pool: pool,
            coldReleaseDelay: 0.03,
            mediaProtectionPollDelay: 0.005,
            mediaPlayingQuery: { _, completion in completion(mediaPlaying) },
            attentionProtectionQuery: { _ in attentionProtected }
        )

        makeInactive(lifecycle, profile: profile)
        try await wait(milliseconds: 30)
        attentionProtected = false
        lifecycle.restartAfterAttentionProtectionEnded(profile: profile)
        try await wait(milliseconds: 50)
        XCTAssertTrue(pool.contains(slotID: profile.id))

        mediaPlaying = false
        try await wait(milliseconds: 15)
        XCTAssertTrue(pool.contains(slotID: profile.id))
        try await wait(milliseconds: 60)
        XCTAssertFalse(pool.contains(slotID: profile.id))
    }

    func testRemovingMediaAloneDoesNotBypassAttentionProtection() async throws {
        let pool = makePool()
        var profile = makeProfile(name: "AttentionWins", policy: .cold)
        profile.backgroundMediaPolicy = .allowBackgroundAudio
        _ = pool.webView(for: profile)
        var attentionProtected = true
        var mediaPlaying = true
        let lifecycle = makeLifecycle(
            pool: pool,
            coldReleaseDelay: 0.03,
            mediaProtectionPollDelay: 0.005,
            mediaPlayingQuery: { _, completion in completion(mediaPlaying) },
            attentionProtectionQuery: { _ in attentionProtected }
        )

        makeInactive(lifecycle, profile: profile)
        try await wait(milliseconds: 30)
        mediaPlaying = false
        try await wait(milliseconds: 60)
        XCTAssertTrue(pool.contains(slotID: profile.id))

        attentionProtected = false
        lifecycle.restartAfterAttentionProtectionEnded(profile: profile)
        try await wait(milliseconds: 15)
        XCTAssertTrue(pool.contains(slotID: profile.id))
        try await wait(milliseconds: 60)
        XCTAssertFalse(pool.contains(slotID: profile.id))
    }

    func testColdRestartAfterSkippedTimerGetsFullFreshDelay() async throws {
        let pool = makePool()
        let profile = makeProfile(name: "ColdRestart", policy: .cold)
        _ = pool.webView(for: profile)
        var attentionProtected = false
        let lifecycle = makeLifecycle(
            pool: pool,
            coldReleaseDelay: 0.04,
            attentionProtectionQuery: { _ in attentionProtected }
        )

        makeInactive(lifecycle, profile: profile)
        attentionProtected = true
        try await wait(milliseconds: 80)
        XCTAssertTrue(pool.contains(slotID: profile.id))

        attentionProtected = false
        lifecycle.restartAfterAttentionProtectionEnded(profile: profile)
        try await wait(milliseconds: 15)
        XCTAssertTrue(pool.contains(slotID: profile.id))
        try await wait(milliseconds: 60)
        XCTAssertFalse(pool.contains(slotID: profile.id))
    }

    func testWarmRestartAfterSkippedTTLGetsFullFreshTTL() async throws {
        let pool = makePool()
        let profile = makeProfile(name: "WarmRestart", policy: .warm)
        _ = pool.webView(for: profile)
        var attentionProtected = false
        let lifecycle = makeLifecycle(
            pool: pool,
            warmReleaseDelay: 0.04,
            attentionProtectionQuery: { _ in attentionProtected }
        )

        makeInactive(lifecycle, profile: profile)
        attentionProtected = true
        try await wait(milliseconds: 80)
        XCTAssertTrue(pool.contains(slotID: profile.id))

        attentionProtected = false
        lifecycle.restartAfterAttentionProtectionEnded(profile: profile)
        try await wait(milliseconds: 15)
        XCTAssertTrue(pool.contains(slotID: profile.id))
        try await wait(milliseconds: 60)
        XCTAssertFalse(pool.contains(slotID: profile.id))
    }

    func testWarmRestartRefreshesRecencyForLaterLRUEviction() {
        let pool = makePool()
        let first = makeProfile(name: "First", policy: .warm)
        let second = makeProfile(name: "Second", policy: .warm)
        let third = makeProfile(name: "Third", policy: .warm)
        [first, second, third].forEach { _ = pool.webView(for: $0) }
        var protectedIDs: Set<UUID> = [first.id]
        let lifecycle = makeLifecycle(
            pool: pool,
            warmReleaseDelay: 60,
            warmResidentLimit: 2,
            attentionProtectionQuery: { protectedIDs.contains($0) }
        )

        makeInactive(lifecycle, profile: first)
        makeInactive(lifecycle, profile: second)
        protectedIDs.remove(first.id)
        lifecycle.restartAfterAttentionProtectionEnded(profile: first)
        makeInactive(lifecycle, profile: third)

        XCTAssertTrue(pool.contains(slotID: first.id))
        XCTAssertFalse(pool.contains(slotID: second.id))
        XCTAssertTrue(pool.contains(slotID: third.id))
    }

    func testSelectedHiddenGeneratingKeepsHiddenGraceAndThenProtectsInactiveRuntime() async throws {
        let pool = makePool()
        let profile = makeProfile(name: "HiddenGenerating", policy: .cold)
        _ = pool.webView(for: profile)
        let lifecycle = makeLifecycle(
            pool: pool,
            coldReleaseDelay: 0.02,
            hiddenActiveGraceDelay: 0.02,
            attentionProtectionQuery: { _ in true }
        )

        lifecycle.setPanelVisible(true, activeProfile: profile)
        lifecycle.activate(profile: profile)
        lifecycle.setPanelVisible(false, activeProfile: profile)
        try await wait(milliseconds: 15)
        XCTAssertTrue(pool.contains(slotID: profile.id))
        XCTAssertTrue(lifecycle.isHiddenActiveGracePending)

        try await wait(milliseconds: 80)
        XCTAssertFalse(lifecycle.isHiddenActiveGracePending)
        XCTAssertEqual(lifecycle.pendingColdReleaseCount, 1)
        XCTAssertTrue(pool.contains(slotID: profile.id))
    }

    func testHotAttentionProtectedSlotGetsNoNewReleasePlan() async throws {
        let pool = makePool()
        let profile = makeProfile(name: "HotGenerating", policy: .hot)
        _ = pool.webView(for: profile)
        let lifecycle = makeLifecycle(
            pool: pool,
            attentionProtectionQuery: { _ in true }
        )

        makeInactive(lifecycle, profile: profile)
        try await wait(milliseconds: 50)

        XCTAssertEqual(lifecycle.pendingColdReleaseCount, 0)
        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 0)
        XCTAssertTrue(pool.contains(slotID: profile.id))
    }

    func testVisibleGeneratingFinishesIdleWithoutInactivePlan() {
        let pool = makePool()
        let profile = makeProfile(name: "VisibleFinish", policy: .cold)
        _ = pool.webView(for: profile)
        let coordinator = WebAttentionCoordinator()
        let lifecycle = makeLifecycle(
            pool: pool,
            coldReleaseDelay: 0.02,
            attentionProtectionQuery: { _ in coordinator.isAttentionProtected(profile.id) }
        )

        lifecycle.setPanelVisible(true, activeProfile: profile)
        lifecycle.activate(profile: profile)
        coordinator.apply(.generationStarted, for: profile.id)
        coordinator.apply(
            .generationFinished(userVisible: true),
            for: profile.id
        )

        XCTAssertEqual(coordinator.state(for: profile.id), .idle)
        XCTAssertEqual(lifecycle.pendingColdReleaseCount, 0)
    }

    func testReadyAcknowledgementWhileVisibleDoesNotCreateInactiveTimer() async throws {
        let pool = makePool()
        let profile = makeProfile(name: "ReadyAcknowledged", policy: .cold)
        _ = pool.webView(for: profile)
        let coordinator = WebAttentionCoordinator()
        coordinator.apply(.generationStarted, for: profile.id)
        coordinator.apply(
            .generationFinished(userVisible: false),
            for: profile.id
        )
        let lifecycle = makeLifecycle(
            pool: pool,
            coldReleaseDelay: 0.02,
            attentionProtectionQuery: { _ in coordinator.isAttentionProtected(profile.id) }
        )

        lifecycle.setPanelVisible(true, activeProfile: profile)
        lifecycle.activate(profile: profile)
        coordinator.acknowledge(slotID: profile.id, userVisible: true)
        lifecycle.restartAfterAttentionProtectionEnded(profile: profile)

        XCTAssertEqual(lifecycle.pendingColdReleaseCount, 0)
        lifecycle.deactivate(profile: profile)
        XCTAssertEqual(lifecycle.pendingColdReleaseCount, 1)
        try await wait(milliseconds: 70)
        XCTAssertFalse(pool.contains(slotID: profile.id))
    }

    func testMultipleSlotsRemainIsolatedAcrossAttentionProtection() async throws {
        let pool = makePool()
        let protected = makeProfile(name: "IsolatedProtected", policy: .cold)
        let ordinary = makeProfile(name: "IsolatedOrdinary", policy: .cold)
        [protected, ordinary].forEach { _ = pool.webView(for: $0) }
        let lifecycle = makeLifecycle(
            pool: pool,
            coldReleaseDelay: 0.02,
            attentionProtectionQuery: { $0 == protected.id }
        )

        makeInactive(lifecycle, profile: protected)
        makeInactive(lifecycle, profile: ordinary)
        try await wait(milliseconds: 70)

        XCTAssertTrue(pool.contains(slotID: protected.id))
        XCTAssertFalse(pool.contains(slotID: ordinary.id))
    }

    func testStaleTimerCallbackCannotReleaseSlotAfterAttentionStarts() async throws {
        let pool = makePool()
        let profile = makeProfile(name: "StaleTimer", policy: .warm)
        _ = pool.webView(for: profile)
        var attentionProtected = false
        let lifecycle = makeLifecycle(
            pool: pool,
            warmReleaseDelay: 0.02,
            attentionProtectionQuery: { _ in attentionProtected }
        )

        makeInactive(lifecycle, profile: profile)
        try await wait(milliseconds: 10)
        attentionProtected = true
        try await wait(milliseconds: 60)

        XCTAssertTrue(pool.contains(slotID: profile.id))
    }

    func testStaleAsyncMediaResultCannotReleaseNewlyAttentionProtectedSlot() async throws {
        let pool = makePool()
        var profile = makeProfile(name: "StaleMedia", policy: .cold)
        profile.backgroundMediaPolicy = .allowBackgroundAudio
        _ = pool.webView(for: profile)
        var pendingMediaResult: ((Bool) -> Void)?
        var attentionProtected = false
        let lifecycle = makeLifecycle(
            pool: pool,
            coldReleaseDelay: 0.02,
            mediaPlayingQuery: { _, completion in
                pendingMediaResult = completion
            },
            attentionProtectionQuery: { _ in attentionProtected }
        )

        makeInactive(lifecycle, profile: profile)
        XCTAssertNotNil(pendingMediaResult)
        attentionProtected = true
        pendingMediaResult?(false)
        try await wait(milliseconds: 70)

        XCTAssertTrue(pool.contains(slotID: profile.id))
    }

    private func makePool() -> WebViewPool {
        WebViewPool(onURLChange: { _, _ in }, initialLoad: { _, _ in })
    }

    private func makeLifecycle(
        pool: WebViewPool,
        coldReleaseDelay: TimeInterval = 30,
        warmReleaseDelay: TimeInterval = 120,
        hiddenActiveGraceDelay: TimeInterval = 120,
        mediaProtectionPollDelay: TimeInterval = 0.01,
        warmResidentLimit: Int = 2,
        mediaPlayingQuery: SlotLifecycleCoordinator.MediaPlayingQuery? = nil,
        attentionProtectionQuery: @escaping SlotLifecycleCoordinator.AttentionProtectionQuery = { _ in false }
    ) -> SlotLifecycleCoordinator {
        let container = WebPanelContainerView(
            frame: NSRect(x: 0, y: 0, width: 430, height: 820)
        )
        retainedContainers.append(container)
        return SlotLifecycleCoordinator(
            webViewPool: pool,
            container: container,
            coldReleaseDelay: coldReleaseDelay,
            warmReleaseDelay: warmReleaseDelay,
            hiddenActiveGraceDelay: hiddenActiveGraceDelay,
            mediaProtectionPollDelay: mediaProtectionPollDelay,
            warmResidentLimit: warmResidentLimit,
            mediaPlayingQuery: mediaPlayingQuery,
            attentionProtectionQuery: attentionProtectionQuery,
            installsMemoryPressureSource: false
        )
    }

    private func makeInactive(
        _ lifecycle: SlotLifecycleCoordinator,
        profile: WebAppProfile
    ) {
        lifecycle.setPanelVisible(true, activeProfile: nil)
        lifecycle.activate(profile: profile)
        lifecycle.deactivate(profile: profile)
    }

    private func makeProfile(
        name: String,
        policy: SlotResidencyPolicy
    ) -> WebAppProfile {
        var profile = WebAppProfile(
            order: 0,
            name: name,
            homeURL: URL(string: "https://example.com/\(name)")!
        )
        profile.residencyPolicy = policy
        return profile
    }

    private func wait(milliseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }
}
