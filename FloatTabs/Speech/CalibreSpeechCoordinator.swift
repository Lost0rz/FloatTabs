import Foundation

enum CalibreReaderSpeechState: Equatable, Sendable {
    case idle
    case extracting
    case speakingUnit
    case pausedAtBoundary
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
        let leaseToken: UInt64
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
    private(set) var state: CalibreReaderSpeechState = .idle

    var onPresentationChange: (() -> Void)?

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
        ownedSession != nil
            && playbackSession.ownsSourceSession(sourceKind: .calibreReader)
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
        return playbackSession.pause(
            sourceKind: .calibreReader,
            slotID: slotID
        )
    }

    func resume(slotID: UUID) -> Bool {
        guard activeSlotID == slotID else { return false }

        switch state {
        case .speakingUnit:
            return playbackSession.resume(
                sourceKind: .calibreReader,
                slotID: slotID
            ) != .rejected
        case .pausedAtBoundary:
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
            advanceAfterBoundary(operation: operation)
            return true
        case .idle, .extracting, .awaitingAdvance, .awaitingRelocation:
            return false
        }
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
            playbackSession.releaseSourceSession(
                sourceKind: .calibreReader,
                token: oldSession.leaseToken
            )
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
              playbackSession.ownsSourceSession(
                  sourceKind: .calibreReader,
                  token: ownedSession.leaseToken
              ) else {
            return
        }

        switch event {
        case .started:
            state = .speakingUnit
            notifyPresentationChange()
        case .paused:
            notifyPresentationChange()
        case .continued:
            state = .speakingUnit
            notifyPresentationChange()
        case let .finished(_, boundary):
            handleFinished(boundary: boundary)
        case .cancelled:
            failCurrentOperation(operation: operationGeneration)
        }
    }

    var isSpeechProtectionActive: Bool {
        hasActiveSourceSession
    }

    func isSpeechProtectionActive(slotID: UUID) -> Bool {
        ownedSession?.slotID == slotID && hasActiveSourceSession
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
        state = .speakingUnit
        notifyPresentationChange()
        speakNextSegment(operation: operation)
    }

    private func speakNextSegment(operation: UInt64) {
        guard let ownedSession,
              isCurrent(operation: operation),
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
            state = .pausedAtBoundary
            notifyPresentationChange()
        case .notAtBoundary:
            if nextSegmentIndex < segments.count {
                speakNextSegment(operation: operation)
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

        state = .awaitingAdvance
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

    private func advanceAfterBoundary(operation: UInt64) {
        guard let unit = currentUnit,
              let ownedSession,
              let bridge = bridgeProvider(ownedSession.slotID) else {
            playbackSession.finishBoundaryResumeWithoutSpeech()
            failCurrentOperation(operation: operation)
            return
        }
        requestAdvance(from: unit, operation: operation, bridge: bridge)
    }

    private func requestAdvance(
        from unit: CalibreReadingUnitIdentity,
        operation: UInt64,
        bridge: CalibreReaderAccess
    ) {
        nextTransitionToken &+= 1
        let transition = nextTransitionToken
        pendingTransitionToken = transition
        state = .awaitingRelocation
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
              state == .awaitingRelocation,
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

        switch state {
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
            state = .extracting
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
        case .idle, .extracting:
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
              ownedSession.leaseToken == playbackSession.activeSourceSessionToken,
              operation == operationGeneration else {
            return false
        }
        if let bridge {
            return bridge.currentDocumentIdentity == ownedSession.document
        }
        return true
    }

    private func notifyPresentationChange() {
        onPresentationChange?()
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
        return SpeechSourcePresentation(
            sourceKind: kind,
            activeSlotID: activeSlotID,
            autoSpeakSlotIDs: [],
            activeSlotAutoSpeakEnabled: false,
            currentSpeakingSlotID: coordinator.currentSpeakingSlotID,
            playbackState: playbackSession.playbackState,
            activeSlotSupportsSpeech: activeSlotID.map {
                coordinator.supportsSpeech(slotID: $0)
            } ?? false,
            capabilities: activeSlotID.map {
                coordinator.supportsSpeech(slotID: $0)
                    ? .calibreReader
                    : .unsupported
            } ?? .unsupported,
            labels: .calibreReader,
            hasActiveSourceSession: coordinator.hasActiveSourceSession
        )
    }

    func supportsSpeech(slotID: UUID) -> Bool {
        coordinator.supportsSpeech(slotID: slotID)
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
        coordinator.stop()
        return hadSession
    }

    func toggleAutoSpeak(slotID: UUID) -> Bool { false }

    func playPreview(_ requests: [SpeechUtteranceRequest]) {}
}
