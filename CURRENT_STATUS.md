# FloatTabs Current Status

**Status date:** 2026-10-18
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: DIAGNOSTICS_HISTORY_REINTEGRATION_ACTIVE**

`FT-DIAG-HISTORY-REINTEGRATION-001` is active. The objective is to restore the already-developed long-term local diagnostics/history product semantics from historical Draft PR #124 onto the current post-v0.5.3 `main` baseline without regressing later accepted Tab Attention, Settings IA, release metadata, runtime ownership, or user data.

## Verified baseline

- Current remote `main`: `fef824c4d9f7783dca80e831c3812dae8e5f0833`.
- Latest public release: `v0.5.3` / Build 21.
- `main` and `v0.5.3` contain the earlier Runtime Diagnostics surface (`Collection mode`, `Export Recent Diagnostics…`, `Open Logs Folder`).
- Historical Draft PR #124 (`FT-DIAG-HISTORY-001`) is still OPEN / Draft / unmerged at `e8bc90ad5d9897585974a84aef92e89bf3c2f2cb`.
- PR #124 contains the missing enhanced local-history semantics, including `Keep local diagnostic history`, diagnostic detail level, `Long-term performance observation`, saved-log workflow, seven-day bounded retention/rotation integration, and low-cadence performance checkpoints.
- PR #124 diverged from current main and must not be merged as a stale branch wholesale.
- The abandoned lifecycle PR #129 was CLOSED / UNMERGED after this baseline mismatch was discovered; it did not modify main.

## Reintegration posture

The accepted source of product intent is the implemented product delta in PR #124, not its stale control files or old branch baseline. Reintegration must start from current `main` and selectively preserve current production behavior where later work overlaps.

Protected current-baseline behavior includes:

- v0.5.3 version/build and release baseline;
- Dot / Beacon / Halo / Orbit / Pulse / Sweep unread attention system and Settings IA;
- current Browser Profile/session/WebKit ownership and data safety;
- current shell/window/focus/navigation/recovery behavior;
- current diagnostics ownership rule: Diagnostics records evidence and does not define product truth/root cause.

## Data safety

- No Browser Profile, Web App Slot, cookie/session/WebKit data migration or reset is authorized.
- No destructive cleanup of existing diagnostics or recovery data is authorized.
- Long-term diagnostics remain local/sanitized; no remote telemetry or automatic AI upload/analysis is authorized.

## Execution / acceptance state

- The selective implementation is committed at semantic source revision `c12e18650f2fb96412f7bd208814a4dccfbfbcc2` on PR #130. PR #124 remains OPEN / Draft and source-only.
- Focused XCTest: 288 passed / 0 failed. Full XCTest: 1,339 passed / 0 failed / 0 skipped. Local Debug and Release arm64 builds passed.
- Exact semantic-head GitHub macOS CI and QA DMG both passed for `c12e18650f2fb96412f7bd208814a4dccfbfbcc2`.
- The exact Release candidate is running from `/Applications/FloatTabs.app`; its embedded revision is `c12e18650f2fb96412f7bd208814a4dccfbfbcc2`, version 0.5.3 / Build 21. The previous application bundle is preserved at `/Applications/FloatTabs-rollback-ft-diag-reintegration-001.app`.
- Human visual / interaction acceptance is still pending. No Browser Profile, Slot, session, cookie, WebKit, backup, or diagnostic data was reset, deleted, or migrated.

## Current posture

```text
ACTIVE_PRODUCT_TASK=FT-DIAG-HISTORY-REINTEGRATION-001
TASK_STATE=WAITING_FOR_HUMAN_REAL_MAC_ACCEPTANCE
BASE_MAIN=fef824c4d9f7783dca80e831c3812dae8e5f0833
SEMANTIC_IMPLEMENTATION_HEAD=c12e18650f2fb96412f7bd208814a4dccfbfbcc2
SOURCE_PR=124_OPEN_DRAFT
SOURCE_PR_HEAD=e8bc90ad5d9897585974a84aef92e89bf3c2f2cb
SOURCE_PR_DISPOSITION=REINTEGRATE_PRODUCT_SEMANTICS
LIFECYCLE_PR_129=CLOSED_ABANDONED_UNMERGED
LATEST_RELEASE=v0.5.3_BUILD_21
HUMAN_UI_ACCEPTANCE=PENDING
ROOT_CAUSE=N/A
```

## Next

Human Real-Mac acceptance is the remaining gate. Keep PR #130 Draft and the exact candidate running; after acceptance, complete merge and give PR #124 a `SUPERSEDED` lifecycle disposition.
