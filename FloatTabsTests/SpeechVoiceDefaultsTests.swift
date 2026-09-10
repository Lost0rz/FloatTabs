import AVFoundation
import XCTest
@testable import FloatTabs

@MainActor
final class SpeechVoiceDefaultsTests: XCTestCase {
    func testVoiceNameNormalizationTreatsTingTingSpellingVariantsAsOneName() {
        XCTAssertEqual(SpeechVoiceCatalog.normalizedVoiceName("Ting-Ting"), "tingting")
        XCTAssertEqual(SpeechVoiceCatalog.normalizedVoiceName("Ting Ting"), "tingting")
        XCTAssertEqual(SpeechVoiceCatalog.normalizedVoiceName("Tingting"), "tingting")
        XCTAssertEqual(SpeechVoiceCatalog.normalizedVoiceName("ting-ting"), "tingting")
    }

    func testNamedDefaultsFilterLanguageRoleThenUseExistingQualityOrdering() {
        let voices = [
            SpeechVoiceDescriptor(
                identifier: "en.samantha.default",
                name: "Samantha",
                language: "en-US",
                quality: .default
            ),
            SpeechVoiceDescriptor(
                identifier: "zh.tingting.premium",
                name: "Ting Ting",
                language: "zh-CN",
                quality: .premium
            ),
            SpeechVoiceDescriptor(
                identifier: "zh.tingting.enhanced",
                name: "Ting-Ting",
                language: "zh-CN",
                quality: .enhanced
            ),
            SpeechVoiceDescriptor(
                identifier: "en.samantha.premium",
                name: "Samantha",
                language: "en-GB",
                quality: .premium
            ),
        ]

        XCTAssertEqual(
            SpeechVoiceCatalog.defaultVoiceDescriptor(for: .chinese, voices: voices)?.identifier,
            "zh.tingting.premium"
        )
        XCTAssertEqual(
            SpeechVoiceCatalog.defaultVoiceDescriptor(for: .english, voices: voices)?.identifier,
            "en.samantha.premium"
        )
        XCTAssertEqual(
            SpeechVoiceCatalog.defaultVoiceDisplayName(for: .chinese),
            "FloatTabs Default — Ting-Ting"
        )
    }

    func testExplicitUnavailableIdentifierDoesNotMutatePreferences() {
        let suite = "FloatTabsTests.SpeechDefaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = SpeechPreferencesStore(defaults: defaults)
        preferences.chineseVoiceIdentifier = "user.voice.temporarily.unavailable"

        let voices = [SpeechVoiceDescriptor(
            identifier: "zh.tingting",
            name: "Ting-Ting",
            language: "zh-CN",
            quality: .default
        )]
        XCTAssertEqual(
            SpeechVoiceCatalog.defaultVoiceDescriptor(for: .chinese, voices: voices)?.identifier,
            "zh.tingting"
        )
        XCTAssertEqual(preferences.chineseVoiceIdentifier, "user.voice.temporarily.unavailable")
    }

    func testProductionResolutionPlanPutsExplicitIdentifierBeforeNamedDefault() {
        let suite = "FloatTabsTests.SpeechResolutionPlan.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = SpeechPreferencesStore(defaults: defaults)
        preferences.chineseVoiceIdentifier = "explicit.chinese"
        preferences.englishVoiceIdentifier = "explicit.english"
        let voices = [
            SpeechVoiceDescriptor(
                identifier: "zh.tingting.premium",
                name: "Ting Ting",
                language: "zh-CN",
                quality: .premium
            ),
            SpeechVoiceDescriptor(
                identifier: "en.samantha.premium",
                name: "Samantha",
                language: "en-US",
                quality: .premium
            ),
        ]

        XCTAssertEqual(
            SpeechVoiceCatalog.resolutionPlan(
                for: .chinese,
                preferences: preferences,
                voices: voices
            ),
            [
                .identifier("explicit.chinese"),
                .identifier("zh.tingting.premium"),
                .language("zh-CN"),
            ]
        )
        XCTAssertEqual(
            SpeechVoiceCatalog.resolutionPlan(
                for: .english,
                preferences: preferences,
                voices: voices
            ),
            [
                .identifier("explicit.english"),
                .identifier("en.samantha.premium"),
                .language("en-US"),
            ]
        )
    }

    func testNamedDefaultsPrecedeSystemLanguageAndGenericRoleFallback() {
        let suite = "FloatTabsTests.SpeechNamedPrecedence.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = SpeechPreferencesStore(defaults: defaults)
        let voices = [
            SpeechVoiceDescriptor(
                identifier: "zh.tingting.premium",
                name: "Ting-Ting",
                language: "zh-CN",
                quality: .premium
            ),
            SpeechVoiceDescriptor(
                identifier: "zh.generic",
                name: "Chinese Generic",
                language: "zh-CN",
                quality: .default
            ),
            SpeechVoiceDescriptor(
                identifier: "en.samantha.enhanced",
                name: "Samantha",
                language: "en-US",
                quality: .enhanced
            ),
            SpeechVoiceDescriptor(
                identifier: "en.generic",
                name: "English Generic",
                language: "en-US",
                quality: .default
            ),
        ]

        XCTAssertEqual(
            SpeechVoiceCatalog.resolutionPlan(
                for: .chinese,
                preferences: preferences,
                voices: voices
            ),
            [
                .identifier("zh.tingting.premium"),
                .language("zh-CN"),
                .identifier("zh.generic"),
            ]
        )
        XCTAssertEqual(
            SpeechVoiceCatalog.resolutionPlan(
                for: .english,
                preferences: preferences,
                voices: voices
            ),
            [
                .identifier("en.samantha.enhanced"),
                .language("en-US"),
                .identifier("en.generic"),
            ]
        )
    }

    func testMissingNamedDefaultsUseSystemLanguageBeforeGenericAndRejectWrongLanguageNames() {
        let suite = "FloatTabsTests.SpeechMissingNamedDefaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = SpeechPreferencesStore(defaults: defaults)
        let chineseVoices = [
            SpeechVoiceDescriptor(
                identifier: "en.tingting.wrong-role",
                name: "Ting-Ting",
                language: "en-US",
                quality: .premium
            ),
            SpeechVoiceDescriptor(
                identifier: "zh.generic",
                name: "Chinese Generic",
                language: "zh-CN",
                quality: .default
            ),
        ]
        let englishVoices = [
            SpeechVoiceDescriptor(
                identifier: "zh.samantha.wrong-role",
                name: "Samantha",
                language: "zh-CN",
                quality: .premium
            ),
            SpeechVoiceDescriptor(
                identifier: "en.generic",
                name: "English Generic",
                language: "en-US",
                quality: .default
            ),
        ]

        XCTAssertEqual(
            SpeechVoiceCatalog.resolutionPlan(
                for: .chinese,
                preferences: preferences,
                voices: chineseVoices
            ),
            [.language("zh-CN"), .identifier("zh.generic")]
        )
        XCTAssertEqual(
            SpeechVoiceCatalog.resolutionPlan(
                for: .english,
                preferences: preferences,
                voices: englishVoices
            ),
            [.language("en-US"), .identifier("en.generic")]
        )
    }

    func testProductionResolverConsumesExplicitThenLanguageFallbackWithoutMutatingPreference() throws {
        guard let fallbackVoice = AVSpeechSynthesisVoice(language: "zh-CN") else {
            throw XCTSkip("zh-CN speech voice is unavailable in this test environment")
        }
        let suite = "FloatTabsTests.SpeechResolverConsumption.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = SpeechPreferencesStore(defaults: defaults)
        preferences.chineseVoiceIdentifier = "explicit.temporarily.unavailable"
        var attempts: [SpeechVoiceResolutionAttempt] = []
        let catalog = SpeechVoiceCatalog(
            notificationCenter: NotificationCenter(),
            voicesProvider: { [] },
            voiceResolver: { identifier in
                attempts.append(.identifier(identifier))
                return nil
            },
            languageVoiceResolver: { language in
                attempts.append(.language(language))
                return fallbackVoice
            }
        )

        XCTAssertIdentical(catalog.voice(for: .chinese, preferences: preferences), fallbackVoice)
        XCTAssertEqual(
            attempts,
            [.identifier("explicit.temporarily.unavailable"), .language("zh-CN")]
        )
        XCTAssertEqual(
            preferences.chineseVoiceIdentifier,
            "explicit.temporarily.unavailable"
        )
    }

    func testAutomaticRoleKeepsExistingNoVoiceResolutionSemantics() {
        let preferences = SpeechPreferencesStore(defaults: UserDefaults())
        XCTAssertTrue(
            SpeechVoiceCatalog.resolutionPlan(
                for: .automatic,
                preferences: preferences,
                voices: []
            ).isEmpty
        )
    }
}
