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
        token: UInt64,
        origin: SpeechPlaybackOrigin = .manual
    ) -> SpeechPlaybackContext {
        SpeechPlaybackContext(
            sourceKind: .chatGPT,
            slotID: slotID,
            transportToken: token,
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

        let playbackContext = context(token: 1)
        XCTAssertTrue(session.speak(
            context: playbackContext,
            text: "Hello.",
            languageRole: .english
        ))
        service.emitStart(1)

        XCTAssertEqual(session.playbackState, .speaking)
        XCTAssertEqual(session.activeSourceKind, .chatGPT)
        XCTAssertEqual(session.activeSlotID, playbackContext.slotID)
        XCTAssertEqual(session.activeTransportToken, 1)
        XCTAssertEqual(events, [.started(playbackContext)])
    }

    func testTransportCallbacksDriveTheSharedStateMachine() {
        let service = SessionControllerSpeechService()
        let session = SpeechPlaybackSessionController(speechService: service)
        var events: [SpeechPlaybackEvent] = []
        session.register(sourceKind: .chatGPT) { events.append($0) }
        let playbackContext = context(token: 2)

        _ = session.speak(context: playbackContext, text: "Hello.", languageRole: .english)
        XCTAssertEqual(session.playbackState, .starting)
        service.emitStart(2)
        XCTAssertEqual(session.playbackState, .speaking)
        XCTAssertTrue(session.pause(sourceKind: .chatGPT, slotID: playbackContext.slotID))
        XCTAssertEqual(session.playbackState, .pausing)
        service.emitPause(2)
        XCTAssertEqual(session.playbackState, .paused)
        XCTAssertEqual(session.resume(sourceKind: .chatGPT, slotID: playbackContext.slotID), .continuedCurrentUtterance)
        XCTAssertEqual(session.playbackState, .resuming)
        service.emitContinue(2)
        XCTAssertEqual(session.playbackState, .speaking)
        service.emitFinish(2)
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
        let first = context(token: 20)
        let second = context(token: 21)

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
        XCTAssertEqual(service.spokenRequests.map(\.transportToken), [20])
    }

    func testSpeakingRejectsSecondSpeakWithoutChangingTransport() {
        let service = SessionControllerSpeechService()
        let session = SpeechPlaybackSessionController(speechService: service)
        let first = context(token: 22)
        let second = context(token: 23)

        _ = session.speak(context: first, text: "First.", languageRole: .english)
        service.emitStart(22)
        XCTAssertFalse(session.speak(
            context: second,
            text: "Second.",
            languageRole: .english
        ))
        XCTAssertEqual(session.activeContext, first)
        XCTAssertEqual(session.playbackState, .speaking)
        XCTAssertEqual(service.spokenRequests.map(\.transportToken), [22])
    }

    func testPausingPausedAndResumingTransportRejectSecondSpeak() {
        let service = SessionControllerSpeechService()
        let session = SpeechPlaybackSessionController(speechService: service)
        let first = context(token: 24)
        let second = context(token: 25)

        _ = session.speak(context: first, text: "First.", languageRole: .english)
        service.emitStart(24)
        XCTAssertTrue(session.pause(sourceKind: .chatGPT, slotID: first.slotID))
        XCTAssertFalse(session.speak(context: second, text: "Second.", languageRole: .english))
        service.emitPause(24)
        XCTAssertFalse(session.speak(context: second, text: "Second.", languageRole: .english))
        XCTAssertEqual(
            session.resume(sourceKind: .chatGPT, slotID: first.slotID),
            .continuedCurrentUtterance
        )
        XCTAssertFalse(session.speak(context: second, text: "Second.", languageRole: .english))
        XCTAssertEqual(session.activeContext, first)
        XCTAssertEqual(session.playbackState, .resuming)
        XCTAssertEqual(service.spokenRequests.map(\.transportToken), [24])
    }

    func testFailedPauseAndResumeRollBackWithoutPublishingACompetingState() {
        let service = SessionControllerSpeechService()
        let session = SpeechPlaybackSessionController(speechService: service)
        let playbackContext = context(token: 3)
        _ = session.speak(context: playbackContext, text: "Hello.", languageRole: .english)
        service.emitStart(3)

        service.pauseResult = false
        XCTAssertFalse(session.pause(sourceKind: .chatGPT, slotID: playbackContext.slotID))
        XCTAssertEqual(session.playbackState, .speaking)

        service.pauseResult = true
        XCTAssertTrue(session.pause(sourceKind: .chatGPT, slotID: playbackContext.slotID))
        service.emitPause(3)
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
        let first = context(token: 4)
        let second = context(token: 5, origin: .automatic)

        _ = session.speak(context: first, text: "First.", languageRole: .english)
        service.emitStart(4)
        XCTAssertTrue(session.pause(sourceKind: .chatGPT, slotID: first.slotID))
        service.emitFinish(4)

        XCTAssertEqual(session.playbackState, .paused)
        XCTAssertTrue(session.isAtSegmentBoundary)
        XCTAssertEqual(session.activeContext, first)
        XCTAssertEqual(events.last, .finished(first, boundary: .pausedAtSegmentBoundary))

        // A late didPause from the already-finished utterance is harmless.
        service.emitPause(4)
        XCTAssertEqual(session.playbackState, .paused)
        XCTAssertEqual(session.activeContext, first)

        XCTAssertEqual(
            session.resume(sourceKind: .chatGPT, slotID: first.slotID),
            .resumeAtSegmentBoundary
        )
        XCTAssertEqual(session.playbackState, .resuming)
        XCTAssertTrue(session.beginBoundaryResume())
        _ = session.speak(context: second, text: "Second.", languageRole: .english)
        service.emitStart(5)

        XCTAssertEqual(session.playbackState, .speaking)
        XCTAssertEqual(session.activeContext, second)
        service.emitCancel(4)
        XCTAssertEqual(session.activeContext, second)
        XCTAssertEqual(session.playbackState, .speaking)
    }

    func testStopInvalidatesOldStartFinishAndCancelCallbacks() {
        let service = SessionControllerSpeechService()
        let session = SpeechPlaybackSessionController(speechService: service)
        var events: [SpeechPlaybackEvent] = []
        session.register(sourceKind: .chatGPT) { events.append($0) }
        let oldContext = context(token: 6)
        let newContext = context(token: 7)

        _ = session.speak(context: oldContext, text: "Old.", languageRole: .english)
        session.stop()
        service.emitStart(6)
        service.emitFinish(6)
        service.emitCancel(6)
        XCTAssertTrue(events.isEmpty)

        _ = session.speak(context: newContext, text: "New.", languageRole: .english)
        service.emitStart(7)
        service.emitFinish(6)
        service.emitCancel(6)
        XCTAssertEqual(session.playbackState, .speaking)
        XCTAssertEqual(session.activeContext, newContext)
        XCTAssertEqual(events, [.started(newContext)])
    }

    func testCancellationTerminatesOnlyTheCurrentTransport() {
        let service = SessionControllerSpeechService()
        let session = SpeechPlaybackSessionController(speechService: service)
        var events: [SpeechPlaybackEvent] = []
        session.register(sourceKind: .chatGPT) { events.append($0) }
        let playbackContext = context(token: 8)

        _ = session.speak(context: playbackContext, text: "Cancel.", languageRole: .english)
        service.emitStart(8)
        service.emitCancel(8)

        XCTAssertEqual(session.playbackState, .idle)
        XCTAssertNil(session.activeContext)
        XCTAssertEqual(events, [.started(playbackContext), .cancelled(playbackContext)])
    }
}
