import Foundation
import XCTest
@testable import FloatTabs

@MainActor
final class RuntimeDiagnosticsTests: XCTestCase {
    func testEnvironmentFieldsCarryBuiltSourceAndBoundedChannelLabels() throws {
        let diagnostics = RuntimeDiagnostics(
            mode: .verbose,
            writer: RuntimeDiagnosticInMemoryWriter()
        )
        let fields = diagnostics.environmentFields()

        guard case let .string(sourceRevision)? = fields["source_revision"] else {
            return XCTFail("expected source_revision metadata")
        }
        XCTAssertTrue(
            sourceRevision == "unknown"
                || sourceRevision.range(of: #"^[0-9a-f]{40}$"#, options: .regularExpression) != nil
        )
        guard case let .string(treeState)? = fields["source_tree_state"],
              RuntimeDiagnosticSourceProvenance.TreeState(rawValue: treeState) != nil else {
            return XCTFail("expected a bounded source_tree_state")
        }
        guard case let .bool(revisionExact)? = fields["source_revision_exact"] else {
            return XCTFail("expected boolean source_revision_exact metadata")
        }
        XCTAssertEqual(revisionExact, treeState == "clean")
        let sanitizedEnvironment = RuntimeDiagnosticPrivacy.sanitize(fields: fields, mode: .verbose)
        XCTAssertEqual(sanitizedEnvironment["source_tree_state"], .string(treeState))
        XCTAssertEqual(sanitizedEnvironment["source_revision_exact"], .bool(revisionExact))
        XCTAssertEqual(fields["build_channel"], .string("Debug"))
        XCTAssertEqual(fields["qa_label"], .string("ft-diag-002-qa"))
        XCTAssertEqual(
            RuntimeDiagnosticPrivacy.sanitize(fields: fields, mode: .verbose)["qa_label"],
            .string("ft-diag-002-qa")
        )
    }

    func testCleanSourceProvenanceIsExact() {
        let provenance = RuntimeDiagnosticSourceProvenance.fromBuildMetadata(
            sourceRevision: String(repeating: "a", count: 40),
            sourceTreeState: "clean",
            sourceRevisionExact: "true"
        )
        XCTAssertEqual(provenance.sourceTreeState, .clean)
        XCTAssertTrue(provenance.sourceRevisionExact)
    }

    func testDirtySourceProvenanceIsNotExact() {
        let provenance = RuntimeDiagnosticSourceProvenance.fromBuildMetadata(
            sourceRevision: String(repeating: "b", count: 40),
            sourceTreeState: "dirty",
            sourceRevisionExact: "true"
        )
        XCTAssertEqual(provenance.sourceTreeState, .dirty)
        XCTAssertFalse(provenance.sourceRevisionExact)
    }

    func testUnknownSourceProvenanceIsNotExact() {
        let provenance = RuntimeDiagnosticSourceProvenance.fromBuildMetadata(
            sourceRevision: String(repeating: "c", count: 40),
            sourceTreeState: "unknown",
            sourceRevisionExact: "true"
        )
        XCTAssertEqual(provenance.sourceTreeState, .unknown)
        XCTAssertFalse(provenance.sourceRevisionExact)
    }

    func testInvalidSourceRevisionForcesUnknownAndNotExact() {
        let provenance = RuntimeDiagnosticSourceProvenance.fromBuildMetadata(
            sourceRevision: "not-a-revision",
            sourceTreeState: "clean",
            sourceRevisionExact: "true"
        )
        XCTAssertEqual(provenance.sourceRevision, "unknown")
        XCTAssertEqual(provenance.sourceTreeState, .unknown)
        XCTAssertFalse(provenance.sourceRevisionExact)
    }

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

    func testPeriodicSamplesDropRepeatedProvenanceAndKeepIdentitySafeCounterDeltas() {
        let writer = RuntimeDiagnosticInMemoryWriter()
        var currentUptime = 100.0
        let diagnostics = RuntimeDiagnostics(
            mode: .standard,
            writer: writer,
            uptime: { currentUptime }
        )

        func checkpoint(
            slotID: String = "slot-a",
            runtimeGeneration: Int64 = 1,
            webViewInstanceID: String = "webview-a",
            documentEpoch: Int64 = 7,
            javascriptErrors: Int64,
            droppedEvents: Int64
        ) {
            var fields = diagnostics.environmentFields()
            fields.merge([
                "slot_id": .string(slotID),
                "runtime_generation": .integer(runtimeGeneration),
                "webview_instance_id": .string(webViewInstanceID),
                "chatgpt_document_epoch": .integer(documentEpoch),
                "page_app_javascript_error_count": .integer(javascriptErrors),
                "page_app_unhandled_rejection_count": .integer(2),
                "page_app_resource_load_failure_count": .integer(3),
                "page_app_resource_http_error_count": .integer(4),
                "page_app_slow_resource_count": .integer(5),
                "page_app_dropped_event_count": .integer(droppedEvents),
                "page_app_lifecycle_event_count": .integer(6)
            ]) { _, new in new }
            diagnostics.record(
                event: "diagnostics.performance_checkpoint",
                level: .notice,
                subsystem: "diagnostics",
                fields: fields
            )
        }

        checkpoint(javascriptErrors: 10, droppedEvents: 20)
        let first = writer.events[0]
        XCTAssertNil(first.fields["app_version"])
        XCTAssertNil(first.fields["source_revision"])
        XCTAssertEqual(first.fields["runtime_generation"], .integer(1))
        XCTAssertEqual(first.fields["page_app_delta_baseline"], .string("established"))
        XCTAssertEqual(first.fields["page_app_javascript_error_delta"], .null)

        currentUptime = 110
        checkpoint(javascriptErrors: 16, droppedEvents: 25)
        let second = writer.events[1]
        XCTAssertEqual(second.fields["page_app_delta_baseline"], .string("continuing"))
        XCTAssertEqual(second.fields["page_app_javascript_error_delta"], .integer(6))
        XCTAssertEqual(second.fields["page_app_dropped_event_delta"], .integer(5))
        XCTAssertEqual(second.fields["page_app_javascript_error_rate_per_minute"], .double(36))
        XCTAssertEqual(second.fields["page_app_delta_interval_s"], .double(10))

        currentUptime = 115
        checkpoint(
            slotID: "slot-b",
            runtimeGeneration: 3,
            webViewInstanceID: "webview-b",
            documentEpoch: 8,
            javascriptErrors: 100,
            droppedEvents: 200
        )
        let firstB = writer.events[2]
        XCTAssertEqual(firstB.fields["page_app_delta_baseline"], .string("established"))

        currentUptime = 120
        checkpoint(slotID: "slot-a", javascriptErrors: 22, droppedEvents: 30)
        let resumedA = writer.events[3]
        XCTAssertEqual(resumedA.fields["page_app_delta_baseline"], .string("continuing"))
        XCTAssertEqual(resumedA.fields["page_app_javascript_error_delta"], .integer(6))
        XCTAssertEqual(resumedA.fields["page_app_dropped_event_delta"], .integer(5))

        currentUptime = 120
        checkpoint(runtimeGeneration: 2, javascriptErrors: 1, droppedEvents: 1)
        let replacement = writer.events[4]
        XCTAssertEqual(
            replacement.fields["page_app_delta_baseline"],
            .string("reset_identity_change")
        )
        XCTAssertEqual(replacement.fields["page_app_javascript_error_delta"], .null)

        currentUptime = 130
        checkpoint(runtimeGeneration: 2, javascriptErrors: 4, droppedEvents: 3)
        let resumed = writer.events[5]
        XCTAssertEqual(resumed.fields["page_app_javascript_error_delta"], .integer(3))
        XCTAssertEqual(resumed.fields["page_app_dropped_event_delta"], .integer(2))

        currentUptime = 140
        checkpoint(
            slotID: "slot-b",
            runtimeGeneration: 3,
            webViewInstanceID: "webview-b",
            documentEpoch: 8,
            javascriptErrors: 106,
            droppedEvents: 205
        )
        let resumedB = writer.events[6]
        XCTAssertEqual(resumedB.fields["page_app_delta_baseline"], .string("continuing"))
        XCTAssertEqual(resumedB.fields["page_app_javascript_error_delta"], .integer(6))
        XCTAssertEqual(resumedB.fields["page_app_dropped_event_delta"], .integer(5))
    }

    func testPerSlotDeltaBaselinesResetOnlyTheAffectedIdentityOrCounter() {
        let writer = RuntimeDiagnosticInMemoryWriter()
        var currentUptime = 1.0
        let diagnostics = RuntimeDiagnostics(
            mode: .standard,
            writer: writer,
            uptime: { currentUptime }
        )

        func checkpoint(
            webViewInstanceID: String = "webview-a",
            documentEpoch: Int64 = 7,
            javascriptErrors: Int64
        ) {
            diagnostics.record(
                event: "diagnostics.performance_checkpoint",
                level: .notice,
                subsystem: "diagnostics",
                fields: [
                    "slot_id": .string("slot-a"),
                    "runtime_generation": .integer(1),
                    "webview_instance_id": .string(webViewInstanceID),
                    "chatgpt_document_epoch": .integer(documentEpoch),
                    "page_app_javascript_error_count": .integer(javascriptErrors),
                    "page_app_unhandled_rejection_count": .integer(0),
                    "page_app_resource_load_failure_count": .integer(0),
                    "page_app_resource_http_error_count": .integer(0),
                    "page_app_slow_resource_count": .integer(0),
                    "page_app_dropped_event_count": .integer(0),
                    "page_app_lifecycle_event_count": .integer(0)
                ]
            )
        }

        checkpoint(javascriptErrors: 10)
        currentUptime = 2
        checkpoint(webViewInstanceID: "webview-b", javascriptErrors: 11)
        XCTAssertEqual(
            writer.events[1].fields["page_app_delta_baseline"],
            .string("reset_identity_change")
        )

        currentUptime = 3
        checkpoint(webViewInstanceID: "webview-b", javascriptErrors: 13)
        XCTAssertEqual(writer.events[2].fields["page_app_javascript_error_delta"], .integer(2))

        currentUptime = 4
        checkpoint(documentEpoch: 8, javascriptErrors: 14)
        XCTAssertEqual(
            writer.events[3].fields["page_app_delta_baseline"],
            .string("reset_identity_change")
        )

        currentUptime = 5
        checkpoint(documentEpoch: 8, javascriptErrors: 12)
        XCTAssertEqual(
            writer.events[4].fields["page_app_delta_baseline"],
            .string("reset_counter_regression")
        )

        currentUptime = 6
        checkpoint(documentEpoch: 8, javascriptErrors: 15)
        XCTAssertEqual(writer.events[5].fields["page_app_javascript_error_delta"], .integer(3))
    }

    func testPeriodicLogVolumeFixtureReportsEquivalentBeforeAndAfterBytes() throws {
        let writer = RuntimeDiagnosticInMemoryWriter()
        var currentUptime = 1.0
        let diagnostics = RuntimeDiagnostics(
            mode: .standard,
            writer: writer,
            uptime: { currentUptime }
        )
        let dynamicFields: [String: RuntimeDiagnosticValue] = [
            "observation_source": .string("long_term_performance"),
            "slot_id": .string("slot-a"),
            "runtime_generation": .integer(1),
            "webview_instance_id": .string("webview-a"),
            "chatgpt_document_epoch": .integer(7),
            "capture_availability": .string("captured"),
            "resident": .bool(true),
            "page_app_javascript_error_count": .integer(20),
            "page_app_unhandled_rejection_count": .integer(2),
            "page_app_resource_load_failure_count": .integer(3),
            "page_app_resource_http_error_count": .integer(4),
            "page_app_slow_resource_count": .integer(5),
            "page_app_dropped_event_count": .integer(6),
            "page_app_lifecycle_event_count": .integer(7)
        ]
        let staticFields = diagnostics.environmentFields()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        var beforeBytes = 0
        for sequence in 1...20 {
            let event = RuntimeDiagnosticEvent(
                timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(sequence)),
                uptime: Double(sequence),
                sequence: UInt64(sequence),
                sessionID: sessionID,
                traceID: nil,
                level: .notice,
                subsystem: "diagnostics",
                event: "web_runtime.cross_world_liveness",
                fields: staticFields.merging(dynamicFields) { _, new in new }
            )
            beforeBytes += try encoder.encode(event).count + 1
        }

        for sequence in 1...20 {
            currentUptime = Double(sequence)
            diagnostics.record(
                event: "web_runtime.cross_world_liveness",
                level: .notice,
                subsystem: "diagnostics",
                fields: dynamicFields
            )
        }
        let afterBytes = writer.lines.reduce(0) { $0 + $1.count }
        let reduction = Double(beforeBytes - afterBytes) / Double(beforeBytes) * 100
        print(
            "LOG_VOLUME_FIXTURE before_bytes=\(beforeBytes) after_bytes=\(afterBytes) "
                + "reduction_percent=\(reduction) before_events=20 after_events=20"
        )
        XCTAssertEqual(writer.events.count, 20)
        XCTAssertLessThan(afterBytes, beforeBytes)
    }

    func testLongTermObservationWaitsSixtySecondsAndDoesNotOverlapSamples() async {
        let suiteName = "FloatTabsTests.LongTermObservation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.longTermPerformanceObservationEnabled = true
        let sleeper = ManualLongTermObservationSleeper()
        var sampleCount = 0
        var currentChecks: [@MainActor () -> Bool] = []
        var completions: [@MainActor () -> Void] = []
        let coordinator = LongTermPerformanceObservationCoordinator(
            preferencesStore: preferences,
            interval: 60,
            sleeper: { try await sleeper.sleep($0) },
            observe: { isCurrent, completion in
                sampleCount += 1
                currentChecks.append(isCurrent)
                completions.append(completion)
            }
        )
        defer { coordinator.stop() }

        coordinator.start()
        await waitUntil { sleeper.pendingCount == 1 }
        XCTAssertEqual(sleeper.requestedIntervals, [60])
        XCTAssertEqual(sampleCount, 0)

        sleeper.advanceNext()
        await waitUntil { sampleCount == 1 }
        XCTAssertTrue(coordinator.isObservationInFlight)
        XCTAssertTrue(currentChecks[0]())
        XCTAssertEqual(sleeper.requestedIntervals, [60])

        completions[0]()
        await waitUntil { sleeper.requestedIntervals.count == 2 }
        XCTAssertEqual(sleeper.requestedIntervals, [60, 60])
        XCTAssertEqual(sampleCount, 1)
        coordinator.stop()
    }

    func testLongTermObservationRequiresEnabledDiagnosticsAndStopsOnPreferenceChange() async {
        let suiteName = "FloatTabsTests.LongTermObservation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.runtimeDiagnosticsMode = .off
        preferences.longTermPerformanceObservationEnabled = true
        let sleeper = ManualLongTermObservationSleeper()
        var sampleCount = 0
        let coordinator = LongTermPerformanceObservationCoordinator(
            preferencesStore: preferences,
            sleeper: { try await sleeper.sleep($0) },
            observe: { _, completion in
                sampleCount += 1
                completion()
            }
        )
        defer { coordinator.stop() }

        coordinator.start()
        for _ in 0..<5 { await Task.yield() }
        XCTAssertTrue(sleeper.requestedIntervals.isEmpty)
        XCTAssertEqual(sampleCount, 0)

        preferences.runtimeDiagnosticsMode = .standard
        await waitUntil { sleeper.pendingCount == 1 }
        preferences.longTermPerformanceObservationEnabled = false
        await waitUntil { sleeper.pendingCount == 0 }

        XCTAssertEqual(sampleCount, 0)
        XCTAssertFalse(coordinator.isRunning)
    }

    func testStoppingInvalidatesInFlightCheckpointAndRejectsLateCompletion() async {
        let suiteName = "FloatTabsTests.LongTermObservation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.longTermPerformanceObservationEnabled = true
        let sleeper = ManualLongTermObservationSleeper()
        var shouldContinue: (@MainActor () -> Bool)?
        var lateCompletion: (@MainActor () -> Void)?
        let coordinator = LongTermPerformanceObservationCoordinator(
            preferencesStore: preferences,
            sleeper: { try await sleeper.sleep($0) },
            observe: { isCurrent, completion in
                shouldContinue = isCurrent
                lateCompletion = completion
            }
        )

        coordinator.start()
        await waitUntil { sleeper.pendingCount == 1 }
        sleeper.advanceNext()
        await waitUntil { shouldContinue != nil }
        XCTAssertTrue(shouldContinue?() == true)

        coordinator.stop()

        XCTAssertFalse(shouldContinue?() ?? true)
        XCTAssertFalse(coordinator.isObservationInFlight)
        lateCompletion?()
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(sleeper.requestedIntervals, [60])
    }

    private func waitUntil(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @MainActor () -> Bool
    ) async {
        for _ in 0..<100 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("condition not met", file: file, line: line)
    }
}

@MainActor
private final class ManualLongTermObservationSleeper {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private var waiters: [Waiter] = []
    private(set) var requestedIntervals: [TimeInterval] = []

    var pendingCount: Int { waiters.count }

    func sleep(_ interval: TimeInterval) async throws {
        let id = UUID()
        requestedIntervals.append(interval)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.resume(id: id, throwing: CancellationError())
            }
        }
    }

    func advanceNext() {
        guard let waiter = waiters.first else { return }
        waiters.removeFirst()
        waiter.continuation.resume()
    }

    private func resume(id: UUID, throwing error: Error) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: error)
    }
}
