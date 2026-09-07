import AVFoundation
import Foundation

@MainActor
protocol SpeechSynthesizing: AnyObject {
    var onUtteranceFinished: (() -> Void)? { get set }

    func speak(_ text: String)
    func stop()
}

/// The single application-level AVSpeechSynthesizer owner. Queue policy lives
/// in AssistantSpeechCoordinator so AVFoundation remains a replaceable seam.
@MainActor
final class SpeechService: NSObject, SpeechSynthesizing, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()

    var onUtteranceFinished: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        synthesizer.speak(AVSpeechUtterance(string: text))
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            self?.onUtteranceFinished?()
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        // Cancellation is intentionally not an advance event. The
        // coordinator clears its current item before calling stop().
    }
}
