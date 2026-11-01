from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file_path = Path(path)
    text = file_path.read_text()
    if old not in text:
        raise SystemExit(f"expected block not found in {path}")
    updated = text.replace(old, new, 1)
    file_path.write_text(updated)


replace_once(
    "FloatTabsTests/AppCommandControllerTests.swift",
    '''    func testEveryPreviouslyFixedShortcutHasAnIndividualBinding() {\n        XCTAssertEqual(AppShortcutCatalog.slotBindings.count, 9)\n        XCTAssertEqual(AppShortcutCatalog.navigationBindings.count, 7)\n        XCTAssertEqual(AppShortcutCatalog.viewBindings.count, 4)\n        XCTAssertEqual(AppShortcutCatalog.residencyBindings.count, 3)\n        XCTAssertEqual(AppShortcutCatalog.applicationBindings.count, 1)\n        XCTAssertEqual(AppShortcutCatalog.allBindings.count, 24)\n        XCTAssertEqual(Set(AppShortcutCatalog.allNames.map(\\.rawValue)).count, 24)\n    }\n\n    func testResidencyShortcutsSelectHotWarmAndCold() {\n        XCTAssertEqual(\n            defaultCommand(\n                keyCode: UInt16(KeyboardShortcuts.Key.h.rawValue),\n                modifiers: [.control, .option]\n            ),\n            .setResidency(.hot)\n        )\n        XCTAssertEqual(\n            defaultCommand(\n                keyCode: UInt16(KeyboardShortcuts.Key.w.rawValue),\n                modifiers: [.control, .option]\n            ),\n            .setResidency(.warm)\n        )\n        XCTAssertEqual(\n            defaultCommand(\n                keyCode: UInt16(KeyboardShortcuts.Key.c.rawValue),\n                modifiers: [.control, .option]\n            ),\n            .setResidency(.cold)\n        )\n    }\n\n    func testStatusHUDDisplaysSelectedResidencyMode() {\n        let hud = StatusHUDView()\n\n        hud.show(residency: .warm)\n\n        XCTAssertFalse(hud.isHidden)\n        XCTAssertEqual(hud.displayedText, "Mode: Warm")\n    }\n''',
    '''    func testEveryCurrentShortcutHasAnIndividualBinding() {\n        XCTAssertEqual(AppShortcutCatalog.slotBindings.count, 9)\n        XCTAssertEqual(AppShortcutCatalog.navigationBindings.count, 7)\n        XCTAssertEqual(AppShortcutCatalog.viewBindings.count, 4)\n        XCTAssertEqual(AppShortcutCatalog.applicationBindings.count, 1)\n        XCTAssertEqual(AppShortcutCatalog.allBindings.count, 21)\n        XCTAssertEqual(Set(AppShortcutCatalog.allNames.map(\\.rawValue)).count, 21)\n    }\n\n    func testLegacyResidencyKeysAreNotCurrentUserShortcuts() {\n        XCTAssertNil(\n            defaultCommand(\n                keyCode: UInt16(KeyboardShortcuts.Key.h.rawValue),\n                modifiers: [.control, .option]\n            )\n        )\n        XCTAssertNil(\n            defaultCommand(\n                keyCode: UInt16(KeyboardShortcuts.Key.w.rawValue),\n                modifiers: [.control, .option]\n            )\n        )\n        XCTAssertNil(\n            defaultCommand(\n                keyCode: UInt16(KeyboardShortcuts.Key.c.rawValue),\n                modifiers: [.control, .option]\n            )\n        )\n    }\n''',
)

replace_once(
    "FloatTabsTests/WebsiteCacheCleanupTests.swift",
    '''    func testPerformanceSettingsShowsResidencyDefaultsAndStoredChoices() {\n        let preferences = AppPreferencesStore(defaults: defaults)\n        preferences.warmWebViewRetentionDelay = 600\n        preferences.coldWebViewReleaseDelay = 120\n\n        let controller = PerformanceSettingsViewController(preferencesStore: preferences)\n        controller.loadView()\n\n        XCTAssertEqual(controller.displayedWarmRetention, "10 minutes")\n        XCTAssertEqual(controller.displayedColdRelease, "2 minutes")\n    }\n''',
    '''    func testPerformanceSettingsDoesNotProjectLegacyResidencyTimingControls() {\n        let preferences = AppPreferencesStore(defaults: defaults)\n        preferences.warmWebViewRetentionDelay = 600\n        preferences.coldWebViewReleaseDelay = 120\n\n        let controller = PerformanceSettingsViewController(preferencesStore: preferences)\n        controller.loadView()\n\n        XCTAssertEqual(preferences.warmWebViewRetentionDelay, 600)\n        XCTAssertEqual(preferences.coldWebViewReleaseDelay, 120)\n        XCTAssertEqual(controller.displayedWebsiteCacheUsage, "Unavailable")\n    }\n''',
)
