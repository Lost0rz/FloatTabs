import XCTest
@testable import FloatTabs

final class MathSpeechNormalizerTests: XCTestCase {
    func testChineseRatioExamplesAreDeterministicallyReadable() {
        XCTAssertEqual(
            MathSpeechNormalizer.normalize("m^2 : mn : n^2 : mn", languageRole: .chinese).text,
            "m 的平方 比 m n 比 n 的平方 比 m n"
        )
        XCTAssertEqual(
            MathSpeechNormalizer.normalize("CE : AD = 2 : 3", languageRole: .chinese).text,
            "C E 比 A D 等于 2 比 3"
        )
        XCTAssertEqual(
            MathSpeechNormalizer.normalize("2^2 : 2 \\times 3 : 2 \\times 3 : 3^2", languageRole: .chinese).text,
            "2 的平方 比 2 乘 3 比 2 乘 3 比 3 的平方"
        )
        XCTAssertEqual(
            MathSpeechNormalizer.normalize("4 : 6 : 6 : 9", languageRole: .chinese).text,
            "4 比 6 比 6 比 9"
        )
    }

    func testSimpleChineseAndEnglishOperations() {
        XCTAssertEqual(
            MathSpeechNormalizer.normalize("x^2 + y^2 = 25", languageRole: .chinese).text,
            "x 的平方 加 y 的平方 等于 25"
        )
        XCTAssertEqual(
            MathSpeechNormalizer.normalize("x^2 + y^2 = 25", languageRole: .english).text,
            "x squared plus y squared equals 25"
        )
        XCTAssertTrue(
            MathSpeechNormalizer.normalize("x >= 3", languageRole: .chinese).text.contains("大于等于")
        )
        XCTAssertTrue(
            MathSpeechNormalizer.normalize("\\sqrt{x+1}", languageRole: .chinese).text.contains("根号")
        )
        XCTAssertEqual(
            MathSpeechNormalizer.normalize("\\frac{a}{b}", languageRole: .english).text,
            "a over b"
        )
        XCTAssertTrue(
            MathSpeechNormalizer.normalize("2 * 3", languageRole: .chinese).text.contains("2 乘 3")
        )
        XCTAssertTrue(
            MathSpeechNormalizer.normalize("2 * 3", languageRole: .english).text.contains("2 times 3")
        )
    }

    func testFormulaWithoutSemanticSourceUsesSafeFallback() {
        let chinese = MathSpeechNormalizer.normalize(
            MathSpeechNormalizer.noSourceFormulaSentinel,
            languageRole: .chinese
        )
        let english = MathSpeechNormalizer.normalize(
            MathSpeechNormalizer.noSourceFormulaSentinel,
            languageRole: .english
        )

        XCTAssertEqual(chinese.text, "此处有一个复杂公式。")
        XCTAssertEqual(english.text, "There is a complex formula here.")
        XCTAssertEqual(chinese.complexity, .complex)
        XCTAssertEqual(english.complexity, .complex)
    }

    func testUnsupportedMathUsesSemanticFallbackWithoutRawLatex() {
        let cases = [
            "\\begin{cases}x & x > 0\\end{cases}",
            "\\frac{\\frac{a}{b}}{c}",
            "\\unknown{x}",
        ]

        for source in cases {
            let result = MathSpeechNormalizer.normalize(source, languageRole: .english)
            XCTAssertEqual(result.complexity, .complex)
            XCTAssertEqual(result.text, "There is a complex formula here.")
            XCTAssertFalse(result.text.contains("\\"))
            XCTAssertFalse(result.text.contains("begin"))
        }
    }

    func testMathLanguageUsesNearestSurroundingText() {
        let chinese = SpeechLanguageRouter.utteranceRequests(for: [
            SpeechContentBlock(kind: .paragraph, text: "由", level: nil),
            SpeechContentBlock(kind: .mathInline, text: "x^2=25", level: nil),
            SpeechContentBlock(kind: .paragraph, text: "可知。", level: nil),
        ])
        XCTAssertEqual(chinese.map(\.languageRole), [.chinese, .chinese, .chinese])

        let english = SpeechLanguageRouter.utteranceRequests(for: [
            SpeechContentBlock(kind: .paragraph, text: "The radius is", level: nil),
            SpeechContentBlock(kind: .mathInline, text: "x^2=25", level: nil),
            SpeechContentBlock(kind: .paragraph, text: "in this example.", level: nil),
        ])
        XCTAssertEqual(english.map(\.languageRole), [.english, .english, .english])
    }
}
