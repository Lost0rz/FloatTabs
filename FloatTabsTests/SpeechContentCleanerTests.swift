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

    func testDropsPurePunctuationAndSymbolBlocks() {
        for text in ["......", "…………", "••••••", "***", "---"] {
            XCTAssertNil(
                SpeechContentCleaner.clean(
                    SpeechContentBlock(kind: .paragraph, text: text, level: nil)
                ),
                "Expected \(text) to be filtered"
            )
        }
    }

    func testRemovesListBulletsAndOrdinalPrefixes() {
        XCTAssertEqual(
            SpeechContentCleaner.clean(
                SpeechContentBlock(kind: .listItem, text: "• 第一项", level: nil)
            ),
            "第一项"
        )
        XCTAssertEqual(
            SpeechContentCleaner.clean(
                SpeechContentBlock(kind: .listItem, text: "1. 第一种方案", level: nil)
            ),
            "第一种方案"
        )
        XCTAssertEqual(
            SpeechContentCleaner.clean(
                SpeechContentBlock(kind: .listItem, text: "2) Second option", level: nil)
            ),
            "Second option"
        )
        XCTAssertEqual(
            SpeechContentCleaner.clean(
                SpeechContentBlock(kind: .listItem, text: "10、 第十项", level: nil)
            ),
            "第十项"
        )
        XCTAssertNil(
            SpeechContentCleaner.clean(
                SpeechContentBlock(kind: .listItem, text: "1.", level: nil)
            )
        )
    }

    func testPreservesMeaningfulNumbersAndTechnicalIdentifiers() {
        let blocks = [
            SpeechContentBlock(kind: .paragraph, text: "版本是 0.2.6。", level: nil),
            SpeechContentBlock(kind: .paragraph, text: "成功率 95%。", level: nil),
            SpeechContentBlock(kind: .paragraph, text: "模型是 GPT-5.6。", level: nil),
        ]

        XCTAssertEqual(
            SpeechContentCleaner.clean(blocks),
            "版本是 0.2.6。\n\n成功率 95%。\n\n模型是 GPT-5.6。"
        )
    }

    func testKeepsRichTextAndMathBlocksForSemanticNormalization() {
        let blocks = [
            SpeechContentBlock(
                kind: .richText,
                text: "小底平方 — 两翼都是两底乘积 — 大底平方",
                level: nil
            ),
            SpeechContentBlock(
                kind: .mathBlock,
                text: "m^2 : mn : n^2 : mn",
                level: nil
            ),
        ]

        XCTAssertEqual(
            SpeechContentCleaner.cleanBlocks(blocks).map(\.kind),
            [.richText, .mathBlock]
        )
        XCTAssertNotNil(SpeechContentCleaner.clean(blocks[1]))
    }

    func testCleaningPreservesTransientSourceLocator() {
        let locator = SpeechSourceLocator(
            documentToken: "document-12345678",
            responseID: "document-12345678:response-1",
            blockID: "document-12345678:response-1:block-0"
        )
        let cleaned = SpeechContentCleaner.cleanBlocks([
            SpeechContentBlock(
                kind: .paragraph,
                text: "**Readable.**",
                level: nil,
                sourceLocator: locator
            ),
        ])

        XCTAssertEqual(cleaned.first?.text, "Readable.")
        XCTAssertEqual(cleaned.first?.sourceLocator, locator)
    }
}
