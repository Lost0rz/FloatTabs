import WebKit
import XCTest
@testable import FloatTabs

@MainActor
private final class ChatGPTResponsePageHarness {
    let webView: WKWebView
    let bridge: ChatGPTResponseBridge

    init() {
        let configuration = WKWebViewConfiguration()
        let bridge = ChatGPTResponseBridge(slotID: UUID())
        bridge.install(into: configuration.userContentController)
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
        bridge.attach(to: webView)
        self.webView = webView
        self.bridge = bridge
    }

    func load(_ bodyHTML: String) {
        let html = "<!doctype html><html><body>\(bodyHTML)</body></html>"
        webView.loadHTMLString(html, baseURL: URL(string: "https://chatgpt.com/c/test")!)
    }

    func settle() async {
        while webView.isLoading {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    func extract() async -> ChatGPTResponsePayload? {
        await withCheckedContinuation { continuation in
            bridge.extractLatest { payload in
                continuation.resume(returning: payload)
            }
        }
    }

    func replaceLatestAssistantNode(id: String = "reply-latest") async -> Bool {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(
                """
                (() => {
                  const original = document.querySelector('[data-message-id="\(id)"]');
                  if (!original) return false;
                  const replacement = original.cloneNode(true);
                  original.replaceWith(replacement);
                  return original !== replacement;
                })()
                """,
                completionHandler: { result, _ in
                    continuation.resume(returning: result as? Bool ?? false)
                }
            )
        }
    }

    func scroll(_ locator: SpeechSourceLocator) async -> Bool {
        await withCheckedContinuation { continuation in
            bridge.scrollToSpeechBlock(locator) { result in
                continuation.resume(returning: result)
            }
        }
    }
}

@MainActor
final class ChatGPTResponseExtractionTests: XCTestCase {
    func testAssistantAndUserMessagesExtractAssistantOnly() async {
        let page = ChatGPTResponsePageHarness()
        page.load("""
        <div data-message-author-role="user"><p>User must not be read.</p></div>
        <div data-message-author-role="assistant" data-message-id="reply-1">
          <h2>Answer</h2>
          <p>Assistant response only.</p>
          <ul><li>Useful item</li></ul>
        </div>
        """)
        await page.settle()

        let payload = await page.extract()
        XCTAssertEqual(payload?.responseID?.hasSuffix(":reply-1"), true)
        let texts = payload?.blocks.map(\.text) ?? []
        XCTAssertTrue(texts.contains("Assistant response only."))
        XCTAssertFalse(texts.contains { $0.contains("User must not be read") })
        XCTAssertTrue(texts.contains("Useful item"))
    }

    func testLatestAssistantReplyIsSelectedAndStableAcrossRerender() async {
        let page = ChatGPTResponsePageHarness()
        page.load("""
        <div data-message-author-role="assistant" data-message-id="reply-old">
          <p>Old response.</p>
        </div>
        <div data-message-author-role="assistant" data-message-id="reply-latest">
          <p>Latest response.</p>
        </div>
        """)
        await page.settle()

        let first = await page.extract()
        let replaced = await page.replaceLatestAssistantNode()
        let second = await page.extract()

        XCTAssertTrue(replaced)
        XCTAssertEqual(first?.responseID, second?.responseID)
        XCTAssertEqual(first?.blocks.map(\.text), ["Latest response."])
        XCTAssertEqual(second?.blocks.map(\.text), ["Latest response."])
        XCTAssertEqual(
            first?.blocks.map { $0.sourceLocator?.blockID },
            second?.blocks.map { $0.sourceLocator?.blockID }
        )
        XCTAssertEqual(first?.blocks.first?.sourceLocator?.responseID, first?.responseID)
    }

    func testEveryEmittedLogicalBlockHasAnOpaqueLocatorInDocumentOrder() async {
        let page = ChatGPTResponsePageHarness()
        page.load("""
        <div data-message-author-role="assistant" data-message-id="reply-locators">
          <p>A <span class="katex" style="display:inline-block"><math><semantics>
            <annotation encoding="application/x-tex">x</annotation>
          </semantics></math></span> B <span class="katex" style="display:inline-block"><math><semantics>
            <annotation encoding="application/x-tex">y</annotation>
          </semantics></math></span> C</p>
          <div class="callout" style="display:block">A rich block.</div>
        </div>
        """)
        await page.settle()

        let payload = await page.extract()
        let blocks = payload?.blocks ?? []
        XCTAssertEqual(blocks.map(\.kind), [
            .paragraph, .mathInline, .paragraph, .mathInline, .paragraph, .richText,
        ])
        let locators = blocks.compactMap(\.sourceLocator)
        XCTAssertEqual(locators.count, blocks.count)
        XCTAssertEqual(Set(locators.map(\.blockID)).count, blocks.count)
        XCTAssertEqual(
            locators.map(\.responseID),
            Array(repeating: payload?.responseID ?? "", count: blocks.count)
        )
        XCTAssertEqual(
            locators.map(\.blockID).enumerated().map {
                $0.element.hasSuffix(":block-\($0.offset)")
            },
            Array(repeating: true, count: blocks.count)
        )
        XCTAssertTrue(locators.allSatisfy { $0.slotID == page.bridge.slotID })
    }

    func testScrollLocatorFailsClosedForUnknownIdentityAndDisconnectedElement() async {
        let page = ChatGPTResponsePageHarness()
        page.load("""
        <div data-message-author-role="assistant" data-message-id="reply-scroll">
          <p>Scroll target.</p>
        </div>
        """)
        await page.settle()

        let payload = await page.extract()
        guard let rawLocator = payload?.blocks.first?.sourceLocator,
              let responseID = payload?.responseID else {
            return XCTFail("Expected a response locator")
        }
        let validLocator = rawLocator.assigning(slotID: page.bridge.slotID)
        let validScroll = await page.scroll(validLocator)
        XCTAssertTrue(validScroll)
        let unknownScroll = await page.scroll(SpeechSourceLocator(
            slotID: page.bridge.slotID,
            documentToken: rawLocator.documentToken,
            responseID: responseID,
            blockID: "unknown-block"
        ))
        XCTAssertFalse(unknownScroll)
        let wrongResponseScroll = await page.scroll(SpeechSourceLocator(
            slotID: page.bridge.slotID,
            documentToken: rawLocator.documentToken,
            responseID: "wrong-response",
            blockID: rawLocator.blockID
        ))
        XCTAssertFalse(wrongResponseScroll)
        let oldDocumentScroll = await page.scroll(SpeechSourceLocator(
            slotID: page.bridge.slotID,
            documentToken: "old-document",
            responseID: responseID,
            blockID: rawLocator.blockID
        ))
        XCTAssertFalse(oldDocumentScroll)

        let replaced = await page.replaceLatestAssistantNode(id: "reply-scroll")
        XCTAssertTrue(replaced)
        let disconnectedScroll = await page.scroll(validLocator)
        XCTAssertFalse(disconnectedScroll)
    }

    func testStructuredCodeAndTableBlocksAreMarkedForCleaner() async {
        let page = ChatGPTResponsePageHarness()
        page.load("""
        <div data-message-author-role="assistant" data-message-id="reply-structured">
          <p>Readable prose.</p>
          <pre>let value = 1\nprint(value)</pre>
          <table><tr><td>raw cell</td></tr></table>
        </div>
        """)
        await page.settle()

        let payload = await page.extract()
        XCTAssertEqual(payload?.blocks.map(\.kind), [.paragraph, .code, .table])
        XCTAssertEqual(
            SpeechContentCleaner.clean(payload?.blocks ?? []),
            "Readable prose."
        )
    }

    func testDisplayKatexWithMathMLAndVisualTreeEmitsOneMathBlock() async {
        let page = ChatGPTResponsePageHarness()
        page.load("""
        <div data-message-author-role="assistant" data-message-id="reply-math-display">
          <p>所以直接套：</p>
          <div class="katex-display" style="display:block">
            <span class="katex">
              <span class="katex-mathml" style="display:none">
                <math><semantics>
                  <annotation encoding="application/x-tex">m^2 : mn : n^2 : mn</annotation>
                </semantics></math>
              </span>
              <span class="katex-html" aria-hidden="true">visual m 2 mn</span>
            </span>
          </div>
        </div>
        """)
        await page.settle()

        let payload = await page.extract()
        XCTAssertEqual(payload?.blocks.map(\.kind), [.paragraph, .mathBlock])
        XCTAssertEqual(payload?.blocks.last?.text, "m^2 : mn : n^2 : mn")
    }

    func testInlineKatexPreservesParagraphMathParagraphOrder() async {
        let page = ChatGPTResponsePageHarness()
        page.load("""
        <div data-message-author-role="assistant" data-message-id="reply-math-inline">
          <p>由 <span class="katex" style="display:inline-block">
            <span class="katex-mathml" style="display:none"><math><semantics>
              <annotation encoding="application/x-tex">x^2+y^2=25</annotation>
            </semantics></math></span>
            <span class="katex-html" aria-hidden="true">visual</span>
          </span> 可知半径为 5。</p>
        </div>
        """)
        await page.settle()

        let payload = await page.extract()
        XCTAssertEqual(payload?.blocks.map(\.kind), [.paragraph, .mathInline, .paragraph])
        XCTAssertEqual(payload?.blocks.map(\.text), ["由", "x^2+y^2=25", "可知半径为 5。"])
    }

    func testMathMLAnnotationIsTheCanonicalSource() async {
        let page = ChatGPTResponsePageHarness()
        page.load("""
        <div data-message-author-role="assistant" data-message-id="reply-mathml">
          <math style="display:inline-block"><semantics>
            <annotation encoding="application/x-tex">CE : AD = 2 : 3</annotation>
            <mrow><mi>visual</mi></mrow>
          </semantics></math>
        </div>
        """)
        await page.settle()

        let payload = await page.extract()
        XCTAssertEqual(payload?.blocks.map(\.kind), [.mathInline])
        XCTAssertEqual(payload?.blocks.first?.text, "CE : AD = 2 : 3")
    }

    func testHiddenMathMLAccessibilityChildDoesNotHideRenderedFormula() async {
        let page = ChatGPTResponsePageHarness()
        page.load("""
        <div data-message-author-role="assistant" data-message-id="reply-hidden-mathml">
          <span class="katex" style="display:inline-block">
            <span class="katex-mathml" style="display:none"><math><semantics>
              <annotation encoding="application/x-tex">4 : 6 : 6 : 9</annotation>
            </semantics></math></span>
            <span class="katex-html" aria-hidden="true">4 6 6 9</span>
          </span>
        </div>
        """)
        await page.settle()

        let payload = await page.extract()
        XCTAssertEqual(payload?.blocks.map(\.kind), [.mathInline])
        XCTAssertEqual(payload?.blocks.first?.text, "4 : 6 : 6 : 9")
    }

    func testStandaloneBorderedRichTextIsExtractedOnce() async {
        let page = ChatGPTResponsePageHarness()
        page.load("""
        <div data-message-author-role="assistant" data-message-id="reply-callout">
          <div class="callout" style="display:block">
            小底平方 — 两翼都是两底乘积 — 大底平方
          </div>
        </div>
        """)
        await page.settle()

        let payload = await page.extract()
        XCTAssertEqual(payload?.blocks.map(\.kind), [.richText])
        XCTAssertEqual(payload?.blocks.first?.text, "小底平方 — 两翼都是两底乘积 — 大底平方")
    }

    func testRichTextWrapperAroundParagraphDoesNotDuplicateParagraph() async {
        let page = ChatGPTResponsePageHarness()
        page.load("""
        <div data-message-author-role="assistant" data-message-id="reply-wrapper">
          <div class="callout" style="display:block"><p>Only one paragraph.</p></div>
        </div>
        """)
        await page.settle()

        let payload = await page.extract()
        XCTAssertEqual(payload?.blocks.map(\.kind), [.paragraph])
        XCTAssertEqual(payload?.blocks.map(\.text), ["Only one paragraph."])
    }

    func testChatGPTCopyAndActionBarControlsAreExcluded() async {
        let page = ChatGPTResponsePageHarness()
        page.load("""
        <div data-message-author-role="assistant" data-message-id="reply-controls">
          <p>Readable answer.</p>
          <div role="toolbar" data-testid="conversation-turn-action-bar">
            <button>Copy</button><span>Regenerate</span><span>Good response</span>
          </div>
        </div>
        """)
        await page.settle()

        let payload = await page.extract()
        XCTAssertEqual(payload?.blocks.map(\.kind), [.paragraph])
        XCTAssertEqual(payload?.blocks.map(\.text), ["Readable answer."])
    }

    func testMultipleInlineMathBlocksRemainInDocumentOrder() async {
        let page = ChatGPTResponsePageHarness()
        page.load("""
        <div data-message-author-role="assistant" data-message-id="reply-order">
          <p>A <span class="katex" style="display:inline-block"><math><semantics>
            <annotation encoding="application/x-tex">x</annotation>
          </semantics></math></span> B <span class="katex" style="display:inline-block"><math><semantics>
            <annotation encoding="application/x-tex">y</annotation>
          </semantics></math></span> C</p>
        </div>
        """)
        await page.settle()

        let payload = await page.extract()
        XCTAssertEqual(payload?.blocks.map(\.kind), [
            .paragraph, .mathInline, .paragraph, .mathInline, .paragraph
        ])
        XCTAssertEqual(payload?.blocks.map(\.text), ["A", "x", "B", "y", "C"])
    }

    func testNoAssistantMessageProducesEmptyExtraction() async {
        let page = ChatGPTResponsePageHarness()
        page.load("<div data-message-author-role=\"user\"><p>User text</p></div>")
        await page.settle()

        let payload = await page.extract()
        XCTAssertNil(payload)
    }
}
