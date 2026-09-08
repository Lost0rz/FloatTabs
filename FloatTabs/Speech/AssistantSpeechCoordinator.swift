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
        let generation: UInt64
        let stopEpoch: UInt64
        let playbackIntentEpoch: UInt64
        let webView: WKWebView
        let origin: SpeechRequestOrigin
    }

    private let speechService: SpeechSynthesizing
    private let webViewProvider: @MainActor (UUID) -> WKWebView?
    private let responseBridgeProvider: @MainActor (UUID) -> ChatGPTResponseExtracting?
    private var extractionRequests: [UUID: ExtractionRequest] = [:]
    private var nextGeneration: UInt64 = 0
    private var stopEpoch: UInt64 = 0
    private var playbackIntentEpoch: UInt64 = 0
    private var nextSequence: UInt64 = 0
    private var spokenResponses: [UUID: Set<SpeechResponseIdentity>] = [:]
    private var suppressedResponses: [UUID: Set<SpeechResponseIdentity>] = [:]
    private var latestResponse: [UUID: SpeechResponseIdentity] = [:]
    private var currentItem: SpeechQueueItem?
    private var speechQueue = SpeechQueue()

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
            self.speakNext()
        }
    }

    var pendingQueueCount: Int {
        speechQueue.items.count
    }

    var currentResponseIdentity: SpeechResponseIdentity? {
        currentItem?.responseID
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
            requestLatestResponse(for: slotID, origin: .automatic)
        case .runtimeReset:
            resetRuntime(slotID: slotID)
        }
    }

    func toggleAutoSpeak(for slotID: UUID) {
        if autoSpeakSlotIDs.contains(slotID) {
            autoSpeakSlotIDs.remove(slotID)
        } else {
            autoSpeakSlotIDs.insert(slotID)
        }
        onSpeechPresentationChange?()
    }

    /// Manual reading is an explicit user action and therefore works even
    /// without an armed automatic source. It is also an explicit replay
    /// command, so the automatic dedupe/suppression sets do not block it.
    func readLatestResponse(for slotID: UUID) {
        playbackIntentEpoch &+= 1
        suppressCurrentAndPendingSpeech()
        speechQueue.clear()
        currentItem = nil
        speechService.stop()
        setCurrentSpeakingSlot(nil)
        requestLatestResponse(for: slotID, origin: .manual)
    }

    /// Stop is local to speech. It never sends a cancellation to ChatGPT.
    func stop() {
        stopEpoch &+= 1
        playbackIntentEpoch &+= 1
        suppressCurrentAndPendingSpeech()
        speechQueue.clear()
        currentItem = nil
        speechService.stop()
        setCurrentSpeakingSlot(nil)
    }

    private func suppressCurrentAndPendingSpeech() {
        if let currentItem {
            suppressedResponses[currentItem.responseID.slotID, default: []].insert(
                currentItem.responseID
            )
        }
        for item in speechQueue.items {
            suppressedResponses[item.responseID.slotID, default: []].insert(item.responseID)
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
        extractionRequests.removeValue(forKey: slotID)
        speechQueue.removeItems(forSlotID: slotID)
        if currentItem?.responseID.slotID == slotID {
            currentItem = nil
            speechService.stop()
            setCurrentSpeakingSlot(nil)
            speakNext()
        }
        spokenResponses.removeValue(forKey: slotID)
        suppressedResponses.removeValue(forKey: slotID)
        latestResponse.removeValue(forKey: slotID)
    }

    private func requestLatestResponse(
        for slotID: UUID,
        origin: SpeechRequestOrigin
    ) {
        guard let webView = webViewProvider(slotID),
              let bridge = responseBridgeProvider(slotID) else {
            return
        }

        nextGeneration &+= 1
        let request = ExtractionRequest(
            generation: nextGeneration,
            stopEpoch: stopEpoch,
            playbackIntentEpoch: playbackIntentEpoch,
            webView: webView,
            origin: origin
        )
        extractionRequests[slotID] = request

        let requestGeneration = request.generation
        let expectedWebView = webView
        bridge.extractLatest { [weak self, weak expectedWebView] payload in
            guard let self,
                  let expectedWebView,
                  let request = self.extractionRequests[slotID],
                  request.generation == requestGeneration,
                  request.webView === expectedWebView,
                  self.webViewProvider(slotID) === expectedWebView else {
                return
            }
            self.extractionRequests.removeValue(forKey: slotID)
            guard request.playbackIntentEpoch == self.playbackIntentEpoch else {
                return
            }
            guard let payload,
                  let responseID = payload.responseID else {
                return
            }

            let identity = SpeechResponseIdentity(
                slotID: slotID,
                documentToken: payload.documentToken,
                responseID: responseID
            )
            self.latestResponse[slotID] = identity
            guard request.stopEpoch == self.stopEpoch else {
                self.suppressedResponses[slotID, default: []].insert(identity)
                return
            }
            self.enqueue(
                payload.blocks,
                identity: identity,
                origin: request.origin
            )
        }
    }

    private func enqueue(
        _ blocks: [SpeechContentBlock],
        identity: SpeechResponseIdentity,
        origin: SpeechRequestOrigin
    ) {
        if origin == .automatic {
            guard !suppressedResponses[identity.slotID, default: []].contains(identity),
                  !spokenResponses[identity.slotID, default: []].contains(identity) else {
                return
            }
        }

        let cleaned = SpeechContentCleaner.clean(blocks)
        let requests = SpeechLanguageRouter.utteranceRequests(
            for: cleaned,
            startingToken: nextSequence
        )
        guard !requests.isEmpty else { return }

        if origin == .automatic {
            let appended = speechQueue.append(
                responseID: identity,
                requests: requests
            )
            guard appended > 0 else { return }
            spokenResponses[identity.slotID, default: []].insert(identity)
        } else {
            speechQueue.replace(responseID: identity, requests: requests)
        }
        nextSequence &+= UInt64(requests.count)
        speakNext()
    }

    private func speakNext() {
        guard currentItem == nil,
              let item = speechQueue.dequeue() else {
            return
        }
        currentItem = item
        setCurrentSpeakingSlot(item.responseID.slotID)
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
