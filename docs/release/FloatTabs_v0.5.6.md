# FloatTabs v0.5.6

Release date: 2026-10-21

Build: **24**

## Summary

FloatTabs v0.5.6 is a diagnostics-efficiency observation release for continued long-term normal use on the Air. It publishes the accepted PR #141 diagnostics changes so future slow/stall incidents retain higher-value long-run evidence while generating less repetitive log volume.

The underlying ChatGPT/WebKit slowdown and WebContent termination root cause remains **UNKNOWN**. This release does **not** claim that issue is fixed.

## Diagnostics Efficiency

* Removes duplicate production auto-hide observation logging while retaining one authoritative decision/reason event.
* Stops copying full static build/environment provenance into every periodic liveness/performance sample when correlation identity is already available elsewhere in the diagnostics stream.
* Throttles diagnostics retention pruning during ordinary writer flushes while preserving startup/rotation/export/final-flush retention boundaries.
* A representative equivalent periodic-log fixture decreased from **21,382 bytes** to **13,702 bytes**, a **35.918%** reduction. The earlier 50% target was not reached and is not claimed.

## Long-run Runtime Evidence

* Replaces the old page-app counter behavior that saturated at 255 with bounded long-run integer totals while preserving the bounded recent event ring.
* Adds checkpoint deltas and per-minute rates for page-app error/resource/lifecycle trends.
* Keeps delta baselines transient and per-Slot with a bounded **64-Slot LRU**. Runtime generation, WebView instance, document epoch, and counter regression reset only the affected Slot baseline, so normal A → B → A Slot switching does not destroy each Slot's trend evidence.
* Exposes content-free Release workload counters for work already performed by the existing ChatGPT attention observer/detector/liveness paths, including mutation batches, detector schedules/evaluations, evaluation duration, response-identity resolution work, and liveness work.
* Adds no new persistent MutationObserver, timer, polling loop, or independent JavaScript sampling cadence.
* Bounds long-term workload WebKit capture to a maximum **5-second** wait and **one outstanding request**. Timeouts complete the native checkpoint; later samples are suppressed while the timed-out callback remains outstanding; a late completion cannot overwrite or double-complete the prior timeout result.
* Workload timeout/suppression is diagnostics evidence only and does not trigger reload, reset, rebuild, or recovery.

## Privacy and Data Safety

* Diagnostics remain content-free: no prompt/response bodies, page text, selector text, clicked-control content, cookies, tokens, session values, or Browser Profile secrets are captured.
* No Browser Profile, Web App Slot, website login/session/cookie, WebsiteData, preference, backup, or existing diagnostic-history clearing/migration is part of this release.
* No automatic reload/reset/rebuild or Hot/Warm/Cold residency-policy change is introduced.
* No private WebKit API or guessed WebContent process attribution is introduced.

## Validation

* Source diagnostics implementation merged through PR #141 to protected `main` at `940fd8e80792eb32c5571bc6b159ffb7db13017f`.
* Final semantic corrective implementation: `e6f0fd8c671c720721fdc4b8ca71d2e993db3a89`.
* Focused bridge/diagnostics tests: **105 passed / 0 failed**.
* Privacy/rotation tests: **35 passed / 0 failed**.
* Full XCTest: **1,357 passed / 0 failed**.
* Debug arm64 build: PASS.
* Release arm64 build: PASS.
* Pre-merge exact-head macOS CI run `39618447261`: PASS.
* Pre-merge exact-head QA DMG run `39618447717`: PASS.
* Independent Web/runtime acceptance: PASS.
* The release lifecycle re-verifies literal v0.5.6 / Build 24 metadata, exact-head CI/QA packaging, post-merge `main`, and publisher asset/tag integrity before publication.

## Release Integrity

* Distribution remains **Apple Silicon arm64-only**.
* The repository release pipeline verifies the Release package, DMG integrity, dSYM archive, code signature, and SHA-256 checksum sidecars.
* The expected public assets are:
  * `FloatTabs-0.5.6.dmg`
  * `FloatTabs-0.5.6.dmg.sha256`
  * `FloatTabs-0.5.6.dSYM.zip`
  * `FloatTabs-0.5.6.dSYM.zip.sha256`

## Long-term Air Observation

Install v0.5.6 / Build 24 on the Air and use FloatTabs normally. If the sidebar/share/image-viewer slowdown, a WebContent termination, or another runtime degradation occurs, export Runtime Diagnostics before reload/restart when practical and note the approximate incident time.

The new evidence is intended to correlate page-app trend rate, observer/detector workload, cross-world/event-loop/frame responsiveness, runtime identity, and termination boundaries. No individual diagnostic event establishes root cause by itself.

## Distribution

FloatTabs v0.5.6 Build 24 is intended to be published through the repository GitHub Release pipeline with the DMG, DMG SHA-256, dSYM archive, and dSYM SHA-256 assets.
