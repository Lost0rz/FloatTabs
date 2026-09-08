import AVFoundation
import AppKit
import Foundation

enum SpeechLanguageRole: String, CaseIterable, Equatable, Sendable {
    case chinese
    case english
    case automatic
}

struct SpeechUtteranceRequest: Equatable, Sendable {
    let text: String
    let languageRole: SpeechLanguageRole
}

struct SpeechPlaybackRequest: Equatable, Sendable {
    let text: String
    let transportToken: UInt64
    let languageRole: SpeechLanguageRole
}

/// Chooses a voice role for already-cleaned, sentence-sized speech text.
/// Technical identifiers are deliberately ignored as language evidence so a
/// Chinese sentence containing API names does not turn into many tiny voice
/// changes.
enum SpeechLanguageRouter {
    private static let technicalIdentifiers: Set<String> = [
        "api", "avspeechsynthesizer", "chatgpt", "gpt", "url", "http",
        "https", "json", "ios", "macos", "sdk", "ui",
    ]

    static func role(for text: String) -> SpeechLanguageRole {
        let chineseCount = text.reduce(into: 0) { count, character in
            if isChinese(character) { count += 1 }
        }
        guard chineseCount > 0 else {
            return containsEnglishLetters(in: text) ? .english : .automatic
        }

        let englishWordCount = text
            .split(whereSeparator: { character in
                !character.isASCII || (!character.isLetter && !character.isNumber)
            })
            .map(String.init)
            .filter { word in
                let normalized = word.lowercased()
                guard !technicalIdentifiers.contains(normalized),
                      !word.contains(where: { $0.isNumber }) else {
                    return false
                }
                return word.contains(where: { $0.isASCII && $0.isLetter })
            }
            .count

        // One incidental prose word inside Chinese remains on the Chinese
        // route, while a fully English sentence remains English.
        if englishWordCount >= 2 && englishWordCount > chineseCount {
            return .english
        }
        return .chinese
    }

    static func utteranceRequests(
        for text: String
    ) -> [SpeechUtteranceRequest] {
        SpeechSegmenter.segment(text)
            .filter(SpeechSpeakabilityFilter.containsSpeakableContent)
            .map { segment in
                SpeechUtteranceRequest(
                    text: segment,
                    languageRole: role(for: segment)
                )
            }
    }

    private static func containsEnglishLetters(in text: String) -> Bool {
        text.contains { $0.isASCII && $0.isLetter }
    }

    private static func isChinese(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                return true
            default:
                return false
            }
        }
    }
}

/// Durable preferences contain only voice identifiers and speech rate. Auto
/// Speak membership and every other playback value remain runtime-only.
@MainActor
final class SpeechPreferencesStore {
    static let chineseVoiceIdentifierKey = "FloatTabs.speech.chineseVoiceIdentifier"
    static let englishVoiceIdentifierKey = "FloatTabs.speech.englishVoiceIdentifier"
    static let speechRateKey = "FloatTabs.speech.rate"
    /// Compatibility/audit marker only. No code reads this legacy mode key.
    static let legacyModeKey = "FloatTabs.chatGPTSpeechMode"
    static let defaultSpeechRate: Float = AVSpeechUtteranceDefaultSpeechRate
    static let minimumSpeechRate: Float = 0.35
    static let maximumSpeechRate: Float = 0.65

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var chineseVoiceIdentifier: String? {
        get { defaults.string(forKey: Self.chineseVoiceIdentifierKey) }
        set { setVoiceIdentifier(newValue, for: .chinese) }
    }

    var englishVoiceIdentifier: String? {
        get { defaults.string(forKey: Self.englishVoiceIdentifierKey) }
        set { setVoiceIdentifier(newValue, for: .english) }
    }

    var speechRate: Float {
        get {
            guard defaults.object(forKey: Self.speechRateKey) != nil else {
                return Self.defaultSpeechRate
            }
            let value = defaults.float(forKey: Self.speechRateKey)
            return min(max(value, Self.minimumSpeechRate), Self.maximumSpeechRate)
        }
        set {
            defaults.set(
                min(max(newValue, Self.minimumSpeechRate), Self.maximumSpeechRate),
                forKey: Self.speechRateKey
            )
        }
    }

    func voiceIdentifier(for role: SpeechLanguageRole) -> String? {
        switch role {
        case .chinese: return chineseVoiceIdentifier
        case .english: return englishVoiceIdentifier
        case .automatic: return nil
        }
    }

    func setVoiceIdentifier(_ identifier: String?, for role: SpeechLanguageRole) {
        let key: String?
        switch role {
        case .chinese: key = Self.chineseVoiceIdentifierKey
        case .english: key = Self.englishVoiceIdentifierKey
        case .automatic: key = nil
        }
        guard let key else { return }
        if let identifier, !identifier.isEmpty {
            defaults.set(identifier, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

enum SpeechVoiceQuality: String, CaseIterable, Equatable, Sendable {
    case `default` = "Default"
    case enhanced = "Enhanced"
    case premium = "Premium"

    var sortRank: Int {
        switch self {
        case .premium: return 3
        case .enhanced: return 2
        case .default: return 1
        }
    }
}

struct SpeechVoiceDescriptor: Equatable, Sendable {
    let identifier: String
    let name: String
    let language: String
    let quality: SpeechVoiceQuality

    func displayName(for role: SpeechLanguageRole) -> String {
        let languageName: String
        switch role {
        case .chinese: languageName = "Chinese"
        case .english: languageName = "English"
        case .automatic: languageName = language
        }
        return "\(name) — \(languageName) (\(language)) — \(quality.rawValue)"
    }
}

@MainActor
protocol SpeechVoiceCatalogProviding: AnyObject {
    var voices: [SpeechVoiceDescriptor] { get }
    var onVoicesChanged: (() -> Void)? { get set }
    func voices(for role: SpeechLanguageRole) -> [SpeechVoiceDescriptor]
    func refresh()
    func voice(
        for role: SpeechLanguageRole,
        preferences: SpeechPreferencesStore
    ) -> AVSpeechSynthesisVoice?
}

/// Live Apple voice catalog. System Settings downloads are reflected through
/// AVSpeechSynthesizer's public available-voices notification.
@MainActor
final class SpeechVoiceCatalog: SpeechVoiceCatalogProviding {
    private let notificationCenter: NotificationCenter
    private let voicesProvider: () -> [AVSpeechSynthesisVoice]
    private var voicesDidChangeObserver: NSObjectProtocol?

    private(set) var voices: [SpeechVoiceDescriptor] = []
    var onVoicesChanged: (() -> Void)?

    init(
        notificationCenter: NotificationCenter = .default,
        voicesProvider: @escaping () -> [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices
    ) {
        self.notificationCenter = notificationCenter
        self.voicesProvider = voicesProvider
        refresh()
        if #available(macOS 14.0, *) {
            voicesDidChangeObserver = notificationCenter.addObserver(
                forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refresh()
                }
            }
        } else {
            voicesDidChangeObserver = nil
        }
    }

    deinit {
        if let voicesDidChangeObserver {
            notificationCenter.removeObserver(voicesDidChangeObserver)
        }
    }

    func refresh() {
        voices = voicesProvider().map { voice in
            SpeechVoiceDescriptor(
                identifier: voice.identifier,
                name: voice.name,
                language: voice.language,
                quality: Self.quality(for: voice.quality)
            )
        }
        onVoicesChanged?()
    }

    func voices(for role: SpeechLanguageRole) -> [SpeechVoiceDescriptor] {
        let filtered: [SpeechVoiceDescriptor]
        switch role {
        case .chinese:
            filtered = voices.filter { $0.language.lowercased().hasPrefix("zh-") }
        case .english:
            filtered = voices.filter { $0.language.lowercased().hasPrefix("en-") }
        case .automatic:
            filtered = voices
        }
        return Self.sorted(filtered)
    }

    func voice(
        for role: SpeechLanguageRole,
        preferences: SpeechPreferencesStore
    ) -> AVSpeechSynthesisVoice? {
        guard role != .automatic else { return nil }
        if let identifier = preferences.voiceIdentifier(for: role),
           voices.contains(where: { $0.identifier == identifier }),
           let preferred = AVSpeechSynthesisVoice(identifier: identifier) {
            return preferred
        }
        if let matching = voices(for: role).first,
           let voice = AVSpeechSynthesisVoice(identifier: matching.identifier) {
            return voice
        }
        let language = role == .chinese ? "zh-CN" : "en-US"
        return AVSpeechSynthesisVoice(language: language)
    }

    private static func sorted(_ voices: [SpeechVoiceDescriptor]) -> [SpeechVoiceDescriptor] {
        voices.sorted {
            if $0.quality.sortRank != $1.quality.sortRank {
                return $0.quality.sortRank > $1.quality.sortRank
            }
            if $0.name.localizedCaseInsensitiveCompare($1.name) != .orderedSame {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.language < $1.language
        }
    }

    private static func quality(
        for quality: AVSpeechSynthesisVoiceQuality
    ) -> SpeechVoiceQuality {
        if quality == .enhanced { return .enhanced }
        if #available(macOS 14.0, *), quality == .premium { return .premium }
        return .default
    }
}

enum SpeechSystemSettings {
    static let spokenContentURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.universalaccess?SpokenContent"
    )!
    static let accessibilityRootURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.universalaccess"
    )!

    static func openHighQualityVoices(
        using opener: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) -> Bool {
        opener(spokenContentURL) || opener(accessibilityRootURL)
    }
}
