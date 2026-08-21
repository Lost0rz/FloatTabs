import WebKit
import XCTest
@testable import FloatTabs

/// Drives the real injected script end-to-end: a synthetic ChatGPT document
/// loaded into a real WKWebView (chatgpt.com base URL), mutated from page
/// JavaScript, observed through the actual MutationObserver pipeline, and
/// reduced through the actual native bridge acceptance path.
@MainActor
private final class ChatGPTDetectorPage {
    final class ObservationLog {
        private(set) var entries: [ChatGPTAttentionObservation] = []

        func record(_ observation: ChatGPTAttentionObservation) {
            entries.append(observation)
        }
    }

    let slotID: UUID
    let webView: WKWebView
    let bridge: ChatGPTAttentionBridge
    private let log: ObservationLog

    var observations: [ChatGPTAttentionObservation] { log.entries }

    init() {
        let log = ObservationLog()
        let slotID = UUID()
        let bridge = ChatGPTAttentionBridge(slotID: slotID) { _, observation in
            log.record(observation)
        }
        let configuration = WKWebViewConfiguration()
        bridge.install(into: configuration.userContentController)
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
        bridge.attach(to: webView)
        self.log = log
        self.slotID = slotID
        self.bridge = bridge
        self.webView = webView
    }

    func load(bodyHTML: String, baseURL: URL = URL(string: "https://chatgpt.com/")!) {
        let html = "<!DOCTYPE html><html><head></head><body>\(bodyHTML)</body></html>"
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    func run(_ javascript: String) {
        webView.evaluateJavaScript(javascript) { _, _ in }
    }

    /// Waits until the page has parsed and the script's coalesced baseline
    /// (up to ~250 ms after load) has had room to settle.
    func settleBaseline() async {
        await waitFor { [self] in !webView.isLoading }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
    }

    func waitFor(
        _ condition: @escaping () -> Bool,
        timeout: TimeInterval = 5
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return condition()
    }
}

@MainActor
final class ChatGPTGenerationDetectorTests: XCTestCase {
    func testHiddenFirstStopControlDoesNotMaskVisibleSecondControl() async {
        let page = ChatGPTDetectorPage()

        page.load(bodyHTML: """
        <button data-testid="stop-button" style="display: none;">Stop 1</button>
        <button data-testid="stop-button">Stop 2</button>
        """)

        let observedStart = await page.waitFor { page.observations.contains(.generationStarted) }
        XCTAssertTrue(
            observedStart,
            "a hidden first match must never mask a later rendered stop control"
        )
        XCTAssertEqual(page.observations, [.generationStarted])
    }

    func testDisplayNoneStopControlIsNotGeneratingUntilRevealedByStyle() async {
        let page = ChatGPTDetectorPage()
        page.load(bodyHTML: """
        <button data-testid="stop-button" style="display: none;">Stop</button>
        """)
        await page.settleBaseline()

        XCTAssertTrue(page.observations.isEmpty, "display:none control must not count")

        page.run("document.querySelector('[data-testid=\"stop-button\"]').style.display = ''")

        let revealed = await page.waitFor { !page.observations.isEmpty }
        XCTAssertTrue(revealed, "style-attribute reveal must re-evaluate without node changes")
        XCTAssertEqual(page.observations, [.generationStarted])
    }

    func testVisibilityHiddenStopControlIsNotGeneratingUntilRevealed() async {
        let page = ChatGPTDetectorPage()
        page.load(bodyHTML: """
        <button data-testid="stop-button" style="visibility: hidden;">Stop</button>
        """)
        await page.settleBaseline()

        XCTAssertTrue(page.observations.isEmpty, "visibility:hidden control must not count")

        page.run("document.querySelector('[data-testid=\"stop-button\"]').style.visibility = 'visible'")

        let revealed = await page.waitFor { !page.observations.isEmpty }
        XCTAssertTrue(revealed, "visibility reveal must re-evaluate")
        XCTAssertEqual(page.observations, [.generationStarted])
    }

    func testClassMutationAloneRevealsStopControlWithoutNodeChanges() async {
        let page = ChatGPTDetectorPage()
        page.load(bodyHTML: """
        <style>.concealed { display: none; }</style>
        <button data-testid="stop-button" class="concealed">Stop</button>
        """)
        await page.settleBaseline()

        XCTAssertTrue(page.observations.isEmpty, "class-hidden control must not count")

        page.run("document.querySelector('[data-testid=\"stop-button\"]').classList.remove('concealed')")

        let revealed = await page.waitFor { !page.observations.isEmpty }
        XCTAssertTrue(revealed, "class-attribute mutation must re-evaluate")
        XCTAssertEqual(page.observations, [.generationStarted])
    }

    func testVisibleStopControlHiddenByAttributeMutationStopsGenerating() async {
        let page = ChatGPTDetectorPage()
        page.load(bodyHTML: """
        <button data-testid="stop-button">Stop</button>
        """)

        let started = await page.waitFor { page.observations.contains(.generationStarted) }
        XCTAssertTrue(started)

        page.run("document.querySelector('[data-testid=\"stop-button\"]').setAttribute('hidden', '')")

        let finished = await page.waitFor { page.observations.contains(.generationFinished) }
        XCTAssertTrue(finished, "hidden-attribute mutation must re-evaluate to idle")
        XCTAssertEqual(page.observations, [.generationStarted, .generationFinished])
    }

    func testNoStopControlMeansIdleUntilOneIsInserted() async {
        let page = ChatGPTDetectorPage()
        page.load(bodyHTML: "<p>Nothing generating here.</p>")
        await page.settleBaseline()

        XCTAssertTrue(page.observations.isEmpty, "no stop control must mean not generating")

        page.run("""
        (() => {
          const button = document.createElement('button');
          button.setAttribute('data-testid', 'stop-button');
          button.textContent = 'Stop';
          document.body.appendChild(button);
        })()
        """)

        let started = await page.waitFor { !page.observations.isEmpty }
        XCTAssertTrue(started)
        XCTAssertEqual(page.observations, [.generationStarted])
    }

    func testInjectedHostGateDerivesFromChatGPTSitePolicy() async {
        let expected = "host === \"\(ChatGPTSitePolicy.chatGPTHost)\""
            + " || host.endsWith(\".\(ChatGPTSitePolicy.chatGPTHost)\")"
            + " || host === \"\(ChatGPTSitePolicy.legacyChatHost)\""

        XCTAssertEqual(ChatGPTAttentionBridge.hostGateExpression(), expected)
        XCTAssertTrue(
            ChatGPTAttentionBridge.scriptSource.contains(expected),
            "the injected script's host gate must be generated from the shared policy"
        )
    }

    func testScriptStaysDormantOnUnsupportedHost() async {
        let page = ChatGPTDetectorPage()
        page.load(
            bodyHTML: """
            <button data-testid="stop-button">Stop</button>
            """,
            baseURL: URL(string: "https://example.com/")!
        )
        await page.settleBaseline()
        try? await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertTrue(
            page.observations.isEmpty,
            "the early host gate must keep the script dormant on unrelated hosts"
        )
    }
}
