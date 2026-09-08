import AVFoundation
import Foundation

@MainActor
protocol SpeechSynthesizing: AnyObject {
    var onUtteranceFinished: ((UInt64) -> Void)? { get set }

    func speak(_ request: SpeechPlaybackRequest)
    func stop()
}

/// The single application-level AVSpeechSynthesizer owner. Queue policy lives
/// in AssistantSpeechCoordinator so AVFoundation remains a replaceable seam.
@MainActor
final class SpeechService: NSObject, SpeechSynthesizing, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let preferences: SpeechPreferencesStore
    private let voiceCatalog: SpeechVoiceCatalogProviding
    private var playbackTokens: [ObjectIdentifier: UInt64] = [:]

    var onUtteranceFinished: ((UInt64) -> Void)?

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

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self,
                  let token = self.playbackTokens.removeValue(forKey: utteranceID) else {
                return
            }
            self.onUtteranceFinished?(token)
        }
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
}
