import AVFoundation
import Foundation

@MainActor
protocol SpeechSynthesizing: AnyObject {
    var onUtteranceStarted: ((UInt64) -> Void)? { get set }
    var onUtteranceFinished: ((UInt64) -> Void)? { get set }
    var onUtterancePaused: ((UInt64) -> Void)? { get set }
    var onUtteranceContinued: ((UInt64) -> Void)? { get set }
    var onUtteranceCancelled: ((UInt64) -> Void)? { get set }

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
        case started
        case paused
        case continued
        case finished
        case cancelled
    }

    private struct ActiveUtterance {
        let utterance: AVSpeechUtterance
        let token: UInt64
    }

    private let synthesizer = AVSpeechSynthesizer()
    private let preferences: SpeechPreferencesStore
    private let voiceCatalog: SpeechVoiceCatalogProviding
    /// Retaining each active utterance keeps its identity stable until the
    /// delegate terminal event arrives. This prevents an old async callback
    /// from deleting a newer token after ObjectIdentifier address reuse.
    private var activeUtterances: [ObjectIdentifier: ActiveUtterance] = [:]

    var onUtteranceStarted: ((UInt64) -> Void)?
    var onUtteranceFinished: ((UInt64) -> Void)?
    var onUtterancePaused: ((UInt64) -> Void)?
    var onUtteranceContinued: ((UInt64) -> Void)?
    var onUtteranceCancelled: ((UInt64) -> Void)?

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
        activeUtterances[ObjectIdentifier(utterance)] = ActiveUtterance(
            utterance: utterance,
            token: request.transportToken
        )
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
        didStart utterance: AVSpeechUtterance
    ) {
        notify(tokenFor: utterance, event: .started)
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
        notify(tokenFor: utterance, removing: true, event: .cancelled)
    }

    private nonisolated func notify(
        tokenFor utterance: AVSpeechUtterance,
        removing: Bool = false,
        event: DelegateEvent
    ) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self, utterance] in
            guard let self else { return }
            guard let active = self.activeUtterances[utteranceID],
                  active.utterance === utterance else {
                return
            }
            let token = active.token
            if removing {
                self.activeUtterances.removeValue(forKey: utteranceID)
            }
            switch event {
            case .started:
                self.onUtteranceStarted?(token)
            case .paused:
                self.onUtterancePaused?(token)
            case .continued:
                self.onUtteranceContinued?(token)
            case .finished:
                self.onUtteranceFinished?(token)
            case .cancelled:
                self.onUtteranceCancelled?(token)
            }
        }
    }
}
