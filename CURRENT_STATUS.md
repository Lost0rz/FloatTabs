# FloatTabs Current Status

**Status date:** 2026-10-19
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: NO_ACTIVE_ENGINEERING_TASK — AIR OBSERVATION**

The v0.5.5 diagnostic observation release is published and verified. No product/release mutation task is active after the control closeout.

## Current public baseline

```text
LATEST_RELEASE=v0.5.5
BUILD=23
ARCH=arm64
RELEASE_COMMIT=45c9d4af15a2472327b796f2b87b88b3efb6717c
ROOT_CAUSE=UNKNOWN
INCIDENT_STATE=WAITING_FOR_FRESH_AIR_EVIDENCE
```

- Diagnostic infrastructure PR #138 merged at `1d6f80a9e59a2fcbee1c846be562b14c6b6e2fea`.
- Release PR #139 merged at `45c9d4af15a2472327b796f2b87b88b3efb6717c`.
- Release PR exact-head macOS CI `39230237508`: PASS.
- Release PR exact-head QA DMG `39230237645`: PASS.
- Post-merge main macOS CI `39231229582`: PASS.
- Publish Release workflow `39231229592`: PASS.
- Public GitHub Release `v0.5.5`: published, non-draft, non-prerelease.
- Tag `v0.5.5` points directly to the release merge commit.
- DMG, DMG checksum, dSYM, and dSYM checksum assets are present.

## Observation baseline

The public v0.5.5 Release preserves bounded, content-free diagnostics for:

- main-page and FloatTabs-isolated-world JavaScript liveness;
- navigation phase and observed Web-process epoch/termination count;
- host resident memory and public attribution availability;
- main-world JavaScript round-trip latency;
- event-loop scheduling latency;
- visible-page frame callback outcome/latency.

The observer remains low-frequency at approximately 30-second intervals, with bounded callbacks/tasks. It can provide persistent/recurring trend evidence but may miss a brief episode that starts and ends between samples.

No arbitrary HEALTHY/DEGRADED threshold exists and no diagnostic event establishes root cause by itself.

## Data and recovery boundary

- Root cause remains `UNKNOWN`; the stall is not claimed fixed.
- No automatic reload/reset/rebuild or new recovery behavior is part of v0.5.5.
- No Browser Profile, cookie, session, WebsiteData, Slot, preference, backup, or diagnostic-history reset/migration is part of this release.
- Diagnostic logs remain local/content-free under the existing bounded retention/export design.

## Operational next step

Install v0.5.5 / Build 23 on the Air and use FloatTabs normally for long-term observation.

If a fresh slow/stall incident occurs, preserve/export Runtime Diagnostics before reload/restart when practical and provide the evidence with an approximate incident time. A later causal-investigation task should be authorized from that fresh evidence rather than guessing a root cause now.
