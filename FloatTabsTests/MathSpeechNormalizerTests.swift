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

    func testCommonGeometryRatiosAreNotComplex() {
        let cases = [
            "AB : CD = m : n",
            "m^2 : mn : mn : n^2",
            "m^2 : mn : n^2 : mn",
            "S_{AOB}:S_{BOC}:S_{COD}:S_{DOA}=m^2:mn:n^2:mn",
        ]

        for source in cases {
            let result = MathSpeechNormalizer.normalize(source, languageRole: .chinese)
            XCTAssertNotEqual(result.complexity, .complex, source)
            XCTAssertFalse(result.text.contains("复杂公式"), source)
        }
    }

    func testSubscriptsAreRenderedStructurally() {
        let result = MathSpeechNormalizer.normalize(
            "S_{AOB}:S_{BOC}:S_{COD}:S_{DOA}",
            languageRole: .chinese
        )

        XCTAssertNotEqual(result.complexity, .complex)
        XCTAssertTrue(result.text.contains("S 下标 A O B"))
        XCTAssertTrue(result.text.contains("S 下标 B O C"))
        XCTAssertTrue(result.text.contains("S 下标 C O D"))
        XCTAssertTrue(result.text.contains("S 下标 D O A"))
    }

    func testUnbracedSubscriptSingle() {
        XCTAssertEqual(
            MathSpeechNormalizer.normalize("S_A", languageRole: .chinese).text,
            "S 下标 A"
        )
    }

    func testUnbracedNumericSubscript() {
        XCTAssertEqual(
            MathSpeechNormalizer.normalize("x_1", languageRole: .chinese).text,
            "x 下标 1"
        )
    }

    func testMultipleUnbracedSubscriptsPreserveRatio() {
        XCTAssertEqual(
            MathSpeechNormalizer.normalize("S_A:S_B", languageRole: .chinese).text,
            "S 下标 A 比 S 下标 B"
        )
    }

    func testUnbracedSubscriptsPreservePlusExpression() {
        XCTAssertEqual(
            MathSpeechNormalizer.normalize("x_1+y_2", languageRole: .chinese).text,
            "x 下标 1 加 y 下标 2"
        )
    }

    func testSubscriptThenSuperscript() {
        XCTAssertEqual(
            MathSpeechNormalizer.normalize("A_i^2", languageRole: .chinese).text,
            "A 下标 i 的平方"
        )
    }

    func testBracedSubscriptRegression() {
        let result = MathSpeechNormalizer.normalize("S_{AOB}", languageRole: .chinese)

        XCTAssertNotEqual(result.complexity, .complex)
        XCTAssertEqual(result.text, "S 下标 A O B")
    }

    func testAreaRatioRegressionRemainsReadable() {
        let source = "S_{AOB}:S_{BOC}:S_{COD}:S_{DOA}=m^2:mn:n^2:mn"
        let result = MathSpeechNormalizer.normalize(source, languageRole: .chinese)

        XCTAssertNotEqual(result.complexity, .complex)
        XCTAssertFalse(result.text.contains("复杂公式"))
    }

    func testBoxedAreaRatioRegressionRemainsReadable() {
        let source = #"\boxed{S_{AOB}:S_{BOC}:S_{COD}:S_{DOA}=m^2:mn:n^2:mn}"#
        let result = MathSpeechNormalizer.normalize(source, languageRole: .chinese)

        XCTAssertNotEqual(result.complexity, .complex)
        XCTAssertFalse(result.text.contains("复杂公式"))
    }

    func testBoxedPresentationalWrapperIsIgnored() {
        let source = #"\boxed{S_{AOB}:S_{BOC}:S_{COD}:S_{DOA}=m^2:mn:n^2:mn}"#
        let result = MathSpeechNormalizer.normalize(source, languageRole: .chinese)

        XCTAssertNotEqual(result.complexity, .complex)
        XCTAssertFalse(result.text.contains("方框"))
        XCTAssertFalse(result.text.contains("复杂公式"))
        XCTAssertTrue(result.text.contains("m 的平方"))
    }

    func testPresentationalDecoratorsAndSpacingAreIgnored() {
        let source = #"\displaystyle\boxed{m^2\: :\quad mn\; :\!n^2}"#
        let result = MathSpeechNormalizer.normalize(source, languageRole: .chinese)

        XCTAssertNotEqual(result.complexity, .complex)
        XCTAssertEqual(result.text, "m 的平方 比 m n 比 n 的平方")
    }

    func testLeftRightDecoratorsAreIgnored() {
        let result = MathSpeechNormalizer.normalize(
            #"\left( m^2 : n^2 \right)"#,
            languageRole: .chinese
        )

        XCTAssertNotEqual(result.complexity, .complex)
        XCTAssertTrue(result.text.contains("m 的平方"))
        XCTAssertTrue(result.text.contains("n 的平方"))
    }

    func testCommonGeometryCommandsAreReadable() {
        let cases: [(String, String)] = [
            (#"AB \parallel CD"#, "平行于"),
            (#"AB \perp CD"#, "垂直于"),
            (#"\angle ABC"#, "角"),
            (#"\triangle ABC"#, "三角形"),
            (#"60^\circ"#, "60 度"),
        ]

        for (source, expected) in cases {
            let result = MathSpeechNormalizer.normalize(source, languageRole: .chinese)
            XCTAssertNotEqual(result.complexity, .complex, source)
            XCTAssertTrue(result.text.contains(expected), "\(source): \(result.text)")
        }
    }

    func testUnsupportedSemanticStructuresRemainComplex() {
        let cases = [
            #"\begin{matrix}a&b\\c&d\end{matrix}"#,
            #"\begin{cases}x & x > 0\\0 & otherwise\end{cases}"#,
            #"\frac{\frac{a}{b}}{c}"#,
            #"\unknown{x}"#,
        ]

        for source in cases {
            XCTAssertEqual(
                MathSpeechNormalizer.normalize(source, languageRole: .chinese).complexity,
                .complex,
                source
            )
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
