# FloatTabs v0.5.4

Release date: 2026-10-18

Build: **22**

## Summary

FloatTabs v0.5.4 publishes the accepted current main baseline after reintegrating the long-term local diagnostics/history capability that was intentionally absent from v0.5.3. Existing unread-attention, shell, speech, runtime-residency and Browser Profile/session behavior from v0.5.3 remains preserved.

## Long-term Runtime Diagnostics

* Adds **Keep local diagnostic history** under Advanced → Runtime Diagnostics.
* Adds Standard / Verbose **Detail level** selection.
* Adds opt-in **Long-term performance observation** with low-frequency, content-free checkpoints for the selected Slot, approximately once per minute.
* Adds **Open Saved Logs Folder** for direct access to retained local JSONL history.
* Keeps **Export Recent Diagnostics…** for bounded manual export.
* Reuses the existing canonical sanitized diagnostics pipeline, bounded rotation and up-to-seven-day retention intent.
* Long-term observation reads only an already resident selected-Slot runtime; it does not materialize a WebView solely for observation.
* Adds diagnostics-only runtime/WebView/navigation identity evidence and a manual-reload diagnostic boundary without changing focus, navigation, recovery or runtime ownership.

## Privacy and Data Safety

* Long-term diagnostics remain local and sanitized; no remote telemetry, automatic upload or automatic AI analysis is introduced.
* Periodic ChatGPT observation stores aggregate/content-free health evidence rather than prompt or response text.
* No Browser Profile, Web App Slot, website login/session/cookie, WebKit store, backup, recovery-data or existing diagnostic-history reset/migration is part of this release.

## Preserved v0.5.3 Behavior

* Dot / Beacon / Halo / Orbit / Pulse / Sweep unread-attention styles and separate palettes remain unchanged.
* General continues to own Interface Appearance and Unread Tab Attention; Audio remains Ready Alerts + Speech.
* Browser Profile color remains removed from normal Tab presentation while compatibility metadata is retained.
* Existing shell movement, focus/navigation/window/runtime ownership, speech behavior and runtime residency fixes remain preserved.

## Validation

* Diagnostics reintegration semantic implementation: `c12e18650f2fb96412f7bd208814a4dccfbfbcc2`.
* Product merge baseline: `3db8718582e0b10510010b5c4c14044b9834a3d9`; lifecycle-closeout main before release preparation: `66de8f18c55d46cf882723c05f0afea8249d9e1b`.
* Focused XCTest: **288 passed / 0 failed**.
* Full XCTest: **1,339 passed / 0 failed / 0 skipped**.
* Debug and Release arm64 builds: PASS.
* Final diagnostics PR hosted macOS CI and QA DMG: PASS.
* Human Real-Mac acceptance: PASS on 2026-10-18.
* The v0.5.4 release PR and publisher pipeline are required to re-verify the literal release metadata/package identity before publication.

## Release Integrity

* Distribution remains **Apple Silicon arm64-only**.
* The release pipeline verifies Release architecture, DMG integrity, dSYM archive, code signature and SHA-256 checksum sidecars.
* Developer ID signing/notarization is used when configured release credentials are present; otherwise the package builder uses its existing sealed ad-hoc fallback.

## Distribution

FloatTabs v0.5.4 Build 22 is published through the repository GitHub Release pipeline with the DMG, DMG SHA-256, dSYM archive and dSYM SHA-256 assets.
