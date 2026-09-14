# Settings Information Architecture Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consolidate FloatTabs Settings into five native macOS Settings pages while preserving every existing preference, callback, runtime authority, persistence key, and backup schema.

**Architecture:** Add a declarative five-page Settings catalog and a scrollable composition controller that embeds the existing settings controllers as child view controllers. Mechanically split the current Account & Language presentation into reusable Browser Profiles, Backup & Restore, and About controllers, while keeping the legacy test initializer as a compatibility wrapper. Embedded versions of the existing scrollable controllers will share the composition page's scroll view so merged pages do not create nested scrolling regions.

**Tech Stack:** Swift, AppKit, NSViewController containment, XCTest, Xcode project file.

**Spec:** `/Users/jack7788/.codex/attachments/7597d7ba-6503-4cd5-bb88-ebb712a0b05a/pasted-text.txt`

## Global Constraints

- The top-level Settings pages are exactly `General`, `Browser & Performance`, `Audio`, `Shortcuts`, and `Advanced`.
- Runtime Diagnostics remains observation/composition-only; do not change its mode, writer, privacy, retention, rotation, export format, namespace, or trace semantics.
- Do not change restore policy, activation options, external-window observation, focus generations, WebAttention, fullscreen, auto-hide, WebView lifecycle, tab selection, speech runtime, notification runtime, Browser Profile rules, backup schema, or persistence keys.
- Remove only the non-functional Language placeholder UI; do not add language selection or localization architecture.
- All existing controls continue to write through their current injected stores/managers and all existing callbacks remain the same.
- PR #81 remains open, Draft, and unmerged; never merge or mark Ready.

---

### Task 1: Lock the Settings information architecture with a failing regression

**Files:**
- Create: `FloatTabsTests/SettingsInformationArchitectureTests.swift`
- Modify: `FloatTabs.xcodeproj/project.pbxproj`

**Interfaces:**
- The test will consume `GlobalSettingsPage.allCases`, `GlobalSettingsPage.title`, and `GlobalSettingsPage.sections`.
- The production catalog will later provide the exact five pages and their section composition.

- [ ] **Step 1: Add the focused test file and assert the desired catalog**

```swift
import XCTest
@testable import FloatTabs

final class SettingsInformationArchitectureTests: XCTestCase {
    func testSettingsUsesFiveConsolidatedTopLevelPages() {
        XCTAssertEqual(
            GlobalSettingsPage.allCases.map(\.title),
            ["General", "Browser & Performance", "Audio", "Shortcuts", "Advanced"]
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
}
```

- [ ] **Step 2: Register the new test source in the existing FloatTabsTests target**

Add one `PBXFileReference`, one `PBXBuildFile`, the file reference under the `FloatTabsTests` group, and the build file under `J00000000000000000000002 /* Sources */`. Use a new unused object-id pair and preserve the project's existing explicit-file layout.

- [ ] **Step 3: Run only the new test and verify the expected RED failure**

Run:

```bash
xcodebuild test -project FloatTabs.xcodeproj -scheme FloatTabs -destination 'platform=macOS,arch=arm64' -only-testing:FloatTabsTests/SettingsInformationArchitectureTests -derivedDataPath /private/tmp/FloatTabsSettingsIARed
```

Expected: compilation/test failure because `GlobalSettingsPage` is not yet defined. Fix only test registration or syntax errors if needed; do not add production implementation before observing this missing-catalog failure.

### Task 2: Add the declarative catalog and composition host

**Files:**
- Create: `FloatTabs/UI/SettingsInformationArchitecture.swift`
- Modify: `FloatTabs/UI/GlobalSettingsController.swift`
- Modify: `FloatTabs.xcodeproj/project.pbxproj`

**Interfaces:**
- `GlobalSettingsPage: CaseIterable, Equatable` exposes `general`, `browserPerformance`, `audio`, `shortcuts`, and `advanced`, plus `title`, `symbol`, and `sections`.
- `GlobalSettingsSection: Equatable` exposes `.interfaceAppearance`, `.browserProfiles`, `.performance`, `.readyAlerts`, `.speech`, `.shortcuts`, `.runtimeDiagnostics`, `.backupRestore`, and `.about`; it deliberately has no `.language` case.
- `SettingsPageViewController.init(childViewControllers:)` owns only AppKit containment/layout and never owns feature state.

- [ ] **Step 1: Implement the catalog and host with no feature behavior**

The host must create one flipped `NSView` document inside one vertical `NSScrollView`, add each supplied controller using `addChild`, constrain each child to the document width, and keep the common page margin at 28 points. It must not copy or cache any preference state.

- [ ] **Step 2: Register the new UI source in the app target**

Add the new file to the UI group and the app sources build phase in `FloatTabs.xcodeproj/project.pbxproj`.

- [ ] **Step 3: Replace the seven `addTab` calls with the five catalog-driven pages**

`GlobalSettingsController.makeWindow()` will iterate `GlobalSettingsPage.allCases` and call a private page factory:

```swift
case .general:
    [AppearanceSettingsViewController(preferencesStore: preferencesStore)]
case .browserPerformance:
    [BrowserProfilesSettingsViewController(browserProfileManager: browserProfileManager, embedsInSettingsPage: true),
     PerformanceSettingsViewController(preferencesStore: preferencesStore, websiteCacheManager: websiteCacheManager, embedsInSettingsPage: true)]
case .audio:
    [NotificationsSettingsViewController(preferencesStore: preferencesStore, attentionSoundPlayer: attentionSoundPlayer, assetStore: attentionSoundAssetStore),
     SpeechSettingsViewController(preferencesStore: speechPreferencesStore, voiceCatalog: speechVoiceCatalog, previewHandler: speechPreviewHandler)]
case .shortcuts:
    [ShortcutsSettingsViewController(embedsInSettingsPage: true)]
case .advanced:
    [RuntimeDiagnosticsSettingsViewController(preferencesStore: preferencesStore, exportHandler: onExportDiagnostics, openLogsHandler: onOpenDiagnosticsLogs),
     BackupRestoreSettingsViewController(onExportBackup: onExportBackup, onRestoreBackup: onRestoreBackup),
     AboutSettingsViewController()]
```

The only changed top-level presentation data is the page label/icon and composition. Existing child controllers remain the sole owners of their stores and actions.

- [ ] **Step 4: Run the focused Settings IA tests and verify GREEN**

Run the command from Task 1. Expected: all catalog tests pass.

### Task 3: Make existing scrollable controllers embeddable without nested scrolling

**Files:**
- Modify: `FloatTabs/UI/GlobalSettingsController.swift`

**Interfaces:**
- `ShortcutsSettingsViewController.init(embedsInSettingsPage: Bool = false)` preserves the old standalone scroll behavior by default.
- `PerformanceSettingsViewController.init(..., embedsInSettingsPage: Bool = false)` preserves the old standalone scroll behavior by default.
- `BrowserProfilesSettingsViewController.init(browserProfileManager:..., embedsInSettingsPage: Bool = false)` uses the composition page scroll view when embedded.

- [ ] **Step 1: Add the embedding flags and write layout assertions to the IA test**

Instantiate the three controllers in standalone and embedded modes, call `loadView()`, and assert both modes load a view. Assert the embedded view contains no nested `NSScrollView` at its root; do not assert implementation-only subview counts.

- [ ] **Step 2: Run the focused layout test and verify it fails for the missing initializers/behavior**

Run the focused Settings IA test target and confirm the failure names the new initializer or embedded-mode contract rather than a test typo.

- [ ] **Step 3: Refactor only the scroll shell**

Build each controller's existing stack/document first. In standalone mode wrap it in its current scroll shell. In embedded mode expose the document as the controller view, preserving all existing controls, actions, refresh calls, async measurement, shortcut identities, and manager/store references. Add bottom constraints where a direct child previously relied on the window frame.

- [ ] **Step 4: Run the focused IA, Performance/WebsiteCache, Browser Profile, and Speech/Attention tests**

Expected: all pass with no preference or callback assertion changes.

### Task 4: Mechanically split Account & Language presentation into Profiles, Backup, and About

**Files:**
- Modify: `FloatTabs/UI/GlobalSettingsController.swift`
- Modify: `FloatTabs/UI/SettingsInformationArchitecture.swift`

**Interfaces:**
- `BrowserProfilesSettingsViewController` owns the existing snapshot-driven Profile rows and manager handoffs.
- `BackupRestoreSettingsViewController` owns the existing export/restore panels and callback types.
- `AboutSettingsViewController` owns version/build and `AppReleaseInfo.latestFixes` presentation.
- `AccountLanguageSettingsViewController` remains as a compatibility subclass of `BrowserProfilesSettingsViewController` for existing focused tests; its initializer accepts the old backup closures but does not render or own them.

- [ ] **Step 1: Extend the failing IA tests for the preserved public seams**

Load the Profile controller with an injected snapshot and assert default/custom names still appear. Assert the Backup controller exposes both existing action buttons and the About controller displays `AppReleaseInfo.currentVersionDisplay` plus every latest-fix entry. Keep callback tests on the same injected closures.

- [ ] **Step 2: Run the new tests and verify RED for the new split controllers**

Expected: missing-type or missing-control failures only.

- [ ] **Step 3: Move the existing Profile UI and logic mechanically**

Rename the existing implementation to `BrowserProfilesSettingsViewController`, remove the Account, Backup & Restore, Language, and About arranged views, preserve the profile snapshot/test seams and all manager calls, and add the embedded scroll shell from Task 3. Add the compatibility subclass with the old test initializer.

- [ ] **Step 4: Add BackupRestoreSettingsViewController by transferring the existing panels verbatim**

Keep the same content type, filename suggestion, export callback, restore callback, warning text, rollback message, and error presentation. Do not alter `FloatTabsBackupService` or any backup schema.

- [ ] **Step 5: Add AboutSettingsViewController with compact read-only presentation**

Show the existing version/build string and latest fixes without adding settings or persistence. Do not change `AppReleaseInfo` data or version resolution.

- [ ] **Step 6: Run focused Profile, Backup, Speech, AttentionSound, RuntimeDiagnostics, and IA tests**

Expected: GREEN, with the Profile/Backup/Speech/Diagnostics tests continuing to exercise the same production authorities.

### Task 5: Normalize presentation copy and update the mechanical Settings reference

**Files:**
- Modify: `FloatTabs/UI/GlobalSettingsController.swift`
- Modify: `FloatTabs/UI/ExternalTabRail.swift`
- Modify: `README.md`

- [ ] **Step 1: Update only stale presentation labels**

Use `Ready Alerts` as the Notifications section heading, keep Speech under the Audio page, remove the non-functional Language section entirely, and change the one user-facing `Settings → Appearance` reference to `Settings → General`. Preserve explanatory text that carries security or data semantics, especially backup exclusions and cache-safety wording.

- [ ] **Step 2: Run `rg` audits for obsolete top-level and forbidden-scope changes**

Confirm old labels no longer occur as top-level tab definitions, and confirm the diff contains no references to restore, activation options, CGWindow observation, WebAttention, fullscreen, auto-hide, diagnostics core, or backup service implementation changes beyond unchanged context.

### Task 6: Full verification and manual acceptance preparation

**Files:**
- No additional production files; inspect all changed files and generated test/build artifacts outside the repository.

- [ ] **Step 1: Run all requested focused test groups**

Run Settings IA, RuntimeDiagnostics, Browser Profile/settings/backup, Speech, AttentionSound, Performance/WebsiteCache, AppPreferences, and relevant ExternalShell tests using the arm64 macOS destination.

- [ ] **Step 2: Run the complete arm64 XCTest suite**

Use an isolated derived-data path under `/private/tmp` and record the exact command/result.

- [ ] **Step 3: Build Debug and Release for arm64**

Use isolated derived-data paths, record both build results, and do not modify source signing or release networking behavior.

- [ ] **Step 4: Run static audits**

Run `git diff --check`, inspect `git diff --stat`, compare changed symbols against the frozen forbidden scope, verify no persistence-key or backup-schema edits, and run the privacy audit plus MainActor I/O audit appropriate to the repository.

- [ ] **Step 5: Perform manual Settings acceptance if the built app can be launched**

Open Settings and check the five labels, minimum width, scrolling, controls, export sheet, backup/restore sheet, Profile create/rename/delete affordances, and compact Advanced/About layout. Record `PASS`, `FAIL`, or `REQUIRED` with the limitation if GUI interaction is unavailable.

### Task 7: Commit and remote handoff without merge

**Files:**
- All files changed by Tasks 1–5.

- [ ] **Step 1: Review the final diff and status**

Confirm only the planned Settings IA, tests, project registration, plan document, and presentation-copy changes are present.

- [ ] **Step 2: Create one new commit**

Use a message such as `feat: consolidate settings information architecture`.

- [ ] **Step 3: Push the branch to origin**

Push `codex/runtime-diagnostics-v1` without force. Verify the new remote SHA matches the new local HEAD.

- [ ] **Step 4: Verify PR state**

Confirm PR #81 remains OPEN, Draft, and unmerged; do not merge or mark Ready.

- [ ] **Step 5: Report exact source/remote SHAs, moved sections, test/build results, audits, and manual acceptance**

Use the requested `PR81 SETTINGS IA CORRECTIVE` report format and state `BUSINESS_BEHAVIOR_CHANGED: NO`, `PREFERENCE_SEMANTICS_CHANGED: NO`, `PERSISTENCE_KEYS_CHANGED: NO`, `BACKUP_SCHEMA_CHANGED: NO`, `DIAGNOSTICS_CORE_CHANGED: NO`, `RESTORE_LOGIC_CHANGED: NO`, and `WINDOW_ACTIVATION_CHANGED: NO` only after the diff and verification support each claim.
