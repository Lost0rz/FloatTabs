# FloatTabs v0.5.3

Release date: 2026-10-18

Build: **21**

## Summary

FloatTabs v0.5.3 packages the accepted reliability, interaction, speech, diagnostics, and unread-attention work merged after v0.5.2. The release keeps Browser Profile and website-session data ownership unchanged and remains Apple Silicon arm64-only.

## Unread / Ready Tab Attention

* Adds six selectable reminder styles: **Dot, Beacon, Halo, Orbit, Pulse, and Sweep**.
* Adds a separate attention palette dimension: **Red, Amber, Blue, Violet, Mint, and Spectrum**; Dot remains the classic red indicator.
* Removes Browser Profile color from normal Tab presentation while retaining existing Profile color metadata for compatibility.
* Settings previews use compact symmetric geometry and the Style chooser uses a responsive 3-column × 2-row layout.
* Unread Tab Attention now lives under **General** beside Interface Appearance; Audio remains focused on Ready Alerts and Speech.
* Animated treatments use bounded Core Animation and respect macOS Reduce Motion without moving or re-laying out Tabs.
* Resident/released favicon color semantics and unread acknowledgement ownership remain unchanged.

## Shell Interaction

* Removes FloatTabs-owned window movement acquisition from the external shell perimeter and complete left Tab rail.
* Retains the bounded inner Web-surface movement affordance as the supported movement owner.
* Tab selection/reorder, fold/unfold, resize, fullscreen ownership, and persisted sizing behavior remain protected.

## ChatGPT Speech Reliability

* Fixes **Read Latest Response** ownership so speech is bound to the latest positively assistant-owned response rather than a broad container that could include the user's prompt.
* Preserves legacy and current semantic response-root support while failing closed when assistant ownership cannot be established.
* Existing Manual Read, Replay, Auto Speak, queueing, and response identity protections remain in place.

## Runtime Residency Reliability

* Inactive Hot runtimes now recover renderer termination in the background without selecting the Tab, presenting FloatTabs, or stealing focus.
* Ordinary hidden Warm runtimes are no longer prematurely released by the old two-Warm LRU path; configured Warm retention governs normal inactivity.
* Memory-pressure warning remains diagnostic-only; critical pressure may still release eligible inactive Warm runtimes while media, attention, and speech protections remain authoritative.

## Diagnostics and Measurement

* Expands privacy-bounded runtime, navigation, focus, and ChatGPT page-app evidence for diagnosing stuck/blank/runtime incidents.
* Diagnostics continue to avoid persisting prompt/response text, cookies, authorization material, full URLs, network payloads, and similar content-bearing data.
* Adds DEBUG/benchmark measurement support for long-running ChatGPT runtime observation without changing Release product behavior.
* The separate long-term diagnostics-history work in PR #124 is **not included** in v0.5.3.

## Validation

* Release baseline before v0.5.3 metadata: `869bfaeb7eb6b00d9f2460fd638cb922f3200981`.
* Latest attention delivery: focused XCTest **93 passed**; full XCTest **1,323 passed / 4 skipped / 0 failed**; Debug and Release arm64 builds PASS; exact-head macOS CI and QA DMG PASS; Human Real-Mac acceptance PASS.
* Shell movement refinement: focused/full XCTest, Debug/Release arm64, hosted macOS CI, QA DMG, and Human Real-Mac acceptance PASS.
* Hot/Warm lifecycle corrective: focused/full regression coverage, Debug/Release arm64, hosted gates, and Human Warm-retention acceptance PASS.
* Latest-response speech ownership corrective: focused extraction/speech suites, full XCTest, Debug/Release builds, independent audit, and Human acceptance PASS.

## Release Integrity

* Distribution remains **Apple Silicon arm64-only**.
* The release pipeline verifies the Release app architecture, DMG integrity, dSYM archive, code signature, and SHA-256 checksum sidecars.
* Developer ID signing/notarization is used when the configured release credentials are present; otherwise the package builder falls back to a sealed ad-hoc signature.

## Data Safety

* No Browser Profile, Web App Slot, website login/session/cookie, WebKit store, backup, or recovery-data reset/migration is part of this release.

## Distribution

FloatTabs v0.5.3 Build 21 is published through the repository's GitHub Release pipeline with the DMG, DMG SHA-256, dSYM archive, and dSYM SHA-256 assets.
