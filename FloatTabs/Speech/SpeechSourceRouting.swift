import Foundation

/// Source-owned projection consumed by the existing rail. The rail remains a
/// presentation surface; it does not select a speech source or own transport.
struct SpeechSourcePresentation: Equatable, Sendable {
    let sourceKind: SpeechSourceKind
    let activeSlotID: UUID?
    let autoSpeakSlotIDs: Set<UUID>
    let activeSlotAutoSpeakEnabled: Bool
    let currentSpeakingSlotID: UUID?
    let playbackState: SpeechPlaybackState
    let activeSlotSupportsSpeech: Bool

    var railPresentation: SpeechRailPresentation {
        SpeechRailPresentation(
            activeSlotID: activeSlotID,
            autoSpeakSlotIDs: autoSpeakSlotIDs,
            activeSlotAutoSpeakEnabled: activeSlotAutoSpeakEnabled,
            currentSpeakingSlotID: currentSpeakingSlotID,
            playbackState: playbackState,
            activeSlotSupportsSpeech: activeSlotSupportsSpeech
        )
    }
}

enum SpeechCommandOutcome: Equatable, Sendable {
    case manualReadAccepted(sourceKind: SpeechSourceKind, slotID: UUID)
    case replayAccepted(sourceKind: SpeechSourceKind, slotID: UUID)
    case paused(sourceKind: SpeechSourceKind, slotID: UUID)
    case resumed(sourceKind: SpeechSourceKind, slotID: UUID)
    case stopped(sourceKind: SpeechSourceKind, slotID: UUID?)
    case autoSpeakToggled(
        sourceKind: SpeechSourceKind,
        slotID: UUID,
        enabled: Bool
    )
    case rejected
    case noOp

    var wasAccepted: Bool {
        switch self {
        case .manualReadAccepted, .replayAccepted, .paused, .resumed,
             .stopped, .autoSpeakToggled:
            return true
        case .rejected, .noOp:
            return false
        }
    }

    var sourceKind: SpeechSourceKind? {
        switch self {
        case let .manualReadAccepted(sourceKind, _),
             let .replayAccepted(sourceKind, _),
             let .paused(sourceKind, _),
             let .resumed(sourceKind, _),
             let .stopped(sourceKind, _),
             let .autoSpeakToggled(sourceKind, _, _):
            return sourceKind
        case .rejected, .noOp:
            return nil
        }
    }
}

@MainActor
protocol SpeechSourceAdapter: AnyObject {
    var kind: SpeechSourceKind { get }
    var presentation: SpeechSourcePresentation { get }

    func supportsSpeech(slotID: UUID) -> Bool
    func isAutoSpeakArmed(slotID: UUID) -> Bool
    func readLatest(slotID: UUID) -> Bool
    func replayLatest(slotID: UUID) -> Bool
    func pause(slotID: UUID) -> Bool
    func resume(slotID: UUID) -> Bool
    func stop(slotID: UUID) -> Bool
    func stopCurrentPlayback() -> Bool
    func toggleAutoSpeak(slotID: UUID) -> Bool
    func playPreview(_ requests: [SpeechUtteranceRequest])
}

/// Thin routing glue for the existing ChatGPT coordinator. ChatGPT response
/// extraction, FIFO, unread, and follow semantics stay in the coordinator.
@MainActor
final class ChatGPTSpeechSourceAdapter: SpeechSourceAdapter {
    let kind: SpeechSourceKind = .chatGPT

    private let coordinator: AssistantSpeechCoordinator
    private let activeSlotIDProvider: @MainActor () -> UUID?
    private let supportsSpeechQuery: @MainActor (UUID) -> Bool

    init(
        coordinator: AssistantSpeechCoordinator,
        playbackSession: SpeechPlaybackSessionController,
        activeSlotIDProvider: @escaping @MainActor () -> UUID?,
        supportsSpeechQuery: @escaping @MainActor (UUID) -> Bool
    ) {
        self.coordinator = coordinator
        self.activeSlotIDProvider = activeSlotIDProvider
        self.supportsSpeechQuery = supportsSpeechQuery

        playbackSession.register(sourceKind: .chatGPT) { [weak coordinator] event in
            coordinator?.handlePlaybackEvent(event)
        }
    }

    var presentation: SpeechSourcePresentation {
        let activeSlotID = activeSlotIDProvider()
        return SpeechSourcePresentation(
            sourceKind: kind,
            activeSlotID: activeSlotID,
            autoSpeakSlotIDs: coordinator.autoSpeakSlotIDs,
            activeSlotAutoSpeakEnabled: activeSlotID.map {
                coordinator.autoSpeakSlotIDs.contains($0)
            } ?? false,
            currentSpeakingSlotID: coordinator.currentSpeakingSlotID,
            playbackState: coordinator.playbackState,
            activeSlotSupportsSpeech: activeSlotID.map {
                supportsSpeechQuery($0)
            } ?? false
        )
    }

    func supportsSpeech(slotID: UUID) -> Bool {
        supportsSpeechQuery(slotID)
    }

    func isAutoSpeakArmed(slotID: UUID) -> Bool {
        coordinator.autoSpeakSlotIDs.contains(slotID)
    }

    func readLatest(slotID: UUID) -> Bool {
        coordinator.readLatestResponse(for: slotID)
    }

    func replayLatest(slotID: UUID) -> Bool {
        coordinator.replayLatestResponse(for: slotID)
    }

    func pause(slotID: UUID) -> Bool {
        coordinator.pauseCurrentSpeech(for: slotID)
    }

    func resume(slotID: UUID) -> Bool {
        coordinator.resumeCurrentSpeech(for: slotID)
    }

    func stop(slotID: UUID) -> Bool {
        guard coordinator.currentSpeakingSlotID == slotID,
              coordinator.playbackState != .idle else {
            return false
        }
        coordinator.stop()
        return true
    }

    func stopCurrentPlayback() -> Bool {
        // Global Stop also cancels pending extraction and queued source work;
        // it is not limited to an utterance that has already reached the
        // shared transport.
        coordinator.stop()
        return true
    }

    func toggleAutoSpeak(slotID: UUID) -> Bool {
        coordinator.toggleAutoSpeak(for: slotID)
        return true
    }

    func playPreview(_ requests: [SpeechUtteranceRequest]) {
        coordinator.playPreview(requests)
    }
}

/// Routes semantic speech commands to the source that owns a Slot. C1's
/// registry is deliberately explicit and contains ChatGPT only.
@MainActor
final class SpeechCommandRouter {
    private let sources: [SpeechSourceKind: SpeechSourceAdapter]
    private let playbackSession: SpeechPlaybackSessionController
    private let activeSlotIDProvider: @MainActor () -> UUID?

    init(
        sources: [SpeechSourceAdapter],
        playbackSession: SpeechPlaybackSessionController,
        activeSlotIDProvider: @escaping @MainActor () -> UUID?
    ) {
        self.sources = Dictionary(uniqueKeysWithValues: sources.map {
            ($0.kind, $0)
        })
        self.playbackSession = playbackSession
        self.activeSlotIDProvider = activeSlotIDProvider
    }

    var registeredSourceKinds: Set<SpeechSourceKind> {
        Set(sources.keys)
    }

    var presentation: SpeechSourcePresentation {
        guard let source = sources[.chatGPT] else {
            return SpeechSourcePresentation(
                sourceKind: .chatGPT,
                activeSlotID: activeSlotIDProvider(),
                autoSpeakSlotIDs: [],
                activeSlotAutoSpeakEnabled: false,
                currentSpeakingSlotID: playbackSession.activeSlotID,
                playbackState: playbackSession.playbackState,
                activeSlotSupportsSpeech: false
            )
        }
        return source.presentation
    }

    @discardableResult
    func readLatestForActiveSlot() -> SpeechCommandOutcome {
        guard let slotID = activeSlotIDProvider(),
              let source = sources[.chatGPT],
              source.supportsSpeech(slotID: slotID) else {
            return .rejected
        }
        // Preserve the pre-router contract: an unavailable source/Slot is a
        // rejected command, while a source-side extraction failure is a
        // handled no-op and must not produce a UI beep.
        guard source.readLatest(slotID: slotID) else { return .noOp }
        return .manualReadAccepted(sourceKind: source.kind, slotID: slotID)
    }

    @discardableResult
    func readPauseResumeForActiveSlot() -> SpeechCommandOutcome {
        guard let slotID = activeSlotIDProvider() else { return .rejected }
        guard let chatGPT = sources[.chatGPT] else { return .rejected }

        if let activeContext = playbackSession.activeContext,
           activeContext.slotID == slotID,
           let source = sources[activeContext.sourceKind] {
            switch playbackSession.playbackState {
            case .speaking:
                return source.pause(slotID: slotID)
                    ? .paused(sourceKind: source.kind, slotID: slotID)
                    : .rejected
            case .paused:
                return source.resume(slotID: slotID)
                    ? .resumed(sourceKind: source.kind, slotID: slotID)
                    : .rejected
            case .starting, .pausing, .resuming:
                return .noOp
            case .idle:
                break
            }
        }

        guard chatGPT.supportsSpeech(slotID: slotID) else {
            return .rejected
        }
        guard chatGPT.readLatest(slotID: slotID) else { return .noOp }
        return .manualReadAccepted(sourceKind: .chatGPT, slotID: slotID)
    }

    @discardableResult
    func replayLatestForActiveSlot() -> SpeechCommandOutcome {
        guard let slotID = activeSlotIDProvider(),
              let source = sources[.chatGPT],
              source.supportsSpeech(slotID: slotID) else {
            return .rejected
        }
        guard source.replayLatest(slotID: slotID) else { return .noOp }
        return .replayAccepted(sourceKind: source.kind, slotID: slotID)
    }

    @discardableResult
    func readPauseResumeSpeechForActiveSlot() -> SpeechCommandOutcome {
        readPauseResumeForActiveSlot()
    }

    @discardableResult
    func replayLatestSpeechForActiveSlot() -> SpeechCommandOutcome {
        replayLatestForActiveSlot()
    }

    @discardableResult
    func stopSpeechForActiveSlot() -> SpeechCommandOutcome {
        stopForActiveSlot()
    }

    @discardableResult
    func stopForActiveSlot() -> SpeechCommandOutcome {
        guard let slotID = activeSlotIDProvider(),
              let activeContext = playbackSession.activeContext,
              activeContext.slotID == slotID,
              let source = sources[activeContext.sourceKind],
              playbackSession.playbackState != .idle,
              source.stop(slotID: slotID) else {
            return .noOp
        }
        return .stopped(sourceKind: source.kind, slotID: slotID)
    }

    @discardableResult
    func stopCurrentPlayback() -> SpeechCommandOutcome {
        let activeContext = playbackSession.activeContext
        let source = activeContext.flatMap { sources[$0.sourceKind] }
            ?? sources[.chatGPT]
        guard let source, source.stopCurrentPlayback() else {
            return .noOp
        }
        return .stopped(
            sourceKind: source.kind,
            slotID: activeContext?.slotID
        )
    }

    @discardableResult
    func toggleAutoSpeakForActiveSlot() -> SpeechCommandOutcome {
        guard let slotID = activeSlotIDProvider(),
              let source = sources[.chatGPT],
              source.supportsSpeech(slotID: slotID)
                    || source.isAutoSpeakArmed(slotID: slotID),
              source.toggleAutoSpeak(slotID: slotID) else {
            return .rejected
        }
        let enabled = source.isAutoSpeakArmed(slotID: slotID)
        return .autoSpeakToggled(
            sourceKind: source.kind,
            slotID: slotID,
            enabled: enabled
        )
    }

    func playPreview(_ requests: [SpeechUtteranceRequest]) {
        sources[.chatGPT]?.playPreview(requests)
    }
}
