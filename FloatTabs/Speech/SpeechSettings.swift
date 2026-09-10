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
    let sourceLocator: SpeechSourceLocator?

    init(
        text: String,
        languageRole: SpeechLanguageRole,
        sourceLocator: SpeechSourceLocator? = nil
    ) {
        self.text = text
        self.languageRole = languageRole
        self.sourceLocator = sourceLocator
    }
}

struct SpeechPlaybackRequest: Equatable, Sendable {
    let text: String
    let transportToken: UInt64
    let languageRole: SpeechLanguageRole
}

/// Routes already-cleaned speech into coherent language runs. Technical
/// identifiers are protected English islands rather than ignored evidence:
/// they remain grouped with nearby English prose without turning every single
/// Latin variable into a voice change.
enum SpeechLanguageRouter {
    private static let technicalIdentifiers: Set<String> = [
        "api", "avspeechsynthesizer", "chatgpt", "gpt", "url", "http",
        "https", "json", "ios", "macos", "sdk", "ui", "pr",
    ]

    private struct LanguageRun {
        let text: String
        let role: SpeechLanguageRole
    }

    static func role(for text: String) -> SpeechLanguageRole {
        let runs = languageRuns(in: text)
        guard !runs.isEmpty else { return .automatic }
        if runs.allSatisfy({ $0.role == .automatic }) {
            return .automatic
        }
        let chineseCount = text.reduce(into: 0) { count, character in
            if isChinese(character) { count += 1 }
        }
        let englishCount = runs
            .filter { $0.role == .english }
            .reduce(into: 0) { count, run in
                count += run.text.filter { $0.isASCII && $0.isLetter }.count
            }
        if chineseCount == 0 && englishCount > 0 {
            return .english
        }
        if englishCount >= 2 && englishCount > chineseCount {
            return .english
        }
        return .chinese
    }

    static func utteranceRequests(
        for text: String
    ) -> [SpeechUtteranceRequest] {
        SpeechSegmenter.segment(text)
            .flatMap { sentence in
                languageRuns(in: sentence).flatMap { run in
                    SpeechSegmenter.segment(run.text)
                        .filter(SpeechSpeakabilityFilter.containsSpeakableContent)
                        .map { segment in
                            SpeechUtteranceRequest(
                                text: segment,
                                languageRole: run.role,
                                sourceLocator: nil
                            )
                        }
                }
            }
    }

    static func utteranceRequests(
        for blocks: [SpeechContentBlock]
    ) -> [SpeechUtteranceRequest] {
        let cleanedBlocks = SpeechContentCleaner.cleanBlocks(blocks)
        let surroundingText = cleanedBlocks
            .filter { $0.kind != .mathInline && $0.kind != .mathBlock }
            .map(\.text)
            .joined(separator: " ")
        let fallbackRole = role(for: surroundingText)

        var requests: [SpeechUtteranceRequest] = []
        for (index, block) in cleanedBlocks.enumerated() {
            let isMath = block.kind == .mathInline || block.kind == .mathBlock
            let languageRole: SpeechLanguageRole
            let text: String
            if isMath {
                let nearestContext = nearestTextContext(
                    around: index,
                    in: cleanedBlocks
                )
                let contextualRole = nearestContext.map(role(for:)) ?? .automatic
                languageRole = contextualRole == .automatic ? fallbackRole : contextualRole
                text = MathSpeechNormalizer.normalize(
                    block.text,
                    languageRole: languageRole
                ).text
                requests.append(contentsOf: SpeechSegmenter.segment(text)
                    .filter(SpeechSpeakabilityFilter.containsSpeakableContent)
                    .map { segment in
                        SpeechUtteranceRequest(
                            text: segment,
                            languageRole: languageRole == .automatic
                                ? role(for: segment)
                                : languageRole,
                            sourceLocator: block.sourceLocator
                        )
                    })
                continue
            }

            requests.append(contentsOf: SpeechSegmenter.segment(block.text)
                .flatMap { sentence in
                    languageRuns(in: sentence).flatMap { run in
                        SpeechSegmenter.segment(run.text)
                            .filter(SpeechSpeakabilityFilter.containsSpeakableContent)
                            .map { segment in
                                SpeechUtteranceRequest(
                                    text: segment,
                                    languageRole: run.role,
                                    sourceLocator: block.sourceLocator
                                )
                            }
                    }
                })
        }
        return requests
    }

    private static func languageRuns(in text: String) -> [LanguageRun] {
        let characters = Array(text)
        guard !characters.isEmpty else { return [] }

        var chunks: [(text: String, isChinese: Bool)] = []
        var current = ""
        var currentIsChinese: Bool?
        for character in characters {
            let chinese = isChinese(character)
            if let currentIsChinese,
               currentIsChinese != chinese,
               !current.isEmpty {
                chunks.append((current, currentIsChinese))
                current.removeAll(keepingCapacity: true)
            }
            current.append(character)
            currentIsChinese = chinese
        }
        if let currentIsChinese, !current.isEmpty {
            chunks.append((current, currentIsChinese))
        }

        var runs: [LanguageRun] = []
        var leadingNeutral = ""
        for chunk in chunks {
            guard !chunk.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }

            let role: SpeechLanguageRole?
            if chunk.isChinese {
                role = .chinese
            } else if containsEnglishEvidence(in: chunk.text) {
                role = .english
            } else {
                role = nil
            }

            guard let role else {
                if runs.isEmpty {
                    leadingNeutral += chunk.text
                } else {
                    runs[runs.index(before: runs.endIndex)] = LanguageRun(
                        text: runs[runs.index(before: runs.endIndex)].text + chunk.text,
                        role: runs[runs.index(before: runs.endIndex)].role
                    )
                }
                continue
            }

            let value = leadingNeutral + chunk.text
            leadingNeutral.removeAll(keepingCapacity: true)
            appendRun(&runs, text: value, role: role)
        }

        if !leadingNeutral.isEmpty, !runs.isEmpty {
            let lastIndex = runs.index(before: runs.endIndex)
            runs[lastIndex] = LanguageRun(
                text: runs[lastIndex].text + leadingNeutral,
                role: runs[lastIndex].role
            )
        }

        if runs.isEmpty {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty,
               value.contains(where: { $0.isNumber }) {
                return [LanguageRun(text: value, role: .automatic)]
            }
            if !value.isEmpty,
               !value.contains(where: isChinese),
               value.contains(where: { $0.isASCII && $0.isLetter }) {
                return [LanguageRun(text: value, role: .english)]
            }
        }

        return runs.compactMap { run in
            let value = run.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            return LanguageRun(text: value, role: run.role)
        }
    }

    private static func appendRun(
        _ runs: inout [LanguageRun],
        text: String,
        role: SpeechLanguageRole
    ) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let last = runs.last, last.role == role {
            runs[runs.index(before: runs.endIndex)] = LanguageRun(
                text: last.text + text,
                role: role
            )
        } else {
            runs.append(LanguageRun(text: text, role: role))
        }
    }

    private static func containsEnglishEvidence(in text: String) -> Bool {
        let tokens = text
            .split { character in
                !(character.isASCII && (character.isLetter || character.isNumber))
            }
            .map(String.init)
        guard tokens.contains(where: { $0.contains(where: { $0.isASCII && $0.isLetter }) }) else {
            return false
        }

        let compact = text
            .lowercased()
            .filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        if technicalIdentifiers.contains(compact) {
            return true
        }
        if tokens.count > 1 || text.contains("#") {
            return true
        }
        guard let token = tokens.first else { return false }
        return token.count >= 2 || token.contains(where: { $0.isNumber })
    }

    private static func nearestTextContext(
        around index: Int,
        in blocks: [SpeechContentBlock]
    ) -> String? {
        for distance in 1...max(blocks.count, 1) {
            let left = index - distance
            if blocks.indices.contains(left), !isMath(blocks[left]) {
                return blocks[left].text
            }
            let right = index + distance
            if blocks.indices.contains(right), !isMath(blocks[right]) {
                return blocks[right].text
            }
        }
        return nil
    }

    private static func isMath(_ block: SpeechContentBlock) -> Bool {
        block.kind == .mathInline || block.kind == .mathBlock
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
    static let followSpeechOnPageKey = "FloatTabs.speech.followSpeechOnPage"
    /// Compatibility/audit marker only. No code reads this legacy mode key.
    static let legacyModeKey = "FloatTabs.chatGPTSpeechMode"
    static let defaultSpeechRate: Float = AVSpeechUtteranceDefaultSpeechRate
    static let minimumSpeechRate: Float = 0.35
    static let maximumSpeechRate: Float = 0.65
    static let defaultFollowSpeechOnPage = true

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

    var followSpeechOnPage: Bool {
        get {
            guard defaults.object(forKey: Self.followSpeechOnPageKey) != nil else {
                return Self.defaultFollowSpeechOnPage
            }
            return defaults.bool(forKey: Self.followSpeechOnPageKey)
        }
        set {
            defaults.set(newValue, forKey: Self.followSpeechOnPageKey)
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
    typealias VoiceResolver = @MainActor (String) -> AVSpeechSynthesisVoice?
    typealias LanguageVoiceResolver = @MainActor (String) -> AVSpeechSynthesisVoice?

    static let chineseDefaultVoiceName = "Ting-Ting"
    static let englishDefaultVoiceName = "Samantha"

    private let notificationCenter: NotificationCenter
    private let voicesProvider: () -> [AVSpeechSynthesisVoice]
    private let voiceResolver: VoiceResolver
    private let languageVoiceResolver: LanguageVoiceResolver
    private var voicesDidChangeObserver: NSObjectProtocol?

    private(set) var voices: [SpeechVoiceDescriptor] = []
    var onVoicesChanged: (() -> Void)?

    init(
        notificationCenter: NotificationCenter = .default,
        voicesProvider: @escaping () -> [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices,
        voiceResolver: @escaping VoiceResolver = { AVSpeechSynthesisVoice(identifier: $0) },
        languageVoiceResolver: @escaping LanguageVoiceResolver = { AVSpeechSynthesisVoice(language: $0) }
    ) {
        self.notificationCenter = notificationCenter
        self.voicesProvider = voicesProvider
        self.voiceResolver = voiceResolver
        self.languageVoiceResolver = languageVoiceResolver
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
           let preferred = voiceResolver(identifier) {
            return preferred
        }
        if let matching = Self.defaultVoiceDescriptor(for: role, voices: voices(for: role)),
           let voice = voiceResolver(matching.identifier) {
            return voice
        }
        let language = role == .chinese ? "zh-CN" : "en-US"
        if let systemVoice = languageVoiceResolver(language) {
            return systemVoice
        }
        return voices(for: role).compactMap { voiceResolver($0.identifier) }.first
    }

    static func defaultVoiceDisplayName(for role: SpeechLanguageRole) -> String {
        switch role {
        case .chinese:
            return "FloatTabs Default — \(chineseDefaultVoiceName)"
        case .english:
            return "FloatTabs Default — \(englishDefaultVoiceName)"
        case .automatic:
            return "System Automatic"
        }
    }

    static func normalizedVoiceName(_ name: String) -> String {
        String(name.lowercased().unicodeScalars.filter {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
        })
    }

    static func defaultVoiceDescriptor(
        for role: SpeechLanguageRole,
        voices: [SpeechVoiceDescriptor]
    ) -> SpeechVoiceDescriptor? {
        guard let defaultName = defaultVoiceName(for: role) else { return nil }
        let target = normalizedVoiceName(defaultName)
        let roleVoices = voices.filter { voice in
            switch role {
            case .chinese: return voice.language.lowercased().hasPrefix("zh-")
            case .english: return voice.language.lowercased().hasPrefix("en-")
            case .automatic: return true
            }
        }
        return sorted(roleVoices).first {
            normalizedVoiceName($0.name) == target
        }
    }

    private static func defaultVoiceName(for role: SpeechLanguageRole) -> String? {
        switch role {
        case .chinese: return chineseDefaultVoiceName
        case .english: return englishDefaultVoiceName
        case .automatic: return nil
        }
    }

    static func sorted(_ voices: [SpeechVoiceDescriptor]) -> [SpeechVoiceDescriptor] {
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
