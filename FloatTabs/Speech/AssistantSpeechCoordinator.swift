import Foundation
import WebKit

/// Coordinates response extraction, privacy-safe cleaning, bounded speech
/// segmentation, and the one app-global speech service.
@MainActor
final class AssistantSpeechCoordinator {
    private struct ExtractionRequest {
        let generation: UInt64
        let stopEpoch: UInt64
        let webView: WKWebView
    }

    private let settings: SpeechSettings
    private let speechService: SpeechSynthesizing
    private let webViewProvider: @MainActor (UUID) -> WKWebView?
    private let responseBridgeProvider: @MainActor (UUID) -> ChatGPTResponseExtracting?
    private var extractionRequests: [UUID: ExtractionRequest] = [:]
    private var nextGeneration: UInt64 = 0
    private var stopEpoch: UInt64 = 0
    private var nextSequence: UInt64 = 0
    private var spokenResponses: [UUID: Set<SpeechResponseIdentity>] = [:]
    private var suppressedResponses: [UUID: Set<SpeechResponseIdentity>] = [:]
    private var latestResponse: [UUID: SpeechResponseIdentity] = [:]
    private var currentItem: SpeechQueueItem?
    private var speechQueue = SpeechQueue()

    init(
        settings: SpeechSettings = SpeechSettings(),
        speechService: SpeechSynthesizing,
        webViewProvider: @escaping @MainActor (UUID) -> WKWebView?,
        responseBridgeProvider: @escaping @MainActor (UUID) -> ChatGPTResponseExtracting?
    ) {
        self.settings = settings
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
            guard settings.mode == .speakWhenCompleted else { return }
            requestLatestResponse(for: slotID)
        case .runtimeReset:
            reset(slotID: slotID)
        }
    }

    /// Manual reading is an explicit user action and therefore works even
    /// while automatic Speak When Completed mode is Off.
    func readLatestResponse(for slotID: UUID) {
        requestLatestResponse(for: slotID)
    }

    /// Stop is local to speech. It never sends a cancellation to ChatGPT.
    func stop() {
        stopEpoch &+= 1
        if let currentItem {
            suppressedResponses[currentItem.responseID.slotID, default: []].insert(
                currentItem.responseID
            )
        }
        for item in speechQueue.items {
            suppressedResponses[item.responseID.slotID, default: []].insert(item.responseID)
        }
        speechQueue.clear()
        currentItem = nil
        speechService.stop()
    }

    func reset(slotID: UUID) {
        nextGeneration &+= 1
        extractionRequests.removeValue(forKey: slotID)
        speechQueue.removeItems(forSlotID: slotID)
        if currentItem?.responseID.slotID == slotID {
            currentItem = nil
            speechService.stop()
        }
        spokenResponses.removeValue(forKey: slotID)
        suppressedResponses.removeValue(forKey: slotID)
        latestResponse.removeValue(forKey: slotID)
    }

    private func requestLatestResponse(for slotID: UUID) {
        guard let webView = webViewProvider(slotID),
              let bridge = responseBridgeProvider(slotID) else {
            return
        }

        nextGeneration &+= 1
        let request = ExtractionRequest(
            generation: nextGeneration,
            stopEpoch: stopEpoch,
            webView: webView
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
            self.enqueue(payload.blocks, identity: identity)
        }
    }

    private func enqueue(
        _ blocks: [SpeechContentBlock],
        identity: SpeechResponseIdentity
    ) {
        guard !suppressedResponses[identity.slotID, default: []].contains(identity),
              !spokenResponses[identity.slotID, default: []].contains(identity) else {
            return
        }

        let cleaned = SpeechContentCleaner.clean(blocks)
        let segments = SpeechSegmenter.segment(cleaned)
        guard !segments.isEmpty else { return }

        if currentItem != nil {
            currentItem = nil
            speechService.stop()
        }
        speechQueue.enqueue(
            responseID: identity,
            segments: segments,
            startingSequence: nextSequence
        )
        nextSequence += UInt64(segments.count)
        spokenResponses[identity.slotID, default: []].insert(identity)
        speakNext()
    }

    private func speakNext() {
        guard currentItem == nil,
              let item = speechQueue.dequeue() else {
            return
        }
        currentItem = item
        speechService.speak(item.text, token: item.sequence)
    }
}
