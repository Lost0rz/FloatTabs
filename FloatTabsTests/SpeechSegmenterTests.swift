import XCTest
@testable import FloatTabs

final class SpeechSegmenterTests: XCTestCase {
    func testUsesEnglishSentenceBoundaries() {
        XCTAssertEqual(
            SpeechSegmenter.segment("First sentence. Second sentence!"),
            ["First sentence.", "Second sentence!"]
        )
    }

    func testSupportsChineseAndMixedText() {
        XCTAssertEqual(
            SpeechSegmenter.segment("第一句。Second sentence。混合完成！"),
            ["第一句。", "Second sentence。", "混合完成！"]
        )
    }

    func testBoundsLongAnswerWithoutTinyTokenSegments() {
        let text = Array(repeating: "This is a useful sentence.", count: 40).joined(separator: " ")
        let segments = SpeechSegmenter.segment(text, maximumLength: 80)

        XCTAssertGreaterThan(segments.count, 1)
        XCTAssertTrue(segments.allSatisfy { $0.count <= 80 })
        XCTAssertTrue(segments.allSatisfy { !$0.isEmpty })
    }
}
