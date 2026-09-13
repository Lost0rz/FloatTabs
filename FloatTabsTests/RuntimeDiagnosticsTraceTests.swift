import XCTest
@testable import FloatTabs

@MainActor
final class RuntimeDiagnosticsTraceTests: XCTestCase {
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
