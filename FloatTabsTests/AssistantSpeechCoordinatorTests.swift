import WebKit
import XCTest
@testable import FloatTabs

@MainActor
private final class TestSpeechService: SpeechSynthesizing {
    private(set) var spoken: [String] = []
    private(set) var stopCount = 0
    var onUtteranceFinished: (() -> Void)?

    func speak(_ text: String) {
        spoken.append(text)
    }

    func stop() {
        stopCount += 1
    }

    func finishCurrentUtterance() {
        onUtteranceFinished?()
    }
}

@MainActor
private final class TestResponseBridge: ChatGPTResponseExtracting {
    private var completions: [@MainActor (ChatGPTResponsePayload?) -> Void] = []

    var requestCount: Int { completions.count }

    func extractLatest(completion: @escaping @MainActor (ChatGPTResponsePayload?) -> Void) {
        completions.append(completion)
    }

    func resolve(_ payload: ChatGPTResponsePayload?) {
        guard !completions.isEmpty else { return }
        completions.removeFirst()(payload)
    }
}

@MainActor
final class AssistantSpeechCoordinatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = "AssistantSpeechCoordinatorTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func makePayload(
        responseID: String = "document-a:response-a",
        text: String = "Completed response."
    ) -> ChatGPTResponsePayload {
        ChatGPTResponsePayload(
            version: ChatGPTResponsePayload.currentVersion,
            kind: .response,
            requestID: "request-12345678",
            documentToken: "document-12345678",
            responseID: responseID,
            blocks: [SpeechContentBlock(kind: .paragraph, text: text, level: nil)]
        )
    }

    private func makeCoordinator(
        settings: SpeechSettings,
        service: TestSpeechService,
        bridge: TestResponseBridge,
        webView: WKWebView
    ) -> AssistantSpeechCoordinator {
        AssistantSpeechCoordinator(
            settings: settings,
            speechService: service,
            webViewProvider: { _ in webView },
            responseBridgeProvider: { _ in bridge }
        )
    }

    func testDefaultSpeechModeIsOffAndCompletionDoesNotExtract() {
        let settings = SpeechSettings(defaults: defaults)
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        let coordinator = makeCoordinator(
            settings: settings,
            service: service,
            bridge: bridge,
            webView: WKWebView()
        )

        XCTAssertEqual(settings.mode, .off)
        coordinator.handle(ChatGPTAttentionObservation.generationFinished, for: UUID())
        XCTAssertEqual(bridge.requestCount, 0)
    }

    func testCompletionExtractsAndSpeaksExactlyOnce() {
        let settings = SpeechSettings(defaults: defaults)
        settings.mode = .speakWhenCompleted
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            settings: settings,
            service: service,
            bridge: bridge,
            webView: WKWebView()
        )

        coordinator.handle(ChatGPTAttentionObservation.generationFinished, for: slotID)
        bridge.resolve(makePayload())
        bridge.resolve(makePayload())

        XCTAssertEqual(service.spoken, ["Completed response."])
        XCTAssertEqual(bridge.requestCount, 0)
    }

    func testStopSuppressesCurrentResponseAndClearsSpeech() {
        let settings = SpeechSettings(defaults: defaults)
        settings.mode = .speakWhenCompleted
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            settings: settings,
            service: service,
            bridge: bridge,
            webView: WKWebView()
        )

        coordinator.handle(ChatGPTAttentionObservation.generationFinished, for: slotID)
        bridge.resolve(makePayload(text: "Current response."))
        coordinator.stop()
        coordinator.readLatestResponse(for: slotID)
        bridge.resolve(makePayload(text: "Current response."))

        XCTAssertEqual(service.spoken, ["Current response."])
        XCTAssertEqual(service.stopCount, 1)
    }

    func testNextResponseCanSpeakAfterStop() {
        let settings = SpeechSettings(defaults: defaults)
        settings.mode = .speakWhenCompleted
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            settings: settings,
            service: service,
            bridge: bridge,
            webView: WKWebView()
        )

        coordinator.handle(ChatGPTAttentionObservation.generationFinished, for: slotID)
        bridge.resolve(makePayload(responseID: "document-a:old"))
        coordinator.stop()
        coordinator.handle(ChatGPTAttentionObservation.generationFinished, for: slotID)
        bridge.resolve(makePayload(responseID: "document-a:new", text: "Next response."))

        XCTAssertEqual(service.spoken, ["Completed response.", "Next response."])
    }

    func testStaleWebViewResultCannotSpeak() {
        let settings = SpeechSettings(defaults: defaults)
        settings.mode = .speakWhenCompleted
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        var currentWebView = WKWebView()
        let slotID = UUID()
        let coordinator = AssistantSpeechCoordinator(
            settings: settings,
            speechService: service,
            webViewProvider: { _ in currentWebView },
            responseBridgeProvider: { _ in bridge }
        )

        coordinator.handle(ChatGPTAttentionObservation.generationFinished, for: slotID)
        currentWebView = WKWebView()
        bridge.resolve(makePayload())

        XCTAssertTrue(service.spoken.isEmpty)
    }

    func testNavigationResetAllowsSameResponseIdentityInNewDocument() {
        let settings = SpeechSettings(defaults: defaults)
        settings.mode = .speakWhenCompleted
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            settings: settings,
            service: service,
            bridge: bridge,
            webView: WKWebView()
        )

        coordinator.handle(ChatGPTAttentionObservation.generationFinished, for: slotID)
        bridge.resolve(makePayload())
        coordinator.handle(.runtimeReset, for: slotID)
        coordinator.handle(ChatGPTAttentionObservation.generationFinished, for: slotID)
        bridge.resolve(makePayload())

        XCTAssertEqual(service.spoken, ["Completed response.", "Completed response."])
    }
}
