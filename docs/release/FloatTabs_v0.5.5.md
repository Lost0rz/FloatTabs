# FloatTabs v0.5.5

Release date: 2026-10-19

Build: **23**

## Summary

FloatTabs v0.5.5 is a diagnostic observation release intended for long-term normal use on the Air. It publishes the bounded Web runtime diagnostics accepted through PR #138 so future slow/stall incidents can be captured with stronger evidence.

The underlying ChatGPT/WebKit stall root cause remains **UNKNOWN**. This release does **not** claim the stall is fixed.

## Web Runtime Observation

* Adds bounded cross-world liveness sampling for supported ChatGPT runtimes in both the ordinary page JavaScript world and the FloatTabs isolated content world.
* Records navigation phase, observed Web-process epoch/termination count, host resident memory, and explicit public-API attribution availability without guessing child-process identity.
* Keeps the post-finish stall evidence boundary conservative: a first finished-state dual timeout is candidate evidence; a consecutive dual timeout is required for confirmed `POST_FINISH_RUNTIME_STALL` evidence.
* Adds content-free main-world responsiveness evidence for partial SPA interaction degradation: JavaScript round-trip latency, one `setTimeout(0)` scheduling turn, and—when visible—one bounded `requestAnimationFrame` callback.
* Preserves slow-success separately from timeout and does not introduce an arbitrary HEALTHY/DEGRADED threshold.
* Bounds outstanding WebKit JavaScript callbacks to at most two per world; saturated samples are recorded as `suppressed`, not misclassified as timeouts.
* Sampling remains low-frequency at approximately 30-second intervals. Persistent or recurring degradation can be trended, but a brief episode may occur entirely between samples.

## Diagnostics, Privacy, and Data Safety

* Existing local Runtime Diagnostics history, bounded rotation/retention, `Export Recent Diagnostics…`, and `Open Saved Logs Folder` remain the first-round incident evidence path.
* Diagnostic evidence is content-free: it does not record prompt/response bodies, page text, clicked controls, selectors, cookies, session/token values, or Browser Profile secrets.
* No remote telemetry, automatic upload, or automatic AI analysis is introduced.
* No automatic reload/reset/rebuild or new recovery behavior is introduced.
* No Hot/Warm/Cold residency-policy change is part of this release.
* No Browser Profile, Web App Slot, website login/session/cookie, WebsiteData, preference, backup, or existing diagnostic-history reset/migration is part of this release.

## Validation

* Diagnostic implementation merged through PR #138 to protected `main` at `1d6f80a9e59a2fcbee1c846be562b14c6b6e2fea`.
* Final responsiveness semantic implementation: `1745acaab91185727901cc7ed48a43f4326ef73e`.
* Focused responsiveness/Web Runtime XCTest: **7 passed**.
* Full XCTest: **1,349 passed / 0 failed / 0 skipped**.
* Debug and Release arm64 builds: PASS.
* Pre-merge exact-head macOS CI and QA DMG: PASS.
* Post-merge `main` macOS CI run `39227623989`: PASS, including Debug build, Release build, native arm64 verification, and unit tests.
* The v0.5.5 release PR and publisher pipeline must re-verify the literal `0.5.5` / Build `23` package identity before publication.

## Release Integrity

* Distribution remains **Apple Silicon arm64-only**.
* The repository release pipeline verifies Release architecture, DMG integrity, dSYM archive, code signature, and SHA-256 checksum sidecars.
* Developer ID signing/notarization is used when configured release credentials are present; otherwise the existing sealed ad-hoc fallback remains the package-builder behavior.

## Long-term Air Observation

Use FloatTabs normally on the Air. If a real slow/stall incident occurs, preserve/export diagnostics before reload or restart when practical. The captured evidence is intended to narrow the later causal investigation; no single diagnostic event establishes root cause.

## Distribution

FloatTabs v0.5.5 Build 23 is intended to be published through the repository GitHub Release pipeline with the DMG, DMG SHA-256, dSYM archive, and dSYM SHA-256 assets.
