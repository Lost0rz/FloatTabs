import AVFoundation
import Foundation

@MainActor
protocol SpeechSynthesizing: AnyObject {
    var onUtteranceFinished: ((UInt64) -> Void)? { get set }
    var onUtterancePaused: ((UInt64) -> Void)? { get set }
    var onUtteranceContinued: ((UInt64) -> Void)? { get set }

    func speak(_ request: SpeechPlaybackRequest)
    @discardableResult
    func pause() -> Bool
    @discardableResult
    func resume() -> Bool
    func stop()
}

/// The single application-level AVSpeechSynthesizer owner. Queue policy lives
/// in AssistantSpeechCoordinator so AVFoundation remains a replaceable seam.
@MainActor
final class SpeechService: NSObject, SpeechSynthesizing, AVSpeechSynthesizerDelegate {
    private enum DelegateEvent: Sendable {
        case paused
        case continued
        case finished
    }

    private let synthesizer = AVSpeechSynthesizer()
    private let preferences: SpeechPreferencesStore
    private let voiceCatalog: SpeechVoiceCatalogProviding
    private var playbackTokens: [ObjectIdentifier: UInt64] = [:]

    var onUtteranceFinished: ((UInt64) -> Void)?
    var onUtterancePaused: ((UInt64) -> Void)?
    var onUtteranceContinued: ((UInt64) -> Void)?

    init(
        preferences: SpeechPreferencesStore = SpeechPreferencesStore(),
        voiceCatalog: SpeechVoiceCatalogProviding = SpeechVoiceCatalog()
    ) {
        self.preferences = preferences
        self.voiceCatalog = voiceCatalog
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ request: SpeechPlaybackRequest) {
        guard !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        let utterance = AVSpeechUtterance(string: request.text)
        utterance.voice = voiceCatalog.voice(
            for: request.languageRole,
            preferences: preferences
        )
        utterance.rate = preferences.speechRate
        playbackTokens[ObjectIdentifier(utterance)] = request.transportToken
        synthesizer.speak(utterance)
    }

    @discardableResult
    func pause() -> Bool {
        synthesizer.pauseSpeaking(at: .word)
    }

    @discardableResult
    func resume() -> Bool {
        synthesizer.continueSpeaking()
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didPause utterance: AVSpeechUtterance
    ) {
        notify(tokenFor: utterance, event: .paused)
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didContinue utterance: AVSpeechUtterance
    ) {
        notify(tokenFor: utterance, event: .continued)
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        notify(tokenFor: utterance, removing: true, event: .finished)
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.playbackTokens.removeValue(forKey: utteranceID)
        }
        // Cancellation is intentionally not an advance event. The
        // coordinator clears its current item before calling stop().
    }

    private nonisolated func notify(
        tokenFor utterance: AVSpeechUtterance,
        removing: Bool = false,
        event: DelegateEvent
    ) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let token: UInt64?
            if removing {
                token = self.playbackTokens.removeValue(forKey: utteranceID)
            } else {
                token = self.playbackTokens[utteranceID]
            }
            guard let token else { return }
            switch event {
            case .paused:
                self.onUtterancePaused?(token)
            case .continued:
                self.onUtteranceContinued?(token)
            case .finished:
                self.onUtteranceFinished?(token)
            }
        }
    }
}
