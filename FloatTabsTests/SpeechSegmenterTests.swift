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

        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.allSatisfy { $0.languageRole == .chinese })
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
private final class TestSpeechPreviewService: SpeechSynthesizing {
    private(set) var requests: [SpeechUtteranceRequest] = []
    private(set) var stopCount = 0
    var onUtteranceFinished: ((UInt64) -> Void)?

    func speak(_ request: SpeechUtteranceRequest) {
        requests.append(request)
    }

    func stop() {
        stopCount += 1
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
        store.chineseVoiceIdentifier = "zh.premium"
        store.englishVoiceIdentifier = "en.enhanced"
        store.speechRate = 0.61

        let reloaded = SpeechPreferencesStore(defaults: defaults)
        XCTAssertEqual(reloaded.chineseVoiceIdentifier, "zh.premium")
        XCTAssertEqual(reloaded.englishVoiceIdentifier, "en.enhanced")
        XCTAssertEqual(reloaded.speechRate, 0.61, accuracy: 0.001)
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
        let preview = TestSpeechPreviewService()
        var opened: [URL] = []
        let controller = SpeechSettingsViewController(
            preferencesStore: preferences,
            voiceCatalog: catalog,
            previewService: preview,
            systemSettingsOpener: { url in
                opened.append(url)
                return true
            }
        )
        controller.loadViewIfNeeded()

        XCTAssertEqual(controller.title, "Speech")
        XCTAssertEqual(controller.chineseVoicePopup.item(at: 0)?.title, "System Automatic")
        XCTAssertEqual(controller.chineseVoicePopup.item(at: 1)?.title, "Chinese Premium — Chinese (zh-CN) — Premium")
        XCTAssertEqual(controller.englishVoicePopup.item(at: 1)?.title, "English Enhanced — English (en-US) — Enhanced")

        controller.chineseVoicePopup.selectItem(at: 1)
        controller.chineseVoiceChanged(controller.chineseVoicePopup)
        XCTAssertEqual(preferences.chineseVoiceIdentifier, "zh.premium")

        controller.speechRateSlider.doubleValue = 0.60
        controller.speechRateChanged(controller.speechRateSlider)
        XCTAssertEqual(preferences.speechRate, 0.60, accuracy: 0.001)

        controller.mixedPreview(controller.mixedPreviewButton)
        XCTAssertEqual(preview.requests.map(\.languageRole), [.chinese, .english, .chinese])
        XCTAssertEqual(preview.stopCount, 1)

        catalog.refreshCount = 0
        controller.refreshVoices(controller.refreshVoicesButton)
        XCTAssertEqual(catalog.refreshCount, 1)
        controller.manageHighQualityVoices(controller.manageHighQualityVoicesButton)
        XCTAssertEqual(opened, [SpeechSystemSettings.spokenContentURL])
    }
}
