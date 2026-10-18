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

## Current posture

```text
ACTIVE_PRODUCT_TASK=FT-DIAG-HISTORY-REINTEGRATION-001
TASK_STATE=ACTIVE
BASE_MAIN=fef824c4d9f7783dca80e831c3812dae8e5f0833
SOURCE_PR=124_OPEN_DRAFT
SOURCE_PR_HEAD=e8bc90ad5d9897585974a84aef92e89bf3c2f2cb
SOURCE_PR_DISPOSITION=REINTEGRATE_PRODUCT_SEMANTICS
LIFECYCLE_PR_129=CLOSED_ABANDONED_UNMERGED
LATEST_RELEASE=v0.5.3_BUILD_21
ROOT_CAUSE=N/A
```

## Next

Reconcile the PR #124 product implementation onto the current-main integration branch, run focused/full verification and exact-head hosted CI, then install an exact Release candidate for Human Real-Mac diagnostics acceptance before merge.