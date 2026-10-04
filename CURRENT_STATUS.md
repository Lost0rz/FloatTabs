# FloatTabs Current Status

**Status date:** 2026-10-04
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Validity and operating mode

`CURRENT_STATUS.md` defines intended project state; live Git refs and GitHub PR metadata define current stored heads and PR states. Refresh refs before continuing.

**MODE: DIAGNOSTIC-ARCHITECTURE-AUDIT**

Lifecycle states are `ACTIVE`, `MERGED`, `SUPERSEDED`, and `ABANDONED`. Machine-specific worktree paths remain local-only.

## Production authority

**PRODUCTION_WORKTREE_ID:** `floattabs-main-production`
**PRODUCTION_BRANCH:** `main`
**EXPECTED_UPSTREAM:** `origin/main`

The production worktree was locally synchronized after #103 merge and reported:
- branch `main`;
- HEAD == `origin/main`;
- ahead/behind `0/0`;
- CLEAN;
- no source/test files modified.

The live `main` ref is authoritative and must be refreshed before any implementation task.

## Governance closeout

FT-GOV-002 is **CLOSED**.

Accepted final facts:
- PR #103 is MERGED;
- merge-produced `main` was verified after merge;
- repository/worktree closeout completed successfully;
- archive tags for historical A and D evidence remain preserved;
- exactly one production `main` worktree is authorized;
- the former governance worktree/branch may remain temporarily as historical cleanup-only state and is not a production worktree;
- no runtime/source/test implementation was changed by FT-GOV-002.

The required-check governance defect discovered during closeout is fixed: governance-only changes now trigger the protected PR-context `Build & Test (Apple Silicon arm64)` check.

## Active pull requests

| PR | Lifecycle | Role |
| --- | --- | --- |
| #102 | ACTIVE / OPEN / Draft | Separate MemoX durable-outbox integration. Do not modify in FT-DIAG-001. |

All prior diagnostic/recovery PRs #99–#101 remain closed historical evidence only.

## Incident truth

The stuck/blank/black WebView/Slot incident root cause remains **UNKNOWN**.

Preserved distinctions:
- restart/relaunch recovery is recovery evidence only;
- prior post-commit stall classification is diagnostic evidence only;
- per-slot reset/recovery behavior is not causal proof;
- no previous diagnostic/recovery PR is accepted as the production root-cause fix.

## Current diagnostic direction

The next authorized work is FT-DIAG-001: a **remote, read-only diagnostic architecture audit**.

The audit must prioritize:
1. key state machines and ownership transitions;
2. process/lifecycle/boundary maps;
3. existing probe/log coverage versus missing boundary observations;
4. cross-process and cross-generation correlation gaps;
5. a deterministic incident-diagnosis flow;
6. an evidence-based construction Gate.

Do not expand internal logging merely for volume. Prefer missing boundary observations and causal discriminators.

## Construction state

**RUNTIME CONSTRUCTION: NOT AUTHORIZED**

No new probe implementation, runtime fix, recovery behavior, tests, build/install/release action, or local incident capture is authorized until FT-DIAG-001 reaches a documented construction verdict.

## Non-blocking follow-up

The historical local/remote `v0.2.6` tag provenance discrepancy remains non-blocking and outside FT-DIAG-001.
