import XCTest
@testable import FloatTabs

@MainActor
final class WebAttentionCoordinatorTests: XCTestCase {
    private var coordinator: WebAttentionCoordinator!
    private var writer: RuntimeDiagnosticInMemoryWriter!
    private var slotA: UUID!
    private var slotB: UUID!

    override func setUp() {
        super.setUp()
        writer = RuntimeDiagnosticInMemoryWriter()
        coordinator = WebAttentionCoordinator(
            diagnostics: RuntimeDiagnostics(mode: .standard, writer: writer)
        )
        slotA = UUID()
        slotB = UUID()
    }

    override func tearDown() {
        coordinator = nil
        writer = nil
        slotA = nil
        slotB = nil
        super.tearDown()
    }

    func testNewSlotDefaultsToIdle() {
        XCTAssertEqual(coordinator.state(for: slotA), .idle)
        XCTAssertFalse(coordinator.isAttentionProtected(slotA))
        XCTAssertTrue(coordinator.readySlotIDs.isEmpty)
    }

    func testIdleToGeneratingOnGenerationStarted() {
        coordinator.apply(.generationStarted, for: slotA)

        XCTAssertEqual(coordinator.state(for: slotA), .generating)
    }

    func testGeneratingToIdleOnUserVisibleFinish() {
        coordinator.apply(.generationStarted, for: slotA)

        coordinator.apply(.generationFinished(userVisible: true), for: slotA)

        XCTAssertEqual(coordinator.state(for: slotA), .idle)
    }

    func testGeneratingToReadyOnHiddenFinish() {
        coordinator.apply(.generationStarted, for: slotA)

        coordinator.apply(.generationFinished(userVisible: false), for: slotA)

        XCTAssertEqual(coordinator.state(for: slotA), .ready)
    }

    func testReadyAcknowledgementWhileUserVisibleGoesIdle() {
        driveToReady(slotA)

        coordinator.acknowledge(slotID: slotA, userVisible: true)

        XCTAssertEqual(coordinator.state(for: slotA), .idle)
    }

    func testReadyAcknowledgementWhileNotUserVisibleStaysReady() {
        driveToReady(slotA)

        coordinator.acknowledge(slotID: slotA, userVisible: false)

        XCTAssertEqual(coordinator.state(for: slotA), .ready)
        XCTAssertEqual(coordinator.readySlotIDs, [slotA])
    }

    func testReadyToGeneratingOnNewGenerationStart() {
        driveToReady(slotA)

        coordinator.apply(.generationStarted, for: slotA)

        XCTAssertEqual(coordinator.state(for: slotA), .generating)
    }

    func testRuntimeResetFromGeneratingGoesIdle() {
        coordinator.apply(.generationStarted, for: slotA)

        coordinator.apply(.runtimeReset, for: slotA)

        XCTAssertEqual(coordinator.state(for: slotA), .idle)
        XCTAssertFalse(coordinator.isAttentionProtected(slotA))
    }

    func testRuntimeResetFromReadyGoesIdle() {
        driveToReady(slotA)

        coordinator.apply(.runtimeReset, for: slotA)

        XCTAssertEqual(coordinator.state(for: slotA), .idle)
        XCTAssertTrue(coordinator.readySlotIDs.isEmpty)
    }

    func testStrayGenerationFinishedFromIdleNeverCreatesReady() {
        coordinator.apply(.generationFinished(userVisible: false), for: slotA)

        XCTAssertEqual(coordinator.state(for: slotA), .idle)
        XCTAssertFalse(coordinator.isAttentionProtected(slotA))
        XCTAssertTrue(coordinator.readySlotIDs.isEmpty)

        // Also after a complete idle -> generating -> idle cycle: a late
        // duplicate finish must not latch a second result.
        coordinator.apply(.generationStarted, for: slotA)
        coordinator.apply(.generationFinished(userVisible: true), for: slotA)
        coordinator.apply(.generationFinished(userVisible: false), for: slotA)

        XCTAssertEqual(coordinator.state(for: slotA), .idle)
        XCTAssertTrue(coordinator.readySlotIDs.isEmpty)
    }

    func testAttentionProtectedOnlyWhileGeneratingOrReady() {
        XCTAssertFalse(coordinator.isAttentionProtected(slotA))

        coordinator.apply(.generationStarted, for: slotA)
        XCTAssertTrue(coordinator.isAttentionProtected(slotA))

        coordinator.apply(.generationFinished(userVisible: false), for: slotA)
        XCTAssertTrue(coordinator.isAttentionProtected(slotA))

        coordinator.acknowledge(slotID: slotA, userVisible: true)
        XCTAssertFalse(coordinator.isAttentionProtected(slotA))
    }

    func testReadySlotProjectionContainsOnlyReadySlots() {
        driveToReady(slotA)
        coordinator.apply(.generationStarted, for: slotB)

        XCTAssertEqual(coordinator.readySlotIDs, [slotA])

        coordinator.apply(.generationFinished(userVisible: true), for: slotB)

        XCTAssertEqual(coordinator.readySlotIDs, [slotA])
    }

    func testMultipleSlotsRemainIsolated() {
        driveToReady(slotA)
        coordinator.apply(.generationStarted, for: slotB)

        XCTAssertEqual(coordinator.state(for: slotA), .ready)
        XCTAssertEqual(coordinator.state(for: slotB), .generating)
        XCTAssertEqual(coordinator.readySlotIDs, [slotA])
    }

    func testResettingOrRemovingOneSlotLeavesOthersUntouched() {
        driveToReady(slotA)
        driveToReady(slotB)

        coordinator.apply(.runtimeReset, for: slotA)

        XCTAssertEqual(coordinator.state(for: slotA), .idle)
        XCTAssertEqual(coordinator.state(for: slotB), .ready)

        coordinator.removeSlot(slotB)

        XCTAssertEqual(coordinator.state(for: slotB), .idle)
        XCTAssertEqual(coordinator.state(for: slotA), .idle)
        XCTAssertTrue(coordinator.readySlotIDs.isEmpty)
    }

    func testRepeatedLifecycleCyclesWithoutStateLeak() {
        // Idle -> Generating -> Ready -> Idle -> Generating -> Idle.
        coordinator.apply(.generationStarted, for: slotA)
        XCTAssertEqual(coordinator.state(for: slotA), .generating)

        coordinator.apply(.generationFinished(userVisible: false), for: slotA)
        XCTAssertEqual(coordinator.state(for: slotA), .ready)

        coordinator.acknowledge(slotID: slotA, userVisible: true)
        XCTAssertEqual(coordinator.state(for: slotA), .idle)

        coordinator.apply(.generationStarted, for: slotA)
        XCTAssertEqual(coordinator.state(for: slotA), .generating)

        coordinator.apply(.generationFinished(userVisible: true), for: slotA)
        XCTAssertEqual(coordinator.state(for: slotA), .idle)

        XCTAssertFalse(coordinator.isAttentionProtected(slotA))
        XCTAssertTrue(coordinator.readySlotIDs.isEmpty)
    }

    func testTransitionDiagnosticsIncludeSemanticContext() {
        coordinator.apply(.generationStarted, for: slotA)
        coordinator.apply(.generationFinished(userVisible: false), for: slotA)
        coordinator.acknowledge(slotID: slotA, userVisible: true)
        coordinator.apply(.generationStarted, for: slotA)
        coordinator.apply(.generationFinished(userVisible: true), for: slotA)
        coordinator.apply(.generationStarted, for: slotA)
        coordinator.apply(.runtimeReset, for: slotA)

        let events = writer.events.filter { $0.event == "attention.transition" }
        XCTAssertEqual(events.count, 7)
        XCTAssertEqual(
            events.map { $0.fields["cause"] },
            [
                .string("generation_started"),
                .string("generation_finished"),
                .string("acknowledged"),
                .string("generation_started"),
                .string("generation_finished"),
                .string("generation_started"),
                .string("runtime_reset")
            ]
        )
        XCTAssertEqual(
            events.map { $0.fields["from"] },
            [
                .string("idle"),
                .string("generating"),
                .string("ready"),
                .string("idle"),
                .string("generating"),
                .string("idle"),
                .string("generating")
            ]
        )
        XCTAssertEqual(
            events.map { $0.fields["to"] },
            [
                .string("generating"),
                .string("ready"),
                .string("idle"),
                .string("generating"),
                .string("idle"),
                .string("generating"),
                .string("idle")
            ]
        )
        XCTAssertNil(events[0].fields["user_visible"])
        XCTAssertEqual(events[1].fields["user_visible"], .bool(false))
        XCTAssertEqual(events[2].fields["user_visible"], .bool(true))
        XCTAssertEqual(events[4].fields["user_visible"], .bool(true))
        XCTAssertNil(events[6].fields["user_visible"])
        XCTAssertTrue(events.allSatisfy { $0.fields["slot_id"] == .string(slotA.uuidString) })
    }

    func testNoOpAttentionTransitionStillDoesNotRecordDiagnostic() {
        coordinator.apply(.generationFinished(userVisible: false), for: slotA)
        coordinator.acknowledge(slotID: slotA, userVisible: false)

        XCTAssertTrue(writer.events.isEmpty)
    }

    /// Drives a Slot through Idle -> Generating -> Ready.
    private func driveToReady(_ slotID: UUID) {
        coordinator.apply(.generationStarted, for: slotID)
        coordinator.apply(.generationFinished(userVisible: false), for: slotID)
    }
}
