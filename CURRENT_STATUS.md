# FloatTabs Current Status

**Status date:** 2026-10-18
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: NO_ACTIVE_PRODUCT_TASK**

`FT-DIAG-HISTORY-REINTEGRATION-001` is completed. Long-term local diagnostics/history has been selectively reintegrated onto the current post-v0.5.3 main baseline and accepted on Real Mac.

## Current main baseline

- Product PR #130: MERGED.
- PR #130 final head: `b0c0759cd7f17b403a4b883097e205566fa38daf`.
- PR #130 merge commit: `3db8718582e0b10510010b5c4c14044b9834a3d9`.
- Semantic implementation head: `c12e18650f2fb96412f7bd208814a4dccfbfbcc2`.
- Historical PR #124: CLOSED / UNMERGED / `SUPERSEDED` at `e8bc90ad5d9897585974a84aef92e89bf3c2f2cb`.
- Lifecycle PR #129: CLOSED / ABANDONED / UNMERGED.

## Accepted diagnostics baseline

Advanced → Runtime Diagnostics now includes:

- `Keep local diagnostic history`;
- `Detail level` with Standard / Verbose;
- `Long-term performance observation`;
- `Export Recent Diagnostics…`;
- `Open Saved Logs Folder`;
- bounded local sanitized JSONL history with the existing retention/rotation pipeline;
- low-cadence selected-Slot content-free performance checkpoints;
- diagnostics-only runtime/WebView/navigation identity evidence;
- manual reload diagnostic boundary;
- no second diagnostics writer, remote telemetry, automatic AI upload, or destructive persistence migration.

Current later product behavior remains preserved, including the accepted unread Tab Attention styles/palette, Settings IA, Browser Profile/session ownership, focus/navigation/window/runtime behavior, and v0.5.3 app metadata.

## Verification / acceptance

- Focused XCTest: 288 passed / 0 failed.
- Full XCTest: 1,339 passed / 0 failed / 0 skipped.
- Local Debug / Release arm64: PASS.
- Final PR head GitHub macOS CI run `39100869890`: PASS.
- Final PR head QA DMG run `39100869878`: PASS.
- Human Real-Mac acceptance: PASS on 2026-10-18.
- No Browser Profile, Slot, session, cookie, WebKit, backup, or diagnostics data was reset, deleted, or migrated.

## Release boundary

- Latest public GitHub Release remains `v0.5.3` / Build 21.
- The reintegrated long-term diagnostics work was merged **after** the v0.5.3 release lifecycle completed, so the existing downloadable v0.5.3 release artifact does not represent this newer main baseline.
- A future release task is required before publishing this reintegrated diagnostics baseline as a new downloadable version.

## Current posture

```text
ACTIVE_PRODUCT_TASK=NONE
LAST_COMPLETED_TASK=FT-DIAG-HISTORY-REINTEGRATION-001
TASK_STATE=COMPLETED
PR_130=MERGED
PR_130_MERGE_COMMIT=3db8718582e0b10510010b5c4c14044b9834a3d9
PR_124=CLOSED_SUPERSEDED_UNMERGED
PR_129=CLOSED_ABANDONED_UNMERGED
HUMAN_UI_ACCEPTANCE=PASS
LATEST_RELEASE=v0.5.3_BUILD_21
MAIN_AHEAD_OF_LATEST_RELEASE=YES
ROOT_CAUSE=N/A
```

## Next

No active product task is authorized. Start or reconcile a new `CURRENT_TASK.md` before any new product, release, cleanup, or diagnostics mutation. If the merged diagnostics baseline should become downloadable, open a new release task rather than modifying this completed lifecycle.
