import Foundation

/// The source that owns a speech playback session. C1 intentionally registers
/// only ChatGPT; adding a case here is not enough to make a source runnable.
enum SpeechSourceKind: String, CaseIterable, Equatable, Hashable, Sendable {
    case chatGPT
}

/// Identity carried from a source through the shared transport boundary.
/// `SpeechPlaybackOrigin` remains an intent (automatic/manual/preview), while
/// `sourceKind` identifies the source that owns the resulting callbacks.
struct SpeechPlaybackContext: Equatable, Sendable {
    let sourceKind: SpeechSourceKind
    let slotID: UUID?
    let transportToken: UInt64
    let origin: SpeechPlaybackOrigin

    init(
        sourceKind: SpeechSourceKind,
        slotID: UUID?,
        transportToken: UInt64,
        origin: SpeechPlaybackOrigin = .manual
    ) {
        self.sourceKind = sourceKind
        self.slotID = slotID
        self.transportToken = transportToken
        self.origin = origin
    }
}

enum SpeechPlaybackBoundaryDisposition: Equatable, Sendable {
    case notAtBoundary
    case pausedAtSegmentBoundary
}

enum SpeechPlaybackEvent: Equatable, Sendable {
    case started(SpeechPlaybackContext)
    case paused(SpeechPlaybackContext)
    case continued(SpeechPlaybackContext)
    case finished(
        SpeechPlaybackContext,
        boundary: SpeechPlaybackBoundaryDisposition
    )
    case cancelled(SpeechPlaybackContext)

    var context: SpeechPlaybackContext {
        switch self {
        case let .started(context), let .paused(context), let .continued(context),
             let .finished(context, _), let .cancelled(context):
            return context
        }
    }
}

enum SpeechPlaybackResumeDisposition: Equatable, Sendable {
    case continuedCurrentUtterance
    case resumeAtSegmentBoundary
    case rejected
}

/// The only owner of SpeechService callbacks, transport transitions, and the
/// app-global playback state. Source-specific FIFO and response policy remain
/// in the source adapter/coordinator that receives its typed events.
@MainActor
final class SpeechPlaybackSessionController {
    typealias EventHandler = @MainActor (SpeechPlaybackEvent) -> Void

    private let speechService: SpeechSynthesizing
    private var eventHandlers: [SpeechSourceKind: EventHandler] = [:]
    private var hasCurrentUtterance = false

    private(set) var playbackState: SpeechPlaybackState = .idle
    private(set) var activeContext: SpeechPlaybackContext?
    var onPlaybackStateChange: (() -> Void)?

    init(speechService: SpeechSynthesizing) {
        self.speechService = speechService

        // This is deliberately the sole production callback binder. No source
        // adapter or coordinator writes to SpeechService's callback properties.
        speechService.onUtteranceStarted = { [weak self] token in
            self?.handleUtteranceStarted(token: token)
        }
        speechService.onUtteranceFinished = { [weak self] token in
            self?.handleUtteranceFinished(token: token)
        }
        speechService.onUtterancePaused = { [weak self] token in
            self?.handleUtterancePaused(token: token)
        }
        speechService.onUtteranceContinued = { [weak self] token in
            self?.handleUtteranceContinued(token: token)
        }
        speechService.onUtteranceCancelled = { [weak self] token in
            self?.handleUtteranceCancelled(token: token)
        }
    }

    var activeSlotID: UUID? { activeContext?.slotID }
    var currentSpeakingSlotID: UUID? { activeSlotID }
    var activeSourceKind: SpeechSourceKind? { activeContext?.sourceKind }
    var activeTransportToken: UInt64? { activeContext?.transportToken }
    var isAtSegmentBoundary: Bool {
        playbackState == .paused && !hasCurrentUtterance
    }

    func register(
        sourceKind: SpeechSourceKind,
        eventHandler: @escaping EventHandler
    ) {
        eventHandlers[sourceKind] = eventHandler
    }

    @discardableResult
    func speak(
        context: SpeechPlaybackContext,
        text: String,
        languageRole: SpeechLanguageRole
    ) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        activeContext = context
        hasCurrentUtterance = true
        setPlaybackState(.starting)
        speechService.speak(
            SpeechPlaybackRequest(
                text: text,
                transportToken: context.transportToken,
                languageRole: languageRole
            )
        )
        return true
    }

    @discardableResult
    func speak(
        _ request: SpeechPlaybackRequest,
        context: SpeechPlaybackContext
    ) -> Bool {
        guard request.transportToken == context.transportToken else { return false }
        return speak(
            context: context,
            text: request.text,
            languageRole: request.languageRole
        )
    }

    @discardableResult
    func pause() -> Bool {
        pause(sourceKind: nil, slotID: nil)
    }

    @discardableResult
    func pause(
        sourceKind: SpeechSourceKind?,
        slotID: UUID?
    ) -> Bool {
        guard ownsActivePlayback(sourceKind: sourceKind, slotID: slotID),
              playbackState == .speaking,
              hasCurrentUtterance else {
            return false
        }

        setPlaybackState(.pausing)
        let accepted = speechService.pause()
        if !accepted {
            setPlaybackState(.speaking)
        }
        return accepted
    }

    @discardableResult
    func resume() -> SpeechPlaybackResumeDisposition {
        resume(sourceKind: nil, slotID: nil)
    }

    @discardableResult
    func resume(
        sourceKind: SpeechSourceKind?,
        slotID: UUID?
    ) -> SpeechPlaybackResumeDisposition {
        guard ownsActivePlayback(sourceKind: sourceKind, slotID: slotID),
              playbackState == .paused else {
            return .rejected
        }

        guard hasCurrentUtterance else {
            // AVFoundation has already finished the paused utterance. The
            // owning source must submit its next segment explicitly.
            setPlaybackState(.resuming)
            return .resumeAtSegmentBoundary
        }

        setPlaybackState(.resuming)
        let accepted = speechService.resume()
        if !accepted {
            setPlaybackState(.paused)
            return .rejected
        }
        return .continuedCurrentUtterance
    }

    /// Used by an owning source after `.resumeAtSegmentBoundary` to leave the
    /// paused transport state before it submits its next FIFO segment.
    @discardableResult
    func beginBoundaryResume() -> Bool {
        guard playbackState == .resuming,
              activeContext != nil,
              !hasCurrentUtterance else {
            return false
        }
        return true
    }

    /// Rolls an empty boundary resume back to a terminal idle state.
    func finishBoundaryResumeWithoutSpeech() {
        guard playbackState == .resuming else { return }
        activeContext = nil
        hasCurrentUtterance = false
        setPlaybackState(.idle)
    }

    /// Clears a boundary pause that ended the final segment. This is separate
    /// from stop so no extra transport cancellation is sent to AVFoundation.
    func dismissPausedBoundary() {
        guard playbackState == .paused, !hasCurrentUtterance else { return }
        activeContext = nil
        setPlaybackState(.idle)
    }

    /// Explicit stop invalidates the context before asking AVFoundation to
    /// stop, so a synchronous or late cancellation cannot affect new speech.
    func stop() {
        activeContext = nil
        hasCurrentUtterance = false
        setPlaybackState(.idle)
        speechService.stop()
    }

    private func ownsActivePlayback(
        sourceKind: SpeechSourceKind?,
        slotID: UUID?
    ) -> Bool {
        guard let activeContext else { return false }
        if let sourceKind, activeContext.sourceKind != sourceKind { return false }
        if let slotID, activeContext.slotID != slotID { return false }
        return true
    }

    private func route(_ event: SpeechPlaybackEvent) {
        eventHandlers[event.context.sourceKind]?(event)
    }

    private func handleUtteranceStarted(token: UInt64) {
        guard let context = activeContext,
              context.transportToken == token,
              playbackState == .starting else {
            return
        }
        hasCurrentUtterance = true
        setPlaybackState(.speaking)
        route(.started(context))
    }

    private func handleUtteranceFinished(token: UInt64) {
        guard let context = activeContext,
              context.transportToken == token else {
            return
        }

        hasCurrentUtterance = false
        let boundary: SpeechPlaybackBoundaryDisposition =
            playbackState == .pausing || playbackState == .paused
                ? .pausedAtSegmentBoundary
                : .notAtBoundary

        if boundary == .pausedAtSegmentBoundary {
            // Retain source/Slot identity while paused at a segment boundary.
            setPlaybackState(.paused)
            route(.finished(context, boundary: boundary))
            return
        }

        activeContext = nil
        setPlaybackState(.idle)
        route(.finished(context, boundary: boundary))
    }

    private func handleUtterancePaused(token: UInt64) {
        guard let context = activeContext,
              context.transportToken == token,
              playbackState == .pausing,
              hasCurrentUtterance else {
            return
        }
        setPlaybackState(.paused)
        route(.paused(context))
    }

    private func handleUtteranceContinued(token: UInt64) {
        guard let context = activeContext,
              context.transportToken == token,
              playbackState == .resuming,
              hasCurrentUtterance else {
            return
        }
        setPlaybackState(.speaking)
        route(.continued(context))
    }

    private func handleUtteranceCancelled(token: UInt64) {
        guard let context = activeContext,
              context.transportToken == token else {
            return
        }
        activeContext = nil
        hasCurrentUtterance = false
        setPlaybackState(.idle)
        route(.cancelled(context))
    }

    private func setPlaybackState(_ state: SpeechPlaybackState) {
        guard playbackState != state else { return }
        playbackState = state
        onPlaybackStateChange?()
    }
}
