# FloatTabs v0.5.14

Release date: 2026-11-25

Build: **32**

## Summary

FloatTabs v0.5.14 is a consolidation and capability release targeting **macOS 14.0+**. It strengthens panel resizing ergonomics, adds Tab Groups with border styling, delivers persistent Bookmarks with Chrome/Safari HTML import/export and a dedicated `Bookmarks.json` sidecar store, introduces bilingual UI localization (`English` / `简体中文`), generalizes AI & background site activity + `window.Notification` bridging, upgrades SVG favicon decoding to native-first vector normalization, and completes backup/entitlement coverage.

## Key Changes

### macOS 14.0 Baseline & Media Capture Entitlements

- Raised `MACOSX_DEPLOYMENT_TARGET` to `14.0` across project configurations and removed legacy macOS 13 Browser Profile compatibility fallbacks (`UnsupportedBrowserProfileView`).
- Added `FloatTabs/FloatTabs.entitlements` granting Hardened Runtime `com.apple.security.device.audio-input` and `com.apple.security.device.camera` alongside existing `Info.plist` TCC usage descriptions, wired into both Xcode builds and `tools/release/build_dmg.sh`.
- Switched deprecated `activateIgnoringOtherApps` activation calls to macOS 14 `NSApp.activate()`.

### Tab Groups & Differentiated Styling

- Added workspace Tab Groups (`Default` + custom named groups) with group-level border theme overrides and quick switching / unread badges on the rail.
- Clicking a completion notification or menubar item automatically routes to the owning group and exact Slot.
- Preserves an unread indicator when more than four groups exist and an off-rail group has unread activity.

### Bookmarks (`Bookmarks.json` Sidecar Store & HTML Import/Export)

- Split bookmarks and bookmark folders into an independent `Bookmarks.json` file alongside `WebAppProfiles.json` with automatic legacy inline migration and corruption recovery protection (`Bookmarks-recovery-*` archive preservation + startup recovery prompt).
- Added debounced runtime persistence (`0.35s` in production) for high-frequency tab selection / current URL updates, with explicit flush before snapshots and app termination.
- Implemented Netscape Bookmark HTML (`NETSCAPE-Bookmark-file-1`) import and export (`BookmarkHTMLCodec`) compatible with Google Chrome and Apple Safari, plus a cascading hover menu picker in Add Web App.
- Enforced retention of at least one Browser Profile (allowing Default Profile deletion only when at least one custom Profile exists) and cleared dangling bookmark Profile references upon Profile deletion.

### Universal Web Activity, W3C Notification Bridge & Localization

- Added `UniversalWebActivityBridge` covering non-ChatGPT web apps with:
  - Main-world `window.Notification` / `ServiceWorkerRegistration.showNotification` interception into FloatTabs unread indicators and native notification routing;
  - Isolated-world AI streaming detection (Gemini, DeepSeek, Claude, Perplexity, Grok, Kimi, Qwen, etc.) and background title-badge / GitHub notification monitoring, synchronized across `DOMContentLoaded`, `didCommit`, and Instant Back resync;
  - Anti-spam sound suppression for consecutive passive badge increments while already unread, plus notification withdrawal when unread is acknowledged or cleared.
- Expanded localized semantic stop/action labels in `ChatGPTResponseExtraction`.
- Added bilingual runtime localization (`AppLocalization`, `L10n`, System / English / Simplified Chinese selector in Global Settings) and clickable empty-state "Add Web App" card.

### Session-Aware Favicons & Native SVG Vector Pipeline

- Normalized SVG favicon payloads in `WebsiteFaviconProvider.normalizedSVGDataForNativeDecode(_:)` (missing `xmlns`, `viewBox`-derived width/height, unbound `currentColor`) for in-process `NSImage` decoding first.
- Replaced per-call `WKWebView` spawning in `FaviconSVGRasterizer` with a serialized shared instance awaiting `img.decode()` / animation frames (`contentWorld: .defaultClient`) and releasing cleanly after 15 seconds idle.

### Settings, External Automation & Complete Backup

- Removed obsolete `WarmWebViewRetentionOption` / `ColdWebViewReleaseOption` settings and added an "Allow external control commands (e.g. RemoteOrbit)" toggle in Shortcuts & External Control settings (`AppPreferencesStore.externalCommandsEnabled`).
- Extended `.floattabsbackup` schema (`FloatTabsBackupService` & `AppCoordinator`) to round-trip all named shortcuts (`appShortcuts`), `websiteCachePolicy`, and `externalCommandsEnabled` while retaining backwards compatibility with v1/earlier v2 backups.

## Data Safety

v0.5.14 preserves existing user data in `~/Library/Application Support/FloatTabs`:

- Browser Profiles, website cookies/sessions, and Slot configurations remain intact across upgrades.
- Unreadable `WebAppProfiles.json` or `Bookmarks.json` files are archived verbatim before recovery replacement is allowed and never silently overwritten by an empty fallback or automatic backup snapshot.

## Validation

Verified prior to tagging `v0.5.14` (Build `32`):

- CI contract suite (`python3 -m unittest discover -s tools/ci/tests -v`)
- Benchmark harness self-tests (`floattabs_benchmark.py --self-test`, `floattabs_phase7_acceptance.py --self-test`)
- Full `FloatTabsTests` XCTest suite (`xcodebuild test -destination 'platform=macOS,arch=arm64'`)
- Release Apple Silicon DMG build & code signature / entitlements verification (`./tools/release/build_dmg.sh`)
