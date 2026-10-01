import Foundation
import XCTest
@testable import FloatTabs

@MainActor
final class RuntimeDiagnosticsTests: XCTestCase {
    func testEventsEncodeAsIndependentJSONLObjectsWithSessionAndMonotonicSequence() throws {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let diagnostics = RuntimeDiagnostics(
            mode: .verbose,
            writer: writer,
            sessionID: sessionID,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            uptime: { 42 }
        )

        diagnostics.record(
            event: "test.first",
            level: .notice,
            subsystem: "tests",
            fields: ["value": .integer(1)]
        )
        diagnostics.record(
            event: "test.second",
            level: .warning,
            subsystem: "tests",
            fields: ["value": .integer(2)]
        )

        let lines = writer.lines
        XCTAssertEqual(lines.count, 2)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let events = try lines.map {
            try decoder.decode(RuntimeDiagnosticEvent.self, from: $0)
        }
        XCTAssertTrue(String(data: lines[0], encoding: .utf8)?.contains("\"schema_version\":1") == true)
        XCTAssertEqual(events.map(\.schemaVersion), [1, 1])
        XCTAssertEqual(Set(events.map(\.sessionID)).count, 1)
        XCTAssertEqual(events.map(\.sequence), [1, 2])
    }

    func testStandardSuppressesDebugAndOffSuppressesEverything() {
        let standardWriter = RuntimeDiagnosticInMemoryWriter()
        let standard = RuntimeDiagnostics(mode: .standard, writer: standardWriter)
        standard.record(event: "test.debug", level: .debug, subsystem: "tests")
        standard.record(event: "test.notice", level: .notice, subsystem: "tests")
        XCTAssertEqual(standardWriter.events.map(\.event), ["test.notice"])

        let offWriter = RuntimeDiagnosticInMemoryWriter()
        let off = RuntimeDiagnostics(mode: .off, writer: offWriter)
        off.record(event: "test.notice", level: .notice, subsystem: "tests")
        XCTAssertTrue(offWriter.events.isEmpty)
    }

    func testRAW_IDENTITY_NOT_DIAGNOSTIC() {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .verbose, writer: writer)
        diagnostics.record(
            event: "unread.test",
            level: .info,
            subsystem: "unread",
            fields: [
                "response_identity": .string("message:secret-response"),
                "response_id": .string("document:response"),
                "document_token": .string("document-secret"),
                "responseidentity_class": .string("already_handled_response"),
                "safe_flag": .bool(true)
            ]
        )

        let fields = writer.events.first?.fields ?? [:]
        XCTAssertNil(fields["response_identity"])
        XCTAssertNil(fields["response_id"])
        XCTAssertNil(fields["document_token"])
        XCTAssertNil(fields["responseidentity_class"])
        XCTAssertEqual(fields["safe_flag"], .bool(true))
    }

    func testStandardRetainsCriticalTransactionBoundariesAtInfoOrHigher() {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        let criticalEvents = [
            "menubar.toggle.intent",
            "menubar.toggle.dispatch",
            "source.order_front",
            "source.focus.result",
            "previous_app.capture"
        ]

        for event in criticalEvents {
            diagnostics.record(event: event, level: .info, subsystem: "tests")
        }

        XCTAssertEqual(writer.events.map(\.event), criticalEvents)
        XCTAssertTrue(writer.events.allSatisfy { $0.level != .debug })
    }

    func testExportAddsRecentEventsBeforeSanitizedMetadata() throws {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        diagnostics.record(
            event: "test.navigation",
            level: .notice,
            subsystem: "tests",
            fields: [
                "url": .string("https://example.com/c/private?token=secret")
            ]
        )

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsExport-\(UUID().uuidString).jsonl")
        let exported = expectation(description: "exported")
        var result: Result<Void, RuntimeDiagnosticExportError>?
        diagnostics.exportRecent(to: destination) {
            result = $0
            exported.fulfill()
        }
        wait(for: [exported], timeout: 2)

        guard case .success = result else {
            return XCTFail("diagnostics export failed: \(String(describing: result))")
        }
        let lines = try String(contentsOf: destination, encoding: .utf8)
            .split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let events = try lines.map {
            try decoder.decode(RuntimeDiagnosticEvent.self, from: Data($0.utf8))
        }
        XCTAssertEqual(events[0].fields["url"], .string("https://example.com"))
        XCTAssertFalse(String(data: Data(lines[0].utf8), encoding: .utf8)?.contains("token") == true)
        XCTAssertEqual(events[1].event, "diagnostics.export.metadata")
        XCTAssertEqual(events[1].fields["schema_version"], .integer(1))
        XCTAssertNotNil(events[1].fields["app_version"])
        try? FileManager.default.removeItem(at: destination)
    }

    func testExportMetadataConsumesSequenceAndNextRuntimeEventContinuesOrdering() throws {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let diagnostics = RuntimeDiagnostics(
            mode: .standard,
            writer: writer,
            sessionID: sessionID,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            uptime: { 42 }
        )
        diagnostics.record(event: "test.first", level: .notice, subsystem: "tests")
        diagnostics.record(event: "test.second", level: .notice, subsystem: "tests")

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsExport-\(UUID().uuidString).jsonl")
        let exported = expectation(description: "exported")
        var result: Result<Void, RuntimeDiagnosticExportError>?
        diagnostics.exportRecent(to: destination) {
            result = $0
            exported.fulfill()
        }
        wait(for: [exported], timeout: 2)
        guard case .success = result else {
            return XCTFail("diagnostics export failed: \(String(describing: result))")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let events = try String(contentsOf: destination, encoding: .utf8)
            .split(separator: "\n")
            .map { try decoder.decode(RuntimeDiagnosticEvent.self, from: Data($0.utf8)) }
        XCTAssertEqual(events.map(\.sequence), [1, 2, 3])
        XCTAssertEqual(events.last?.event, "diagnostics.export.metadata")

        diagnostics.record(event: "test.after-export", level: .notice, subsystem: "tests")
        XCTAssertEqual(writer.events.last?.sequence, 4)
        try? FileManager.default.removeItem(at: destination)
    }

    func testTraceRootIsPresentWithoutCreatingPerEventTraceIDs() {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .verbose, writer: writer)
        let trace = diagnostics.beginTrace(root: "panel.summon")

        diagnostics.record(event: "panel.summon.received", subsystem: "panel", trace: trace)
        diagnostics.record(event: "panel.presentation.begin", subsystem: "panel", trace: trace)

        XCTAssertEqual(writer.events.map(\.traceID), [trace.id, trace.id])
        XCTAssertEqual(
            writer.events.map { $0.fields["trace_root"] },
            [.string("panel.summon"), .string("panel.summon")]
        )
    }

    func testStandardRetainsAllRestoreObservationEvents() {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)

        [
            "previous_app.capture",
            "previous_app.restore.decision",
            "previous_app.restore.requested",
            "previous_app.restore.request_result",
            "previous_app.restore.observed",
            "panel.auto_hide.decision"
        ].forEach { event in
            diagnostics.record(event: event, level: .info, subsystem: "panel")
        }

        XCTAssertEqual(
            writer.events.map(\.event),
            [
                "previous_app.capture",
                "previous_app.restore.decision",
                "previous_app.restore.requested",
                "previous_app.restore.request_result",
                "previous_app.restore.observed",
                "panel.auto_hide.decision"
            ]
        )
    }

    func testDismissSourceTaxonomyDistinguishesExplicitAndAutomaticHides() {
        XCTAssertEqual(RuntimeDiagnosticDismissSource.hotkey.classification, .explicit)
        XCTAssertEqual(RuntimeDiagnosticDismissSource.menubar.classification, .explicit)
        XCTAssertEqual(RuntimeDiagnosticDismissSource.externalCommand.classification, .explicit)
        XCTAssertEqual(RuntimeDiagnosticDismissSource.workspaceActivation.classification, .automatic)
        XCTAssertEqual(RuntimeDiagnosticDismissSource.globalMouse.classification, .automatic)
        XCTAssertEqual(RuntimeDiagnosticDismissSource.fullscreen.classification, .explicit)
        XCTAssertEqual(RuntimeDiagnosticDismissSource.internal.classification, .explicit)
    }

    func testAutoHideObservationDecisionReasonsAreStable() {
        XCTAssertEqual(
            RuntimeDiagnosticAutoHideObservationDecision.workspace(
                panelVisible: true,
                pinned: false,
                suppressionActive: true,
                presentationFocusPending: false,
                frontmostMatches: true
            ),
            .ignore(reason: .suppressionGrace)
        )
        XCTAssertEqual(
            RuntimeDiagnosticAutoHideObservationDecision.workspace(
                panelVisible: true,
                pinned: false,
                suppressionActive: false,
                presentationFocusPending: true,
                frontmostMatches: true
            ),
            .ignore(reason: .presentationFocusPending)
        )
        XCTAssertEqual(
            RuntimeDiagnosticAutoHideObservationDecision.workspace(
                panelVisible: true,
                pinned: true,
                suppressionActive: false,
                presentationFocusPending: false,
                frontmostMatches: true
            ),
            .ignore(reason: .pinned)
        )
        XCTAssertEqual(
            RuntimeDiagnosticAutoHideObservationDecision.workspace(
                panelVisible: true,
                pinned: false,
                suppressionActive: false,
                presentationFocusPending: false,
                frontmostMatches: false
            ),
            .ignore(reason: .frontmostMismatch)
        )
        XCTAssertEqual(
            RuntimeDiagnosticAutoHideObservationDecision.workspace(
                panelVisible: false,
                pinned: false,
                suppressionActive: false,
                presentationFocusPending: false,
                frontmostMatches: true
            ),
            .ignore(reason: .panelNotVisible)
        )
        XCTAssertEqual(
            RuntimeDiagnosticAutoHideObservationDecision.workspace(
                panelVisible: true,
                pinned: false,
                suppressionActive: false,
                presentationFocusPending: false,
                frontmostMatches: true,
                activatedApplicationIsOwn: true
            ),
            .ignore(reason: .ownApplication)
        )
        XCTAssertEqual(
            RuntimeDiagnosticAutoHideObservationDecision.globalMouse(
                panelVisible: true,
                pinned: false,
                insidePresentation: false,
                staleEvent: true
            ),
            .ignore(reason: .staleMouseEvent)
        )
        XCTAssertEqual(
            RuntimeDiagnosticAutoHideObservationDecision.globalMouse(
                panelVisible: true,
                pinned: false,
                insidePresentation: false,
                staleEvent: false
            ),
            .hide
        )
        XCTAssertEqual(
            RuntimeDiagnosticAutoHideObservationDecision.globalMouse(
                panelVisible: true,
                pinned: false,
                insidePresentation: true,
                staleEvent: false
            ),
            .ignore(reason: .insidePresentation)
        )
    }

    func testRestoreObservationTrackerRejectsStaleTicket() {
        var tracker = RuntimeDiagnosticRestoreObservationTracker()
        let first = tracker.begin(trace: RuntimeDiagnosticTrace(root: "dismiss-A"))
        let second = tracker.begin(trace: RuntimeDiagnosticTrace(root: "dismiss-B"))

        XCTAssertFalse(tracker.accepts(first))
        XCTAssertTrue(tracker.accepts(second))
        XCTAssertEqual(tracker.trace(for: second)?.root, "dismiss-B")
    }

    func testRestoreObservationTrackerInvalidationCannotConsumeLaterTicket() {
        var tracker = RuntimeDiagnosticRestoreObservationTracker()
        let first = tracker.begin(trace: RuntimeDiagnosticTrace(root: "dismiss-A"))

        tracker.invalidate()
        let later = tracker.begin(trace: RuntimeDiagnosticTrace(root: "dismiss-C"))

        XCTAssertNil(tracker.consume(first))
        XCTAssertTrue(tracker.accepts(later))
        XCTAssertEqual(tracker.consume(later)?.trace.root, "dismiss-C")
    }
}

@MainActor
private final class RendererProbeJavaScriptEvaluatorCapture {
    var completion: (@Sendable (Any?, Error?) -> Void)?
}

final class RuntimeDiagnosticsInstrumentationTests: XCTestCase {
    func testPassiveResponsiveStallNeverRequestsRecovery() {
        var tracker = WebRuntimeRecoveryTracker(runtimeGeneration: 1)
        let navigation = WebRuntimeNavigationTicket(runtimeGeneration: 1, navigationGeneration: 1)

        XCTAssertEqual(tracker.navigationStarted(navigation), .passive)
        XCTAssertNil(tracker.requestSoftRecovery(
            for: navigation,
            classification: .rendererResponsiveNavigationStall
        ))
    }

    func testUserReloadCanRequestOnlyOneResponsiveSoftRecovery() throws {
        var tracker = WebRuntimeRecoveryTracker(runtimeGeneration: 4)
        _ = tracker.recordUserAction(.reload, navigationGenerationBefore: 0)
        let navigation = WebRuntimeNavigationTicket(runtimeGeneration: 4, navigationGeneration: 1)

        XCTAssertEqual(tracker.navigationStarted(navigation), .userAction(generation: 1))
        let request = try XCTUnwrap(tracker.requestSoftRecovery(
            for: navigation,
            classification: .rendererResponsiveNavigationStall
        ))
        XCTAssertEqual(request.ticket.action, .reload)
        XCTAssertNil(tracker.requestSoftRecovery(
            for: navigation,
            classification: .rendererResponsiveNavigationStall
        ))
    }

    func testUserHomeRecoveryRetainsTheSameHomeIntentAndEntryFallback() throws {
        let homeURL = URL(string: "https://example.test/start")!
        var tracker = WebRuntimeRecoveryTracker(runtimeGeneration: 5)
        _ = tracker.recordUserAction(
            .home,
            navigationGenerationBefore: 0,
            homeURL: homeURL,
            homeURLSchemeWasInferred: true
        )
        let navigation = WebRuntimeNavigationTicket(runtimeGeneration: 5, navigationGeneration: 1)
        _ = tracker.navigationStarted(navigation)

        let request = try XCTUnwrap(tracker.requestSoftRecovery(
            for: navigation,
            classification: .rendererResponsiveNavigationStall
        ))
        XCTAssertEqual(request.ticket.action, .home)
        XCTAssertEqual(request.homeURL, homeURL)
        XCTAssertTrue(request.homeURLSchemeWasInferred)
    }

    func testOnlyRendererTimeoutIsHardRecoveryCandidate() {
        XCTAssertFalse(WebRuntimeRecoveryClassification(probeResult: .success).isHardRecoveryCandidate)
        XCTAssertFalse(WebRuntimeRecoveryClassification(probeResult: .failed).isHardRecoveryCandidate)
        XCTAssertTrue(WebRuntimeRecoveryClassification(probeResult: .timeout).isHardRecoveryCandidate)
    }

    func testFailedRendererProbeDoesNotRequestSoftOrHardRecovery() {
        var tracker = WebRuntimeRecoveryTracker(runtimeGeneration: 5)
        _ = tracker.recordUserAction(.reload, navigationGenerationBefore: 0)
        let navigation = WebRuntimeNavigationTicket(runtimeGeneration: 5, navigationGeneration: 1)
        _ = tracker.navigationStarted(navigation)

        XCTAssertNil(tracker.requestSoftRecovery(
            for: navigation,
            classification: WebRuntimeRecoveryClassification(probeResult: .failed)
        ))
        XCTAssertNotNil(tracker.userActionContext(for: navigation))
    }

    func testNewNavigationMakesPendingSoftRecoveryStale() throws {
        var tracker = WebRuntimeRecoveryTracker(runtimeGeneration: 6)
        _ = tracker.recordUserAction(.reload, navigationGenerationBefore: 0)
        let original = WebRuntimeNavigationTicket(runtimeGeneration: 6, navigationGeneration: 1)
        _ = tracker.navigationStarted(original)
        let request = try XCTUnwrap(tracker.requestSoftRecovery(
            for: original,
            classification: .rendererResponsiveNavigationStall
        ))
        let unrelated = WebRuntimeNavigationTicket(runtimeGeneration: 6, navigationGeneration: 2)
        XCTAssertEqual(tracker.navigationStarted(unrelated), .staleSoftRecovery(request.ticket))
        XCTAssertFalse(tracker.isCurrent(request.ticket))
    }

    func testNewUserActionInvalidatesOldRecoveryTimeout() throws {
        var tracker = WebRuntimeRecoveryTracker(runtimeGeneration: 7)
        _ = tracker.recordUserAction(.reload, navigationGenerationBefore: 0)
        let navigation = WebRuntimeNavigationTicket(runtimeGeneration: 7, navigationGeneration: 1)
        _ = tracker.navigationStarted(navigation)
        let request = try XCTUnwrap(tracker.requestSoftRecovery(
            for: navigation,
            classification: .rendererResponsiveNavigationStall
        ))
        _ = tracker.recordUserAction(.home, navigationGenerationBefore: 1)

        XCTAssertFalse(tracker.softRecoveryStartTimedOut(request.ticket))
        XCTAssertFalse(tracker.isCurrent(request.ticket))
    }

    func testCurrentRecoveryStartTimeoutConsumesItsTicketOnce() throws {
        var tracker = WebRuntimeRecoveryTracker(runtimeGeneration: 8)
        _ = tracker.recordUserAction(.reload, navigationGenerationBefore: 0)
        let navigation = WebRuntimeNavigationTicket(runtimeGeneration: 8, navigationGeneration: 1)
        _ = tracker.navigationStarted(navigation)
        let request = try XCTUnwrap(tracker.requestSoftRecovery(
            for: navigation,
            classification: .rendererResponsiveNavigationStall
        ))
        XCTAssertTrue(tracker.beginSoftRecovery(request.ticket))

        XCTAssertTrue(tracker.softRecoveryStartTimedOut(request.ticket))
        XCTAssertFalse(tracker.softRecoveryStartTimedOut(request.ticket))
        XCTAssertFalse(tracker.isCurrent(request.ticket))
    }

    func testNaturalUserNavigationFinishInvalidatesDeferredRecovery() throws {
        var tracker = WebRuntimeRecoveryTracker(runtimeGeneration: 9)
        _ = tracker.recordUserAction(.home, navigationGenerationBefore: 0)
        let navigation = WebRuntimeNavigationTicket(runtimeGeneration: 9, navigationGeneration: 1)
        _ = tracker.navigationStarted(navigation)
        let request = try XCTUnwrap(tracker.requestSoftRecovery(
            for: navigation,
            classification: .rendererResponsiveNavigationStall
        ))
        XCTAssertTrue(tracker.deferSoftRecovery(request.ticket))

        XCTAssertEqual(tracker.userNavigationFinished(navigation), request.ticket)
        XCTAssertFalse(tracker.isCurrent(request.ticket))
        XCTAssertNil(tracker.didFinish(navigation))
    }

    func testRuntimeReplacementInvalidatesPendingRecovery() throws {
        var tracker = WebRuntimeRecoveryTracker(runtimeGeneration: 8)
        _ = tracker.recordUserAction(.reload, navigationGenerationBefore: 0)
        let navigation = WebRuntimeNavigationTicket(runtimeGeneration: 8, navigationGeneration: 1)
        _ = tracker.navigationStarted(navigation)
        let request = try XCTUnwrap(tracker.requestSoftRecovery(
            for: navigation,
            classification: .rendererResponsiveNavigationStall
        ))

        XCTAssertEqual(tracker.replaceRuntime(with: 9), request.ticket)
        XCTAssertFalse(tracker.isCurrent(request.ticket))
        XCTAssertNil(tracker.userActionContext(for: navigation))
    }

    func testReleaseInvalidatesPendingRecoveryAndAction() throws {
        var tracker = WebRuntimeRecoveryTracker(runtimeGeneration: 10)
        _ = tracker.recordUserAction(.home, navigationGenerationBefore: 0)
        let navigation = WebRuntimeNavigationTicket(runtimeGeneration: 10, navigationGeneration: 1)
        _ = tracker.navigationStarted(navigation)
        let request = try XCTUnwrap(tracker.requestSoftRecovery(
            for: navigation,
            classification: .rendererResponsiveNavigationStall
        ))

        XCTAssertEqual(tracker.invalidate(), request.ticket)
        XCTAssertFalse(tracker.isCurrent(request.ticket))
        XCTAssertNil(tracker.userActionContext(for: navigation))
    }

    func testCompletedOrdinaryUserNavigationClearsRecoveryIntent() {
        var tracker = WebRuntimeRecoveryTracker(runtimeGeneration: 11)
        _ = tracker.recordUserAction(.reload, navigationGenerationBefore: 0)
        let navigation = WebRuntimeNavigationTicket(runtimeGeneration: 11, navigationGeneration: 1)
        _ = tracker.navigationStarted(navigation)

        XCTAssertNil(tracker.didFinish(navigation))
        XCTAssertNil(tracker.userActionContext(for: navigation))
    }

    func testSoftRecoveryCompletesExactlyOnceOnCommit() throws {
        var tracker = WebRuntimeRecoveryTracker(runtimeGeneration: 12)
        _ = tracker.recordUserAction(.reload, navigationGenerationBefore: 0)
        let original = WebRuntimeNavigationTicket(runtimeGeneration: 12, navigationGeneration: 1)
        _ = tracker.navigationStarted(original)
        let request = try XCTUnwrap(tracker.requestSoftRecovery(
            for: original,
            classification: .rendererResponsiveNavigationStall
        ))
        XCTAssertTrue(tracker.beginSoftRecovery(request.ticket))
        XCTAssertFalse(tracker.beginSoftRecovery(request.ticket))

        let recoveryNavigation = WebRuntimeNavigationTicket(runtimeGeneration: 12, navigationGeneration: 2)
        XCTAssertEqual(tracker.navigationStarted(recoveryNavigation), .softRecovery(request.ticket))
        XCTAssertEqual(tracker.didCommit(recoveryNavigation), request.ticket)
        XCTAssertNil(tracker.didFinish(recoveryNavigation))
        XCTAssertFalse(tracker.isCurrent(request.ticket))
    }

    func testNavigationFinishAndFailurePreventAStall() {
        for terminal in ["finish", "failure"] {
            var tracker = WebRuntimeHealthTracker(runtimeGeneration: 7)
            let ticket = tracker.provisionalStarted()

            switch terminal {
            case "finish": XCTAssertTrue(tracker.didFinish(ticket))
            default: XCTAssertTrue(tracker.didFail(ticket))
            }

            XCTAssertFalse(tracker.markStalled(ticket), "\(terminal) must terminate stall observation")
        }
    }

    func testCommittedNavigationCanStillBeClassifiedStalledUntilFinish() {
        var tracker = WebRuntimeHealthTracker(runtimeGeneration: 7)
        let ticket = tracker.provisionalStarted()

        XCTAssertTrue(tracker.didCommit(ticket))
        XCTAssertTrue(tracker.isCommitted(ticket))
        XCTAssertTrue(tracker.markStalled(ticket), "commit is progress, not a terminal navigation state")
        XCTAssertFalse(tracker.markStalled(ticket), "one generation must emit at most one stall")
    }

    func testNavigationWatchdogReportsExactlyOneStall() {
        var tracker = WebRuntimeHealthTracker(runtimeGeneration: 3)
        let ticket = tracker.provisionalStarted()

        XCTAssertTrue(tracker.markStalled(ticket))
        XCTAssertFalse(tracker.markStalled(ticket))
    }

    func testNewNavigationMakesTheOldWatchdogStale() {
        var tracker = WebRuntimeHealthTracker(runtimeGeneration: 3)
        let first = tracker.provisionalStarted()
        let second = tracker.provisionalStarted()

        XCTAssertFalse(tracker.markStalled(first))
        XCTAssertTrue(tracker.markStalled(second))
    }

    func testRuntimeReplacementInvalidatesOldNavigationWatchdog() {
        var tracker = WebRuntimeHealthTracker(runtimeGeneration: 11)
        let oldRuntime = tracker.provisionalStarted()

        tracker.replaceRuntime(with: 12)

        XCTAssertFalse(tracker.markStalled(oldRuntime))
        let newRuntime = tracker.provisionalStarted()
        XCTAssertEqual(newRuntime.runtimeGeneration, 12)
        XCTAssertNotEqual(newRuntime.runtimeGeneration, oldRuntime.runtimeGeneration)
    }

    func testRendererProbeSuccessFailureAndTimeoutAreSingleCompletion() {
        var success = RendererProbeLifecycle(runtimeGeneration: 4)
        let successfulProbe = success.begin(for: WebRuntimeNavigationTicket(
            runtimeGeneration: 4,
            navigationGeneration: 8
        ))
        XCTAssertEqual(success.complete(successfulProbe, as: .success), .success)
        XCTAssertNil(success.complete(successfulProbe, as: .failed))
        XCTAssertNil(success.timeout(successfulProbe), "late timeout must not follow success")

        var failure = RendererProbeLifecycle(runtimeGeneration: 4)
        let failedProbe = failure.begin(for: WebRuntimeNavigationTicket(
            runtimeGeneration: 4,
            navigationGeneration: 9
        ))
        XCTAssertEqual(failure.complete(failedProbe, as: .failed), .failed)

        var timeout = RendererProbeLifecycle(runtimeGeneration: 4)
        let timedOutProbe = timeout.begin(for: WebRuntimeNavigationTicket(
            runtimeGeneration: 4,
            navigationGeneration: 10
        ))
        XCTAssertEqual(timeout.timeout(timedOutProbe), .timeout)
        XCTAssertNil(timeout.complete(timedOutProbe, as: .success), "late JS callback must be ignored")
    }

    func testRendererProbeCallbackFromReplacedRuntimeIsIgnored() {
        var lifecycle = RendererProbeLifecycle(runtimeGeneration: 20)
        let ticket = lifecycle.begin(for: WebRuntimeNavigationTicket(
            runtimeGeneration: 20,
            navigationGeneration: 1
        ))

        lifecycle.replaceRuntime(with: 21)

        XCTAssertNil(lifecycle.complete(ticket, as: .success))
    }

    func testRendererProbeSnapshotCopiesOnlySafeStateIntoSendableValue() {
        let snapshot = RendererProbeSnapshot(
            value: [
                "ready_state": "complete",
                "visibility_state": "visible",
                "page_text": "must not cross the callback boundary"
            ],
            error: nil
        )

        XCTAssertEqual(snapshot.result, .success)
        XCTAssertEqual(snapshot.readyState, "complete")
        XCTAssertEqual(snapshot.visibilityState, "visible")
        XCTAssertNil(snapshot.errorCategory)

        let invalid = RendererProbeSnapshot(
            value: ["ready_state": "unexpected", "visibility_state": "visible"],
            error: nil
        )
        XCTAssertEqual(invalid.result, .failed)
        XCTAssertNil(invalid.readyState)
        XCTAssertNil(invalid.visibilityState)
    }

    @MainActor
    func testIncidentSnapshotKeepsWebViewWindowAndSourceHostWindowSeparate() {
        let slotID = UUID()
        let webView = WebViewFactory.makeWebView()
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        let observer = SlotNavigationObserver(
            slotID: slotID,
            webView: webView,
            websiteMode: .desktop,
            onURLChange: { _, _ in },
            diagnostics: diagnostics,
            runtimeGeneration: 31,
            incidentDiagnosticContextProvider: { _ in
                [
                    "source_window_visible": .bool(true),
                    "source_window_key": .bool(true)
                ]
            }
        )

        observer.webViewWebContentProcessDidTerminate(webView)

        let snapshot = writer.events.last { $0.event == "web_runtime.incident_snapshot" }
        XCTAssertEqual(snapshot?.fields["webview_window_visible"], .bool(false))
        XCTAssertEqual(snapshot?.fields["webview_window_key"], .bool(false))
        XCTAssertEqual(snapshot?.fields["source_window_visible"], .bool(true))
        XCTAssertEqual(snapshot?.fields["source_window_key"], .bool(true))
        observer.invalidate()
    }

    @MainActor
    func testNewNavigationInvalidatesPendingRendererProbe() async {
        for lateResult in [WebRuntimeRendererProbeResult.success, .failed] {
            let slotID = UUID()
            let webView = WebViewFactory.makeWebView()
            let writer = RuntimeDiagnosticInMemoryWriter()
            let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
            let evaluatorCapture = RendererProbeJavaScriptEvaluatorCapture()
            let observer = SlotNavigationObserver(
                slotID: slotID,
                webView: webView,
                websiteMode: .desktop,
                onURLChange: { _, _ in },
                diagnostics: diagnostics,
                runtimeGeneration: 4,
                javaScriptEvaluator: { [weak evaluatorCapture] _, _, completion in
                    evaluatorCapture?.completion = completion
                }
            )

            observer.webView(webView, didStartProvisionalNavigation: nil)
            observer.startRendererProbe(
                in: webView,
                for: WebRuntimeNavigationTicket(runtimeGeneration: 4, navigationGeneration: 1)
            )
            observer.webView(webView, didStartProvisionalNavigation: nil)

            guard let javaScriptCompletion = evaluatorCapture.completion else {
                XCTFail("expected the test evaluator to retain the probe callback")
                observer.invalidate()
                continue
            }
            let error: Error? = lateResult == .failed
                ? NSError(domain: "probe-test", code: 1)
                : nil
            let value: Any? = lateResult == .success
                ? ["ready_state": "complete", "visibility_state": "visible"]
                : nil
            javaScriptCompletion(value, error)
            try? await Task.sleep(nanoseconds: 100_000_000)

            XCTAssertFalse(
                writer.events.contains {
                    ["renderer_probe.success", "renderer_probe.failed", "renderer_probe.timeout"]
                        .contains($0.event)
                },
                "a late \(lateResult) callback from navigation A must be ignored after B starts"
            )
            observer.invalidate()
        }
    }

    @MainActor
    func testNewNavigationCancelsAndInvalidatesPendingRendererProbeTimeout() async {
        let slotID = UUID()
        let webView = WebViewFactory.makeWebView()
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        let observer = SlotNavigationObserver(
            slotID: slotID,
            webView: webView,
            websiteMode: .desktop,
            onURLChange: { _, _ in },
            diagnostics: diagnostics,
            runtimeGeneration: 4,
            javaScriptEvaluator: { _, _, _ in }
        )

        observer.webView(webView, didStartProvisionalNavigation: nil)
        observer.startRendererProbe(
            in: webView,
            for: WebRuntimeNavigationTicket(runtimeGeneration: 4, navigationGeneration: 1)
        )
        observer.webView(webView, didStartProvisionalNavigation: nil)
        let waitNanoseconds = UInt64(
            (SlotNavigationObserver.rendererProbeTimeout + 0.25) * 1_000_000_000
        )
        try? await Task.sleep(nanoseconds: waitNanoseconds)

        XCTAssertFalse(
            writer.events.contains { $0.event == "renderer_probe.timeout" },
            "navigation A's pending timeout must be ignored after navigation B starts"
        )
        observer.invalidate()
    }

    @MainActor
    func testReloadNavigationWithResponsiveRendererRequestsOneSoftRecovery() async throws {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let evaluatorCapture = RendererProbeJavaScriptEvaluatorCapture()
        let webView = WebViewFactory.makeWebView()
        let observer = SlotNavigationObserver(
            slotID: UUID(),
            webView: webView,
            websiteMode: .desktop,
            onURLChange: { _, _ in },
            diagnostics: RuntimeDiagnostics(mode: .standard, writer: writer),
            runtimeGeneration: 7,
            javaScriptEvaluator: { [weak evaluatorCapture] _, _, completion in
                evaluatorCapture?.completion = completion
            }
        )
        observer.observeUserAction(.reload)
        observer.webView(webView, didStartProvisionalNavigation: nil)
        observer.startRendererProbe(
            in: webView,
            for: WebRuntimeNavigationTicket(runtimeGeneration: 7, navigationGeneration: 1)
        )
        let completion = try XCTUnwrap(evaluatorCapture.completion)
        completion(
            ["ready_state": "interactive", "visibility_state": "visible"],
            nil
        )
        for _ in 0..<5 { await Task.yield() }

        let requests = writer.events.filter { $0.event == "web_runtime.recovery.soft_requested" }
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.fields["runtime_generation"], .integer(7))
        XCTAssertEqual(requests.first?.fields["navigation_generation"], .integer(1))
        XCTAssertEqual(requests.first?.fields["user_action_generation"], .integer(1))
        XCTAssertEqual(requests.first?.fields["recovery_generation"], .integer(1))
        XCTAssertEqual(requests.first?.fields["action"], .string("reload"))
        observer.invalidate()
    }

    @MainActor
    func testHomeNavigationWithResponsiveRendererKeepsHomeActionIntent() async throws {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let evaluatorCapture = RendererProbeJavaScriptEvaluatorCapture()
        let webView = WebViewFactory.makeWebView()
        let observer = SlotNavigationObserver(
            slotID: UUID(),
            webView: webView,
            websiteMode: .desktop,
            onURLChange: { _, _ in },
            diagnostics: RuntimeDiagnostics(mode: .standard, writer: writer),
            runtimeGeneration: 8,
            javaScriptEvaluator: { [weak evaluatorCapture] _, _, completion in
                evaluatorCapture?.completion = completion
            }
        )

        observer.observeUserAction(.home)
        observer.webView(webView, didStartProvisionalNavigation: nil)
        observer.startRendererProbe(
            in: webView,
            for: WebRuntimeNavigationTicket(runtimeGeneration: 8, navigationGeneration: 1)
        )
        let completion = try XCTUnwrap(evaluatorCapture.completion)
        completion(
            ["ready_state": "complete", "visibility_state": "visible"],
            nil
        )
        for _ in 0..<5 { await Task.yield() }

        let request = writer.events.first { $0.event == "web_runtime.recovery.soft_requested" }
        XCTAssertEqual(request?.fields["action"], .string("home"))
        XCTAssertEqual(request?.fields["reason"], .string("user_action_stalled_renderer_responsive"))
        observer.invalidate()
    }

    @MainActor
    func testPassiveResponsiveRendererProbeRecordsWithoutRecovery() async throws {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let evaluatorCapture = RendererProbeJavaScriptEvaluatorCapture()
        let webView = WebViewFactory.makeWebView()
        let observer = SlotNavigationObserver(
            slotID: UUID(),
            webView: webView,
            websiteMode: .desktop,
            onURLChange: { _, _ in },
            diagnostics: RuntimeDiagnostics(mode: .standard, writer: writer),
            runtimeGeneration: 13,
            javaScriptEvaluator: { [weak evaluatorCapture] _, _, completion in
                evaluatorCapture?.completion = completion
            }
        )
        observer.webView(webView, didStartProvisionalNavigation: nil)
        observer.startRendererProbe(
            in: webView,
            for: WebRuntimeNavigationTicket(runtimeGeneration: 13, navigationGeneration: 1)
        )
        let completion = try XCTUnwrap(evaluatorCapture.completion)
        completion(["ready_state": "interactive", "visibility_state": "visible"], nil)
        for _ in 0..<5 { await Task.yield() }

        XCTAssertTrue(writer.events.contains { $0.event == "renderer_probe.success" })
        XCTAssertFalse(writer.events.contains { $0.event.hasPrefix("web_runtime.recovery.") })
        observer.invalidate()
    }

    @MainActor
    func testFailedRendererProbeRecordsNoHardRecovery() async throws {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let evaluatorCapture = RendererProbeJavaScriptEvaluatorCapture()
        let webView = WebViewFactory.makeWebView()
        let observer = SlotNavigationObserver(
            slotID: UUID(),
            webView: webView,
            websiteMode: .desktop,
            onURLChange: { _, _ in },
            diagnostics: RuntimeDiagnostics(mode: .standard, writer: writer),
            runtimeGeneration: 14,
            javaScriptEvaluator: { [weak evaluatorCapture] _, _, completion in
                evaluatorCapture?.completion = completion
            }
        )
        observer.observeUserAction(.reload)
        observer.webView(webView, didStartProvisionalNavigation: nil)
        observer.startRendererProbe(
            in: webView,
            for: WebRuntimeNavigationTicket(runtimeGeneration: 14, navigationGeneration: 1)
        )
        let completion = try XCTUnwrap(evaluatorCapture.completion)
        completion(nil, NSError(domain: "renderer-probe-test", code: 1))
        for _ in 0..<5 { await Task.yield() }

        XCTAssertTrue(writer.events.contains { $0.event == "renderer_probe.failed" })
        XCTAssertTrue(writer.events.contains {
            $0.event == "web_runtime.recovery.soft_failed"
                && $0.fields["reason"] == .string("renderer_probe_failed")
        })
        XCTAssertFalse(writer.events.contains { $0.event == "web_runtime.recovery.hard_deferred" })
        observer.invalidate()
    }

    @MainActor
    func testRendererProbeTimeoutRecordsHardRecoveryDeferredWithoutEscalation() async throws {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let webView = WebViewFactory.makeWebView()
        let observer = SlotNavigationObserver(
            slotID: UUID(),
            webView: webView,
            websiteMode: .desktop,
            onURLChange: { _, _ in },
            diagnostics: RuntimeDiagnostics(mode: .standard, writer: writer),
            runtimeGeneration: 15,
            isSlotActive: { _ in true },
            javaScriptEvaluator: { _, _, _ in }
        )
        observer.observeUserAction(.reload)
        observer.webView(webView, didStartProvisionalNavigation: nil)
        observer.startRendererProbe(
            in: webView,
            for: WebRuntimeNavigationTicket(runtimeGeneration: 15, navigationGeneration: 1)
        )
        let waitNanoseconds = UInt64(
            (SlotNavigationObserver.rendererProbeTimeout + 0.25) * 1_000_000_000
        )
        try? await Task.sleep(nanoseconds: waitNanoseconds)

        XCTAssertTrue(writer.events.contains { $0.event == "renderer_probe.timeout" })
        XCTAssertTrue(writer.events.contains {
            $0.event == "web_runtime.recovery.hard_deferred"
                && $0.fields["reason"] == .string(
                    "renderer_probe_timeout_existing_rebuild_owner_required"
                )
                && $0.fields["recovery_generation"] == .null
        })
        XCTAssertFalse(writer.events.contains { $0.event == "web_runtime.recovery.soft_requested" })
        observer.invalidate()
    }
}
