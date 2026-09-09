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

    func appendAssistantNode(id: String, bodyHTML: String) async -> Bool {
        guard let idData = try? JSONEncoder().encode(id),
              let idJSON = String(data: idData, encoding: .utf8),
              let bodyData = try? JSONEncoder().encode(bodyHTML),
              let bodyJSON = String(data: bodyData, encoding: .utf8) else {
            return false
        }
        return await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(
                """
                (() => {
                  const node = document.createElement('div');
                  node.setAttribute('data-message-author-role', 'assistant');
                  node.setAttribute('data-message-id', \(idJSON));
                  node.innerHTML = \(bodyJSON);
                  document.body.appendChild(node);
                  return true;
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

    func testOlderResponseLocatorSurvivesLaterResponseExtraction() async {
        let page = ChatGPTResponsePageHarness()
        page.load("""
        <div data-message-author-role="assistant" data-message-id="reply-one">
          <p>R1 paragraph one.</p>
          <p>R1 paragraph two.</p>
        </div>
        """)
        await page.settle()

        let first = await page.extract()
        guard let firstBlocks = first?.blocks,
              let firstBlockOne = firstBlocks.first?.sourceLocator,
              let firstBlockTwo = firstBlocks.dropFirst().first?.sourceLocator else {
            return XCTFail("Expected two R1 locators")
        }
        let firstScroll = await page.scroll(firstBlockOne)
        XCTAssertTrue(firstScroll)
        let appended = await page.appendAssistantNode(
            id: "reply-two",
            bodyHTML: "<p>R2 paragraph one.</p><p>R2 paragraph two.</p>"
        )
        XCTAssertTrue(appended)

        let second = await page.extract()
        guard let secondBlockOne = second?.blocks.first?.sourceLocator else {
            return XCTFail("Expected an R2 locator")
        }
        let oldResponseScroll = await page.scroll(firstBlockTwo)
        let newResponseScroll = await page.scroll(secondBlockOne)
        XCTAssertTrue(oldResponseScroll)
        XCTAssertTrue(newResponseScroll)
    }

    func testSameResponseRefreshReplacesOnlyItsLocators() async {
        let page = ChatGPTResponsePageHarness()
        page.load("""
        <div data-message-author-role="assistant" data-message-id="reply-one">
          <p>R1 remains available.</p>
        </div>
        """)
        await page.settle()

        let first = await page.extract()
        guard let firstLocator = first?.blocks.first?.sourceLocator else {
            return XCTFail("Expected R1 locator")
        }
        let appended = await page.appendAssistantNode(
            id: "reply-two",
            bodyHTML: "<p>R2 before rerender.</p>"
        )
        XCTAssertTrue(appended)
        let second = await page.extract()
        guard let oldSecondLocator = second?.blocks.first?.sourceLocator else {
            return XCTFail("Expected initial R2 locator")
        }
        let replaced = await page.replaceLatestAssistantNode(id: "reply-two")
        XCTAssertTrue(replaced)
        let refreshed = await page.extract()
        guard let refreshedLocator = refreshed?.blocks.first?.sourceLocator else {
            return XCTFail("Expected refreshed R2 locator")
        }

        XCTAssertEqual(oldSecondLocator.blockID, refreshedLocator.blockID)
        let firstResponseScroll = await page.scroll(firstLocator)
        let refreshedOldLocatorScroll = await page.scroll(oldSecondLocator)
        let refreshedScroll = await page.scroll(refreshedLocator)
        XCTAssertTrue(firstResponseScroll)
        XCTAssertTrue(refreshedOldLocatorScroll)
        XCTAssertTrue(refreshedScroll)
    }

    func testEmptyExtractionDoesNotClearActiveResponseLocators() async {
        let page = ChatGPTResponsePageHarness()
        page.load("""
        <div data-message-author-role="assistant" data-message-id="reply-one">
          <p>Active R1 remains.</p>
        </div>
        """)
        await page.settle()

        let first = await page.extract()
        guard let firstLocator = first?.blocks.first?.sourceLocator else {
            return XCTFail("Expected active R1 locator")
        }
        let appended = await page.appendAssistantNode(
            id: "reply-empty",
            bodyHTML: "<span style='display:block;min-height:1px'></span>"
        )
        XCTAssertTrue(appended)
        let emptyPayload = await page.extract()
        XCTAssertNil(emptyPayload)
        let activeResponseScroll = await page.scroll(firstLocator)
        XCTAssertTrue(activeResponseScroll)
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

    func testSemanticMathMLWithoutAnnotationPreservesCommonStructure() async {
        let page = ChatGPTResponsePageHarness()
        page.load("""
        <div data-message-author-role="assistant" data-message-id="reply-semantic-mathml">
          <p>常见公式：</p>
          <math style="display:inline-block"><semantics>
            <mrow>
              <msub><mi>S</mi><mrow><mi>A</mi><mi>O</mi><mi>B</mi></mrow></msub>
              <mo>:</mo>
              <msup><mi>m</mi><mn>2</mn></msup>
            </mrow>
          </semantics></math>
        </div>
        """)
        await page.settle()

        let payload = await page.extract()
        XCTAssertEqual(payload?.blocks.map(\.kind), [.paragraph, .mathInline])
        XCTAssertEqual(payload?.blocks.last?.text, "S_{AOB} : m^{2}")
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

    func testRealisticChatGPTMathStructureFixture() async {
        let page = ChatGPTResponsePageHarness()
        page.load("""
        <div data-message-author-role="assistant" data-message-id="reply-realistic">
          <div class="markdown prose">
            <p>下面测试数学公式和中英文混合朗读。</p>
            <p>这个 PR uses a manual priority barrier，所以 Auto Speak 不会打断。</p>
            <p>
              <span data-math="true" aria-hidden="true" style="display:inline-block" data-latex="x^2 + y^2 = 25">
                <span class="katex-mathml" style="display:none"><math><semantics>
                  <annotation encoding="application/x-tex">x^2 + y^2 = 25</annotation>
                </semantics></math></span>
                <span class="katex-html" aria-hidden="true">visual x 2 y 2 25</span>
              </span>
            </p>
            <div data-math="true" style="display:block" data-latex="CE : AD = 2 : 3">
              <span aria-hidden="true">visual CE AD 2 3</span>
            </div>
            <p>[Important] This English text must not disappear.</p>
          </div>
        </div>
        """)
        await page.settle()

        let payload = await page.extract()
        let blocks = payload?.blocks ?? []
        XCTAssertEqual(blocks.map(\.kind), [
            .paragraph, .paragraph, .mathInline, .mathBlock, .paragraph,
        ])
        XCTAssertTrue(blocks.contains { $0.text == "x^2 + y^2 = 25" })
        XCTAssertTrue(blocks.contains { $0.text == "CE : AD = 2 : 3" })
        XCTAssertTrue(blocks.contains { $0.text.contains("This English text must not disappear") })
        XCTAssertEqual(Set(blocks.compactMap(\.sourceLocator).map(\.responseID)).count, 1)

        let requests = SpeechLanguageRouter.utteranceRequests(for: blocks)
        XCTAssertTrue(requests.contains {
            $0.text.contains("x 的平方") || $0.text.contains("x squared")
        })
        XCTAssertTrue(requests.contains {
            $0.text.contains("C E")
                && $0.text.contains("A D")
                && ($0.text.contains("比") || $0.text.contains("to"))
        })
        XCTAssertTrue(requests.contains { $0.text.contains("This English text must not disappear") })
    }

    func testSyntheticGeometryQAConversationKeepsAllCommonMathSources() async {
        let page = ChatGPTResponsePageHarness()
        page.load("""
        <div data-message-author-role="assistant" data-message-id="reply-geometry-qa">
          <p>如果两条平行边：</p>
          <p><span data-math="true" data-latex="AB : CD = m : n" aria-hidden="true">visual</span></p>
          <p>那么面积关系是：</p>
          <div data-math="true" style="display:block" data-latex="S_{AOB}:S_{BOC}:S_{COD}:S_{DOA}=m^2:mn:n^2:mn">
            <span aria-hidden="true">visual area ratio</span>
          </div>
          <p><span data-math="true" data-latex="m^2 : mn : mn : n^2" aria-hidden="true">visual</span></p>
          <p>靠着短底的那块：<span data-math="true" data-latex="m^2" aria-hidden="true">visual</span></p>
          <p>两边翅膀都是 <span data-math="true" data-latex="mn" aria-hidden="true">visual</span></p>
          <p>靠着长底的那块：<span data-math="true" data-latex="n^2" aria-hidden="true">visual</span></p>
          <p><span data-math="true" data-latex="\\boxed{S_{AOB}:S_{BOC}:S_{COD}:S_{DOA}=m^2:mn:n^2:mn}" aria-hidden="true">visual boxed ratio</span></p>
        </div>
        """)
        await page.settle()

        let payload = await page.extract()
        let mathBlocks = (payload?.blocks ?? []).filter {
            $0.kind == .mathInline || $0.kind == .mathBlock
        }
        XCTAssertEqual(mathBlocks.count, 7)
        XCTAssertEqual(
            mathBlocks.map(\.text),
            [
                "AB : CD = m : n",
                "S_{AOB}:S_{BOC}:S_{COD}:S_{DOA}=m^2:mn:n^2:mn",
                "m^2 : mn : mn : n^2",
                "m^2",
                "mn",
                "n^2",
                "\\boxed{S_{AOB}:S_{BOC}:S_{COD}:S_{DOA}=m^2:mn:n^2:mn}",
            ]
        )
        XCTAssertFalse(mathBlocks.contains { $0.text.contains("without_semantic_source") })
        XCTAssertTrue(mathBlocks.allSatisfy {
            MathSpeechNormalizer.normalize($0.text).complexity != .complex
        })
        XCTAssertEqual(Set(mathBlocks.compactMap(\.sourceLocator).map(\.responseID)).count, 1)
    }

    func testPreformattedNaturalLanguageIsReadWithMeaningfulLineBoundaries() async {
        let page = ChatGPTResponsePageHarness()
        page.load("""
        <div data-message-author-role="assistant" data-message-id="reply-preformatted-prose">
          <p>Opening paragraph.</p>
          <pre><code><div class="cm-content">
            <div class="cm-line">This isn't surprising,</div>
            <div class="cm-line">这并不奇怪,</div>
            <div class="cm-line"></div>
            <div class="cm-line">considering the context,</div>
            <div class="cm-line">考虑到上下文,</div>
            <div class="cm-line">the basic mandatory high school curriculum</div>
            <div class="cm-line">基础的、强制性的高中课程</div>
            <div class="cm-line">leaves students with</div>
            <div class="cm-line">使学生留下</div>
            <div class="cm-line">a poor understanding of</div>
            <div class="cm-line">对……缺乏充分了解</div>
            <div class="cm-line">the vast academic possibilities</div>
            <div class="cm-line">大量的学术可能性</div>
            <div class="cm-line">that await them in college</div>
            <div class="cm-line">他们进入大学后将会面对的</div>
            <button>Copy</button>
          </div></code></pre>
        </div>
        """)
        await page.settle()

        let blocks = await page.extract()?.blocks ?? []
        XCTAssertEqual(blocks.map(\.kind), [.paragraph, .richText])
        guard let richText = blocks.last else {
            return XCTFail("Expected a readable preformatted block")
        }
        XCTAssertFalse(richText.text.contains("Copy"))
        XCTAssertTrue(richText.text.contains("This isn't surprising,\n这并不奇怪,"))
        XCTAssertTrue(richText.text.contains("curriculum\n基础的、强制性的高中课程"))

        let cleaned = SpeechContentCleaner.cleanBlocks(blocks)
        XCTAssertEqual(cleaned.map(\.kind), [.paragraph, .richText])
        XCTAssertTrue(cleaned.last?.text.contains("considering the context,\n考虑到上下文,") == true)
        XCTAssertFalse(cleaned.last?.text.contains("    ") == true)

        let requests = SpeechLanguageRouter.utteranceRequests(for: blocks)
        let requestText = requests.map(\.text).joined(separator: "\n")
        for line in [
            "This isn't surprising",
            "considering",
            "the basic mandatory high school curriculum",
            "leaves students with",
            "a poor understanding of",
            "the vast academic possibilities",
            "that await them in college",
            "这并不奇怪",
            "考虑到上下文",
            "基础的、强制性的高中课程",
            "使学生留下",
            "对……缺乏充分了解",
            "大量的学术可能性",
            "他们进入大学后将会面对的",
        ] {
            XCTAssertTrue(requestText.contains(line), "Missing readable line: \(line)")
        }

        let richRequests = requests.filter { $0.sourceLocator == richText.sourceLocator }
        XCTAssertGreaterThan(richRequests.count, 1)
        XCTAssertEqual(Set(richRequests.compactMap(\.sourceLocator)).count, 1)
        XCTAssertTrue(richRequests.contains { $0.languageRole == .english })
        XCTAssertTrue(richRequests.contains { $0.languageRole == .chinese })
    }

    func testPreformattedMachineContentRemainsSkippedAcrossSupportedSignals() async {
        let page = ChatGPTResponsePageHarness()
        page.load("""
        <div data-message-author-role="assistant" data-message-id="reply-machine-preformatted">
          <pre><code data-language="swift">func greet(name: String) {
            print("Hello \\(name)")
          }</code></pre>
          <pre><code class="language-javascript">const value = 1;
            console.log(value);</code></pre>
          <pre><code class="language-python">def foo():
            return 1</code></pre>
          <pre><code class="language-shell">$ git status
            $ git log --oneline</code></pre>
          <pre><code class="language-json">{
            "status": "ok",
            "count": 3
          }</code></pre>
          <pre><code class="language-text">Traceback (most recent call last):
            at Foo.bar
          Exception: synthetic failure</code></pre>
          <pre><code class="language-text">diff --git a/a.swift b/a.swift
          --- a/a.swift
          +++ b/a.swift
          @@ -1 +1 @@</code></pre>
        </div>
        """)
        await page.settle()

        let blocks = await page.extract()?.blocks ?? []
        XCTAssertEqual(blocks.count, 7)
        XCTAssertTrue(blocks.allSatisfy { $0.kind == .code })
        XCTAssertTrue(SpeechContentCleaner.cleanBlocks(blocks).isEmpty)
    }

    func testAmbiguousPreformattedProseAndInlineCodeRemainReadable() async {
        let page = ChatGPTResponsePageHarness()
        page.load("""
        <div data-message-author-role="assistant" data-message-id="reply-ambiguous-prose">
          <pre><code class="language-text"><div class="cm-line">[Important] This sentence matters.</div>
            <div class="cm-line">A = B because the two sides are equal.</div>
            <div class="cm-line">if you consider the context, the answer changes.</div>
          </code></pre>
          <p>The <code>considering</code> phrase modifies the whole clause.</p>
        </div>
        """)
        await page.settle()

        let blocks = await page.extract()?.blocks ?? []
        XCTAssertEqual(blocks.map(\.kind), [.richText, .paragraph])
        let requests = SpeechLanguageRouter.utteranceRequests(for: blocks)
        XCTAssertTrue(requests.contains { $0.text.contains("This sentence matters") })
        XCTAssertTrue(requests.contains { $0.text.contains("A = B") })
        XCTAssertTrue(requests.contains { $0.text.contains("if you consider") })
        XCTAssertTrue(requests.contains { $0.text.contains("considering") })
    }

    func testLongParagraphIsSplitWithoutSilentTextLoss() async {
        let page = ChatGPTResponsePageHarness()
        let words = (0..<1000).map { "word\($0)" }.joined(separator: " ")
        page.load("""
        <div data-message-author-role="assistant" data-message-id="reply-long">
          <p>START \(words) END</p>
        </div>
        """)
        await page.settle()

        let payload = await page.extract()
        let blocks = payload?.blocks ?? []
        XCTAssertGreaterThan(blocks.count, 1)
        XCTAssertTrue(blocks.allSatisfy { $0.text.count <= 4000 })
        let joined = blocks.map(\.text).joined(separator: " ")
        XCTAssertTrue(joined.contains("START"))
        XCTAssertTrue(joined.contains("word999"))
        XCTAssertTrue(joined.contains("END"))
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
