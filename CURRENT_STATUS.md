# FloatTabs Current Status

**Status date:** `2026-11-02`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 7 FINAL-CI TEST CORRECTIVE**

Current program/task: `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

Current execution state: `V5 CONTRACT FROZEN / PHASE 6 MERGED / PHASE 7 PRODUCT CORRECTIVE COMPLETE / FINAL-CI SINGLE TEST CORRECTIVE ACTIVE`.

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
PHASE_7_FULL_XCTEST_CORRECTIVE_RUN_41366231928=PASS
PHASE_7_QA_DMG_653=e1814064c4678efc66d1acf479c3f7e5af4f0439 / PASS
PHASE_7_MACOS_CI_1334=e1814064c4678efc66d1acf479c3f7e5af4f0439 / FAIL / ONE TEST
PHASE_7_FINAL_CI_TEST_CORRECTIVE=ACTIVE / TEST-ONLY
PROGRAM_HUMAN_ACCEPTANCE=NOT_STARTED
```

## Current authority

Program contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V5.md`

Phase 7 execution contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase7_Automatic_Lifecycle_Implementation_Contract_V1.md`

`CURRENT_TASK.md` is the only active mutation authorization.

## Final-CI finding

Literal head `e1814064...` passed:

- QA DMG #653;
- package-lock verification;
- Debug arm64 build;
- Release arm64 build;
- native Release architecture verification.

macOS CI #1334 then ran 1114 tests and produced exactly one failure:

```text
WebAttentionCrossFeatureTests
  testNonInteractivePresentationKeepsAutomaticLifecycleUntilInteractionReturns
  line 2047: XCTAssertNotNil failed
```

Fresh production inspection proves this is not a lifecycle defect:

1. `showFloatTabs()` calls `slotLifecycleCoordinator.setPanelVisible(true, activeProfile:)`;
2. current selected Slot activation cancels that Slot's inactive plan;
3. the test's `isAttentionUserVisible` fact is AppKit/test-environment dependent and is not the lifecycle ownership predicate;
4. therefore the test must not infer current Slot inactive-plan ownership from Attention interaction visibility.

The canonical assertion is:

```text
showFloatTabs() while ChatA selected
→ ChatA inactive-plan token == nil

select Plain
→ ChatA inactive-plan token != nil
```

This remains a test-only corrective. No production mutation is authorized or required.

## Exact-diff audit result

Fresh production exact-diff audit found no new issue:

- persistence authority is `runtimeRetentionPreference`;
- legacy residency is bounded compatibility projection only;
- Hot hidden host architecture is removed;
- Cold Runtime release no longer triggers website-cache cleanup;
- current UI/settings/shortcuts expose Automatic / Keep Loaded only;
- lifecycle ownership remains `SlotLifecycleCoordinator` → `WebViewPool`;
- Browser Profile/session data and Phase 6 restore boundaries are unchanged.

## Current execution order

```text
single test-only assertion corrective
→ full XCTest
→ user-authored final-verification control sync
→ literal-head macOS CI + QA DMG
→ bounded Real-Mac evidence where independently available
→ merge-readiness decision
```

## Safety boundary

The corrective must not:

- modify production lifecycle/runtime code;
- clear or migrate Browser Profile cookies/session/site data;
- restore Hot/Warm/Cold current policy;
- add hidden persistent WebViews;
- change release/version metadata.
