# FloatTabs v0.5.7

Release date: 2026-10-24

Build: **25**

## Summary

FloatTabs v0.5.7 publishes the accepted Web runtime / Attention corrective work completed after v0.5.6 together with the Active Tab and unread Attention visual refinement.

This release improves recovery-state correctness and the clarity of Tab/Attention presentation while preserving Browser Profile, website session, and user preference data.

The previously observed WebContent stall/termination root cause remains **UNKNOWN**. v0.5.7 does not claim that underlying incident is fully root-caused or eliminated.

## Active Tab and Attention UI

- The active Tab now remains expanded at **76 pt** and keeps its label visible without requiring pointer hover.
- Inactive Tabs retain the existing **40 → 76 pt** Dock/hover magnification behavior.
- Unread Attention styles are simplified to four canonical choices: **Dot, Beacon, Orbit, Pulse**.
- Existing stored `halo` values migrate compatibly to Pulse and stored `sweep` values migrate to Orbit; existing preferences are not deleted or reset.
- Orbit is rendered as a clearer internal Tab perimeter so it is not lost against the larger FloatTabs shell border.
- Pulse now uses a stronger whole-surface treatment, breathing from opacity **0.38** to a full **1.00** peak; Reduce Motion keeps a static representative state at **0.72**.
- Settings presents the four Attention styles in a **2 × 2** layout using the same shared renderer as the runtime surface.

## Web Runtime / Attention Correctness

- Recovery navigation identity is retained across immediate/deferred recovery paths so stale or superseded callbacks cannot incorrectly claim the current navigation.
- Recovery completion restores the correct finished-navigation state and preserves post-finish stall eligibility.
- Finite liveness/resync request capacity is bounded by the physical WebContent runtime epoch rather than ordinary document replacement.
- Ordinary page/document replacement does not grant a fresh request budget; authoritative WebContent process replacement does.
- Late callbacks from an older runtime epoch are rejected safely.
- Bounded native Attention timeout/suppression health counters remain available in Standard diagnostics without adding a new JavaScript polling cadence.

These changes improve FloatTabs-owned correctness and diagnosability. They do not by themselves establish the external WebContent stall/termination root cause.

## Data Safety

- No Browser Profile, Web App Slot, website login/session/cookie, preference, backup, or persisted website-data clearing is part of this release.
- No reload/reset/restart workaround is introduced as a substitute for runtime ownership correctness.
- No destructive preference migration is used for the Attention-style reduction.
- No private WebKit API is introduced.

## Validation

- The Web runtime / Attention corrective was merged to protected `main` before this release.
- The Active Tab / unread Attention refinement was merged through PR #146 at `00618024e6d5ef9802e10f882008079e5e27a90e` after focused XCTest, full XCTest, Debug/Release arm64 builds, exact-head macOS CI, and QA DMG validation passed.
- Its subsequent control closeout passed protected-branch macOS CI and left no active engineering task or open PR before release preparation.
- The v0.5.7 release lifecycle independently re-verifies the literal release metadata, required CI, Apple Silicon package build, DMG/dSYM checksums, tag provenance, and published GitHub Release assets.

## Release Integrity

Distribution remains **Apple Silicon arm64-only**.

Expected public assets:

- `FloatTabs-0.5.7.dmg`
- `FloatTabs-0.5.7.dmg.sha256`
- `FloatTabs-0.5.7.dSYM.zip`
- `FloatTabs-0.5.7.dSYM.zip.sha256`

The repository release workflow builds the Release package, verifies the DMG and dSYM checksum sidecars, and publishes the GitHub Release from the accepted release `main` identity.

## Installation / Observation

Download `FloatTabs-0.5.7.dmg` from the GitHub Release and replace the existing application normally. Browser Profile and website session data are not intentionally reset by this release.

Continue normal use. If a fresh slowdown, stall, or WebContent termination occurs, preserve/export Runtime Diagnostics before reload/restart when practical and note the approximate incident time so the recorded runtime/navigation/Attention evidence can be correlated.
