# FloatTabs Current Status

**Status date:** `2026-11-01`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — CONTRACT RECONCILED / PHASE 6 CLOSEOUT + PHASE 7 AUTOMATIC LIFECYCLE**

Current program/task: `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

Current execution state: `V5 CONTRACT FROZEN / PR #187 PHASE 6 CLOSEOUT PENDING / PHASE 7 IMPLEMENTATION NOT STARTED`.

## Canonical state

```text
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
JSC_ROOT_CAUSE=UNKNOWN

PHASE_1_SAFE_HIBERNATE_RESTORE=COMPLETE / MERGED
PHASE_2_READY_UNREAD_DECOUPLING=COMPLETE / MERGED
PHASE_3_NATIVE_COMPLETION_NOTIFICATION=COMPLETE / MERGED
PHASE_4_REFERENCE_DERIVED_RUNTIME_MANAGEMENT=DELIVERED FOUNDATION / TARGET POLICY SUPERSEDED BY V5 PHASE 7
PHASE_5_BACKGROUND_GENERATION_THRIFT=COMPLETE / MERGED

PHASE_6_PR=#187 OPEN / DRAFT / UNMERGED
PHASE_6_CURRENT_PRODUCT_HEAD=76c092523fe343eacc0592bfac25086da0d0d83d
PHASE_6_GATE0=COMPLETE / OUTCOME_A / NAVIGATION_BACKED_READINESS
PHASE_6_CORRECTIVE=C1-C4 FUNCTIONAL CORRECTIVE APPLIED
PHASE_6_REQUIRED_CI=PASS / RUN 1312 / HEAD 76c092523fe343eacc0592bfac25086da0d0d83d
PHASE_6_QA_DMG=PASS / RUN 637
PHASE_6_REAL_MAC_QA=STARTED ON CORRECTIVE BUILD
PHASE_6_EXACT_DIFF_FRESH_AUDIT=PENDING
PHASE_6_MERGE=BLOCKED PENDING BOUNDED SMOKE + FRESH EXACT_DIFF AUDIT

REAL_MAC_MEMORY_OBSERVATION=MULTIPLE LEGACY HOT CHATGPT RUNTIMES REMAIN RESIDENT / HIGH MEMORY
POLICY_ROOT_CAUSE=KNOWN / LEGACY HOT EXCLUDED FROM AUTOMATIC EVICTION BY DESIGN
PROGRAM_CONTRACT_AUDIT=V4 STOP FOR FINAL ACCEPTANCE
PROGRAM_CONTRACT=V5 ACCEPTED / FROZEN
TARGET_POLICY=AUTOMATIC + KEEP_LOADED
NORMAL_AUTOMATIC_TARGET=2
AUTOMATIC_INACTIVE_GRACE=30S
WARNING_AUTOMATIC_TARGET=1
CRITICAL_AUTOMATIC_TARGET=0

PHASE_7_CONTRACT=ACCEPTED / FROZEN
PHASE_7_IMPLEMENTATION=NOT_STARTED
PHASE_7_PREDECESSOR_GATE=MERGE PR #187 FIRST
PHASE_7_NEXT_USER_START_REQUIRED=YES
PROGRAM_HUMAN_ACCEPTANCE=PENDING
CI_RUNNER=macmini-floattabs-01 / self-hosted / macOS / ARM64 / mac-mini-ci
```

## Contract reconciliation result

Fresh source/contract audit found that V4's Phase 4 policy is a hybrid model rather than the intended final automatic lifecycle:

- Hot is a permanent normal/critical automatic-budget exclusion;
- Warm/Cold remain separate persisted classes with independent timers;
- the current Tab menu still exposes Hot/Warm/Cold;
- Performance Settings still exposes Warm retention and Cold release delay;
- inactive Hot keeps a hidden attached WebView host;
- normal managed target `3` is an unmeasured reference-derived assumption;
- Phase 6 explicitly froze those semantics, so restore work alone cannot satisfy the final memory objective.

The Phase 6 restore architecture remains valid. The program now adds one final structural Phase 7 to retire the legacy residency product model.

## Current authority

Program contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V5.md`

Phase 6 PR-scoped implementation contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Implementation_Contract_V1.md`

Phase 7 implementation contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase7_Automatic_Lifecycle_Implementation_Contract_V1.md`

`CURRENT_TASK.md` remains the only active mutation authorization.

## Phase 7 frozen target

```text
legacy Hot            -> Keep Loaded compatibility mapping
legacy Warm / Cold    -> Automatic compatibility mapping
new Slot              -> Automatic

Automatic inactive
→ 30s grace
→ normal target 2 / warning 1 / critical 0
→ LRU eligible reclaim
→ existing WebViewPool hibernate
→ Phase 6 restore on next use

Keep Loaded
→ no proactive launch materialization
→ retained during normal operation when already live
→ no hidden Hot host presentation
→ critical pressure may reclaim if inactive and otherwise unprotected
```

Hard protection remains active/presented, fullscreen, supplemental-visible, Attention generating and allowed active/pending background media.

Runtime reclaim no longer authorizes legacy Cold-based website-cache cleanup.

## PR #187 disposition

PR #187 remains Phase 6 only. Do not add Phase 7 product-source mutation to it.

Before merge:

1. finish bounded Real-Mac restore smoke on the corrective head;
2. reconcile the known comment-only exact-diff churn;
3. obtain fresh independent exact-diff audit PASS;
4. merge only if those Phase 6 gates pass.

The Real-Mac high-memory observation does not invalidate the Phase 6 restore implementation; it invalidates V4 as the final program policy.

## Next action

Hold Phase 7 product mutation until PR #187 is dispositioned/merged and the user explicitly starts Phase 7 construction.

Then create a fresh Phase 7 branch/worktree from updated `main` and execute the frozen Phase 7 contract WP1-WP5.
