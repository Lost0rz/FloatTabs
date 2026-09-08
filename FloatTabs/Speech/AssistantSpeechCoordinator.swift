import Foundation
import WebKit

enum SpeechRequestOrigin: Equatable, Sendable {
    case automatic
    case manual
}

struct SpeechRailPresentation: Equatable, Sendable {
    let activeSlotID: UUID?
    let autoSpeakSlotIDs: Set<UUID>
    let activeSlotAutoSpeakEnabled: Bool
    let currentSpeakingSlotID: UUID?
    let activeSlotSupportsSpeech: Bool
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

    private(set) var autoSpeakSlotIDs = Set<UUID>()
    private(set) var currentSpeakingSlotID: UUID?
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
            guard let self,
                  let currentItem = self.currentItem,
                  currentItem.sequence == token else {
                return
            }
            self.currentItem = nil
            if self.speechQueue.isEmpty {
                self.setCurrentSpeakingSlot(nil)
            }
            self.drainAutomaticReservations()
            self.speakNext()
        }
    }

    var pendingQueueCount: Int {
        speechQueue.items.count
    }

    var currentResponseIdentity: SpeechResponseIdentity? {
        currentItem?.responseID
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
        speechService.stop()
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
        speechService.stop()
        setCurrentSpeakingSlot(nil)
        speechQueue.replacePreview(requests: requests)
        if let highestToken = requests.map(\.token).max() {
            nextSequence = max(nextSequence, highestToken &+ 1)
        }
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
        speechService.stop()
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
            speechService.stop()
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

        let cleaned = SpeechContentCleaner.clean(payload.blocks)
        let requests = SpeechLanguageRouter.utteranceRequests(
            for: cleaned,
            startingToken: nextSequence
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
        speechQueue.replace(responseID: identity, requests: requests)
        nextSequence &+= UInt64(requests.count)
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
                let sequencedRequests = requests.enumerated().map { offset, request in
                    SpeechUtteranceRequest(
                        text: request.text,
                        token: nextSequence &+ UInt64(offset),
                        languageRole: request.languageRole
                    )
                }
                let appended = speechQueue.append(
                    responseID: identity,
                    requests: sequencedRequests
                )
                guard appended > 0 else { return }
                automaticReservations.removeFirst()
                spokenResponses[identity.slotID, default: []].insert(identity)
                nextSequence &+= UInt64(appended)
                speakNext()
            }
        }
    }

    private func speakNext() {
        guard currentItem == nil,
              let item = speechQueue.dequeue() else {
            return
        }
        currentItem = item
        setCurrentSpeakingSlot(item.responseID?.slotID)
        speechService.speak(
            SpeechUtteranceRequest(
                text: item.text,
                token: item.sequence,
                languageRole: item.languageRole
            )
        )
    }

    private func setCurrentSpeakingSlot(_ slotID: UUID?) {
        guard currentSpeakingSlotID != slotID else { return }
        currentSpeakingSlotID = slotID
        onSpeechPresentationChange?()
    }
}
