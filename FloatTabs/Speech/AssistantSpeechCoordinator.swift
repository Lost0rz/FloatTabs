import Foundation
import WebKit

enum SpeechRequestOrigin: Equatable, Sendable {
    case automatic
    case manual
}

enum SpeechPlaybackState: Equatable, Sendable {
    case idle
    case speaking
    case paused
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
            requests: [SpeechUtteranceRequest]
        )
        case released
    }

    private struct AutomaticReservation {
        let order: UInt64
        let slotID: UUID
        let requestID: UUID
        var state: AutomaticReservationState
    }

    private let speechService: SpeechSynthesizing
    private let webViewProvider: @MainActor (UUID) -> WKWebView?
    private let responseBridgeProvider: @MainActor (UUID) -> ChatGPTResponseExtracting?
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
    private var speechQueue = SpeechQueue()
    private var automaticReservations: [AutomaticReservation] = []
    private var manualPlaybackBarrier: UInt64?
    private var pauseRequested = false
    private var resumeRequested = false

    private(set) var autoSpeakSlotIDs = Set<UUID>()
    private(set) var currentSpeakingSlotID: UUID?
    private(set) var playbackState: SpeechPlaybackState = .idle
    var onSpeechPresentationChange: (() -> Void)?

    init(
        speechService: SpeechSynthesizing,
        webViewProvider: @escaping @MainActor (UUID) -> WKWebView?,
        responseBridgeProvider: @escaping @MainActor (UUID) -> ChatGPTResponseExtracting?
    ) {
        self.speechService = speechService
        self.webViewProvider = webViewProvider
        self.responseBridgeProvider = responseBridgeProvider
        speechService.onUtteranceFinished = { [weak self] token in
            self?.handleUtteranceFinished(token: token)
        }
        speechService.onUtterancePaused = { [weak self] token in
            self?.handleUtterancePaused(token: token)
        }
        speechService.onUtteranceContinued = { [weak self] token in
            self?.handleUtteranceContinued(token: token)
        }
    }

    var pendingQueueCount: Int {
        speechQueue.items.count
    }

    var currentResponseIdentity: SpeechResponseIdentity? {
        currentItem?.responseID
    }

    @discardableResult
    func pauseCurrentSpeech(for slotID: UUID) -> Bool {
        guard currentSpeakingSlotID == slotID,
              currentItem != nil,
              playbackState == .speaking,
              !pauseRequested else {
            return false
        }

        resumeRequested = false
        pauseRequested = true
        let accepted = speechService.pause()
        if !accepted {
            pauseRequested = false
        }
        return accepted
    }

    @discardableResult
    func resumeCurrentSpeech(for slotID: UUID) -> Bool {
        guard currentSpeakingSlotID == slotID,
              currentItem != nil,
              playbackState == .paused,
              !resumeRequested else {
            return false
        }

        pauseRequested = false
        resumeRequested = true
        let accepted = speechService.resume()
        if !accepted {
            resumeRequested = false
            return false
        }

        // continueSpeaking() is the successful user intent. The delegate
        // callback remains token-guarded confirmation and cannot resurrect a
        // stopped or superseded item.
        setPlaybackState(.speaking)
        return true
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
            invalidateAutomaticPlayback(for: slotID)
            let preservedResponseID: SpeechResponseIdentity? = {
                guard currentItem?.origin == .automatic,
                      currentItem?.responseID?.slotID == slotID else {
                    return nil
                }
                return currentItem?.responseID
            }()
            speechQueue.removeAutomaticItems(
                forSlotID: slotID,
                preservingResponseID: preservedResponseID
            )
            drainAutomaticReservations()
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
        invalidateAllAutomaticPlayback()
        suppressCurrentAndPendingSpeech()
        speechQueue.clear()
        currentItem = nil
        pauseRequested = false
        resumeRequested = false
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

    /// Preview is a user-priority playback intent. It shares this coordinator
    /// and therefore the same SpeechService and AVSpeechSynthesizer stream.
    /// Preview items carry no response identity and never mutate Tab state.
    func playPreview(_ requests: [SpeechUtteranceRequest]) {
        guard !requests.isEmpty else { return }
        playbackIntentEpoch &+= 1
        stopEpoch &+= 1
        invalidateAllAutomaticPlayback()
        extractionRequests.removeAll()
        manualPlaybackBarrier = nil
        suppressCurrentAndPendingSpeech()
        speechQueue.clear()
        currentItem = nil
        pauseRequested = false
        resumeRequested = false
        speechService.stop()
        setPlaybackState(.idle)
        setCurrentSpeakingSlot(nil)
        let previewItems = makeQueueItems(
            responseID: nil,
            requests: requests,
            origin: .preview,
            limit: speechQueue.maximumPendingSegments
        )
        speechQueue.replacePreview(items: previewItems)
        speakNext()
    }

    /// Stop is local to speech. It never sends a cancellation to ChatGPT.
    func stop() {
        stopEpoch &+= 1
        playbackIntentEpoch &+= 1
        invalidateAllAutomaticPlayback()
        extractionRequests.removeAll()
        manualPlaybackBarrier = nil
        suppressCurrentAndPendingSpeech()
        speechQueue.clear()
        currentItem = nil
        pauseRequested = false
        resumeRequested = false
        speechService.stop()
        setPlaybackState(.idle)
        setCurrentSpeakingSlot(nil)
    }

    private func suppressCurrentAndPendingSpeech() {
        if let responseID = currentItem?.responseID {
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
        let affectedRequests = extractionRequests.filter { $0.value.slotID == slotID }
        for (requestID, request) in affectedRequests {
            extractionRequests.removeValue(forKey: requestID)
            releaseExtraction(request)
        }
        releaseAutomaticReservations(for: slotID)
        let currentWasRemoved = currentItem?.responseID?.slotID == slotID
        speechQueue.removeItems(forSlotID: slotID)
        if currentWasRemoved {
            currentItem = nil
            pauseRequested = false
            resumeRequested = false
            speechService.stop()
            setPlaybackState(.idle)
            setCurrentSpeakingSlot(nil)
            speakNext()
        }
        spokenResponses.removeValue(forKey: slotID)
        suppressedResponses.removeValue(forKey: slotID)
        latestResponse.removeValue(forKey: slotID)
        drainAutomaticReservations()
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
            drainAutomaticReservations()
            return
        }

        automaticReservations[index].state = .staged(
            identity: identity,
            requests: requests
        )
        drainAutomaticReservations()
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
        let hasSpeechToPreempt = currentItem != nil || !speechQueue.isEmpty
        suppressCurrentAndPendingSpeech()
        speechQueue.clear()
        currentItem = nil
        if hasSpeechToPreempt {
            speechService.stop()
        }
        setCurrentSpeakingSlot(nil)

        guard !requests.isEmpty else {
            releaseManualBarrier(intent: manualIntent)
            return
        }

        latestResponse[request.slotID] = identity
        let manualItems = makeQueueItems(
            responseID: identity,
            requests: requests,
            origin: .manual,
            limit: speechQueue.maximumPendingSegments
        )
        speechQueue.replace(items: manualItems)
        speakNext()
        releaseManualBarrier(intent: manualIntent)
    }

    private func releaseManualBarrier(intent: UInt64) {
        guard manualPlaybackBarrier == intent else { return }
        manualPlaybackBarrier = nil
        drainAutomaticReservations()
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

    private func invalidateAutomaticPlayback(for slotID: UUID) {
        let automaticRequestIDs = extractionRequests.compactMap { requestID, request in
            request.origin == .automatic && request.slotID == slotID ? requestID : nil
        }
        for requestID in automaticRequestIDs {
            extractionRequests.removeValue(forKey: requestID)
        }
        automaticReservations.removeAll { reservation in
            reservation.slotID == slotID
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
            reservation.slotID == slotID
        }
    }

    private func releaseAutomaticReservations(for slotID: UUID) {
        automaticReservations.removeAll { $0.slotID == slotID }
    }

    private func releaseAutomaticReservation(requestID: UUID) {
        automaticReservations.removeAll { $0.requestID == requestID }
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
            case let .staged(identity, requests):
                guard !suppressedResponses[identity.slotID, default: []].contains(identity) else {
                    automaticReservations.removeFirst()
                    continue
                }
                let automaticItems = makeQueueItems(
                    responseID: identity,
                    requests: requests,
                    origin: .automatic,
                    limit: speechQueue.availableCapacity
                )
                guard !automaticItems.isEmpty else { return }
                let appended = speechQueue.append(items: automaticItems)
                guard appended > 0 else { return }
                automaticReservations.removeFirst()
                spokenResponses[identity.slotID, default: []].insert(identity)
                speakNext()
            }
        }
    }

    private func makeQueueItems(
        responseID: SpeechResponseIdentity?,
        requests: [SpeechUtteranceRequest],
        origin: SpeechPlaybackOrigin,
        limit: Int
    ) -> [SpeechQueueItem] {
        guard limit > 0 else { return [] }
        var items: [SpeechQueueItem] = []
        for request in requests where items.count < limit {
            guard !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  SpeechSpeakabilityFilter.containsSpeakableContent(request.text) else {
                continue
            }
            let sequence = nextSequence
            nextSequence &+= 1
            items.append(
                SpeechQueueItem(
                    responseID: responseID,
                    sequence: sequence,
                    text: request.text,
                    languageRole: request.languageRole,
                    origin: origin
                )
            )
        }
        return items
    }

    private func speakNext() {
        guard playbackState != .paused,
              !pauseRequested,
              currentItem == nil,
              let item = speechQueue.dequeue() else {
            return
        }
        currentItem = item
        setCurrentSpeakingSlot(item.responseID?.slotID)
        setPlaybackState(.speaking)
        speechService.speak(
            SpeechPlaybackRequest(
                text: item.text,
                transportToken: item.sequence,
                languageRole: item.languageRole
            )
        )
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

    private func handleUtteranceFinished(token: UInt64) {
        guard let currentItem,
              currentItem.sequence == token else {
            return
        }
        self.currentItem = nil
        pauseRequested = false
        resumeRequested = false
        setPlaybackState(.idle)
        if speechQueue.isEmpty {
            setCurrentSpeakingSlot(nil)
        }
        drainAutomaticReservations()
        speakNext()
    }

    private func handleUtterancePaused(token: UInt64) {
        guard let currentItem,
              currentItem.sequence == token,
              playbackState == .speaking,
              pauseRequested else {
            return
        }
        pauseRequested = false
        resumeRequested = false
        setPlaybackState(.paused)
    }

    private func handleUtteranceContinued(token: UInt64) {
        guard let currentItem,
              currentItem.sequence == token,
              playbackState == .paused || resumeRequested else {
            return
        }
        pauseRequested = false
        resumeRequested = false
        setPlaybackState(.speaking)
    }
}
