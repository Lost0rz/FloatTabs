import AppKit
import XCTest
@testable import FloatTabs

@MainActor
final class SettingsInformationArchitectureTests: XCTestCase {
    func testSettingsUsesFiveConsolidatedTopLevelPages() {
        XCTAssertEqual(
            GlobalSettingsPage.allCases.map(\.title),
            ["General", "Browser", "Audio", "Shortcuts", "Advanced"]
        )
        XCTAssertFalse(
            GlobalSettingsPage.allCases.map(\.title).contains {
                ["Appearance", "Performance", "Notifications", "Speech", "Diagnostics", "Account & Language"].contains($0)
            }
        )
    }

    func testSettingsPagesRetainAllExistingFeatureSections() {
        XCTAssertEqual(
            GlobalSettingsPage.general.sections,
            [.interfaceAppearance, .unreadTabAttention]
        )
        XCTAssertEqual(
            GlobalSettingsPage.browserPerformance.sections,
            [.browserProfiles, .performance]
        )
        XCTAssertEqual(
            GlobalSettingsPage.audio.sections,
            [.readyAlerts, .speech]
        )
        XCTAssertEqual(GlobalSettingsPage.shortcuts.sections, [.shortcuts])
        XCTAssertEqual(
            GlobalSettingsPage.advanced.sections,
            [.runtimeDiagnostics, .backupRestore, .about]
        )
    }

    func testNotificationsControllerExposesReadyAudioControlsOnly() {
        let controller = NotificationsSettingsViewController(
            preferencesStore: AppPreferencesStore(),
            attentionSoundPlayer: SilentAttentionSoundPlayer(),
            availableSoundNames: ["Ping"]
        )
        controller.loadViewIfNeeded()

        let strings = allControlStrings(in: controller.view)
        XCTAssertTrue(strings.contains("Ready Alerts"))
        XCTAssertTrue(strings.contains("Play sound when ChatGPT is ready"))
        XCTAssertTrue(strings.contains("Ready Sound"))
        XCTAssertTrue(strings.contains("Volume"))
        XCTAssertTrue(strings.contains("Play Preview"))
        XCTAssertFalse(strings.contains("Unread Tab Attention"))
        XCTAssertFalse(strings.contains("Palette"))
        XCTAssertFalse(strings.contains("Dot"))
    }

    func testGeneralAndAudioComposeOneDedicatedAttentionController() throws {
        let settings = GlobalSettingsController(preferencesStore: AppPreferencesStore())
        let general = try XCTUnwrap(
            settings.makeSettingsPage(for: .general) as? SettingsPageViewController
        )
        let audio = try XCTUnwrap(
            settings.makeSettingsPage(for: .audio) as? SettingsPageViewController
        )

        XCTAssertEqual(
            general.embeddedControllers.map { String(describing: type(of: $0)) },
            ["AppearanceSettingsViewController", "UnreadTabAttentionSettingsViewController"]
        )
        XCTAssertEqual(
            audio.embeddedControllers.map { String(describing: type(of: $0)) },
            ["NotificationsSettingsViewController", "SpeechSettingsViewController"]
        )
        XCTAssertEqual(
            general.embeddedControllers.filter { $0 is UnreadTabAttentionSettingsViewController }.count,
            1
        )
        XCTAssertFalse(audio.embeddedControllers.contains { $0 is UnreadTabAttentionSettingsViewController })
    }

    func testLanguagePlaceholderIsNotASettingsSection() {
        let sectionNames = GlobalSettingsPage.allCases
            .flatMap(\.sections)
            .map(\.rawValue)
        XCTAssertFalse(sectionNames.contains("language"))
    }

    func testMergedPageUsesOneOuterScrollViewForScrollableSections() {
        let profileController = BrowserProfilesSettingsViewController(
            browserProfileManager: .unavailable,
            embedsInSettingsPage: true
        )
        let performanceController = PerformanceSettingsViewController(
            preferencesStore: AppPreferencesStore(),
            embedsInSettingsPage: true
        )
        let shortcutsController = ShortcutsSettingsViewController(embedsInSettingsPage: true)

        for controller in [profileController, performanceController, shortcutsController] {
            controller.loadView()
            XCTAssertFalse(controller.view.subviews.contains(where: { $0 is NSScrollView }))
        }
    }

    func testSettingsPageLoadsEmbeddedViewsWithValidConstraintHierarchy() {
        let page = SettingsPageViewController(childViewControllers: [
            StubSettingsChildViewController(),
            StubSettingsChildViewController(),
        ])

        page.loadView()

        XCTAssertTrue(page.view.subviews.contains(where: { $0 is NSScrollView }))
    }

    func testSplitSettingsControllersKeepTheirExistingPresentationSeams() {
        let profile = BrowserProfile(
            id: UUID(),
            name: "Company",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let profileController = BrowserProfilesSettingsViewController(
            browserProfileManager: BrowserProfileManagementClient(
                snapshot: {
                    BrowserProfileManagementSnapshot(
                        customProfiles: [profile],
                        referencedProfileIDs: [],
                        customProfilesSupported: true
                    )
                },
                create: { _ in profile },
                rename: { _, _ in },
                delete: { _ in }
            )
        )
        profileController.loadView()
        XCTAssertEqual(profileController.displayedBrowserProfileNames, ["Default", "Company"])

        let backupController = BackupRestoreSettingsViewController(
            onExportBackup: { _ in },
            onRestoreBackup: { _ in URL(fileURLWithPath: "/tmp/rollback.json") }
        )
        backupController.loadView()
        XCTAssertTrue(backupController.exportButton.target === backupController)
        XCTAssertTrue(backupController.restoreButton.target === backupController)

        let aboutController = AboutSettingsViewController()
        aboutController.loadView()
        XCTAssertEqual(aboutController.displayedVersion, AppReleaseInfo.currentVersionDisplay)
        XCTAssertEqual(aboutController.displayedLatestFixes, "")
    }

    func testVersionDisplayOmitsBuildNumber() {
        XCTAssertEqual(
            AppReleaseInfo.displayVersion(shortVersion: "0.4.0", build: "17"),
            "Version 0.4.0"
        )
    }
}

@MainActor
private struct SilentAttentionSoundPlayer: AttentionSoundPlaying {
    func play(source: AttentionSoundPlaybackSource, volume: Double) {}
}

@MainActor
private func allControlStrings(in view: NSView) -> [String] {
    let current: [String] = switch view {
    case let field as NSTextField:
        [field.stringValue]
    case let button as NSButton:
        [button.title]
    case let popup as NSPopUpButton:
        [popup.titleOfSelectedItem ?? ""]
    default:
        []
    }
    return current + view.subviews.flatMap(allControlStrings)
}

@MainActor
private final class StubSettingsChildViewController: NSViewController {
    override func loadView() {
        view = NSView()
    }
}
