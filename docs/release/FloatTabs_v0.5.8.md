# FloatTabs v0.5.8

Release date: 2026-10-27

Build: **26**

## Summary

FloatTabs v0.5.8 publishes the incident-oriented runtime diagnostics work merged after v0.5.7.

The release improves the evidence available for Web runtime, navigation, recovery, Attention, memory-pressure and focus-restore incidents while preserving existing product behavior, Browser Profiles, website sessions and persistence semantics.

The previously observed WebContent stall / termination root cause remains **UNKNOWN**. v0.5.8 does not claim that the underlying runtime incident has been causally fixed or eliminated.

## Incident-Oriented Runtime Diagnostics

### Shared incident correlation

- Runtime incidents can carry a shared incident identity across bounded diagnostic emitters.
- A single incident can correlate WebContent termination, recovery disposition, recovery navigation progress and the first healthy runtime closure.
- Post-finish and navigation-stall evidence can terminate explicitly as healthy recovery, superseding navigation, stale context or runtime replacement.
- Incident IDs are correlation evidence only; they do not become canonical product/runtime state.

### Bounded automatic evidence

- Known runtime-failure triggers can request bounded snapshots rather than relying only on a later manual capture.
- Snapshot evidence remains privacy-filtered and does not mutate the Slot, reload the page, rebuild the runtime or alter persisted website data.
- Existing manual diagnostic capture remains available.

### WebContent termination and recovery

- Termination evidence records the observed runtime/process epoch boundary and keeps recovery progress under the same incident identity when appropriate.
- Recovery navigation commit/finish evidence is correlated without changing the existing recovery policy.
- The first healthy current-runtime liveness boundary can close the incident explicitly.
- A recovery that works still establishes only a recovery boundary; it does not prove the cause of the termination.

## Attention Diagnostics

Attention liveness/resync abnormal paths now have stronger typed evidence for:

- timeout;
- evaluation/callback failure;
- invalid/parse-invalid results;
- stale runtime/document callbacks;
- request-budget suppression;
- late callbacks from an older runtime epoch.

Suppression remains semantically distinct from failure and timeout. The accepted Attention business-state machine and timeout thresholds are unchanged.

## Memory Pressure Evidence

- Memory-pressure observations can be correlated with incident/sequence identity and FloatTabs host resident memory.
- Per-Slot evaluation records why a runtime was eligible, skipped or released under the existing lifecycle policy.
- FloatTabs does **not** claim per-WebContent-process memory ownership from host RSS.
- Public WebKit APIs do not expose a reliable WebContent child-process attribution API, so diagnostics explicitly record `unavailable_public_api` rather than guessing.

## Previous-Application Restore Evidence

Focus/previous-application restoration now records terminal outcomes so a request does not remain diagnostically ambiguous after its bounded observation window.

This is evidence only; focus policy itself is unchanged.

## Page-App Diagnostic Evidence

- Page-app occurrence age is now represented as true age-at-capture rather than document-relative occurrence time.
- Structural error evidence remains content-free and privacy-filtered.
- Bounded retention is category-diverse and tracks per-kind drops so one noisy category cannot silently hide all other evidence.

## Diagnostic Noise Reduction

Redundant healthy/low-value diagnostic persistence was reduced without reducing the actual runtime health-probe cadence or suppressing meaningful decision/failure events.

## CI Stability Corrective

The final release candidate also includes a **test-only** stabilization for one new incident-correlation regression test.

The test previously depended on asynchronous `WKWebView.url` timing after `loadHTMLString`. On some macOS CI runs the production supported-ChatGPT URL admission guard correctly returned before the test fixture had exposed the expected URL, causing the assertion to flake.

The test now uses a deterministic test-only `WKWebView` fixture that reports a supported ChatGPT URL while still executing the real production liveness method and preserving the incident-ID / healthy-closure assertions.

No production runtime source, recovery policy, timeout or CI workflow behavior was changed by this corrective.

## Data Safety

v0.5.8 does not intentionally reset, replace or clear:

- Browser Profiles;
- Web App Slot configuration;
- website cookies, sessions or logins;
- user preferences;
- backup data;
- persisted website data.

No reload/reset/restart workaround is introduced as a substitute for runtime ownership correctness. No private WebKit API is introduced.

## Validation

Diagnostics delivery:

- PR #153: **MERGED**
- merge commit: `73eee804cbe32a32bdce9b389be98939570c097e`
- accepted production semantic implementation: `b6d9e6841da92033dbc2f5fbd5c325915e1e3864`
- final PR head after test-only stabilization/control closeout: `dcff3e7d56e6fc0c8f2489b1fa08af20536bffac`

Final verification before merge:

- named flaky regression: `1 passed / 0 failed`;
- repeated named regression: `20/20 passed`;
- full `WebFocusAdapterTests`: `26 passed / 0 failed`;
- full XCTest suite: `1,382 executed / 0 failed`;
- macOS CI run `40427655506` / `#1150`: **SUCCESS**;
- required `Build & Test (Apple Silicon arm64)`: **SUCCESS**;
- QA DMG run `40427655469` / `#544`: **SUCCESS**;
- fresh-context diagnostics audit: **PASS**;
- unresolved implementation blockers: **NONE**.

The v0.5.8 release lifecycle independently re-verifies the literal release metadata and package identity after this release record and version bump are merged.

## Release Integrity

Distribution remains **Apple Silicon arm64-only**.

Expected public assets:

- `FloatTabs-0.5.8.dmg`
- `FloatTabs-0.5.8.dmg.sha256`
- `FloatTabs-0.5.8.dSYM.zip`
- `FloatTabs-0.5.8.dSYM.zip.sha256`

The repository release workflow builds the Release package, verifies the app architecture, code-signature integrity, DMG validity and checksum sidecars, then publishes the GitHub Release from the accepted merged release identity.

The package is notarized only when the release environment supplies the configured Developer ID signing identity and notarization profile; otherwise the workflow produces the sealed ad-hoc signed package supported by the repository build script.

## Installation / Runtime Observation

Install `FloatTabs-0.5.8.dmg` normally over the existing application. Browser Profile and website session data are not intentionally reset by the upgrade.

After installation, use FloatTabs normally for an observation period. If a fresh slowdown, stall, WebContent termination, Attention abnormality or focus-restore anomaly occurs, preserve/export Runtime Diagnostics before reload/reset/restart when practical and note:

1. approximate incident time;
2. affected Slot / website;
3. what was happening immediately before the symptom;
4. whether reload/reset/restart recovered it.

Recovery does not prove root cause. Until fresh causal evidence supports a stronger claim, the historical runtime root cause remains **UNKNOWN**.
