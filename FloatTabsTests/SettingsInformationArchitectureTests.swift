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

    func testRuntimeDiagnosticsSettingsProjectsHistoryModeAndPersistsObservationOptIn() throws {
        let suiteName = "FloatTabsTests.RuntimeDiagnosticsSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.runtimeDiagnosticsMode = .verbose
        let controller = RuntimeDiagnosticsSettingsViewController(
            preferencesStore: preferences,
            exportHandler: { _, completion in completion(.failure(.writerDisabled)) },
            openLogsHandler: {}
        )
        controller.loadView()
        let descendants = descendantViews(of: controller.view)

        let history = try XCTUnwrap(
            descendants.compactMap { $0 as? NSButton }.first {
                $0.title == "Keep local diagnostic history"
            }
        )
        let detailLevel = try XCTUnwrap(
            descendants.compactMap { $0 as? NSPopUpButton }.first {
                $0.itemTitles.contains("Standard") && $0.itemTitles.contains("Verbose")
            }
        )
        let observation = try XCTUnwrap(
            descendants.compactMap { $0 as? NSButton }.first {
                $0.title == "Long-term performance observation"
            }
        )

        XCTAssertEqual(history.state, .on)
        XCTAssertEqual(detailLevel.titleOfSelectedItem, "Verbose")
        XCTAssertEqual(observation.state, .off)

        history.state = .off
        _ = NSApp.sendAction(try XCTUnwrap(history.action), to: history.target, from: history)
        XCTAssertEqual(preferences.runtimeDiagnosticsMode, .off)

        history.state = .on
        _ = NSApp.sendAction(try XCTUnwrap(history.action), to: history.target, from: history)
        XCTAssertEqual(preferences.runtimeDiagnosticsMode, .standard)

        detailLevel.selectItem(withTitle: "Verbose")
        _ = NSApp.sendAction(try XCTUnwrap(detailLevel.action), to: detailLevel.target, from: detailLevel)
        XCTAssertEqual(preferences.runtimeDiagnosticsMode, .verbose)

        observation.state = .on
        _ = NSApp.sendAction(try XCTUnwrap(observation.action), to: observation.target, from: observation)
        XCTAssertTrue(defaults.bool(forKey: "FloatTabs.longTermPerformanceObservation.enabled"))
        XCTAssertNil(defaults.object(forKey: "FloatTabs.runtimeDiagnostics.retainHistory"))

        let labels = descendants.compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertTrue(labels.contains { $0.localizedCaseInsensitiveContains("local")
            && $0.localizedCaseInsensitiveContains("sanitized")
            && $0.localizedCaseInsensitiveContains("seven days") })
        XCTAssertTrue(labels.contains { $0.localizedCaseInsensitiveContains("low-frequency")
            && $0.localizedCaseInsensitiveContains("content-free") })
    }

    func testObservationControlPausesWhenLocalHistoryIsOffWithoutClearingOptIn() throws {
        let suiteName = "FloatTabsTests.RuntimeDiagnosticsSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "FloatTabs.longTermPerformanceObservation.enabled")
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.runtimeDiagnosticsMode = .off
        let controller = RuntimeDiagnosticsSettingsViewController(preferencesStore: preferences)
        controller.loadView()
        let descendants = descendantViews(of: controller.view)

        let observation = try XCTUnwrap(
            descendants.compactMap { $0 as? NSButton }.first {
                $0.title == "Long-term performance observation"
            }
        )
        let detailLevel = try XCTUnwrap(
            descendants.compactMap { $0 as? NSPopUpButton }.first {
                $0.itemTitles.contains("Standard") && $0.itemTitles.contains("Verbose")
            }
        )

        XCTAssertFalse(observation.isEnabled)
        XCTAssertEqual(observation.state, .on)
        XCTAssertFalse(detailLevel.isEnabled)
        XCTAssertTrue(controller.exportButton.isEnabled)
        XCTAssertTrue(controller.openLogsButton.isEnabled)
        XCTAssertTrue(defaults.bool(forKey: "FloatTabs.longTermPerformanceObservation.enabled"))
    }

    func testVersionDisplayOmitsBuildNumber() {
        XCTAssertEqual(
            AppReleaseInfo.displayVersion(shortVersion: "0.4.0", build: "17"),
            "Version 0.4.0"
        )
    }

    private func descendantViews(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendantViews(of:))
    }
}

@MainActor
private final class StubSettingsChildViewController: NSViewController {
    override func loadView() {
        view = NSView()
    }
}
