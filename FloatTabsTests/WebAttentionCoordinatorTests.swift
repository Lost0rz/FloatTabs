import XCTest
@testable import FloatTabs

@MainActor
final class WebAttentionCoordinatorTests: XCTestCase {
    private var coordinator: WebAttentionCoordinator!
    private var slotA: UUID!
    private var slotB: UUID!

    override func setUp() {
        super.setUp()
        coordinator = WebAttentionCoordinator()
        slotA = UUID()
        slotB = UUID()
    }

    override func tearDown() {
        coordinator = nil
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

    /// Drives a Slot through Idle -> Generating -> Ready.
    private func driveToReady(_ slotID: UUID) {
        coordinator.apply(.generationStarted, for: slotID)
        coordinator.apply(.generationFinished(userVisible: false), for: slotID)
    }
}
