import AppKit
import Dispatch
import XCTest
@testable import FloatTabs

@MainActor
final class WebAttentionLifecycleTests: XCTestCase {
    private var retainedContainers: [WebPanelContainerView] = []

    func testInactiveColdAttentionProtectedSurvivesColdDelay() async throws {
        let pool = makePool()
        let profile = makeProfile(name: "ProtectedCold", policy: .cold)
        _ = try pool.webView(for: profile)
        var attentionProtected = true
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 0.02,
            attentionProtectionQuery: { _ in attentionProtected }
        )

        makeInactive(lifecycle, profile: profile)
        try await wait(milliseconds: 70)

        XCTAssertTrue(pool.contains(slotID: profile.id))
        attentionProtected = false
    }

    func testRuntimeReleasePreparationRunsBeforeWebViewHibernate() async throws {
        let pool = makePool()
        let profile = makeProfile(name: "ReleaseOrder", policy: .cold)
        _ = try pool.webView(for: profile)
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        var wasResidentDuringPreparation = false
        var releasedProfile: WebAppProfile?
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 0.02,
            prepareRuntimeForRelease: { preparedSlotID in
                wasResidentDuringPreparation = pool.contains(slotID: preparedSlotID)
            },
            onRuntimeReleased: { profile in
                releasedProfile = profile
            },
            diagnostics: diagnostics
        )

        makeInactive(lifecycle, profile: profile)
        try await wait(milliseconds: 70)

        XCTAssertTrue(wasResidentDuringPreparation)
        XCTAssertEqual(releasedProfile?.id, profile.id)
        XCTAssertFalse(pool.contains(slotID: profile.id))
        let release = try XCTUnwrap(writer.events.first { $0.event == "slot_lifecycle.hibernate" })
        let cancelled = try XCTUnwrap(
            writer.events.first { $0.event == "slot_lifecycle.inactive_plan.cancelled" }
        )
        XCTAssertEqual(release.fields["inactive_plan_id"], cancelled.fields["inactive_plan_id"])
        XCTAssertNil(release.fields["plan_token"])
        XCTAssertNil(cancelled.fields["plan_token"])
    }

    func testHidingPanelNotifiesBackgroundPolicyBeforeHiddenGraceRelease() async throws {
        let pool = makePool()
        let profile = makeProfile(name: "HiddenPanel", policy: .warm)
        _ = try pool.webView(for: profile)
        var becameInactiveCount = 0
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 60,
            hiddenActiveGraceDelay: 0.06,
            onSlotBecameInactive: { _ in
                becameInactiveCount += 1
            }
        )

        lifecycle.setPanelVisible(true, activeProfile: profile)
        lifecycle.activate(profile: profile)
        lifecycle.setPanelVisible(false, activeProfile: profile)

        XCTAssertEqual(becameInactiveCount, 1)
        XCTAssertTrue(pool.contains(slotID: profile.id))
        XCTAssertTrue(lifecycle.isHiddenActiveGracePending)

        try await wait(milliseconds: 20)
        XCTAssertTrue(pool.contains(slotID: profile.id))
    }

    func testInactiveWarmAttentionProtectedSurvivesWarmTTL() async throws {
        let pool = makePool()
        let profile = makeProfile(name: "ProtectedWarm", policy: .warm)
        _ = try pool.webView(for: profile)
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 0.02,
            attentionProtectionQuery: { _ in true }
        )

        makeInactive(lifecycle, profile: profile)
        try await wait(milliseconds: 70)

        XCTAssertTrue(pool.contains(slotID: profile.id))
    }

    func testFiveInactiveAutomaticRuntimesRemainResidentUnderNormalPressure() throws {
        let pool = makePool()
        let profiles = [
            makeProfile(name: "WarmOne", policy: .warm),
            makeProfile(name: "WarmTwo", policy: .warm),
            makeProfile(name: "WarmThree", policy: .warm),
            makeProfile(name: "WarmFour", policy: .warm),
            makeProfile(name: "WarmFive", policy: .warm)
        ]
        for profile in profiles {
            _ = try pool.webView(for: profile)
        }
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 600,
            diagnostics: diagnostics
        )

        for profile in profiles {
            makeInactive(lifecycle, profile: profile)
        }

        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 5)
        XCTAssertEqual(pool.count, 5)
        XCTAssertEqual(profiles.filter { pool.contains(slotID: $0.id) }.count, 5)
        XCTAssertNil(lifecycle.diagnosticSnapshotFields(for: profiles[0].id)[
            "lifecycle_managed_resident_target"
        ])
        XCTAssertFalse(writer.events.contains { $0.event == "slot_lifecycle.runtime_budget" })
    }

    func testKeepLoadedRemainsResidentPastNormalLongIdleBoundary() async throws {
        let pool = makePool()
        let profile = makeProfile(name: "KeepLoadedLongIdle", policy: .hot)
        _ = try pool.webView(for: profile)
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 0.02
        )

        makeInactive(lifecycle, profile: profile)
        try await wait(milliseconds: 80)

        XCTAssertTrue(pool.contains(slotID: profile.id))
        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 0)
        XCTAssertNil(lifecycle.debugInactivePlanToken(slotID: profile.id))
    }

    func testMemoryWarningProgressivelyReclaimsOneEligibleAutomaticPerStep() async throws {
        let pool = makePool()
        let profiles = [
            makeProfile(name: "WarningOne", policy: .warm),
            makeProfile(name: "WarningTwo", policy: .warm),
            makeProfile(name: "WarningThree", policy: .warm)
        ]
        for profile in profiles { _ = try pool.webView(for: profile) }
        var releasedSlotIDs: [UUID] = []
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 600,
            pressureStepDelay: 0.03,
            onRuntimeReleased: { releasedSlotIDs.append($0.id) }
        )
        for profile in profiles { makeInactive(lifecycle, profile: profile) }

        XCTAssertEqual(pool.count, 3)
        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 3)
        // Normal pressure has no count-based reclaim path.
        let baselineReleasedCount = releasedSlotIDs.count
        XCTAssertEqual(baselineReleasedCount, 0)
        let expectedOrder = profiles.sorted {
            let lhs = lifecycle.debugInactiveSinceUptime(slotID: $0.id) ?? .infinity
            let rhs = lifecycle.debugInactiveSinceUptime(slotID: $1.id) ?? .infinity
            return lhs == rhs ? $0.id.uuidString < $1.id.uuidString : lhs < rhs
        }.map(\.id)
        lifecycle.handleMemoryPressure(.warning)

        // One reclaim transaction per step: exactly one Runtime is gone
        // synchronously; the rest may only follow through continuation steps.
        XCTAssertEqual(pool.count, 2)
        XCTAssertEqual(releasedSlotIDs.count, baselineReleasedCount + 1)

        let fullyReclaimed = try await waitUntil { pool.count == 0 }
        XCTAssertTrue(fullyReclaimed)

        // Sustained warning reclaims every eligible Automatic exactly once.
        XCTAssertEqual(releasedSlotIDs, expectedOrder)
        XCTAssertEqual(Set(releasedSlotIDs).count, profiles.count)
        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 0)
    }

    func testWarningThenNormalPressureCancelsPendingContinuation() async throws {
        let pool = makePool()
        let profiles = [
            makeProfile(name: "NormalStopOne", policy: .warm),
            makeProfile(name: "NormalStopTwo", policy: .warm)
        ]
        for profile in profiles { _ = try pool.webView(for: profile) }
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 600,
            pressureStepDelay: 0.25
        )
        for profile in profiles { makeInactive(lifecycle, profile: profile) }

        XCTAssertEqual(pool.count, 2)
        lifecycle.handleMemoryPressure(.warning)
        XCTAssertEqual(pool.count, 1)

        // Pressure clears before the next continuation step fires.
        lifecycle.handleMemoryPressureNormalized()
        try await wait(milliseconds: 600)

        // The not-yet-started continuation is cancelled: the second Runtime
        // stays resident, and pressure reclaim performs no mass restore.
        XCTAssertEqual(pool.count, 1)
        XCTAssertFalse(pool.contains(slotID: releasedFirst(of: profiles, in: pool)))
        XCTAssertTrue(pool.contains(slotID: residentSecond(of: profiles, in: pool)))
    }

    private func releasedFirst(
        of profiles: [WebAppProfile],
        in pool: WebViewPool
    ) -> UUID {
        profiles.first { !pool.contains(slotID: $0.id) }!.id
    }

    private func residentSecond(
        of profiles: [WebAppProfile],
        in pool: WebViewPool
    ) -> UUID {
        profiles.first { pool.contains(slotID: $0.id) }!.id
    }

    func testGeneratingToReadyWhileInactiveCanReleaseAfterProtectionEnds() async throws {
        let pool = makePool()
        let profile = makeProfile(name: "GeneratingReady", policy: .cold)
        _ = try pool.webView(for: profile)
        let coordinator = WebAttentionCoordinator()
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 0.02,
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
        XCTAssertFalse(coordinator.isAttentionProtected(profile.id))
        XCTAssertFalse(pool.contains(slotID: profile.id))
    }

    func testReleaseTimerCreatedBeforeGenerationStartsCannotReleaseProtectedSlot() async throws {
        let pool = makePool()
        let profile = makeProfile(name: "LateGeneration", policy: .cold)
        _ = try pool.webView(for: profile)
        let coordinator = WebAttentionCoordinator()
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 0.03,
            attentionProtectionQuery: { _ in coordinator.isAttentionProtected(profile.id) }
        )

        makeInactive(lifecycle, profile: profile)
        coordinator.apply(.generationStarted, for: profile.id)
        try await wait(milliseconds: 80)

        XCTAssertTrue(pool.contains(slotID: profile.id))
        XCTAssertEqual(coordinator.state(for: profile.id), .generating)
    }

    func testMemoryWarningProgressivelyReclaimsEligibleButPreservesAttentionProtected() async throws {
        let pool = makePool()
        let protected = makeProfile(name: "Protected", policy: .warm)
        let eligibleB = makeProfile(name: "EligibleB", policy: .warm)
        let eligibleC = makeProfile(name: "EligibleC", policy: .warm)
        for profile in [protected, eligibleB, eligibleC] {
            _ = try pool.webView(for: profile)
        }
        let protectedIDs: Set<UUID> = [protected.id]
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 60,
            pressureStepDelay: 0.03,
            attentionProtectionQuery: { protectedIDs.contains($0) }
        )

        makeInactive(lifecycle, profile: protected)
        makeInactive(lifecycle, profile: eligibleB)
        makeInactive(lifecycle, profile: eligibleC)
        lifecycle.handleMemoryPressure(.warning)

        let eligibleReclaimed = try await waitUntil {
            !pool.contains(slotID: eligibleB.id) && !pool.contains(slotID: eligibleC.id)
        }
        XCTAssertTrue(eligibleReclaimed)
        XCTAssertTrue(pool.contains(slotID: protected.id))
        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 1)
    }

    func testMemoryWarningProgressivelyReclaimsEligibleButPreservesMediaProtected() async throws {
        let pool = makePool()
        var protected = makeProfile(name: "WarningMediaProtected", policy: .warm)
        protected.backgroundMediaPolicy = .allowBackgroundAudio
        let eligibleB = makeProfile(name: "WarningB", policy: .warm)
        let eligibleC = makeProfile(name: "WarningC", policy: .warm)
        for profile in [protected, eligibleB, eligibleC] {
            _ = try pool.webView(for: profile)
        }
        let lifecycle = makeLifecycle(
            pool: pool,
            pressureStepDelay: 0.03,
            mediaPlayingQuery: { _, completion in completion(true) }
        )

        makeInactive(lifecycle, profile: protected)
        makeInactive(lifecycle, profile: eligibleB)
        makeInactive(lifecycle, profile: eligibleC)
        lifecycle.handleMemoryPressure(.warning)

        let eligibleReclaimed = try await waitUntil {
            !pool.contains(slotID: eligibleB.id) && !pool.contains(slotID: eligibleC.id)
        }
        XCTAssertTrue(eligibleReclaimed)
        XCTAssertTrue(pool.contains(slotID: protected.id))
        XCTAssertTrue(lifecycle.mediaProtectedIDs.contains(protected.id))
        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 1)
    }

    func testMemoryWarningPreservesActiveVisibleWarmRuntime() throws {
        let pool = makePool()
        let profile = makeProfile(name: "WarningActiveVisible", policy: .warm)
        _ = try pool.webView(for: profile)
        let lifecycle = makeLifecycle(pool: pool)

        lifecycle.setPanelVisible(true, activeProfile: profile)
        lifecycle.activate(profile: profile)
        lifecycle.handleMemoryPressure(.warning)

        XCTAssertTrue(pool.contains(slotID: profile.id))
        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 0)
    }

    func testMemoryWarningPreservesHotRuntime() throws {
        let pool = makePool()
        let profile = makeProfile(name: "WarningHot", policy: .hot)
        _ = try pool.webView(for: profile)
        let lifecycle = makeLifecycle(pool: pool)

        makeInactive(lifecycle, profile: profile)
        lifecycle.handleMemoryPressure(.warning)

        XCTAssertTrue(pool.contains(slotID: profile.id))
        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 0)
    }

    func testMemoryWarningPreservesGeneratingAndEligibleWarmRuntimes() throws {
        let pool = makePool()
        let generating = makeProfile(name: "WarningGenerating", policy: .warm)
        let ready = makeProfile(name: "WarningReady", policy: .warm)
        for profile in [generating, ready] {
            _ = try pool.webView(for: profile)
        }
        let coordinator = WebAttentionCoordinator()
        let lifecycle = makeLifecycle(
            pool: pool,
            attentionProtectionQuery: { slotID in
                coordinator.isAttentionProtected(slotID)
            }
        )

        coordinator.apply(.generationStarted, for: generating.id)
        makeInactive(lifecycle, profile: generating)

        coordinator.apply(.generationStarted, for: ready.id)
        makeInactive(lifecycle, profile: ready)
        coordinator.apply(
            .generationFinished(userVisible: false),
            for: ready.id
        )

        lifecycle.handleMemoryPressure(.warning)

        XCTAssertEqual(coordinator.state(for: generating.id), .generating)
        XCTAssertEqual(coordinator.state(for: ready.id), .ready)
        XCTAssertTrue(pool.contains(slotID: generating.id))
        XCTAssertFalse(pool.contains(slotID: ready.id))
        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 1)
    }

    func testMemoryWarningWithoutEligibleCandidateIsObserveOnlyAndHasNoReleaseEvidence() throws {
        let pool = makePool()
        let profile = makeProfile(name: "WarningDiagnostic", policy: .warm)
        _ = try pool.webView(for: profile)
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        let lifecycle = makeLifecycle(
            pool: pool,
            attentionProtectionQuery: { _ in true },
            diagnostics: diagnostics
        )

        makeInactive(lifecycle, profile: profile)
        lifecycle.handleMemoryPressure(.warning)

        let evaluation = try XCTUnwrap(
            writer.events.first {
                $0.event == "slot_lifecycle.memory_pressure_slot"
                    && $0.fields["action"] == nil
            }
        )
        XCTAssertEqual(evaluation.fields["pressure_level"], .string("warning"))
        XCTAssertEqual(evaluation.fields["release_eligible"], .bool(false))
        XCTAssertEqual(evaluation.fields["decision"], .string("observe"))
        XCTAssertEqual(
            evaluation.fields["release_reason"],
            .string("warning_diagnostics_only")
        )
        XCTAssertTrue(writer.events.contains { event in
            event.event == "slot_lifecycle.memory_pressure.no_candidate"
        })
        XCTAssertFalse(writer.events.contains { event in
            event.event == "slot_lifecycle.hibernate"
        })
        XCTAssertFalse(writer.events.contains { event in
            event.fields["release_reason"] == .string("warning_pressure_eligible")
        })
    }

    func testMemoryCriticalDiagnosticReportsTruthfulHibernateCompletion() throws {
        let pool = makePool()
        let profile = makeProfile(name: "CriticalDiagnostic", policy: .warm)
        _ = try pool.webView(for: profile)
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        let lifecycle = makeLifecycle(
            pool: pool,
            diagnostics: diagnostics
        )

        makeInactive(lifecycle, profile: profile)
        lifecycle.handleMemoryPressure(.critical)

        let evaluation = try XCTUnwrap(
            writer.events.first {
                $0.event == "slot_lifecycle.memory_pressure_slot"
                    && $0.fields["action"] == nil
            }
        )
        XCTAssertEqual(evaluation.fields["decision"], .string("hibernate"))

        let completion = try XCTUnwrap(
            writer.events.first {
                $0.event == "slot_lifecycle.memory_pressure_slot"
                    && $0.fields["action"] == .string("hibernate_completed")
            }
        )
        XCTAssertEqual(completion.fields["pressure_level"], .string("critical"))
        XCTAssertEqual(completion.fields["release_eligible"], .bool(true))
        XCTAssertEqual(completion.fields["decision"], .string("hibernate"))
        XCTAssertEqual(
            completion.fields["release_reason"],
            .string("critical_pressure_eligible")
        )
    }

    func testMemoryCriticalEvictsEligibleWarmButNotAttentionProtectedWarm() throws {
        let pool = makePool()
        let protected = makeProfile(name: "CriticalProtected", policy: .warm)
        let eligible = makeProfile(name: "CriticalEligible", policy: .warm)
        for profile in [protected, eligible] {
            _ = try pool.webView(for: profile)
        }
        let lifecycle = makeLifecycle(
            pool: pool,
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
        _ = try pool.webView(for: profile)
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 0.02,
            attentionProtectionQuery: { _ in true }
        )

        makeInactive(lifecycle, profile: profile)
        try await wait(milliseconds: 70)

        XCTAssertTrue(pool.contains(slotID: profile.id))
        XCTAssertTrue(lifecycle.mediaProtectedIDs.isEmpty)
    }

    func testStandardDiagnosticsExplainAttentionProtectionAtReleaseTimer() async throws {
        let pool = makePool()
        let profile = makeProfile(name: "DiagnosticAttentionProtected", policy: .cold)
        _ = try pool.webView(for: profile)
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        var prepared = false
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 0.02,
            prepareRuntimeForRelease: { _ in prepared = true },
            attentionProtectionQuery: { _ in true },
            diagnostics: diagnostics
        )

        makeInactive(lifecycle, profile: profile)
        try await wait(milliseconds: 70)

        XCTAssertTrue(pool.contains(slotID: profile.id))
        XCTAssertFalse(prepared)
        let event = try XCTUnwrap(
            writer.events.first { $0.event == "slot_lifecycle.attention_protected" }
        )
        XCTAssertEqual(event.level, .info)
        XCTAssertEqual(event.fields["slot_id"], .string(profile.id.uuidString))
        XCTAssertEqual(event.fields["boundary"], .string("automatic_long_idle"))
    }

    func testStandardDiagnosticsPersistPlanIdentityAcrossProtectionAndCancellation() async throws {
        let pool = makePool()
        let profile = makeProfile(name: "DiagnosticPlanIdentity", policy: .cold)
        _ = try pool.webView(for: profile)
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        var attentionProtected = true
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 0.02,
            attentionProtectionQuery: { _ in attentionProtected },
            diagnostics: diagnostics
        )

        makeInactive(lifecycle, profile: profile)
        try await wait(milliseconds: 70)

        let created = try XCTUnwrap(
            writer.events.first { $0.event == "slot_lifecycle.inactive_plan.created" }
        )
        let protected = try XCTUnwrap(
            writer.events.first { $0.event == "slot_lifecycle.attention_protected" }
        )
        let createdPlanID = try XCTUnwrap(created.fields["inactive_plan_id"])
        XCTAssertEqual(protected.fields["inactive_plan_id"], createdPlanID)
        XCTAssertNil(created.fields["plan_token"])
        XCTAssertNil(protected.fields["plan_token"])

        lifecycle.activate(profile: profile)
        let cancelled = try XCTUnwrap(
            writer.events.first { $0.event == "slot_lifecycle.inactive_plan.cancelled" }
        )
        XCTAssertEqual(cancelled.fields["inactive_plan_id"], createdPlanID)
        XCTAssertNil(cancelled.fields["plan_token"])

        // A later real lifecycle boundary creates a distinct plan identity.
        attentionProtected = false
        lifecycle.deactivate(profile: profile)
        let createdPlans = writer.events.filter {
            $0.event == "slot_lifecycle.inactive_plan.created"
        }
        XCTAssertEqual(createdPlans.count, 2)
        XCTAssertNotEqual(createdPlans[1].fields["inactive_plan_id"], createdPlanID)
    }

    func testStandardDiagnosticsExposeInactivePlansAndHiddenActiveGrace() async throws {
        let pool = makePool()
        let profile = makeProfile(name: "DiagnosticStandardLifecycle", policy: .cold)
        _ = try pool.webView(for: profile)
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 60,
            hiddenActiveGraceDelay: 0.02,
            diagnostics: diagnostics
        )

        makeInactive(lifecycle, profile: profile)
        lifecycle.activate(profile: profile)
        lifecycle.setPanelVisible(true, activeProfile: profile)
        lifecycle.activate(profile: profile)
        lifecycle.setPanelVisible(false, activeProfile: profile)
        try await wait(milliseconds: 70)

        let events = writer.events
        XCTAssertTrue(events.contains { $0.event == "slot_lifecycle.inactive_plan.created" })
        XCTAssertTrue(events.contains { $0.event == "slot_lifecycle.inactive_plan.cancelled" })
        let createdPlans = events.filter {
            $0.event == "slot_lifecycle.inactive_plan.created"
        }
        let cancelledPlans = events.filter {
            $0.event == "slot_lifecycle.inactive_plan.cancelled"
        }
        XCTAssertEqual(createdPlans.count, 2)
        XCTAssertEqual(cancelledPlans.count, 1)
        XCTAssertEqual(
            createdPlans[0].fields["inactive_plan_id"],
            cancelledPlans[0].fields["inactive_plan_id"]
        )
        XCTAssertNotEqual(
            createdPlans[0].fields["inactive_plan_id"],
            createdPlans[1].fields["inactive_plan_id"]
        )
        XCTAssertTrue(createdPlans.allSatisfy { $0.fields["plan_token"] == nil })
        XCTAssertTrue(cancelledPlans.allSatisfy { $0.fields["plan_token"] == nil })
        let graceEvents = events.filter { $0.event == "slot_lifecycle.hidden_active_grace" }
        XCTAssertEqual(graceEvents.map { $0.fields["state"] }, [.string("scheduled"), .string("expired")])
        XCTAssertTrue(events.filter { $0.event == "slot_lifecycle.inactive_plan.created" }.allSatisfy {
            $0.level == .info
                && $0.fields["slot_id"] == .string(profile.id.uuidString)
                && $0.fields["runtime_retention"] == .string(profile.runtimeRetentionPreference.rawValue)
        })
        XCTAssertTrue(events.filter { $0.event == "slot_lifecycle.inactive_plan.cancelled" }.allSatisfy {
            $0.level == .info
                && $0.fields["slot_id"] == .string(profile.id.uuidString)
        })
        XCTAssertTrue(graceEvents.allSatisfy {
            $0.level == .info
                && $0.fields["slot_id"] == .string(profile.id.uuidString)
        })
        XCTAssertFalse(events.contains { $0.event == "slot_lifecycle.activate" })
        XCTAssertFalse(events.contains { $0.event == "slot_lifecycle.deactivate" })
    }

    func testMediaOnlyProtectionStillWorks() async throws {
        let pool = makePool()
        var profile = makeProfile(name: "MediaOnly", policy: .cold)
        profile.backgroundMediaPolicy = .allowBackgroundAudio
        _ = try pool.webView(for: profile)
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        var mediaPlaying = true
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 0.03,
            mediaProtectionPollDelay: 0.005,
            mediaPlayingQuery: { _, completion in completion(mediaPlaying) },
            diagnostics: diagnostics
        )

        makeInactive(lifecycle, profile: profile)
        try await wait(milliseconds: 70)
        XCTAssertTrue(pool.contains(slotID: profile.id))
        let mediaProtected = try XCTUnwrap(
            writer.events.first { $0.event == "slot_lifecycle.media_protected" }
        )
        XCTAssertNotNil(mediaProtected.fields["inactive_plan_id"])
        XCTAssertNil(mediaProtected.fields["plan_token"])

        mediaPlaying = false
        let released = try await waitUntil { !pool.contains(slotID: profile.id) }
        XCTAssertTrue(released)
    }

    func testFullscreenProtectedDeactivateOnlyRecordsAcceptedDeactivation() throws {
        let pool = makePool()
        let profile = makeProfile(name: "FullscreenDeactivate", policy: .cold)
        _ = try pool.webView(for: profile)
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        let lifecycle = makeLifecycle(
            pool: pool,
            diagnostics: diagnostics
        )

        lifecycle.beginFullscreenSourceVisibility(profile: profile)
        XCTAssertEqual(
            writer.events.filter { $0.event == "slot_lifecycle.fullscreen_protected" }.count,
            1
        )
        lifecycle.deactivate(profile: profile)

        XCTAssertTrue(pool.contains(slotID: profile.id))
        XCTAssertEqual(
            writer.events.filter { $0.event == "slot_lifecycle.deactivate" }.count,
            0
        )

        let otherProfile = makeProfile(name: "OtherFullscreenDeactivate", policy: .cold)
        lifecycle.endFullscreenSourceVisibility(profile: otherProfile)
        XCTAssertEqual(
            writer.events.filter { $0.event == "slot_lifecycle.fullscreen_released" }.count,
            0
        )

        lifecycle.endFullscreenSourceVisibility(profile: profile)
        XCTAssertEqual(
            writer.events.filter { $0.event == "slot_lifecycle.fullscreen_released" }.count,
            1
        )
        lifecycle.deactivate(profile: profile)
        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 1)
    }

    func testRemovingAttentionAloneDoesNotBypassMediaProtection() async throws {
        let pool = makePool()
        var profile = makeProfile(name: "MediaWins", policy: .cold)
        profile.backgroundMediaPolicy = .allowBackgroundAudio
        _ = try pool.webView(for: profile)
        var attentionProtected = true
        var mediaPlaying = true
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 0.03,
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
        let released = try await waitUntil { !pool.contains(slotID: profile.id) }
        XCTAssertTrue(released)
    }

    func testRemovingMediaAloneDoesNotBypassAttentionProtection() async throws {
        let pool = makePool()
        var profile = makeProfile(name: "AttentionWins", policy: .cold)
        profile.backgroundMediaPolicy = .allowBackgroundAudio
        _ = try pool.webView(for: profile)
        var attentionProtected = true
        var mediaPlaying = true
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 0.03,
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
        XCTAssertFalse(pool.contains(slotID: profile.id))
    }

    func testProtectionEndReevaluatesElapsedAutomaticStageWithFreshPlan() async throws {
        let pool = makePool()
        let profile = makeProfile(name: "ColdRestart", policy: .cold)
        _ = try pool.webView(for: profile)
        var attentionProtected = false
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 0.04,
            attentionProtectionQuery: { _ in attentionProtected }
        )

        makeInactive(lifecycle, profile: profile)
        attentionProtected = true
        try await wait(milliseconds: 80)
        XCTAssertTrue(pool.contains(slotID: profile.id))

        attentionProtected = false
        lifecycle.restartAfterAttentionProtectionEnded(profile: profile)
        XCTAssertFalse(pool.contains(slotID: profile.id))
    }

    func testLongIdleProtectionEndDoesNotRestartTheLongIdleLifetime() async throws {
        let pool = makePool()
        let profile = makeProfile(name: "WarmRestart", policy: .warm)
        _ = try pool.webView(for: profile)
        var attentionProtected = false
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 0.04,
            attentionProtectionQuery: { _ in attentionProtected }
        )

        makeInactive(lifecycle, profile: profile)
        attentionProtected = true
        try await wait(milliseconds: 80)
        XCTAssertTrue(pool.contains(slotID: profile.id))

        attentionProtected = false
        lifecycle.restartAfterAttentionProtectionEnded(profile: profile)
        XCTAssertFalse(pool.contains(slotID: profile.id))
    }

    func testAutomaticStageBoundariesKeepIdleResidentThenReclaimAtLongIdle() throws {
        XCTAssertEqual(
            AutomaticLifecycleStage.resolve(
                inactiveDuration: 119,
                recentStageDuration: 120,
                longIdleThreshold: 600
            ),
            .recent
        )
        XCTAssertEqual(
            AutomaticLifecycleStage.resolve(
                inactiveDuration: 120,
                recentStageDuration: 120,
                longIdleThreshold: 600
            ),
            .idle
        )
        XCTAssertEqual(
            AutomaticLifecycleStage.resolve(
                inactiveDuration: 599,
                recentStageDuration: 120,
                longIdleThreshold: 600
            ),
            .idle
        )
        XCTAssertEqual(
            AutomaticLifecycleStage.resolve(
                inactiveDuration: 600,
                recentStageDuration: 120,
                longIdleThreshold: 600
            ),
            .longIdle
        )

        let pool = makePool()
        let profile = makeProfile(name: "StageBoundary", policy: .warm)
        _ = try pool.webView(for: profile)
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        let scheduler = ManualLifecycleScheduler(now: 100)
        let lifecycle = makeLifecycle(
            pool: pool,
            recentStageDuration: 120,
            longIdleThreshold: 600,
            monotonicUptime: { scheduler.now },
            scheduleDelayedWork: { delay, workItem in
                scheduler.schedule(after: delay, workItem: workItem)
            },
            diagnostics: diagnostics
        )

        makeInactive(lifecycle, profile: profile)
        XCTAssertEqual(lifecycle.debugInactiveStage(slotID: profile.id), .recent)
        XCTAssertTrue(pool.contains(slotID: profile.id))

        scheduler.advance(to: 219)
        XCTAssertEqual(lifecycle.debugInactiveStage(slotID: profile.id), .recent)
        XCTAssertTrue(pool.contains(slotID: profile.id))

        scheduler.advance(to: 220)
        XCTAssertEqual(lifecycle.debugInactiveStage(slotID: profile.id), .idle)
        XCTAssertTrue(pool.contains(slotID: profile.id))

        scheduler.advance(to: 699)
        XCTAssertEqual(lifecycle.debugInactiveStage(slotID: profile.id), .idle)
        XCTAssertTrue(pool.contains(slotID: profile.id))

        scheduler.advance(to: 700)
        XCTAssertFalse(pool.contains(slotID: profile.id))
        let hibernations = writer.events.filter { $0.event == "slot_lifecycle.hibernate" }
        XCTAssertEqual(hibernations.count, 1)
        XCTAssertEqual(
            hibernations.first?.fields["release_reason"],
            .string("automatic_long_idle_expired")
        )
    }

    func testDiagnosticSnapshotTracksObservedMemoryPressureAndMonotonicAge() throws {
        var uptime = 50.0
        let lifecycle = makeLifecycle(
            pool: makePool(),
            monotonicUptime: { uptime }
        )
        let slotID = UUID()

        var fields = lifecycle.diagnosticSnapshotFields(for: slotID)
        XCTAssertEqual(fields["lifecycle_memory_pressure_observation"], .string("unobserved"))
        XCTAssertEqual(fields["lifecycle_memory_pressure_observation_uptime"], .null)
        XCTAssertEqual(fields["lifecycle_memory_pressure_observation_age_seconds"], .null)

        uptime = 100
        lifecycle.handleMemoryPressure(.warning)
        fields = lifecycle.diagnosticSnapshotFields(for: slotID)
        XCTAssertEqual(fields["lifecycle_memory_pressure_observation"], .string("warning"))
        XCTAssertEqual(fields["lifecycle_memory_pressure_observation_uptime"], .double(100))
        XCTAssertEqual(fields["lifecycle_memory_pressure_observation_age_seconds"], .double(0))

        uptime = 102.5
        fields = lifecycle.diagnosticSnapshotFields(for: slotID)
        XCTAssertEqual(fields["lifecycle_memory_pressure_observation"], .string("warning"))
        XCTAssertEqual(fields["lifecycle_memory_pressure_observation_uptime"], .double(100))
        XCTAssertEqual(fields["lifecycle_memory_pressure_observation_age_seconds"], .double(2.5))

        uptime = 105
        lifecycle.handleMemoryPressure(.critical)
        fields = lifecycle.diagnosticSnapshotFields(for: slotID)
        XCTAssertEqual(fields["lifecycle_memory_pressure_observation"], .string("critical"))
        XCTAssertEqual(fields["lifecycle_memory_pressure_observation_uptime"], .double(105))
        XCTAssertEqual(fields["lifecycle_memory_pressure_observation_age_seconds"], .double(0))

        uptime = 110
        lifecycle.handleMemoryPressureNormalized()
        fields = lifecycle.diagnosticSnapshotFields(for: slotID)
        XCTAssertEqual(fields["lifecycle_memory_pressure_observation"], .string("normal"))
        XCTAssertEqual(fields["lifecycle_memory_pressure_observation_uptime"], .double(110))

        uptime = 114.5
        fields = lifecycle.diagnosticSnapshotFields(for: slotID)
        XCTAssertEqual(fields["lifecycle_memory_pressure_observation_age_seconds"], .double(4.5))

        let encodedFields = try JSONEncoder().encode(fields)
        let decodedFields = try JSONDecoder().decode(
            [String: RuntimeDiagnosticValue].self,
            from: encodedFields
        )
        XCTAssertEqual(
            decodedFields["lifecycle_memory_pressure_observation"],
            .string("normal")
        )
        XCTAssertEqual(
            decodedFields["lifecycle_memory_pressure_observation_age_seconds"],
            .double(4.5)
        )
    }

    func testReactivationInvalidatesScheduledStageBoundary() throws {
        let pool = makePool()
        let profile = makeProfile(name: "ReactivatedBeforeBoundary", policy: .warm)
        _ = try pool.webView(for: profile)
        let scheduler = ManualLifecycleScheduler(now: 100)
        let lifecycle = makeLifecycle(
            pool: pool,
            recentStageDuration: 120,
            longIdleThreshold: 600,
            monotonicUptime: { scheduler.now },
            scheduleDelayedWork: { delay, workItem in
                scheduler.schedule(after: delay, workItem: workItem)
            }
        )

        makeInactive(lifecycle, profile: profile)
        XCTAssertNotNil(lifecycle.debugInactivePlanToken(slotID: profile.id))

        scheduler.advance(to: 110)
        lifecycle.activate(profile: profile)
        XCTAssertNil(lifecycle.debugInactivePlanToken(slotID: profile.id))

        // Run the old plan's queued boundary after reactivation. Its captured
        // token must not reclaim or mutate the current Runtime.
        scheduler.advance(to: 800)
        XCTAssertTrue(pool.contains(slotID: profile.id))
        XCTAssertNil(lifecycle.debugInactivePlanToken(slotID: profile.id))
    }

    func testCriticalMayBypassRecentButWarningMustWaitUntilIdle() throws {
        let pool = makePool()
        let profile = makeProfile(name: "RecentPressure", policy: .warm)
        _ = try pool.webView(for: profile)
        let lifecycle = makeLifecycle(
            pool: pool,
            recentStageDuration: 120,
            longIdleThreshold: 600,
            pressureStepDelay: 600
        )
        makeInactive(lifecycle, profile: profile)

        lifecycle.handleMemoryPressure(.warning)
        XCTAssertTrue(pool.contains(slotID: profile.id))
        XCTAssertEqual(lifecycle.debugInactiveStage(slotID: profile.id), .recent)

        lifecycle.handleMemoryPressure(.critical)
        XCTAssertFalse(pool.contains(slotID: profile.id))
    }

    func testCriticalMemoryPressureProgressivelyReleasesWarmAfterProtectionEnds() async throws {
        let pool = makePool()
        let first = makeProfile(name: "First", policy: .warm)
        let second = makeProfile(name: "Second", policy: .warm)
        let third = makeProfile(name: "Third", policy: .warm)
        for profile in [first, second, third] {
            _ = try pool.webView(for: profile)
        }
        var protectedIDs: Set<UUID> = [first.id]
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 60,
            pressureStepDelay: 0.03,
            attentionProtectionQuery: { protectedIDs.contains($0) }
        )

        makeInactive(lifecycle, profile: first)
        makeInactive(lifecycle, profile: second)
        makeInactive(lifecycle, profile: third)
        protectedIDs.remove(first.id)
        lifecycle.restartAfterAttentionProtectionEnded(profile: first)
        lifecycle.handleMemoryPressure(.critical)

        let fullyReclaimed = try await waitUntil { pool.count == 0 }
        XCTAssertTrue(fullyReclaimed)
        XCTAssertFalse(pool.contains(slotID: first.id))
        XCTAssertFalse(pool.contains(slotID: second.id))
        XCTAssertFalse(pool.contains(slotID: third.id))
    }

    func testSustainedWarningNeverReclaimsKeepLoaded() async throws {
        let pool = makePool()
        let keepLoaded = makeProfile(name: "WarningKeepLoaded", policy: .hot)
        let automaticA = makeProfile(name: "WarningAutoA", policy: .warm)
        let automaticB = makeProfile(name: "WarningAutoB", policy: .warm)
        for profile in [keepLoaded, automaticA, automaticB] {
            _ = try pool.webView(for: profile)
        }
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 600,
            pressureStepDelay: 0.03
        )

        makeInactive(lifecycle, profile: keepLoaded)
        makeInactive(lifecycle, profile: automaticA)
        makeInactive(lifecycle, profile: automaticB)
        lifecycle.handleMemoryPressure(.warning)

        let automaticsReclaimed = try await waitUntil {
            !pool.contains(slotID: automaticA.id) && !pool.contains(slotID: automaticB.id)
        }
        XCTAssertTrue(automaticsReclaimed)
        XCTAssertTrue(pool.contains(slotID: keepLoaded.id))
    }

    func testSustainedCriticalReclaimsAutomaticBeforeInactiveKeepLoaded() async throws {
        let pool = makePool()
        let keepLoaded = makeProfile(name: "CriticalKeepLoaded", policy: .hot)
        let automaticA = makeProfile(name: "CriticalAutoA", policy: .warm)
        let automaticB = makeProfile(name: "CriticalAutoB", policy: .warm)
        for profile in [keepLoaded, automaticA, automaticB] {
            _ = try pool.webView(for: profile)
        }
        var releasedSlotIDs: [UUID] = []
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 600,
            pressureStepDelay: 0.03,
            onRuntimeReleased: { releasedSlotIDs.append($0.id) }
        )

        makeInactive(lifecycle, profile: keepLoaded)
        makeInactive(lifecycle, profile: automaticA)
        makeInactive(lifecycle, profile: automaticB)
        lifecycle.handleMemoryPressure(.critical)

        let automaticReclaimed = try await waitUntil {
            !pool.contains(slotID: automaticA.id) && !pool.contains(slotID: automaticB.id)
        }
        XCTAssertTrue(automaticReclaimed)

        // Keep Loaded remains resident after Automatic candidates are gone.
        let automaticIDs = Set([automaticA.id, automaticB.id])
        XCTAssertTrue(
            releasedSlotIDs.prefix(2).allSatisfy(automaticIDs.contains),
            "expected Automatic candidates first, got \(releasedSlotIDs)"
        )
        XCTAssertEqual(Set(releasedSlotIDs), automaticIDs)
        XCTAssertTrue(pool.contains(slotID: keepLoaded.id))
    }

    func testDuplicatePressureEventsDoNotStackReclaimTransactions() async throws {
        let pool = makePool()
        let profiles = [
            makeProfile(name: "StackOne", policy: .warm),
            makeProfile(name: "StackTwo", policy: .warm)
        ]
        for profile in profiles { _ = try pool.webView(for: profile) }
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 600,
            pressureStepDelay: 0.3
        )
        for profile in profiles { makeInactive(lifecycle, profile: profile) }

        XCTAssertEqual(pool.count, 2)
        lifecycle.handleMemoryPressure(.warning)
        lifecycle.handleMemoryPressure(.warning)
        lifecycle.handleMemoryPressure(.warning)

        // Repeated stale events while a continuation is pending neither
        // stack synchronous purges nor precompute a batch eviction.
        XCTAssertEqual(pool.count, 1)

        try await wait(milliseconds: 700)
        XCTAssertEqual(pool.count, 0)
    }

    func testMediaPlayingPressureCandidateStaysProtectedWhileAnotherEligibleRuntimeProgresses() throws {
        let pool = makePool()
        var mediaProfile = makeProfile(name: "PressureMedia", policy: .warm)
        mediaProfile.backgroundMediaPolicy = .allowBackgroundAudio
        let eligibleProfile = makeProfile(name: "PressureEligible", policy: .warm)
        _ = try pool.webView(for: mediaProfile)
        _ = try pool.webView(for: eligibleProfile)

        let scheduler = ManualLifecycleScheduler(now: 1_000)
        var mediaQueryCount = 0
        var pressureMediaResult: ((Bool) -> Void)?
        let lifecycle = makeLifecycle(
            pool: pool,
            recentStageDuration: 30,
            longIdleThreshold: 600,
            monotonicUptime: { scheduler.now },
            scheduleDelayedWork: { delay, workItem in
                scheduler.schedule(after: delay, workItem: workItem)
            },
            mediaPlayingQuery: { slotID, completion in
                guard slotID == mediaProfile.id else { return }
                mediaQueryCount += 1
                if mediaQueryCount == 1 {
                    completion(false)
                } else {
                    pressureMediaResult = completion
                }
            }
        )

        makeInactive(lifecycle, profile: mediaProfile)
        XCTAssertEqual(mediaQueryCount, 1)
        scheduler.advance(to: 1_001)
        makeInactive(lifecycle, profile: eligibleProfile)
        scheduler.advance(to: 1_031)
        XCTAssertEqual(lifecycle.debugInactiveStage(slotID: mediaProfile.id), .idle)
        XCTAssertEqual(lifecycle.debugInactiveStage(slotID: eligibleProfile.id), .idle)

        lifecycle.handleMemoryPressure(.warning)
        XCTAssertNotNil(pressureMediaResult)
        pressureMediaResult?(true)
        XCTAssertTrue(lifecycle.mediaProtectedIDs.contains(mediaProfile.id))

        // The async media result schedules the existing progressive step.
        // It skips the protected oldest candidate and reselects the other
        // eligible Runtime from current facts.
        scheduler.advance(to: 1_031.5)
        XCTAssertTrue(pool.contains(slotID: mediaProfile.id))
        XCTAssertTrue(lifecycle.mediaProtectedIDs.contains(mediaProfile.id))
        XCTAssertFalse(pool.contains(slotID: eligibleProfile.id))
    }

    func testStaleAsyncPressurePlanReentersFreshCandidateSelection() throws {
        let pool = makePool()
        var mediaProfile = makeProfile(name: "StalePressureMedia", policy: .warm)
        mediaProfile.backgroundMediaPolicy = .allowBackgroundAudio
        let nextEligibleProfile = makeProfile(name: "FreshPressureCandidate", policy: .warm)
        _ = try pool.webView(for: mediaProfile)
        _ = try pool.webView(for: nextEligibleProfile)

        let scheduler = ManualLifecycleScheduler(now: 2_000)
        var mediaQueries: [(UUID, (Bool) -> Void)] = []
        let lifecycle = makeLifecycle(
            pool: pool,
            recentStageDuration: 30,
            longIdleThreshold: 600,
            monotonicUptime: { scheduler.now },
            scheduleDelayedWork: { delay, workItem in
                scheduler.schedule(after: delay, workItem: workItem)
            },
            mediaPlayingQuery: { slotID, completion in
                mediaQueries.append((slotID, completion))
            }
        )

        makeInactive(lifecycle, profile: mediaProfile)
        let (initialSlotID, initialMediaResult) = mediaQueries.removeFirst()
        XCTAssertEqual(initialSlotID, mediaProfile.id)
        initialMediaResult(false)

        scheduler.advance(to: 2_001)
        makeInactive(lifecycle, profile: nextEligibleProfile)
        scheduler.advance(to: 2_030)
        lifecycle.handleMemoryPressure(.warning)
        XCTAssertEqual(mediaQueries.count, 1)
        let (pressureSlotID, pressureMediaResult) = mediaQueries.removeFirst()
        XCTAssertEqual(pressureSlotID, mediaProfile.id)

        // Make the captured oldest plan stale while its media query is still
        // in flight. The other candidate becomes IDLE before that callback.
        scheduler.advance(to: 2_031)
        lifecycle.activate(profile: mediaProfile)
        pressureMediaResult(false)

        XCTAssertTrue(pool.contains(slotID: mediaProfile.id))
        XCTAssertFalse(pool.contains(slotID: nextEligibleProfile.id))
    }

    func testPressureNormalizationDuringAsyncMediaEvaluationDoesNotRestartReclaim() throws {
        let pool = makePool()
        var profile = makeProfile(name: "NormalizedAsyncPressure", policy: .warm)
        profile.backgroundMediaPolicy = .allowBackgroundAudio
        _ = try pool.webView(for: profile)

        let scheduler = ManualLifecycleScheduler(now: 3_000)
        var mediaQueries: [(UUID, (Bool) -> Void)] = []
        let lifecycle = makeLifecycle(
            pool: pool,
            recentStageDuration: 30,
            longIdleThreshold: 600,
            monotonicUptime: { scheduler.now },
            scheduleDelayedWork: { delay, workItem in
                scheduler.schedule(after: delay, workItem: workItem)
            },
            mediaPlayingQuery: { slotID, completion in
                mediaQueries.append((slotID, completion))
            }
        )

        makeInactive(lifecycle, profile: profile)
        let (_, initialMediaResult) = mediaQueries.removeFirst()
        initialMediaResult(false)
        scheduler.advance(to: 3_030)

        lifecycle.handleMemoryPressure(.warning)
        XCTAssertEqual(mediaQueries.count, 1)
        let (_, stalePressureResult) = mediaQueries.removeFirst()
        lifecycle.handleMemoryPressureNormalized()
        stalePressureResult(false)

        XCTAssertTrue(pool.contains(slotID: profile.id))
        scheduler.advance(to: 3_100)
        XCTAssertTrue(pool.contains(slotID: profile.id))
    }

    func testOldPressureEvaluationTokenCannotMutateNewCriticalEvaluation() throws {
        let pool = makePool()
        var profile = makeProfile(name: "PressureTokenIsolation", policy: .warm)
        profile.backgroundMediaPolicy = .allowBackgroundAudio
        _ = try pool.webView(for: profile)

        let scheduler = ManualLifecycleScheduler(now: 4_000)
        var mediaQueries: [(UUID, (Bool) -> Void)] = []
        let lifecycle = makeLifecycle(
            pool: pool,
            recentStageDuration: 30,
            longIdleThreshold: 600,
            monotonicUptime: { scheduler.now },
            scheduleDelayedWork: { delay, workItem in
                scheduler.schedule(after: delay, workItem: workItem)
            },
            mediaPlayingQuery: { slotID, completion in
                mediaQueries.append((slotID, completion))
            }
        )

        makeInactive(lifecycle, profile: profile)
        let (_, initialMediaResult) = mediaQueries.removeFirst()
        initialMediaResult(false)
        scheduler.advance(to: 4_030)

        lifecycle.handleMemoryPressure(.warning)
        XCTAssertEqual(mediaQueries.count, 1)
        let (_, staleWarningResult) = mediaQueries.removeFirst()
        lifecycle.handleMemoryPressure(.critical)
        XCTAssertEqual(mediaQueries.count, 1)
        let (_, currentCriticalResult) = mediaQueries.removeFirst()

        staleWarningResult(false)
        XCTAssertTrue(pool.contains(slotID: profile.id))

        currentCriticalResult(false)
        XCTAssertFalse(pool.contains(slotID: profile.id))
    }

    // MARK: Sustained-pressure eligibility re-entry

    func testSustainedWarningReclaimsRuntimeWhenGenerationProtectionEndsWithoutNewPressureEvent() async throws {
        let pool = makePool()
        let profile = makeProfile(name: "ReentryGenerating", policy: .warm)
        _ = try pool.webView(for: profile)
        let coordinator = WebAttentionCoordinator()
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 600,
            pressureStepDelay: 0.05,
            attentionProtectionQuery: { coordinator.isAttentionProtected($0) }
        )

        coordinator.apply(.generationStarted, for: profile.id)
        makeInactive(lifecycle, profile: profile)
        lifecycle.handleMemoryPressure(.warning)
        XCTAssertTrue(pool.contains(slotID: profile.id))

        // Protection ends with NO second warning event: the still-active
        // warning state must reclaim the newly eligible Runtime itself.
        coordinator.apply(.generationFinished(userVisible: false), for: profile.id)
        lifecycle.restartAfterAttentionProtectionEnded(profile: profile)

        let reclaimed = try await waitUntil { !pool.contains(slotID: profile.id) }
        XCTAssertTrue(reclaimed)
        XCTAssertEqual(coordinator.state(for: profile.id), .ready)
    }

    func testSustainedCriticalReclaimsKeepLoadedWhenProtectionEndsWithoutNewPressureEvent() async throws {
        let pool = makePool()
        let automatic = makeProfile(name: "ReentryAutomatic", policy: .warm)
        let keepLoaded = makeProfile(name: "ReentryKeepLoaded", policy: .hot)
        for profile in [automatic, keepLoaded] {
            _ = try pool.webView(for: profile)
        }
        let coordinator = WebAttentionCoordinator()
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 600,
            pressureStepDelay: 0.05,
            attentionProtectionQuery: { coordinator.isAttentionProtected($0) }
        )

        // Keep Loaded is generating-protected; the eligible Automatic is
        // reclaimed by the critical ladder first.
        coordinator.apply(.generationStarted, for: keepLoaded.id)
        makeInactive(lifecycle, profile: automatic)
        makeInactive(lifecycle, profile: keepLoaded)
        lifecycle.handleMemoryPressure(.critical)

        let automaticReclaimed = try await waitUntil {
            !pool.contains(slotID: automatic.id)
        }
        XCTAssertTrue(automaticReclaimed)
        XCTAssertTrue(pool.contains(slotID: keepLoaded.id))

        // Protection ending does not make Keep Loaded pressure eligible.
        coordinator.apply(.generationFinished(userVisible: false), for: keepLoaded.id)
        lifecycle.restartAfterAttentionProtectionEnded(profile: keepLoaded)
        try await wait(milliseconds: 100)
        XCTAssertTrue(pool.contains(slotID: keepLoaded.id))
    }

    func testCriticalTakeoverCancelsPendingWarningContinuationAndPreservesOrdering() async throws {
        let pool = makePool()
        let keepLoaded = makeProfile(name: "TakeoverKeepLoaded", policy: .hot)
        let automaticA = makeProfile(name: "TakeoverAutoA", policy: .warm)
        let automaticB = makeProfile(name: "TakeoverAutoB", policy: .warm)
        for profile in [keepLoaded, automaticA, automaticB] {
            _ = try pool.webView(for: profile)
        }
        var releasedSlotIDs: [UUID] = []
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 600,
            pressureStepDelay: 0.25,
            onRuntimeReleased: { releasedSlotIDs.append($0.id) }
        )
        for profile in [keepLoaded, automaticA, automaticB] {
            makeInactive(lifecycle, profile: profile)
        }

        lifecycle.handleMemoryPressure(.warning)
        XCTAssertEqual(pool.count, 2)
        XCTAssertEqual(releasedSlotIDs.count, 1)

        // Critical arrives while the warning continuation is pending: the
        // stale warning continuation is cancelled and critical takes over
        // while preserving Keep Loaded.
        lifecycle.handleMemoryPressure(.critical)
        XCTAssertEqual(pool.count, 1)
        XCTAssertEqual(releasedSlotIDs.count, 2)
        XCTAssertTrue(automaticA.id == releasedSlotIDs[0] || automaticB.id == releasedSlotIDs[0])

        let automaticReclaimed = try await waitUntil {
            !pool.contains(slotID: automaticA.id) && !pool.contains(slotID: automaticB.id)
        }
        XCTAssertTrue(automaticReclaimed)
        XCTAssertTrue(pool.contains(slotID: keepLoaded.id))
        XCTAssertEqual(Set(releasedSlotIDs).count, releasedSlotIDs.count)
        XCTAssertFalse(releasedSlotIDs.contains(keepLoaded.id))
    }

    func testNormalizedPressureClearsStaleStateBeforeEligibilityReturns() async throws {
        let pool = makePool()
        let profile = makeProfile(name: "StaleWarningGenerating", policy: .warm)
        _ = try pool.webView(for: profile)
        let coordinator = WebAttentionCoordinator()
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 600,
            pressureStepDelay: 0.05,
            attentionProtectionQuery: { coordinator.isAttentionProtected($0) }
        )

        coordinator.apply(.generationStarted, for: profile.id)
        makeInactive(lifecycle, profile: profile)
        lifecycle.handleMemoryPressure(.warning)
        XCTAssertTrue(pool.contains(slotID: profile.id))

        // Pressure clears while the Runtime is still protected; protection
        // then ends with no further pressure event.
        lifecycle.handleMemoryPressureNormalized()
        coordinator.apply(.generationFinished(userVisible: false), for: profile.id)
        lifecycle.restartAfterAttentionProtectionEnded(profile: profile)

        // Stale warning state must not reclaim; normal policy keeps this
        // IDLE Automatic Runtime resident until its long-idle boundary.
        try await wait(milliseconds: 200)
        XCTAssertTrue(pool.contains(slotID: profile.id))
        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 1)
    }

    func testRepeatedEligibilityBoundariesProduceSingleReclaimChain() async throws {
        let pool = makePool()
        let profile = makeProfile(name: "SingleChainGenerating", policy: .warm)
        _ = try pool.webView(for: profile)
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        let coordinator = WebAttentionCoordinator()
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 600,
            pressureStepDelay: 0.05,
            attentionProtectionQuery: { coordinator.isAttentionProtected($0) },
            diagnostics: diagnostics
        )

        coordinator.apply(.generationStarted, for: profile.id)
        makeInactive(lifecycle, profile: profile)
        // Repeated same-level pressure events while no candidate exists.
        lifecycle.handleMemoryPressure(.warning)
        lifecycle.handleMemoryPressure(.warning)
        lifecycle.handleMemoryPressure(.warning)
        XCTAssertTrue(pool.contains(slotID: profile.id))

        // Protection ends once; repeated eligibility boundaries must still
        // yield exactly one reclaim transaction chain for one Runtime.
        coordinator.apply(.generationFinished(userVisible: false), for: profile.id)
        lifecycle.restartAfterAttentionProtectionEnded(profile: profile)
        lifecycle.handleMemoryPressure(.warning)

        let reclaimed = try await waitUntil { !pool.contains(slotID: profile.id) }
        XCTAssertTrue(reclaimed)
        let hibernateEvents = writer.events.filter { $0.event == "slot_lifecycle.hibernate" }
        XCTAssertEqual(hibernateEvents.count, 1)
    }

    func testSelectedHiddenGeneratingKeepsHiddenGraceAndThenProtectsInactiveRuntime() async throws {
        let pool = makePool()
        let profile = makeProfile(name: "HiddenGenerating", policy: .cold)
        _ = try pool.webView(for: profile)
        var attentionProtectionQueryCount = 0
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 0.02,
            hiddenActiveGraceDelay: 0.02,
            attentionProtectionQuery: { _ in
                attentionProtectionQueryCount += 1
                return true
            }
        )

        lifecycle.setPanelVisible(true, activeProfile: profile)
        lifecycle.activate(profile: profile)
        lifecycle.setPanelVisible(false, activeProfile: profile)
        XCTAssertTrue(lifecycle.isHiddenActiveGracePending)
        XCTAssertTrue(pool.contains(slotID: profile.id))

        // The Cold release callback's proactive-protection check is the only
        // reachable attention query for this pauseWhenInactive Cold fixture,
        // so a non-zero count proves the eviction timer reached its live
        // protection boundary instead of merely having been scheduled.
        let reachedEvictionProtectionBoundary = try await waitUntil {
            !lifecycle.isHiddenActiveGracePending
                && lifecycle.pendingWarmReleaseCount == 1
                && attentionProtectionQueryCount >= 1
                && pool.contains(slotID: profile.id)
        }
        XCTAssertTrue(reachedEvictionProtectionBoundary)
        XCTAssertFalse(lifecycle.isHiddenActiveGracePending)
        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 1)
        XCTAssertGreaterThanOrEqual(attentionProtectionQueryCount, 1)
        XCTAssertTrue(pool.contains(slotID: profile.id))
    }

    func testHotAttentionProtectedSlotGetsNoNewReleasePlan() async throws {
        let pool = makePool()
        let profile = makeProfile(name: "HotGenerating", policy: .hot)
        _ = try pool.webView(for: profile)
        let lifecycle = makeLifecycle(
            pool: pool,
            attentionProtectionQuery: { _ in true }
        )

        makeInactive(lifecycle, profile: profile)
        try await wait(milliseconds: 50)

        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 0)
        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 0)
        XCTAssertTrue(pool.contains(slotID: profile.id))
    }

    func testVisibleGeneratingFinishesIdleWithoutInactivePlan() throws {
        let pool = makePool()
        let profile = makeProfile(name: "VisibleFinish", policy: .cold)
        _ = try pool.webView(for: profile)
        let coordinator = WebAttentionCoordinator()
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 0.02,
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
        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 0)
    }

    func testReadyAcknowledgementWhileVisibleDoesNotCreateInactiveTimer() async throws {
        let pool = makePool()
        let profile = makeProfile(name: "ReadyAcknowledged", policy: .cold)
        _ = try pool.webView(for: profile)
        let coordinator = WebAttentionCoordinator()
        coordinator.apply(.generationStarted, for: profile.id)
        coordinator.apply(
            .generationFinished(userVisible: false),
            for: profile.id
        )
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 0.02,
            attentionProtectionQuery: { _ in coordinator.isAttentionProtected(profile.id) }
        )

        lifecycle.setPanelVisible(true, activeProfile: profile)
        lifecycle.activate(profile: profile)
        coordinator.acknowledge(slotID: profile.id, userVisible: true)
        lifecycle.restartAfterAttentionProtectionEnded(profile: profile)

        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 0)
        lifecycle.deactivate(profile: profile)
        XCTAssertEqual(lifecycle.pendingWarmReleaseCount, 1)
        try await wait(milliseconds: 70)
        XCTAssertFalse(pool.contains(slotID: profile.id))
    }

    func testMultipleSlotsRemainIsolatedAcrossAttentionProtection() async throws {
        let pool = makePool()
        let protected = makeProfile(name: "IsolatedProtected", policy: .cold)
        let ordinary = makeProfile(name: "IsolatedOrdinary", policy: .cold)
        for profile in [protected, ordinary] {
            _ = try pool.webView(for: profile)
        }
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 0.02,
            attentionProtectionQuery: { $0 == protected.id }
        )

        makeInactive(lifecycle, profile: protected)
        makeInactive(lifecycle, profile: ordinary)
        try await wait(milliseconds: 70)

        XCTAssertTrue(pool.contains(slotID: protected.id))
        XCTAssertFalse(pool.contains(slotID: ordinary.id))
    }

    func testStaleTimerCallbackCannotReleaseSlotAfterAttentionStarts() throws {
        let pool = makePool()
        let profile = makeProfile(name: "StaleTimer", policy: .warm)
        _ = try pool.webView(for: profile)
        var attentionProtected = false
        let scheduler = ManualLifecycleScheduler(now: 100)
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 0.02,
            monotonicUptime: { scheduler.now },
            scheduleDelayedWork: { delay, workItem in
                scheduler.schedule(after: delay, workItem: workItem)
            },
            attentionProtectionQuery: { _ in attentionProtected }
        )

        makeInactive(lifecycle, profile: profile)
        scheduler.advance(to: 100.01)
        attentionProtected = true
        scheduler.advance(to: 100.03)

        XCTAssertTrue(pool.contains(slotID: profile.id))
    }

    func testStaleAsyncMediaResultCannotReleaseNewlyAttentionProtectedSlot() throws {
        let pool = makePool()
        var profile = makeProfile(name: "StaleMedia", policy: .cold)
        profile.backgroundMediaPolicy = .allowBackgroundAudio
        _ = try pool.webView(for: profile)
        var pendingMediaResult: ((Bool) -> Void)?
        var attentionProtected = false
        let scheduler = ManualLifecycleScheduler(now: 100)
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 0.02,
            monotonicUptime: { scheduler.now },
            scheduleDelayedWork: { delay, workItem in
                scheduler.schedule(after: delay, workItem: workItem)
            },
            mediaPlayingQuery: { _, completion in
                pendingMediaResult = completion
            },
            attentionProtectionQuery: { _ in attentionProtected }
        )

        makeInactive(lifecycle, profile: profile)
        XCTAssertNotNil(pendingMediaResult)
        attentionProtected = true
        pendingMediaResult?(false)
        scheduler.advance(to: 100.07)

        XCTAssertTrue(pool.contains(slotID: profile.id))
    }

    func testAsyncMediaResultFromReleasedRuntimeCannotAdvanceOldPlan() throws {
        let pool = makePool()
        var profile = makeProfile(name: "ReleasedMedia", policy: .cold)
        profile.backgroundMediaPolicy = .allowBackgroundAudio
        _ = try pool.webView(for: profile)
        var pendingMediaResults: [(Bool) -> Void] = []
        var mediaQueryCount = 0
        let scheduler = ManualLifecycleScheduler(now: 100)
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 0.02,
            mediaProtectionPollDelay: 0.01,
            monotonicUptime: { scheduler.now },
            scheduleDelayedWork: { delay, workItem in
                scheduler.schedule(after: delay, workItem: workItem)
            },
            mediaPlayingQuery: { _, completion in
                mediaQueryCount += 1
                pendingMediaResults.append(completion)
            }
        )

        makeInactive(lifecycle, profile: profile)
        XCTAssertEqual(mediaQueryCount, 1)
        // The pending query belongs to this exact Runtime.
        pool.release(slotID: profile.id)
        pendingMediaResults.removeFirst()(true)
        scheduler.advance(to: 100.1)

        XCTAssertEqual(mediaQueryCount, 1)
        XCTAssertFalse(pool.contains(slotID: profile.id))
    }

    func testOldInactivePlanCannotReclaimReplacementRuntimeGeneration() throws {
        let pool = makePool()
        let profile = makeProfile(name: "ReplacementRuntime", policy: .warm)
        _ = try pool.webView(for: profile)
        let scheduler = ManualLifecycleScheduler(now: 100)
        let lifecycle = makeLifecycle(
            pool: pool,
            longIdleThreshold: 0.04,
            monotonicUptime: { scheduler.now },
            scheduleDelayedWork: { delay, workItem in
                scheduler.schedule(after: delay, workItem: workItem)
            }
        )
        makeInactive(lifecycle, profile: profile)
        let oldPlanToken = try XCTUnwrap(lifecycle.debugInactivePlanToken(slotID: profile.id))

        pool.release(slotID: profile.id)
        _ = try pool.webView(for: profile)
        XCTAssertEqual(lifecycle.debugInactivePlanToken(slotID: profile.id), oldPlanToken)

        scheduler.advance(to: 100.04)
        XCTAssertTrue(pool.contains(slotID: profile.id))
    }

    private func makePool() -> WebViewPool {
        WebViewPool(onURLChange: { _, _ in }, initialLoad: { _, _ in })
    }

    private func makeLifecycle(
        pool: WebViewPool,
        recentStageDuration: TimeInterval = 0,
        longIdleThreshold: TimeInterval = 600,
        hiddenActiveGraceDelay: TimeInterval = 120,
        mediaProtectionPollDelay: TimeInterval = 0.01,
        pressureStepDelay: TimeInterval = 0.02,
        monotonicUptime: @escaping SlotLifecycleCoordinator.MonotonicUptimeProvider = {
            ProcessInfo.processInfo.systemUptime
        },
        scheduleDelayedWork: SlotLifecycleCoordinator.DelayedWorkScheduler? = nil,
        mediaPlayingQuery: SlotLifecycleCoordinator.MediaPlayingQuery? = nil,
        prepareRuntimeForRelease: @escaping SlotLifecycleCoordinator.RuntimeReleasePreparation = { _ in },
        onRuntimeReleased: @escaping SlotLifecycleCoordinator.RuntimeReleasedHandler = { _ in },
        onSlotBecameInactive: @escaping SlotLifecycleCoordinator.SlotBecameInactiveHandler = { _ in },
        attentionProtectionQuery: @escaping SlotLifecycleCoordinator.AttentionProtectionQuery = { _ in false },
        diagnostics: any RuntimeDiagnosticRecording = RuntimeDiagnosticNoopRecorder()
    ) -> SlotLifecycleCoordinator {
        let container = WebPanelContainerView(
            frame: NSRect(x: 0, y: 0, width: 430, height: 820)
        )
        retainedContainers.append(container)
        return SlotLifecycleCoordinator(
            webViewPool: pool,
            container: container,
            recentStageDuration: recentStageDuration,
            longIdleThreshold: longIdleThreshold,
            hiddenActiveGraceDelay: hiddenActiveGraceDelay,
            mediaProtectionPollDelay: mediaProtectionPollDelay,
            pressureStepDelay: pressureStepDelay,
            monotonicUptime: monotonicUptime,
            scheduleDelayedWork: scheduleDelayedWork,
            mediaPlayingQuery: mediaPlayingQuery,
            onRuntimeReleased: onRuntimeReleased,
            prepareRuntimeForRelease: prepareRuntimeForRelease,
            onSlotBecameInactive: onSlotBecameInactive,
            attentionProtectionQuery: attentionProtectionQuery,
            diagnostics: diagnostics,
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

    private func waitUntil(
        timeoutMilliseconds: UInt64 = 500,
        pollMilliseconds: UInt64 = 5,
        condition: () -> Bool
    ) async throws -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds
            + timeoutMilliseconds * 1_000_000

        while true {
            if condition() {
                return true
            }
            if DispatchTime.now().uptimeNanoseconds >= deadline {
                return false
            }
            try await wait(milliseconds: pollMilliseconds)
        }
    }
}

@MainActor
private final class ManualLifecycleScheduler {
    private struct ScheduledWork {
        let deadline: TimeInterval
        let order: UInt64
        let workItem: DispatchWorkItem
    }

    private(set) var now: TimeInterval
    private var nextOrder: UInt64 = 0
    private var scheduledWork: [ScheduledWork] = []

    init(now: TimeInterval) {
        self.now = now
    }

    func schedule(after delay: TimeInterval, workItem: DispatchWorkItem) {
        scheduledWork.append(
            ScheduledWork(
                deadline: now + max(delay, 0),
                order: nextOrder,
                workItem: workItem
            )
        )
        nextOrder += 1
    }

    func advance(to target: TimeInterval) {
        let boundedTarget = max(now, target)
        now = boundedTarget
        while let nextIndex = scheduledWork.indices
            .filter({ scheduledWork[$0].deadline <= boundedTarget })
            .min(by: {
                let lhs = scheduledWork[$0]
                let rhs = scheduledWork[$1]
                return lhs.deadline == rhs.deadline
                    ? lhs.order < rhs.order
                    : lhs.deadline < rhs.deadline
            }) {
            let next = scheduledWork.remove(at: nextIndex)
            if !next.workItem.isCancelled {
                next.workItem.perform()
            }
        }
    }
}
