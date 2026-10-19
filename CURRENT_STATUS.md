# FloatTabs Current Status

**Status date:** 2026-10-19
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: AUTHORIZED — FINAL MERGE GATE**
Active task: `FT-DIAG-POST-FINISH-STALL-001` on `codex/ft-post-finish-stall-diag-001`.
PR: `#138 — Diagnose post-finish Web runtime stalls across JavaScript worlds`.

## Current facts

- Protected baseline before merge: `main@3511297d5f573598556739519bae859322578768`.
- Latest public release: `v0.5.4` / Build 22.
- Final semantic implementation identity: `1745acaab91185727901cc7ed48a43f4326ef73e`.
- Independent Web re-audit: `PASS` on 2026-10-19.
- Pre-merge audited repository head: `4f1b6b7f7c507970d055f9d4ac77b61b0090dc7e`.
- Pre-merge audited-head macOS CI `39216559333`: PASS.
- Pre-merge audited-head QA DMG `39216559277`: PASS.
- Focused responsiveness/Web Runtime XCTest: 7 passed.
- Full XCTest: 1,349 passed, 0 skipped, 0 failed.
- Root cause: `UNKNOWN`.
- Fresh incident: `NOT_OBSERVED`.

## Diagnostic observation baseline

The Release diagnostic path now preserves bounded, content-free evidence for:

- main-page and FloatTabs-isolated-world liveness;
- navigation phase and Web-process epoch/termination count;
- host resident memory and explicit attribution availability;
- main-world JavaScript round-trip latency;
- main-world event-loop scheduling latency;
- visible-page frame callback outcome/latency.

Sampling remains low-frequency at 30-second intervals. It can show persistent/recurring degradation but may miss a brief episode entirely between samples. No fixed degraded threshold or causal classification is introduced.

Probe lifecycle remains bounded: one cancelable observation task per observer, at most two pending callbacks per JS world, bounded timeout/window behavior, and no persistent page listener or high-frequency polling.

Diagnostics remain content-free and do not record prompt/response text, page text, clicked control, selector, cookies, tokens, sessions, or Browser Profile secrets.

## Merge authorization

The user authorized merge and subsequent observation release on 2026-10-19.

PR #138 may be marked Ready and merged only after the literal final control-only head re-passes exact-head required CI and QA DMG and remains clean/mergeable.

No further semantic code change is authorized in this task.

## Release path after merge

After PR #138 merges and main is verified healthy:

1. close `FT-DIAG-POST-FINISH-STALL-001` as merged;
2. create a separate release-only task from merged `main`;
3. bump version/build and add release notes;
4. validate exact release head;
5. merge the release PR through protected main;
6. allow the repository `Publish Release` workflow to publish the observation build for Air long-term use.

The release must state that root cause remains unknown and that the stall is not claimed fixed.
