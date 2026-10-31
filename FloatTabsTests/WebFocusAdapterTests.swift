import AppKit
import WebKit
import XCTest
@testable import FloatTabs

@MainActor
final class WebFocusAdapterTests: XCTestCase {
    private var retainedWindows: [NSWindow] = []

    /// Test-only WebKit fixture: the production liveness entry point reads
    /// WKWebView.url as its supported-site admission guard. Keep that guard
    /// real while removing runner timing from this recovery test.
    private final class DeterministicChatGPTURLWebView: WKWebView {
        private let deterministicURL: URL

        init(deterministicURL: URL) {
            self.deterministicURL = deterministicURL
            super.init(
                frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                configuration: WKWebViewConfiguration()
            )
        }

        required init?(coder: NSCoder) {
            fatalError("DeterministicChatGPTURLWebView is test-only")
        }

        override var url: URL? {
            deterministicURL
        }
    }

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

    func testRouterPreservesActiveChatGPTMessageEditorForPresentation() async throws {
        let webView = makeWebView()
        load(
            """
            <main style="min-height: 500px;">
                <textarea aria-label="Message ChatGPT"></textarea>
                <article style="height: 800px;">
                    <textarea aria-label="Edit message">draft to revise</textarea>
                </article>
            </main>
            """,
            in: webView
        )
        await settle(webView)

        _ = await boolValue(
            "(() => { const editor = document.querySelector('article textarea'); editor.focus(); return document.activeElement === editor; })()",
            in: webView
        )

        let router = WebFocusRouter()
        router.setCurrentWebView(webView)
        let focused = await router.focusInputForPresentation()
        let focusedLabel = await stringValue(
            "document.activeElement.getAttribute('aria-label')",
            in: webView
        )
        let focusedValue = await stringValue(
            "document.activeElement.value",
            in: webView
        )

        XCTAssertTrue(focused)
        XCTAssertEqual(router.currentTarget, .input)
        XCTAssertEqual(focusedLabel, "Edit message")
        XCTAssertEqual(focusedValue, "draft to revise")
    }

    func testVoiceFocusRestoresTheInputAndCaretCapturedBeforePresentation() async throws {
        let webView = makeWebView()
        load(
            """
            <main style="min-height: 500px;">
                <textarea aria-label="Message ChatGPT">bottom draft</textarea>
                <article style="height: 800px;">
                    <textarea aria-label="Edit message">edited response</textarea>
                </article>
            </main>
            """,
            in: webView
        )
        await settle(webView)

        let captured = await boolValue(
            """
            (() => {
                const composer = document.querySelector('textarea[aria-label="Message ChatGPT"]');
                composer.focus();
                composer.setSelectionRange(3, 3);
                return document.activeElement === composer;
            })()
            """,
            in: webView
        )
        XCTAssertTrue(captured)

        let router = WebFocusRouter()
        router.setCurrentWebView(webView)
        let marked = await router.captureInputTargetForExternalVoice()
        XCTAssertTrue(marked.succeeded)

        // Simulate WebKit restoring the other editor while the FloatTabs
        // window becomes key. The voice restore must use the pre-presentation
        // marker, not this newer document.activeElement.
        _ = await boolValue(
            """
            (() => {
                const editor = document.querySelector('textarea[aria-label="Edit message"]');
                editor.focus();
                return document.activeElement === editor;
            })()
            """,
            in: webView
        )

        let focused = await router.focusInputForPresentation(
            preservingCapturedTarget: true
        )
        let focusedLabel = await stringValue(
            "document.activeElement.getAttribute('aria-label')",
            in: webView
        )
        let selectionStart = await numberValue(
            "document.activeElement.selectionStart",
            in: webView
        )
        let markerCount = await numberValue(
            "document.querySelectorAll('[data-floattabs-voice-target]').length",
            in: webView
        )

        XCTAssertTrue(focused)
        XCTAssertEqual(focusedLabel, "Message ChatGPT")
        XCTAssertEqual(selectionStart, 3)
        XCTAssertEqual(markerCount, 0)
    }

    func testVoiceFocusRestoresCapturedChatGPTMessageEditorAndSelection() async throws {
        let webView = makeWebView()
        load(
            """
            <main style="min-height: 500px;">
                <textarea aria-label="Message ChatGPT">bottom draft</textarea>
                <article style="height: 800px;">
                    <textarea aria-label="Edit message">edited response</textarea>
                </article>
            </main>
            """,
            in: webView
        )
        await settle(webView)

        let editorPrepared = await boolValue(
            """
            (() => {
                const editor = document.querySelector('textarea[aria-label="Edit message"]');
                window.__originalVoiceEditor = editor;
                editor.focus();
                editor.setSelectionRange(2, 5);
                return document.activeElement === editor
                    && editor.selectionStart === 2
                    && editor.selectionEnd === 5;
            })()
            """,
            in: webView
        )
        XCTAssertTrue(editorPrepared)

        let router = WebFocusRouter()
        router.setCurrentWebView(webView)
        let captured = await router.captureInputTargetForExternalVoice()

        XCTAssertTrue(captured.succeeded)
        XCTAssertEqual(captured.kind, .messageEditor)
        XCTAssertEqual(captured.source, .captured)

        _ = await boolValue(
            "document.querySelector('textarea[aria-label=\"Message ChatGPT\"]').focus(); true",
            in: webView
        )

        let restored = await router.focusInputForPresentation(
            preservingCapturedTarget: true
        )
        let restoredEditor = await boolValue(
            "document.activeElement === window.__originalVoiceEditor",
            in: webView
        )
        let selectionStart = await numberValue(
            "document.activeElement.selectionStart",
            in: webView
        )
        let selectionEnd = await numberValue(
            "document.activeElement.selectionEnd",
            in: webView
        )

        XCTAssertTrue(restored)
        XCTAssertTrue(restoredEditor)
        XCTAssertEqual(selectionStart, 2)
        XCTAssertEqual(selectionEnd, 5)
    }

    func testVoiceFocusFallsBackToChatGPTComposerWhenActivationChangedToMessageEditor() async throws {
        let webView = makeWebView()
        load(
            """
            <main style="min-height: 500px;">
                <textarea aria-label="Message ChatGPT">bottom draft</textarea>
                <article style="height: 800px;">
                    <textarea aria-label="Edit message">edited response</textarea>
                </article>
            </main>
            """,
            in: webView
        )
        await settle(webView)

        let activationFocusedEditor = await boolValue(
            """
            (() => {
                const editor = document.querySelector('textarea[aria-label="Edit message"]');
                editor.focus();
                return document.activeElement === editor;
            })()
            """,
            in: webView
        )
        XCTAssertTrue(activationFocusedEditor)

        let router = WebFocusRouter()
        router.setCurrentWebView(webView)
        let focused = await router.focusInputForPresentation(
            preservingCapturedTarget: true
        )
        let focusedLabel = await stringValue(
            "document.activeElement.getAttribute('aria-label')",
            in: webView
        )

        XCTAssertTrue(focused)
        XCTAssertEqual(focusedLabel, "Message ChatGPT")
    }

    func testVoiceFocusDiagnosticsUseFixedOwnerAndTargetClassifications() async throws {
        let webView = makeWebView()
        load(
            """
            <main style="min-height: 500px;">
                <textarea aria-label="Message ChatGPT">bottom draft</textarea>
                <article style="height: 800px;">
                    <textarea aria-label="Edit message">edited response</textarea>
                </article>
            </main>
            """,
            in: webView
        )
        await settle(webView)

        _ = await boolValue(
            """
            (() => {
                const editor = document.querySelector('textarea[aria-label="Edit message"]');
                editor.focus();
                return document.activeElement === editor;
            })()
            """,
            in: webView
        )

        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        let router = WebFocusRouter(diagnostics: diagnostics)
        router.setCurrentWebView(webView)
        let trace = RuntimeDiagnosticTrace(root: "voice-focus-test")

        let focused = await router.focusInputForPresentation(
            preservingCapturedTarget: true,
            trace: trace
        )
        XCTAssertTrue(focused)

        let event = try XCTUnwrap(
            writer.events.last(where: { $0.event == "web_focus.presentation.completed" })
        )
        XCTAssertEqual(event.fields["focus_owner"], .string("external_voice"))
        XCTAssertEqual(event.fields["voice_target_kind"], .string("composer"))
        XCTAssertEqual(event.fields["voice_target_source"], .string("fallback_candidate"))
        XCTAssertFalse(event.fields.keys.contains("aria_label"))
        XCTAssertFalse(event.fields.keys.contains("text_content"))
    }

    func testRouterOnlyReportsInputReadyForCurrentDOMInput() async throws {
        let webView = makeWebView()
        load(
            """
            <main tabindex="-1" style="min-height: 500px;">
                <textarea aria-label="Message ChatGPT">existing text</textarea>
                <article style="height: 800px;">Conversation</article>
            </main>
            """,
            in: webView
        )
        await settle(webView)

        let router = WebFocusRouter()
        router.setCurrentWebView(webView)
        _ = try await ChatGPTAdapter().focusPage(in: webView)
        let pageReadyBeforeInput = await router.isInputFocusReady()
        XCTAssertFalse(pageReadyBeforeInput)

        let focused = await router.focusInputForPresentation()
        let inputReady = await router.isInputFocusReady()
        XCTAssertTrue(focused)
        XCTAssertTrue(inputReady)

        _ = try await ChatGPTAdapter().focusPage(in: webView)
        let pageReadyAfterInput = await router.isInputFocusReady()
        XCTAssertFalse(pageReadyAfterInput)
    }

    func testChatGPTAdapterRecognizesPlaintextOnlyComposer() async throws {
        let webView = makeWebView()
        load(
            """
            <main tabindex="-1" style="min-height: 500px;">
                <div contenteditable="plaintext-only"
                     role="textbox"
                     aria-label="Message ChatGPT"></div>
            </main>
            """,
            in: webView
        )
        await settle(webView)

        let adapter = ChatGPTAdapter()
        try await adapter.focusInput(in: webView)
        let target = try await adapter.currentFocus(in: webView)

        XCTAssertEqual(target, .input)
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

    private func makeWebView(deterministicURL: URL? = nil) -> WKWebView {
        let webView: WKWebView
        if let deterministicURL {
            webView = DeterministicChatGPTURLWebView(deterministicURL: deterministicURL)
        } else {
            webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        }
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

@MainActor
extension WebFocusAdapterTests {
    func testGeneratingPeriodicCrossWorldLivenessIsSuppressedButExplicitCaptureRuns() async throws {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        let webView = makeWebView()
        let slotID = UUID()
        let attentionCoordinator = WebAttentionCoordinator()
        attentionCoordinator.apply(.generationStarted, for: slotID)
        var evaluatedWorlds: [WebRuntimeLivenessWorld] = []
        let observer = SlotNavigationObserver(
            slotID: slotID,
            webView: webView,
            websiteMode: .desktop,
            onURLChange: { _, _ in },
            diagnostics: diagnostics,
            attentionStateQuery: { queriedSlotID in
                XCTAssertEqual(queriedSlotID, slotID)
                return attentionCoordinator.state(for: queriedSlotID)
            },
            crossWorldLivenessInterval: 300,
            livenessProbeEvaluator: { _, world in
                evaluatedWorlds.append(world)
                return .success(
                    readyState: "complete",
                    visibilityState: "visible",
                    latencyMilliseconds: 1
                )
            },
            responsivenessProbeEvaluator: { _, _ in .notRun() }
        )
        load("<main>Generating cross-world suppression</main>", in: webView)
        await settle(webView)

        await observer.captureCrossWorldLivenessOnce(source: .periodic)

        XCTAssertTrue(evaluatedWorlds.isEmpty)
        let suppressed = try XCTUnwrap(
            writer.events.last { $0.event == "web_runtime.cross_world_liveness_suppressed" }
        )
        XCTAssertEqual(suppressed.fields["slot_id"], .string(slotID.uuidString))
        XCTAssertEqual(suppressed.fields["reason"], .string("chatgpt_generating"))
        XCTAssertEqual(suppressed.fields["sample_source"], .string("periodic"))
        XCTAssertEqual(suppressed.fields["js_evaluation_started"], .bool(false))

        await observer.captureCrossWorldLivenessOnce()

        XCTAssertEqual(evaluatedWorlds, [.mainPage, .floatTabsIsolated])
        attentionCoordinator.apply(.generationFinished(userVisible: true), for: slotID)
        await observer.captureCrossWorldLivenessOnce(source: .periodic)
        XCTAssertEqual(
            evaluatedWorlds,
            [.mainPage, .floatTabsIsolated, .mainPage, .floatTabsIsolated]
        )
    }

    func testPeriodicCrossWorldLivenessRunsForIdleAndReadyAndSkipsNonChatGPT() async throws {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        let webView = makeWebView()
        let slotID = UUID()
        let attentionCoordinator = WebAttentionCoordinator()
        var evaluationCount = 0
        let observer = SlotNavigationObserver(
            slotID: slotID,
            webView: webView,
            websiteMode: .desktop,
            onURLChange: { _, _ in },
            diagnostics: diagnostics,
            attentionStateQuery: { queriedSlotID in
                attentionCoordinator.state(for: queriedSlotID)
            },
            crossWorldLivenessInterval: 300,
            livenessProbeEvaluator: { _, _ in
                evaluationCount += 1
                return .success(
                    readyState: "complete",
                    visibilityState: "visible",
                    latencyMilliseconds: 1
                )
            },
            responsivenessProbeEvaluator: { _, _ in .notRun() }
        )
        load("<main>Periodic cross-world sampling</main>", in: webView)
        await settle(webView)

        await observer.captureCrossWorldLivenessOnce(source: .periodic)
        XCTAssertEqual(evaluationCount, 2)

        attentionCoordinator.apply(.generationStarted, for: slotID)
        attentionCoordinator.apply(.generationFinished(userVisible: false), for: slotID)
        await observer.captureCrossWorldLivenessOnce(source: .periodic)
        XCTAssertEqual(evaluationCount, 4)

        let nonChatGPTWebView = makeWebView()
        let nonChatGPTSlotID = UUID()
        attentionCoordinator.apply(.generationStarted, for: nonChatGPTSlotID)
        let nonChatGPTObserver = SlotNavigationObserver(
            slotID: nonChatGPTSlotID,
            webView: nonChatGPTWebView,
            websiteMode: .desktop,
            onURLChange: { _, _ in },
            diagnostics: diagnostics,
            attentionStateQuery: { queriedSlotID in
                attentionCoordinator.state(for: queriedSlotID)
            },
            crossWorldLivenessInterval: 300,
            livenessProbeEvaluator: { _, _ in
                XCTFail("non-ChatGPT periodic sampling should not evaluate JavaScript")
                return .terminal(.failed, latencyMilliseconds: 0)
            }
        )
        load(
            "<main>Non-ChatGPT periodic sampling</main>",
            baseURL: URL(string: "https://example.com/"),
            in: nonChatGPTWebView
        )
        await settle(nonChatGPTWebView)
        await nonChatGPTObserver.captureCrossWorldLivenessOnce(source: .periodic)

        XCTAssertNil(
            writer.events.last { $0.event == "web_runtime.cross_world_liveness_suppressed" }
        )
    }

    func testRuntimeLivenessDistinguishesMainPageFromIsolatedWorld() async throws {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        let webView = makeWebView()
        let observer = SlotNavigationObserver(
            slotID: UUID(), webView: webView, websiteMode: .desktop,
            onURLChange: { _, _ in }, diagnostics: diagnostics,
            crossWorldLivenessInterval: 300,
            livenessProbeEvaluator: { _, world in
                world == .mainPage
                    ? .success(readyState: "complete", visibilityState: "visible", latencyMilliseconds: 1.25)
                    : .terminal(.timeout, latencyMilliseconds: 5_000)
            }
        )
        load("<main>Cross-world probe</main>", in: webView)
        await settle(webView)
        XCTAssertEqual(observer.currentNavigationDiagnosticFields["navigation_phase"], .string("finished"))

        await observer.captureCrossWorldLivenessOnce()

        let event = try XCTUnwrap(writer.events.last { $0.event == "web_runtime.cross_world_liveness" })
        XCTAssertEqual(event.fields["main_world_probe_outcome"], .string("success"))
        XCTAssertEqual(event.fields["isolated_world_probe_outcome"], .string("timeout"))
        XCTAssertEqual(event.fields["navigation_finished"], .bool(true))
        XCTAssertEqual(event.fields["post_finish_dual_timeout_count"], .integer(0))
        XCTAssertEqual(event.fields["web_process_resource_attribution"], .string("unavailable_public_api"))
        XCTAssertNotNil(event.fields["host_resident_size_bytes"])
        XCTAssertNil(event.fields["page_text"])
        XCTAssertNil(event.fields["prompt"])
        XCTAssertNil(event.fields["response_text"])
        XCTAssertNil(event.fields["document_token"])
        XCTAssertNil(writer.events.last { $0.event == "web_runtime.post_finish_stall_candidate" })
        XCTAssertNil(writer.events.last { $0.event == "web_runtime.post_finish_stall_detected" })
    }

    func testRuntimeResponsivenessDistinguishesSlowSuccessFromTimeoutWithoutPageContent() async throws {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        let webView = makeWebView()
        var responsivenessResults = [
            WebRuntimeResponsivenessProbeResult.success(
                probeLatencyMilliseconds: 2_812,
                eventLoopSchedulingLatencyMilliseconds: 1_247.5,
                frameCallbackOutcome: .sampled,
                frameCallbackLatencyMilliseconds: 1_530.25
            ),
            WebRuntimeResponsivenessProbeResult.terminal(
                .timeout,
                probeLatencyMilliseconds: 5_000
            )
        ]
        let observer = SlotNavigationObserver(
            slotID: UUID(), webView: webView, websiteMode: .desktop,
            onURLChange: { _, _ in }, diagnostics: diagnostics,
            crossWorldLivenessInterval: 300,
            livenessProbeEvaluator: { _, _ in
                .success(readyState: "complete", visibilityState: "visible", latencyMilliseconds: 2)
            },
            responsivenessProbeEvaluator: { _, shouldMeasureFrame in
                XCTAssertTrue(shouldMeasureFrame)
                return responsivenessResults.removeFirst()
            }
        )
        load("<main>CONTENT_SENTINEL sidebar button response</main>", in: webView)
        await settle(webView)

        await observer.captureCrossWorldLivenessOnce()
        await observer.captureCrossWorldLivenessOnce()

        let events = writer.events.filter { $0.event == "web_runtime.cross_world_liveness" }
        XCTAssertEqual(events.count, 2)
        let slowSuccess = events[0]
        XCTAssertEqual(slowSuccess.fields["main_world_probe_outcome"], .string("success"))
        XCTAssertEqual(slowSuccess.fields["main_world_responsiveness_probe_outcome"], .string("success"))
        XCTAssertEqual(slowSuccess.fields["main_world_responsiveness_probe_latency_ms"], .double(2_812))
        XCTAssertEqual(slowSuccess.fields["main_world_event_loop_schedule_latency_ms"], .double(1_247.5))
        XCTAssertEqual(slowSuccess.fields["main_world_frame_callback_outcome"], .string("sampled"))
        XCTAssertEqual(slowSuccess.fields["main_world_frame_callback_latency_ms"], .double(1_530.25))

        let timeout = events[1]
        XCTAssertEqual(timeout.fields["main_world_probe_outcome"], .string("success"))
        XCTAssertEqual(timeout.fields["main_world_responsiveness_probe_outcome"], .string("timeout"))
        XCTAssertEqual(timeout.fields["main_world_event_loop_schedule_latency_ms"], .null)
        XCTAssertEqual(timeout.fields["main_world_frame_callback_latency_ms"], .null)

        for event in events {
            XCTAssertFalse(event.fields.keys.contains { key in
                ["page_text", "prompt", "response_text", "selector", "clicked_control"].contains(key)
            })
            XCTAssertFalse(event.fields.values.contains { value in
                if case let .string(string) = value {
                    return string.contains("CONTENT_SENTINEL") || string.contains("sidebar button")
                }
                return false
            })
            XCTAssertFalse(event.fields.keys.contains { $0.contains("degraded_classification") })
        }
    }

    func testRuntimeResponsivenessFromReplacedContextIsStaleNotSlow() async throws {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        let webView = makeWebView()
        let gate = RuntimeResponsivenessProbeTestGate()
        let observer = SlotNavigationObserver(
            slotID: UUID(), webView: webView, websiteMode: .desktop,
            onURLChange: { _, _ in }, diagnostics: diagnostics,
            crossWorldLivenessInterval: 300,
            livenessProbeEvaluator: { _, _ in
                .success(readyState: "complete", visibilityState: "visible", latencyMilliseconds: 1)
            },
            responsivenessProbeEvaluator: { _, _ in await gate.evaluate() }
        )
        load("<main>Stale responsiveness probe</main>", in: webView)
        await settle(webView)

        let capture = Task { @MainActor in await observer.captureCrossWorldLivenessOnce() }
        await gate.waitUntilStarted()
        observer.invalidateDiagnosticNavigation()
        gate.resolve(
            .success(
                probeLatencyMilliseconds: 3_900,
                eventLoopSchedulingLatencyMilliseconds: 3_700,
                frameCallbackOutcome: .sampled,
                frameCallbackLatencyMilliseconds: 3_800
            )
        )
        await capture.value

        let event = try XCTUnwrap(writer.events.last { $0.event == "web_runtime.cross_world_liveness" })
        XCTAssertEqual(event.fields["runtime_context_current"], .bool(false))
        XCTAssertEqual(event.fields["main_world_probe_outcome"], .string("stale"))
        XCTAssertEqual(event.fields["main_world_responsiveness_probe_outcome"], .string("stale"))
        XCTAssertEqual(event.fields["main_world_event_loop_schedule_latency_ms"], .null)
        XCTAssertEqual(event.fields["main_world_frame_callback_latency_ms"], .null)
        XCTAssertEqual(event.fields["post_finish_dual_timeout_count"], .integer(0))
        XCTAssertNil(writer.events.last { $0.event == "web_runtime.post_finish_stall_detected" })
    }

    func testRuntimeResponsivenessProbeUsesExistingBoundedCallbackBudget() async {
        let budget = WebRuntimeLivenessRequestBudget()
        _ = budget.reserve(.mainPage)
        _ = budget.reserve(.mainPage)
        let result = await SlotNavigationObserver.productionResponsivenessProbe(
            webView: makeWebView(),
            shouldMeasureFrame: true,
            timeout: 5,
            requestBudget: budget
        )

        XCTAssertEqual(result.outcome, .suppressed)
        XCTAssertEqual(budget.pendingCount(in: .mainPage), 2)
        XCTAssertLessThanOrEqual(
            budget.pendingCount(in: .mainPage),
            WebRuntimeLivenessRequestBudget.maximumPendingRequestsPerWorld
        )
    }

    func testProductionRuntimeResponsivenessProbeReturnsContentFreeSchedulingMetrics() async {
        let webView = makeWebView()
        load(
            "<script>Object.defineProperty(document, 'visibilityState', { configurable: true, value: 'visible' });</script><main>CONTENT_SENTINEL private page content</main>",
            in: webView
        )
        await settle(webView)
        let budget = WebRuntimeLivenessRequestBudget()

        let result = await SlotNavigationObserver.productionResponsivenessProbe(
            webView: webView,
            shouldMeasureFrame: true,
            timeout: 5,
            requestBudget: budget
        )

        XCTAssertEqual(result.outcome, .success)
        XCTAssertGreaterThanOrEqual(result.probeLatencyMilliseconds, 0)
        XCTAssertGreaterThanOrEqual(result.eventLoopSchedulingLatencyMilliseconds ?? -1, 0)
        XCTAssertTrue(
            result.frameCallbackOutcome == .sampled
                || result.frameCallbackOutcome == .measurementWindowElapsed
        )
        if result.frameCallbackOutcome == .sampled {
            XCTAssertGreaterThanOrEqual(result.frameCallbackLatencyMilliseconds ?? -1, 0)
        } else {
            XCTAssertNil(result.frameCallbackLatencyMilliseconds)
        }
        XCTAssertEqual(budget.pendingCount(in: .mainPage), 0)
    }

    func testRuntimeLivenessSuppressionIsNotMisclassifiedAsTimeout() async throws {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        let webView = makeWebView()
        let observer = SlotNavigationObserver(
            slotID: UUID(), webView: webView, websiteMode: .desktop,
            onURLChange: { _, _ in }, diagnostics: diagnostics,
            crossWorldLivenessInterval: 300,
            livenessProbeEvaluator: { _, world in
                .terminal(
                    world == .mainPage ? .suppressed : .timeout,
                    latencyMilliseconds: 5_000
                )
            }
        )
        load("<main>Suppressed cross-world probe</main>", in: webView)
        await settle(webView)

        await observer.captureCrossWorldLivenessOnce()

        let event = try XCTUnwrap(writer.events.last { $0.event == "web_runtime.cross_world_liveness" })
        XCTAssertEqual(event.fields["main_world_probe_outcome"], .string("suppressed"))
        XCTAssertEqual(event.fields["isolated_world_probe_outcome"], .string("timeout"))
        XCTAssertEqual(event.fields["post_finish_dual_timeout_count"], .integer(0))
        XCTAssertNil(writer.events.last { $0.event == "web_runtime.post_finish_stall_candidate" })
        XCTAssertNil(writer.events.last { $0.event == "web_runtime.post_finish_stall_detected" })
    }

    func testRuntimeLivenessPendingRequestBudgetIsBoundedPerWorld() throws {
        let budget = WebRuntimeLivenessRequestBudget()
        let mainOne = try XCTUnwrap(budget.reserve(.mainPage))
        let mainTwo = try XCTUnwrap(budget.reserve(.mainPage))
        XCTAssertNil(budget.reserve(.mainPage))
        XCTAssertEqual(budget.pendingCount(in: .mainPage), 2)

        let isolatedOne = try XCTUnwrap(budget.reserve(.floatTabsIsolated))
        let isolatedTwo = try XCTUnwrap(budget.reserve(.floatTabsIsolated))
        XCTAssertNil(budget.reserve(.floatTabsIsolated))
        XCTAssertEqual(budget.pendingCount(in: .floatTabsIsolated), 2)

        budget.complete(mainOne, in: .mainPage)
        XCTAssertEqual(budget.pendingCount(in: .mainPage), 1)
        XCTAssertNotNil(budget.reserve(.mainPage))
        XCTAssertEqual(budget.pendingCount(in: .mainPage), 2)

        budget.complete(mainTwo, in: .mainPage)
        budget.complete(isolatedOne, in: .floatTabsIsolated)
        budget.complete(isolatedTwo, in: .floatTabsIsolated)
        XCTAssertEqual(budget.pendingCount(in: .mainPage), 1)
        XCTAssertEqual(budget.pendingCount(in: .floatTabsIsolated), 0)
    }

    func testRuntimeLivenessNeedsTwoFinishedDualTimeoutsToConfirmStall() async throws {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        let webView = makeWebView()
        let observer = SlotNavigationObserver(
            slotID: UUID(), webView: webView, websiteMode: .desktop,
            onURLChange: { _, _ in }, diagnostics: diagnostics,
            crossWorldLivenessInterval: 300,
            livenessProbeEvaluator: { _, _ in .terminal(.timeout, latencyMilliseconds: 5_000) }
        )
        load("<main>Dual timeout</main>", in: webView)
        await settle(webView)
        XCTAssertEqual(observer.currentNavigationDiagnosticFields["navigation_phase"], .string("finished"))

        await observer.captureCrossWorldLivenessOnce()
        let candidate = try XCTUnwrap(writer.events.last { $0.event == "web_runtime.post_finish_stall_candidate" })
        XCTAssertEqual(candidate.fields["stall_confirmation_state"], .string("candidate"))
        XCTAssertEqual(candidate.fields["post_finish_dual_timeout_count"], .integer(1))

        await observer.captureCrossWorldLivenessOnce()
        let confirmed = try XCTUnwrap(writer.events.last { $0.event == "web_runtime.post_finish_stall_detected" })
        XCTAssertEqual(confirmed.fields["stall_class"], .string("POST_FINISH_RUNTIME_STALL"))
        XCTAssertEqual(confirmed.fields["stall_confirmation_state"], .string("confirmed"))
        XCTAssertEqual(confirmed.fields["post_finish_dual_timeout_count"], .integer(2))
        XCTAssertEqual(confirmed.fields["navigation_phase"], .string("finished"))
    }

    func testRecoveredFinishRestoresPostFinishStallEligibility() async throws {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .verbose, writer: writer)
        let webView = makeWebView()
        let observer = SlotNavigationObserver(
            slotID: UUID(), webView: webView, websiteMode: .desktop,
            onURLChange: { _, _ in }, diagnostics: diagnostics,
            crossWorldLivenessInterval: 300,
            livenessProbeEvaluator: { _, _ in .terminal(.timeout, latencyMilliseconds: 5_000) }
        )

        observer.webViewWebContentProcessDidTerminate(webView)
        webView.navigationDelegate = nil
        let recoveryNavigation = try XCTUnwrap(
            webView.loadHTMLString(
                "<html><body>recovered finish</body></html>",
                baseURL: URL(string: "https://chatgpt.com/")
            )
        )
        await settle(webView)
        observer.registerRecoveryNavigation(recoveryNavigation)
        observer.webView(webView, didCommit: recoveryNavigation)
        observer.webView(webView, didFinish: recoveryNavigation)

        XCTAssertEqual(
            observer.currentNavigationDiagnosticFields["navigation_phase"],
            .string("finished")
        )
        await observer.captureCrossWorldLivenessOnce()

        let candidate = try XCTUnwrap(
            writer.events.last { $0.event == "web_runtime.post_finish_stall_candidate" }
        )
        XCTAssertEqual(candidate.fields["navigation_finished"], .bool(true))
        XCTAssertEqual(candidate.fields["navigation_phase"], .string("finished"))
        XCTAssertEqual(candidate.fields["post_finish_dual_timeout_count"], .integer(1))
    }

    func testStallTerminationRecoveryClosesSameIncidentWhenRuntimeIsHealthy() async throws {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .verbose, writer: writer)
        let webView = makeWebView(
            deterministicURL: URL(string: "https://chatgpt.com/recovered")
        )
        let observer = SlotNavigationObserver(
            slotID: UUID(), webView: webView, websiteMode: .desktop,
            onURLChange: { _, _ in }, diagnostics: diagnostics,
            crossWorldLivenessInterval: 300,
            livenessProbeEvaluator: { _, _ in
                .success(readyState: "complete", visibilityState: "visible", latencyMilliseconds: 1)
            }
        )

        let stalledNavigation = try XCTUnwrap(
            webView.loadHTMLString(
                "<html><body>stalled</body></html>",
                baseURL: URL(string: "https://chatgpt.com/stalled")
            )
        )
        webView.navigationDelegate = nil
        observer.webView(webView, didStartProvisionalNavigation: stalledNavigation)
        observer.fireDiagnosticStallWatchdog(
            navigationID: ObjectIdentifier(stalledNavigation),
            generation: 1,
            phase: "provisional"
        )
        let incidentID = try XCTUnwrap(
            writer.events.last { $0.event == "navigation.stall_detected" }?.fields["incident_id"]
        )

        observer.webViewWebContentProcessDidTerminate(webView)
        let termination = try XCTUnwrap(
            writer.events.last { $0.event == "web_content_process_terminated" }
        )
        XCTAssertEqual(termination.fields["incident_id"], incidentID)

        let recoveryNavigation = try XCTUnwrap(
            webView.loadHTMLString(
                "<html><body>recovered</body></html>",
                baseURL: URL(string: "https://chatgpt.com/recovered")
            )
        )
        await settle(webView)
        observer.registerRecoveryNavigation(recoveryNavigation)
        observer.webView(webView, didCommit: recoveryNavigation)
        observer.webView(webView, didFinish: recoveryNavigation)
        let progress = try XCTUnwrap(
            writer.events.last { $0.event == "web_runtime.incident.recovery_progress" }
        )
        XCTAssertEqual(progress.fields["incident_id"], incidentID)

        await observer.captureCrossWorldLivenessOnce()

        let closure = try XCTUnwrap(
            writer.events.last { $0.event == "web_runtime.incident.closed" }
        )
        XCTAssertEqual(closure.fields["incident_id"], incidentID)
        XCTAssertEqual(closure.fields["incident_outcome"], .string("healthy_current_runtime"))
    }

    func testTerminatedIncidentClosesAsRuntimeReplacedWhenInvalidated() throws {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        let webView = makeWebView()
        let observer = SlotNavigationObserver(
            slotID: UUID(), webView: webView, websiteMode: .desktop,
            onURLChange: { _, _ in }, diagnostics: diagnostics
        )

        observer.webViewWebContentProcessDidTerminate(webView)
        let incidentID = try XCTUnwrap(
            writer.events.last { $0.event == "web_content_process_terminated" }?.fields["incident_id"]
        )

        observer.invalidateDiagnosticNavigation()

        let closure = try XCTUnwrap(
            writer.events.last { $0.event == "web_runtime.incident.closed" }
        )
        XCTAssertEqual(closure.fields["incident_id"], incidentID)
        XCTAssertEqual(closure.fields["incident_outcome"], .string("runtime_replaced"))
    }

    func testRuntimeLivenessMarksInFlightResultsStaleAfterInvalidation() async throws {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        let webView = makeWebView()
        let gate = RuntimeLivenessProbeTestGate()
        let observer = SlotNavigationObserver(
            slotID: UUID(), webView: webView, websiteMode: .desktop,
            onURLChange: { _, _ in }, diagnostics: diagnostics,
            crossWorldLivenessInterval: 300,
            livenessProbeEvaluator: { _, _ in await gate.evaluate() }
        )
        load("<main>Stale probe</main>", in: webView)
        await settle(webView)

        let capture = Task { @MainActor in await observer.captureCrossWorldLivenessOnce() }
        await gate.waitUntilStarted(count: 2)
        observer.invalidateDiagnosticNavigation()
        gate.resolveAll(.success(readyState: "complete", visibilityState: "visible", latencyMilliseconds: 1))
        await capture.value

        let event = try XCTUnwrap(writer.events.last { $0.event == "web_runtime.cross_world_liveness" })
        XCTAssertEqual(event.fields["runtime_context_current"], .bool(false))
        XCTAssertEqual(event.fields["main_world_probe_outcome"], .string("stale"))
        XCTAssertEqual(event.fields["isolated_world_probe_outcome"], .string("stale"))
        XCTAssertEqual(event.fields["post_finish_dual_timeout_count"], .integer(0))
        XCTAssertNil(writer.events.last { $0.event == "web_runtime.post_finish_stall_detected" })
    }

    func testObservedWebProcessEpochAdvancesOnlyAtTerminationCallback() throws {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        let webView = makeWebView()
        let identity = WebRuntimeDiagnosticIdentity(runtimeGeneration: 42, webViewInstanceID: UUID())
        let observer = SlotNavigationObserver(
            slotID: UUID(), webView: webView, runtimeDiagnosticIdentity: identity,
            websiteMode: .desktop, onURLChange: { _, _ in }, diagnostics: diagnostics,
            crossWorldLivenessInterval: 300
        )

        XCTAssertEqual(observer.currentContentProcessDiagnosticFields["observed_web_process_epoch"], .integer(1))
        XCTAssertEqual(observer.currentContentProcessDiagnosticFields["observed_web_process_termination_count"], .integer(0))

        observer.webViewWebContentProcessDidTerminate(webView)
        let first = try XCTUnwrap(writer.events.last { $0.event == "web_content_process_terminated" })
        XCTAssertEqual(first.fields["observed_web_process_epoch"], .integer(2))
        XCTAssertEqual(first.fields["observed_web_process_termination_count"], .integer(1))
        XCTAssertEqual(first.fields["runtime_generation"], .integer(42))
        XCTAssertEqual(first.fields["webview_instance_id"], .string(identity.webViewInstanceID.uuidString))

        observer.webViewWebContentProcessDidTerminate(webView)
        XCTAssertEqual(observer.currentContentProcessDiagnosticFields["observed_web_process_epoch"], .integer(3))
        XCTAssertEqual(observer.currentContentProcessDiagnosticFields["observed_web_process_termination_count"], .integer(2))
    }
}

@MainActor
private final class RuntimeLivenessProbeTestGate {
    private var continuations: [CheckedContinuation<WebRuntimeLivenessProbeResult, Never>] = []

    func evaluate() async -> WebRuntimeLivenessProbeResult {
        await withCheckedContinuation { continuations.append($0) }
    }

    func waitUntilStarted(count: Int) async {
        while continuations.count < count { await Task.yield() }
    }

    func resolveAll(_ result: WebRuntimeLivenessProbeResult) {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume(returning: result) }
    }
}

@MainActor
private final class RuntimeResponsivenessProbeTestGate {
    private var continuation: CheckedContinuation<WebRuntimeResponsivenessProbeResult, Never>?

    func evaluate() async -> WebRuntimeResponsivenessProbeResult {
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        while continuation == nil { await Task.yield() }
    }

    func resolve(_ result: WebRuntimeResponsivenessProbeResult) {
        let pending = continuation
        continuation = nil
        pending?.resume(returning: result)
    }
}
