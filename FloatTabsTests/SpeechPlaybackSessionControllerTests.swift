import XCTest
@testable import FloatTabs

@MainActor
private final class SessionControllerSpeechService: SpeechSynthesizing {
    private(set) var spokenRequests: [SpeechPlaybackRequest] = []
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private(set) var stopCount = 0

    var onUtteranceStarted: ((UInt64) -> Void)?
    var onUtteranceFinished: ((UInt64) -> Void)?
    var onUtterancePaused: ((UInt64) -> Void)?
    var onUtteranceContinued: ((UInt64) -> Void)?
    var onUtteranceCancelled: ((UInt64) -> Void)?
    var pauseResult = true
    var resumeResult = true

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

    func emitStart(_ token: UInt64) { onUtteranceStarted?(token) }
    func emitFinish(_ token: UInt64) { onUtteranceFinished?(token) }
    func emitPause(_ token: UInt64) { onUtterancePaused?(token) }
    func emitContinue(_ token: UInt64) { onUtteranceContinued?(token) }
    func emitCancel(_ token: UInt64) { onUtteranceCancelled?(token) }
}

@MainActor
final class SpeechPlaybackSessionControllerTests: XCTestCase {
    private func context(
        slotID: UUID? = UUID(),
        sourceSequence: UInt64,
        origin: SpeechPlaybackOrigin = .manual
    ) -> SpeechPlaybackContext {
        SpeechPlaybackContext(
            sourceKind: .chatGPT,
            slotID: slotID,
            sourceSequence: sourceSequence,
            origin: origin
        )
    }

    func testSessionIsTheSingleCallbackOwnerAndRoutesTypedEvents() {
        let service = SessionControllerSpeechService()
        let session = SpeechPlaybackSessionController(speechService: service)
        var events: [SpeechPlaybackEvent] = []
        session.register(sourceKind: .chatGPT) { events.append($0) }

        XCTAssertNotNil(service.onUtteranceStarted)
        XCTAssertNotNil(service.onUtteranceFinished)
        XCTAssertNotNil(service.onUtterancePaused)
        XCTAssertNotNil(service.onUtteranceContinued)
        XCTAssertNotNil(service.onUtteranceCancelled)

        let playbackContext = context(sourceSequence: 101)
        XCTAssertTrue(session.speak(
            context: playbackContext,
            text: "Hello.",
            languageRole: .english
        ))
        let callbackToken = service.spokenRequests[0].transportToken
        service.emitStart(callbackToken)

        XCTAssertEqual(session.playbackState, .speaking)
        XCTAssertEqual(session.activeSourceKind, .chatGPT)
        XCTAssertEqual(session.activeSlotID, playbackContext.slotID)
        XCTAssertEqual(session.activeTransportToken, callbackToken)
        XCTAssertNotEqual(session.activeTransportToken, playbackContext.sourceSequence)
        XCTAssertEqual(events, [.started(playbackContext)])
    }

    func testTransportCallbacksDriveTheSharedStateMachine() {
        let service = SessionControllerSpeechService()
        let session = SpeechPlaybackSessionController(speechService: service)
        var events: [SpeechPlaybackEvent] = []
        session.register(sourceKind: .chatGPT) { events.append($0) }
        let playbackContext = context(sourceSequence: 2)

        _ = session.speak(context: playbackContext, text: "Hello.", languageRole: .english)
        XCTAssertEqual(session.playbackState, .starting)
        let callbackToken = service.spokenRequests[0].transportToken
        service.emitStart(callbackToken)
        XCTAssertEqual(session.playbackState, .speaking)
        XCTAssertTrue(session.pause(sourceKind: .chatGPT, slotID: playbackContext.slotID))
        XCTAssertEqual(session.playbackState, .pausing)
        service.emitPause(callbackToken)
        XCTAssertEqual(session.playbackState, .paused)
        XCTAssertEqual(session.resume(sourceKind: .chatGPT, slotID: playbackContext.slotID), .continuedCurrentUtterance)
        XCTAssertEqual(session.playbackState, .resuming)
        service.emitContinue(callbackToken)
        XCTAssertEqual(session.playbackState, .speaking)
        service.emitFinish(callbackToken)
        XCTAssertEqual(session.playbackState, .idle)
        XCTAssertNil(session.activeContext)
        XCTAssertEqual(events, [
            .started(playbackContext),
            .paused(playbackContext),
            .continued(playbackContext),
            .finished(playbackContext, boundary: .notAtBoundary),
        ])
    }

    func testStartingRejectsSecondSpeakWithoutChangingTransport() {
        let service = SessionControllerSpeechService()
        let session = SpeechPlaybackSessionController(speechService: service)
        let first = context(sourceSequence: 20)
        let second = context(sourceSequence: 21)

        XCTAssertTrue(session.speak(
            context: first,
            text: "First.",
            languageRole: .english
        ))
        XCTAssertFalse(session.speak(
            context: second,
            text: "Second.",
            languageRole: .english
        ))
        XCTAssertEqual(session.activeContext, first)
        XCTAssertEqual(session.playbackState, .starting)
        XCTAssertEqual(service.spokenRequests.map(\.transportToken), [1])
        XCTAssertNotEqual(service.spokenRequests[0].transportToken, first.sourceSequence)
    }

    func testSpeakingRejectsSecondSpeakWithoutChangingTransport() {
        let service = SessionControllerSpeechService()
        let session = SpeechPlaybackSessionController(speechService: service)
        let first = context(sourceSequence: 22)
        let second = context(sourceSequence: 23)

        _ = session.speak(context: first, text: "First.", languageRole: .english)
        let callbackToken = service.spokenRequests[0].transportToken
        service.emitStart(callbackToken)
        XCTAssertFalse(session.speak(
            context: second,
            text: "Second.",
            languageRole: .english
        ))
        XCTAssertEqual(session.activeContext, first)
        XCTAssertEqual(session.playbackState, .speaking)
        XCTAssertEqual(service.spokenRequests.map(\.transportToken), [1])
    }

    func testPausingPausedAndResumingTransportRejectSecondSpeak() {
        let service = SessionControllerSpeechService()
        let session = SpeechPlaybackSessionController(speechService: service)
        let first = context(sourceSequence: 24)
        let second = context(sourceSequence: 25)

        _ = session.speak(context: first, text: "First.", languageRole: .english)
        let callbackToken = service.spokenRequests[0].transportToken
        service.emitStart(callbackToken)
        XCTAssertTrue(session.pause(sourceKind: .chatGPT, slotID: first.slotID))
        XCTAssertFalse(session.speak(context: second, text: "Second.", languageRole: .english))
        service.emitPause(callbackToken)
        XCTAssertFalse(session.speak(context: second, text: "Second.", languageRole: .english))
        XCTAssertEqual(
            session.resume(sourceKind: .chatGPT, slotID: first.slotID),
            .continuedCurrentUtterance
        )
        XCTAssertFalse(session.speak(context: second, text: "Second.", languageRole: .english))
        XCTAssertEqual(session.activeContext, first)
        XCTAssertEqual(session.playbackState, .resuming)
        XCTAssertEqual(service.spokenRequests.map(\.transportToken), [1])
    }

    func testFailedPauseAndResumeRollBackWithoutPublishingACompetingState() {
        let service = SessionControllerSpeechService()
        let session = SpeechPlaybackSessionController(speechService: service)
        let playbackContext = context(sourceSequence: 3)
        _ = session.speak(context: playbackContext, text: "Hello.", languageRole: .english)
        let callbackToken = service.spokenRequests[0].transportToken
        service.emitStart(callbackToken)

        service.pauseResult = false
        XCTAssertFalse(session.pause(sourceKind: .chatGPT, slotID: playbackContext.slotID))
        XCTAssertEqual(session.playbackState, .speaking)

        service.pauseResult = true
        XCTAssertTrue(session.pause(sourceKind: .chatGPT, slotID: playbackContext.slotID))
        service.emitPause(callbackToken)
        service.resumeResult = false
        XCTAssertEqual(
            session.resume(sourceKind: .chatGPT, slotID: playbackContext.slotID),
            .rejected
        )
        XCTAssertEqual(session.playbackState, .paused)
    }

    func testPauseAtSegmentBoundaryRetainsIdentityAndResumeHasExplicitDisposition() {
        let service = SessionControllerSpeechService()
        let session = SpeechPlaybackSessionController(speechService: service)
        var events: [SpeechPlaybackEvent] = []
        session.register(sourceKind: .chatGPT) { events.append($0) }
        let first = context(sourceSequence: 7)
        let second = context(sourceSequence: 7, origin: .automatic)

        _ = session.speak(context: first, text: "First.", languageRole: .english)
        let firstCallbackToken = service.spokenRequests[0].transportToken
        service.emitStart(firstCallbackToken)
        XCTAssertTrue(session.pause(sourceKind: .chatGPT, slotID: first.slotID))
        service.emitFinish(firstCallbackToken)

        XCTAssertEqual(session.playbackState, .paused)
        XCTAssertTrue(session.isAtSegmentBoundary)
        XCTAssertEqual(session.activeContext, first)
        XCTAssertEqual(events.last, .finished(first, boundary: .pausedAtSegmentBoundary))

        // A late didPause from the already-finished utterance is harmless.
        service.emitPause(firstCallbackToken)
        XCTAssertEqual(session.playbackState, .paused)
        XCTAssertEqual(session.activeContext, first)

        XCTAssertEqual(
            session.resume(sourceKind: .chatGPT, slotID: first.slotID),
            .resumeAtSegmentBoundary
        )
        XCTAssertEqual(session.playbackState, .resuming)
        XCTAssertTrue(session.beginBoundaryResume())
        _ = session.speak(context: second, text: "Second.", languageRole: .english)
        let secondCallbackToken = service.spokenRequests[1].transportToken
        XCTAssertNotEqual(firstCallbackToken, secondCallbackToken)

        // Reusing the source sequence is valid, but every callback from the
        // previous transport remains stale after the boundary handoff.
        service.emitStart(firstCallbackToken)
        service.emitPause(firstCallbackToken)
        service.emitContinue(firstCallbackToken)
        service.emitFinish(firstCallbackToken)
        service.emitCancel(firstCallbackToken)
        XCTAssertEqual(session.playbackState, .starting)
        XCTAssertEqual(session.activeContext, second)

        service.emitStart(secondCallbackToken)

        XCTAssertEqual(session.playbackState, .speaking)
        XCTAssertEqual(session.activeContext, second)
        XCTAssertTrue(session.pause(sourceKind: .chatGPT, slotID: second.slotID))
        service.emitPause(secondCallbackToken)
        XCTAssertEqual(
            session.resume(sourceKind: .chatGPT, slotID: second.slotID),
            .continuedCurrentUtterance
        )
        service.emitContinue(secondCallbackToken)
        service.emitFinish(secondCallbackToken)
        XCTAssertEqual(session.playbackState, .idle)
        XCTAssertNil(session.activeContext)
    }

    func testStopMintsFreshTransportTokenForReusedSourceSequence() {
        let service = SessionControllerSpeechService()
        let session = SpeechPlaybackSessionController(speechService: service)
        var events: [SpeechPlaybackEvent] = []
        session.register(sourceKind: .chatGPT) { events.append($0) }
        let first = context(sourceSequence: 7)
        let second = context(sourceSequence: 7)

        _ = session.speak(context: first, text: "Old.", languageRole: .english)
        let firstCallbackToken = service.spokenRequests[0].transportToken
        session.stop()

        _ = session.speak(context: second, text: "New.", languageRole: .english)
        let secondCallbackToken = service.spokenRequests[1].transportToken
        XCTAssertNotEqual(firstCallbackToken, secondCallbackToken)

        // All callbacks from the stopped transport are stale, including the
        // callbacks that would otherwise move a live transport through its
        // state machine.
        service.emitStart(firstCallbackToken)
        service.emitPause(firstCallbackToken)
        service.emitContinue(firstCallbackToken)
        service.emitFinish(firstCallbackToken)
        service.emitCancel(firstCallbackToken)
        XCTAssertEqual(session.playbackState, .starting)
        XCTAssertEqual(session.activeContext, second)
        XCTAssertEqual(events, [])

        service.emitStart(secondCallbackToken)
        XCTAssertEqual(session.playbackState, .speaking)
        XCTAssertEqual(events, [.started(second)])
        service.emitFinish(secondCallbackToken)
        XCTAssertEqual(session.playbackState, .idle)
        XCTAssertEqual(events, [.started(second), .finished(second, boundary: .notAtBoundary)])
    }

    func testOldTransportCallbacksCannotAffectReplacementAfterStop() {
        let service = SessionControllerSpeechService()
        let session = SpeechPlaybackSessionController(speechService: service)
        var events: [SpeechPlaybackEvent] = []
        session.register(sourceKind: .chatGPT) { events.append($0) }
        let oldContext = context(sourceSequence: 6)
        let newContext = context(sourceSequence: 7)

        _ = session.speak(context: oldContext, text: "Old.", languageRole: .english)
        let oldCallbackToken = service.spokenRequests[0].transportToken
        session.stop()
        service.emitStart(oldCallbackToken)
        service.emitFinish(oldCallbackToken)
        service.emitCancel(oldCallbackToken)
        XCTAssertTrue(events.isEmpty)

        _ = session.speak(context: newContext, text: "New.", languageRole: .english)
        let newCallbackToken = service.spokenRequests[1].transportToken
        service.emitStart(newCallbackToken)
        service.emitFinish(oldCallbackToken)
        service.emitCancel(oldCallbackToken)
        XCTAssertEqual(session.playbackState, .speaking)
        XCTAssertEqual(session.activeContext, newContext)
        XCTAssertEqual(events, [.started(newContext)])
    }

    func testCancellationTerminatesOnlyTheCurrentTransport() {
        let service = SessionControllerSpeechService()
        let session = SpeechPlaybackSessionController(speechService: service)
        var events: [SpeechPlaybackEvent] = []
        session.register(sourceKind: .chatGPT) { events.append($0) }
        let playbackContext = context(sourceSequence: 8)

        _ = session.speak(context: playbackContext, text: "Cancel.", languageRole: .english)
        let callbackToken = service.spokenRequests[0].transportToken
        service.emitStart(callbackToken)
        service.emitCancel(callbackToken)

        XCTAssertEqual(session.playbackState, .idle)
        XCTAssertNil(session.activeContext)
        XCTAssertEqual(events, [.started(playbackContext), .cancelled(playbackContext)])
    }
}
