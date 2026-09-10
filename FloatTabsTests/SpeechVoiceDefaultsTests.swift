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
}
