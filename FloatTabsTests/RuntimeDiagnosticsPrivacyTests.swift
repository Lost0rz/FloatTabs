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
}
