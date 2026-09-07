import XCTest
@testable import FloatTabs

final class SpeechContentCleanerTests: XCTestCase {
    func testKeepsUsefulStructuredProseAndRemovesMarkdownPunctuation() {
        let blocks = [
            SpeechContentBlock(kind: .heading, text: "## Summary", level: 2),
            SpeechContentBlock(kind: .paragraph, text: "**The answer** is *here* [link](https://example.com).", level: nil),
            SpeechContentBlock(kind: .listItem, text: "- First item", level: nil),
            SpeechContentBlock(kind: .quote, text: "> A short quote.", level: nil),
        ]

        XCTAssertEqual(
            SpeechContentCleaner.clean(blocks),
            "Summary\n\nThe answer is here link.\n\nFirst item\n\nA short quote."
        )
    }

    func testSkipsCodeAndTables() {
        let blocks = [
            SpeechContentBlock(kind: .paragraph, text: "Before.", level: nil),
            SpeechContentBlock(kind: .code, text: "let secret = \"do not read\"", level: nil),
            SpeechContentBlock(kind: .table, text: "hundreds of cells", level: nil),
            SpeechContentBlock(kind: .paragraph, text: "After.", level: nil),
        ]

        XCTAssertEqual(SpeechContentCleaner.clean(blocks), "Before.\n\nAfter.")
    }

    func testSkipsRawJSONAndStackTraces() {
        XCTAssertNil(
            SpeechContentCleaner.clean(
                SpeechContentBlock(kind: .paragraph, text: "{\"answer\":\"secret\"}", level: nil)
            )
        )
        XCTAssertNil(
            SpeechContentCleaner.clean(
                SpeechContentBlock(
                    kind: .paragraph,
                    text: "Traceback\n  at first\n  at second",
                    level: nil
                )
            )
        )
        XCTAssertNil(
            SpeechContentCleaner.clean(
                SpeechContentBlock(
                    kind: .paragraph,
                    text: "diff --git a/a.swift b/a.swift\n--- a/a.swift\n+++ b/a.swift\n@@ -1 +1 @@",
                    level: nil
                )
            )
        )
    }

    func testCollapsesLongURLsAndFilesystemPaths() {
        let cleaned = SpeechContentCleaner.clean([
            SpeechContentBlock(
                kind: .paragraph,
                text: "See https://example.com/a/very/long/path and /Users/jack/project/file.swift.",
                level: nil
            )
        ])

        XCTAssertEqual(cleaned, "See 链接 and 路径")
        XCTAssertFalse(cleaned.contains("example.com"))
        XCTAssertFalse(cleaned.contains("/Users/"))
    }
}
