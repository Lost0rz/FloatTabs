import AVFoundation
import XCTest
@testable import FloatTabs

final class SpeechSegmenterTests: XCTestCase {
    func testUsesEnglishSentenceBoundaries() {
        XCTAssertEqual(
            SpeechSegmenter.segment("First sentence. Second sentence!"),
            ["First sentence.", "Second sentence!"]
        )
    }

    func testSupportsChineseAndMixedText() {
        XCTAssertEqual(
            SpeechSegmenter.segment("第一句。Second sentence。混合完成！"),
            ["第一句。", "Second sentence。", "混合完成！"]
        )
    }

    func testDoesNotSplitDecimalPeriods() {
        XCTAssertEqual(
            SpeechSegmenter.segment("The value is 3.14. Next sentence."),
            ["The value is 3.14.", "Next sentence."]
        )
    }

    func testDoesNotSplitCommonAbbreviations() {
        XCTAssertEqual(
            SpeechSegmenter.segment("For example, e.g. this case works. Next sentence."),
            ["For example, e.g. this case works.", "Next sentence."]
        )
    }

    func testMixedChineseEnglishWithDecimalBoundary() {
        XCTAssertEqual(
            SpeechSegmenter.segment("例如版本是 3.14。Next sentence."),
            ["例如版本是 3.14。", "Next sentence."]
        )
    }

    func testBoundsLongAnswerWithoutTinyTokenSegments() {
        let text = Array(repeating: "This is a useful sentence.", count: 40).joined(separator: " ")
        let segments = SpeechSegmenter.segment(text, maximumLength: 80)

        XCTAssertGreaterThan(segments.count, 1)
        XCTAssertTrue(segments.allSatisfy { $0.count <= 80 })
        XCTAssertTrue(segments.allSatisfy { !$0.isEmpty })
    }

    func testLanguageRouterChoosesChineseAndEnglishRoles() {
        XCTAssertEqual(SpeechLanguageRouter.role(for: "这是中文测试。"), .chinese)
        XCTAssertEqual(SpeechLanguageRouter.role(for: "This is an English test."), .english)
    }

    func testLanguageRouterProducesMixedParagraphVoiceRuns() {
        let requests = SpeechLanguageRouter.utteranceRequests(
            for: "这是第一段中文。This is an English sentence.继续中文内容。"
        )

        XCTAssertEqual(
            requests.map(\.languageRole),
            [.chinese, .english, .chinese]
        )
        XCTAssertEqual(requests.map(\.text), [
            "这是第一段中文。",
            "This is an English sentence.",
            "继续中文内容。",
        ])
    }

    func testLanguageRouterDoesNotOverSplitTechnicalIdentifiersOrDecimals() {
        let requests = SpeechLanguageRouter.utteranceRequests(
            for: "这个 API 使用 AVSpeechSynthesizer。版本是 3.14，模型是 GPT-5.6。"
        )

        XCTAssertEqual(
            requests.map(\.languageRole),
            [.chinese, .english, .chinese, .english, .chinese, .english]
        )
        XCTAssertEqual(
            requests.map(\.text),
            ["这个", "API", "使用", "AVSpeechSynthesizer。", "版本是 3.14，模型是", "GPT-5.6。"]
        )
    }

    func testLanguageRouterKeepsTechnicalIdentifiersAsEnglishIslands() {
        let requests = SpeechLanguageRouter.utteranceRequests(
            for: "这个 PR #71 使用 GPT-5.6 和 ChatGPT 的 API。"
        )

        XCTAssertTrue(requests.contains { $0.languageRole == .english && $0.text.contains("PR") })
        XCTAssertTrue(requests.contains { $0.languageRole == .english && $0.text.contains("GPT-5.6") })
        XCTAssertTrue(requests.contains { $0.languageRole == .english && $0.text.contains("ChatGPT") })
        XCTAssertTrue(requests.contains { $0.languageRole == .english && $0.text.contains("API") })
    }

    func testSingleLatinVariableInChineseProseStaysWithChineseRun() {
        let requests = SpeechLanguageRouter.utteranceRequests(for: "令 x 表示半径。")

        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.languageRole, .chinese)
        XCTAssertEqual(requests.first?.text, "令 x 表示半径。")
    }

    func testLanguageRouterDropsPunctuationOnlySegments() {
        for text in ["......", "…………", "••••••", "***", "---"] {
            XCTAssertTrue(
                SpeechLanguageRouter.utteranceRequests(for: text).isEmpty,
                "Expected \(text) to produce no speech requests"
            )
        }
    }

    func testRepeatedPunctuationRemainsASeparatorButNeverAnUtterance() {
        let requests = SpeechLanguageRouter.utteranceRequests(
            for: "这是第一句......这是第二句。"
        )

        XCTAssertEqual(requests.map(\.text), ["这是第一句.", "这是第二句。"])
        XCTAssertTrue(
            requests.allSatisfy {
                SpeechSpeakabilityFilter.containsSpeakableContent($0.text)
            }
        )
    }

    func testLeadingDecorativeSeparatorIsNotReadInMixedText() {
        XCTAssertEqual(
            SpeechLanguageRouter.utteranceRequests(
                for: "第一项。--- Second item."
            ).map(\.text),
            ["第一项。", "Second item."]
        )
    }
}

@MainActor
private final class TestSpeechVoiceCatalog: SpeechVoiceCatalogProviding {
    var voices: [SpeechVoiceDescriptor]
    var onVoicesChanged: (() -> Void)?
    var refreshCount = 0

    init(voices: [SpeechVoiceDescriptor]) {
        self.voices = voices
    }

    func voices(for role: SpeechLanguageRole) -> [SpeechVoiceDescriptor] {
        let filtered: [SpeechVoiceDescriptor]
        switch role {
        case .chinese:
            filtered = voices.filter { $0.language.hasPrefix("zh-") }
        case .english:
            filtered = voices.filter { $0.language.hasPrefix("en-") }
        case .automatic:
            filtered = voices
        }
        return filtered.sorted {
            if $0.quality.sortRank != $1.quality.sortRank {
                return $0.quality.sortRank > $1.quality.sortRank
            }
            return $0.name < $1.name
        }
    }

    func refresh() {
        refreshCount += 1
        onVoicesChanged?()
    }

    func voice(
        for role: SpeechLanguageRole,
        preferences: SpeechPreferencesStore
    ) -> AVSpeechSynthesisVoice? {
        nil
    }
}

@MainActor
final class SpeechSettingsTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "FloatTabsTests.SpeechSettings.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    private var sampleVoices: [SpeechVoiceDescriptor] {
        [
            SpeechVoiceDescriptor(
                identifier: "zh.default",
                name: "Chinese Default",
                language: "zh-CN",
                quality: .default
            ),
            SpeechVoiceDescriptor(
                identifier: "zh.premium",
                name: "Chinese Premium",
                language: "zh-CN",
                quality: .premium
            ),
            SpeechVoiceDescriptor(
                identifier: "en.enhanced",
                name: "English Enhanced",
                language: "en-US",
                quality: .enhanced
            ),
        ]
    }

    func testPreferencesPersistVoiceIdentifiersAndRateButNeverArmATab() {
        let defaults = makeDefaults()
        defaults.set("speakWhenCompleted", forKey: SpeechPreferencesStore.legacyModeKey)
        let store = SpeechPreferencesStore(defaults: defaults)

        XCTAssertNil(store.chineseVoiceIdentifier)
        XCTAssertEqual(store.speechRate, SpeechPreferencesStore.defaultSpeechRate)
        XCTAssertTrue(store.followSpeechOnPage)
        store.chineseVoiceIdentifier = "zh.premium"
        store.englishVoiceIdentifier = "en.enhanced"
        store.speechRate = 0.61
        store.followSpeechOnPage = false

        let reloaded = SpeechPreferencesStore(defaults: defaults)
        XCTAssertEqual(reloaded.chineseVoiceIdentifier, "zh.premium")
        XCTAssertEqual(reloaded.englishVoiceIdentifier, "en.enhanced")
        XCTAssertEqual(reloaded.speechRate, 0.61, accuracy: 0.001)
        XCTAssertFalse(reloaded.followSpeechOnPage)
        XCTAssertEqual(defaults.string(forKey: SpeechPreferencesStore.legacyModeKey), "speakWhenCompleted")
    }

    func testVoiceCatalogFiltersAndSortsByAppleQualityThenName() {
        let catalog = TestSpeechVoiceCatalog(voices: sampleVoices)

        XCTAssertEqual(catalog.voices(for: .chinese).map(\.quality), [.premium, .default])
        XCTAssertEqual(catalog.voices(for: .english).map(\.language), ["en-US"])
        XCTAssertTrue(
            catalog.voices(for: .chinese).first?.displayName(for: .chinese).contains("Premium") == true
        )
    }

    func testHighQualityVoiceActionUsesDirectLinkThenAccessibilityFallback() {
        var opened: [URL] = []
        let result = SpeechSystemSettings.openHighQualityVoices { url in
            opened.append(url)
            return url == SpeechSystemSettings.accessibilityRootURL
        }

        XCTAssertTrue(result)
        XCTAssertEqual(
            opened,
            [SpeechSystemSettings.spokenContentURL, SpeechSystemSettings.accessibilityRootURL]
        )
    }

    func testSpeechSettingsTabShowsVoiceQualityRefreshPreviewAndManageActions() {
        let defaults = makeDefaults()
        let preferences = SpeechPreferencesStore(defaults: defaults)
        let catalog = TestSpeechVoiceCatalog(voices: sampleVoices)
        var previewRequests: [SpeechUtteranceRequest] = []
        var opened: [URL] = []
        let controller = SpeechSettingsViewController(
            preferencesStore: preferences,
            voiceCatalog: catalog,
            previewHandler: { requests in
                previewRequests = requests
            },
            systemSettingsOpener: { url in
                opened.append(url)
                return true
            }
        )
        controller.loadViewIfNeeded()

        XCTAssertEqual(controller.title, "Speech")
        XCTAssertEqual(controller.followSpeechSwitch.state, .on)
        XCTAssertEqual(controller.chineseVoicePopup.item(at: 0)?.title, "FloatTabs Default — Ting-Ting")
        XCTAssertEqual(controller.chineseVoicePopup.item(at: 1)?.title, "Chinese Premium — Chinese (zh-CN) — Premium")
        XCTAssertEqual(controller.englishVoicePopup.item(at: 1)?.title, "English Enhanced — English (en-US) — Enhanced")

        controller.chineseVoicePopup.selectItem(at: 1)
        controller.chineseVoiceChanged(controller.chineseVoicePopup)
        XCTAssertEqual(preferences.chineseVoiceIdentifier, "zh.premium")

        controller.speechRateSlider.doubleValue = 0.60
        controller.speechRateChanged(controller.speechRateSlider)
        XCTAssertEqual(preferences.speechRate, 0.60, accuracy: 0.001)

        controller.followSpeechSwitch.state = .off
        controller.followSpeechChanged(controller.followSpeechSwitch)
        XCTAssertFalse(preferences.followSpeechOnPage)

        controller.mixedPreview(controller.mixedPreviewButton)
        XCTAssertEqual(previewRequests.map(\.languageRole), [.chinese, .english, .chinese])

        catalog.refreshCount = 0
        controller.refreshVoices(controller.refreshVoicesButton)
        XCTAssertEqual(catalog.refreshCount, 1)
        controller.manageHighQualityVoices(controller.manageHighQualityVoicesButton)
        XCTAssertEqual(opened, [SpeechSystemSettings.spokenContentURL])
    }

    func testSpeechSettingsPreviewCanUseTheSharedPlaybackHandler() {
        let defaults = makeDefaults()
        let preferences = SpeechPreferencesStore(defaults: defaults)
        let catalog = TestSpeechVoiceCatalog(voices: sampleVoices)
        var previewRequests: [SpeechUtteranceRequest] = []
        let controller = SpeechSettingsViewController(
            preferencesStore: preferences,
            voiceCatalog: catalog,
            previewHandler: { requests in
                previewRequests = requests
            }
        )
        controller.loadViewIfNeeded()

        controller.englishPreview(controller.englishPreviewButton)

        XCTAssertEqual(previewRequests.map(\.text), ["This is a FloatTabs English voice test."])
        XCTAssertEqual(previewRequests.map(\.languageRole), [.english])
    }
}
