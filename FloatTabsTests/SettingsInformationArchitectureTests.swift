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

    func testUnreadAttentionStyleGridIsResponsiveThreeColumnLayoutAndKeepsPaletteLayout() throws {
        let suiteName = "FloatTabsTests.AttentionStyleGridLayout.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.attentionStyle = .dot
        let controller = UnreadTabAttentionSettingsViewController(
            preferencesStore: preferences
        )
        controller.loadViewIfNeeded()

        let wide = try styleGridRows(controller, contentWidth: 640)
        let narrow = try styleGridRows(controller, contentWidth: 500)

        for layout in [wide, narrow] {
            XCTAssertEqual(layout.rows.map { $0.map(\.style.displayName) }, [
                ["Dot", "Beacon", "Halo"],
                ["Orbit", "Pulse", "Sweep"],
            ])
            XCTAssertEqual(layout.rows.flatMap { $0 }.count, 6)
            let choices = layout.rows.flatMap { $0 }
            XCTAssertTrue(choices.allSatisfy { (82...84).contains(Int($0.frame.height.rounded())) })
            for row in layout.rows {
                let widths = row.map(\.frame.width)
                XCTAssertLessThanOrEqual((widths.max() ?? 0) - (widths.min() ?? 0), 1.01)
            }
            let cardWidths = choices.map(\.frame.width)
            XCTAssertLessThanOrEqual((cardWidths.max() ?? 0) - (cardWidths.min() ?? 0), 1.01)

            for row in layout.rows {
                for pair in zip(row, row.dropFirst()) {
                    XCTAssertEqual(pair.1.frame.minX - pair.0.frame.maxX, 10, accuracy: 0.5)
                }
                for choice in row {
                    XCTAssertGreaterThan(choice.previewSurfaceView.frame.width, 90)
                    XCTAssertEqual(choice.previewSurfaceView.frame.height, 38, accuracy: 0.01)
                    let selectedCheck = try XCTUnwrap(
                        allDescendants(of: choice).compactMap { $0 as? NSImageView }.first {
                            $0.image?.accessibilityDescription == "Selected"
                        }
                    )
                    if choice.style == .dot {
                        XCTAssertTrue(choice.isSelectedStyle)
                        XCTAssertFalse(selectedCheck.isHidden)
                    }
                }
            }
        }

        XCTAssertEqual(wide.rowWidth, 640 - 56, accuracy: 1)
        XCTAssertEqual(narrow.rowWidth, 500 - 56, accuracy: 1)
        XCTAssertGreaterThan(wide.cardWidth, narrow.cardWidth)

        let paletteRows = groupedRows(controller.attentionPaletteChoices)
        XCTAssertEqual(paletteRows.map(\.count), [3, 3])
        XCTAssertEqual(
            Set(controller.attentionPaletteChoices.map { $0.frame.width }),
            [104]
        )
        for row in paletteRows {
            for pair in zip(row, row.dropFirst()) {
                XCTAssertEqual(pair.1.frame.minX - pair.0.frame.maxX, 8, accuracy: 0.5)
            }
        }
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
private struct AttentionStyleGridLayout {
    let rows: [[AttentionStyleChoiceButton]]
    let rowWidth: CGFloat
    let cardWidth: CGFloat
}

@MainActor
private func styleGridRows(
    _ controller: UnreadTabAttentionSettingsViewController,
    contentWidth: CGFloat
) throws -> AttentionStyleGridLayout {
    controller.view.setFrameSize(NSSize(width: contentWidth, height: 700))
    layoutRecursively(controller.view)
    let rows = groupedRows(controller.attentionStyleChoices)
    let firstChoice = try XCTUnwrap(controller.attentionStyleChoices.first)
    let row = try XCTUnwrap(firstChoice.superview)
    return AttentionStyleGridLayout(
        rows: rows,
        rowWidth: row.frame.width,
        cardWidth: firstChoice.frame.width
    )
}

@MainActor
private func groupedRows<T: NSView>(_ views: [T]) -> [[T]] {
    var rows: [[T]] = []
    for view in views {
        if rows.last?.first?.superview === view.superview {
            rows[rows.count - 1].append(view)
        } else {
            rows.append([view])
        }
    }
    return rows
}

@MainActor
private func layoutRecursively(_ view: NSView) {
    view.needsLayout = true
    view.layoutSubtreeIfNeeded()
    view.subviews.forEach(layoutRecursively)
}

@MainActor
private func allDescendants(of view: NSView) -> [NSView] {
    view.subviews + view.subviews.flatMap(allDescendants)
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
