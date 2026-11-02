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

    func previewSnapshot() async -> ChatGPTResponsePreviewSnapshot? {
        await withCheckedContinuation { continuation in
            bridge.previewLatestAssistantResponse { snapshot in
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

    // MARK: Notification preview projection (one-shot, best-effort)

    /// N1-1/N1-2/N1-3: the latest completed assistant response produces
    /// bounded plain text that excludes prompt/user/composer/action content,
    /// with whitespace normalized to readable single spacing.
    func testPreviewSnapshotReturnsBoundedPlainTextFromLatestAssistantResponse() async throws {
        let page = ChatGPTResponsePageHarness()
        page.load("""
        <div data-message-author-role="assistant" data-message-id="earlier-reply">
          <p>Earlier assistant response.</p>
        </div>
        <section data-message-author-role="assistant" data-message-id="latest-reply">
          <p>Line one
             and   line two.</p>
          <ul><li>Bullet item</li></ul>
          <div role="toolbar"><button id="copy">Copy</button></div>
          <button id="regen" aria-label="Regenerate">Regenerate</button>
          <div aria-hidden="true"><p>Hidden helper text</p></div>
          <style>.x { color: red }</style>
        </section>
        <div data-message-author-role="user"><p>Please summarise the report.</p></div>
        <div><textarea id="composer">Draft prompt text</textarea></div>
        """)
        let ready = await page.waitForDocumentReady()
        XCTAssertTrue(ready)

        let previewValue = await page.previewSnapshot()
        let preview = try XCTUnwrap(previewValue)
        XCTAssertEqual(preview.generating, false)
        let text = try XCTUnwrap(preview.previewText)
        XCTAssertTrue(text.contains("Line one and line two."), "preview: \(text)")
        XCTAssertTrue(text.contains("Bullet item"))
        // Only the latest assistant response is projected.
        XCTAssertFalse(text.contains("Earlier assistant response."))
        // Prompt/user, composer, action, hidden and style content excluded.
        XCTAssertFalse(text.contains("Please summarise the report."))
        XCTAssertFalse(text.contains("Draft prompt text"))
        XCTAssertFalse(text.contains("Copy"))
        XCTAssertFalse(text.contains("Regenerate"))
        XCTAssertFalse(text.contains("Hidden helper text"))
        XCTAssertFalse(text.contains("color: red"))
    }

    /// Excluded descendants are removed from allowed content nodes, while
    /// nested selected blocks contribute their text only once.
    func testPreviewSanitizesExcludedDescendantsAndDeduplicatesNestedBlocks() async throws {
        let page = ChatGPTResponsePageHarness()
        page.load("""
        <section data-message-author-role="assistant" data-message-id="sanitized-preview">
          <p>Answer <button>Copy button secret</button> remains.</p>
          <p>Answer <span role="button">Copy role secret</span> remains.</p>
          <p>Answer <span aria-hidden="true">Hidden helper secret</span> remains.</p>
          <p>Answer <span style="display:none">CSS hidden secret</span> remains.</p>
          <p>Answer <span role="toolbar">Toolbar secret</span> remains.</p>
          <p>Answer <span data-testid="response-action-toolbar">Action secret</span> remains.</p>
          <ol><li><p>Nested list item.</p></li></ol>
          <blockquote><p>Nested quoted paragraph.</p></blockquote>
          <pre><code>let answer = 42</code></pre>
          <p>Math <span role="math">x^2 + y^2</span> remains readable.</p>
          <p>Legitimate final paragraph.</p>
        </section>
        <div data-message-author-role="user"><p>User prompt secret.</p></div>
        """)
        let ready = await page.waitForDocumentReady()
        XCTAssertTrue(ready)

        let previewValue = await page.previewSnapshot()
        let preview = try XCTUnwrap(previewValue)
        let text = try XCTUnwrap(preview.previewText)

        for excluded in [
            "Copy button secret",
            "Copy role secret",
            "Hidden helper secret",
            "CSS hidden secret",
            "Toolbar secret",
            "Action secret",
            "User prompt secret"
        ] {
            XCTAssertFalse(text.contains(excluded), "excluded preview text leaked: \(excluded)")
        }
        XCTAssertEqual(text.components(separatedBy: "Nested list item.").count - 1, 1)
        XCTAssertEqual(text.components(separatedBy: "Nested quoted paragraph.").count - 1, 1)
        XCTAssertTrue(text.contains("let answer = 42"))
        XCTAssertTrue(text.contains("x^2 + y^2"))
        XCTAssertTrue(text.contains("Legitimate final paragraph."))
        XCTAssertTrue(text.contains("Answer remains."))
    }

    /// N1-3: pathological whitespace inside the selected content collapses
    /// to readable single spacing, and Unicode is preserved safely.
    func testPreviewSnapshotNormalizesWhitespaceAndPreservesUnicode() async throws {
        let page = ChatGPTResponsePageHarness()
        page.load("""
        <div data-message-author-role="assistant" data-message-id="unicode-reply">
          <p> café — “ok” 😀 \u{00A0}\u{00A0} naïve </p>
        </div>
        """)
        let ready = await page.waitForDocumentReady()
        XCTAssertTrue(ready)

        let previewValue = await page.previewSnapshot()
        let preview = try XCTUnwrap(previewValue)
        let text = try XCTUnwrap(preview.previewText)
        XCTAssertTrue(text.contains("café — “ok” 😀"))
        XCTAssertTrue(text.contains("naïve"))
        XCTAssertFalse(text.contains("  "), "double spacing must collapse: \(text)")
    }

    /// N1-4: the gathered preview window is bounded before crossing the
    /// native bridge.
    func testPreviewSnapshotIsBoundedToTheGatherLimit() async throws {
        let page = ChatGPTResponsePageHarness()
        page.load("""
        <div data-message-author-role="assistant" data-message-id="long-reply">
          <p>\(String(repeating: "word ", count: 400))</p>
        </div>
        """)
        let ready = await page.waitForDocumentReady()
        XCTAssertTrue(ready)

        let previewValue = await page.previewSnapshot()
        let preview = try XCTUnwrap(previewValue)
        let text = try XCTUnwrap(preview.previewText)
        XCTAssertLessThanOrEqual(text.count, 600)
    }

    /// N1-5: no trustworthy preview while generating or without an assistant
    /// root — the notification must fall back to the generic body.
    func testPreviewSnapshotAbsentWhileGeneratingOrWithoutAssistantRoot() async throws {
        let generatingPage = ChatGPTResponsePageHarness()
        generatingPage.load("""
        <div data-message-author-role="assistant" data-message-id="generating-reply">
          <p>Partial response so far.</p>
        </div>
        <button data-testid="stop-button">Stop</button>
        """)
        let generatingReady = await generatingPage.waitForDocumentReady()
        XCTAssertTrue(generatingReady)
        let generatingPreview = await generatingPage.previewSnapshot()
        XCTAssertNil(generatingPreview, "generating state must not admit a trusted preview")

        let emptyPage = ChatGPTResponsePageHarness()
        emptyPage.load("<div><p>No conversation here.</p></div>")
        let emptyReady = await emptyPage.waitForDocumentReady()
        XCTAssertTrue(emptyReady)
        let emptyPreview = await emptyPage.previewSnapshot()
        let noRootSnapshot = try XCTUnwrap(emptyPreview)
        XCTAssertNil(noRootSnapshot.previewText)
    }

    /// N1-7: the ordinary status snapshot remains body-free — the preview
    /// payload cannot leak response text through the status contract.
    func testStatusSnapshotRemainsBodyFreeAlongsidePreviewAPI() async throws {
        let page = ChatGPTResponsePageHarness()
        page.load("""
        <div data-message-author-role="assistant" data-message-id="status-reply">
          <p>Status must stay metadata only.</p>
        </div>
        """)
        let ready = await page.waitForDocumentReady()
        XCTAssertTrue(ready)

        let statusValue = await page.snapshotStatus()
        let status = try XCTUnwrap(statusValue)
        XCTAssertEqual(status.responseIdentity?.rawValue, "message:status-reply")
        // The status snapshot type exposes no text payload by construction;
        // assert its payload stays identity/status-only.
        XCTAssertEqual(
            ChatGPTResponseBridge.parseResponseStatusSnapshot([
                "version": 1,
                "documentToken": status.documentToken,
                "responseIdentity": status.responseIdentity?.rawValue,
                "generating": false,
                "preview": "would-be response body text"
            ]),
            ChatGPTResponseStatusSnapshot(
                documentToken: status.documentToken,
                responseIdentity: status.responseIdentity,
                generating: false
            )
        )
    }

}
