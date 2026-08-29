import AppKit
import WebKit
import XCTest
@testable import FloatTabs

@MainActor
final class WebFocusAdapterTests: XCTestCase {
    private var retainedWindows: [NSWindow] = []

    private final class FutureAdapter: WebSiteAdapter {
        let identifier = "future"

        func matches(url: URL?, webView: WKWebView) async -> Bool { true }
        func togglePrimaryFocus(in webView: WKWebView) async throws -> WebFocusTarget { .input }
        func focusInput(in webView: WKWebView) async throws {}
        func focusPage(in webView: WKWebView) async throws {}
        func currentFocus(in webView: WKWebView) async throws -> WebFocusTarget { .unavailable }
    }

    func testChatGPTAdapterPrefersComposerOverSearchAndRestoresCaret() async throws {
        let webView = makeWebView()
        load(
            """
            <main style="min-height: 500px;">
                <input role="textbox" type="search" aria-label="Search conversations">
                <textarea aria-label="Message ChatGPT">existing text</textarea>
                <article style="height: 800px;">Conversation</article>
            </main>
            """,
            in: webView
        )
        await settle(webView)

        let adapter = ChatGPTAdapter()
        let matchesChatGPT = await adapter.matches(
            url: URL(string: "https://chatgpt.com/c/example"),
            webView: webView
        )
        XCTAssertTrue(matchesChatGPT)

        try await adapter.focusInput(in: webView)
        let firstFocusedLabel = await stringValue(
            "document.activeElement.getAttribute('aria-label')",
            in: webView
        )
        let firstSelectionEnd = await numberValue(
            "document.activeElement.selectionEnd",
            in: webView
        )
        XCTAssertEqual(firstFocusedLabel, "Message ChatGPT")
        XCTAssertEqual(firstSelectionEnd, 13)

        let pageTarget = try await adapter.togglePrimaryFocus(in: webView)
        XCTAssertEqual(pageTarget, .page)
        let pageTag = await stringValue(
            "document.activeElement.tagName.toLowerCase()",
            in: webView
        )
        XCTAssertTrue(["main", "body"].contains(pageTag))
        let pageStillOwnsComposerFocus = await boolValue(
            "document.activeElement.matches('textarea, [contenteditable=\"true\"], [role=\"textbox\"]')",
            in: webView
        )
        XCTAssertFalse(pageStillOwnsComposerFocus)

        let inputTarget = try await adapter.togglePrimaryFocus(in: webView)
        XCTAssertEqual(inputTarget, .input)
        let secondFocusedLabel = await stringValue(
            "document.activeElement.getAttribute('aria-label')",
            in: webView
        )
        let secondSelectionEnd = await numberValue(
            "document.activeElement.selectionEnd",
            in: webView
        )
        let temporaryTabIndex = await stringValue(
            "document.querySelector('[data-floattabs-focus-tabindex]')",
            in: webView
        )
        XCTAssertEqual(secondFocusedLabel, "Message ChatGPT")
        XCTAssertEqual(secondSelectionEnd, 13)
        XCTAssertNil(temporaryTabIndex)
    }

    func testChatGPTContentEditableComposerWorksAndDoesNotClearText() async throws {
        let webView = makeWebView()
        load(
            """
            <main style="min-height: 500px;">
                <div role="textbox" contenteditable="true" aria-label="Ask ChatGPT">keep this</div>
            </main>
            """,
            in: webView
        )
        await settle(webView)

        let adapter = ChatGPTAdapter()
        try await adapter.focusInput(in: webView)

        let textContent = await stringValue("document.activeElement.textContent", in: webView)
        let selectionLabel = await stringValue(
            "document.activeElement.getAttribute('aria-label')",
            in: webView
        )
        XCTAssertEqual(textContent, "keep this")
        XCTAssertEqual(selectionLabel, "Ask ChatGPT")
    }

    func testPageFocusTargetsNestedScrollableConversationContainer() async throws {
        let webView = makeWebView()
        load(
            """
            <main style="height: 500px;">
                <textarea aria-label="Message ChatGPT">existing text</textarea>
                <div id="conversation-scroll" style="height: 160px; overflow-y: auto;">
                    <article style="height: 1200px;">Conversation</article>
                </div>
            </main>
            """,
            in: webView
        )
        await settle(webView)

        let adapter = ChatGPTAdapter()
        try await adapter.focusInput(in: webView)
        let pageTarget = try await adapter.togglePrimaryFocus(in: webView)

        XCTAssertEqual(pageTarget, .page)
        let focusedID = await stringValue(
            "document.activeElement.id",
            in: webView
        )
        XCTAssertEqual(focusedID, "conversation-scroll")
    }

    func testPageScrollMovesCachedNestedConversationContainer() async throws {
        let webView = makeWebView()
        load(
            """
            <main style="height: 500px;">
                <textarea aria-label="Message ChatGPT">existing text</textarea>
                <div id="conversation-scroll" style="height: 160px; overflow-y: auto;">
                    <article style="height: 1200px;">Conversation</article>
                </div>
            </main>
            """,
            in: webView
        )
        await settle(webView)

        _ = try await WebFocusDOM.evaluate(
            WebFocusDOM.pageScrollScript(lines: 40, direction: 1),
            in: webView
        )
        let firstScrollTop = await numberValue(
            "document.getElementById('conversation-scroll').scrollTop",
            in: webView
        )
        _ = try await WebFocusDOM.evaluate(
            WebFocusDOM.pageScrollScript(lines: 40, direction: 1),
            in: webView
        )
        let secondScrollTop = await numberValue(
            "document.getElementById('conversation-scroll').scrollTop",
            in: webView
        )

        XCTAssertGreaterThan(firstScrollTop ?? 0, 0)
        XCTAssertLessThanOrEqual(firstScrollTop ?? Int.max, 88)
        XCTAssertGreaterThan(secondScrollTop ?? 0, firstScrollTop ?? 0)
    }

    func testGenericAdapterTogglesOnOrdinaryWebsite() async throws {
        let webView = makeWebView()
        load(
            """
            <main style="min-height: 500px;">
                <textarea placeholder="Write a comment">unchanged</textarea>
                <article style="height: 800px;">Content</article>
            </main>
            """,
            in: webView
        )
        await settle(webView)

        let adapter = GenericWebAdapter()
        let initialTarget = try await adapter.currentFocus(in: webView)
        let inputTarget = try await adapter.togglePrimaryFocus(in: webView)
        let pageTarget = try await adapter.togglePrimaryFocus(in: webView)
        let activeTag = await stringValue(
            "document.activeElement.tagName.toLowerCase()",
            in: webView
        )
        let textareaValue = await stringValue(
            "document.querySelector('textarea').value",
            in: webView
        )
        XCTAssertEqual(initialTarget, .page)
        XCTAssertEqual(inputTarget, .input)
        XCTAssertEqual(pageTarget, .page)
        XCTAssertTrue(["main", "body"].contains(activeTag))
        XCTAssertEqual(textareaValue, "unchanged")
    }

    func testRouterFallsBackToGenericAndRecordsUnavailableInputFailure() async throws {
        let webView = makeWebView()
        load(
            "<main style=\"min-height: 500px;\">No composer</main>",
            baseURL: URL(string: "https://example.com/"),
            in: webView
        )
        await settle(webView)

        let router = WebFocusRouter()
        var transitions: [WebFocusTransition] = []
        router.onTransition = { transitions.append($0) }
        router.setCurrentWebView(webView)

        let transition = await router.togglePrimaryFocus()

        XCTAssertEqual(router.currentWebsiteIdentifier, "generic")
        XCTAssertFalse(transition.succeeded)
        XCTAssertEqual(transition.to, .input)
        XCTAssertEqual(transitions, [transition])
        XCTAssertNotNil(transition.failureReason)
    }

    func testRouterCanInitializeInputFocusForPresentation() async throws {
        let webView = makeWebView()
        load(
            """
            <main style="min-height: 500px;">
                <textarea aria-label="Message ChatGPT">existing text</textarea>
                <article style="height: 800px;">Conversation</article>
            </main>
            """,
            in: webView
        )
        await settle(webView)

        let router = WebFocusRouter()
        router.setCurrentWebView(webView)
        let focused = await router.focusInputForPresentation()
        let focusedLabel = await stringValue(
            "document.activeElement.getAttribute('aria-label')",
            in: webView
        )

        XCTAssertTrue(focused)
        XCTAssertEqual(router.currentTarget, .input)
        XCTAssertEqual(focusedLabel, "Message ChatGPT")
    }

    func testRegistryUsesChatGPTBeforeGenericFallback() async {
        let webView = makeWebView()
        let registry = WebSiteAdapterRegistry()

        let chatGPT = await registry.adapter(
            for: URL(string: "https://chatgpt.com/"),
            webView: webView
        )
        let generic = await registry.adapter(
            for: URL(string: "https://example.com/"),
            webView: webView
        )

        XCTAssertEqual(chatGPT.identifier, "chatgpt")
        XCTAssertEqual(generic.identifier, "generic")

        registry.register(FutureAdapter())
        let future = await registry.adapter(
            for: URL(string: "https://example.com/"),
            webView: webView
        )
        XCTAssertEqual(future.identifier, "future")
    }

    private func makeWebView() -> WKWebView {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = webView
        window.orderFrontRegardless()
        retainedWindows.append(window)
        return webView
    }

    private func load(
        _ body: String,
        baseURL: URL? = URL(string: "https://chatgpt.com/"),
        in webView: WKWebView
    ) {
        webView.loadHTMLString(
            "<!doctype html><html><body>\(body)</body></html>",
            baseURL: baseURL
        )
    }

    private func settle(_ webView: WKWebView) async {
        for _ in 0..<50 {
            if !webView.isLoading {
                try? await Task.sleep(nanoseconds: 150_000_000)
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func stringValue(_ script: String, in webView: WKWebView) async -> String? {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(script) { value, _ in
                continuation.resume(returning: value as? String)
            }
        }
    }

    private func numberValue(_ script: String, in webView: WKWebView) async -> Int? {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(script) { value, _ in
                continuation.resume(returning: (value as? NSNumber)?.intValue)
            }
        }
    }

    private func boolValue(_ script: String, in webView: WKWebView) async -> Bool {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(script) { value, _ in
                continuation.resume(returning: (value as? NSNumber)?.boolValue ?? false)
            }
        }
    }
}
