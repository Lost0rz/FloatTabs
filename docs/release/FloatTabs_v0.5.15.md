# FloatTabs v0.5.15

Release date: 2026-11-25

Build: **33**

## Summary

FloatTabs v0.5.15 fixes Browser Profile renaming when deletion is disabled, refines local code-signing ergonomics for WebCrypto Keychain continuity across local builds, and removes obsolete compatibility shims and dead CI catalog globs.

## Key Changes

### Browser Profile Rename & Input Polish

- Fixed `ProfileDeleteTooltipView.hitTest(_:)` in `GlobalSettingsController.swift` to convert hit-test coordinates from `superview` into local `bounds` before testing bounds containment, preventing the disabled `Delete…` tooltip wrapper from intercepting clicks on the adjacent `Rename…` button.
- Focused the name input field automatically (`initialFirstResponder`) and flushed active IME text composition (`endEditing(for: nil)`) on confirm for Browser Profile create and rename sheets.
- Added layout and AppKit hit-testing regression coverage in `BrowserProfileSettingsTests.testDisabledDeleteTooltipWrapperDoesNotStealRenameButtonHitTesting`.

### Release & Code Cleanup

- Added optional local-only auto-detection in `tools/release/build_dmg.sh` for a user-created `"FloatTabs Local Signing"` self-signed code-signing identity (`--timestamp=none`) when `FLOATTABS_SIGN_IDENTITY` is unset outside CI, preserving WebCrypto Keychain authorization across local rebuilds while keeping Developer ID and CI ad-hoc signing unchanged.
- Removed obsolete `PerformanceSettingsViewController.refreshPerformanceSettings()`, `AccountLanguageSettingsViewController`, `ExternalTabVisualPalette`, and `RuntimeDiagnosticNoopWriter`, plus dead path globs in `.github/ci-capabilities.json`.

## Validation

Verified prior to tagging `v0.5.15` (Build `33`):

- CI contract suite (`python3 -m unittest discover -s tools/ci/tests -v`) and `ci-router.py check-catalog`
- Focused `FloatTabsTests` regression suites (`BrowserProfileSettingsTests`, `SettingsInformationArchitectureTests`, `ExternalShellTests`, `RuntimeDiagnosticsRotationTests`)
- Release Apple Silicon DMG build and code signature verification (`./tools/release/build_dmg.sh`)
