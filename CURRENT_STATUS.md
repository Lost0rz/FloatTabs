# FloatTabs Current Status

**Status date:** `2026-11-02`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 7 FINAL VERIFICATION**

Current program/task: `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

Current execution state: `V5 CONTRACT FROZEN / PHASE 7 PRODUCT + TEST CORRECTIVES COMPLETE / FINAL LITERAL-HEAD VERIFICATION ACTIVE`.

## Canonical state

```text
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
JSC_ROOT_CAUSE=UNKNOWN

PROGRAM_CONTRACT=V5 ACCEPTED / FROZEN
TARGET_POLICY=AUTOMATIC + KEEP_LOADED
NORMAL_AUTOMATIC_TARGET=2
AUTOMATIC_INACTIVE_GRACE=30S
WARNING_AUTOMATIC_TARGET=1
CRITICAL_AUTOMATIC_TARGET=0

PHASE_7_CONTRACT=ACCEPTED / FROZEN / RECONCILED
PHASE_7_BRANCH=codex/ft-runtime-lifecycle-phase7-automatic-001
PHASE_7_PR=#188 OPEN / DRAFT / UNMERGED
PHASE_7_PRODUCT_CORRECTIVE=COMPLETE
PHASE_7_MACHINE_TEST_CORRECTIVE=COMPLETE
PHASE_7_FINAL_SINGLE_TEST_CORRECTIVE=COMPLETE
PHASE_7_FINAL_SINGLE_TEST_CORRECTIVE_HEAD=212546f692738b396f0e1cb14d6a43f66ac109e7
PHASE_7_FINAL_CORRECTIVE_XCTEST=PASS / RUN 41367458150
PHASE_7_EXACT_DIFF_AUDIT=PASS / NO NEW PRODUCTION ISSUE
FINAL_LITERAL_HEAD=PAIRED_CONTROL_SYNC_HEAD
PROGRAM_HUMAN_ACCEPTANCE=NOT_STARTED
```

## Current authority

Program contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V5.md`

Phase 7 execution contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase7_Automatic_Lifecycle_Implementation_Contract_V1.md`

`CURRENT_TASK.md` is the only active mutation authorization.

## Corrective closeout

Phase 7 product corrective is complete and preserves the frozen product model:

- current Runtime Retention is `Automatic` / `Keep Loaded` only;
- new Slots default Automatic;
- normal / warning / critical Automatic targets remain `2 / 1 / 0`;
- Automatic inactivity grace remains 30 seconds;
- Hot/Warm/Cold are compatibility-only and no longer current product UI/settings/shortcut policy;
- Hot-only hidden WebView hosts are removed;
- Runtime reclaim does not trigger legacy Cold website-cache cleanup;
- Browser Profile/session data and Phase 6 restore ownership remain unchanged.

The final formal CI failure on earlier head `e1814064...` was reduced to one environment-sensitive test assertion. Production inspection proved selected-Slot lifecycle ownership was correct: `showFloatTabs()` marks the selected Slot presented and cancels its inactive plan independently of AppKit Attention interaction visibility. The bounded correction therefore changed only the test contract:

```text
showFloatTabs() with ChatA selected
→ ChatA inactive-plan token == nil

select Plain
→ ChatA inactive-plan token != nil
```

Verified final corrective evidence:

```text
CORRECTIVE_RUN=41367458150
SINGLE_TEST_FILE_SCOPE=PASS
FULL_XCTEST=PASS
TEMP_CORRECTIVE_WORKFLOW=REMOVED
PRODUCTION_FILES_CHANGED_BY_FINAL_CORRECTIVE=0
```

## Fresh exact-diff audit

Fresh code-level audit remains PASS:

- persistence authority is `runtimeRetentionPreference`;
- legacy residency is bounded compatibility projection only;
- lifecycle ownership remains `SlotLifecycleCoordinator` → `WebViewPool`;
- no second lifecycle writer exists;
- no hidden persistent Runtime continuity workaround remains;
- no Cold→website-cache cleanup coupling remains;
- current UI/settings/shortcuts do not restore Hot/Warm/Cold product controls;
- Browser Profile/session safety is preserved;
- Phase 6 restore boundary is not redesigned.

## Final verification gate

The paired `CURRENT_STATUS.md` / `CURRENT_TASK.md` control sync establishes the final user-authored PR head. No further repository mutation is authorized unless that exact head exposes a new defect.

Merge-readiness requires the same final literal head to pass:

1. `Build & Test (Apple Silicon arm64)` on the project self-hosted runner;
2. QA DMG;
3. fresh identity check showing PR head unchanged;
4. exact-diff audit remains PASS.

Phase 7 Real-Mac WP5 evidence remains independent: the existing benchmark harness is historical Hot/Warm/Cold Stage 5E and is not accepted as Phase 7 Automatic/Keep Loaded evidence. Human UI/runtime acceptance remains `NOT_STARTED`.

## Safety boundary

Do not:

- mutate production code unless final-head machine evidence proves a new defect and authority is reconciled first;
- clear or migrate Browser Profile cookies/session/site data;
- restore Hot/Warm/Cold as current policy;
- add hidden persistent WebViews;
- change release/version metadata;
- treat checks from any earlier head as evidence for the final literal head.
