import WebKit
import XCTest
@testable import FloatTabs

@MainActor
private final class TestSpeechService: SpeechSynthesizing {
    private(set) var spokenRequests: [SpeechPlaybackRequest] = []
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private(set) var stopCount = 0
    var onUtteranceFinished: ((UInt64) -> Void)?
    var onUtterancePaused: ((UInt64) -> Void)?
    var onUtteranceContinued: ((UInt64) -> Void)?
    var pauseResult = true
    var resumeResult = true

    var spoken: [String] { spokenRequests.map(\.text) }
    var spokenTokens: [UInt64] { spokenRequests.map(\.transportToken) }
    var spokenLanguageRoles: [SpeechLanguageRole] {
        spokenRequests.map(\.languageRole)
    }

    func speak(_ request: SpeechPlaybackRequest) {
        spokenRequests.append(request)
    }

    func pause() -> Bool {
        pauseCount += 1
        return pauseResult
    }

    func resume() -> Bool {
        resumeCount += 1
        return resumeResult
    }

    func stop() {
        stopCount += 1
    }

    func finish(token: UInt64) {
        onUtteranceFinished?(token)
    }

    func pause(token: UInt64) {
        onUtterancePaused?(token)
    }

    func `continue`(token: UInt64) {
        onUtteranceContinued?(token)
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
private final class TestFollowBridge: ChatGPTResponseFollowing {
    private(set) var locators: [SpeechSourceLocator] = []
    var result = true

    func scrollToSpeechBlock(
        _ locator: SpeechSourceLocator,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        locators.append(locator)
        completion(result)
    }
}

@MainActor
final class SpeechServiceTests: XCTestCase {
    func testPauseAndResumeWithoutAnActiveUtteranceFailClosed() {
        let service = SpeechService()

        XCTAssertFalse(service.pause())
        XCTAssertFalse(service.resume())
        service.stop()
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

    private func makeLongResponseText(prefix: String, count: Int) -> String {
        (1...count).map { "\(prefix) segment \($0)." }.joined(separator: " ")
    }

    private func finishEverySpokenRequest(_ service: TestSpeechService) {
        var index = 0
        while index < service.spokenTokens.count {
            service.finish(token: service.spokenTokens[index])
            index += 1
        }
    }

    private func makeCoordinator(
        service: TestSpeechService,
        bridge: TestResponseBridge,
        webView: WKWebView,
        followBridge: TestFollowBridge? = nil,
        activeSlotIDProvider: @escaping @MainActor () -> UUID? = { nil },
        followSpeechEnabled: @escaping @MainActor () -> Bool = { true }
    ) -> AssistantSpeechCoordinator {
        AssistantSpeechCoordinator(
            speechService: service,
            webViewProvider: { _ in webView },
            responseBridgeProvider: { _ in bridge },
            followBridgeProvider: { _ in followBridge },
            activeSlotIDProvider: activeSlotIDProvider,
            followSpeechEnabled: followSpeechEnabled
        )
    }

    private func makeFollowPayload(
        documentToken: String = "document-a-follow",
        responseID: String = "document-a-follow:response-a",
        blocks: [SpeechContentBlock]
    ) -> ChatGPTResponsePayload {
        ChatGPTResponsePayload(
            version: ChatGPTResponsePayload.currentVersion,
            kind: .response,
            requestID: "request-follow-12345678",
            documentToken: documentToken,
            responseID: responseID,
            blocks: blocks.enumerated().map { index, block in
                SpeechContentBlock(
                    kind: block.kind,
                    text: block.text,
                    level: block.level,
                    sourceLocator: SpeechSourceLocator(
                        documentToken: documentToken,
                        responseID: responseID,
                        blockID: "\(responseID):block-\(index)"
                    )
                )
            }
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

        XCTAssertTrue(coordinator.autoSpeakSlotIDs.isEmpty)
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
        XCTAssertEqual(service.stopCount, 2)
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

    func testAutomaticResponsesAppendWithoutInterruptingCurrentUtterance() {
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
        XCTAssertEqual(service.spoken, ["A one."])

        service.finish(token: tokenA)
        XCTAssertEqual(service.spoken, ["A one.", "A two."])
        let tokenATwo = service.spokenTokens[1]
        service.finish(token: tokenATwo)
        XCTAssertEqual(service.spoken, ["A one.", "A two.", "B one."])
        let tokenB = service.spokenTokens[2]
        service.finish(token: tokenB)
        XCTAssertEqual(service.spoken, ["A one.", "A two.", "B one.", "B two."])
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

    func testMultipleAutoSpeakSlotsRemainArmedAndUseCompletionOrderFIFO() {
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
        coordinator.toggleAutoSpeak(for: slotB)
        XCTAssertEqual(coordinator.autoSpeakSlotIDs, Set([slotA, slotB]))

        coordinator.handle(.generationFinished, for: slotA)
        coordinator.handle(.generationFinished, for: slotB)
        XCTAssertEqual(bridgeA.requestCount, 1)
        XCTAssertEqual(bridgeB.requestCount, 1)
        bridgeA.resolve(makePayload(responseID: "document-a:a", text: "A."))
        XCTAssertEqual(service.spoken, ["A."])
        bridgeB.resolve(makePayload(responseID: "document-b:b", text: "B."))
        XCTAssertEqual(service.spoken, ["A."])
        service.finish(token: service.spokenTokens[0])

        XCTAssertEqual(service.spoken, ["A.", "B."])
    }

    func testManualReadInvalidatesPendingAutomaticFromAnotherSlot() {
        let service = TestSpeechService()
        let slotA = UUID()
        let slotB = UUID()
        let bridgeA = TestResponseBridge()
        let bridgeB = TestResponseBridge()
        let webViewA = WKWebView()
        let webViewB = WKWebView()
        let coordinator = AssistantSpeechCoordinator(
            speechService: service,
            webViewProvider: { slotID in slotID == slotA ? webViewA : webViewB },
            responseBridgeProvider: { slotID in slotID == slotA ? bridgeA : bridgeB }
        )
        coordinator.toggleAutoSpeak(for: slotA)

        coordinator.handle(.generationFinished, for: slotA)
        coordinator.readLatestResponse(for: slotB)
        bridgeB.resolve(makePayload(responseID: "document-b:manual", text: "B manual."))
        XCTAssertEqual(service.spoken, ["B manual."])
        XCTAssertEqual(coordinator.currentSpeakingSlotID, slotB)

        bridgeA.resolve(makePayload(responseID: "document-a:stale", text: "A stale."))

        XCTAssertEqual(service.spoken, ["B manual."])
        XCTAssertEqual(coordinator.currentSpeakingSlotID, slotB)
    }

    func testAutomaticCompletionAfterManualReadQueuesBehindManualSpeech() {
        let service = TestSpeechService()
        let slotA = UUID()
        let slotB = UUID()
        let bridgeA = TestResponseBridge()
        let bridgeB = TestResponseBridge()
        let webViewA = WKWebView()
        let webViewB = WKWebView()
        let coordinator = AssistantSpeechCoordinator(
            speechService: service,
            webViewProvider: { slotID in slotID == slotA ? webViewA : webViewB },
            responseBridgeProvider: { slotID in slotID == slotA ? bridgeA : bridgeB }
        )
        coordinator.toggleAutoSpeak(for: slotA)

        coordinator.readLatestResponse(for: slotB)
        bridgeB.resolve(makePayload(responseID: "document-b:manual", text: "B manual."))
        let manualToken = service.spokenTokens[0]

        coordinator.handle(.generationFinished, for: slotA)
        bridgeA.resolve(makePayload(responseID: "document-a:new", text: "A automatic."))

        XCTAssertEqual(service.spoken, ["B manual."])
        service.finish(token: manualToken)
        XCTAssertEqual(service.spoken, ["B manual.", "A automatic."])
    }

    func testManualReadReplacesCurrentAndPendingAutomaticSpeech() {
        let service = TestSpeechService()
        let slotA = UUID()
        let slotB = UUID()
        let slotC = UUID()
        let bridgeA = TestResponseBridge()
        let bridgeB = TestResponseBridge()
        let bridgeC = TestResponseBridge()
        let webViewA = WKWebView()
        let webViewB = WKWebView()
        let webViewC = WKWebView()
        let coordinator = AssistantSpeechCoordinator(
            speechService: service,
            webViewProvider: { slotID in
                switch slotID {
                case slotA: return webViewA
                case slotB: return webViewB
                default: return webViewC
                }
            },
            responseBridgeProvider: { slotID in
                switch slotID {
                case slotA: return bridgeA
                case slotB: return bridgeB
                default: return bridgeC
                }
            }
        )
        coordinator.toggleAutoSpeak(for: slotA)
        coordinator.toggleAutoSpeak(for: slotB)

        coordinator.handle(.generationFinished, for: slotA)
        bridgeA.resolve(makePayload(responseID: "document-a:a", text: "A one. A two."))
        let staleToken = service.spokenTokens[0]
        coordinator.handle(.generationFinished, for: slotB)
        bridgeB.resolve(makePayload(responseID: "document-b:b", text: "B pending."))

        coordinator.readLatestResponse(for: slotC)
        bridgeC.resolve(makePayload(responseID: "document-c:c", text: "C manual."))

        XCTAssertEqual(service.spoken, ["A one.", "C manual."])
        XCTAssertEqual(coordinator.currentSpeakingSlotID, slotC)
        XCTAssertEqual(coordinator.pendingQueueCount, 0)

        service.finish(token: staleToken)
        XCTAssertEqual(service.spoken, ["A one.", "C manual."])
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

        XCTAssertTrue(coordinator.autoSpeakSlotIDs.isEmpty)
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
        XCTAssertEqual(coordinator.autoSpeakSlotIDs, Set([slotID]))
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
        XCTAssertEqual(coordinator.autoSpeakSlotIDs, Set([slotID]))
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
        XCTAssertEqual(coordinator.autoSpeakSlotIDs, Set([slotID]))

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

        XCTAssertEqual(coordinator.autoSpeakSlotIDs, Set([slotID]))
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

        XCTAssertTrue(coordinator.autoSpeakSlotIDs.isEmpty)
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

    func testPauseKeepsCurrentItemSourceAndAutoSpeakMembership() {
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
        bridge.resolve(makePayload(text: "Pause me."))
        let token = service.spokenTokens[0]

        XCTAssertTrue(coordinator.pauseCurrentSpeech(for: slotID))
        XCTAssertEqual(service.pauseCount, 1)
        XCTAssertEqual(coordinator.playbackState, .speaking)

        service.pause(token: token)
        XCTAssertEqual(coordinator.playbackState, .paused)
        XCTAssertEqual(coordinator.currentSpeakingSlotID, slotID)
        XCTAssertEqual(coordinator.currentResponseIdentity?.slotID, slotID)
        XCTAssertEqual(coordinator.pendingQueueCount, 0)
        XCTAssertEqual(coordinator.autoSpeakSlotIDs, Set([slotID]))

        XCTAssertFalse(coordinator.pauseCurrentSpeech(for: slotID))
        XCTAssertEqual(service.pauseCount, 1)
    }

    func testResumeKeepsSourceAndReturnsToSpeakingState() {
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
        bridge.resolve(makePayload(text: "Resume me."))
        let token = service.spokenTokens[0]
        XCTAssertTrue(coordinator.pauseCurrentSpeech(for: slotID))
        service.pause(token: token)

        XCTAssertTrue(coordinator.resumeCurrentSpeech(for: slotID))
        XCTAssertEqual(service.resumeCount, 1)
        XCTAssertEqual(coordinator.playbackState, .speaking)
        XCTAssertEqual(coordinator.currentSpeakingSlotID, slotID)
        XCTAssertEqual(coordinator.autoSpeakSlotIDs, Set([slotID]))

        service.continue(token: token)
        XCTAssertEqual(coordinator.playbackState, .speaking)
        XCTAssertFalse(coordinator.resumeCurrentSpeech(for: slotID))
        XCTAssertEqual(service.resumeCount, 1)
    }

    func testFinishWinsWhenPauseBoundaryArrivesLate() {
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
        bridge.resolve(makePayload(text: "Short."))
        let token = service.spokenTokens[0]

        XCTAssertTrue(coordinator.pauseCurrentSpeech(for: slotID))
        service.finish(token: token)
        service.pause(token: token)

        XCTAssertEqual(coordinator.playbackState, .idle)
        XCTAssertNil(coordinator.currentSpeakingSlotID)
        XCTAssertNil(coordinator.currentResponseIdentity)
    }

    func testStopWhilePausedClearsPlaybackButPreservesAutoSpeak() {
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
        bridge.resolve(makePayload(text: "Stop me."))
        let token = service.spokenTokens[0]
        XCTAssertTrue(coordinator.pauseCurrentSpeech(for: slotID))
        service.pause(token: token)

        coordinator.stop()

        XCTAssertEqual(service.stopCount, 1)
        XCTAssertEqual(coordinator.playbackState, .idle)
        XCTAssertNil(coordinator.currentSpeakingSlotID)
        XCTAssertNil(coordinator.currentResponseIdentity)
        XCTAssertEqual(coordinator.pendingQueueCount, 0)
        XCTAssertEqual(coordinator.autoSpeakSlotIDs, Set([slotID]))

        service.continue(token: token)
        service.finish(token: token)
        XCTAssertEqual(coordinator.playbackState, .idle)
        XCTAssertNil(coordinator.currentSpeakingSlotID)
    }

    func testPausedAutomaticStreamBlocksQueuedAutomaticPlaybackUntilResumeAndFinish() {
        let service = TestSpeechService()
        let slotA = UUID()
        let slotB = UUID()
        let bridgeA = TestResponseBridge()
        let bridgeB = TestResponseBridge()
        let webViewA = WKWebView()
        let webViewB = WKWebView()
        let coordinator = AssistantSpeechCoordinator(
            speechService: service,
            webViewProvider: { slotID in slotID == slotA ? webViewA : webViewB },
            responseBridgeProvider: { slotID in slotID == slotA ? bridgeA : bridgeB }
        )
        coordinator.toggleAutoSpeak(for: slotA)
        coordinator.toggleAutoSpeak(for: slotB)

        coordinator.handle(.generationFinished, for: slotA)
        bridgeA.resolve(makePayload(responseID: "document-a:a", text: "A."))
        let tokenA = service.spokenTokens[0]
        XCTAssertTrue(coordinator.pauseCurrentSpeech(for: slotA))
        service.pause(token: tokenA)

        coordinator.handle(.generationFinished, for: slotB)
        bridgeB.resolve(makePayload(responseID: "document-b:b", text: "B."))

        XCTAssertEqual(coordinator.playbackState, .paused)
        XCTAssertEqual(coordinator.currentSpeakingSlotID, slotA)
        XCTAssertEqual(service.spoken, ["A."])
        XCTAssertEqual(coordinator.pendingQueueCount, 1)

        XCTAssertTrue(coordinator.resumeCurrentSpeech(for: slotA))
        service.continue(token: tokenA)
        service.finish(token: tokenA)

        XCTAssertEqual(service.spoken, ["A.", "B."])
        XCTAssertEqual(coordinator.playbackState, .speaking)
        XCTAssertEqual(coordinator.currentSpeakingSlotID, slotB)
    }

    func testPausedFIFOKeepsAThenBThenCOrder() {
        let service = TestSpeechService()
        let slots = [UUID(), UUID(), UUID()]
        let bridges = [TestResponseBridge(), TestResponseBridge(), TestResponseBridge()]
        let webViews = [WKWebView(), WKWebView(), WKWebView()]
        let coordinator = AssistantSpeechCoordinator(
            speechService: service,
            webViewProvider: { slotID in
                guard let index = slots.firstIndex(of: slotID) else { return nil }
                return webViews[index]
            },
            responseBridgeProvider: { slotID in
                guard let index = slots.firstIndex(of: slotID) else { return nil }
                return bridges[index]
            }
        )
        slots.forEach { coordinator.toggleAutoSpeak(for: $0) }

        for (index, slotID) in slots.enumerated() {
            coordinator.handle(.generationFinished, for: slotID)
            bridges[index].resolve(
                makePayload(
                    responseID: "document-\(index):response",
                    text: "\(index)."
                )
            )
        }

        let firstToken = service.spokenTokens[0]
        XCTAssertTrue(coordinator.pauseCurrentSpeech(for: slots[0]))
        service.pause(token: firstToken)
        XCTAssertEqual(service.spoken, ["0."])
        XCTAssertEqual(coordinator.pendingQueueCount, 2)

        XCTAssertTrue(coordinator.resumeCurrentSpeech(for: slots[0]))
        service.continue(token: firstToken)
        service.finish(token: firstToken)
        let secondToken = service.spokenTokens[1]
        service.finish(token: secondToken)
        let thirdToken = service.spokenTokens[2]
        service.finish(token: thirdToken)

        XCTAssertEqual(service.spoken, ["0.", "1.", "2."])
    }

    func testManualReadOtherTabSupersedesPausedSourceWithoutChangingAutoMembership() {
        let service = TestSpeechService()
        let slotA = UUID()
        let slotB = UUID()
        let bridgeA = TestResponseBridge()
        let bridgeB = TestResponseBridge()
        let webViewA = WKWebView()
        let webViewB = WKWebView()
        let coordinator = AssistantSpeechCoordinator(
            speechService: service,
            webViewProvider: { slotID in slotID == slotA ? webViewA : webViewB },
            responseBridgeProvider: { slotID in slotID == slotA ? bridgeA : bridgeB }
        )
        coordinator.toggleAutoSpeak(for: slotA)
        coordinator.handle(.generationFinished, for: slotA)
        bridgeA.resolve(makePayload(responseID: "document-a:a", text: "A."))
        let tokenA = service.spokenTokens[0]
        XCTAssertTrue(coordinator.pauseCurrentSpeech(for: slotA))
        service.pause(token: tokenA)

        coordinator.readLatestResponse(for: slotB)
        bridgeB.resolve(makePayload(responseID: "document-b:b", text: "B manual."))

        XCTAssertEqual(service.spoken, ["A.", "B manual."])
        XCTAssertEqual(coordinator.currentSpeakingSlotID, slotB)
        XCTAssertEqual(coordinator.playbackState, .speaking)
        XCTAssertEqual(coordinator.autoSpeakSlotIDs, Set([slotA]))

        service.pause(token: tokenA)
        service.continue(token: tokenA)
        service.finish(token: tokenA)
        XCTAssertEqual(coordinator.currentSpeakingSlotID, slotB)
        XCTAssertEqual(coordinator.playbackState, .speaking)
    }

    func testAutoOffWhilePausedPreservesCurrentResponseForResume() {
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
        bridge.resolve(makePayload(text: "Keep me."))
        let token = service.spokenTokens[0]
        XCTAssertTrue(coordinator.pauseCurrentSpeech(for: slotID))
        service.pause(token: token)

        coordinator.toggleAutoSpeak(for: slotID)

        XCTAssertTrue(coordinator.autoSpeakSlotIDs.isEmpty)
        XCTAssertEqual(coordinator.playbackState, .paused)
        XCTAssertEqual(coordinator.currentSpeakingSlotID, slotID)
        XCTAssertEqual(coordinator.currentResponseIdentity?.slotID, slotID)

        XCTAssertTrue(coordinator.resumeCurrentSpeech(for: slotID))
        service.continue(token: token)
        service.finish(token: token)
        XCTAssertEqual(coordinator.playbackState, .idle)
        XCTAssertNil(coordinator.currentSpeakingSlotID)
    }

    func testRuntimeResetAndRemovalWhilePausedCannotResurrectPlayback() {
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
        bridge.resolve(makePayload(text: "Reset me."))
        let token = service.spokenTokens[0]
        XCTAssertTrue(coordinator.pauseCurrentSpeech(for: slotID))
        service.pause(token: token)

        coordinator.resetRuntime(slotID: slotID)

        XCTAssertEqual(coordinator.playbackState, .idle)
        XCTAssertNil(coordinator.currentSpeakingSlotID)
        XCTAssertEqual(coordinator.autoSpeakSlotIDs, Set([slotID]))
        XCTAssertEqual(coordinator.pendingQueueCount, 0)

        service.pause(token: token)
        service.continue(token: token)
        service.finish(token: token)
        XCTAssertEqual(coordinator.playbackState, .idle)
        XCTAssertNil(coordinator.currentSpeakingSlotID)

        coordinator.removeSlot(slotID: slotID)
        XCTAssertTrue(coordinator.autoSpeakSlotIDs.isEmpty)
    }

    func testPreviewSupersedesPausedResponseAndIgnoresLateCallbacks() {
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
        bridge.resolve(makePayload(text: "Response."))
        let responseToken = service.spokenTokens[0]
        XCTAssertTrue(coordinator.pauseCurrentSpeech(for: slotID))
        service.pause(token: responseToken)

        coordinator.playPreview(
            SpeechLanguageRouter.utteranceRequests(for: "Preview.")
        )
        let previewToken = service.spokenTokens[1]

        XCTAssertEqual(coordinator.playbackState, .speaking)
        XCTAssertNil(coordinator.currentSpeakingSlotID)
        XCTAssertNil(coordinator.currentResponseIdentity)

        service.pause(token: responseToken)
        service.continue(token: responseToken)
        service.finish(token: responseToken)
        XCTAssertEqual(coordinator.playbackState, .speaking)
        XCTAssertNil(coordinator.currentSpeakingSlotID)

        service.finish(token: previewToken)
        XCTAssertEqual(coordinator.playbackState, .idle)
    }

    func testPostManualAutomaticResolutionWaitsForManualAndThenContinues() {
        let service = TestSpeechService()
        let slotA = UUID()
        let slotB = UUID()
        let bridgeA = TestResponseBridge()
        let bridgeB = TestResponseBridge()
        let webViewA = WKWebView()
        let webViewB = WKWebView()
        let coordinator = AssistantSpeechCoordinator(
            speechService: service,
            webViewProvider: { slotID in slotID == slotA ? webViewA : webViewB },
            responseBridgeProvider: { slotID in slotID == slotA ? bridgeA : bridgeB }
        )
        coordinator.toggleAutoSpeak(for: slotA)

        coordinator.readLatestResponse(for: slotB)
        coordinator.handle(.generationFinished, for: slotA)
        bridgeA.resolve(makePayload(responseID: "document-a:auto", text: "Auto A."))

        XCTAssertTrue(service.spoken.isEmpty)
        XCTAssertTrue(coordinator.isManualPlaybackBarrierActive)

        bridgeB.resolve(makePayload(responseID: "document-b:manual", text: "Manual B."))
        XCTAssertEqual(service.spoken, ["Manual B."])
        XCTAssertEqual(coordinator.currentSpeakingSlotID, slotB)

        service.finish(token: service.spokenTokens[0])
        XCTAssertEqual(service.spoken, ["Manual B.", "Auto A."])
        XCTAssertFalse(coordinator.isManualPlaybackBarrierActive)
    }

    func testManualFailureReleasesBarrierForPostManualAutomatic() {
        let service = TestSpeechService()
        let slotA = UUID()
        let slotB = UUID()
        let bridgeA = TestResponseBridge()
        let bridgeB = TestResponseBridge()
        let webViewA = WKWebView()
        let webViewB = WKWebView()
        let coordinator = AssistantSpeechCoordinator(
            speechService: service,
            webViewProvider: { slotID in slotID == slotA ? webViewA : webViewB },
            responseBridgeProvider: { slotID in slotID == slotA ? bridgeA : bridgeB }
        )
        coordinator.toggleAutoSpeak(for: slotA)

        coordinator.readLatestResponse(for: slotB)
        coordinator.handle(.generationFinished, for: slotA)
        bridgeA.resolve(makePayload(responseID: "document-a:auto", text: "Auto A."))
        XCTAssertTrue(service.spoken.isEmpty)

        bridgeB.resolve(nil)

        XCTAssertEqual(service.spoken, ["Auto A."])
        XCTAssertFalse(coordinator.isManualPlaybackBarrierActive)
    }

    func testManualRuntimeResetReleasesBarrierWithoutDeadlock() {
        let service = TestSpeechService()
        let slotA = UUID()
        let slotB = UUID()
        let bridgeA = TestResponseBridge()
        let bridgeB = TestResponseBridge()
        let webViewA = WKWebView()
        let webViewB = WKWebView()
        let coordinator = AssistantSpeechCoordinator(
            speechService: service,
            webViewProvider: { slotID in slotID == slotA ? webViewA : webViewB },
            responseBridgeProvider: { slotID in slotID == slotA ? bridgeA : bridgeB }
        )
        coordinator.toggleAutoSpeak(for: slotA)

        coordinator.readLatestResponse(for: slotB)
        coordinator.handle(.generationFinished, for: slotA)
        bridgeA.resolve(makePayload(responseID: "document-a:auto", text: "Auto A."))
        coordinator.resetRuntime(slotID: slotB)

        XCTAssertEqual(service.spoken, ["Auto A."])
        XCTAssertFalse(coordinator.isManualPlaybackBarrierActive)
    }

    func testAutoOffInvalidatesPendingExtraction() {
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
        coordinator.toggleAutoSpeak(for: slotID)
        bridge.resolve(makePayload(text: "Must not speak."))

        XCTAssertTrue(service.spoken.isEmpty)
        XCTAssertTrue(coordinator.autoSpeakSlotIDs.isEmpty)
    }

    func testAutoOffRemovesQueuedAutomaticResponseButKeepsCurrentResponse() {
        let service = TestSpeechService()
        let slotA = UUID()
        let slotB = UUID()
        let bridgeA = TestResponseBridge()
        let bridgeB = TestResponseBridge()
        let webViewA = WKWebView()
        let webViewB = WKWebView()
        let coordinator = AssistantSpeechCoordinator(
            speechService: service,
            webViewProvider: { slotID in slotID == slotA ? webViewA : webViewB },
            responseBridgeProvider: { slotID in slotID == slotA ? bridgeA : bridgeB }
        )
        coordinator.toggleAutoSpeak(for: slotA)
        coordinator.toggleAutoSpeak(for: slotB)

        coordinator.handle(.generationFinished, for: slotB)
        bridgeB.resolve(makePayload(responseID: "document-b:current", text: "Current B."))
        let currentToken = service.spokenTokens[0]
        coordinator.handle(.generationFinished, for: slotA)
        bridgeA.resolve(makePayload(responseID: "document-a:queued", text: "Queued A."))
        coordinator.toggleAutoSpeak(for: slotA)

        service.finish(token: currentToken)

        XCTAssertEqual(service.spoken, ["Current B."])
    }

    func testAutoOffAllowsCurrentAutomaticResponseToFinishItsPendingSegments() {
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
        let firstToken = service.spokenTokens[0]
        coordinator.toggleAutoSpeak(for: slotID)

        service.finish(token: firstToken)

        XCTAssertEqual(service.spoken, ["One.", "Two."])
        XCTAssertEqual(coordinator.currentSpeakingSlotID, slotID)
    }

    func testAutoOffDoesNotCancelManualCurrentSpeech() {
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            service: service,
            bridge: bridge,
            webView: WKWebView()
        )
        coordinator.toggleAutoSpeak(for: slotID)
        coordinator.readLatestResponse(for: slotID)
        bridge.resolve(makePayload(responseID: "document-a:manual", text: "Manual."))
        let manualToken = service.spokenTokens[0]

        coordinator.toggleAutoSpeak(for: slotID)
        service.finish(token: manualToken)

        XCTAssertEqual(service.spoken, ["Manual."])
        XCTAssertTrue(coordinator.autoSpeakSlotIDs.isEmpty)
    }

    func testAutomaticPlaybackUsesGenerationAcceptanceFIFOWhenExtractionCompletesOutOfOrder() {
        let service = TestSpeechService()
        let slotA = UUID()
        let slotB = UUID()
        let bridgeA = TestResponseBridge()
        let bridgeB = TestResponseBridge()
        let webViewA = WKWebView()
        let webViewB = WKWebView()
        let coordinator = AssistantSpeechCoordinator(
            speechService: service,
            webViewProvider: { slotID in slotID == slotA ? webViewA : webViewB },
            responseBridgeProvider: { slotID in slotID == slotA ? bridgeA : bridgeB }
        )
        coordinator.toggleAutoSpeak(for: slotA)
        coordinator.toggleAutoSpeak(for: slotB)

        coordinator.handle(.generationFinished, for: slotA)
        coordinator.handle(.generationFinished, for: slotB)
        bridgeB.resolve(makePayload(responseID: "document-b:first-resolved", text: "B."))
        XCTAssertTrue(service.spoken.isEmpty)
        bridgeA.resolve(makePayload(responseID: "document-a:first-accepted", text: "A."))

        XCTAssertEqual(service.spoken, ["A."])
        service.finish(token: service.spokenTokens[0])
        XCTAssertEqual(service.spoken, ["A.", "B."])
    }

    func testAutomaticFIFOReleasesWhenEarlierExtractionFails() {
        let service = TestSpeechService()
        let slotA = UUID()
        let slotB = UUID()
        let bridgeA = TestResponseBridge()
        let bridgeB = TestResponseBridge()
        let webViewA = WKWebView()
        let webViewB = WKWebView()
        let coordinator = AssistantSpeechCoordinator(
            speechService: service,
            webViewProvider: { slotID in slotID == slotA ? webViewA : webViewB },
            responseBridgeProvider: { slotID in slotID == slotA ? bridgeA : bridgeB }
        )
        coordinator.toggleAutoSpeak(for: slotA)
        coordinator.toggleAutoSpeak(for: slotB)

        coordinator.handle(.generationFinished, for: slotA)
        coordinator.handle(.generationFinished, for: slotB)
        bridgeB.resolve(makePayload(responseID: "document-b:survivor", text: "B."))
        bridgeA.resolve(nil)

        XCTAssertEqual(service.spoken, ["B."])
    }

    func testAutoOffReleasesLaterAutomaticReservation() {
        let service = TestSpeechService()
        let slotA = UUID()
        let slotB = UUID()
        let bridgeA = TestResponseBridge()
        let bridgeB = TestResponseBridge()
        let webViewA = WKWebView()
        let webViewB = WKWebView()
        let coordinator = AssistantSpeechCoordinator(
            speechService: service,
            webViewProvider: { slotID in slotID == slotA ? webViewA : webViewB },
            responseBridgeProvider: { slotID in slotID == slotA ? bridgeA : bridgeB }
        )
        coordinator.toggleAutoSpeak(for: slotA)
        coordinator.toggleAutoSpeak(for: slotB)

        coordinator.handle(.generationFinished, for: slotA)
        coordinator.handle(.generationFinished, for: slotB)
        coordinator.toggleAutoSpeak(for: slotA)
        bridgeB.resolve(makePayload(responseID: "document-b:survivor", text: "B."))

        XCTAssertEqual(service.spoken, ["B."])
    }

    func testPreviewSharesStreamAndLateAutomaticFinishCannotAdvanceIt() {
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
        bridge.resolve(makePayload(text: "Automatic."))
        let automaticToken = service.spokenTokens[0]

        coordinator.playPreview([
            SpeechUtteranceRequest(text: "Preview.", languageRole: .english),
        ])
        let previewToken = service.spokenTokens[1]

        XCTAssertEqual(service.spoken, ["Automatic.", "Preview."])
        XCTAssertNil(coordinator.currentResponseIdentity)
        XCTAssertNil(coordinator.currentSpeakingSlotID)
        XCTAssertEqual(coordinator.autoSpeakSlotIDs, Set([slotID]))

        service.finish(token: automaticToken)
        XCTAssertEqual(service.spoken, ["Automatic.", "Preview."])
        service.finish(token: previewToken)
        XCTAssertNil(coordinator.currentResponseIdentity)

        coordinator.handle(.generationFinished, for: slotID)
        bridge.resolve(makePayload(responseID: "document-a:after-preview", text: "After preview."))
        XCTAssertEqual(service.spoken, ["Automatic.", "Preview.", "After preview."])
    }

    func testCoordinatorDropsPureSymbolPreviewRequestsAtQueueBoundary() {
        let service = TestSpeechService()
        let coordinator = makeCoordinator(
            service: service,
            bridge: TestResponseBridge(),
            webView: WKWebView()
        )

        coordinator.playPreview([
            SpeechUtteranceRequest(text: "......", languageRole: .english),
            SpeechUtteranceRequest(text: "Readable preview.", languageRole: .english),
        ])

        XCTAssertEqual(service.spoken, ["Readable preview."])
    }

    func testPreviewTransportTokenCannotCollideWithSupersededAutomaticToken() {
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
        bridge.resolve(makePayload(responseID: "document-a:auto", text: "Automatic."))
        let automaticToken = service.spokenTokens[0]

        coordinator.playPreview(SpeechLanguageRouter.utteranceRequests(for: "Preview."))
        let previewToken = service.spokenTokens[1]

        XCTAssertNotEqual(previewToken, automaticToken)
        service.finish(token: automaticToken)
        XCTAssertEqual(service.spoken, ["Automatic.", "Preview."])

        service.finish(token: previewToken)
        XCTAssertNil(coordinator.currentResponseIdentity)
    }

    func testPreviewToPreviewUsesUniqueTokensAndIgnoresFirstLateFinish() {
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        let coordinator = makeCoordinator(
            service: service,
            bridge: bridge,
            webView: WKWebView()
        )

        coordinator.playPreview(SpeechLanguageRouter.utteranceRequests(for: "Preview one."))
        let previewOneToken = service.spokenTokens[0]

        coordinator.playPreview(
            SpeechLanguageRouter.utteranceRequests(for: "Preview two. Second segment.")
        )
        let previewTwoToken = service.spokenTokens[1]
        XCTAssertNotEqual(previewOneToken, previewTwoToken)

        service.finish(token: previewOneToken)
        XCTAssertEqual(service.spoken, ["Preview one.", "Preview two."])

        service.finish(token: previewTwoToken)
        XCTAssertEqual(service.spoken, ["Preview one.", "Preview two.", "Second segment."])
        service.finish(token: service.spokenTokens[2])
        XCTAssertNil(coordinator.currentResponseIdentity)
    }

    func testMultiSegmentPreviewUsesUniqueCoordinatorTokensAndIgnoresDuplicateFinish() {
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        let coordinator = makeCoordinator(
            service: service,
            bridge: bridge,
            webView: WKWebView()
        )
        let requests = SpeechLanguageRouter.utteranceRequests(
            for: "第一句。This is the second sentence.第三句。"
        )

        coordinator.playPreview(requests)
        let firstToken = service.spokenTokens[0]
        XCTAssertEqual(service.spokenLanguageRoles, [.chinese])

        service.finish(token: firstToken)
        let secondToken = service.spokenTokens[1]
        service.finish(token: firstToken)
        XCTAssertEqual(service.spoken, ["第一句。", "This is the second sentence."])

        service.finish(token: secondToken)
        let thirdToken = service.spokenTokens[2]
        XCTAssertEqual(Set([firstToken, secondToken, thirdToken]).count, 3)
        XCTAssertEqual(service.spokenLanguageRoles, [.chinese, .english, .chinese])

        service.finish(token: thirdToken)
        XCTAssertNil(coordinator.currentResponseIdentity)
    }

    func testAutomaticManualPreviewAndAutomaticTokensShareOneNamespace() {
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
        bridge.resolve(makePayload(responseID: "document-a:auto-1", text: "Automatic one."))
        let automaticOneToken = service.spokenTokens[0]

        coordinator.readLatestResponse(for: slotID)
        bridge.resolve(makePayload(responseID: "document-a:manual", text: "Manual."))
        let manualToken = service.spokenTokens[1]

        coordinator.playPreview(SpeechLanguageRouter.utteranceRequests(for: "Preview."))
        let previewToken = service.spokenTokens[2]

        coordinator.handle(.generationFinished, for: slotID)
        bridge.resolve(makePayload(responseID: "document-a:auto-2", text: "Automatic two."))
        service.finish(token: previewToken)
        let automaticTwoToken = service.spokenTokens[3]

        XCTAssertEqual(
            service.spokenTokens,
            [automaticOneToken, manualToken, previewToken, automaticTwoToken]
        )
        XCTAssertEqual(Set(service.spokenTokens).count, service.spokenTokens.count)
    }

    func testFollowScrollsActiveBlockOnceAcrossSegmentsAndThenFollowsNextBlock() {
        let service = TestSpeechService()
        let responseBridge = TestResponseBridge()
        let followBridge = TestFollowBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            service: service,
            bridge: responseBridge,
            webView: WKWebView(),
            followBridge: followBridge,
            activeSlotIDProvider: { slotID }
        )
        coordinator.toggleAutoSpeak(for: slotID)
        coordinator.handle(.generationFinished, for: slotID)
        responseBridge.resolve(makeFollowPayload(blocks: [
            SpeechContentBlock(
                kind: .paragraph,
                text: "First sentence. Second sentence. Third sentence.",
                level: nil
            ),
            SpeechContentBlock(kind: .paragraph, text: "Next block.", level: nil),
        ]))

        XCTAssertEqual(service.spoken, ["First sentence."])
        XCTAssertEqual(followBridge.locators.map(\.blockID), [
            "document-a-follow:response-a:block-0",
        ])

        service.finish(token: service.spokenTokens[0])
        XCTAssertEqual(followBridge.locators.count, 1)
        service.finish(token: service.spokenTokens[1])
        XCTAssertEqual(followBridge.locators.count, 1)
        service.finish(token: service.spokenTokens[2])

        XCTAssertEqual(service.spoken, [
            "First sentence.",
            "Second sentence.",
            "Third sentence.",
            "Next block.",
        ])
        XCTAssertEqual(followBridge.locators.map(\.blockID), [
            "document-a-follow:response-a:block-0",
            "document-a-follow:response-a:block-1",
        ])
    }

    func testFollowScrollsPreformattedRichTextOnceAcrossLineSegments() {
        let service = TestSpeechService()
        let responseBridge = TestResponseBridge()
        let followBridge = TestFollowBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            service: service,
            bridge: responseBridge,
            webView: WKWebView(),
            followBridge: followBridge,
            activeSlotIDProvider: { slotID }
        )
        coordinator.readLatestResponse(for: slotID)
        responseBridge.resolve(makeFollowPayload(blocks: [
            SpeechContentBlock(
                kind: .richText,
                text: "This is the first line.\n这是第二行。\nThis is the third line.",
                level: nil
            ),
        ]))

        XCTAssertEqual(followBridge.locators.map(\.blockID), [
            "document-a-follow:response-a:block-0",
        ])
        service.finish(token: service.spokenTokens[0])
        service.finish(token: service.spokenTokens[1])
        service.finish(token: service.spokenTokens[2])
        XCTAssertEqual(service.spoken, [
            "This is the first line.",
            "这是第二行。",
            "This is the third line.",
        ])
        XCTAssertEqual(followBridge.locators.map(\.blockID), [
            "document-a-follow:response-a:block-0",
        ])
    }

    func testFollowPreservesMathRichAndComplexFallbackLocators() {
        let service = TestSpeechService()
        let responseBridge = TestResponseBridge()
        let followBridge = TestFollowBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            service: service,
            bridge: responseBridge,
            webView: WKWebView(),
            followBridge: followBridge,
            activeSlotIDProvider: { slotID }
        )
        coordinator.readLatestResponse(for: slotID)
        responseBridge.resolve(makeFollowPayload(blocks: [
            SpeechContentBlock(kind: .mathBlock, text: "x^2 + y^2 = 25", level: nil),
            SpeechContentBlock(
                kind: .richText,
                text: "A boxed explanation.",
                level: nil
            ),
            SpeechContentBlock(
                kind: .mathBlock,
                text: "\\begin{cases}x & x > 0\\end{cases}",
                level: nil
            ),
        ]))

        XCTAssertEqual(followBridge.locators.map(\.blockID), [
            "document-a-follow:response-a:block-0",
        ])
        XCTAssertFalse(service.spoken[0].contains("\\"))

        service.finish(token: service.spokenTokens[0])
        XCTAssertEqual(followBridge.locators.map(\.blockID), [
            "document-a-follow:response-a:block-0",
            "document-a-follow:response-a:block-1",
        ])
        service.finish(token: service.spokenTokens[1])
        XCTAssertEqual(followBridge.locators.map(\.blockID), [
            "document-a-follow:response-a:block-0",
            "document-a-follow:response-a:block-1",
            "document-a-follow:response-a:block-2",
        ])
        XCTAssertEqual(service.spoken[2], "There is a complex formula here.")
    }

    func testBackgroundSpeechDoesNotFollowUntilUserReturnsToSpeakingTab() {
        let service = TestSpeechService()
        let responseBridge = TestResponseBridge()
        let followBridge = TestFollowBridge()
        let slotA = UUID()
        let slotB = UUID()
        var activeSlotID: UUID? = slotB
        let coordinator = makeCoordinator(
            service: service,
            bridge: responseBridge,
            webView: WKWebView(),
            followBridge: followBridge,
            activeSlotIDProvider: { activeSlotID }
        )
        coordinator.toggleAutoSpeak(for: slotA)
        coordinator.handle(.generationFinished, for: slotA)
        responseBridge.resolve(makeFollowPayload(blocks: [
            SpeechContentBlock(kind: .paragraph, text: "Background.", level: nil),
        ]))

        XCTAssertTrue(followBridge.locators.isEmpty)
        XCTAssertEqual(coordinator.currentSpeakingSlotID, slotA)

        activeSlotID = slotA
        coordinator.handleActiveTabChange(to: slotA)
        XCTAssertEqual(followBridge.locators.count, 1)
        XCTAssertEqual(followBridge.locators[0].blockID, "document-a-follow:response-a:block-0")
    }

    func testManualScrollSuspendsFollowAndResumeRestoresOnlyForNextBlock() {
        let service = TestSpeechService()
        let responseBridge = TestResponseBridge()
        let followBridge = TestFollowBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            service: service,
            bridge: responseBridge,
            webView: WKWebView(),
            followBridge: followBridge,
            activeSlotIDProvider: { slotID }
        )
        coordinator.readLatestResponse(for: slotID)
        responseBridge.resolve(makeFollowPayload(blocks: [
            SpeechContentBlock(kind: .paragraph, text: "P.", level: nil),
            SpeechContentBlock(kind: .paragraph, text: "Q.", level: nil),
            SpeechContentBlock(kind: .paragraph, text: "R.", level: nil),
        ]))
        XCTAssertEqual(followBridge.locators.count, 1)

        coordinator.handleManualScroll(for: slotID, documentToken: "document-a-follow")
        XCTAssertTrue(coordinator.isFollowSuspendedForCurrentSpeech)
        service.finish(token: service.spokenTokens[0])
        XCTAssertEqual(followBridge.locators.count, 1)
        XCTAssertEqual(service.spoken, ["P.", "Q."])

        let qToken = service.spokenTokens[1]
        XCTAssertTrue(coordinator.pauseCurrentSpeech(for: slotID))
        service.pause(token: qToken)
        XCTAssertEqual(coordinator.playbackState, .paused)
        XCTAssertTrue(coordinator.resumeCurrentSpeech(for: slotID))
        XCTAssertEqual(coordinator.playbackState, .speaking)
        XCTAssertEqual(followBridge.locators.count, 1)

        service.finish(token: qToken)
        XCTAssertEqual(service.spoken, ["P.", "Q.", "R."])
        XCTAssertEqual(followBridge.locators.count, 2)
        XCTAssertFalse(coordinator.isFollowSuspendedForCurrentSpeech)
    }

    func testProgrammaticFollowDoesNotSelfSuspend() {
        let service = TestSpeechService()
        let responseBridge = TestResponseBridge()
        let followBridge = TestFollowBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            service: service,
            bridge: responseBridge,
            webView: WKWebView(),
            followBridge: followBridge,
            activeSlotIDProvider: { slotID }
        )
        coordinator.readLatestResponse(for: slotID)
        responseBridge.resolve(makeFollowPayload(blocks: [
            SpeechContentBlock(kind: .paragraph, text: "P.", level: nil),
            SpeechContentBlock(kind: .paragraph, text: "Q.", level: nil),
        ]))

        XCTAssertFalse(coordinator.isFollowSuspendedForCurrentSpeech)
        service.finish(token: service.spokenTokens[0])
        XCTAssertEqual(followBridge.locators.count, 2)
        XCTAssertFalse(coordinator.isFollowSuspendedForCurrentSpeech)
    }

    func testFollowSettingOffBlocksScrollAndOnResumesOnNextBlock() {
        let service = TestSpeechService()
        let responseBridge = TestResponseBridge()
        let followBridge = TestFollowBridge()
        let slotID = UUID()
        var followEnabled = false
        let coordinator = makeCoordinator(
            service: service,
            bridge: responseBridge,
            webView: WKWebView(),
            followBridge: followBridge,
            activeSlotIDProvider: { slotID },
            followSpeechEnabled: { followEnabled }
        )
        coordinator.readLatestResponse(for: slotID)
        responseBridge.resolve(makeFollowPayload(blocks: [
            SpeechContentBlock(kind: .paragraph, text: "P.", level: nil),
            SpeechContentBlock(kind: .paragraph, text: "Q.", level: nil),
            SpeechContentBlock(kind: .paragraph, text: "R.", level: nil),
        ]))
        XCTAssertTrue(followBridge.locators.isEmpty)

        followEnabled = true
        service.finish(token: service.spokenTokens[0])
        XCTAssertEqual(followBridge.locators.count, 1)
        XCTAssertEqual(followBridge.locators[0].blockID, "document-a-follow:response-a:block-1")
    }

    func testStopAndNewManualReadClearFollowSuspension() {
        let service = TestSpeechService()
        let responseBridge = TestResponseBridge()
        let followBridge = TestFollowBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            service: service,
            bridge: responseBridge,
            webView: WKWebView(),
            followBridge: followBridge,
            activeSlotIDProvider: { slotID }
        )
        coordinator.readLatestResponse(for: slotID)
        responseBridge.resolve(makeFollowPayload(blocks: [
            SpeechContentBlock(kind: .paragraph, text: "Old.", level: nil),
        ]))
        coordinator.handleManualScroll(for: slotID, documentToken: "document-a-follow")
        XCTAssertTrue(coordinator.isFollowSuspendedForCurrentSpeech)

        coordinator.stop()
        coordinator.readLatestResponse(for: slotID)
        responseBridge.resolve(makeFollowPayload(
            responseID: "document-a-follow:response-new",
            blocks: [SpeechContentBlock(kind: .paragraph, text: "New.", level: nil)]
        ))

        XCTAssertEqual(followBridge.locators.map(\.responseID), [
            "document-a-follow:response-a",
            "document-a-follow:response-new",
        ])
        XCTAssertFalse(coordinator.isFollowSuspendedForCurrentSpeech)
    }

    func testFollowLocatorSurvivesNewerResponseInSameSlotFIFO() {
        let service = TestSpeechService()
        let responseBridge = TestResponseBridge()
        let followBridge = TestFollowBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            service: service,
            bridge: responseBridge,
            webView: WKWebView(),
            followBridge: followBridge,
            activeSlotIDProvider: { slotID }
        )
        coordinator.toggleAutoSpeak(for: slotID)

        coordinator.handle(.generationFinished, for: slotID)
        responseBridge.resolve(makeFollowPayload(
            responseID: "document-a-follow:response-one",
            blocks: [
                SpeechContentBlock(kind: .paragraph, text: "R1 first.", level: nil),
                SpeechContentBlock(kind: .paragraph, text: "R1 second.", level: nil),
            ]
        ))
        let firstToken = service.spokenTokens[0]
        coordinator.handle(.generationFinished, for: slotID)
        responseBridge.resolve(makeFollowPayload(
            responseID: "document-a-follow:response-two",
            blocks: [SpeechContentBlock(kind: .paragraph, text: "R2 first.", level: nil)]
        ))

        XCTAssertEqual(followBridge.locators.map(\.responseID), [
            "document-a-follow:response-one",
        ])
        service.finish(token: firstToken)
        XCTAssertEqual(service.spoken, ["R1 first.", "R1 second."])
        service.finish(token: service.spokenTokens[1])
        XCTAssertEqual(service.spoken, ["R1 first.", "R1 second.", "R2 first."])
        XCTAssertEqual(followBridge.locators.map(\.responseID), [
            "document-a-follow:response-one",
            "document-a-follow:response-one",
            "document-a-follow:response-two",
        ])
    }

    func testNaturalEndResetsSuspensionForLaterResponseInSameSlot() {
        let service = TestSpeechService()
        let responseBridge = TestResponseBridge()
        let followBridge = TestFollowBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            service: service,
            bridge: responseBridge,
            webView: WKWebView(),
            followBridge: followBridge,
            activeSlotIDProvider: { slotID }
        )
        coordinator.toggleAutoSpeak(for: slotID)

        coordinator.handle(.generationFinished, for: slotID)
        responseBridge.resolve(makeFollowPayload(
            responseID: "document-a-follow:response-one",
            blocks: [SpeechContentBlock(kind: .paragraph, text: "R1.", level: nil)]
        ))
        coordinator.handleManualScroll(for: slotID, documentToken: "document-a-follow")
        service.finish(token: service.spokenTokens[0])
        XCTAssertFalse(coordinator.isFollowSuspendedForCurrentSpeech)

        coordinator.handle(.generationFinished, for: slotID)
        responseBridge.resolve(makeFollowPayload(
            responseID: "document-a-follow:response-two",
            blocks: [SpeechContentBlock(kind: .paragraph, text: "R2.", level: nil)]
        ))
        XCTAssertEqual(followBridge.locators.map(\.responseID), [
            "document-a-follow:response-one",
            "document-a-follow:response-two",
        ])
    }

    func testContinuousSameSlotQueuePreservesSuspensionUntilStreamEnds() {
        let service = TestSpeechService()
        let responseBridge = TestResponseBridge()
        let followBridge = TestFollowBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            service: service,
            bridge: responseBridge,
            webView: WKWebView(),
            followBridge: followBridge,
            activeSlotIDProvider: { slotID }
        )
        coordinator.toggleAutoSpeak(for: slotID)

        coordinator.handle(.generationFinished, for: slotID)
        responseBridge.resolve(makeFollowPayload(
            responseID: "document-a-follow:response-one",
            blocks: [SpeechContentBlock(kind: .paragraph, text: "R1.", level: nil)]
        ))
        coordinator.handle(.generationFinished, for: slotID)
        responseBridge.resolve(makeFollowPayload(
            responseID: "document-a-follow:response-two",
            blocks: [SpeechContentBlock(kind: .paragraph, text: "R2.", level: nil)]
        ))
        coordinator.handleManualScroll(for: slotID, documentToken: "document-a-follow")

        service.finish(token: service.spokenTokens[0])
        XCTAssertEqual(service.spoken, ["R1.", "R2."])
        XCTAssertTrue(coordinator.isFollowSuspendedForCurrentSpeech)
        XCTAssertEqual(followBridge.locators.count, 1)

        service.finish(token: service.spokenTokens[1])
        XCTAssertFalse(coordinator.isFollowSuspendedForCurrentSpeech)
    }

    func testCrossSlotTransitionReleasesOldSlotSuspension() {
        let service = TestSpeechService()
        let responseBridge = TestResponseBridge()
        let followBridge = TestFollowBridge()
        let slotA = UUID()
        let slotB = UUID()
        var activeSlotID: UUID? = slotA
        let coordinator = makeCoordinator(
            service: service,
            bridge: responseBridge,
            webView: WKWebView(),
            followBridge: followBridge,
            activeSlotIDProvider: { activeSlotID }
        )
        coordinator.toggleAutoSpeak(for: slotA)
        coordinator.toggleAutoSpeak(for: slotB)

        coordinator.handle(.generationFinished, for: slotA)
        responseBridge.resolve(makeFollowPayload(
            documentToken: "document-a",
            responseID: "document-a:response-a",
            blocks: [SpeechContentBlock(kind: .paragraph, text: "A1.", level: nil)]
        ))
        coordinator.handleManualScroll(for: slotA, documentToken: "document-a")

        coordinator.handle(.generationFinished, for: slotB)
        responseBridge.resolve(makeFollowPayload(
            documentToken: "document-b",
            responseID: "document-b:response-b",
            blocks: [SpeechContentBlock(kind: .paragraph, text: "B1.", level: nil)]
        ))
        activeSlotID = slotB
        service.finish(token: service.spokenTokens[0])
        XCTAssertEqual(coordinator.currentSpeakingSlotID, slotB)

        service.finish(token: service.spokenTokens[1])
        activeSlotID = slotA
        coordinator.handle(.generationFinished, for: slotA)
        responseBridge.resolve(makeFollowPayload(
            documentToken: "document-a",
            responseID: "document-a:response-a-two",
            blocks: [SpeechContentBlock(kind: .paragraph, text: "A2.", level: nil)]
        ))

        XCTAssertEqual(followBridge.locators.last?.responseID, "document-a:response-a-two")
    }

    func testMANUAL_100_SEGMENTS_NO_LOSS() {
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        let coordinator = makeCoordinator(
            service: service,
            bridge: bridge,
            webView: WKWebView()
        )

        coordinator.readLatestResponse(for: UUID())
        bridge.resolve(makePayload(
            responseID: "document-a:manual-100",
            text: makeLongResponseText(prefix: "Manual", count: 100)
        ))
        finishEverySpokenRequest(service)

        XCTAssertEqual(service.spoken.count, 100)
        XCTAssertEqual(service.spoken.first, "Manual segment 1.")
        XCTAssertEqual(service.spoken.last, "Manual segment 100.")
    }

    func testAUTO_100_SEGMENTS_NO_LOSS() {
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
        XCTAssertEqual(
            SpeechLanguageRouter.utteranceRequests(for: [
                SpeechContentBlock(
                    kind: .paragraph,
                    text: makeLongResponseText(prefix: "Auto", count: 100),
                    level: nil
                ),
            ]).count,
            100
        )
        bridge.resolve(makePayload(
            responseID: "document-a:auto-100",
            text: makeLongResponseText(prefix: "Auto", count: 100)
        ))
        finishEverySpokenRequest(service)

        XCTAssertEqual(service.spoken.count, 100)
        XCTAssertEqual(service.spoken.first, "Auto segment 1.")
        XCTAssertEqual(service.spoken.last, "Auto segment 100.")
    }

    func testR1_100_THEN_R2_10_FIFO() {
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
        bridge.resolve(makePayload(
            responseID: "document-a:auto-r1",
            text: makeLongResponseText(prefix: "R1", count: 100)
        ))
        coordinator.handle(.generationFinished, for: slotID)
        bridge.resolve(makePayload(
            responseID: "document-a:auto-r2",
            text: makeLongResponseText(prefix: "R2", count: 10)
        ))
        finishEverySpokenRequest(service)

        XCTAssertEqual(service.spoken.count, 110)
        XCTAssertEqual(Array(service.spoken.prefix(100)), (1...100).map { "R1 segment \($0)." })
        XCTAssertEqual(Array(service.spoken.suffix(10)), (1...10).map { "R2 segment \($0)." })
    }

    func testPAUSE_AT_30_RESUME_TO_100() {
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            service: service,
            bridge: bridge,
            webView: WKWebView()
        )

        coordinator.readLatestResponse(for: slotID)
        bridge.resolve(makePayload(
            responseID: "document-a:manual-pause-100",
            text: makeLongResponseText(prefix: "Pause", count: 100)
        ))
        for index in 0..<29 {
            service.finish(token: service.spokenTokens[index])
        }
        let pausedToken = service.spokenTokens[29]
        XCTAssertTrue(coordinator.pauseCurrentSpeech(for: slotID))
        service.pause(token: pausedToken)
        XCTAssertEqual(service.spoken.count, 30)

        XCTAssertTrue(coordinator.resumeCurrentSpeech(for: slotID))
        finishEverySpokenRequest(service)
        XCTAssertEqual(service.spoken.count, 100)
        XCTAssertEqual(service.spoken.last, "Pause segment 100.")
    }

    func testSTOP_AT_30_DOES_NOT_CONTINUE() {
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            service: service,
            bridge: bridge,
            webView: WKWebView()
        )

        coordinator.readLatestResponse(for: slotID)
        bridge.resolve(makePayload(
            responseID: "document-a:manual-stop-100",
            text: makeLongResponseText(prefix: "Stop", count: 100)
        ))
        for index in 0..<29 {
            service.finish(token: service.spokenTokens[index])
        }
        let stoppedToken = service.spokenTokens[29]
        coordinator.stop()
        service.finish(token: stoppedToken)

        XCTAssertEqual(service.spoken.count, 30)
        XCTAssertNil(coordinator.currentResponseIdentity)
    }

    func testMANUAL_SUPERSEDE_DROPS_OLD_REMAINDER() {
        let service = TestSpeechService()
        let bridge = TestResponseBridge()
        let slotID = UUID()
        let coordinator = makeCoordinator(
            service: service,
            bridge: bridge,
            webView: WKWebView()
        )

        coordinator.readLatestResponse(for: slotID)
        bridge.resolve(makePayload(
            responseID: "document-a:manual-old",
            text: makeLongResponseText(prefix: "Old", count: 100)
        ))
        let oldFirstToken = service.spokenTokens[0]
        coordinator.readLatestResponse(for: slotID)
        bridge.resolve(makePayload(
            responseID: "document-a:manual-new",
            text: makeLongResponseText(prefix: "New", count: 3)
        ))
        finishEverySpokenRequest(service)
        service.finish(token: oldFirstToken)

        XCTAssertTrue(service.spoken.allSatisfy { !$0.hasPrefix("Old") || $0 == "Old segment 1." })
        XCTAssertEqual(Array(service.spoken.suffix(3)), [
            "New segment 1.", "New segment 2.", "New segment 3.",
        ])
    }

    func testAUTO_OFF_PRESERVES_STARTED_RESPONSE_REMAINDER() {
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
        bridge.resolve(makePayload(
            responseID: "document-a:auto-off-100",
            text: makeLongResponseText(prefix: "Started", count: 100)
        ))
        let firstToken = service.spokenTokens[0]
        coordinator.toggleAutoSpeak(for: slotID)
        finishEverySpokenRequest(service)
        service.finish(token: firstToken)

        XCTAssertEqual(service.spoken.count, 100)
        XCTAssertEqual(service.spoken.last, "Started segment 100.")
    }
}
