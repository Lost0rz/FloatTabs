import Foundation

/// The source that owns a speech playback session.
enum SpeechSourceKind: String, CaseIterable, Equatable, Hashable, Sendable {
    case chatGPT
    case calibreReader
}

/// Identity carried from a source through the shared transport boundary.
/// `sourceSequence` identifies the source item and is intentionally distinct
/// from the callback token minted by `SpeechPlaybackSessionController`.
/// `SpeechPlaybackOrigin` remains an intent (automatic/manual/preview), while
/// `sourceKind` identifies the source that owns the resulting callbacks.
struct SpeechPlaybackContext: Equatable, Sendable {
    let sourceKind: SpeechSourceKind
    let slotID: UUID?
    let sourceSequence: UInt64
    let origin: SpeechPlaybackOrigin

    init(
        sourceKind: SpeechSourceKind,
        slotID: UUID?,
        sourceSequence: UInt64,
        origin: SpeechPlaybackOrigin = .manual
    ) {
        self.sourceKind = sourceKind
        self.slotID = slotID
        self.sourceSequence = sourceSequence
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

    private struct ActiveTransport {
        let context: SpeechPlaybackContext
        let callbackToken: UInt64
    }

    private let speechService: SpeechSynthesizing
    private var eventHandlers: [SpeechSourceKind: EventHandler] = [:]
    private var hasCurrentUtterance = false
    private var nextTransportToken: UInt64 = 0
    private var activeTransport: ActiveTransport?
    private var nextSourceSessionToken: UInt64 = 0
    private var activeSourceSession: (
        kind: SpeechSourceKind,
        slotID: UUID?,
        token: UInt64
    )?

    private(set) var playbackState: SpeechPlaybackState = .idle
    /// Source-level identity for the currently admitted transport.
    var activeContext: SpeechPlaybackContext? { activeTransport?.context }
    var onPlaybackStateChange: (() -> Void)?
    /// A source session is intentionally independent from AV transport. A
    /// reader can own this lease while the transport is idle between visual
    /// pages, so another source cannot acquire the continuous-reading path.
    var activeSourceSessionKind: SpeechSourceKind? { activeSourceSession?.kind }
    var activeSourceSessionSlotID: UUID? { activeSourceSession?.slotID }
    var activeSourceSessionToken: UInt64? { activeSourceSession?.token }

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
    /// Session-owned AV callback identity. Sources must use `activeContext`'s
    /// `sourceSequence` for their own item matching instead.
    var activeTransportCallbackToken: UInt64? { activeTransport?.callbackToken }
    var activeTransportToken: UInt64? { activeTransportCallbackToken }
    var isAtSegmentBoundary: Bool {
        playbackState == .paused && !hasCurrentUtterance
    }

    @discardableResult
    func acquireSourceSession(
        sourceKind: SpeechSourceKind,
        slotID: UUID? = nil
    ) -> UInt64? {
        if let activeSourceSession {
            return activeSourceSession.kind == sourceKind
                && activeSourceSession.slotID == slotID
                ? activeSourceSession.token
                : nil
        }
        nextSourceSessionToken &+= 1
        let token = nextSourceSessionToken
        activeSourceSession = (sourceKind, slotID, token)
        return token
    }

    func ownsSourceSession(
        sourceKind: SpeechSourceKind,
        token: UInt64? = nil
    ) -> Bool {
        guard let activeSourceSession,
              activeSourceSession.kind == sourceKind else {
            return false
        }
        return token == nil || activeSourceSession.token == token
    }

    func releaseSourceSession(
        sourceKind: SpeechSourceKind,
        token: UInt64? = nil
    ) {
        guard ownsSourceSession(sourceKind: sourceKind, token: token) else {
            return
        }
        activeSourceSession = nil
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

        let isBoundaryHandoff = playbackState == .resuming
            && !hasCurrentUtterance
            && activeContext?.sourceKind == context.sourceKind
        let isOrdinaryAdmission = playbackState == .idle
            && !hasCurrentUtterance
            && activeContext == nil
        guard isOrdinaryAdmission || isBoundaryHandoff else {
            // A source must explicitly terminate its current session before
            // another ordinary utterance can replace its transport identity.
            // The only exception is the owning source's boundary resume.
            return false
        }

        let callbackToken = mintTransportToken()
        activeTransport = ActiveTransport(
            context: context,
            callbackToken: callbackToken
        )
        hasCurrentUtterance = true
        setPlaybackState(.starting)
        speechService.speak(
            SpeechPlaybackRequest(
                text: text,
                transportToken: callbackToken,
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
        // The request token is transport-owned input and is deliberately not
        // trusted here. This compatibility overload still routes through the
        // canonical admission path, which mints a fresh callback token.
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
        activeTransport = nil
        hasCurrentUtterance = false
        setPlaybackState(.idle)
    }

    /// Clears a boundary pause that ended the final segment. This is separate
    /// from stop so no extra transport cancellation is sent to AVFoundation.
    func dismissPausedBoundary() {
        guard playbackState == .paused, !hasCurrentUtterance else { return }
        activeTransport = nil
        setPlaybackState(.idle)
    }

    /// Explicit stop invalidates the context before asking AVFoundation to
    /// stop, so a synchronous or late cancellation cannot affect new speech.
    func stop() {
        activeTransport = nil
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
        guard let activeTransport,
              activeTransport.callbackToken == token,
              playbackState == .starting else {
            return
        }
        hasCurrentUtterance = true
        setPlaybackState(.speaking)
        route(.started(activeTransport.context))
    }

    private func handleUtteranceFinished(token: UInt64) {
        guard let activeTransport,
              activeTransport.callbackToken == token else {
            return
        }

        let context = activeTransport.context
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

        self.activeTransport = nil
        setPlaybackState(.idle)
        route(.finished(context, boundary: boundary))
    }

    private func handleUtterancePaused(token: UInt64) {
        guard let activeTransport,
              activeTransport.callbackToken == token,
              playbackState == .pausing,
              hasCurrentUtterance else {
            return
        }
        setPlaybackState(.paused)
        route(.paused(activeTransport.context))
    }

    private func handleUtteranceContinued(token: UInt64) {
        guard let activeTransport,
              activeTransport.callbackToken == token,
              playbackState == .resuming,
              hasCurrentUtterance else {
            return
        }
        setPlaybackState(.speaking)
        route(.continued(activeTransport.context))
    }

    private func handleUtteranceCancelled(token: UInt64) {
        guard let activeTransport,
              activeTransport.callbackToken == token else {
            return
        }
        self.activeTransport = nil
        hasCurrentUtterance = false
        setPlaybackState(.idle)
        route(.cancelled(activeTransport.context))
    }

    private func mintTransportToken() -> UInt64 {
        nextTransportToken &+= 1
        return nextTransportToken
    }

    private func setPlaybackState(_ state: SpeechPlaybackState) {
        guard playbackState != state else { return }
        playbackState = state
        onPlaybackStateChange?()
    }
}
