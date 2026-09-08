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

    func replaceLatestAssistantNode() async -> Bool {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(
                """
                (() => {
                  const original = document.querySelector('[data-message-id="reply-latest"]');
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

    func testNoAssistantMessageProducesEmptyExtraction() async {
        let page = ChatGPTResponsePageHarness()
        page.load("<div data-message-author-role=\"user\"><p>User text</p></div>")
        await page.settle()

        let payload = await page.extract()
        XCTAssertNil(payload)
    }
}
