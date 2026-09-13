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
}
