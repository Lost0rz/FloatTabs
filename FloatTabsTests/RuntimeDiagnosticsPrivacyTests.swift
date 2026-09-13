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

    func testSensitiveFieldsAreDroppedBeforePersistence() {
        let fields = RuntimeDiagnosticPrivacy.sanitize(fields: [
            "token": .string("secret"),
            "Authorization": .string("Bearer secret"),
            "inputValue": .string("private text"),
            "safeState": .string("ready")
        ], mode: .verbose)

        XCTAssertNil(fields["token"])
        XCTAssertNil(fields["Authorization"])
        XCTAssertNil(fields["inputValue"])
        XCTAssertEqual(fields["safeState"], .string("ready"))
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

    func testExportDoesNotReingestInDirectoryManagedLookingDestination() throws {
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
        writer.exportRecent(metadata: metadata, to: destination) { result in
            if case .failure = result {
                XCTFail("first diagnostics export failed: \(result)")
            }
            firstExported.fulfill()
        }
        wait(for: [firstExported], timeout: 2)
        let firstContents = try String(contentsOf: destination, encoding: .utf8)
        XCTAssertFalse(firstContents.contains("OLD_EXPORT_SENTINEL"))

        let secondExported = expectation(description: "second export")
        writer.exportRecent(metadata: metadata, to: destination) { result in
            if case .failure = result {
                XCTFail("second diagnostics export failed: \(result)")
            }
            secondExported.fulfill()
        }
        wait(for: [secondExported], timeout: 2)
        let secondContents = try String(contentsOf: destination, encoding: .utf8)

        XCTAssertFalse(secondContents.contains("OLD_EXPORT_SENTINEL"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let secondEvents = try secondContents
            .split(separator: "\n")
            .map { try decoder.decode(RuntimeDiagnosticEvent.self, from: Data($0.utf8)) }
        XCTAssertEqual(secondEvents.map(\.event), [
            "managed.runtime.event",
            "diagnostics.export.metadata"
        ])
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
