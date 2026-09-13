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

    func testWriterRemovesSegmentsOlderThanRetentionWindow() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsDiagnostics-retention-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let oldFile = directory.appendingPathComponent("runtime-old-001.jsonl")
        XCTAssertTrue(FileManager.default.createFile(atPath: oldFile.path, contents: Data("old\n".utf8)))
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-8 * 24 * 60 * 60)],
            ofItemAtPath: oldFile.path
        )

        let writer = RuntimeDiagnosticWriter(
            directory: directory,
            retention: 7 * 24 * 60 * 60
        )
        writer.enqueue(RuntimeDiagnosticEvent.test(sequence: 1))
        let flushed = expectation(description: "writer flushed")
        writer.requestFinalFlush(timeout: 1) { flushed.fulfill() }
        wait(for: [flushed], timeout: 2)

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFile.path))
    }

    func testWriterPreservesEnqueueOrderWithinAFlushedSegment() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsDiagnostics-order-" + UUID().uuidString)
        let writer = RuntimeDiagnosticWriter(
            directory: directory,
            maxSegmentBytes: 1024 * 1024,
            maxSegments: 2
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
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sequences = try files.flatMap { file in
            try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n")
                .map { try decoder.decode(RuntimeDiagnosticEvent.self, from: Data($0.utf8)).sequence }
        }
        XCTAssertEqual(sequences, Array(1...12).map(UInt64.init))
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
