# FloatTabs v0.5.1

Release date: 2026-09-20

Build: **19**

## Summary

FloatTabs v0.5.1 publishes the three verified production updates merged after v0.5.0: per-tab home-page capture, visible ChatGPT completion unread-state correction, and the final external-voice native-focus stabilization.

## Tab Home

* Adds **Set Current Page as Tab Home**.
* A tab can adopt its current committed page URL as its home destination.
* The update requires a committed URL before replacing the saved home value.
* Existing tab persistence and navigation behavior remain otherwise unchanged.

## ChatGPT Unread State

* Fixes visible ChatGPT assistant completion incorrectly creating an unread badge.
* Completion that belongs to the currently visible document no longer becomes unread merely because response-finish bookkeeping runs.
* Background and genuinely unseen response attention behavior remains preserved.

## External Voice Focus

* Stabilizes native focus ownership for external voice input.
* A presentation generation now owns at most one required native source-window focus transfer.
* If the source window is already key, no redundant native focus transfer is issued.
* Repeated readiness callbacks do not cause additional key/main-window churn.
* External-voice settle handling preserves DOM/editor readiness without performing a second native refocus.
* Fullscreen and ordinary non-voice presentation behavior remain unchanged.
* The corrective preserves the existing RemoteOrbit semantic `focusInputForVoice` integration and does not add input-source switching hacks.

## Validation

* Production baseline:
  `72ee5898378df31f3e0b0de7f1b48965d66d9fd6`
* v0.5.0 release baseline:
  `9dec944f466c259c6d53e6191faadca5e33fbb03`
* Main is exactly 3 commits ahead of v0.5.0.
* Post-merge required check on the final production baseline:
  `Build & Test (Apple Silicon arm64)` — PASS.
* External voice runtime acceptance completed successfully on the merged corrective.
* No PR #87 single-instance runtime ownership changes are included in this release.

## Release Integrity

* Release packaging remains Apple Silicon arm64-only.
* The existing release pipeline builds and verifies the DMG, dSYM, native architecture, code signature, and SHA-256 checksums.
* The QA/release package remains ad-hoc signed when no Developer ID identity is supplied.

## Distribution

FloatTabs v0.5.1 Build 19 is distributed as an ad-hoc signed, unnotarized **Apple Silicon arm64-only** DMG.
