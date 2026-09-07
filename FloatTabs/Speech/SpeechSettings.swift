import Foundation

enum ChatGPTSpeechMode: String, CaseIterable, Equatable, Sendable {
    case off
    case speakWhenCompleted

    var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .speakWhenCompleted:
            return "Speak When Completed"
        }
    }
}

/// Durable speech preferences. Response content and runtime speech state are
/// deliberately not part of this store.
@MainActor
final class SpeechSettings {
    static let modeKey = "FloatTabs.chatGPTSpeechMode"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var mode: ChatGPTSpeechMode {
        get {
            guard let rawValue = defaults.string(forKey: Self.modeKey),
                  let mode = ChatGPTSpeechMode(rawValue: rawValue) else {
                return .off
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.modeKey)
        }
    }
}
