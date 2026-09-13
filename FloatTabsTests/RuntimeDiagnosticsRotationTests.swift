import Foundation
import XCTest
@testable import FloatTabs

final class RuntimeDiagnosticsRotationTests: XCTestCase {
    func testWriterRotatesAtConfiguredLimitAndRetainsOnlyConfiguredSegments() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsDiagnostics-\(UUID().uuidString)")
        let writer = RuntimeDiagnosticWriter(
            directory: directory,
            maxSegmentBytes: 220,
            maxSegments: 2,
            retention: 7 * 24 * 60 * 60
        )
        for sequence in 1...12 {
            writer.enqueue(RuntimeDiagnosticEvent.test(sequence: UInt64(sequence)))
        }
        let flushed = expectation(description: "writer flushed")
        writer.requestFinalFlush(timeout: 1) { flushed.fulfill() }
        wait(for: [flushed], timeout: 2)

        let files = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }
        XCTAssertLessThanOrEqual(files.count, 2)
        XCTAssertTrue(files.allSatisfy { (try? Data(contentsOf: $0)) != nil })
    }

    func testWriterFailureDoesNotThrowOrInvokeBusinessError() {
        let writer = RuntimeDiagnosticWriter(
            directory: URL(fileURLWithPath: "/dev/null/impossible")
        )
        writer.enqueue(RuntimeDiagnosticEvent.test(sequence: 1))
        writer.requestFinalFlush(timeout: 0.1) {}
    }
}

private extension RuntimeDiagnosticEvent {
    static func test(sequence: UInt64) -> RuntimeDiagnosticEvent {
        RuntimeDiagnosticEvent(
            schemaVersion: 1,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(sequence)),
            uptime: Double(sequence),
            sequence: sequence,
            sessionID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            traceID: nil,
            level: .notice,
            subsystem: "tests",
            event: "test.event",
            fields: ["payload": .string(String(repeating: "x", count: 80))]
        )
    }
}
