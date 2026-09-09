import Foundation
import WebKit

enum SpeechRequestOrigin: Equatable, Sendable {
    case automatic
    case manual
}

enum SpeechPlaybackState: Equatable, Sendable {
    case idle
    case starting
    case speaking
    case pausing
    case paused
    case resuming
}

struct SpeechRailPresentation: Equatable, Sendable {
    let activeSlotID: UUID?
    let autoSpeakSlotIDs: Set<UUID>
    let activeSlotAutoSpeakEnabled: Bool
    let currentSpeakingSlotID: UUID?
    let playbackState: SpeechPlaybackState
    let activeSlotSupportsSpeech: Bool

    init(
        activeSlotID: UUID?,
        autoSpeakSlotIDs: Set<UUID>,
        activeSlotAutoSpeakEnabled: Bool,
        currentSpeakingSlotID: UUID?,
        playbackState: SpeechPlaybackState = .idle,
        activeSlotSupportsSpeech: Bool
    ) {
        self.activeSlotID = activeSlotID
        self.autoSpeakSlotIDs = autoSpeakSlotIDs
        self.activeSlotAutoSpeakEnabled = activeSlotAutoSpeakEnabled
        self.currentSpeakingSlotID = currentSpeakingSlotID
        self.playbackState = playbackState
        self.activeSlotSupportsSpeech = activeSlotSupportsSpeech
    }
}

/// Coordinates response extraction, privacy-safe cleaning, bounded speech
/// segmentation, and the one app-global speech service.
@MainActor
final class AssistantSpeechCoordinator {
    private struct ExtractionRequest {
        let requestID: UUID
        let slotID: UUID
        let generation: UInt64
        let stopEpoch: UInt64
        let playbackIntentEpoch: UInt64
        let webView: WKWebView
        let origin: SpeechRequestOrigin
        let automaticOrder: UInt64?
        let manualIntent: UInt64?
    }

    private enum AutomaticReservationState {
        case pending
        case staged(
            identity: SpeechResponseIdentity,
            requests: [SpeechUtteranceRequest],
            nextIndex: Int
        )
        case released
    }

    private struct AutomaticReservation {
        let order: UInt64
        let slotID: UUID
        let requestID: UUID
        var state: AutomaticReservationState
    }

    private struct SpeechPlaybackBatch {
        let responseID: SpeechResponseIdentity?
        let requests: [SpeechUtteranceRequest]
        let origin: SpeechPlaybackOrigin
        var nextIndex: Int
    }

    private let speechService: SpeechSynthesizing
    private let webViewProvider: @MainActor (UUID) -> WKWebView?
    private let responseBridgeProvider: @MainActor (UUID) -> ChatGPTResponseExtracting?
    private let followBridgeProvider: @MainActor (UUID) -> ChatGPTResponseFollowing?
    private let activeSlotIDProvider: @MainActor () -> UUID?
    private let followSpeechEnabled: @MainActor () -> Bool
    private var extractionRequests: [UUID: ExtractionRequest] = [:]
    private var nextGeneration: UInt64 = 0
    private var stopEpoch: UInt64 = 0
    private var playbackIntentEpoch: UInt64 = 0
    private var nextSequence: UInt64 = 0
    private var nextAutomaticOrder: UInt64 = 0
    private var nextManualIntent: UInt64 = 0
    private var spokenResponses: [UUID: Set<SpeechResponseIdentity>] = [:]
    private var suppressedResponses: [UUID: Set<SpeechResponseIdentity>] = [:]
    private var latestResponse: [UUID: SpeechResponseIdentity] = [:]
    private var currentItem: SpeechQueueItem?
    /// A segment can finish in the small window between a pause request and
    /// AVFoundation's didPause callback. Keep the stream owner and response
    /// identity alive while the remainder is held behind the pause barrier.
    private var pausedResponseID: SpeechResponseIdentity?
    private var pausedStreamOrigin: SpeechPlaybackOrigin?
    private var speechQueue = SpeechQueue()
    /// Transient response remainder. SpeechQueue stays bounded while this
    /// cursor preserves FIFO order for a long manual or automatic response.
    private var speechBacklog: [SpeechPlaybackBatch] = []
    private var automaticReservations: [AutomaticReservation] = []
    private var manualPlaybackBarrier: UInt64?
    private var lastFollowedLocator: SpeechSourceLocator?
    private var followSuspendedSlotIDs = Set<UUID>()
    private var followGeneration: UInt64 = 0

    private(set) var autoSpeakSlotIDs = Set<UUID>()
    private(set) var currentSpeakingSlotID: UUID?
    private(set) var playbackState: SpeechPlaybackState = .idle
    var onSpeechPresentationChange: (() -> Void)?

    init(
        speechService: SpeechSynthesizing,
        webViewProvider: @escaping @MainActor (UUID) -> WKWebView?,
        responseBridgeProvider: @escaping @MainActor (UUID) -> ChatGPTResponseExtracting?,
        followBridgeProvider: @escaping @MainActor (UUID) -> ChatGPTResponseFollowing? = { _ in nil },
        activeSlotIDProvider: @escaping @MainActor () -> UUID? = { nil },
        followSpeechEnabled: @escaping @MainActor () -> Bool = { true }
    ) {
        self.speechService = speechService
        self.webViewProvider = webViewProvider
        self.responseBridgeProvider = responseBridgeProvider
        self.followBridgeProvider = followBridgeProvider
        self.activeSlotIDProvider = activeSlotIDProvider
        self.followSpeechEnabled = followSpeechEnabled
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

    var pendingQueueCount: Int {
        speechQueue.items.count
    }

    var currentResponseIdentity: SpeechResponseIdentity? {
        currentItem?.responseID ?? pausedResponseID
    }

    var isFollowSuspendedForCurrentSpeech: Bool {
        guard let slotID = currentResponseIdentity?.slotID else { return false }
        return followSuspendedSlotIDs.contains(slotID)
    }

    @discardableResult
    func pauseCurrentSpeech(for slotID: UUID) -> Bool {
        guard currentSpeakingSlotID == slotID,
              currentItem != nil,
              playbackState == .speaking else {
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
    func resumeCurrentSpeech(for slotID: UUID) -> Bool {
        guard currentSpeakingSlotID == slotID,
              playbackState == .paused else {
            return false
        }

        // Resuming is a user review boundary. The current block remains where
        // the user left it; the next source block re-enables normal following.
        followSuspendedSlotIDs.remove(slotID)
        guard currentItem != nil else {
            // If the utterance finished just before didPause, AVFoundation no
            // longer has an utterance to continue. Resume the held FIFO stream
            // by starting its next item; the next didStart callback confirms
            // audible playback.
            setPlaybackState(.resuming)
            drainPlayback()
            speakNext()
            if currentItem == nil {
                setPlaybackState(.idle)
                setCurrentSpeakingSlot(nil)
                return false
            }
            return true
        }

        setPlaybackState(.resuming)
        let accepted = speechService.resume()
        if !accepted {
            setPlaybackState(.paused)
        }
        return accepted
    }

    /// Receives a trusted page-scroll intent from the response content world.
    /// Speech continues, but automatic following is suspended for this active
    /// playback session until Resume or a new explicit Read Latest intent.
    func handleManualScroll(for slotID: UUID, documentToken: String) {
        guard let item = currentItem,
              let responseID = item.responseID,
              responseID.slotID == slotID,
              responseID.documentToken == documentToken,
              item.sourceLocator?.documentToken == documentToken else {
            return
        }
        followSuspendedSlotIDs.insert(slotID)
    }

    /// Called after a user-selected Tab has become the physical presentation.
    /// A background speech stream can be located once when the user returns to
    /// its Tab, but it can never select, focus, or activate that Tab itself.
    func handleActiveTabChange(to slotID: UUID) {
        guard playbackState == .speaking,
              currentSpeakingSlotID == slotID else {
            return
        }
        followCurrentItem(force: true)
    }

    var isManualPlaybackBarrierActive: Bool {
        manualPlaybackBarrier != nil
    }

    func handle(
        _ observation: ChatGPTAttentionObservation,
        for slotID: UUID
    ) {
        switch observation {
        case .generationStarted:
            break
        case .generationFinished:
            guard autoSpeakSlotIDs.contains(slotID) else { return }
            // A newer completion from the same Tab supersedes only an older
            // pending or staged extraction. Already speaking or queued items
            // remain valid and are never interrupted here.
            invalidatePendingAutomaticExtraction(for: slotID)
            let order = nextAutomaticOrder
            nextAutomaticOrder &+= 1
            let requestID = UUID()
            automaticReservations.append(
                AutomaticReservation(
                    order: order,
                    slotID: slotID,
                    requestID: requestID,
                    state: .pending
                )
            )
            guard requestLatestResponse(
                for: slotID,
                origin: .automatic,
                requestID: requestID,
                automaticOrder: order,
                manualIntent: nil
            ) else {
                releaseAutomaticReservation(requestID: requestID)
                return
            }
        case .runtimeReset:
            resetRuntime(slotID: slotID)
        }
    }

    func toggleAutoSpeak(for slotID: UUID) {
        if autoSpeakSlotIDs.contains(slotID) {
            autoSpeakSlotIDs.remove(slotID)
            let preservedResponseID: SpeechResponseIdentity? = {
                guard currentResponseIdentity?.slotID == slotID,
                      currentItem?.origin == .automatic || pausedStreamOrigin == .automatic else {
                    return nil
                }
                return currentResponseIdentity
            }()
            invalidateAutomaticPlayback(
                for: slotID,
                preservingResponseID: preservedResponseID
            )
            speechQueue.removeAutomaticItems(
                forSlotID: slotID,
                preservingResponseID: preservedResponseID
            )
            drainPlayback()
        } else {
            autoSpeakSlotIDs.insert(slotID)
        }
        onSpeechPresentationChange?()
    }

    /// Manual reading is an explicit user action and therefore works even
    /// without an armed automatic source. It establishes a barrier before
    /// extraction so an automatic result that resolves first can only stage.
    func readLatestResponse(for slotID: UUID) {
        playbackIntentEpoch &+= 1
        resetFollowState(for: slotID)
        invalidateAllAutomaticPlayback()
        suppressCurrentAndPendingSpeech()
        speechBacklog.removeAll()
        speechQueue.clear()
        currentItem = nil
        pausedResponseID = nil
        pausedStreamOrigin = nil
        speechService.stop()
        setPlaybackState(.idle)
        setCurrentSpeakingSlot(nil)

        nextManualIntent &+= 1
        let manualIntent = nextManualIntent
        manualPlaybackBarrier = manualIntent
        let requestID = UUID()
        guard requestLatestResponse(
            for: slotID,
            origin: .manual,
            requestID: requestID,
            automaticOrder: nil,
            manualIntent: manualIntent
        ) else {
            releaseManualBarrier(intent: manualIntent)
            return
        }
    }

    /// Replays the latest response from segment one. The response body is not
    /// retained; this deliberately reuses the trusted latest-response bridge
    /// and the same supersession/token invalidation path as manual reading.
    func replayLatestResponse(for slotID: UUID) {
        readLatestResponse(for: slotID)
    }

    /// Preview is a user-priority playback intent. It shares this coordinator
    /// and therefore the same SpeechService and AVSpeechSynthesizer stream.
    /// Preview items carry no response identity and never mutate Tab state.
    func playPreview(_ requests: [SpeechUtteranceRequest]) {
        guard !requests.isEmpty else { return }
        playbackIntentEpoch &+= 1
        stopEpoch &+= 1
        resetFollowState()
        invalidateAllAutomaticPlayback()
        extractionRequests.removeAll()
        manualPlaybackBarrier = nil
        suppressCurrentAndPendingSpeech()
        speechBacklog.removeAll()
        speechQueue.clear()
        currentItem = nil
        pausedResponseID = nil
        pausedStreamOrigin = nil
        speechService.stop()
        setPlaybackState(.idle)
        setCurrentSpeakingSlot(nil)
        speechBacklog = [SpeechPlaybackBatch(
            responseID: nil,
            requests: requests,
            origin: .preview,
            nextIndex: 0
        )]
        drainPlayback()
    }

    /// Stop is local to speech. It never sends a cancellation to ChatGPT.
    func stop() {
        stopEpoch &+= 1
        playbackIntentEpoch &+= 1
        resetFollowState()
        invalidateAllAutomaticPlayback()
        extractionRequests.removeAll()
        manualPlaybackBarrier = nil
        suppressCurrentAndPendingSpeech()
        speechBacklog.removeAll()
        speechQueue.clear()
        currentItem = nil
        pausedResponseID = nil
        pausedStreamOrigin = nil
        speechService.stop()
        setPlaybackState(.idle)
        setCurrentSpeakingSlot(nil)
    }

    private func suppressCurrentAndPendingSpeech() {
        if let responseID = currentItem?.responseID {
            suppressedResponses[responseID.slotID, default: []].insert(responseID)
        }
        if let responseID = pausedResponseID {
            suppressedResponses[responseID.slotID, default: []].insert(responseID)
        }
        for item in speechQueue.items {
            guard let responseID = item.responseID else { continue }
            suppressedResponses[responseID.slotID, default: []].insert(responseID)
        }
    }

    /// Resets only transient WebView/document state. An armed Slot remains
    /// armed so a later runtime recreation can continue listening.
    func resetRuntime(slotID: UUID) {
        resetRuntimeState(slotID: slotID)
        onSpeechPresentationChange?()
    }

    /// Permanent Slot deletion is different from navigation/runtime reset:
    /// only this path clears the session-scoped Auto Speak source.
    func removeSlot(slotID: UUID) {
        resetRuntimeState(slotID: slotID)
        autoSpeakSlotIDs.remove(slotID)
        onSpeechPresentationChange?()
    }

    private func resetRuntimeState(slotID: UUID) {
        nextGeneration &+= 1
        resetFollowState(for: slotID)
        let affectedRequests = extractionRequests.filter { $0.value.slotID == slotID }
        for (requestID, request) in affectedRequests {
            extractionRequests.removeValue(forKey: requestID)
            releaseExtraction(request)
        }
        releaseAutomaticReservations(for: slotID)
        speechBacklog.removeAll { $0.responseID?.slotID == slotID }
        let currentWasRemoved = currentItem?.responseID?.slotID == slotID
            || currentSpeakingSlotID == slotID
        speechQueue.removeItems(forSlotID: slotID)
        if currentWasRemoved {
            currentItem = nil
            pausedResponseID = nil
            pausedStreamOrigin = nil
            speechService.stop()
            setPlaybackState(.idle)
            setCurrentSpeakingSlot(nil)
            speakNext()
        }
        spokenResponses.removeValue(forKey: slotID)
        suppressedResponses.removeValue(forKey: slotID)
        latestResponse.removeValue(forKey: slotID)
        drainPlayback()
    }

    private func requestLatestResponse(
        for slotID: UUID,
        origin: SpeechRequestOrigin,
        requestID: UUID,
        automaticOrder: UInt64?,
        manualIntent: UInt64?
    ) -> Bool {
        guard let webView = webViewProvider(slotID),
              let bridge = responseBridgeProvider(slotID) else {
            return false
        }

        nextGeneration &+= 1
        let request = ExtractionRequest(
            requestID: requestID,
            slotID: slotID,
            generation: nextGeneration,
            stopEpoch: stopEpoch,
            playbackIntentEpoch: playbackIntentEpoch,
            webView: webView,
            origin: origin,
            automaticOrder: automaticOrder,
            manualIntent: manualIntent
        )
        extractionRequests[requestID] = request

        let expectedWebView = webView
        bridge.extractLatest { [weak self, weak expectedWebView] payload in
            guard let self else { return }
            self.completeExtraction(
                requestID: requestID,
                expectedWebView: expectedWebView,
                payload: payload
            )
        }
        return true
    }

    private func completeExtraction(
        requestID: UUID,
        expectedWebView: WKWebView?,
        payload: ChatGPTResponsePayload?
    ) {
        guard let request = extractionRequests.removeValue(forKey: requestID) else {
            return
        }

        guard let expectedWebView,
              request.webView === expectedWebView,
              webViewProvider(request.slotID) === expectedWebView else {
            releaseExtraction(request)
            return
        }
        guard request.playbackIntentEpoch == playbackIntentEpoch else {
            releaseExtraction(request)
            return
        }
        guard let payload,
              let responseID = payload.responseID else {
            releaseExtraction(request)
            return
        }

        let identity = SpeechResponseIdentity(
            slotID: request.slotID,
            documentToken: payload.documentToken,
            responseID: responseID
        )
        latestResponse[request.slotID] = identity
        guard request.stopEpoch == stopEpoch else {
            suppressedResponses[request.slotID, default: []].insert(identity)
            releaseExtraction(request)
            return
        }

        let requests = SpeechLanguageRouter.utteranceRequests(
            for: payload.blocks
        )

        switch request.origin {
        case .automatic:
            stageAutomatic(
                identity: identity,
                requests: requests,
                request: request
            )
        case .manual:
            finishManualExtraction(
                identity: identity,
                requests: requests,
                request: request
            )
        }
    }

    private func releaseExtraction(_ request: ExtractionRequest) {
        switch request.origin {
        case .automatic:
            releaseAutomaticReservation(requestID: request.requestID)
        case .manual:
            if let manualIntent = request.manualIntent {
                releaseManualBarrier(intent: manualIntent)
            }
        }
    }

    private func stageAutomatic(
        identity: SpeechResponseIdentity,
        requests: [SpeechUtteranceRequest],
        request: ExtractionRequest
    ) {
        guard let automaticOrder = request.automaticOrder,
              let index = automaticReservations.firstIndex(where: {
                  $0.order == automaticOrder
              }) else {
            return
        }
        guard autoSpeakSlotIDs.contains(request.slotID),
              !requests.isEmpty,
              !suppressedResponses[identity.slotID, default: []].contains(identity),
              !spokenResponses[identity.slotID, default: []].contains(identity) else {
            automaticReservations[index].state = .released
            drainPlayback()
            return
        }

        automaticReservations[index].state = .staged(
            identity: identity,
            requests: requests,
            nextIndex: 0
        )
        drainPlayback()
    }

    private func finishManualExtraction(
        identity: SpeechResponseIdentity,
        requests: [SpeechUtteranceRequest],
        request: ExtractionRequest
    ) {
        guard let manualIntent = request.manualIntent,
              manualPlaybackBarrier == manualIntent else {
            return
        }

        // This is intentionally defensive: the barrier normally prevents an
        // automatic item from becoming current, but a valid manual result is
        // still required to preempt one if a future state-machine change ever
        // lets that narrow race through.
        let hasSpeechToPreempt = currentItem != nil
            || pausedResponseID != nil
            || !speechQueue.isEmpty
            || !speechBacklog.isEmpty
        suppressCurrentAndPendingSpeech()
        speechBacklog.removeAll()
        speechQueue.clear()
        currentItem = nil
        pausedResponseID = nil
        pausedStreamOrigin = nil
        setPlaybackState(.idle)
        if hasSpeechToPreempt {
            speechService.stop()
        }
        setCurrentSpeakingSlot(nil)

        guard !requests.isEmpty else {
            releaseManualBarrier(intent: manualIntent)
            return
        }

        latestResponse[request.slotID] = identity
        speechBacklog = [SpeechPlaybackBatch(
            responseID: identity,
            requests: requests,
            origin: .manual,
            nextIndex: 0
        )]
        releaseManualBarrier(intent: manualIntent)
    }

    private func releaseManualBarrier(intent: UInt64) {
        guard manualPlaybackBarrier == intent else { return }
        manualPlaybackBarrier = nil
        drainPlayback()
    }

    private func invalidateAllAutomaticPlayback() {
        let automaticRequestIDs = extractionRequests.compactMap { requestID, request in
            request.origin == .automatic ? requestID : nil
        }
        for requestID in automaticRequestIDs {
            extractionRequests.removeValue(forKey: requestID)
        }
        automaticReservations.removeAll()
    }

    private func invalidateAutomaticPlayback(
        for slotID: UUID,
        preservingResponseID: SpeechResponseIdentity? = nil
    ) {
        let automaticRequestIDs = extractionRequests.compactMap { requestID, request in
            request.origin == .automatic && request.slotID == slotID ? requestID : nil
        }
        for requestID in automaticRequestIDs {
            extractionRequests.removeValue(forKey: requestID)
        }
        automaticReservations.removeAll { reservation in
            guard reservation.slotID == slotID else { return false }
            guard let preservingResponseID else { return true }
            if case let .staged(identity, _, _) = reservation.state {
                return identity != preservingResponseID
            }
            return true
        }
    }

    private func invalidatePendingAutomaticExtraction(for slotID: UUID) {
        let automaticRequestIDs = extractionRequests.compactMap { requestID, request in
            request.origin == .automatic && request.slotID == slotID ? requestID : nil
        }
        for requestID in automaticRequestIDs {
            extractionRequests.removeValue(forKey: requestID)
        }
        automaticReservations.removeAll { reservation in
            guard reservation.slotID == slotID else { return false }
            if case .pending = reservation.state { return true }
            return false
        }
    }

    private func releaseAutomaticReservations(for slotID: UUID) {
        automaticReservations.removeAll { $0.slotID == slotID }
    }

    private func releaseAutomaticReservation(requestID: UUID) {
        automaticReservations.removeAll { $0.requestID == requestID }
        drainPlayback()
    }

    private func drainPlayback() {
        guard manualPlaybackBarrier == nil else { return }
        if !speechBacklog.isEmpty {
            drainSpeechBacklog()
            return
        }
        drainAutomaticReservations()
    }

    private func drainSpeechBacklog() {
        guard manualPlaybackBarrier == nil else { return }
        while let first = speechBacklog.first {
            let result = makeQueueItems(
                responseID: first.responseID,
                requests: first.requests,
                origin: first.origin,
                startIndex: first.nextIndex,
                limit: speechQueue.availableCapacity
            )
            guard result.nextIndex > first.nextIndex || !result.items.isEmpty else { return }
            if !result.items.isEmpty {
                let appended = speechQueue.append(items: result.items)
                guard appended > 0 else { return }
            }
            if result.nextIndex >= first.requests.count {
                speechBacklog.removeFirst()
            } else {
                speechBacklog[0].nextIndex = result.nextIndex
                if !result.items.isEmpty { speakNext() }
                return
            }
            speakNext()
            if speechQueue.availableCapacity == 0 { return }
        }
        drainAutomaticReservations()
    }

    private func drainAutomaticReservations() {
        guard manualPlaybackBarrier == nil else { return }

        while let first = automaticReservations.first {
            switch first.state {
            case .pending:
                return
            case .released:
                automaticReservations.removeFirst()
            case let .staged(identity, requests, nextIndex):
                guard !suppressedResponses[identity.slotID, default: []].contains(identity) else {
                    automaticReservations.removeFirst()
                    continue
                }
                let result = makeQueueItems(
                    responseID: identity,
                    requests: requests,
                    origin: .automatic,
                    startIndex: nextIndex,
                    limit: speechQueue.availableCapacity
                )
                guard result.nextIndex > nextIndex || !result.items.isEmpty else { return }
                if !result.items.isEmpty {
                    let appended = speechQueue.append(items: result.items)
                    guard appended > 0 else { return }
                    spokenResponses[identity.slotID, default: []].insert(identity)
                }
                if result.nextIndex >= requests.count {
                    automaticReservations.removeFirst()
                } else {
                    automaticReservations[0].state = .staged(
                        identity: identity,
                        requests: requests,
                        nextIndex: result.nextIndex
                    )
                    if !result.items.isEmpty { speakNext() }
                    return
                }
                speakNext()
                if speechQueue.availableCapacity == 0 { return }
            }
        }
    }

    private func makeQueueItems(
        responseID: SpeechResponseIdentity?,
        requests: [SpeechUtteranceRequest],
        origin: SpeechPlaybackOrigin,
        startIndex: Int,
        limit: Int
    ) -> (items: [SpeechQueueItem], nextIndex: Int) {
        guard limit > 0 else { return ([], max(0, min(startIndex, requests.count))) }
        var items: [SpeechQueueItem] = []
        var index = max(0, min(startIndex, requests.count))
        while index < requests.count && items.count < limit {
            let request = requests[index]
            index += 1
            guard !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  SpeechSpeakabilityFilter.containsSpeakableContent(request.text) else {
                continue
            }
            let sequence = nextSequence
            nextSequence &+= 1
            let sourceLocator: SpeechSourceLocator? = {
                guard let responseID,
                      let locator = request.sourceLocator,
                      locator.documentToken == responseID.documentToken,
                      locator.responseID == responseID.responseID else {
                    return nil
                }
                return locator.assigning(slotID: responseID.slotID)
            }()
            items.append(
                SpeechQueueItem(
                    responseID: responseID,
                    sequence: sequence,
                    text: request.text,
                    languageRole: request.languageRole,
                    origin: origin,
                    sourceLocator: sourceLocator
                )
            )
        }
        return (items, index)
    }

    private func speakNext() {
        guard playbackState != .paused,
              playbackState != .pausing,
              currentItem == nil,
              let item = speechQueue.dequeue() else {
            return
        }
        currentItem = item
        pausedResponseID = nil
        pausedStreamOrigin = nil
        setCurrentSpeakingSlot(item.responseID?.slotID)
        setPlaybackState(.starting)
        speechService.speak(
            SpeechPlaybackRequest(
                text: item.text,
                transportToken: item.sequence,
                languageRole: item.languageRole
            )
        )
    }

    private func followCurrentItem(force: Bool = false) {
        guard followSpeechEnabled(),
              playbackState == .speaking,
              let item = currentItem,
              item.origin != .preview,
              let responseID = item.responseID,
              let locator = item.sourceLocator,
              locator.slotID == responseID.slotID,
              currentSpeakingSlotID == responseID.slotID,
              activeSlotIDProvider() == responseID.slotID,
              !followSuspendedSlotIDs.contains(responseID.slotID),
              let bridge = followBridgeProvider(responseID.slotID) else {
            return
        }
        if !force, lastFollowedLocator == locator {
            return
        }

        // All identity checks happen immediately before dispatch. The one-shot
        // bridge then validates the same document/response against its live
        // content-world registry, so a late callback cannot retarget another
        // Slot or document.
        followGeneration &+= 1
        let expectedGeneration = followGeneration
        let expectedSequence = item.sequence
        lastFollowedLocator = locator
        bridge.scrollToSpeechBlock(locator) { [weak self] _ in
            guard let self,
                  self.followGeneration == expectedGeneration,
                  self.currentItem?.sequence == expectedSequence else {
                return
            }
        }
    }

    private func resetFollowState(for slotID: UUID? = nil) {
        followGeneration &+= 1
        lastFollowedLocator = nil
        if let slotID {
            followSuspendedSlotIDs.remove(slotID)
        } else {
            followSuspendedSlotIDs.removeAll()
        }
    }

    private func setCurrentSpeakingSlot(_ slotID: UUID?) {
        guard currentSpeakingSlotID != slotID else { return }
        currentSpeakingSlotID = slotID
        onSpeechPresentationChange?()
    }

    private func setPlaybackState(_ state: SpeechPlaybackState) {
        guard playbackState != state else { return }
        playbackState = state
        onSpeechPresentationChange?()
    }

    private func handleUtteranceStarted(token: UInt64) {
        guard let currentItem,
              currentItem.sequence == token,
              playbackState == .starting else {
            return
        }
        setPlaybackState(.speaking)
        followCurrentItem()
    }

    private func handleUtteranceFinished(token: UInt64) {
        guard let currentItem,
              currentItem.sequence == token else {
            return
        }
        let finishedItem = currentItem
        let finishedSlotID = finishedItem.responseID?.slotID
        let pauseReachedBoundary = playbackState == .pausing || playbackState == .paused
        self.currentItem = nil

        if pauseReachedBoundary,
           !speechQueue.isEmpty || !speechBacklog.isEmpty {
            pausedResponseID = finishedItem.responseID
            pausedStreamOrigin = finishedItem.origin
            setPlaybackState(.paused)
            return
        }

        pausedResponseID = nil
        pausedStreamOrigin = nil
        setPlaybackState(.idle)
        if speechQueue.isEmpty {
            setCurrentSpeakingSlot(nil)
        }
        drainPlayback()
        speakNext()
        if let finishedSlotID,
           currentSpeakingSlotID != finishedSlotID {
            // Manual scroll suspension belongs to the continuous speech
            // session, not to a permanently remembered Slot. Keep it while
            // the same Slot has another queued item, but release it when the
            // stream ends or moves to another Slot.
            followSuspendedSlotIDs.remove(finishedSlotID)
        }
    }

    private func handleUtterancePaused(token: UInt64) {
        guard let currentItem,
              currentItem.sequence == token,
              playbackState == .pausing else {
            return
        }
        setPlaybackState(.paused)
    }

    private func handleUtteranceContinued(token: UInt64) {
        guard let currentItem,
              currentItem.sequence == token,
              playbackState == .resuming else {
            return
        }
        setPlaybackState(.speaking)
    }

    private func handleUtteranceCancelled(token: UInt64) {
        guard let currentItem,
              currentItem.sequence == token else {
            return
        }

        // Cancellation is a terminal transport event, not a finish event.
        // Drop the remainder so no late cancel can advance the FIFO or leave
        // a ghost speaking state behind. A future response may arm a fresh
        // playback session normally.
        self.currentItem = nil
        pausedResponseID = nil
        pausedStreamOrigin = nil
        speechQueue.clear()
        speechBacklog.removeAll()
        invalidateAllAutomaticPlayback()
        setPlaybackState(.idle)
        setCurrentSpeakingSlot(nil)
    }
}
