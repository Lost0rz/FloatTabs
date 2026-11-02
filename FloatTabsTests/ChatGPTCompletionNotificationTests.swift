import UserNotifications
import XCTest
@testable import FloatTabs

/// Notification coordinator/backend coverage: rich title/body projection,
/// system-settings preflight, contextual authorization, submission
/// semantics, replacement, and exact-Slot routing.
///
/// Every test in this file drives the real coordinator through the injected
/// recording/fake backend. No test touches a real system notification center,
/// so authorization, delivery, withdrawal, replacement and routing are all
/// deterministic.
@MainActor
private final class RecordingCompletionNotificationBackend: ChatGPTCompletionNotificationBackend {
    enum Operation: Equatable {
        case installedDelegate
        case readSettings(ChatGPTNotificationSettingsFacts)
        case requestedAuthorization
        case withdrew(identifier: String)
        case delivered(ChatGPTCompletionNotificationRequest)
    }

    var settings = ChatGPTNotificationSettingsFacts(
        authorizationStatus: ChatGPTNotificationSettingsFacts.authorized,
        alertSetting: "enabled",
        alertStyle: "banner",
        notificationCenterSetting: "enabled",
        showPreviewsSetting: "enabled"
    )
    /// Settings returned after a contextual authorization request.
    var settingsAfterAuthorization: ChatGPTNotificationSettingsFacts?
    var authorizationGranted = true
    var deliverySucceeds = true

    private(set) var operations: [Operation] = []

    func notificationSettings() async -> ChatGPTNotificationSettingsFacts {
        operations.append(.readSettings(settings))
        return settings
    }

    func requestAlertAuthorization() async -> Bool {
        operations.append(.requestedAuthorization)
        if let settingsAfterAuthorization {
            settings = settingsAfterAuthorization
        }
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
        backend: RecordingCompletionNotificationBackend,
        diagnostics: (any RuntimeDiagnosticRecording)? = nil
    ) -> ChatGPTCompletionNotificationCoordinator {
        if let diagnostics {
            return ChatGPTCompletionNotificationCoordinator(
                backend: backend,
                diagnostics: diagnostics
            )
        }
        return ChatGPTCompletionNotificationCoordinator(backend: backend)
    }

    private func authorizedSettings(
        authorization: String = ChatGPTNotificationSettingsFacts.authorized,
        alertSetting: String = "enabled",
        alertStyle: String = "banner"
    ) -> ChatGPTNotificationSettingsFacts {
        ChatGPTNotificationSettingsFacts(
            authorizationStatus: authorization,
            alertSetting: alertSetting,
            alertStyle: alertStyle,
            notificationCenterSetting: "enabled",
            showPreviewsSetting: "enabled"
        )
    }

    /// The coordinator performs every system operation through the injected
    /// backend, in the frozen settings → (withdraw → deliver) order, with no
    /// real notification center involved. Already-authorized completions
    /// never re-request authorization.
    func testCoordinatorDelegatesAllSystemOperationsThroughInjectedBackend() async {
        let backend = RecordingCompletionNotificationBackend()
        let coordinator = makeCoordinator(backend: backend)
        let slotID = UUID()
        let settings = backend.settings

        await coordinator.performNotify(
            slotID: slotID,
            displayName: "Work Chat",
            assistantPreview: "Preview text"
        )

        XCTAssertEqual(backend.operations, [
            .readSettings(settings),
            .withdrew(identifier: ChatGPTCompletionNotificationCoordinator
                .notificationIdentifier(for: slotID)),
            .delivered(
                ChatGPTCompletionNotificationRequest(
                    identifier: ChatGPTCompletionNotificationCoordinator
                        .notificationIdentifier(for: slotID),
                    title: "Work Chat",
                    body: "Preview text",
                    payload: ChatGPTCompletionNotificationPayload(
                        version: ChatGPTCompletionNotificationPayload.currentVersion,
                        kind: ChatGPTCompletionNotificationPayload.kind,
                        slotID: slotID
                    )
                )
            )
        ])
    }

    /// The Slot display name becomes the title; a trusted preview becomes
    /// the body.
    func testSlotNameBecomesTitleAndPreviewBecomesBody() async {
        let backend = RecordingCompletionNotificationBackend()
        let coordinator = makeCoordinator(backend: backend)
        let slotID = UUID()

        await coordinator.performNotify(
            slotID: slotID,
            displayName: "Research Assistant",
            assistantPreview: "Here is the summary you asked for."
        )

        XCTAssertEqual(backend.deliveredRequests.count, 1)
        XCTAssertEqual(backend.deliveredRequests[0].title, "Research Assistant")
        XCTAssertEqual(
            backend.deliveredRequests[0].body,
            "Here is the summary you asked for."
        )
    }

    /// Missing name falls back to ChatGPT; missing preview falls back to the
    /// generic completion body.
    func testMissingProjectionInputFallsBackToGenericContent() async {
        let backend = RecordingCompletionNotificationBackend()
        let coordinator = makeCoordinator(backend: backend)
        let slotID = UUID()

        await coordinator.performNotify(
            slotID: slotID,
            displayName: nil,
            assistantPreview: nil
        )

        XCTAssertEqual(backend.deliveredRequests.count, 1)
        XCTAssertEqual(
            backend.deliveredRequests[0].title,
            ChatGPTCompletionNotificationCoordinator.notificationTitleFallback
        )
        XCTAssertEqual(
            backend.deliveredRequests[0].body,
            ChatGPTCompletionNotificationCoordinator.notificationBodyFallback
        )
    }

    /// An untrusted empty/whitespace preview still falls back; a preview of
    /// only whitespace is not a trusted preview.
    func testWhitespaceOnlyPreviewFallsBackToGenericBody() async {
        XCTAssertEqual(
            ChatGPTCompletionNotificationCoordinator.normalizedBody("   \n\t "),
            ChatGPTCompletionNotificationCoordinator.notificationBodyFallback
        )
        XCTAssertEqual(
            ChatGPTCompletionNotificationCoordinator.normalizedTitle("   \n\t "),
            ChatGPTCompletionNotificationCoordinator.notificationTitleFallback
        )
    }

    /// Title is capped at 80 user-perceived characters; body at 240.
    func testProjectionCapsAtFrozenCharacterLimits() {
        let longTitle = String(repeating: "t", count: 300)
        let longBody = String(repeating: "b", count: 1000)
        XCTAssertEqual(
            ChatGPTCompletionNotificationCoordinator.normalizedTitle(longTitle).count,
            80
        )
        XCTAssertEqual(
            ChatGPTCompletionNotificationCoordinator.normalizedBody(longBody).count,
            240
        )
        // Unicode safety: composed characters count as user-perceived
        // characters, not code points.
        let emojiBody = String(repeating: "😀", count: 300)
        XCTAssertEqual(
            ChatGPTCompletionNotificationCoordinator.normalizedBody(emojiBody).count,
            240
        )
    }

    /// Pathological internal whitespace collapses to single spacing.
    func testProjectionCollapsesInternalWhitespace() {
        XCTAssertEqual(
            ChatGPTCompletionNotificationCoordinator.normalizedTitle("  A\u{2028}B   C  "),
            "A B C"
        )
        XCTAssertEqual(
            ChatGPTCompletionNotificationCoordinator.normalizedBody(" line1 \n line2 \t\t end "),
            "line1 line2 end"
        )
    }

    /// notDetermined: authorization is requested contextually exactly once,
    /// settings are reread, and the completion is then submitted.
    func testNotDeterminedRequestsAuthorizationOnceAndRereadsSettings() async {
        let backend = RecordingCompletionNotificationBackend()
        backend.settings = authorizedSettings(
            authorization: ChatGPTNotificationSettingsFacts.notDetermined
        )
        backend.settingsAfterAuthorization = authorizedSettings()
        let coordinator = makeCoordinator(backend: backend)
        let slotID = UUID()

        await coordinator.performNotify(
            slotID: slotID,
            displayName: "Chat",
            assistantPreview: nil
        )

        XCTAssertEqual(backend.deliveredRequests.count, 1)
        XCTAssertEqual(
            backend.operations.filter { operation in
                if case .requestedAuthorization = operation { return true }
                return false
            }.count,
            1
        )
        // Settings were read twice: preflight + post-authorization reread.
        XCTAssertEqual(
            backend.operations.filter { operation in
                if case .readSettings = operation { return true }
                return false
            }.count,
            2
        )
    }

    /// Already-authorized completions never re-request authorization.
    func testAuthorizedCompletionNeverReRequestsAuthorization() async {
        let backend = RecordingCompletionNotificationBackend()
        let coordinator = makeCoordinator(backend: backend)
        let slotID = UUID()

        await coordinator.performNotify(
            slotID: slotID,
            displayName: "Chat",
            assistantPreview: nil
        )
        await coordinator.performNotify(
            slotID: slotID,
            displayName: "Chat",
            assistantPreview: nil
        )

        XCTAssertTrue(backend.operations.allSatisfy { operation in
            if case .requestedAuthorization = operation { return false }
            return true
        })
    }

    /// Denied authorization skips system submission only: no delivery, no
    /// withdrawal, no route callback.
    func testDeniedAuthorizationSkipsSubmissionWithoutProductSideEffects() async {
        let backend = RecordingCompletionNotificationBackend()
        backend.settings = authorizedSettings(
            authorization: ChatGPTNotificationSettingsFacts.denied
        )
        let coordinator = makeCoordinator(backend: backend)
        var routedSlots: [UUID] = []
        coordinator.onRouteSlot = { routedSlots.append($0) }
        let slotID = UUID()

        await coordinator.performNotify(
            slotID: slotID,
            displayName: "Chat",
            assistantPreview: "text"
        )

        XCTAssertEqual(backend.operations, [.readSettings(backend.settings)])
        XCTAssertTrue(backend.deliveredRequests.isEmpty)
        XCTAssertTrue(routedSlots.isEmpty)
    }

    /// An authorized app with alerts disabled still submits so Notification
    /// Center can apply the user's chosen policy; diagnostics make clear that
    /// a banner is not expected.
    func testAuthorizedWithAlertsDisabledStillSubmitsWithDiagnostics() async {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        let backend = RecordingCompletionNotificationBackend()
        backend.settings = authorizedSettings(
            alertSetting: "disabled",
            alertStyle: "none"
        )
        let coordinator = makeCoordinator(backend: backend, diagnostics: diagnostics)
        let slotID = UUID()

        await coordinator.performNotify(
            slotID: slotID,
            displayName: "Chat",
            assistantPreview: "preview"
        )

        XCTAssertEqual(backend.deliveredRequests.count, 1)
        let submitted = writer.events.first { $0.event == "notification.submitted" }
        XCTAssertNotNil(submitted)
        XCTAssertEqual(submitted?.fields["banner_expected"], .bool(false))
        XCTAssertEqual(submitted?.fields["alert_style"], .string("none"))
    }

    /// Submission success is recorded as system submission, not as proof of
    /// visible banner presentation, and settings facts are captured.
    func testDiagnosticsRecordSettingsFactsAndSubmissionSemantics() async {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        let backend = RecordingCompletionNotificationBackend()
        let coordinator = makeCoordinator(backend: backend, diagnostics: diagnostics)
        let slotID = UUID()
        let secretName = "Secret Slot Name"
        let secretPreview = "Secret assistant response preview"

        await coordinator.performNotify(
            slotID: slotID,
            displayName: secretName,
            assistantPreview: secretPreview
        )

        let settingsEvent = writer.events.first { $0.event == "notification.settings" }
        XCTAssertNotNil(settingsEvent)
        XCTAssertEqual(settingsEvent?.fields["permission_status"], .string("authorized"))
        XCTAssertEqual(settingsEvent?.fields["alert_setting"], .string("enabled"))
        XCTAssertEqual(settingsEvent?.fields["alert_style"], .string("banner"))
        XCTAssertEqual(settingsEvent?.fields["notification_center_setting"], .string("enabled"))
        XCTAssertEqual(settingsEvent?.fields["show_previews_setting"], .string("enabled"))
        XCTAssertEqual(
            settingsEvent?.fields["banner_expected"],
            nil
        )

        XCTAssertNotNil(
            writer.events.first { $0.event == "notification.submitted" }
        )
        // No diagnostic field anywhere carries the name or preview text.
        for event in writer.events {
            for (_, value) in event.fields {
                if case let .string(text) = value {
                    XCTAssertFalse(text.contains(secretName))
                    XCTAssertFalse(text.contains(secretPreview))
                }
            }
        }
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

        await coordinator.performNotify(
            slotID: slotID,
            displayName: "Chat",
            assistantPreview: nil
        )
        XCTAssertEqual(backend.deliveredRequests.count, 1)
        XCTAssertTrue(routedSlots.isEmpty)

        backend.deliverySucceeds = true
        await coordinator.performNotify(
            slotID: slotID,
            displayName: "Chat",
            assistantPreview: nil
        )
        XCTAssertEqual(backend.deliveredRequests.count, 2)
    }

    /// The production synchronous entry reaches the injected backend without
    /// any real system notification dependency.
    func testProductionNotifyEntryReachesInjectedBackend() async throws {
        let backend = RecordingCompletionNotificationBackend()
        let coordinator = makeCoordinator(backend: backend)
        let slotID = UUID()

        coordinator.notify(
            slotID: slotID,
            displayName: "Chat",
            assistantPreview: nil
        )

        for _ in 0..<200 where backend.deliveredRequests.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(backend.deliveredRequests.count, 1)
    }

    /// Same Slot always maps to the same deterministic identifier.
    func testSameSlotUsesDeterministicIdentifier() async {
        let backend = RecordingCompletionNotificationBackend()
        let coordinator = makeCoordinator(backend: backend)
        let slotID = UUID()

        await coordinator.performNotify(slotID: slotID, displayName: nil, assistantPreview: nil)
        await coordinator.performNotify(slotID: slotID, displayName: nil, assistantPreview: nil)

        XCTAssertEqual(backend.deliveredRequests.count, 2)
        XCTAssertEqual(
            backend.deliveredRequests.map(\.identifier),
            [
                ChatGPTCompletionNotificationCoordinator.notificationIdentifier(for: slotID),
                ChatGPTCompletionNotificationCoordinator.notificationIdentifier(for: slotID)
            ]
        )
    }

    /// A newer same-Slot completion explicitly withdraws prior same-Slot
    /// system notification state before delivering the replacement.
    func testSameSlotSecondCompletionWithdrawsPriorStateBeforeReplacement() async {
        let backend = RecordingCompletionNotificationBackend()
        let coordinator = makeCoordinator(backend: backend)
        let slotID = UUID()
        let identifier = ChatGPTCompletionNotificationCoordinator
            .notificationIdentifier(for: slotID)

        await coordinator.performNotify(slotID: slotID, displayName: nil, assistantPreview: nil)
        await coordinator.performNotify(slotID: slotID, displayName: nil, assistantPreview: nil)

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

    /// Different Slots use independent identifiers and never withdraw
    /// each other's notification state.
    func testDifferentSlotsRemainIndependent() async {
        let backend = RecordingCompletionNotificationBackend()
        let coordinator = makeCoordinator(backend: backend)
        let slotA = UUID()
        let slotB = UUID()

        await coordinator.performNotify(slotID: slotA, displayName: nil, assistantPreview: nil)
        await coordinator.performNotify(slotID: slotB, displayName: nil, assistantPreview: nil)

        XCTAssertEqual(backend.withdrawnIdentifiers, [
            ChatGPTCompletionNotificationCoordinator.notificationIdentifier(for: slotA),
            ChatGPTCompletionNotificationCoordinator.notificationIdentifier(for: slotB)
        ])
        XCTAssertEqual(backend.deliveredRequests.map(\.identifier), [
            ChatGPTCompletionNotificationCoordinator.notificationIdentifier(for: slotA),
            ChatGPTCompletionNotificationCoordinator.notificationIdentifier(for: slotB)
        ])
    }

    /// The payload carries exactly version/kind/slot_id and nothing else —
    /// no Slot name, response preview, prompt, response, URL, Profile, or
    /// session content.
    func testPayloadIsBoundedToVersionKindAndSlotID() async {
        let backend = RecordingCompletionNotificationBackend()
        let coordinator = makeCoordinator(backend: backend)
        let slotID = UUID()

        await coordinator.performNotify(
            slotID: slotID,
            displayName: "Named Slot",
            assistantPreview: "Assistant preview text"
        )

        let userInfo = backend.deliveredRequests[0].payload.userInfo
        XCTAssertEqual(
            Set(userInfo.keys.compactMap { $0 as? String }),
            ["version", "kind", "slot_id"]
        )
        XCTAssertEqual(userInfo["version"] as? Int, 1)
        XCTAssertEqual(userInfo["kind"] as? String, "chatgpt_completion")
        XCTAssertEqual(userInfo["slot_id"] as? String, slotID.uuidString)
        XCTAssertFalse(
            userInfo.values.contains { value in
                (value as? String)?.contains("Named Slot") == true
                    || (value as? String)?.contains("Assistant preview text") == true
            }
        )
    }

    /// Exact routing is recovered from the bounded system payload alone — a
    /// notification stays routable with no prior notify and no
    /// coordinator-owned in-memory record.
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

    /// Only the default action routes the exact Slot UUID.
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

    /// Dismissal never routes.
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

    /// A malformed Slot UUID never routes.
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

    /// Unknown version or kind never routes.
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

    /// A recognized foreground completion presents as banner/list with no
    /// notification sound.
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

    /// An unknown notification is not presented as a completion.
    func testForegroundUnknownNotificationIsNotPresented() {
        let backend = RecordingCompletionNotificationBackend()
        let coordinator = makeCoordinator(backend: backend)

        let options = coordinator.foregroundPresentationOptions(
            userInfo: ["unrelated": true]
        )

        XCTAssertTrue(options.isEmpty)
    }

    /// The notification-center delegate is installed during app startup,
    /// before any delivery can occur.
    func testDelegateIsInstalledAtStartupThroughBackend() {
        let backend = RecordingCompletionNotificationBackend()
        let coordinator = makeCoordinator(backend: backend)

        coordinator.installAtStartup()

        XCTAssertEqual(backend.operations, [.installedDelegate])
    }
}
