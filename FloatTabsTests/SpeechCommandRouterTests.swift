import XCTest
@testable import FloatTabs

@MainActor
private final class RouterSpeechService: SpeechSynthesizing {
    private(set) var spokenRequests: [SpeechPlaybackRequest] = []
    var onUtteranceStarted: ((UInt64) -> Void)?
    var onUtteranceFinished: ((UInt64) -> Void)?
    var onUtterancePaused: ((UInt64) -> Void)?
    var onUtteranceContinued: ((UInt64) -> Void)?
    var onUtteranceCancelled: ((UInt64) -> Void)?
    var pauseResult = true
    var resumeResult = true

    func speak(_ request: SpeechPlaybackRequest) { spokenRequests.append(request) }
    func pause() -> Bool { pauseResult }
    func resume() -> Bool { resumeResult }
    func stop() {}
    func emitStart(_ token: UInt64) { onUtteranceStarted?(token) }
    func emitPause(_ token: UInt64) { onUtterancePaused?(token) }
    func emitContinue(_ token: UInt64) { onUtteranceContinued?(token) }
}

@MainActor
private final class TestSpeechSourceAdapter: SpeechSourceAdapter {
    let kind: SpeechSourceKind = .chatGPT
    let slotID: UUID
    weak var session: SpeechPlaybackSessionController?
    var supports = true
    var readSucceeds = true
    var replaySucceeds = true
    var hasResumable = false
    var resumeResult = true
    var armed = false
    var readCount = 0
    var replayCount = 0
    var pauseCount = 0
    var resumeCount = 0
    var stopCount = 0
    var globalStopCount = 0
    var toggleCount = 0

    init(slotID: UUID) { self.slotID = slotID }

    var presentation: SpeechSourcePresentation {
        SpeechSourcePresentation(
            sourceKind: kind,
            activeSlotID: slotID,
            autoSpeakSlotIDs: armed ? [slotID] : [],
            activeSlotAutoSpeakEnabled: armed,
            currentSpeakingSlotID: session?.activeSlotID,
            playbackState: session?.playbackState ?? .idle,
            activeSlotSupportsSpeech: supports
        )
    }

    func supportsSpeech(slotID: UUID) -> Bool { slotID == self.slotID && supports }
    func hasResumableState(slotID: UUID) -> Bool {
        slotID == self.slotID && hasResumable
    }
    func isAutoSpeakArmed(slotID: UUID) -> Bool { slotID == self.slotID && armed }
    func readLatest(slotID: UUID) -> Bool {
        guard supportsSpeech(slotID: slotID) else { return false }
        readCount += 1
        return readSucceeds
    }
    func replayLatest(slotID: UUID) -> Bool {
        guard supportsSpeech(slotID: slotID) else { return false }
        replayCount += 1
        return replaySucceeds
    }
    func pause(slotID: UUID) -> Bool {
        guard slotID == self.slotID else { return false }
        pauseCount += 1
        return session?.pause(sourceKind: kind, slotID: slotID) ?? false
    }
    func resume(slotID: UUID) -> Bool {
        guard slotID == self.slotID else { return false }
        resumeCount += 1
        if hasResumable { return resumeResult }
        return session?.resume(sourceKind: kind, slotID: slotID) != .rejected
    }
    func stop(slotID: UUID) -> Bool {
        guard slotID == self.slotID else { return false }
        stopCount += 1
        session?.stop()
        return true
    }
    func stopCurrentPlayback() -> Bool {
        globalStopCount += 1
        session?.stop()
        return true
    }
    func toggleAutoSpeak(slotID: UUID) -> Bool {
        guard slotID == self.slotID else { return false }
        toggleCount += 1
        armed.toggle()
        return true
    }
    func playPreview(_ requests: [SpeechUtteranceRequest]) {}
}

@MainActor
final class SpeechCommandRouterTests: XCTestCase {
    func testC1RegistryContainsOnlyChatGPT() {
        let session = SpeechPlaybackSessionController(speechService: RouterSpeechService())
        let adapter = TestSpeechSourceAdapter(slotID: UUID())
        let router = SpeechCommandRouter(
            sources: [adapter],
            playbackSession: session,
            activeSlotIDProvider: { adapter.slotID }
        )

        XCTAssertEqual(router.registeredSourceKinds, [.chatGPT])
    }

    func testUnsupportedSlotRejectsManualReadAndReplay() {
        let slotID = UUID()
        let session = SpeechPlaybackSessionController(speechService: RouterSpeechService())
        let adapter = TestSpeechSourceAdapter(slotID: slotID)
        adapter.supports = false
        let router = SpeechCommandRouter(
            sources: [adapter],
            playbackSession: session,
            activeSlotIDProvider: { slotID }
        )

        XCTAssertEqual(router.readLatestForActiveSlot(), .rejected)
        XCTAssertEqual(router.replayLatestForActiveSlot(), .rejected)
        XCTAssertEqual(adapter.readCount, 0)
        XCTAssertEqual(adapter.replayCount, 0)
    }

    func testManualReadAndReplayReturnTypedChatGPTOutcomes() {
        let slotID = UUID()
        let session = SpeechPlaybackSessionController(speechService: RouterSpeechService())
        let adapter = TestSpeechSourceAdapter(slotID: slotID)
        let router = SpeechCommandRouter(
            sources: [adapter],
            playbackSession: session,
            activeSlotIDProvider: { slotID }
        )

        XCTAssertEqual(
            router.readLatestForActiveSlot(),
            .manualReadAccepted(sourceKind: .chatGPT, slotID: slotID)
        )
        XCTAssertEqual(
            router.replayLatestForActiveSlot(),
            .replayAccepted(sourceKind: .chatGPT, slotID: slotID)
        )
    }

    func testSourceExtractionFailureIsHandledWithoutRejectingTheCommand() {
        let slotID = UUID()
        let session = SpeechPlaybackSessionController(speechService: RouterSpeechService())
        let adapter = TestSpeechSourceAdapter(slotID: slotID)
        adapter.readSucceeds = false
        adapter.replaySucceeds = false
        let router = SpeechCommandRouter(
            sources: [adapter],
            playbackSession: session,
            activeSlotIDProvider: { slotID }
        )

        XCTAssertEqual(router.readLatestForActiveSlot(), .noOp)
        XCTAssertEqual(router.replayLatestForActiveSlot(), .noOp)
    }

    func testActiveSpeechPauseResumeAndTransitionNoOp() {
        let slotID = UUID()
        let service = RouterSpeechService()
        let session = SpeechPlaybackSessionController(speechService: service)
        let adapter = TestSpeechSourceAdapter(slotID: slotID)
        adapter.session = session
        let router = SpeechCommandRouter(
            sources: [adapter],
            playbackSession: session,
            activeSlotIDProvider: { slotID }
        )
        let context = SpeechPlaybackContext(
            sourceKind: .chatGPT,
            slotID: slotID,
            sourceSequence: 10,
            origin: .manual
        )
        _ = session.speak(context: context, text: "Read.", languageRole: .english)
        let callbackToken = service.spokenRequests[0].transportToken
        service.emitStart(callbackToken)

        XCTAssertEqual(
            router.readPauseResumeForActiveSlot(),
            .paused(sourceKind: .chatGPT, slotID: slotID)
        )
        XCTAssertEqual(router.readPauseResumeForActiveSlot(), .noOp)
        service.emitPause(callbackToken)
        XCTAssertEqual(
            router.readPauseResumeForActiveSlot(),
            .resumed(sourceKind: .chatGPT, slotID: slotID)
        )
        XCTAssertEqual(router.readPauseResumeForActiveSlot(), .noOp)
    }

    func testTransportPauseAndResumeFailureIsNoOpWithoutBeepOutcome() {
        let slotID = UUID()
        let service = RouterSpeechService()
        let session = SpeechPlaybackSessionController(speechService: service)
        let adapter = TestSpeechSourceAdapter(slotID: slotID)
        adapter.session = session
        let router = SpeechCommandRouter(
            sources: [adapter],
            playbackSession: session,
            activeSlotIDProvider: { slotID }
        )
        let context = SpeechPlaybackContext(
            sourceKind: .chatGPT,
            slotID: slotID,
            sourceSequence: 30,
            origin: .manual
        )
        _ = session.speak(context: context, text: "Read.", languageRole: .english)
        let callbackToken = service.spokenRequests[0].transportToken
        service.emitStart(callbackToken)

        service.pauseResult = false
        XCTAssertEqual(router.readPauseResumeForActiveSlot(), .noOp)
        XCTAssertEqual(session.playbackState, .speaking)

        service.pauseResult = true
        XCTAssertEqual(
            router.readPauseResumeForActiveSlot(),
            .paused(sourceKind: .chatGPT, slotID: slotID)
        )
        service.emitPause(callbackToken)
        service.resumeResult = false
        XCTAssertEqual(router.readPauseResumeForActiveSlot(), .noOp)
        XCTAssertEqual(session.playbackState, .paused)
    }

    func testTransportIdleSourceSessionRoutesResumeWithoutFreshRead() {
        let slotID = UUID()
        let session = SpeechPlaybackSessionController(speechService: RouterSpeechService())
        let adapter = TestSpeechSourceAdapter(slotID: slotID)
        adapter.hasResumable = true
        let router = SpeechCommandRouter(
            sources: [adapter],
            playbackSession: session,
            activeSlotIDProvider: { slotID }
        )
        XCTAssertNotNil(session.acquireSourceSession(
            sourceKind: .chatGPT,
            slotID: slotID
        ))

        XCTAssertEqual(
            router.readPauseResumeForActiveSlot(),
            .resumed(sourceKind: .chatGPT, slotID: slotID)
        )
        XCTAssertEqual(adapter.resumeCount, 1)
        XCTAssertEqual(adapter.readCount, 0)
    }

    func testStopIsScopedToTheActiveSlotAndReturnsTypedOutcome() {
        let slotID = UUID()
        let service = RouterSpeechService()
        let session = SpeechPlaybackSessionController(speechService: service)
        let adapter = TestSpeechSourceAdapter(slotID: slotID)
        adapter.session = session
        let router = SpeechCommandRouter(
            sources: [adapter],
            playbackSession: session,
            activeSlotIDProvider: { slotID }
        )
        let context = SpeechPlaybackContext(
            sourceKind: .chatGPT,
            slotID: slotID,
            sourceSequence: 11,
            origin: .manual
        )
        _ = session.speak(context: context, text: "Stop.", languageRole: .english)
        let callbackToken = service.spokenRequests[0].transportToken
        service.emitStart(callbackToken)

        XCTAssertEqual(
            router.stopForActiveSlot(),
            .stopped(sourceKind: .chatGPT, slotID: slotID)
        )
        XCTAssertEqual(router.stopForActiveSlot(), .noOp)
        XCTAssertEqual(adapter.stopCount, 1)
    }

    func testGlobalStopRoutesEvenWhenSourceHasPendingWorkWithoutTransport() {
        let slotID = UUID()
        let session = SpeechPlaybackSessionController(speechService: RouterSpeechService())
        let adapter = TestSpeechSourceAdapter(slotID: slotID)
        let router = SpeechCommandRouter(
            sources: [adapter],
            playbackSession: session,
            activeSlotIDProvider: { slotID }
        )

        XCTAssertEqual(
            router.stopCurrentPlayback(),
            .stopped(sourceKind: .chatGPT, slotID: nil)
        )
        XCTAssertEqual(adapter.globalStopCount, 1)
    }

    func testGlobalStopRoutesActiveTransportThroughSourceGlobalStop() {
        let slotID = UUID()
        let service = RouterSpeechService()
        let session = SpeechPlaybackSessionController(speechService: service)
        let adapter = TestSpeechSourceAdapter(slotID: slotID)
        adapter.session = session
        let router = SpeechCommandRouter(
            sources: [adapter],
            playbackSession: session,
            activeSlotIDProvider: { slotID }
        )
        let context = SpeechPlaybackContext(
            sourceKind: .chatGPT,
            slotID: slotID,
            sourceSequence: 40,
            origin: .manual
        )

        _ = session.speak(context: context, text: "Stop.", languageRole: .english)
        let callbackToken = service.spokenRequests[0].transportToken
        service.emitStart(callbackToken)

        XCTAssertEqual(
            router.stopCurrentPlayback(),
            .stopped(sourceKind: .chatGPT, slotID: slotID)
        )
        XCTAssertEqual(adapter.globalStopCount, 1)
        XCTAssertEqual(session.playbackState, .idle)
        XCTAssertNil(session.activeContext)
    }

    func testAutoSpeakAllowsArmedUnsupportedSlotAndReportsToggle() {
        let slotID = UUID()
        let session = SpeechPlaybackSessionController(speechService: RouterSpeechService())
        let adapter = TestSpeechSourceAdapter(slotID: slotID)
        adapter.supports = false
        adapter.armed = true
        let router = SpeechCommandRouter(
            sources: [adapter],
            playbackSession: session,
            activeSlotIDProvider: { slotID }
        )

        XCTAssertEqual(
            router.toggleAutoSpeakForActiveSlot(),
            .autoSpeakToggled(sourceKind: .chatGPT, slotID: slotID, enabled: false)
        )
        XCTAssertEqual(adapter.toggleCount, 1)
    }
}
