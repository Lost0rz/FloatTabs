import Foundation

enum AppLanguage: String, CaseIterable, Codable, Equatable, Sendable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var displayName: String {
        switch self {
        case .system:
            return L10n.tr("System", "跟随系统")
        case .english:
            return "English"
        case .simplifiedChinese:
            return "简体中文"
        }
    }
}

enum EffectiveAppLanguage: String, Equatable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
}

private final class AppLocalizationStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var selectedLanguageValue: AppLanguage = .english
    private var preferredLanguagesProviderValue: @Sendable () -> [String] = {
        Locale.preferredLanguages
    }

    var selectedLanguage: AppLanguage {
        get {
            lock.lock()
            defer { lock.unlock() }
            return selectedLanguageValue
        }
        set {
            lock.lock()
            selectedLanguageValue = newValue
            lock.unlock()
        }
    }

    var preferredLanguages: [String] {
        lock.lock()
        let provider = preferredLanguagesProviderValue
        lock.unlock()
        return provider()
    }

    func setPreferredLanguagesProvider(_ provider: (@Sendable () -> [String])?) {
        lock.lock()
        preferredLanguagesProviderValue = provider ?? { Locale.preferredLanguages }
        lock.unlock()
    }

    func reset() {
        lock.lock()
        selectedLanguageValue = .english
        preferredLanguagesProviderValue = { Locale.preferredLanguages }
        lock.unlock()
    }
}

enum AppLocalization {
    private static let storage = AppLocalizationStorage()

    /// Process-memory selection defaults to `.english` until the app binds
    /// `AppPreferencesStore` at launch so isolated XCTests stay locale-stable.
    nonisolated static var selectedLanguage: AppLanguage {
        get { storage.selectedLanguage }
        set { storage.selectedLanguage = newValue }
    }

    nonisolated static func resolveSystemLanguage(
        preferredLanguages: [String]
    ) -> EffectiveAppLanguage {
        for identifier in preferredLanguages {
            let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized.hasPrefix("zh") {
                return .simplifiedChinese
            }
            if normalized.hasPrefix("en") {
                return .english
            }
        }
        return .english
    }

    nonisolated static var effectiveLanguage: EffectiveAppLanguage {
        switch selectedLanguage {
        case .system:
            return resolveSystemLanguage(preferredLanguages: storage.preferredLanguages)
        case .english:
            return .english
        case .simplifiedChinese:
            return .simplifiedChinese
        }
    }

    nonisolated static var isChinese: Bool {
        effectiveLanguage == .simplifiedChinese
    }

    @MainActor
    static func apply(_ language: AppLanguage, postNotification: Bool = true) {
        let previousEffective = effectiveLanguage
        let previousSelection = selectedLanguage
        selectedLanguage = language
        guard postNotification,
              previousSelection != language || previousEffective != effectiveLanguage else {
            return
        }
        NotificationCenter.default.post(name: .floatTabsLanguageDidChange, object: nil)
    }

    nonisolated static func setPreferredLanguagesProviderForTesting(
        _ provider: (@Sendable () -> [String])?
    ) {
        storage.setPreferredLanguagesProvider(provider)
    }

    @MainActor
    static func resetForTesting() {
        storage.reset()
    }
}

enum L10n {
    nonisolated static func tr(_ english: String, _ chinese: String) -> String {
        AppLocalization.isChinese ? chinese : english
    }

    nonisolated static func defaultDisplayName(_ rawName: String) -> String {
        if rawName == "Default" {
            return tr("Default", "默认")
        }
        return rawName
    }
}

extension Notification.Name {
    static let floatTabsLanguageDidChange = Notification.Name(
        "FloatTabs.languageDidChange"
    )
    static let floatTabsAppLanguageDidChange = Notification.Name(
        "FloatTabs.appLanguageDidChange"
    )
}
