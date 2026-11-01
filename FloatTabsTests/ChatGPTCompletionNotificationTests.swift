import UserNotifications
import XCTest
@testable import FloatTabs

/// Gate A — Phase 3 notification coordinator/backend coverage.
///
/// Every test in this file drives the real coordinator through the injected
/// recording/fake backend. No test touches a real system notification center,
/// so authorization, delivery, withdrawal, replacement and routing are all
/// deterministic.
@MainActor
private final class RecordingCompletionNotificationBackend: ChatGPTCompletionNotificationBackend {
    enum Operation: Equatable {
        case installedDelegate
        case requestedAuthorization
        case withdrew(identifier: String)
        case delivered(ChatGPTCompletionNotificationRequest)
    }

    var authorizationGranted = true
    var deliverySucceeds = true

    private(set) var operations: [Operation] = []

    func requestAlertAuthorization() async -> Bool {
        operations.append(.requestedAuthorization)
        return authorizationGranted
    }

    func withdraw(identifier: String) async {
        operations.append(.withdrew(identifier: identifier))
    }

    func deliver(_ request: ChatGPTCompletionNotificationRequest) async -> Bool {
        operations.append(.delivered(request))
        return deliverySucceeds
    }

    func installDelegate(_ delegate: UNUserNotificationCenterDelegate) {
        operations.append(.installedDelegate)
    }

    var deliveredRequests: [ChatGPTCompletionNotificationRequest] {
        operations.compactMap { operation in
            guard case let .delivered(request) = operation else { return nil }
            return request
        }
    }

    var withdrawnIdentifiers: [String] {
        operations.compactMap { operation in
            guard case let .withdrew(identifier) = operation else { return nil }
            return identifier
        }
    }
}

@MainActor
final class ChatGPTCompletionNotificationTests: XCTestCase {
    private func makeCoordinator(
        backend: RecordingCompletionNotificationBackend
    ) -> ChatGPTCompletionNotificationCoordinator {
        ChatGPTCompletionNotificationCoordinator(backend: backend)
    }

    /// J1/J5: the coordinator performs every system operation through the
    /// injected backend, in the frozen authorization → withdraw → deliver
    /// order, with no real notification center involved.
    func testCoordinatorDelegatesAllSystemOperationsThroughInjectedBackend() async {
        let backend = RecordingCompletionNotificationBackend()
        let coordinator = makeCoordinator(backend: backend)
        let slotID = UUID()

        await coordinator.performNotify(slotID: slotID)

        XCTAssertEqual(backend.operations, [
            .requestedAuthorization,
            .withdrew(identifier: ChatGPTCompletionNotificationCoordinator
                .notificationIdentifier(for: slotID)),
            .delivered(
                ChatGPTCompletionNotificationRequest(
                    identifier: ChatGPTCompletionNotificationCoordinator
                        .notificationIdentifier(for: slotID),
                    title: ChatGPTCompletionNotificationCoordinator.notificationTitle,
                    body: ChatGPTCompletionNotificationCoordinator.notificationBody,
                    payload: ChatGPTCompletionNotificationPayload(
                        version: ChatGPTCompletionNotificationPayload.currentVersion,
                        kind: ChatGPTCompletionNotificationPayload.kind,
                        slotID: slotID
                    )
                )
            )
        ])
    }

    /// J2: granted alert authorization schedules exactly one generic request.
    func testGrantedAuthorizationDeliversExactlyOneGenericRequest() async {
        let backend = RecordingCompletionNotificationBackend()
        let coordinator = makeCoordinator(backend: backend)
        let slotID = UUID()

        await coordinator.performNotify(slotID: slotID)

        XCTAssertEqual(backend.deliveredRequests.count, 1)
        let request = backend.deliveredRequests[0]
        XCTAssertEqual(request.title, "FloatTabs")
        XCTAssertEqual(request.body, "A ChatGPT response is ready.")
        XCTAssertEqual(
            request.identifier,
            "floattabs.chatgpt-completion." + slotID.uuidString
        )
    }

    /// J3/J4: denied/error/unavailable authorization schedules no delivery,
    /// no withdrawal, and no route callback — a projection failure only.
    func testDeniedOrUnavailableAuthorizationSchedulesNoDelivery() async {
        let backend = RecordingCompletionNotificationBackend()
        backend.authorizationGranted = false
        let coordinator = makeCoordinator(backend: backend)
        var routedSlots: [UUID] = []
        coordinator.onRouteSlot = { routedSlots.append($0) }
        let slotID = UUID()

        await coordinator.performNotify(slotID: slotID)

        XCTAssertEqual(backend.operations, [.requestedAuthorization])
        XCTAssertTrue(backend.deliveredRequests.isEmpty)
        XCTAssertTrue(routedSlots.isEmpty)
    }

    /// A failing delivery is a projection failure only: the route surface and
    /// later attempts are unaffected.
    func testDeliveryFailureIsProjectionFailureOnly() async {
        let backend = RecordingCompletionNotificationBackend()
        backend.deliverySucceeds = false
        let coordinator = makeCoordinator(backend: backend)
        var routedSlots: [UUID] = []
        coordinator.onRouteSlot = { routedSlots.append($0) }
        let slotID = UUID()

        await coordinator.performNotify(slotID: slotID)
        XCTAssertEqual(backend.deliveredRequests.count, 1)
        XCTAssertTrue(routedSlots.isEmpty)

        backend.deliverySucceeds = true
        await coordinator.performNotify(slotID: slotID)
        XCTAssertEqual(backend.deliveredRequests.count, 2)
    }

    /// The production synchronous entry reaches the injected backend without
    /// any real system notification dependency.
    func testProductionNotifyEntryReachesInjectedBackend() async throws {
        let backend = RecordingCompletionNotificationBackend()
        let coordinator = makeCoordinator(backend: backend)
        let slotID = UUID()

        coordinator.notify(slotID: slotID)

        for _ in 0..<200 where backend.deliveredRequests.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(backend.deliveredRequests.count, 1)
    }

    /// J6: same Slot always maps to the same deterministic identifier.
    func testSameSlotUsesDeterministicIdentifier() async {
        let backend = RecordingCompletionNotificationBackend()
        let coordinator = makeCoordinator(backend: backend)
        let slotID = UUID()

        await coordinator.performNotify(slotID: slotID)
        await coordinator.performNotify(slotID: slotID)

        XCTAssertEqual(backend.deliveredRequests.count, 2)
        XCTAssertEqual(
            backend.deliveredRequests.map(\.identifier),
            [
                ChatGPTCompletionNotificationCoordinator.notificationIdentifier(for: slotID),
                ChatGPTCompletionNotificationCoordinator.notificationIdentifier(for: slotID)
            ]
        )
    }

    /// J7: a newer same-Slot completion explicitly withdraws prior same-Slot
    /// system notification state before delivering the replacement.
    func testSameSlotSecondCompletionWithdrawsPriorStateBeforeReplacement() async {
        let backend = RecordingCompletionNotificationBackend()
        let coordinator = makeCoordinator(backend: backend)
        let slotID = UUID()
        let identifier = ChatGPTCompletionNotificationCoordinator
            .notificationIdentifier(for: slotID)

        await coordinator.performNotify(slotID: slotID)
        await coordinator.performNotify(slotID: slotID)

        XCTAssertEqual(backend.withdrawnIdentifiers, [identifier, identifier])
        let firstDeliverIndex = backend.operations.firstIndex {
            if case .delivered = $0 { return true }
            return false
        }
        let secondWithdrawIndex = backend.operations.lastIndex {
            if case .withdrew = $0 { return true }
            return false
        }
        guard let firstDeliverIndex, let secondWithdrawIndex else {
            return XCTFail("Expected two deliveries and a trailing withdrawal")
        }
        XCTAssertLessThan(
            firstDeliverIndex,
            secondWithdrawIndex,
            "The second same-Slot delivery must withdraw the first delivery first"
        )
    }

    /// J8: different Slots use independent identifiers and never withdraw
    /// each other's notification state.
    func testDifferentSlotsRemainIndependent() async {
        let backend = RecordingCompletionNotificationBackend()
        let coordinator = makeCoordinator(backend: backend)
        let slotA = UUID()
        let slotB = UUID()

        await coordinator.performNotify(slotID: slotA)
        await coordinator.performNotify(slotID: slotB)

        XCTAssertEqual(backend.withdrawnIdentifiers, [
            ChatGPTCompletionNotificationCoordinator.notificationIdentifier(for: slotA),
            ChatGPTCompletionNotificationCoordinator.notificationIdentifier(for: slotB)
        ])
        XCTAssertEqual(backend.deliveredRequests.map(\.identifier), [
            ChatGPTCompletionNotificationCoordinator.notificationIdentifier(for: slotA),
            ChatGPTCompletionNotificationCoordinator.notificationIdentifier(for: slotB)
        ])
    }

    /// J9: the payload carries exactly version/kind/slot_id and nothing else —
    /// no prompt, response, URL, Profile, or session content.
    func testPayloadIsBoundedToVersionKindAndSlotID() async {
        let backend = RecordingCompletionNotificationBackend()
        let coordinator = makeCoordinator(backend: backend)
        let slotID = UUID()

        await coordinator.performNotify(slotID: slotID)

        let userInfo = backend.deliveredRequests[0].payload.userInfo
        XCTAssertEqual(
            Set(userInfo.keys.compactMap { $0 as? String }),
            ["version", "kind", "slot_id"]
        )
        XCTAssertEqual(userInfo["version"] as? Int, 1)
        XCTAssertEqual(userInfo["kind"] as? String, "chatgpt_completion")
        XCTAssertEqual(userInfo["slot_id"] as? String, slotID.uuidString)
    }

    /// J14 + Gate C6: exact routing is recovered from the bounded system
    /// payload alone — a notification stays routable with no prior notify and
    /// no coordinator-owned in-memory record.
    func testRoutingRequiresNoInMemoryNotificationRecord() {
        let backend = RecordingCompletionNotificationBackend()
        let coordinator = makeCoordinator(backend: backend)
        var routedSlots: [UUID] = []
        coordinator.onRouteSlot = { routedSlots.append($0) }
        let slotID = UUID()

        coordinator.handleNotificationResponse(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: [
                "version": 1,
                "kind": "chatgpt_completion",
                "slot_id": slotID.uuidString
            ]
        )

        XCTAssertEqual(routedSlots, [slotID])
    }

    /// J10: only the default action routes the exact Slot UUID.
    func testDefaultActionRoutesExactSlotUUID() {
        let backend = RecordingCompletionNotificationBackend()
        let coordinator = makeCoordinator(backend: backend)
        var routedSlots: [UUID] = []
        coordinator.onRouteSlot = { routedSlots.append($0) }
        let slotID = UUID()

        coordinator.handleNotificationResponse(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: ChatGPTCompletionNotificationPayload(
                version: 1,
                kind: "chatgpt_completion",
                slotID: slotID
            ).userInfo
        )

        XCTAssertEqual(routedSlots, [slotID])
    }

    /// J11: dismissal never routes.
    func testDismissalDoesNotRoute() {
        let backend = RecordingCompletionNotificationBackend()
        let coordinator = makeCoordinator(backend: backend)
        var routedSlots: [UUID] = []
        coordinator.onRouteSlot = { routedSlots.append($0) }
        let slotID = UUID()

        coordinator.handleNotificationResponse(
            actionIdentifier: UNNotificationDismissActionIdentifier,
            userInfo: ChatGPTCompletionNotificationPayload(
                version: 1,
                kind: "chatgpt_completion",
                slotID: slotID
            ).userInfo
        )

        XCTAssertTrue(routedSlots.isEmpty)
    }

    /// J12: a malformed Slot UUID never routes.
    func testMalformedSlotUUIDDoesNotRoute() {
        let backend = RecordingCompletionNotificationBackend()
        let coordinator = makeCoordinator(backend: backend)
        var routedSlots: [UUID] = []
        coordinator.onRouteSlot = { routedSlots.append($0) }

        coordinator.handleNotificationResponse(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: [
                "version": 1,
                "kind": "chatgpt_completion",
                "slot_id": "not-a-uuid"
            ]
        )

        XCTAssertTrue(routedSlots.isEmpty)
    }

    /// J13: unknown version or kind never routes.
    func testUnknownVersionOrKindDoesNotRoute() {
        let backend = RecordingCompletionNotificationBackend()
        let coordinator = makeCoordinator(backend: backend)
        var routedSlots: [UUID] = []
        coordinator.onRouteSlot = { routedSlots.append($0) }
        let slotID = UUID()

        coordinator.handleNotificationResponse(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: [
                "version": 2,
                "kind": "chatgpt_completion",
                "slot_id": slotID.uuidString
            ]
        )
        coordinator.handleNotificationResponse(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: [
                "version": 1,
                "kind": "web_notification",
                "slot_id": slotID.uuidString
            ]
        )

        XCTAssertTrue(routedSlots.isEmpty)
    }

    /// J14: a recognized foreground completion presents as banner/list with
    /// no notification sound.
    func testForegroundRecognizedCompletionPresentsBannerAndListWithoutSound() {
        let backend = RecordingCompletionNotificationBackend()
        let coordinator = makeCoordinator(backend: backend)
        let slotID = UUID()

        let options = coordinator.foregroundPresentationOptions(
            userInfo: ChatGPTCompletionNotificationPayload(
                version: 1,
                kind: "chatgpt_completion",
                slotID: slotID
            ).userInfo
        )

        XCTAssertEqual(options, [.banner, .list])
        XCTAssertFalse(options.contains(.sound))
    }

    /// J14: an unknown notification is not presented as a Phase 3 completion.
    func testForegroundUnknownNotificationIsNotPresented() {
        let backend = RecordingCompletionNotificationBackend()
        let coordinator = makeCoordinator(backend: backend)

        let options = coordinator.foregroundPresentationOptions(
            userInfo: ["unrelated": true]
        )

        XCTAssertTrue(options.isEmpty)
    }

    /// E: the notification-center delegate is installed during app startup,
    /// before any delivery can occur.
    func testDelegateIsInstalledAtStartupThroughBackend() {
        let backend = RecordingCompletionNotificationBackend()
        let coordinator = makeCoordinator(backend: backend)

        coordinator.installAtStartup()

        XCTAssertEqual(backend.operations, [.installedDelegate])
    }
}
