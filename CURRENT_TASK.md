# FloatTabs Current Task

**Task ID:** `FT-RELEASE-V0.5.5-001`
**Title:** Publish FloatTabs v0.5.5 diagnostic observation release
**Status:** `TERMINAL — PUBLISHED / VERIFIED`
**Mode:** `TERMINAL`
**Task class:** `RELEASE`

> This release task is complete and grants no further product, release, branch, data, or recovery authority.

## Terminal result

FloatTabs v0.5.5 / Build 23 has been merged, published, and independently verified as the current public observation release for long-term normal use on the Air.

```text
VERSION=0.5.5
BUILD=23
ARCH=arm64
ROOT_CAUSE=UNKNOWN
BUG_FIXED_CLAIM=NO
RELEASE_STATE=PUBLISHED_VERIFIED
```

## Verified release identity

- Diagnostic infrastructure PR #138 merged to protected `main` at `1d6f80a9e59a2fcbee1c846be562b14c6b6e2fea`.
- Release PR #139 merged to protected `main` at `45c9d4af15a2472327b796f2b87b88b3efb6717c`.
- Release metadata is v0.5.5 / Build 23 for both Debug and Release app configurations.
- Release PR exact-head macOS CI `39230237508`: PASS.
- Release PR exact-head QA DMG `39230237645`: PASS.
- Post-merge main macOS CI `39231229582`: PASS.
- Publish Release workflow `39231229592`: PASS.
- Public GitHub Release: `v0.5.5`, non-draft, non-prerelease, published 2026-10-19.
- `refs/tags/v0.5.5` points directly to `45c9d4af15a2472327b796f2b87b88b3efb6717c`.
- Published assets verified present:
  - `FloatTabs-0.5.5.dmg`
  - `FloatTabs-0.5.5.dmg.sha256`
  - `FloatTabs-0.5.5.dSYM.zip`
  - `FloatTabs-0.5.5.dSYM.zip.sha256`
- DMG release asset SHA-256 digest metadata: `d574f15d93d8ea55cb3189e4c2df54af2c58ed20b760b4c0f1527e9833fadac5`.

## Product / diagnostic state

The published observation release includes bounded, content-free evidence for:

- main-page and FloatTabs-isolated-world JavaScript liveness;
- navigation phase and observed Web-process epoch/termination count;
- host resident memory and explicit public attribution availability;
- main-world JavaScript round-trip latency;
- event-loop scheduling latency;
- visible-page frame callback outcome/latency.

Sampling remains approximately every 30 seconds. A brief slowdown may occur entirely between samples. No fixed healthy/degraded threshold or causal classification is defined.

Root cause remains `UNKNOWN`. No automatic reload/reset/rebuild or new recovery behavior was introduced.

## Data safety

No release or diagnostic action authorized by this task clears or rewrites Browser Profiles, cookies, sessions, WebsiteData, Slots, preferences, backups, or existing diagnostic history.

## Operational next state

No engineering mutation task is active after this closeout.

Air is the long-term real-use observation host. If a fresh slow/stall incident occurs, preserve/export Runtime Diagnostics before reload/restart when practical and return that evidence for a new causal-investigation decision.
