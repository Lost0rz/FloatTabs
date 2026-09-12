import Foundation

enum CalibreReaderSpeechState: Equatable, Sendable {
    case idle
    case extracting
    case speakingUnit
    case pausedAtBoundary
    case suspended
    case awaitingAdvance
    case awaitingRelocation
}

enum CalibreReaderTextNormalizer {
    static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00AD}", with: "")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
protocol CalibreSpeechWatchdogScheduling: AnyObject {
    func schedule(
        after delay: TimeInterval,
        operation: @escaping @MainActor () -> Void
    ) -> AnyObject
    func cancel(_ task: AnyObject)
}

@MainActor
final class CalibreSpeechWatchdogScheduler: CalibreSpeechWatchdogScheduling {
    func schedule(
        after delay: TimeInterval,
        operation: @escaping @MainActor () -> Void
    ) -> AnyObject {
        let workItem = DispatchWorkItem {
            operation()
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0, delay),
            execute: workItem
        )
        return workItem
    }

    func cancel(_ task: AnyObject) {
        (task as? DispatchWorkItem)?.cancel()
    }
}

/// Source-local continuous-reading lifecycle. The shared Session remains the
/// sole AV/state authority; this coordinator owns only the reader unit and
/// the asynchronous relocation transition between units.
@MainActor
final class CalibreSpeechCoordinator {
    private struct OwnedSession {
        let slotID: UUID
        var leaseToken: UInt64?
        let document: CalibreReaderDocumentIdentity
    }

    private let playbackSession: SpeechPlaybackSessionController
    private let bridgeProvider: @MainActor (UUID) -> CalibreReaderAccess?
    private let watchdogScheduler: CalibreSpeechWatchdogScheduling
    private let relocationWatchdogDelay: TimeInterval
    private var ownedSession: OwnedSession?
    private var currentUnit: CalibreReadingUnitIdentity?
    private var sourceSequence: UInt64 = 0
    private var operationGeneration: UInt64 = 0
    private var nextTransitionToken: UInt64 = 0
    private var pendingTransitionToken: UInt64?
    private var relocationWatchdog: AnyObject?
    private var segments: [SpeechUtteranceRequest] = []
    private var nextSegmentIndex = 0
    private var currentSegmentIndex: Int?
    /// Background suspension is source-local. The shared playback session
    /// remains the only transport authority, while this remembers the state
    /// whose bounded transaction may still settle underneath suspension.
    private var suspendedState: CalibreReaderSpeechState?
    private(set) var state: CalibreReaderSpeechState = .idle

    var onPresentationChange: (() -> Void)?
    /// Reports only changes to the WebView-runtime protection condition. This
    /// lets lifecycle timers restart after EOF/Stop/suspension without making
    /// the source lease itself a permanent WebView retention reason.
    var onSpeechProtectionChange: ((UUID, Bool) -> Void)?

    convenience init(
        playbackSession: SpeechPlaybackSessionController,
        bridgeProvider: @escaping @MainActor (UUID) -> CalibreReaderAccess?
    ) {
        self.init(
            playbackSession: playbackSession,
            bridgeProvider: bridgeProvider,
            watchdogScheduler: CalibreSpeechWatchdogScheduler(),
            relocationWatchdogDelay: 5
        )
    }

    init(
        playbackSession: SpeechPlaybackSessionController,
        bridgeProvider: @escaping @MainActor (UUID) -> CalibreReaderAccess?,
        watchdogScheduler: CalibreSpeechWatchdogScheduling,
        relocationWatchdogDelay: TimeInterval = 5
    ) {
        self.playbackSession = playbackSession
        self.bridgeProvider = bridgeProvider
        self.watchdogScheduler = watchdogScheduler
        self.relocationWatchdogDelay = relocationWatchdogDelay
    }

    var activeSlotID: UUID? {
        ownedSession?.slotID
    }

    var hasActiveSourceSession: Bool {
        guard let leaseToken = ownedSession?.leaseToken else { return false }
        return playbackSession.ownsSourceSession(
            sourceKind: .calibreReader,
            token: leaseToken
        )
    }

    /// Source-local reading state can remain resumable after the shared
    /// source-session lease and transport have been yielded to another source.
    func hasResumableState(slotID: UUID) -> Bool {
        guard ownedSession?.slotID == slotID else { return false }
        switch state {
        case .idle:
            return false
        case .extracting, .speakingUnit, .pausedAtBoundary, .suspended,
             .awaitingAdvance, .awaitingRelocation:
            return true
        }
    }

    var isBackgroundSuspended: Bool {
        state == .suspended
    }

    var currentSpeakingSlotID: UUID? {
        guard hasActiveSourceSession else { return nil }
        return playbackSession.activeSourceSessionSlotID
    }

    func supportsSpeech(slotID: UUID) -> Bool {
        bridgeProvider(slotID)?.isReaderCandidate == true
    }

    func readCurrentPage(slotID: UUID) -> Bool {
        guard let bridge = bridgeProvider(slotID),
              bridge.isReaderCandidate,
              let document = bridge.currentDocumentIdentity else {
            return false
        }

        stop()
        guard let leaseToken = playbackSession.acquireSourceSession(
            sourceKind: .calibreReader,
            slotID: slotID
        ) else {
            return false
        }

        operationGeneration &+= 1
        let operation = operationGeneration
        ownedSession = OwnedSession(
            slotID: slotID,
            leaseToken: leaseToken,
            document: document
        )
        currentUnit = nil
        pendingTransitionToken = nil
        bridge.onRelocation = { [weak self] relocation in
            self?.handleRelocation(relocation, operation: operation)
        }
        state = .extracting
        notifyPresentationChange()
        bridge.extractCurrentReadingUnit { [weak self, weak bridge] result in
            guard let self,
                  let bridge,
                  self.isCurrent(operation: operation, bridge: bridge) else {
                return
            }
            switch result {
            case let .success(page):
                self.beginUnit(page, operation: operation, bridge: bridge)
            case .failure:
                self.failCurrentOperation(operation: operation)
            }
        }
        return true
    }

    func replayCurrentPage(slotID: UUID) -> Bool {
        readCurrentPage(slotID: slotID)
    }

    func pause(slotID: UUID) -> Bool {
        guard activeSlotID == slotID,
              state == .speakingUnit else {
            return false
        }
        let accepted = playbackSession.pause(
            sourceKind: .calibreReader,
            slotID: slotID
        )
        if accepted {
            // Manual Pause is a source-local resumable checkpoint, not a
            // claim on the app-global transport. Keep the current segment as
            // the safe replay boundary, then yield both shared authorities so
            // ChatGPT Auto Speak can be admitted under either background
            // policy.
            yieldSharedSpeechAuthorityForManualPause()
        }
        notifyPresentationChange()
        return accepted
    }

    func resume(slotID: UUID) -> Bool {
        guard activeSlotID == slotID else { return false }

        switch state {
        case .speakingUnit:
            if !hasActiveSourceSession {
                guard let operation = currentOperation else { return false }
                return reacquireAndResumeSpeakingUnit(
                    slotID: slotID,
                    operation: operation
                )
            }
            let disposition = playbackSession.resume(
                sourceKind: .calibreReader,
                slotID: slotID
            )
            notifyPresentationChange()
            return disposition != .rejected
        case .pausedAtBoundary:
            if !hasActiveSourceSession {
                guard let operation = currentOperation else { return false }
                return reacquireAndResumePausedBoundary(
                    slotID: slotID,
                    operation: operation
                )
            }
            guard playbackSession.resume(
                sourceKind: .calibreReader,
                slotID: slotID
            ) == .resumeAtSegmentBoundary,
            playbackSession.beginBoundaryResume() else {
                return false
            }
            guard let operation = currentOperation else {
                playbackSession.finishBoundaryResumeWithoutSpeech()
                return false
            }
            continueAfterBoundary(operation: operation)
            return true
        case .suspended:
            guard let bridge = bridgeProvider(slotID),
                  bridge.isReaderCandidate,
                  let ownedSession,
                  bridge.currentDocumentIdentity == ownedSession.document,
                  let operation = currentOperation else {
                stop()
                return false
            }

            let underlyingState = suspendedState ?? .speakingUnit
            if !hasActiveSourceSession {
                guard playbackSession.activeContext == nil,
                      let leaseToken = playbackSession.acquireSourceSession(
                          sourceKind: .calibreReader,
                          slotID: slotID
                      ) else {
                    return false
                }
                guard var currentSession = self.ownedSession,
                      currentSession.slotID == slotID else {
                    playbackSession.releaseSourceSession(
                        sourceKind: .calibreReader,
                        token: leaseToken
                    )
                    return false
                }
                currentSession.leaseToken = leaseToken
                self.ownedSession = currentSession

                switch underlyingState {
                case .speakingUnit, .pausedAtBoundary:
                    suspendedState = nil
                    state = .speakingUnit
                    notifyPresentationChange()
                    if nextSegmentIndex < segments.count {
                        speakNextSegment(operation: operation)
                    } else {
                        finishCurrentUnit(operation: operation)
                    }
                    return true
                case .extracting, .awaitingAdvance, .awaitingRelocation:
                    suspendedState = nil
                    state = underlyingState
                    notifyPresentationChange()
                    return true
                case .idle, .suspended:
                    playbackSession.releaseSourceSession(
                        sourceKind: .calibreReader,
                        token: leaseToken
                    )
                    self.ownedSession?.leaseToken = nil
                    return false
                }
            }
            if underlyingState == .speakingUnit,
               playbackSession.playbackState == .starting {
                suspendedState = nil
                state = .speakingUnit
                notifyPresentationChange()
                return true
            }
            let resumeDisposition = playbackSession.resume(
                sourceKind: .calibreReader,
                slotID: slotID
            )
            switch resumeDisposition {
            case .continuedCurrentUtterance:
                suspendedState = nil
                state = .speakingUnit
                notifyPresentationChange()
                return true
            case .resumeAtSegmentBoundary:
                guard playbackSession.beginBoundaryResume() else {
                    return false
                }
                suspendedState = nil
                state = .speakingUnit
                notifyPresentationChange()
                continueAfterBoundary(operation: operation)
                return true
            case .rejected:
                // A suspension that outlived its shared transport must not
                // invent a new CFI or silently restart from an unknown unit.
                if underlyingState == .speakingUnit {
                    guard playbackSession.playbackState == .idle else {
                        return false
                    }
                    suspendedState = nil
                    state = .speakingUnit
                    notifyPresentationChange()
                    if nextSegmentIndex < segments.count {
                        speakNextSegment(operation: operation)
                    } else {
                        finishCurrentUnit(operation: operation)
                    }
                    return true
                }
                if underlyingState == .pausedAtBoundary,
                   playbackSession.playbackState == .idle {
                    suspendedState = nil
                    state = .speakingUnit
                    notifyPresentationChange()
                    if nextSegmentIndex < segments.count {
                        speakNextSegment(operation: operation)
                    } else {
                        finishCurrentUnit(operation: operation)
                    }
                    return true
                }
                guard underlyingState == .extracting
                        || underlyingState == .awaitingAdvance
                        || underlyingState == .awaitingRelocation else {
                    return false
                }
                suspendedState = nil
                state = underlyingState
                notifyPresentationChange()
                return true
            }
        case .idle, .extracting, .awaitingAdvance, .awaitingRelocation:
            return false
        }
    }

    /// Applies the source half of Background Media Policy. Allowing
    /// background audio never resumes a suspended source; only an explicit
    /// Resume command can do that.
    func handleBackgroundMediaPolicyChange(
        slotID: UUID,
        policy: BackgroundMediaPolicy,
        isInactive: Bool
    ) {
        guard activeSlotID == slotID else { return }
        guard policy == .pauseWhenInactive, isInactive else { return }
        suspendForBackgroundIfNeeded(slotID: slotID)
    }

    func handleBecameInactive(profile: WebAppProfile) {
        handleBackgroundMediaPolicyChange(
            slotID: profile.id,
            policy: profile.backgroundMediaPolicy,
            isInactive: true
        )
    }

    /// Tears down the source before SlotLifecycleCoordinator releases the
    /// underlying WebView. Protection notifications are intentionally
    /// suppressed here so a release cannot recreate a fresh inactive plan
    /// while its current plan is being removed.
    func prepareForRuntimeRelease(slotID: UUID) {
        guard activeSlotID == slotID else { return }
        suppressSpeechProtectionNotifications = true
        stop()
        suppressSpeechProtectionNotifications = false
    }

    func stop() {
        operationGeneration &+= 1
        cancelRelocationWatchdog()
        let oldSession = ownedSession
        ownedSession = nil
        currentUnit = nil
        pendingTransitionToken = nil
        segments.removeAll()
        nextSegmentIndex = 0
        currentSegmentIndex = nil
        suspendedState = nil
        state = .idle

        if let slotID = oldSession?.slotID,
           let bridge = bridgeProvider(slotID) {
            bridge.onRelocation = nil
            bridge.cancelPendingWork()
        }
        if playbackSession.activeContext?.sourceKind == .calibreReader {
            playbackSession.stop()
        }
        if let oldSession {
            if let leaseToken = oldSession.leaseToken {
                playbackSession.releaseSourceSession(
                    sourceKind: .calibreReader,
                    token: leaseToken
                )
            }
        }
        notifyPresentationChange()
    }

    func resetRuntime(slotID: UUID) {
        guard ownedSession?.slotID == slotID else { return }
        stop()
    }

    func removeSlot(slotID: UUID) {
        resetRuntime(slotID: slotID)
    }

    func handlePlaybackEvent(_ event: SpeechPlaybackEvent) {
        guard let ownedSession,
              event.context.sourceKind == .calibreReader,
              event.context.slotID == ownedSession.slotID,
              let leaseToken = ownedSession.leaseToken,
              playbackSession.ownsSourceSession(
                  sourceKind: .calibreReader,
                  token: leaseToken
              ) else {
            return
        }

        switch event {
        case .started:
            if isSuspendedForBackground {
                _ = playbackSession.pause(
                    sourceKind: .calibreReader,
                    slotID: ownedSession.slotID
                )
                notifyPresentationChange()
                return
            }
            state = .speakingUnit
            notifyPresentationChange()
        case .paused:
            notifyPresentationChange()
        case .continued:
            if isSuspendedForBackground {
                _ = playbackSession.pause(
                    sourceKind: .calibreReader,
                    slotID: ownedSession.slotID
                )
                notifyPresentationChange()
                return
            }
            suspendedState = nil
            state = .speakingUnit
            notifyPresentationChange()
        case let .finished(_, boundary):
            handleFinished(boundary: boundary)
        case .cancelled:
            failCurrentOperation(operation: operationGeneration)
        }
    }

    var isSpeechProtectionActive: Bool {
        isSpeechRuntimeProtectionActive
    }

    func isSpeechProtectionActive(slotID: UUID) -> Bool {
        isSpeechRuntimeProtectionActive(slotID: slotID)
    }

    var isSpeechRuntimeProtectionActive: Bool {
        guard let slotID = ownedSession?.slotID else { return false }
        return isSpeechRuntimeProtectionActive(slotID: slotID)
    }

    func isSpeechRuntimeProtectionActive(slotID: UUID) -> Bool {
        guard ownedSession?.slotID == slotID,
              hasActiveSourceSession else {
            return false
        }
        switch state {
        case .extracting, .awaitingAdvance, .awaitingRelocation:
            return true
        case .speakingUnit:
            switch playbackSession.playbackState {
            case .starting, .speaking, .resuming:
                return true
            case .idle, .pausing, .paused:
                return false
            }
        case .idle, .pausedAtBoundary, .suspended:
            return false
        }
    }

    var capabilities: SpeechCapabilities {
        .calibreReader
    }

    private var currentOperation: UInt64? {
        ownedSession == nil ? nil : operationGeneration
    }

    private func beginUnit(
        _ page: CalibreReaderPage,
        operation: UInt64,
        bridge: CalibreReaderAccess
    ) {
        guard let ownedSession,
              page.identity.document == ownedSession.document,
              bridge.currentDocumentIdentity == ownedSession.document else {
            failCurrentOperation(operation: operation)
            return
        }
        let text = CalibreReaderTextNormalizer.normalize(page.text)
        let requests = SpeechLanguageRouter.utteranceRequests(for: text)
        guard !requests.isEmpty else {
            failCurrentOperation(operation: operation)
            return
        }

        sourceSequence &+= 1
        currentUnit = page.identity
        segments = requests
        nextSegmentIndex = 0
        currentSegmentIndex = nil
        if isSuspendedForBackground {
            suspendedState = .speakingUnit
            notifyPresentationChange()
            return
        }
        state = .speakingUnit
        notifyPresentationChange()
        speakNextSegment(operation: operation)
    }

    private func speakNextSegment(operation: UInt64) {
        guard let ownedSession,
              isCurrent(operation: operation),
              !isSuspendedForBackground,
              nextSegmentIndex < segments.count else {
            return
        }
        let index = nextSegmentIndex
        let request = segments[index]
        nextSegmentIndex += 1
        currentSegmentIndex = index
        let context = SpeechPlaybackContext(
            sourceKind: .calibreReader,
            slotID: ownedSession.slotID,
            sourceSequence: sourceSequence,
            origin: .manual
        )
        guard playbackSession.speak(
            context: context,
            text: request.text,
            languageRole: request.languageRole
        ) else {
            failCurrentOperation(operation: operation)
            return
        }
    }

    private func handleFinished(
        boundary: SpeechPlaybackBoundaryDisposition
    ) {
        guard let operation = currentOperation else { return }
        switch boundary {
        case .pausedAtSegmentBoundary:
            if isSuspendedForBackground {
                suspendedState = .pausedAtBoundary
                notifyPresentationChange()
                return
            }
            state = .pausedAtBoundary
            notifyPresentationChange()
        case .notAtBoundary:
            if nextSegmentIndex < segments.count {
                if isSuspendedForBackground {
                    suspendedState = .speakingUnit
                    notifyPresentationChange()
                } else {
                    speakNextSegment(operation: operation)
                }
            } else {
                finishCurrentUnit(operation: operation)
            }
        }
    }

    private func finishCurrentUnit(operation: UInt64) {
        guard let unit = currentUnit,
              let ownedSession,
              let bridge = bridgeProvider(ownedSession.slotID),
              isCurrent(operation: operation, bridge: bridge) else {
            failCurrentOperation(operation: operation)
            return
        }

        if isSuspendedForBackground {
            suspendedState = .awaitingAdvance
        } else {
            state = .awaitingAdvance
        }
        notifyPresentationChange()
        bridge.extractCurrentReadingUnit { [weak self, weak bridge] result in
            guard let self,
                  let bridge,
                  self.isCurrent(operation: operation, bridge: bridge) else {
                return
            }
            guard case let .success(page) = result,
                  page.identity.document == ownedSession.document else {
                self.failCurrentOperation(operation: operation)
                return
            }
            guard page.identity == unit else {
                self.terminateExternalRelocation(operation: operation)
                return
            }
            guard !page.isAtEnd else {
                self.finishSession(operation: operation)
                return
            }
            self.requestAdvance(
                from: unit,
                operation: operation,
                bridge: bridge
            )
        }
    }

    private func continueAfterBoundary(operation: UInt64) {
        guard isCurrent(operation: operation) else {
            playbackSession.finishBoundaryResumeWithoutSpeech()
            return
        }

        if nextSegmentIndex < segments.count {
            // The ReadingUnit remains the source item during a boundary
            // handoff. SpeechPlaybackSessionController mints the fresh
            // transport callback token when this segment is admitted.
            state = .speakingUnit
            notifyPresentationChange()
            speakNextSegment(operation: operation)
            return
        }

        // A boundary pause on the final segment still needs the ordinary
        // ReadingUnit completion/revalidation path. End the empty shared
        // transport handoff first so an EOF or page advance never leaves the
        // session in `.resuming` while no new utterance is pending.
        playbackSession.finishBoundaryResumeWithoutSpeech()
        finishCurrentUnit(operation: operation)
    }

    private func requestAdvance(
        from unit: CalibreReadingUnitIdentity,
        operation: UInt64,
        bridge: CalibreReaderAccess
    ) {
        nextTransitionToken &+= 1
        let transition = nextTransitionToken
        pendingTransitionToken = transition
        if isSuspendedForBackground {
            suspendedState = .awaitingRelocation
        } else {
            state = .awaitingRelocation
        }
        notifyPresentationChange()
        bridge.requestAdvance(
            from: unit,
            transitionToken: transition
        ) { [weak self] accepted in
            guard let self,
                  self.isCurrent(operation: operation),
                  self.pendingTransitionToken == transition else {
                return
            }
            if !accepted {
                self.failCurrentOperation(operation: operation)
                return
            }
            self.startRelocationWatchdog(
                operation: operation,
                document: unit.document,
                transition: transition
            )
        }
    }

    private func startRelocationWatchdog(
        operation: UInt64,
        document: CalibreReaderDocumentIdentity,
        transition: UInt64
    ) {
        cancelRelocationWatchdog()
        relocationWatchdog = watchdogScheduler.schedule(
            after: relocationWatchdogDelay
        ) { [weak self] in
            self?.handleRelocationWatchdog(
                operation: operation,
                document: document,
                transition: transition
            )
        }
    }

    private func cancelRelocationWatchdog() {
        guard let relocationWatchdog else { return }
        watchdogScheduler.cancel(relocationWatchdog)
        self.relocationWatchdog = nil
    }

    private func handleRelocationWatchdog(
        operation: UInt64,
        document: CalibreReaderDocumentIdentity,
        transition: UInt64
    ) {
        relocationWatchdog = nil
        guard let ownedSession,
              isCurrent(operation: operation),
              ownedSession.document == document,
              operationalState == .awaitingRelocation,
              pendingTransitionToken == transition else {
            return
        }
        failCurrentOperation(operation: operation)
    }

    private func handleRelocation(
        _ relocation: CalibreReaderRelocation,
        operation: UInt64
    ) {
        guard let ownedSession,
              isCurrent(operation: operation),
              relocation.identity.document == ownedSession.document else {
            return
        }

        switch operationalState {
        case .awaitingRelocation:
            guard let unit = currentUnit,
                  relocation.identity != unit else {
                return
            }
            guard relocation.transitionToken == pendingTransitionToken else {
                terminateExternalRelocation(operation: operation)
                return
            }
            cancelRelocationWatchdog()
            pendingTransitionToken = nil
            guard let bridge = bridgeProvider(ownedSession.slotID) else {
                failCurrentOperation(operation: operation)
                return
            }
            if isSuspendedForBackground {
                suspendedState = .extracting
            } else {
                state = .extracting
            }
            notifyPresentationChange()
            bridge.extractCurrentReadingUnit { [weak self, weak bridge] result in
                guard let self,
                      let bridge,
                      self.isCurrent(operation: operation, bridge: bridge) else {
                    return
                }
                guard case let .success(page) = result,
                      page.identity == relocation.identity else {
                    self.failCurrentOperation(operation: operation)
                    return
                }
                self.beginUnit(page, operation: operation, bridge: bridge)
            }
        case .speakingUnit, .pausedAtBoundary, .awaitingAdvance:
            if let unit = currentUnit, relocation.identity != unit {
                terminateExternalRelocation(operation: operation)
            }
        case .idle, .extracting, .suspended:
            break
        }
    }

    private func terminateExternalRelocation(operation: UInt64) {
        guard isCurrent(operation: operation) else { return }
        stop()
    }

    private func finishSession(operation: UInt64) {
        guard isCurrent(operation: operation) else { return }
        stop()
    }

    private func failCurrentOperation(operation: UInt64) {
        guard isCurrent(operation: operation) else { return }
        stop()
    }

    private func isCurrent(
        operation: UInt64,
        bridge: CalibreReaderAccess? = nil
    ) -> Bool {
        guard let ownedSession,
              operation == operationGeneration else {
            return false
        }
        if let leaseToken = ownedSession.leaseToken,
           leaseToken != playbackSession.activeSourceSessionToken {
            return false
        }
        if let bridge {
            return bridge.currentDocumentIdentity == ownedSession.document
        }
        return true
    }

    private var isSuspendedForBackground: Bool {
        state == .suspended
    }

    private var operationalState: CalibreReaderSpeechState {
        suspendedState ?? state
    }

    private var suppressSpeechProtectionNotifications = false
    private var lastSpeechProtection = false
    private var lastSpeechProtectionSlotID: UUID?

    private func suspendForBackgroundIfNeeded(slotID: UUID) {
        guard activeSlotID == slotID,
              state != .idle,
              state != .suspended else {
            return
        }

        suspendedState = state
        state = .suspended
        if playbackSession.playbackState == .speaking {
            _ = playbackSession.pause(
                sourceKind: .calibreReader,
                slotID: slotID
            )
        }
        yieldSharedSpeechAuthorityIfNeeded()
        notifyPresentationChange()
    }

    /// Background suspension is allowed to retain reader extraction state, but
    /// it must not retain the global AV transport or source-session lease.
    /// Mid-utterance transport is restarted from the current segment boundary
    /// after an explicit Resume; a completed boundary keeps its next segment.
    private func yieldSharedSpeechAuthorityIfNeeded() {
        guard state == .suspended,
              let ownedSession else { return }

        if suspendedState == .speakingUnit {
            if let currentSegmentIndex,
               currentSegmentIndex < nextSegmentIndex {
                nextSegmentIndex = currentSegmentIndex
            }
            self.currentSegmentIndex = nil
        } else if suspendedState == .pausedAtBoundary {
            self.currentSegmentIndex = nil
        }

        let ownsCalibreTransport = playbackSession.activeContext?.sourceKind
                == .calibreReader
            && playbackSession.activeContext?.slotID == ownedSession.slotID
        if ownsCalibreTransport {
            playbackSession.stop()
        }
        if let leaseToken = ownedSession.leaseToken {
            playbackSession.releaseSourceSession(
                sourceKind: .calibreReader,
                token: leaseToken
            )
            self.ownedSession?.leaseToken = nil
        }
    }

    /// Re-admits a manually paused reader after another source has used the
    /// shared transport. The cursor has already been rewound by the manual
    /// pause checkpoint, so this starts the same source unit at a known
    /// segment boundary without extracting a new CFI.
    private func reacquireAndResumeSpeakingUnit(
        slotID: UUID,
        operation: UInt64
    ) -> Bool {
        guard let bridge = bridgeProvider(slotID),
              bridge.isReaderCandidate,
              let ownedSession,
              ownedSession.slotID == slotID,
              bridge.currentDocumentIdentity == ownedSession.document,
              isCurrent(operation: operation),
              playbackSession.activeContext == nil,
              let leaseToken = playbackSession.acquireSourceSession(
                  sourceKind: .calibreReader,
                  slotID: slotID
              ) else {
            return false
        }

        guard var currentSession = self.ownedSession,
              currentSession.slotID == slotID else {
            playbackSession.releaseSourceSession(
                sourceKind: .calibreReader,
                token: leaseToken
            )
            return false
        }
        currentSession.leaseToken = leaseToken
        self.ownedSession = currentSession
        state = .speakingUnit
        notifyPresentationChange()
        if nextSegmentIndex < segments.count {
            speakNextSegment(operation: operation)
        } else {
            finishCurrentUnit(operation: operation)
        }
        return true
    }

    private func reacquireAndResumePausedBoundary(
        slotID: UUID,
        operation: UInt64
    ) -> Bool {
        guard let bridge = bridgeProvider(slotID),
              bridge.isReaderCandidate,
              let ownedSession,
              ownedSession.slotID == slotID,
              bridge.currentDocumentIdentity == ownedSession.document,
              isCurrent(operation: operation),
              playbackSession.activeContext == nil,
              let leaseToken = playbackSession.acquireSourceSession(
                  sourceKind: .calibreReader,
                  slotID: slotID
              ) else {
            return false
        }

        guard var currentSession = self.ownedSession,
              currentSession.slotID == slotID else {
            playbackSession.releaseSourceSession(
                sourceKind: .calibreReader,
                token: leaseToken
            )
            return false
        }
        currentSession.leaseToken = leaseToken
        self.ownedSession = currentSession
        state = .speakingUnit
        notifyPresentationChange()
        if nextSegmentIndex < segments.count {
            speakNextSegment(operation: operation)
        } else {
            finishCurrentUnit(operation: operation)
        }
        return true
    }

    private func yieldSharedSpeechAuthorityForManualPause() {
        guard let ownedSession else { return }

        if state == .speakingUnit {
            if let currentSegmentIndex,
               currentSegmentIndex < nextSegmentIndex {
                nextSegmentIndex = currentSegmentIndex
            }
            currentSegmentIndex = nil
        } else if state == .pausedAtBoundary {
            currentSegmentIndex = nil
        }

        let ownsCalibreTransport = playbackSession.activeContext?.sourceKind
                == .calibreReader
            && playbackSession.activeContext?.slotID == ownedSession.slotID
        if ownsCalibreTransport {
            playbackSession.stop()
        }
        if let leaseToken = ownedSession.leaseToken {
            playbackSession.releaseSourceSession(
                sourceKind: .calibreReader,
                token: leaseToken
            )
            self.ownedSession?.leaseToken = nil
        }
    }

    private func notifyPresentationChange() {
        onPresentationChange?()
        guard !suppressSpeechProtectionNotifications else {
            lastSpeechProtection = isSpeechRuntimeProtectionActive
            lastSpeechProtectionSlotID = ownedSession?.slotID
            return
        }

        let currentSlotID = ownedSession?.slotID
        let currentProtection = isSpeechRuntimeProtectionActive
        if currentProtection != lastSpeechProtection
            || currentSlotID != lastSpeechProtectionSlotID {
            if let previousSlotID = lastSpeechProtectionSlotID,
               lastSpeechProtection {
                onSpeechProtectionChange?(previousSlotID, false)
            }
            if let currentSlotID, currentProtection {
                onSpeechProtectionChange?(currentSlotID, true)
            }
        }
        lastSpeechProtection = currentProtection
        lastSpeechProtectionSlotID = currentProtection ? currentSlotID : nil
    }
}

@MainActor
final class CalibreSpeechSourceAdapter: SpeechSourceAdapter {
    let kind: SpeechSourceKind = .calibreReader

    private let coordinator: CalibreSpeechCoordinator
    private let playbackSession: SpeechPlaybackSessionController
    private let activeSlotIDProvider: @MainActor () -> UUID?

    init(
        coordinator: CalibreSpeechCoordinator,
        playbackSession: SpeechPlaybackSessionController,
        activeSlotIDProvider: @escaping @MainActor () -> UUID? = { nil }
    ) {
        self.coordinator = coordinator
        self.playbackSession = playbackSession
        self.activeSlotIDProvider = activeSlotIDProvider
        playbackSession.register(sourceKind: .calibreReader) { [weak coordinator] event in
            coordinator?.handlePlaybackEvent(event)
        }
    }

    var presentation: SpeechSourcePresentation {
        let activeSlotID = activeSlotIDProvider()
        let isSuspended = coordinator.isBackgroundSuspended
        let resumableSlotID = activeSlotID.flatMap {
            coordinator.hasResumableState(slotID: $0) ? $0 : nil
        }
        let isYieldedResumableState = resumableSlotID != nil
            && !coordinator.hasActiveSourceSession
        return SpeechSourcePresentation(
            sourceKind: kind,
            activeSlotID: activeSlotID,
            autoSpeakSlotIDs: [],
            activeSlotAutoSpeakEnabled: false,
            currentSpeakingSlotID: coordinator.currentSpeakingSlotID,
            playbackState: isSuspended || isYieldedResumableState
                ? .paused
                : playbackSession.playbackState,
            activeSlotSupportsSpeech: activeSlotID.map {
                coordinator.supportsSpeech(slotID: $0)
            } ?? false,
            capabilities: activeSlotID.map {
                coordinator.supportsSpeech(slotID: $0)
                    ? .calibreReader
                    : .unsupported
            } ?? .unsupported,
            labels: .calibreReader,
            hasActiveSourceSession: coordinator.hasActiveSourceSession,
            resumableSlotID: resumableSlotID
        )
    }

    func supportsSpeech(slotID: UUID) -> Bool {
        coordinator.supportsSpeech(slotID: slotID)
    }

    func hasResumableState(slotID: UUID) -> Bool {
        coordinator.hasResumableState(slotID: slotID)
    }

    func isAutoSpeakArmed(slotID: UUID) -> Bool { false }

    func readLatest(slotID: UUID) -> Bool {
        coordinator.readCurrentPage(slotID: slotID)
    }

    func replayLatest(slotID: UUID) -> Bool {
        coordinator.replayCurrentPage(slotID: slotID)
    }

    func pause(slotID: UUID) -> Bool {
        coordinator.pause(slotID: slotID)
    }

    func resume(slotID: UUID) -> Bool {
        coordinator.resume(slotID: slotID)
    }

    func stop(slotID: UUID) -> Bool {
        guard coordinator.activeSlotID == slotID else { return false }
        coordinator.stop()
        return true
    }

    func stopCurrentPlayback() -> Bool {
        let hadSession = coordinator.hasActiveSourceSession
            || (coordinator.activeSlotID.map {
                coordinator.hasResumableState(slotID: $0)
            } ?? false)
        coordinator.stop()
        return hadSession
    }

    func toggleAutoSpeak(slotID: UUID) -> Bool { false }

    func playPreview(_ requests: [SpeechUtteranceRequest]) {}
}
