import AVFoundation
import Foundation

@MainActor
protocol SpeechSynthesizing: AnyObject {
    var onUtteranceFinished: ((UInt64) -> Void)? { get set }

    func speak(_ text: String, token: UInt64)
    func stop()
}

/// The single application-level AVSpeechSynthesizer owner. Queue policy lives
/// in AssistantSpeechCoordinator so AVFoundation remains a replaceable seam.
@MainActor
final class SpeechService: NSObject, SpeechSynthesizing, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var playbackTokens: [ObjectIdentifier: UInt64] = [:]

    var onUtteranceFinished: ((UInt64) -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, token: UInt64) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        playbackTokens[ObjectIdentifier(utterance)] = token
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
