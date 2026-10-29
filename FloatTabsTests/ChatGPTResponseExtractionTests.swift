import WebKit
import XCTest
@testable import FloatTabs

@MainActor
private final class TrustedInteractionCallbackRecorder {
    var count = 0
}

@MainActor
private final class ChatGPTResponsePageHarness {
    let webView: WKWebView
    let bridge: ChatGPTResponseBridge
    private let trustedInteractionRecorder: TrustedInteractionCallbackRecorder

    var trustedInteractionCallbackCount: Int {
        trustedInteractionRecorder.count
    }

    init() {
        let configuration = WKWebViewConfiguration()
        let recorder = TrustedInteractionCallbackRecorder()
        let bridge = ChatGPTResponseBridge(
            slotID: UUID(),
            onTrustedInteraction: { _, _, _ in
                recorder.count += 1
            }
        )
        bridge.install(into: configuration.userContentController)
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
        bridge.attach(to: webView)
        self.webView = webView
        self.bridge = bridge
        self.trustedInteractionRecorder = recorder
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

    func waitForDocumentReady() async -> Bool {
        for _ in 0..<40 {
            if await snapshotStatus() != nil {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    func waitForDocumentChange(after documentToken: String) async -> ChatGPTResponseStatusSnapshot? {
        for _ in 0..<100 {
            if let snapshot = await snapshotStatus(),
               snapshot.documentToken != documentToken {
                return snapshot
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return nil
    }

    func snapshotStatus() async -> ChatGPTResponseStatusSnapshot? {
        await withCheckedContinuation { continuation in
            bridge.snapshotLatestResponseStatus { snapshot in
                continuation.resume(returning: snapshot)
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

    func evaluatePageWorldReturningBool(_ script: String) async -> Bool {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(script) { result, _ in
                continuation.resume(returning: result as? Bool ?? false)
            }
        }
    }

    func classifyTrustedAssistantPointerTarget(selector: String) async -> String? {
        guard let data = try? JSONEncoder().encode(selector),
              let selectorJSON = String(data: data, encoding: .utf8) else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(
                "globalThis.__floatTabsDebugClassifyAssistantPointerTargetV3?.(\(selectorJSON)) ?? null",
                in: nil,
                in: ChatGPTResponseExtraction.contentWorld,
                completionHandler: { result in
                    switch result {
                    case let .success(value):
                        continuation.resume(returning: value as? String)
                    case .failure:
                        continuation.resume(returning: nil)
                    }
                }
            )
        }
    }
}

@MainActor
final class ChatGPTResponseExtractionTests: XCTestCase {
    func testInjectedScriptRetainsIdentityStatusAndTrustedInteractionContract() {
        let source = ChatGPTResponseExtraction.scriptSource

        for preserved in [
            "__floatTabsChatGPTResponseIdentitySnapshotV1",
            "DOMContentLoaded",
            "event: \"documentReady\"",
            "event: \"manualScroll\"",
            "event: \"trustedInteraction\"",
            "latestResponseIdentity",
            "latestResponseComplete",
            "event.isTrusted",
            "pointerdown"
        ] {
            XCTAssertTrue(source.contains(preserved), "preserved contract missing: \(preserved)")
        }
    }

    func testTrustedPointerClassifierUsesAssistantStructureNotControlLabels() async {
        let page = ChatGPTResponsePageHarness()
        page.load("""
        <section data-message-author-role="assistant" data-message-id="reply-pointer">
          <p id="response-body">Assistant body.</p>
          <div role="toolbar"><button id="copy">Copy</button></div>
          <a id="response-link" href="/details">Open response details</a>
        </section>
        <aside><button id="sidebar">Copy</button></aside>
        <div><textarea id="composer"></textarea><button id="send">Send</button></div>
        <article data-testid="conversation-turn-assistant">
          <div data-message-author-role="assistant"></div>
          <div role="toolbar"><button id="article-assistant-copy">Copy</button></div>
        </article>
        <article data-testid="conversation-turn-user">
          <div data-message-author-role="user"></div>
          <button id="article-user-copy">Copy</button>
        </article>
        """)
        await page.settle()

        let responseBodyClassification =
            await page.classifyTrustedAssistantPointerTarget(selector: "#response-body")
        let copyClassification =
            await page.classifyTrustedAssistantPointerTarget(selector: "#copy")
        let responseLinkClassification =
            await page.classifyTrustedAssistantPointerTarget(selector: "#response-link")
        let sidebarClassification =
            await page.classifyTrustedAssistantPointerTarget(selector: "#sidebar")
        let composerClassification =
            await page.classifyTrustedAssistantPointerTarget(selector: "#composer")
        let sendClassification =
            await page.classifyTrustedAssistantPointerTarget(selector: "#send")
        let articleAssistantClassification =
            await page.classifyTrustedAssistantPointerTarget(selector: "#article-assistant-copy")
        let articleUserClassification =
            await page.classifyTrustedAssistantPointerTarget(selector: "#article-user-copy")

        XCTAssertEqual(responseBodyClassification, "assistantPointer")
        XCTAssertEqual(copyClassification, "assistantPointer")
        XCTAssertEqual(responseLinkClassification, "assistantPointer")
        XCTAssertNil(sidebarClassification)
        XCTAssertNil(composerClassification)
        XCTAssertNil(sendClassification)
        XCTAssertEqual(articleAssistantClassification, "assistantPointer")
        XCTAssertNil(articleUserClassification)
    }

    func testSyntheticPointerdownDoesNotReachTrustedInteractionCallback() async {
        let page = ChatGPTResponsePageHarness()
        page.load("""
        <section data-message-author-role="assistant" data-message-id="reply-synthetic-pointer">
          <p>Assistant response.</p>
          <button id="copy">Copy</button>
        </section>
        """)
        await page.settle()

        let documentReady = await page.waitForDocumentReady()
        let dispatched = await page.evaluatePageWorldReturningBool("""
        (() => {
          const target = document.querySelector('#copy');
          if (!target) return false;
          target.dispatchEvent(new PointerEvent('pointerdown', {
            bubbles: true,
            composed: true,
            clientX: 10,
            clientY: 10
          }));
          return true;
        })()
        """)
        XCTAssertTrue(documentReady)
        XCTAssertTrue(dispatched)
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(page.trustedInteractionCallbackCount, 0)
    }

    func testCanonicalIdentityIsStableAcrossRerenderAndDocumentReplacement() async throws {
        let page = ChatGPTResponsePageHarness()
        page.load("""
        <div data-message-author-role="assistant" data-message-id="canonical-id">
          <p>Latest response.</p>
        </div>
        """)
        let firstReady = await page.waitForDocumentReady()
        XCTAssertTrue(firstReady)

        let firstSnapshot = await page.snapshotStatus()
        let first = try XCTUnwrap(firstSnapshot)
        XCTAssertEqual(first.responseIdentity?.rawValue, "message:canonical-id")
        let replaced = await page.replaceLatestAssistantNode(id: "canonical-id")
        XCTAssertTrue(replaced)
        let rerenderedSnapshot = await page.snapshotStatus()
        let rerendered = try XCTUnwrap(rerenderedSnapshot)
        XCTAssertEqual(rerendered.responseIdentity, first.responseIdentity)

        page.load("""
        <div data-message-author-role="assistant" data-message-id="canonical-id">
          <p>Reloaded response.</p>
        </div>
        """)
        let reloadedSnapshot = await page.waitForDocumentChange(after: first.documentToken)
        let reloaded = try XCTUnwrap(reloadedSnapshot)
        XCTAssertNotEqual(reloaded.documentToken, first.documentToken)
        XCTAssertEqual(reloaded.responseIdentity, first.responseIdentity)
    }
}
