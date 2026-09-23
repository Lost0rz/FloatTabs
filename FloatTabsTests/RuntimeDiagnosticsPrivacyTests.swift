import Foundation
import XCTest
@testable import FloatTabs

final class RuntimeDiagnosticsPrivacyTests: XCTestCase {
    func testURLsRemoveUserInfoQueryAndFragmentAndRedactConversationLikePath() {
        let url = URL(string: "https://user:password@example.com/c/secret-conversation?token=abc#message")!
        XCTAssertEqual(
            RuntimeDiagnosticPrivacy.safeURLString(url, mode: .standard),
            "https://example.com"
        )
        XCTAssertEqual(
            RuntimeDiagnosticPrivacy.safeURLString(url, mode: .verbose),
            "https://example.com/c/<redacted>"
        )
    }

    func testIPAddressLiteralURLHostsAreDroppedInEveryDiagnosticMode() {
        let ipv4 = URL(string: "http://192.168.1.20:8080/private?token=x#fragment")!
        XCTAssertNil(RuntimeDiagnosticPrivacy.safeURLString(ipv4, mode: .standard))
        XCTAssertNil(RuntimeDiagnosticPrivacy.safeURLString(ipv4, mode: .verbose))

        let loopback = URL(string: "http://127.0.0.1:3000/")!
        XCTAssertNil(RuntimeDiagnosticPrivacy.safeURLString(loopback, mode: .standard))

        let publicIPv4 = URL(string: "https://8.8.8.8/")!
        XCTAssertNil(RuntimeDiagnosticPrivacy.safeURLString(publicIPv4, mode: .standard))

        let ipv6 = URL(string: "http://[::1]/")!
        XCTAssertNil(RuntimeDiagnosticPrivacy.safeURLString(ipv6, mode: .standard))

        let nonLoopbackIPv6 = URL(string: "https://[2001:db8::1]/")!
        XCTAssertNil(RuntimeDiagnosticPrivacy.safeURLString(nonLoopbackIPv6, mode: .standard))

        let mappedIPv6 = URL(string: "https://[::ffff:192.0.2.1]/")!
        XCTAssertNil(RuntimeDiagnosticPrivacy.safeURLString(mappedIPv6, mode: .standard))
    }

    func testNormalDNSURLHostsRemainAllowed() {
        let url = URL(string: "https://example.com/private?x=1#fragment")!
        XCTAssertEqual(
            RuntimeDiagnosticPrivacy.safeURLString(url, mode: .standard),
            "https://example.com"
        )
        XCTAssertEqual(
            RuntimeDiagnosticPrivacy.safeURLString(url, mode: .verbose),
            "https://example.com/private"
        )

        let numericDNSLabel = URL(string: "https://123.example.com/")!
        XCTAssertEqual(
            RuntimeDiagnosticPrivacy.safeURLString(numericDNSLabel, mode: .standard),
            "https://123.example.com"
        )
    }

    func testBareIPAddressStringsAreDroppedByValueLevelSanitization() {
        let fields = RuntimeDiagnosticPrivacy.sanitize(fields: [
            "host": .string("192.168.1.20"),
            "peer": .string("2001:db8::1"),
            "mapped_peer": .string("::ffff:192.0.2.1"),
            "scoped_peer": .string("fe80::1%en0"),
            "safe_state": .string("ready"),
            "safe_host": .string("example.com")
        ], mode: .verbose)

        XCTAssertNil(fields["host"])
        XCTAssertNil(fields["peer"])
        XCTAssertNil(fields["mapped_peer"])
        XCTAssertNil(fields["scoped_peer"])
        XCTAssertEqual(fields["safe_state"], .string("ready"))
        XCTAssertEqual(fields["safe_host"], .string("example.com"))
    }

    func testWindowObservationFieldsArePrivacySafeAndDropTitles() {
        let fields = RuntimeDiagnosticPrivacy.sanitize(fields: [
            "application_bundle_id": .string("md.obsidian"),
            "process_identifier": .integer(42),
            "window_number": .integer(1001),
            "window_display_id": .integer(2),
            "window_observation_quality": .string("frontmost_candidate"),
            "bounds_x": .double(10),
            "bounds_y": .double(20),
            "bounds_width": .double(800),
            "bounds_height": .double(600),
            "window_title": .string("Private note title"),
            "document_title": .string("Private document title"),
            "safe_state": .string("ready")
        ], mode: .standard)

        XCTAssertEqual(fields["application_bundle_id"], .string("md.obsidian"))
        XCTAssertEqual(fields["process_identifier"], .integer(42))
        XCTAssertEqual(fields["window_number"], .integer(1001))
        XCTAssertEqual(fields["window_display_id"], .integer(2))
        XCTAssertEqual(fields["window_observation_quality"], .string("frontmost_candidate"))
        XCTAssertNil(fields["window_title"])
        XCTAssertNil(fields["document_title"])
        XCTAssertEqual(fields["safe_state"], .string("ready"))
    }

    func testWindowMatchReportsTrueFalseAndUnknownWithoutFalseCertainty() {
        XCTAssertEqual(
            RuntimeDiagnosticExternalWindowObservation.windowMatch(
                applicationMatches: false,
                capturedWindowNumber: 10,
                observedWindowNumber: 10
            ),
            .unknown
        )
        XCTAssertEqual(
            RuntimeDiagnosticExternalWindowObservation.windowMatch(
                applicationMatches: false,
                capturedWindowNumber: 10,
                observedWindowNumber: 11
            ),
            .unknown
        )
        XCTAssertEqual(
            RuntimeDiagnosticExternalWindowObservation.windowMatch(
                applicationMatches: true,
                capturedWindowNumber: 10,
                observedWindowNumber: 10
            ),
            .matched
        )
        XCTAssertEqual(
            RuntimeDiagnosticExternalWindowObservation.windowMatch(
                applicationMatches: true,
                capturedWindowNumber: 10,
                observedWindowNumber: 11
            ),
            .mismatched
        )
        XCTAssertEqual(
            RuntimeDiagnosticExternalWindowObservation.windowMatch(
                applicationMatches: true,
                capturedWindowNumber: nil,
                observedWindowNumber: 11
            ),
            .unknown
        )
        XCTAssertEqual(
            RuntimeDiagnosticExternalWindowObservation.windowMatch(
                applicationMatches: true,
                capturedWindowNumber: 10,
                observedWindowNumber: nil
            ),
            .unknown
        )
    }

    @MainActor
    func testNoWindowTitleOrRawWindowDictionaryCanBePersisted() throws {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        diagnostics.record(
            event: "previous_app.restore.observed",
            level: .notice,
            subsystem: "panel",
            fields: [
                "window_number": .integer(101),
                "window_observation_quality": .string("frontmost_candidate"),
                "window_title": .string("Private title"),
                "raw_window_dictionary": .string("Private note content")
            ]
        )

        let line = try XCTUnwrap(writer.lines.first)
        let contents = try XCTUnwrap(String(data: line, encoding: .utf8))
        XCTAssertTrue(contents.contains("window_number"))
        XCTAssertTrue(contents.contains("frontmost_candidate"))
        XCTAssertFalse(contents.contains("Private title"))
        XCTAssertFalse(contents.contains("Private note content"))
    }

    func testSensitiveFieldsAreDroppedBeforePersistence() {
        let fields = RuntimeDiagnosticPrivacy.sanitize(fields: [
            "token": .string("secret"),
            "plan_token": .string("legacy-plan-token"),
            "access_token": .string("access-secret"),
            "auth_token": .string("auth-secret"),
            "Authorization": .string("Bearer secret"),
            "inputValue": .string("private text"),
            "safeState": .string("ready")
        ], mode: .verbose)

        XCTAssertNil(fields["token"])
        XCTAssertNil(fields["plan_token"])
        XCTAssertNil(fields["access_token"])
        XCTAssertNil(fields["auth_token"])
        XCTAssertNil(fields["Authorization"])
        XCTAssertNil(fields["inputValue"])
        XCTAssertEqual(fields["safeState"], .string("ready"))
    }

    func testUnreadDiagnosticFieldsRemainAllowedWhileSensitiveLookalikesAreDropped() {
        let fields = RuntimeDiagnosticPrivacy.sanitize(fields: [
            "slot_id": .string(UUID().uuidString),
            "source": .string("trusted_manual_scroll"),
            "reason": .string("not_actually_presented"),
            "completion_valid": .bool(true),
            "presentation_visible": .bool(false),
            "web_window_key": .bool(false),
            "unread_before": .bool(true),
            "unread_after": .bool(true),
            "active_slot_matches": .bool(true),
            "attention_state_before": .string("ready"),
            "session_locked": .bool(false),
            "panel_visible": .bool(false),
            "document_token": .string("private-document"),
            "response_content": .string("private response"),
            "page_title": .string("private title"),
            "input_value": .string("private input"),
            "clipboard_content": .string("private clipboard")
        ], mode: .verbose)

        XCTAssertNotNil(fields["slot_id"])
        XCTAssertEqual(fields["source"], .string("trusted_manual_scroll"))
        XCTAssertEqual(fields["reason"], .string("not_actually_presented"))
        XCTAssertEqual(fields["completion_valid"], .bool(true))
        XCTAssertEqual(fields["presentation_visible"], .bool(false))
        XCTAssertEqual(fields["web_window_key"], .bool(false))
        XCTAssertEqual(fields["unread_before"], .bool(true))
        XCTAssertEqual(fields["unread_after"], .bool(true))
        XCTAssertEqual(fields["active_slot_matches"], .bool(true))
        XCTAssertEqual(fields["attention_state_before"], .string("ready"))
        XCTAssertEqual(fields["session_locked"], .bool(false))
        XCTAssertEqual(fields["panel_visible"], .bool(false))
        XCTAssertNil(fields["document_token"])
        XCTAssertNil(fields["response_content"])
        XCTAssertNil(fields["page_title"])
        XCTAssertNil(fields["input_value"])
        XCTAssertNil(fields["clipboard_content"])
    }

    func testResponseIdentityFragmentsAreNeverDiagnosticData() {
        let fields = RuntimeDiagnosticPrivacy.sanitize(fields: [
            "response_identity": .string("message:private"),
            "response_id": .string("private-response"),
            "document_token": .string("private-document"),
            "responseidentity_class": .string("already_handled_response"),
            "response_identity_tag": .string("0123456789abcdef"),
            "ack_identity_tag": .string("abcdef0123456789"),
            "document_token_tag": .string("fedcba9876543210"),
            "safe_reason": .string("already_handled_response")
        ], mode: .verbose)

        XCTAssertNil(fields["response_identity"])
        XCTAssertNil(fields["response_id"])
        XCTAssertNil(fields["document_token"])
        XCTAssertNil(fields["responseidentity_class"])
        XCTAssertEqual(fields["response_identity_tag"], .string("0123456789abcdef"))
        XCTAssertEqual(fields["ack_identity_tag"], .string("abcdef0123456789"))
        XCTAssertEqual(fields["document_token_tag"], .string("fedcba9876543210"))
        XCTAssertEqual(fields["safe_reason"], .string("already_handled_response"))
    }

    func testGenericLookingSensitiveKeysAreDroppedWithoutAnExactKeyDenylist() {
        let fields = RuntimeDiagnosticPrivacy.sanitize(fields: [
            "pageBodyText": .string("private page"),
            "domHTMLSnapshot": .string("<input value='private'>"),
            "formInputPayload": .string("private input"),
            "messageContent": .string("private message"),
            "requestAuthorizationHeader": .string("Bearer secret"),
            "safeState": .string("ready")
        ], mode: .verbose)

        XCTAssertNil(fields["pageBodyText"])
        XCTAssertNil(fields["domHTMLSnapshot"])
        XCTAssertNil(fields["formInputPayload"])
        XCTAssertNil(fields["messageContent"])
        XCTAssertNil(fields["requestAuthorizationHeader"])
        XCTAssertEqual(fields["safeState"], .string("ready"))
    }

    func testVoiceFocusDiagnosticsKeepOnlyFixedClassifications() {
        let fields = RuntimeDiagnosticPrivacy.sanitize(fields: [
            "focus_owner": .string("external_voice"),
            "voice_target_kind": .string("message_editor"),
            "voice_target_source": .string("captured"),
            "aria_label": .string("Message ChatGPT with private draft"),
            "text_content": .string("private message content")
        ], mode: .verbose)

        XCTAssertEqual(fields["focus_owner"], .string("external_voice"))
        XCTAssertEqual(fields["voice_target_kind"], .string("message_editor"))
        XCTAssertEqual(fields["voice_target_source"], .string("captured"))
        XCTAssertNil(fields["aria_label"])
        XCTAssertNil(fields["text_content"])
    }

    func testWriterReappliesSanitizerAtPersistenceBoundary() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsDiagnostics-privacy-" + UUID().uuidString)
        let writer = RuntimeDiagnosticWriter(directory: directory)
        let event = RuntimeDiagnosticEvent(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            uptime: 1,
            sequence: 1,
            sessionID: UUID(),
            traceID: nil,
            level: .notice,
            subsystem: "tests",
            event: "privacy.boundary",
            fields: [
                "url": .string("https://example.com/c/private?token=secret"),
                "body": .string("private page content"),
                "safe_state": .string("ready")
            ]
        )
        writer.enqueue(event)

        let flushed = expectation(description: "writer flushed")
        writer.requestFinalFlush(timeout: 1) { flushed.fulfill() }
        wait(for: [flushed], timeout: 2)

        let file = try XCTUnwrap(
            FileManager.default
                .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "jsonl" })
        )
        let contents = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(contents.contains("private page content"))
        XCTAssertFalse(contents.contains("token"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let persisted = try decoder.decode(
            RuntimeDiagnosticEvent.self,
            from: Data(contents.utf8)
        )
        XCTAssertEqual(persisted.fields["url"], .string("https://example.com/c/<redacted>"))
        XCTAssertNil(persisted.fields["body"])
        XCTAssertEqual(persisted.fields["safe_state"], .string("ready"))
    }

    func testWriterPersistenceDropsIPAddressURLAndBareHost() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsDiagnostics-ip-privacy-" + UUID().uuidString)
        let writer = RuntimeDiagnosticWriter(directory: directory)
        let event = RuntimeDiagnosticEvent(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            uptime: 1,
            sequence: 1,
            sessionID: UUID(),
            traceID: nil,
            level: .notice,
            subsystem: "tests",
            event: "privacy.ip.boundary",
            fields: [
                "url": .string("http://10.0.0.5/private?token=secret"),
                "host": .string("10.0.0.5"),
                "safe_state": .string("ready"),
                "safe_host": .string("example.com")
            ]
        )
        writer.enqueue(event)

        let flushed = expectation(description: "writer flushed")
        writer.requestFinalFlush(timeout: 1) { flushed.fulfill() }
        wait(for: [flushed], timeout: 2)

        let file = try XCTUnwrap(
            FileManager.default
                .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "jsonl" })
        )
        let contents = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(contents.contains("10.0.0.5"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let persisted = try decoder.decode(
            RuntimeDiagnosticEvent.self,
            from: Data(contents.utf8)
        )
        XCTAssertNil(persisted.fields["url"])
        XCTAssertNil(persisted.fields["host"])
        XCTAssertEqual(persisted.fields["safe_state"], .string("ready"))
        XCTAssertEqual(persisted.fields["safe_host"], .string("example.com"))
    }

    func testExportReadsOnlyManagedRuntimeSegmentsAndLeavesForeignJSONL() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsDiagnostics-export-boundary-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let managedFile = directory.appendingPathComponent("runtime-20260913-001.jsonl")
        try writeFixtureEvent(event: "managed.runtime.event", sequence: 1, to: managedFile)
        let highIndexFile = directory.appendingPathComponent("runtime-20260913-1000.jsonl")
        try writeFixtureEvent(event: "managed.high-index.event", sequence: 2, to: highIndexFile)

        let foreignFile = directory.appendingPathComponent("foreign.jsonl")
        XCTAssertTrue(
            FileManager.default.createFile(
                atPath: foreignFile.path,
                contents: Data("SECRET_FOREIGN_PAYLOAD\n".utf8)
            )
        )
        let malformedFile = directory.appendingPathComponent("runtime-20260913-01.jsonl")
        XCTAssertTrue(
            FileManager.default.createFile(
                atPath: malformedFile.path,
                contents: Data("SECRET_MALFORMED_PAYLOAD\n".utf8)
            )
        )
        let invalidDateFile = directory.appendingPathComponent("runtime-20261301-003.jsonl")
        XCTAssertTrue(
            FileManager.default.createFile(
                atPath: invalidDateFile.path,
                contents: Data("SECRET_INVALID_DATE_PAYLOAD\n".utf8)
            )
        )
        let directoryEntry = directory.appendingPathComponent("runtime-20260913-004.jsonl")
        try FileManager.default.createDirectory(
            at: directoryEntry,
            withIntermediateDirectories: false
        )
        let priorExport = directory.appendingPathComponent("FloatTabs-Diagnostics-old.jsonl")
        XCTAssertTrue(
            FileManager.default.createFile(
                atPath: priorExport.path,
                contents: Data("SECRET_PRIOR_EXPORT_PAYLOAD\n".utf8)
            )
        )

        XCTAssertTrue(RuntimeDiagnosticWriter.isManagedRuntimeSegment(managedFile))
        XCTAssertTrue(RuntimeDiagnosticWriter.isManagedRuntimeSegment(highIndexFile))
        XCTAssertFalse(RuntimeDiagnosticWriter.isManagedRuntimeSegment(foreignFile))
        XCTAssertFalse(RuntimeDiagnosticWriter.isManagedRuntimeSegment(malformedFile))
        XCTAssertFalse(RuntimeDiagnosticWriter.isManagedRuntimeSegment(invalidDateFile))
        XCTAssertFalse(RuntimeDiagnosticWriter.isManagedRuntimeSegment(directoryEntry))
        XCTAssertFalse(RuntimeDiagnosticWriter.isManagedRuntimeSegment(priorExport))

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsDiagnostics-export-" + UUID().uuidString + ".jsonl")
        let writer = RuntimeDiagnosticWriter(directory: directory)
        let exported = expectation(description: "exported")
        let result = LockedExportResult()
        writer.exportRecent(
            metadata: RuntimeDiagnosticEvent.exportFixture(event: "diagnostics.export.metadata", sequence: 2),
            to: destination
        ) {
            result.set($0)
            exported.fulfill()
        }
        wait(for: [exported], timeout: 2)

        guard case .success = result.value else {
            return XCTFail("diagnostics export failed: \(String(describing: result.value))")
        }
        let contents = try String(contentsOf: destination, encoding: .utf8)
        XCTAssertTrue(contents.contains("managed.runtime.event"))
        XCTAssertTrue(contents.contains("managed.high-index.event"))
        XCTAssertFalse(contents.contains("SECRET_FOREIGN_PAYLOAD"))
        XCTAssertFalse(contents.contains("SECRET_MALFORMED_PAYLOAD"))
        XCTAssertFalse(contents.contains("SECRET_INVALID_DATE_PAYLOAD"))
        XCTAssertFalse(contents.contains("SECRET_PRIOR_EXPORT_PAYLOAD"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: foreignFile.path))
    }

    func testExportCannotOverwriteActiveRuntimeSegment() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsDiagnostics-export-active-" + UUID().uuidString)
        let flushed = expectation(description: "debounced initial runtime flush")
        flushed.assertForOverFulfill = false
        let writer = RuntimeDiagnosticWriter(
            directory: directory,
            debounceInterval: 0.05,
            flushObserver: { flushed.fulfill() }
        )
        writer.enqueue(
            RuntimeDiagnosticEvent.exportFixture(
                event: "managed.runtime.event",
                sequence: 1
            )
        )
        wait(for: [flushed], timeout: 2)

        let activeFile = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .first(where: { RuntimeDiagnosticWriter.isManagedRuntimeSegment($0) })
        )
        let activeFilename = activeFile.deletingPathExtension().lastPathComponent
        let caseVariantDestination = directory.appendingPathComponent(
            "R" + String(activeFilename.dropFirst()) + ".jsonl"
        )
        let exportResult = LockedExportResult()
        let exportCompleted = expectation(description: "active segment export rejected")
        writer.exportRecent(
            metadata: RuntimeDiagnosticEvent.exportFixture(
                event: "diagnostics.export.metadata",
                sequence: 2
            ),
            to: caseVariantDestination
        ) {
            exportResult.set($0)
            exportCompleted.fulfill()
        }
        wait(for: [exportCompleted], timeout: 2)
        assertReservedDestination(exportResult.value)

        writer.enqueue(
            RuntimeDiagnosticEvent.exportFixture(
                event: "managed.runtime.event",
                sequence: 2
            )
        )
        let finalFlush = expectation(description: "final runtime flush")
        writer.requestFinalFlush(timeout: 1) { finalFlush.fulfill() }
        wait(for: [finalFlush], timeout: 2)

        let events = try decodeEvents(
            from: String(contentsOf: activeFile, encoding: .utf8)
        )
        XCTAssertEqual(events.map { $0.event }, [
            "managed.runtime.event",
            "managed.runtime.event"
        ])
        XCTAssertEqual(events.map { $0.sequence }, [1, 2])
        XCTAssertFalse(events.contains { $0.event == "diagnostics.export.metadata" })
    }

    func testExportRejectsManagedLookingDestinationInsideLogs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsDiagnostics-export-recursion-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let managedFile = directory.appendingPathComponent("runtime-20260913-001.jsonl")
        try writeFixtureEvent(event: "managed.runtime.event", sequence: 1, to: managedFile)
        let priorExport = directory.appendingPathComponent("FloatTabs-Diagnostics-old.jsonl")
        XCTAssertTrue(
            FileManager.default.createFile(
                atPath: priorExport.path,
                contents: Data("OLD_EXPORT_SENTINEL\n".utf8)
            )
        )

        let destination = directory.appendingPathComponent("runtime-20260913-999.jsonl")
        let writer = RuntimeDiagnosticWriter(directory: directory)
        let metadata = RuntimeDiagnosticEvent.exportFixture(
            event: "diagnostics.export.metadata",
            sequence: 2
        )

        let firstExported = expectation(description: "first export")
        let firstResult = LockedExportResult()
        writer.exportRecent(metadata: metadata, to: destination) { result in
            firstResult.set(result)
            firstExported.fulfill()
        }
        wait(for: [firstExported], timeout: 2)
        assertReservedDestination(firstResult.value)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testExportRejectsASCIICaseVariantsOfManagedLookingDestinationInsideLogs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsDiagnostics-export-case-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let writer = RuntimeDiagnosticWriter(directory: directory)
        let variants = [
            "Runtime-20260913-001.jsonl",
            "RUNTIME-20260913-001.jsonl",
            "runtime-20260913-001.JSONL",
            "Runtime-20260913-999.JSONL"
        ]

        for (index, filename) in variants.enumerated() {
            let destination = directory.appendingPathComponent(filename)
            let exported = expectation(description: "reserved case variant \(index)")
            let result = LockedExportResult()
            writer.exportRecent(
                metadata: RuntimeDiagnosticEvent.exportFixture(
                    event: "diagnostics.export.metadata",
                    sequence: UInt64(index + 1)
                ),
                to: destination
            ) {
                result.set($0)
                exported.fulfill()
            }
            wait(for: [exported], timeout: 2)

            assertReservedDestination(result.value)
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    func testExportRejectsNonExistingManagedLookingDestinationInsideLogs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsDiagnostics-export-nonexisting-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let destination = directory.appendingPathComponent("runtime-20260913-999.jsonl")
        let writer = RuntimeDiagnosticWriter(directory: directory)
        let exported = expectation(description: "reserved destination rejected")
        let result = LockedExportResult()
        writer.exportRecent(
            metadata: RuntimeDiagnosticEvent.exportFixture(
                event: "diagnostics.export.metadata",
                sequence: 1
            ),
            to: destination
        ) {
            result.set($0)
            exported.fulfill()
        }
        wait(for: [exported], timeout: 2)

        assertReservedDestination(result.value)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testNormalLogsExportDoesNotReingestPriorExport() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsDiagnostics-export-normal-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let managedFile = directory.appendingPathComponent("runtime-20260913-001.jsonl")
        try writeFixtureEvent(event: "managed.runtime.event", sequence: 1, to: managedFile)
        let priorExport = directory.appendingPathComponent("FloatTabs-Diagnostics-old.jsonl")
        XCTAssertTrue(
            FileManager.default.createFile(
                atPath: priorExport.path,
                contents: Data("OLD_EXPORT_SENTINEL\n".utf8)
            )
        )
        let writer = RuntimeDiagnosticWriter(directory: directory)
        let metadata = RuntimeDiagnosticEvent.exportFixture(
            event: "diagnostics.export.metadata",
            sequence: 2
        )

        let firstDestination = directory.appendingPathComponent("FloatTabs-Diagnostics-20260913.jsonl")
        let firstExported = expectation(description: "normal Logs export")
        let firstResult = LockedExportResult()
        writer.exportRecent(metadata: metadata, to: firstDestination) {
            firstResult.set($0)
            firstExported.fulfill()
        }
        wait(for: [firstExported], timeout: 2)
        assertSuccessfulExport(firstResult.value)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstDestination.path))

        let secondDestination = directory.appendingPathComponent("FloatTabs-Diagnostics-second.jsonl")
        let secondExported = expectation(description: "second normal Logs export")
        let secondResult = LockedExportResult()
        writer.exportRecent(metadata: metadata, to: secondDestination) {
            secondResult.set($0)
            secondExported.fulfill()
        }
        wait(for: [secondExported], timeout: 2)
        assertSuccessfulExport(secondResult.value)

        let secondContents = try String(contentsOf: secondDestination, encoding: .utf8)
        XCTAssertFalse(secondContents.contains("OLD_EXPORT_SENTINEL"))
        XCTAssertEqual(try decodeEvents(from: secondContents).map(\.event), [
            "managed.runtime.event",
            "diagnostics.export.metadata"
        ])
    }

    func testManagedLookingExportOutsideLogsRemainsAllowed() throws {
        let logsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsDiagnostics-export-outside-logs-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let outsideDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsDiagnostics-export-destination-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)

        let managedFile = logsDirectory.appendingPathComponent("runtime-20260913-001.jsonl")
        try writeFixtureEvent(event: "managed.runtime.event", sequence: 1, to: managedFile)
        let destination = outsideDirectory.appendingPathComponent("Runtime-20260913-999.JSONL")
        let writer = RuntimeDiagnosticWriter(directory: logsDirectory)
        let exported = expectation(description: "outside Logs export")
        let result = LockedExportResult()
        writer.exportRecent(
            metadata: RuntimeDiagnosticEvent.exportFixture(
                event: "diagnostics.export.metadata",
                sequence: 2
            ),
            to: destination
        ) {
            result.set($0)
            exported.fulfill()
        }
        wait(for: [exported], timeout: 2)

        assertSuccessfulExport(result.value)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try decodeEvents(from: String(contentsOf: destination, encoding: .utf8)).map(\.event), [
            "managed.runtime.event",
            "diagnostics.export.metadata"
        ])
    }

    func testManagedLookingExportThroughLogsSymlinkAliasIsRejected() throws {
        let logsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsDiagnostics-export-symlink-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let logsAlias = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsDiagnostics-export-symlink-alias-" + UUID().uuidString)
        try FileManager.default.createSymbolicLink(at: logsAlias, withDestinationURL: logsDirectory)

        let destination = logsAlias.appendingPathComponent("runtime-20260913-999.jsonl")
        let writer = RuntimeDiagnosticWriter(directory: logsDirectory)
        let exported = expectation(description: "symlink alias reserved destination rejected")
        let result = LockedExportResult()
        writer.exportRecent(
            metadata: RuntimeDiagnosticEvent.exportFixture(
                event: "diagnostics.export.metadata",
                sequence: 1
            ),
            to: destination
        ) {
            result.set($0)
            exported.fulfill()
        }
        wait(for: [exported], timeout: 2)

        assertReservedDestination(result.value)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testManagedLookingExportThroughCaseVariantLogsDirectoryUsesFilesystemIdentity() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsDiagnostics-export-directory-case-" + UUID().uuidString)
        let logsDirectory = root.appendingPathComponent("Logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let caseVariantDirectory = root.appendingPathComponent("logs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: caseVariantDirectory.path) else {
            throw XCTSkip("temporary test volume is case-sensitive")
        }

        let destination = caseVariantDirectory.appendingPathComponent("runtime-20260913-999.jsonl")
        let writer = RuntimeDiagnosticWriter(directory: logsDirectory)
        let exported = expectation(description: "case-variant Logs destination rejected")
        let result = LockedExportResult()
        writer.exportRecent(
            metadata: RuntimeDiagnosticEvent.exportFixture(
                event: "diagnostics.export.metadata",
                sequence: 1
            ),
            to: destination
        ) {
            result.set($0)
            exported.fulfill()
        }
        wait(for: [exported], timeout: 2)

        assertReservedDestination(result.value)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    private func assertReservedDestination(
        _ result: Result<Void, RuntimeDiagnosticExportError>?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .failure(error) = result else {
            return XCTFail("expected reserved destination failure, got \(String(describing: result))", file: file, line: line)
        }
        guard case .reservedDestination = error else {
            return XCTFail("expected reservedDestination, got \(error)", file: file, line: line)
        }
        XCTAssertEqual(error.diagnosticCategory, "reserved_destination", file: file, line: line)
    }

    private func assertSuccessfulExport(
        _ result: Result<Void, RuntimeDiagnosticExportError>?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .success = result else {
            return XCTFail("expected successful export, got \(String(describing: result))", file: file, line: line)
        }
    }

    private func decodeEvents(from contents: String) throws -> [RuntimeDiagnosticEvent] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try contents
            .split(separator: "\n")
            .map { try decoder.decode(RuntimeDiagnosticEvent.self, from: Data($0.utf8)) }
    }

    private func writeFixtureEvent(
        event: String,
        sequence: UInt64,
        to url: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(
            RuntimeDiagnosticEvent.exportFixture(event: event, sequence: sequence)
        )
        data.append(0x0A)
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: data))
    }
}

private extension RuntimeDiagnosticEvent {
    static func exportFixture(event: String, sequence: UInt64) -> RuntimeDiagnosticEvent {
        RuntimeDiagnosticEvent(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            uptime: Double(sequence),
            sequence: sequence,
            sessionID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            traceID: nil,
            level: .notice,
            subsystem: "tests",
            event: event,
            fields: ["safe_state": .string("ready")]
        )
    }
}

private final class LockedExportResult: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Result<Void, RuntimeDiagnosticExportError>?

    var value: Result<Void, RuntimeDiagnosticExportError>? {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func set(_ value: Result<Void, RuntimeDiagnosticExportError>) {
        lock.lock()
        storage = value
        lock.unlock()
    }
}
