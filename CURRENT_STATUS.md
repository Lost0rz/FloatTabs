# FloatTabs Current Status

**Status date:** `2026-11-01`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 7 AUTOMATIC LIFECYCLE CONSTRUCTION**

Current program/task: `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

Current execution state: `V5 CONTRACT FROZEN / PHASE 6 MERGED / PHASE 7 IMPLEMENTATION ACTIVE`.

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
PHASE_6_PERCEIVED_FAST_RESTORE=COMPLETE / MERGED
PHASE_6_PR=#187 MERGED
PHASE_6_MERGE_COMMIT=54f2e43b0fbc224affa52d9662ac2ba5aa5b963c
PHASE_6_PRODUCT_HEAD=76c092523fe343eacc0592bfac25086da0d0d83d
PHASE_6_LITERAL_HEAD=0cc37d9f892cc2b1ff730e14a0ae9ff3418fbc4d
PHASE_6_REQUIRED_CI=PASS / RUN 1313
PHASE_6_QA_DMG=PASS / RUN 638
PHASE_6_FRESH_SELF_AUDIT=PASS / USER_AUTHORIZED / REVIEW 5728825453

PROGRAM_CONTRACT=V5 ACCEPTED / FROZEN
TARGET_POLICY=AUTOMATIC + KEEP_LOADED
NORMAL_AUTOMATIC_TARGET=2
AUTOMATIC_INACTIVE_GRACE=30S
WARNING_AUTOMATIC_TARGET=1
CRITICAL_AUTOMATIC_TARGET=0

PHASE_7_CONTRACT=ACCEPTED / FROZEN
PHASE_7_IMPLEMENTATION=ACTIVE
PHASE_7_BRANCH=codex/ft-runtime-lifecycle-phase7-automatic-001
PHASE_7_BASE=main@54f2e43b0fbc224affa52d9662ac2ba5aa5b963c
PROGRAM_HUMAN_ACCEPTANCE=PENDING
CI_RUNNER=macmini-floattabs-01 / self-hosted / macOS / ARM64 / mac-mini-ci
```

## Current authority

Program contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V5.md`

Phase 7 execution contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase7_Automatic_Lifecycle_Implementation_Contract_V1.md`

`CURRENT_TASK.md` is the only active mutation authorization.

## Phase 7 target

```text
legacy Hot         -> Keep Loaded compatibility mapping
legacy Warm / Cold -> Automatic compatibility mapping
new Slot           -> Automatic

Automatic inactive
→ 30s grace
→ normal target 2 / warning 1 / critical 0
→ deterministic LRU reclaim
→ existing WebViewPool hibernate
→ Phase 6 restore on next use

Keep Loaded
→ no proactive launch materialization
→ retained during normal operation when already live
→ no hidden Hot host presentation
→ critical pressure may reclaim if inactive and otherwise unprotected
```

Hard protection remains active/presented, fullscreen, supplemental-visible, Attention generating, allowed active/pending background media, and current materialization/restoring ownership.

Runtime reclaim does not authorize website-cache/session cleanup.

## Current execution order

```text
WP1 canonical model + compatibility
→ WP2 lifecycle policy + container simplification
→ WP3 UI/settings retirement
→ WP4 recovery/cache integration
→ WP5 machine + Real-Mac evidence
→ fresh self-audit
→ merge-readiness decision
```

Phase 7 must not change release/version or clear Browser Profile/cookie/session data.
