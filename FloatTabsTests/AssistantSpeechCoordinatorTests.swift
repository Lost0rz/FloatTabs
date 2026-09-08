import WebKit
import XCTest
@testable import FloatTabs

@MainActor
private final class TestSpeechService: SpeechSynthesizing {
    private(set) var spoken: [String] = []
    private(set) var spokenTokens: [UInt64] = []
    private(set) var stopCount = 0
    var onUtteranceFinished: ((UInt64) -> Void)?

    func speak(_ text: String, token: UInt64) {
        spoken.append(text)
        spokenTokens.append(token)
    }

    func stop() {
        stopCount += 1
    }

    func finish(token: UInt64) {
        onUtteranceFinished?(token)
    }

    func cancel(token: UInt64) {
        // didCancel is intentionally not surfaced as a finish callback.
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

    func resolve(at index: Int, with payload: ChatGPTResponsePayload?) {
        guard completions.indices.contains(index) else { return }
        completions.remove(at: index)(payload)
    }
}

@MainActor
final class AssistantSpeechCoordinatorTests: XCTestCase {
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
        service: TestSpeechService,
        bridge: TestResponseBridge,
        webView: WKWebView
    ) -> AssistantSpeechCoordinator {
        AssistantSpeechCoordinator(
            speechService: service,
            webViewProvider: { _ in webView },
            responseBridgeProvider: { _ in bridge }
        )
    }

    func testDefaultAutoSpeakSourceIsNilAndCompletionDoesNotExtract() {
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        let coordinator = makeCoordinator(
            service: service,
            bridge: bridge,
            webView: WKWebView()
        )

        XCTAssertNil(coordinator.autoSpeakSlotID)
        coordinator.handle(ChatGPTAttentionObservation.generationFinished, for: UUID())
        XCTAssertEqual(bridge.requestCount, 0)
    }

    func testCompletionExtractsAndSpeaksExactlyOnce() {
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            service: service,
            bridge: bridge,
            webView: WKWebView()
        )
        coordinator.toggleAutoSpeak(for: slotID)

        coordinator.handle(ChatGPTAttentionObservation.generationFinished, for: slotID)
        bridge.resolve(makePayload())
        coordinator.handle(ChatGPTAttentionObservation.generationFinished, for: slotID)
        bridge.resolve(makePayload())

        XCTAssertEqual(service.spoken, ["Completed response."])
        XCTAssertEqual(bridge.requestCount, 0)
    }

    func testStopSuppressesCurrentResponseAndClearsSpeech() {
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            service: service,
            bridge: bridge,
            webView: WKWebView()
        )
        coordinator.toggleAutoSpeak(for: slotID)

        coordinator.handle(ChatGPTAttentionObservation.generationFinished, for: slotID)
        bridge.resolve(makePayload(text: "Current response."))
        coordinator.stop()
        coordinator.readLatestResponse(for: slotID)
        bridge.resolve(makePayload(text: "Current response."))

        XCTAssertEqual(service.spoken, ["Current response.", "Current response."])
        XCTAssertEqual(service.stopCount, 1)
    }

    func testNextResponseCanSpeakAfterStop() {
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            service: service,
            bridge: bridge,
            webView: WKWebView()
        )
        coordinator.toggleAutoSpeak(for: slotID)

        coordinator.handle(ChatGPTAttentionObservation.generationFinished, for: slotID)
        bridge.resolve(makePayload(responseID: "document-a:old"))
        coordinator.stop()
        coordinator.handle(ChatGPTAttentionObservation.generationFinished, for: slotID)
        bridge.resolve(makePayload(responseID: "document-a:new", text: "Next response."))

        XCTAssertEqual(service.spoken, ["Completed response.", "Next response."])
    }

    func testStaleWebViewResultCannotSpeak() {
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        var currentWebView = WKWebView()
        let slotID = UUID()
        let coordinator = AssistantSpeechCoordinator(
            speechService: service,
            webViewProvider: { _ in currentWebView },
            responseBridgeProvider: { _ in bridge }
        )
        coordinator.toggleAutoSpeak(for: slotID)

        coordinator.handle(ChatGPTAttentionObservation.generationFinished, for: slotID)
        currentWebView = WKWebView()
        bridge.resolve(makePayload())

        XCTAssertTrue(service.spoken.isEmpty)
    }

    func testNavigationResetAllowsSameResponseIdentityInNewDocument() {
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            service: service,
            bridge: bridge,
            webView: WKWebView()
        )
        coordinator.toggleAutoSpeak(for: slotID)

        coordinator.handle(ChatGPTAttentionObservation.generationFinished, for: slotID)
        bridge.resolve(makePayload())
        coordinator.handle(.runtimeReset, for: slotID)
        coordinator.handle(ChatGPTAttentionObservation.generationFinished, for: slotID)
        bridge.resolve(makePayload())

        XCTAssertEqual(service.spoken, ["Completed response.", "Completed response."])
    }

    func testAllResponseSegmentsAdvanceOnMatchingFinishToken() {
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            service: service,
            bridge: bridge,
            webView: WKWebView()
        )
        coordinator.toggleAutoSpeak(for: slotID)

        coordinator.handle(.generationFinished, for: slotID)
        bridge.resolve(makePayload(text: "One. Two. Three."))
        XCTAssertEqual(service.spoken, ["One."])

        service.finish(token: service.spokenTokens[0])
        XCTAssertEqual(service.spoken, ["One.", "Two."])
        service.finish(token: service.spokenTokens[1])
        XCTAssertEqual(service.spoken, ["One.", "Two.", "Three."])
        service.finish(token: service.spokenTokens[2])

        XCTAssertNil(coordinator.currentResponseIdentity)
        XCTAssertEqual(coordinator.pendingQueueCount, 0)
    }

    func testStaleFinishAfterStopCannotAdvanceQueue() {
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            service: service,
            bridge: bridge,
            webView: WKWebView()
        )
        coordinator.toggleAutoSpeak(for: slotID)

        coordinator.handle(.generationFinished, for: slotID)
        bridge.resolve(makePayload(text: "One. Two."))
        let token = service.spokenTokens[0]
        coordinator.stop()
        service.finish(token: token)

        XCTAssertEqual(service.spoken, ["One."])
        XCTAssertNil(coordinator.currentResponseIdentity)
        XCTAssertEqual(coordinator.pendingQueueCount, 0)
    }

    func testSupersedeIgnoresOldFinishUntilNewTokenFinishes() {
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            service: service,
            bridge: bridge,
            webView: WKWebView()
        )
        coordinator.toggleAutoSpeak(for: slotID)

        coordinator.handle(.generationFinished, for: slotID)
        bridge.resolve(makePayload(responseID: "document-a:response-a", text: "A one. A two."))
        let tokenA = service.spokenTokens[0]

        coordinator.handle(.generationFinished, for: slotID)
        bridge.resolve(makePayload(responseID: "document-a:response-b", text: "B one. B two."))
        let tokenB = service.spokenTokens[1]
        XCTAssertEqual(service.spoken, ["A one.", "B one."])

        service.finish(token: tokenA)
        XCTAssertEqual(service.spoken, ["A one.", "B one."])
        service.finish(token: tokenB)
        XCTAssertEqual(service.spoken, ["A one.", "B one.", "B two."])
    }

    func testCancelledUtteranceDoesNotAdvanceQueue() {
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            service: service,
            bridge: bridge,
            webView: WKWebView()
        )
        coordinator.toggleAutoSpeak(for: slotID)

        coordinator.handle(.generationFinished, for: slotID)
        bridge.resolve(makePayload(text: "One. Two."))
        service.cancel(token: service.spokenTokens[0])

        XCTAssertEqual(service.spoken, ["One."])
        XCTAssertEqual(coordinator.pendingQueueCount, 1)
        XCTAssertNotNil(coordinator.currentResponseIdentity)
    }

    func testOlderExtractionCannotConsumeNewerRequest() {
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            service: service,
            bridge: bridge,
            webView: WKWebView()
        )
        coordinator.toggleAutoSpeak(for: slotID)

        coordinator.handle(.generationFinished, for: slotID)
        coordinator.handle(.generationFinished, for: slotID)
        XCTAssertEqual(bridge.requestCount, 2)

        bridge.resolve(at: 0, with: makePayload(responseID: "document-a:old", text: "Old."))
        XCTAssertTrue(service.spoken.isEmpty)
        XCTAssertEqual(bridge.requestCount, 1)

        bridge.resolve(makePayload(responseID: "document-a:new", text: "New."))
        XCTAssertEqual(service.spoken, ["New."])
    }

    func testNewerExtractionResolvedFirstIgnoresOlderLaterResult() {
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            service: service,
            bridge: bridge,
            webView: WKWebView()
        )
        coordinator.toggleAutoSpeak(for: slotID)

        coordinator.handle(.generationFinished, for: slotID)
        coordinator.handle(.generationFinished, for: slotID)
        bridge.resolve(at: 1, with: makePayload(responseID: "document-a:new", text: "New."))
        bridge.resolve(at: 0, with: makePayload(responseID: "document-a:old", text: "Old."))

        XCTAssertEqual(service.spoken, ["New."])
    }

    func testStopEpochCannotBeBypassedByStaleExtraction() {
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            service: service,
            bridge: bridge,
            webView: WKWebView()
        )
        coordinator.toggleAutoSpeak(for: slotID)

        coordinator.handle(.generationFinished, for: slotID)
        coordinator.stop()
        coordinator.handle(.generationFinished, for: slotID)
        bridge.resolve(at: 0, with: makePayload(responseID: "document-a:old", text: "Old."))
        XCTAssertTrue(service.spoken.isEmpty)
        XCTAssertEqual(bridge.requestCount, 1)

        bridge.resolve(makePayload(responseID: "document-a:new", text: "New."))
        XCTAssertEqual(service.spoken, ["New."])
    }

    func testAutoSpeakSourceSwitchesAtomicallyBetweenSlots() {
        let service = TestSpeechService()
        let slotA = UUID()
        let slotB = UUID()
        let bridgeA = TestResponseBridge()
        let bridgeB = TestResponseBridge()
        let webViewA = WKWebView()
        let webViewB = WKWebView()
        let coordinator = AssistantSpeechCoordinator(
            speechService: service,
            webViewProvider: { slotID in
                slotID == slotA ? webViewA : webViewB
            },
            responseBridgeProvider: { slotID in
                slotID == slotA ? bridgeA : bridgeB
            }
        )
        coordinator.toggleAutoSpeak(for: slotA)
        XCTAssertEqual(coordinator.autoSpeakSlotID, slotA)
        coordinator.toggleAutoSpeak(for: slotB)
        XCTAssertEqual(coordinator.autoSpeakSlotID, slotB)

        coordinator.handle(.generationFinished, for: slotA)
        coordinator.handle(.generationFinished, for: slotB)
        XCTAssertEqual(bridgeA.requestCount, 0)
        XCTAssertEqual(bridgeB.requestCount, 1)
        bridgeB.resolve(makePayload(responseID: "document-b:b", text: "B."))

        XCTAssertEqual(service.spoken, ["B."])
    }

    func testManualReadWorksWhenAutomaticModeIsOff() {
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            service: service,
            bridge: bridge,
            webView: WKWebView()
        )

        coordinator.readLatestResponse(for: slotID)
        XCTAssertEqual(bridge.requestCount, 1)
        bridge.resolve(makePayload(text: "Manual response."))

        XCTAssertEqual(service.spoken, ["Manual response."])
    }

    func testRerenderedSameResponseIsNotSpokenTwice() {
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            service: service,
            bridge: bridge,
            webView: WKWebView()
        )
        coordinator.toggleAutoSpeak(for: slotID)

        coordinator.handle(.generationFinished, for: slotID)
        bridge.resolve(makePayload(responseID: "document-a:reply-latest", text: "Stable."))
        coordinator.handle(.generationFinished, for: slotID)
        bridge.resolve(makePayload(responseID: "document-a:reply-latest", text: "Stable."))

        XCTAssertEqual(service.spoken, ["Stable."])
    }

    func testTogglingSameAutoSpeakSlotDisarmsIt() {
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            service: service,
            bridge: bridge,
            webView: WKWebView()
        )

        coordinator.toggleAutoSpeak(for: slotID)
        coordinator.toggleAutoSpeak(for: slotID)

        XCTAssertNil(coordinator.autoSpeakSlotID)
        coordinator.handle(.generationFinished, for: slotID)
        XCTAssertEqual(bridge.requestCount, 0)
    }

    func testManualReadReplaysSameResponseAfterAutomaticPlayback() {
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            service: service,
            bridge: bridge,
            webView: WKWebView()
        )
        coordinator.toggleAutoSpeak(for: slotID)

        coordinator.handle(.generationFinished, for: slotID)
        bridge.resolve(makePayload(responseID: "document-a:reply", text: "Replay me."))
        coordinator.readLatestResponse(for: slotID)
        bridge.resolve(makePayload(responseID: "document-a:reply", text: "Replay me."))

        XCTAssertEqual(service.spoken, ["Replay me.", "Replay me."])
        XCTAssertEqual(coordinator.autoSpeakSlotID, slotID)
    }

    func testStopSuppressesAutomaticRerenderButManualReplayBypassesSuppression() {
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            service: service,
            bridge: bridge,
            webView: WKWebView()
        )
        coordinator.toggleAutoSpeak(for: slotID)

        coordinator.handle(.generationFinished, for: slotID)
        bridge.resolve(makePayload(responseID: "document-a:reply", text: "Replay me."))
        coordinator.stop()

        coordinator.handle(.generationFinished, for: slotID)
        bridge.resolve(makePayload(responseID: "document-a:reply", text: "Replay me."))
        XCTAssertEqual(service.spoken, ["Replay me."])

        coordinator.readLatestResponse(for: slotID)
        bridge.resolve(makePayload(responseID: "document-a:reply", text: "Replay me."))
        XCTAssertEqual(service.spoken, ["Replay me.", "Replay me."])

        coordinator.handle(.generationFinished, for: slotID)
        bridge.resolve(makePayload(responseID: "document-a:reply", text: "Replay me."))
        XCTAssertEqual(service.spoken, ["Replay me.", "Replay me."])
        XCTAssertEqual(coordinator.autoSpeakSlotID, slotID)
    }

    func testStopPreservesAutoSpeakSourceAndNextResponseSpeaks() {
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            service: service,
            bridge: bridge,
            webView: WKWebView()
        )
        coordinator.toggleAutoSpeak(for: slotID)
        coordinator.handle(.generationFinished, for: slotID)
        bridge.resolve(makePayload(responseID: "document-a:old", text: "Old."))

        coordinator.stop()
        XCTAssertEqual(coordinator.autoSpeakSlotID, slotID)

        coordinator.handle(.generationFinished, for: slotID)
        bridge.resolve(makePayload(responseID: "document-a:new", text: "New."))
        XCTAssertEqual(service.spoken, ["Old.", "New."])
    }

    func testRuntimeResetStopsSpeechButPreservesAutoSpeakSource() {
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            service: service,
            bridge: bridge,
            webView: WKWebView()
        )
        coordinator.toggleAutoSpeak(for: slotID)
        coordinator.handle(.generationFinished, for: slotID)
        bridge.resolve(makePayload(text: "Current."))

        coordinator.resetRuntime(slotID: slotID)

        XCTAssertEqual(coordinator.autoSpeakSlotID, slotID)
        XCTAssertNil(coordinator.currentSpeakingSlotID)
        XCTAssertEqual(coordinator.pendingQueueCount, 0)
    }

    func testPermanentSlotRemovalClearsMatchingAutoSpeakSource() {
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            service: service,
            bridge: bridge,
            webView: WKWebView()
        )
        coordinator.toggleAutoSpeak(for: slotID)

        coordinator.removeSlot(slotID: slotID)

        XCTAssertNil(coordinator.autoSpeakSlotID)
    }

    func testCurrentSpeakingSlotProjectionTracksStartFinishAndStop() {
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            service: service,
            bridge: bridge,
            webView: WKWebView()
        )
        coordinator.toggleAutoSpeak(for: slotID)

        coordinator.handle(.generationFinished, for: slotID)
        bridge.resolve(makePayload(text: "One. Two."))
        XCTAssertEqual(coordinator.currentSpeakingSlotID, slotID)

        service.finish(token: service.spokenTokens[0])
        XCTAssertEqual(coordinator.currentSpeakingSlotID, slotID)
        service.finish(token: service.spokenTokens[1])
        XCTAssertNil(coordinator.currentSpeakingSlotID)

        coordinator.readLatestResponse(for: slotID)
        bridge.resolve(makePayload(responseID: "document-a:manual", text: "Manual."))
        XCTAssertEqual(coordinator.currentSpeakingSlotID, slotID)
        coordinator.stop()
        XCTAssertNil(coordinator.currentSpeakingSlotID)
    }
}
