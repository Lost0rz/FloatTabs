# FloatTabs Current Status

**Status date:** 2026-10-21
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: NO_ACTIVE_ENGINEERING_TASK — AIR OBSERVATION**

The v0.5.6 diagnostics-efficiency observation release is published and verified. No product/release mutation task remains active after this control closeout.

## Current public baseline

```text
LATEST_RELEASE=v0.5.6
BUILD=24
ARCH=arm64
RELEASE_COMMIT=17f1bf1760625833d0b82397009223b2165521c7
ROOT_CAUSE=UNKNOWN
INCIDENT_STATE=WAITING_FOR_FRESH_AIR_EVIDENCE
```

## Verified release lifecycle

- Diagnostics source PR #141 merged to protected `main` at `940fd8e80792eb32c5571bc6b159ffb7db13017f`.
- Release PR #142 merged to protected `main` at `17f1bf1760625833d0b82397009223b2165521c7`.
- Source post-merge main macOS CI `39620963744`: PASS.
- Release PR exact-head macOS CI `39622419627`: PASS.
- Release PR exact-head QA DMG `39622419742`: PASS.
- Publish Release workflow `39623668661`: PASS.
- Post-release-merge main macOS CI `39623668662`: PASS.
- Public GitHub Release `v0.5.6` (release ID `419708920`): published, non-draft, non-prerelease.
- `refs/tags/v0.5.6` points directly to `17f1bf1760625833d0b82397009223b2165521c7`.
- Published assets verified present:
  - `FloatTabs-0.5.6.dmg`
  - `FloatTabs-0.5.6.dmg.sha256`
  - `FloatTabs-0.5.6.dSYM.zip`
  - `FloatTabs-0.5.6.dSYM.zip.sha256`

GitHub release asset digests:

```text
DMG_ASSET_SHA256=d377b027b8e2c8503f62c60a698ed39668937ec86c0e14416bfac93804e6e55a
DSYM_ZIP_ASSET_SHA256=9f215607adb516509bc61d616e3a1e567ca5d28a4086029900a45ccfe5998a5d
```

Publisher verification confirmed both checksum sidecars with `shasum -a 256 -c`; `hdiutil verify` reported the DMG as valid. The built app reported v0.5.6 / Build 24 and arm64.

## Observation baseline

v0.5.6 preserves lower-volume, higher-value long-run diagnostics for:

- main-page and FloatTabs-isolated-world JavaScript liveness;
- navigation phase and observed Web-process epoch/termination count;
- host resident memory and public attribution availability;
- main-world JavaScript round-trip, event-loop, and visible-frame responsiveness;
- long-run page-app totals plus identity-safe deltas/rates;
- existing ChatGPT attention observer/detector/liveness workload;
- bounded workload-capture outcomes including timeout/suppressed/stale/evaluation-failed.

A representative equivalent periodic-log fixture measured 21,382 bytes before and 13,702 bytes after, a 35.918% reduction. The earlier 50% target was not reached and is not claimed.

No individual diagnostic event establishes root cause by itself.

## Data and recovery boundary

- Root cause remains `UNKNOWN`; the slowdown/termination incident is not claimed fixed.
- No automatic reload/reset/rebuild or new recovery behavior is part of v0.5.6.
- No Browser Profile, cookie, session, WebsiteData, Slot, preference, backup, or diagnostic-history reset/migration is part of this release.
- No private WebKit process attribution or page-content capture was added.
- Diagnostic logs remain local/content-free under the existing bounded retention/export design.

## Operational next step

Install v0.5.6 / Build 24 on the Air and use FloatTabs normally for long-term observation.

If a fresh sidebar/share/image-viewer slowdown, WebContent termination, or another slow/stall incident occurs, preserve/export Runtime Diagnostics before reload/restart when practical and provide the evidence with an approximate incident time. A later causal-investigation task should be authorized from that fresh evidence rather than guessing a root cause now.
