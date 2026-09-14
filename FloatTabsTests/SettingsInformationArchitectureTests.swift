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
        XCTAssertEqual(GlobalSettingsPage.general.sections, [.interfaceAppearance])
        XCTAssertEqual(
            GlobalSettingsPage.browserPerformance.sections,
            [.browserProfiles, .performance]
        )
        XCTAssertEqual(GlobalSettingsPage.audio.sections, [.readyAlerts, .speech])
        XCTAssertEqual(GlobalSettingsPage.shortcuts.sections, [.shortcuts])
        XCTAssertEqual(
            GlobalSettingsPage.advanced.sections,
            [.runtimeDiagnostics, .backupRestore, .about]
        )
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
private final class StubSettingsChildViewController: NSViewController {
    override func loadView() {
        view = NSView()
    }
}
