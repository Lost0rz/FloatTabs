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
    let capabilities: SpeechCapabilities
    let labels: SpeechPresentationLabels
    let hasActiveSourceSession: Bool

    init(
        sourceKind: SpeechSourceKind,
        activeSlotID: UUID?,
        autoSpeakSlotIDs: Set<UUID>,
        activeSlotAutoSpeakEnabled: Bool,
        currentSpeakingSlotID: UUID?,
        playbackState: SpeechPlaybackState,
        activeSlotSupportsSpeech: Bool,
        capabilities: SpeechCapabilities = .chatGPT,
        labels: SpeechPresentationLabels = .chatGPT,
        hasActiveSourceSession: Bool = false
    ) {
        self.sourceKind = sourceKind
        self.activeSlotID = activeSlotID
        self.autoSpeakSlotIDs = autoSpeakSlotIDs
        self.activeSlotAutoSpeakEnabled = activeSlotAutoSpeakEnabled
        self.currentSpeakingSlotID = currentSpeakingSlotID
        self.playbackState = playbackState
        self.activeSlotSupportsSpeech = activeSlotSupportsSpeech
        self.capabilities = capabilities
        self.labels = labels
        self.hasActiveSourceSession = hasActiveSourceSession
    }

    var railPresentation: SpeechRailPresentation {
        SpeechRailPresentation(
            activeSlotID: activeSlotID,
            autoSpeakSlotIDs: autoSpeakSlotIDs,
            activeSlotAutoSpeakEnabled: activeSlotAutoSpeakEnabled,
            currentSpeakingSlotID: currentSpeakingSlotID,
            playbackState: playbackState,
            activeSlotSupportsSpeech: activeSlotSupportsSpeech,
            capabilities: capabilities,
            labels: labels,
            hasActiveSourceSession: hasActiveSourceSession
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
        activeSlotIDProvider: @escaping @MainActor () -> UUID? = { nil },
        supportsSpeechQuery: @escaping @MainActor (UUID) -> Bool = { _ in true }
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
            } ?? false,
            capabilities: activeSlotID.map {
                supportsSpeechQuery($0) ? .chatGPT : .unsupported
            } ?? .unsupported,
            labels: .chatGPT,
            hasActiveSourceSession: coordinator.currentSpeakingSlotID != nil
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
        if let slotID = activeSlotIDProvider(),
           let source = resolveSource(for: slotID, allowingArmed: true) {
            return source.presentation
        }
        // Preserve the C1 ChatGPT presentation for a regular unsupported web
        // Slot. A newly registered source must not become the fallback merely
        // because it sorts first; source capability still has to be proven.
        guard let source = sources[.chatGPT] ?? orderedSources.first else {
            fatalError("SpeechCommandRouter requires a registered source")
        }
        return source.presentation
    }

    @discardableResult
    func readLatestForActiveSlot() -> SpeechCommandOutcome {
        guard let slotID = activeSlotIDProvider(),
              let source = resolveSource(for: slotID) else {
            return .rejected
        }
        // Preserve the pre-router contract: an unavailable source/Slot is a
        // rejected command, while a source-side extraction failure is a
        // handled no-op and must not produce a UI beep.
        _ = stopCurrentPlayback()
        guard source.readLatest(slotID: slotID) else { return .noOp }
        return .manualReadAccepted(sourceKind: source.kind, slotID: slotID)
    }

    @discardableResult
    func readPauseResumeForActiveSlot() -> SpeechCommandOutcome {
        guard let slotID = activeSlotIDProvider() else { return .rejected }

        if let activeContext = playbackSession.activeContext,
           activeContext.slotID == slotID {
            // An active transport owner always wins. Never fall through to a
            // different source when that owner cannot be resolved.
            guard let source = sources[activeContext.sourceKind] else {
                return .noOp
            }
            switch playbackSession.playbackState {
            case .speaking:
                return source.pause(slotID: slotID)
                    ? .paused(sourceKind: source.kind, slotID: slotID)
                    : .noOp
            case .paused:
                return source.resume(slotID: slotID)
                    ? .resumed(sourceKind: source.kind, slotID: slotID)
                    : .noOp
            case .starting, .pausing, .resuming:
                return .noOp
            case .idle:
                return .noOp
            }
        }

        guard let source = resolveSource(for: slotID) else {
            return .rejected
        }
        _ = stopCurrentPlayback()
        guard source.readLatest(slotID: slotID) else { return .noOp }
        return .manualReadAccepted(sourceKind: source.kind, slotID: slotID)
    }

    @discardableResult
    func replayLatestForActiveSlot() -> SpeechCommandOutcome {
        guard let slotID = activeSlotIDProvider(),
              let source = resolveSource(for: slotID) else {
            return .rejected
        }
        _ = stopCurrentPlayback()
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
        guard let slotID = activeSlotIDProvider() else {
            return .noOp
        }
        if let activeContext = playbackSession.activeContext,
           activeContext.slotID == slotID,
           let source = sources[activeContext.sourceKind],
           playbackSession.playbackState != .idle,
           source.stop(slotID: slotID) {
            return .stopped(sourceKind: source.kind, slotID: slotID)
        }
        if let sourceKind = playbackSession.activeSourceSessionKind,
           playbackSession.activeSourceSessionSlotID == slotID,
           let source = sources[sourceKind],
           source.stop(slotID: slotID) {
            return .stopped(sourceKind: source.kind, slotID: slotID)
        }
        return .noOp
    }

    @discardableResult
    func stopCurrentPlayback() -> SpeechCommandOutcome {
        let activeContext = playbackSession.activeContext
        let activeSourceKind = activeContext?.sourceKind
            ?? playbackSession.activeSourceSessionKind
        let activeSourceSlotID = activeContext?.slotID
            ?? playbackSession.activeSourceSessionSlotID
        var targetSources = orderedSources
        if let activeSourceKind,
           let activeIndex = targetSources.firstIndex(where: {
               $0.kind == activeSourceKind
           }) {
            // Active ownership changes ordering and outcome priority only. It
            // must never remove the other registered sources from Global Stop.
            let activeSource = targetSources.remove(at: activeIndex)
            targetSources.insert(activeSource, at: 0)
        }
        guard !targetSources.isEmpty else {
            return .noOp
        }

        let stoppedSources = targetSources.filter { $0.stopCurrentPlayback() }
        let stoppedSource = activeSourceKind.flatMap { activeSourceKind in
            stoppedSources.first { $0.kind == activeSourceKind }
        } ?? stoppedSources.first
        guard let stoppedSource else { return .noOp }
        return .stopped(
            sourceKind: stoppedSource.kind,
            slotID: stoppedSource.kind == activeSourceKind
                ? activeSourceSlotID
                : nil
        )
    }

    @discardableResult
    func toggleAutoSpeakForActiveSlot() -> SpeechCommandOutcome {
        guard let slotID = activeSlotIDProvider(),
              let source = resolveSource(for: slotID, allowingArmed: true),
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
        // Settings preview is an existing ChatGPT-only compatibility path in
        // C1. It is intentionally not generic Slot source resolution.
        _ = stopCurrentPlayback()
        sources[.chatGPT]?.playPreview(requests)
    }

    private var orderedSources: [SpeechSourceAdapter] {
        sources.values.sorted { $0.kind.rawValue < $1.kind.rawValue }
    }

    private func resolveSource(
        for slotID: UUID,
        allowingArmed: Bool = false
    ) -> SpeechSourceAdapter? {
        if let supportingSource = orderedSources.first(where: {
            $0.supportsSpeech(slotID: slotID)
        }) {
            return supportingSource
        }
        guard allowingArmed else { return nil }
        return orderedSources.first(where: {
            $0.isAutoSpeakArmed(slotID: slotID)
        })
    }
}
