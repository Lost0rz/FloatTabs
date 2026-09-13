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
}
