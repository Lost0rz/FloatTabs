import XCTest
@testable import FloatTabs

@MainActor
final class RuntimeDiagnosticsTraceTests: XCTestCase {
    func testPresentationFocusRequestRetainsOriginalTraceAcrossReplacement() {
        let traceA = RuntimeDiagnosticTrace(root: "presentation-A")
        let traceB = RuntimeDiagnosticTrace(root: "presentation-B")
        let requestA = RuntimeDiagnosticPresentationFocusRequest(generation: 1, trace: traceA)
        let requestB = RuntimeDiagnosticPresentationFocusRequest(generation: 2, trace: traceB)

        XCTAssertEqual(requestA.trace, traceA)
        XCTAssertEqual(requestA.generation, 1)
        XCTAssertNotEqual(requestA, requestB)
        XCTAssertEqual(requestB.trace, traceB)
    }

    func testTabSelectionEventsCanShareAnExplicitTraceRoot() {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .verbose, writer: writer)
        let store = TabStore(repository: MemoryProfileRepository(), diagnostics: diagnostics)
        let first = store.add(name: "First", homeURL: URL(string: "https://example.com/first")!)!
        let second = store.add(name: "Second", homeURL: URL(string: "https://example.com/second")!)!
        let trace = diagnostics.beginTrace(root: "tab.selection")

        XCTAssertTrue(store.select(id: first.id, trace: trace))
        XCTAssertTrue(store.select(id: second.id, trace: trace))

        XCTAssertEqual(
            writer.events.suffix(4).map(\.traceID),
            [trace.id, trace.id, trace.id, trace.id]
        )
        XCTAssertEqual(writer.events.suffix(4).map(\.event), [
            "tab.selection.requested",
            "tab.selection.changed",
            "tab.selection.requested",
            "tab.selection.changed"
        ])
    }

    func testFullscreenObservationUsesProcessEnvelopeAndRealOwnerCorrelationFields() {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let diagnostics = RuntimeDiagnostics(
            mode: .standard,
            writer: writer,
            sessionID: sessionID
        )

        diagnostics.record(
            event: "fullscreen.state",
            level: .info,
            subsystem: "fullscreen",
            fields: [
                "session_state": .string("restoring"),
                "restore_generation": .integer(3),
                "source_window_number": .integer(42)
            ]
        )

        XCTAssertEqual(writer.events.count, 1)
        XCTAssertEqual(writer.events.first?.sessionID, sessionID)
        XCTAssertNil(writer.events.first?.traceID)
        XCTAssertEqual(writer.events.first?.fields["session_state"], .string("restoring"))
        XCTAssertEqual(writer.events.first?.fields["restore_generation"], .integer(3))
        XCTAssertEqual(writer.events.first?.fields["source_window_number"], .integer(42))
    }

    func testOneSemanticTraceIsSharedAndIndependentEventsMayHaveNoTrace() {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .verbose, writer: writer)
        let trace = diagnostics.beginTrace(
            root: "presentation",
            fields: ["source": .string("hotkey")]
        )

        diagnostics.record(
            event: "panel.presentation.begin",
            level: .notice,
            subsystem: "panel",
            trace: trace
        )
        diagnostics.record(
            event: "panel.presentation.completed",
            level: .notice,
            subsystem: "panel",
            trace: trace
        )
        diagnostics.record(
            event: "background.cleanup",
            level: .info,
            subsystem: "storage"
        )

        XCTAssertEqual(writer.events.prefix(2).map(\.traceID), [trace.id, trace.id])
        XCTAssertNil(writer.events.last?.traceID)
        XCTAssertEqual(Set(writer.events.prefix(2).map(\.traceID)).count, 1)
    }
}
