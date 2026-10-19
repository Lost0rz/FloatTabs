# FloatTabs Current Task

**Task ID:** `FT-DIAG-POST-FINISH-STALL-001`
**Title:** Merge bounded Web runtime diagnostics for long-term Air observation
**Status:** `AUTHORIZED — FINAL MERGE GATE`
**Mode:** `DIAGNOSTIC`
**Task class:** `INCIDENT_INVESTIGATION`
**Base:** `main@3511297d5f573598556739519bae859322578768`
**Branch:** `codex/ft-post-finish-stall-diag-001`
**PR:** `#138`
**Final semantic implementation identity:** `1745acaab91185727901cc7ed48a43f4326ef73e`

## Objective

Merge the audited diagnostic infrastructure so FloatTabs can be released as a long-term observation build for normal use on the Air. Root cause remains `UNKNOWN`; this task does not claim the stall is fixed.

Mac mini remains the development/release-preparation machine. Air remains the long-term normal-use observation and fresh-incident capture machine.

## Verified basis

- Independent Web re-audit passed on 2026-10-19 against repository head `4f1b6b7f7c507970d055f9d4ac77b61b0090dc7e`.
- Semantic implementation head `1745acaab91185727901cc7ed48a43f4326ef73e` contains bounded cross-world liveness plus content-free event-loop/frame responsiveness evidence.
- Focused responsiveness/Web Runtime XCTest: 7 passed.
- Full XCTest: 1,349 passed, 0 skipped, 0 failed.
- Debug arm64 and Release arm64 builds passed.
- Pre-merge audited-head macOS CI `39216559333` passed.
- Pre-merge audited-head QA DMG `39216559277` passed.
- PR #138 was open, draft, clean, and mergeable at the last audit.
- Fresh Air incident capture is later causal evidence and is not a merge prerequisite.

## Authorized scope

1. Record this user-authorized merge state in `CURRENT_TASK.md` / `CURRENT_STATUS.md` and push it on the existing PR branch.
2. Re-run/verify the required exact-head CI and QA DMG for the resulting control-only head.
3. If exact-head checks pass and PR #138 remains clean/mergeable, mark it Ready for Review and merge it into protected `main` using an expected-head guard.
4. Verify the merge landed on `main` and the required post-merge repository state is healthy.
5. Do not perform further product-code changes in this task.
6. After merge, close this task and create a separate release task from the merged `main` baseline for the observation release.

## Merge gate

Merge only if all remain true on the literal final PR head:

- Web re-audit = PASS;
- required `Build & Test (Apple Silicon arm64)` = PASS;
- QA DMG = PASS;
- PR state = open / clean / mergeable;
- head/base identity unchanged except for this authorized control reconciliation.

## Explicitly unauthorized

- Any claim that root cause is known or the bug is fixed.
- New reload/reset/rebuild/recovery behavior.
- Hot/Warm/Cold policy changes.
- Browser Profile, cookie, session, WebsiteData, Slot, preference, backup, or user-configuration mutation.
- Any additional semantic product change before merge.

## After merge

This task becomes terminal. The successor task is a release-only task that will bump version/build, add release notes, validate the package, merge through protected `main`, and allow the existing `Publish Release` workflow to publish the observation release.
