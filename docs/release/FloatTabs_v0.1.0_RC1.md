# FloatTabs v0.1.0 RC1 — Backup, Restore & DMG Release Contract

Status: implementation plan.

Base: `main @ e69e8441d07f26242fc6ef3486b3a474cf48fe37` after accepted Stage 6C + 6D merge.

## 1. Goal

Stop feature expansion and create a usable V1 release candidate that can be installed as a macOS DMG and used for real-world testing over time.

The remaining V1 work in this release candidate is deliberately narrow:

```text
Data continuity
+ installable Release build
+ repeatable DMG packaging
```

No new browser features, shell redesign, lifecycle tuning, or appearance polish are part of RC1.

## 2. Normal upgrade behavior

FloatTabs configuration already lives outside the application bundle:

```text
~/Library/Application Support/FloatTabs/WebAppProfiles.json
UserDefaults for com.lost0rz.FloatTabs
WKWebsiteDataStore.default()
```

Replacing `FloatTabs.app` with a newer build does not normally delete the Application Support file or UserDefaults. Stable bundle identifier is therefore a release invariant:

```text
com.lost0rz.FloatTabs
```

The backup system is an additional safety/migration mechanism for:

- moving to another Mac;
- reinstalling from scratch;
- manual rollback safety;
- protecting per-Slot configuration before risky changes;
- recovering from configuration mistakes.

## 3. Backup format

Use one explicit versioned JSON document with extension:

```text
.floattabsbackup
```

Schema V1 contains:

```text
schemaVersion
createdAt
sourceAppVersion
sourceBuild

webAppState
  ├─ all WebAppProfile records
  └─ lastActiveTabID

globalPreferences
  ├─ appearanceMode
  └─ followPreferredSize

globalShowHideShortcut
```

Because `WebAppProfile` already contains the per-Slot configuration, this preserves:

- Slot order/name;
- Home URL / Current URL;
- Website Mode;
- Window Size / custom viewport;
- Zoom;
- Browser Identity / compatibility settings;
- Residency: Hot / Warm / Cold;
- Background Media policy;
- created/last-used timestamps.

### Explicitly excluded

The backup must **not** claim to include:

- website passwords;
- cookies;
- OAuth tokens/session storage;
- arbitrary WebKit caches;
- exact DOM/JS runtime state;
- downloads or external files.

These remain owned by WebKit or the filesystem. On another Mac, website logins may need to be performed again.

## 4. Restore rules

Restore is a replace operation, not a merge operation.

Flow:

```text
Choose .floattabsbackup
→ validate schema
→ validate/sanitize Web App URLs and profile data
→ user confirms replacement
→ create rollback backup of current FloatTabs configuration
→ release existing live WKWebViews
→ replace TabStore state
→ apply global preferences
→ restore global Show/Hide shortcut
→ synchronize active Slot/UI
```

If an imported `currentURL` is unsafe it is dropped; an unsafe `homeURL` invalidates that profile.

The imported active Slot is restored only if its ID still exists after sanitization; otherwise use the first valid Slot.

A restore must never silently create/restore website credentials.

## 5. Account & Language UI

Keep the existing Settings root. Under the **Account** section add:

```text
Backup & Restore

Export Backup…
Restore Backup…
```

Supporting copy must state that site configurations/settings are included but website login/session data is not.

`Restore Backup…` requires a destructive confirmation before replacing the current configuration.

Do not add fake cloud sync or account sign-in.

## 6. Architecture

Add one persistence service:

```text
FloatTabsBackupService
```

Responsibilities:

- versioned encoding/decoding;
- metadata/version capture;
- backup validation;
- automatic rollback file before restore;
- no AppKit presentation logic.

Data owners remain authoritative:

```text
TabStore
→ Web App state

AppPreferencesStore
→ application preferences

KeyboardShortcuts
→ global Show/Hide binding

GlobalSettingsController
→ save/open panels and user confirmation only
```

`TabStore` gains explicit export/replace APIs rather than allowing Settings code to mutate its arrays directly.

`PanelController` owns runtime teardown/re-synchronization when imported Slot state replaces the live Slot set.

## 7. Local automatic safety backups

Before every successful manual restore, write the current configuration to:

```text
~/Library/Application Support/FloatTabs/Backups/
FloatTabs-before-restore-<timestamp>-<id>.floattabsbackup
```

In addition, on app start and clean termination, update one local configuration snapshot for the current app version/build:

```text
FloatTabs-auto-<version>-<build>.floattabsbackup
```

A newer build uses a different filename, so the previous version's latest snapshot remains available during upgrades. These are local configuration backups only; RC1 does not implement background cloud sync or website credential/session migration.

## 8. Release build

Current project version remains:

```text
MARKETING_VERSION = 0.1.0
CURRENT_PROJECT_VERSION = 1
PRODUCT_BUNDLE_IDENTIFIER = com.lost0rz.FloatTabs
```

RC1 adds a repeatable release script:

```text
tools/release/build_dmg.sh
```

Default mode creates a local/CI **unsigned QA DMG** suitable for installation/testing on the developer Mac.

Expected artifact:

```text
FloatTabs-0.1.0.dmg
├─ FloatTabs.app
└─ Applications -> /Applications
```

The script must:

- build `Release` configuration;
- use the resolved Swift package lock;
- stage the app and Applications symlink;
- create compressed UDZO DMG;
- verify the DMG;
- clearly report whether the app is unsigned QA or Developer ID signed.

## 9. Signing / notarization boundary

Public distribution requires credentials that must not be committed to Git:

- Developer ID Application certificate;
- Apple Developer Team ID;
- notarization credentials / keychain profile.

The script should support these through environment variables when available, but RC1 must not hard-code identities or secrets.

Without those credentials, the generated artifact is a QA DMG for personal testing, not a public notarized release.

## 10. CI / release validation

Permanent macOS CI must add an unsigned Release build in addition to the existing Debug build + Unit Tests.

Add a manual QA-DMG workflow that:

```text
workflow_dispatch
→ Release build
→ build DMG
→ verify DMG
→ upload FloatTabs-0.1.0.dmg artifact
```

No release/tag publication is automatic in RC1.

## 11. Real-Mac acceptance

Before calling RC1 usable:

1. export backup from Account & Language;
2. modify/remove at least one Slot and change a global setting/shortcut;
3. restore backup;
4. confirm all Slot order/settings/current URLs return;
5. confirm global appearance/follow-size/shortcut return;
6. confirm rollback backup file was created;
7. confirm website login cookies are not represented as backed up;
8. build Release DMG;
9. mount DMG;
10. drag FloatTabs.app to Applications;
11. launch installed app;
12. confirm existing Application Support configuration survives replacing the app build;
13. run quick Stage 5/6 regression in the installed Release build.

## 12. Non-goals

Not in RC1:

- cloud account;
- cloud backup/sync;
- website credential/session migration;
- auto-updater;
- launch-at-login;
- app icon redesign;
- accent/theme redesign;
- new Web App features;
- new lifecycle tuning;
- public notarized release without credentials.
