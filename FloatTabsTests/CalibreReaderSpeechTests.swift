import WebKit
import XCTest
@testable import FloatTabs

@MainActor
private final class CalibreTestSpeechService: SpeechSynthesizing {
    private(set) var spokenRequests: [SpeechPlaybackRequest] = []
    private(set) var stopCount = 0

    var onUtteranceStarted: ((UInt64) -> Void)?
    var onUtteranceFinished: ((UInt64) -> Void)?
    var onUtterancePaused: ((UInt64) -> Void)?
    var onUtteranceContinued: ((UInt64) -> Void)?
    var onUtteranceCancelled: ((UInt64) -> Void)?

    func speak(_ request: SpeechPlaybackRequest) {
        spokenRequests.append(request)
    }

    func pause() -> Bool { true }
    func resume() -> Bool { true }
    func stop() { stopCount += 1 }

    func emitStart() {
        guard let token = spokenRequests.last?.transportToken else { return }
        onUtteranceStarted?(token)
    }

    func emitFinish() {
        guard let token = spokenRequests.last?.transportToken else { return }
        onUtteranceFinished?(token)
    }
}

@MainActor
private final class CalibreTestReaderBridge: CalibreReaderAccess {
    let slotID: UUID
    var currentDocumentIdentity: CalibreReaderDocumentIdentity?
    var isReaderCandidate = true
    var onRelocation: ((CalibreReaderRelocation) -> Void)?
    var currentPage: CalibreReaderPage
    private(set) var extractionCount = 0
    private(set) var advanceCount = 0
    private var pendingTransitionToken: UInt64?

    init(slotID: UUID, pages: [CalibreReaderPage]) {
        self.slotID = slotID
        self.currentPage = pages[0]
        self.currentDocumentIdentity = pages[0].identity.document
    }

    func detectCurrentReader(completion: @escaping (Bool) -> Void) {
        completion(isReaderCandidate)
    }

    func extractCurrentReadingUnit(
        completion: @escaping (Result<CalibreReaderPage, Error>) -> Void
    ) {
        extractionCount += 1
        completion(.success(currentPage))
    }

    func requestAdvance(
        from identity: CalibreReadingUnitIdentity,
        transitionToken: UInt64,
        completion: @escaping (Bool) -> Void
    ) {
        guard identity == currentPage.identity else {
            completion(false)
            return
        }
        advanceCount += 1
        pendingTransitionToken = transitionToken
        completion(true)
    }

    func cancelPendingWork() {
        pendingTransitionToken = nil
    }

    func emitRelocation(
        _ page: CalibreReaderPage,
        token: UInt64? = nil,
        usePendingTransitionToken: Bool = true
    ) {
        currentPage = page
        currentDocumentIdentity = page.identity.document
        onRelocation?(
            CalibreReaderRelocation(
                identity: page.identity,
                transitionToken: usePendingTransitionToken
                    ? token ?? pendingTransitionToken
                    : token
            )
        )
        pendingTransitionToken = nil
    }
}

@MainActor
private final class CalibreStubSpeechSource: SpeechSourceAdapter {
    let kind: SpeechSourceKind = .chatGPT
    let slotID: UUID
    var readCount = 0
    var globalStopCount = 0
    var presentation: SpeechSourcePresentation {
        SpeechSourcePresentation(
            sourceKind: kind,
            activeSlotID: slotID,
            autoSpeakSlotIDs: [],
            activeSlotAutoSpeakEnabled: false,
            currentSpeakingSlotID: nil,
            playbackState: .idle,
            activeSlotSupportsSpeech: true
        )
    }

    init(slotID: UUID) { self.slotID = slotID }
    func supportsSpeech(slotID: UUID) -> Bool { slotID == self.slotID }
    func isAutoSpeakArmed(slotID: UUID) -> Bool { false }
    func readLatest(slotID: UUID) -> Bool { readCount += 1; return true }
    func replayLatest(slotID: UUID) -> Bool { true }
    func pause(slotID: UUID) -> Bool { false }
    func resume(slotID: UUID) -> Bool { false }
    func stop(slotID: UUID) -> Bool { false }
    func stopCurrentPlayback() -> Bool { globalStopCount += 1; return true }
    func toggleAutoSpeak(slotID: UUID) -> Bool { false }
    func playPreview(_ requests: [SpeechUtteranceRequest]) {}
}

@MainActor
private final class CalibreTestResponseBridge: ChatGPTResponseExtracting {
    private(set) var requestCount = 0

    func extractLatest(completion: @escaping @MainActor (ChatGPTResponsePayload?) -> Void) {
        requestCount += 1
    }
}

@MainActor
final class CalibreReaderSpeechTests: XCTestCase {
    private let slotID = UUID()

    private func document(generation: UInt64 = 1) -> CalibreReaderDocumentIdentity {
        let url = URL(string: "https://reader.example.test/read/7/epub")!
        return CalibreReaderDocumentIdentity(
            slotID: slotID,
            documentGeneration: generation,
            committedURL: url,
            origin: URL(string: "https://reader.example.test")!,
            readerKind: .epub
        )
    }

    private func page(
        document: CalibreReaderDocumentIdentity,
        start: String,
        end: String,
        text: String,
        atEnd: Bool = false
    ) -> CalibreReaderPage {
        CalibreReaderPage(
            identity: CalibreReadingUnitIdentity(
                document: document,
                startCFI: start,
                endCFI: end
            ),
            text: text,
            isAtEnd: atEnd
        )
    }

    private func makeCoordinator(
        bridge: CalibreTestReaderBridge,
        service: CalibreTestSpeechService
    ) -> (CalibreSpeechCoordinator, SpeechPlaybackSessionController) {
        let session = SpeechPlaybackSessionController(speechService: service)
        let coordinator = CalibreSpeechCoordinator(
            playbackSession: session,
            bridgeProvider: { id in id == bridge.slotID ? bridge : nil }
        )
        _ = CalibreSpeechSourceAdapter(
            coordinator: coordinator,
            playbackSession: session,
            activeSlotIDProvider: { bridge.slotID }
        )
        return (coordinator, session)
    }

    func testRouteMatcherAcceptsOnlyEPUBAndKEPUBReaderTail() {
        XCTAssertEqual(
            CalibreReaderRouteMatcher.readerKind(
                for: URL(string: "https://host.test/prefix/read/42/epub?x=1")
            ),
            .epub
        )
        XCTAssertEqual(
            CalibreReaderRouteMatcher.readerKind(
                for: URL(string: "http://host.test/read/42/kepub")
            ),
            .kepub
        )
        XCTAssertNil(CalibreReaderRouteMatcher.readerKind(
            for: URL(string: "https://host.test/read/42/pdf")
        ))
        XCTAssertNil(CalibreReaderRouteMatcher.readerKind(
            for: URL(string: "https://host.test/read/42/epub/extra")
        ))
        XCTAssertNil(CalibreReaderRouteMatcher.readerKind(
            for: URL(string: "https://host.test/read/no-id/epub")
        ))
    }

    func testCommittedOriginContainsOnlySchemeHostAndPort() {
        XCTAssertEqual(
            CalibreReaderRouteMatcher.committedOrigin(
                for: URL(string: "HTTPS://Reader.Example:8443/read/1/epub?q=1")!
            ),
            URL(string: "https://reader.example:8443")
        )
    }

    func testCalibreTextNormalizationPreservesBookContentAndLineBreaks() {
        XCTAssertEqual(
            CalibreReaderTextNormalizer.normalize(
                "  First\u{00AD} line  \r\n\tSecond\u{200B} line.  "
            ),
            "First line\nSecond line."
        )
    }

    func testReaderCandidateMustBeRuntimeBackedBeforeAcquiringLease() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "Page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first])
        bridge.isReaderCandidate = false
        let service = CalibreTestSpeechService()
        let (coordinator, session) = makeCoordinator(bridge: bridge, service: service)

        XCTAssertFalse(coordinator.readCurrentPage(slotID: slotID))
        XCTAssertNil(session.activeSourceSessionKind)
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testCalibrePresentationUsesPageSemanticsAndDisablesAutoSpeak() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "Page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first])
        let service = CalibreTestSpeechService()
        let session = SpeechPlaybackSessionController(speechService: service)
        let coordinator = CalibreSpeechCoordinator(
            playbackSession: session,
            bridgeProvider: { id in id == self.slotID ? bridge : nil }
        )
        let adapter = CalibreSpeechSourceAdapter(
            coordinator: coordinator,
            playbackSession: session,
            activeSlotIDProvider: { self.slotID }
        )

        XCTAssertEqual(adapter.presentation.capabilities, .calibreReader)
        XCTAssertTrue(adapter.presentation.activeSlotSupportsSpeech)
        XCTAssertFalse(adapter.presentation.capabilities.canAutoSpeak)
        XCTAssertEqual(adapter.presentation.labels.read, "Read From Current Page")
        XCTAssertEqual(adapter.presentation.labels.replay, "Replay Current Page")
    }

    func testSourceLeaseIsIndependentFromTransportAndRejectsForeignOwner() {
        let service = CalibreTestSpeechService()
        let session = SpeechPlaybackSessionController(speechService: service)
        let owner = UUID()
        let other = UUID()
        let token = session.acquireSourceSession(
            sourceKind: .calibreReader,
            slotID: owner
        )

        XCTAssertNotNil(token)
        XCTAssertEqual(
            session.acquireSourceSession(sourceKind: .calibreReader, slotID: owner),
            token
        )
        XCTAssertNil(session.acquireSourceSession(sourceKind: .chatGPT, slotID: other))
        XCTAssertEqual(session.playbackState, .idle)
        session.releaseSourceSession(sourceKind: .calibreReader, token: token)
        XCTAssertNil(session.activeSourceSessionKind)
    }

    func testPinnedBridgeScriptsUseRuntimeCFIAndRelocationWithoutWholeDocumentText() {
        let source = CalibreReaderBridge.currentReadingUnitScript
            + CalibreReaderBridge.runtimeDetectionScript
            + CalibreReaderBridge.advanceScript(startCFI: "a", endCFI: "b")
            + CalibreReaderBridge.relocationObserverScript(generation: 1)
        XCTAssertTrue(source.contains("currentLocation"))
        XCTAssertTrue(source.contains("ePub.CFI"))
        XCTAssertTrue(source.contains("rendition.next()"))
        XCTAssertTrue(source.contains("relocated"))
        XCTAssertTrue(source.contains("generation"))
        XCTAssertTrue(source.contains("startCFI"))
        XCTAssertTrue(source.contains("endCFI"))
        XCTAssertFalse(source.contains("document.body.innerText"))
        XCTAssertFalse(source.contains("document.body.textContent"))
        XCTAssertFalse(source.contains("spine"))
    }

    func testReadHoldsSourceLeaseAcrossTransportIdleAndAdvancesOnlyAfterChangedRelocation() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "First page.")
        let second = page(document: doc, start: "c", end: "d", text: "Second page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first, second])
        let service = CalibreTestSpeechService()
        let (coordinator, session) = makeCoordinator(bridge: bridge, service: service)

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        XCTAssertEqual(session.activeSourceSessionKind, .calibreReader)
        service.emitStart()
        service.emitFinish()

        XCTAssertEqual(coordinator.state, .awaitingRelocation)
        XCTAssertEqual(session.playbackState, .idle)
        XCTAssertEqual(bridge.advanceCount, 1)
        XCTAssertEqual(service.spokenRequests.count, 1)
        XCTAssertEqual(session.activeSourceSessionKind, .calibreReader)

        bridge.emitRelocation(first, token: 1)
        XCTAssertEqual(coordinator.state, .awaitingRelocation)
        bridge.emitRelocation(second, token: 1)
        XCTAssertEqual(coordinator.state, .speakingUnit)
        XCTAssertEqual(service.spokenRequests.count, 2)
        XCTAssertEqual(session.activeSourceSessionKind, .calibreReader)
    }

    func testExternalRelocationTerminatesContinuousSessionWithoutIssuingAdvance() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "First page.")
        let second = page(document: doc, start: "c", end: "d", text: "Manual page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first, second])
        let service = CalibreTestSpeechService()
        let (coordinator, session) = makeCoordinator(bridge: bridge, service: service)

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        service.emitStart()
        bridge.emitRelocation(
            second,
            token: nil,
            usePendingTransitionToken: false
        )

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(session.activeSourceSessionKind)
        XCTAssertEqual(bridge.advanceCount, 0)
        XCTAssertEqual(service.stopCount, 1)
    }

    func testExternalRelocationDuringAdvanceWaitTerminatesSession() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "First page.")
        let second = page(document: doc, start: "c", end: "d", text: "Manual page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first, second])
        let service = CalibreTestSpeechService()
        let (coordinator, session) = makeCoordinator(bridge: bridge, service: service)

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        service.emitStart()
        service.emitFinish()
        XCTAssertEqual(coordinator.state, .awaitingRelocation)

        bridge.emitRelocation(
            second,
            token: nil,
            usePendingTransitionToken: false
        )

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(session.activeSourceSessionKind)
        XCTAssertEqual(service.spokenRequests.count, 1)
    }

    func testDuplicateRelocationDoesNotDuplicateNextPageSpeech() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "First page.")
        let second = page(document: doc, start: "c", end: "d", text: "Second page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first, second])
        let service = CalibreTestSpeechService()
        let (coordinator, _) = makeCoordinator(bridge: bridge, service: service)

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        service.emitStart()
        service.emitFinish()
        bridge.emitRelocation(second, token: 1)
        XCTAssertEqual(service.spokenRequests.count, 2)

        bridge.emitRelocation(second, token: nil)
        XCTAssertEqual(coordinator.state, .speakingUnit)
        XCTAssertEqual(service.spokenRequests.count, 2)
    }

    func testEndOfBookReleasesLeaseAndSpeechProtection() {
        let doc = document()
        let last = page(document: doc, start: "a", end: "b", text: "Last page.", atEnd: true)
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [last])
        let service = CalibreTestSpeechService()
        let (coordinator, session) = makeCoordinator(bridge: bridge, service: service)

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        service.emitStart()
        service.emitFinish()

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(session.activeSourceSessionKind)
        XCTAssertFalse(coordinator.isSpeechProtectionActive)
    }

    func testBridgeErrorOrDocumentReplacementReleasesLease() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "Page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first])
        let service = CalibreTestSpeechService()
        let (coordinator, session) = makeCoordinator(bridge: bridge, service: service)

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        bridge.isReaderCandidate = false
        coordinator.resetRuntime(slotID: slotID)

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(session.activeSourceSessionKind)
        XCTAssertEqual(service.stopCount, 1)
    }

    func testGlobalStopClearsCalibreLeaseAndMakesLateRelocationInert() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "Page.")
        let second = page(document: doc, start: "c", end: "d", text: "Next.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first, second])
        let service = CalibreTestSpeechService()
        let (coordinator, session) = makeCoordinator(bridge: bridge, service: service)
        let source = CalibreSpeechSourceAdapter(
            coordinator: coordinator,
            playbackSession: session,
            activeSlotIDProvider: { self.slotID }
        )
        let router = SpeechCommandRouter(
            sources: [source],
            playbackSession: session,
            activeSlotIDProvider: { self.slotID }
        )

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        service.emitStart()
        XCTAssertEqual(
            router.stopCurrentPlayback(),
            .stopped(sourceKind: .calibreReader, slotID: slotID)
        )
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(session.activeSourceSessionKind)
        let spokenCount = service.spokenRequests.count
        bridge.emitRelocation(second, token: 1)
        XCTAssertEqual(service.spokenRequests.count, spokenCount)

        XCTAssertEqual(router.stopCurrentPlayback(), .noOp)
    }

    func testPreviewPreemptsCalibreSessionBeforeStartingChatGPTPreview() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "Page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first])
        let service = CalibreTestSpeechService()
        let session = SpeechPlaybackSessionController(speechService: service)
        let calibreCoordinator = CalibreSpeechCoordinator(
            playbackSession: session,
            bridgeProvider: { id in id == self.slotID ? bridge : nil }
        )
        let calibreSource = CalibreSpeechSourceAdapter(
            coordinator: calibreCoordinator,
            playbackSession: session,
            activeSlotIDProvider: { self.slotID }
        )
        let responseBridge = CalibreTestResponseBridge()
        let chatGPTCoordinator = AssistantSpeechCoordinator(
            playbackSession: session,
            webViewProvider: { _ in WKWebView(frame: .zero) },
            responseBridgeProvider: { _ in responseBridge }
        )
        let chatGPTSource = ChatGPTSpeechSourceAdapter(
            coordinator: chatGPTCoordinator,
            playbackSession: session
        )
        let router = SpeechCommandRouter(
            sources: [calibreSource, chatGPTSource],
            playbackSession: session,
            activeSlotIDProvider: { self.slotID }
        )

        XCTAssertTrue(calibreCoordinator.readCurrentPage(slotID: slotID))
        XCTAssertNotNil(session.activeSourceSessionKind)
        router.playPreview(SpeechLanguageRouter.utteranceRequests(for: "Preview."))

        XCTAssertNil(session.activeSourceSessionKind)
        XCTAssertEqual(calibreCoordinator.state, .idle)
        XCTAssertEqual(service.spokenRequests.last?.text, "Preview.")
        XCTAssertGreaterThan(service.stopCount, 0)
    }

    func testDocumentNavigationCreatesNewGenerationAndDropsReaderCandidate() {
        let bridge = CalibreReaderBridge(slotID: slotID)
        let webView = WKWebView(frame: .zero)
        bridge.attach(to: webView)
        let url = URL(string: "https://reader.example.test/read/7/epub")!

        bridge.handleNavigationCommit(url)
        let firstGeneration = bridge.currentDocumentIdentity?.documentGeneration
        XCTAssertNotNil(firstGeneration)
        XCTAssertFalse(bridge.isReaderCandidate)

        bridge.handleNavigationCommit(url)
        XCTAssertEqual(
            bridge.currentDocumentIdentity?.documentGeneration,
            (firstGeneration ?? 0) + 1
        )
        XCTAssertFalse(bridge.isReaderCandidate)
    }

    func testPauseAtBoundaryResumesOnceIntoAdvance() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "Page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first])
        let service = CalibreTestSpeechService()
        let (coordinator, _) = makeCoordinator(bridge: bridge, service: service)

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        service.emitStart()
        XCTAssertTrue(coordinator.pause(slotID: slotID))
        service.emitFinish()
        XCTAssertEqual(coordinator.state, .pausedAtBoundary)
        XCTAssertEqual(bridge.advanceCount, 0)

        XCTAssertTrue(coordinator.resume(slotID: slotID))
        XCTAssertEqual(coordinator.state, .awaitingRelocation)
        XCTAssertEqual(bridge.advanceCount, 1)
    }

    func testManualCrossSourceReadStopsCalibreBeforeChatGPTAdmission() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "Page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first])
        let service = CalibreTestSpeechService()
        let (coordinator, session) = makeCoordinator(bridge: bridge, service: service)
        let chatSlot = UUID()
        let chatSource = CalibreStubSpeechSource(slotID: chatSlot)
        let calibreSource = CalibreSpeechSourceAdapter(
            coordinator: coordinator,
            playbackSession: session,
            activeSlotIDProvider: { chatSlot }
        )
        var activeSlot = slotID
        let router = SpeechCommandRouter(
            sources: [chatSource, calibreSource],
            playbackSession: session,
            activeSlotIDProvider: { activeSlot }
        )

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        service.emitStart()
        activeSlot = chatSlot
        XCTAssertEqual(
            router.readLatestForActiveSlot(),
            .manualReadAccepted(sourceKind: .chatGPT, slotID: chatSlot)
        )
        XCTAssertNil(session.activeSourceSessionKind)
        XCTAssertEqual(chatSource.readCount, 1)
    }

    func testChatGPTAutoSpeakIsSuppressedBeforeAutomaticBridgeAdmission() {
        let service = CalibreTestSpeechService()
        let session = SpeechPlaybackSessionController(speechService: service)
        let bridge = CalibreTestResponseBridge()
        let webView = WKWebView(frame: .zero)
        let coordinator = AssistantSpeechCoordinator(
            playbackSession: session,
            webViewProvider: { _ in webView },
            responseBridgeProvider: { _ in bridge },
            activeSlotIDProvider: { self.slotID },
            automaticSpeechSuppressed: { _ in true }
        )

        _ = ChatGPTSpeechSourceAdapter(
            coordinator: coordinator,
            playbackSession: session
        )
        coordinator.toggleAutoSpeak(for: slotID)
        _ = session.acquireSourceSession(
            sourceKind: .calibreReader,
            slotID: slotID
        )
        coordinator.handle(.generationFinished, for: slotID)

        XCTAssertEqual(bridge.requestCount, 0)
    }
}
