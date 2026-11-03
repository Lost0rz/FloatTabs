# FloatTabs Current Status

**Status date:** 2026-11-03  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: ADAPTIVE LIFECYCLE — WP2 CLOSEOUT HARDENING / CI-TEST BOUNDARY FIRST**

Current task: `FT-ADAPTIVE-LIFECYCLE-RESTORE-001 / WP2-001` — **ACTIVE / CLOSEOUT HARDENING**.

Branch: `codex/adaptive-lifecycle-wp2-policy`  
Draft PR: `#195`  
Baseline: `main@2a52800f770266f7c901eb612a0b319ddca142df`  
Machine-verified WP2 implementation head: `1f33637b215cf742e20f5a8012818ac14ad459c9`  
Durable policy: `docs/architecture/FloatTabs_Runtime_Lifecycle_Policy_V7.md`

## Verified WP2 product state

```text
WP1=COMPLETE / HUMAN_ACCEPTED
WP2_STAGED_AUTOMATIC_POLICY=IMPLEMENTED
WP2_CORRECTIVE_A/B/C=PASS
AFFECTED_LIFECYCLE_WP1_REGRESSIONS=PASS
TEST_RUNNER_PROCESS_ISOLATION=SUPPORTED_AND_IMPLEMENTED
CANONICAL_INVENTORY_COVERAGE=PASS
SELF_HOSTED_IMPLEMENTATION_HEAD_CI=PASS
QA_DMG_IMPLEMENTATION_HEAD=PASS
NO_PRODUCTION_SOURCE_MUTATION_IN_RUNNER_CORRECTIVE=YES
HUMAN_INITIAL_SMOKE=PASS_NO_VISIBLE_ISSUE
HUMAN_EXTENDED_IDLE_OBSERVATION=DEFERRED_TO_LONG_RUN_DIAGNOSTICS
PR_195=OPEN_DRAFT_UNMERGED
WP3=NOT_STARTED
WP4=NOT_STARTED
```

The user has exercised the installed QA build and reports no visible issue in ordinary short-run use. Long-idle and long-duration behavior is intentionally no longer treated as a one-shot blocking manual session; final confidence will come from normal-use diagnostics collected over time.

## Closeout sequence — current authority

WP2 closeout is now intentionally ordered:

1. **CI / test boundary reconciliation — ACTIVE**
2. **Runtime diagnostics coverage audit / bounded augmentation — NOT STARTED**
3. **Normal-use observation window + exported diagnostics audit — NOT STARTED**
4. **Final exact-diff / literal-head reconciliation → merge decision → release DMG — BLOCKED**

Do not start diagnostics mutation before the CI/test boundary is reconciled and verified.

## Why the CI boundary is being corrected

The current PR workflow is too broad for the repository's control-plane workflow. `macos-ci.yml` includes product/test/project/workflow paths plus `AGENTS.md`, `CURRENT_STATUS.md`, and `CURRENT_TASK.md`. More importantly, GitHub `pull_request` path filters evaluate the PR's three-dot changed-file set rather than only the latest synchronization delta. Once an open PR already contains product changes, a later control-only commit can therefore retrigger the heavy job even when the new commit changes only control documents.

Observed consequence on PR #195: control-only reconciliation commits repeatedly occupied the self-hosted FloatTabs runner and reran Debug/Release/XCTest work after the implementation head was already machine-green.

The corrective must distinguish **latest PR synchronize delta** from **full PR merge coverage**. Merely deleting control files from `paths:` is not sufficient.

## Test-hygiene boundary

This phase may audit and retire stale test material, but **age is not evidence of obsolescence**.

A test may be removed or rewritten only when current product/architecture authority proves that it exercises a retired contract, duplicate historical harness, or superseded behavior and the removal does not create a current coverage gap. Current data/session safety, Browser Profile, lifecycle, focus/input, fullscreen, persistence, recovery, Attention, and WebKit integration contracts remain protected.

The previously preserved fixture-teardown experiment remains **SUPERSEDED FOR THIS INCIDENT / NOT FOR MERGE** and must not be mixed into WP2 merely to make the suite smaller.

## Diagnostics baseline already available

FloatTabs already has a production Runtime Diagnostics subsystem with:

- `RuntimeDiagnosticMode` Standard / Verbose;
- local JSONL writer and export;
- 7-day default retention;
- bounded segment rotation;
- optional long-term performance observation on a 60-second cadence;
- `diagnostics.performance_checkpoint` sampling;
- page-app counter delta/rate tracking;
- lifecycle memory-pressure and reclaim/protection events.

The next diagnostics stage must therefore be a **gap audit first**, not a replacement logging system. Add only fields/events needed to reconstruct WP2 retention/stage/runtime ownership/protection/reclaim/materialization/recovery behavior from normal-use logs.

## WP2 lifecycle safety boundary remains unchanged

- normal Runtime count is never a reclaim reason;
- Keep Loaded / Pinned is never automatically reclaimed by normal, warning, or critical FloatTabs policy;
- Automatic stages remain RECENT `<30s`, IDLE `>=30s && <600s`, LONG_IDLE `>=600s`;
- warning reclaims only eligible IDLE/LONG_IDLE Automatic progressively;
- critical may include RECENT Automatic but never Keep Loaded or hard-protected Runtime;
- Browser Profile/session/cookie/site data must never be cleared as recovery or diagnostics behavior;
- reload/reset/restart remains recovery evidence only, never root-cause proof.

## Merge / release gate

PR #195 stays Draft and unmerged while closeout hardening is active.

Final merge consideration requires:

1. CI/test boundary corrective verified;
2. diagnostics coverage judged sufficient and any bounded augmentation verified;
3. a normal-use diagnostics sample reviewed with no blocking lifecycle regression;
4. final literal-head exact-diff and required machine gate green.

Do not merge, release, or begin WP3/WP4 before those gates are reconciled.
