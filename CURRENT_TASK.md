# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Title:** Runtime Lifecycle / Memory redesign — Phase 7 automatic lifecycle retirement  
**Status:** `ACTIVE / FINAL-CI TEST CORRECTIVE`  
**Mode:** `BOUNDED TEST CORRECTIVE / VERIFY / SELF-AUDIT TO MERGE-READY`  
**Task class:** `WEB RUNTIME / LIFECYCLE / MEMORY`  
**JSC root cause:** `UNKNOWN`

## Authorization state

Phase 6 PR #187 is merged. Phase 7 PR #188 remains `OPEN / DRAFT / UNMERGED`.

The Phase 7 product corrective is complete. A literal-head final CI run on `e1814064c4678efc66d1acf479c3f7e5af4f0439` passed Debug, Release, native architecture and QA DMG, but exposed one environment-sensitive test assertion. The user has authorized continuing remote construction; this task now authorizes one bounded test-only final-CI corrective.

No product scope is reopened.

## Current authority

Program contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V5.md`

Phase 7 execution contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase7_Automatic_Lifecycle_Implementation_Contract_V1.md`

Implementation branch:

`codex/ft-runtime-lifecycle-phase7-automatic-001`

## Frozen product policy

```text
Automatic   (default)
Keep Loaded

normal target   = 2 Automatic runtimes
inactive grace  = 30 seconds
warning target  = 1
critical target = 0
```

Legacy Hot/Warm/Cold remains compatibility-only. Browser Profile/session/cache safety and Phase 6 restore ownership remain unchanged.

## Fresh final-CI evidence

Literal head `e1814064...`:

```text
QA_DMG_653=PASS
DEBUG_ARM64=PASS
RELEASE_ARM64=PASS
NATIVE_RELEASE_ARCH=PASS
MACOS_CI_1334_UNIT_TESTS=FAIL / 1 OF 1114
```

Only failing test:

`WebAttentionCrossFeatureTests.testNonInteractivePresentationKeepsAutomaticLifecycleUntilInteractionReturns`

Failure:

`XCTAssertNotNil(controller.debugInactivePlanToken(slotID: slot.id))`

The assertion was conditional on `isAttentionUserVisible == false`. That relationship is invalid for lifecycle ownership: `showFloatTabs()` marks the selected Slot presented in `SlotLifecycleCoordinator`, which cancels its inactive plan even when AppKit interaction visibility in a test host is not yet true.

## Authorized corrective

Only `FloatTabsTests/WebAttentionCrossFeatureTests.swift` may change for this final-CI corrective, plus temporary self-removing remote execution machinery and the two control files.

Required semantic change:

```text
After showFloatTabs() with ChatA selected:
  ChatA inactive-plan token == nil

After selecting Plain:
  ChatA inactive-plan token != nil
```

Do not branch lifecycle-plan expectations on `isAttentionUserVisible`.

## Verification gates

After the single test-only correction:

1. test-only diff/scope hygiene PASS;
2. full XCTest PASS;
3. temporary corrective machinery removed;
4. user-authored control sync establishes final literal head;
5. current literal head passes macOS CI `Build & Test (Apple Silicon arm64)`;
6. QA DMG passes on that same head;
7. exact-diff audit remains PASS;
8. Real-Mac lifecycle evidence remains an independent acceptance gate where available.

Human UI/runtime acceptance remains `NOT_STARTED`.

## STOP conditions

STOP before production mutation if the single corrected test still fails in a way that proves a real lifecycle defect. Do not alter runtime ownership, Browser Profile/session data, restore behavior, cache policy, or release metadata without a new reconciled authority.

## Current execution state

```text
PHASE7_PR=#188_OPEN_DRAFT_UNMERGED
PHASE7_PRODUCT_CORRECTIVE=COMPLETE
FINAL_HEAD_E181_QA=PASS
FINAL_HEAD_E181_CI=FAIL_ONE_TEST
CURRENT_STAGE=FINAL_CI_TEST_CORRECTIVE
AUTHORIZED_MUTATION=ONE_TEST_ONLY
NEXT_REQUIRED_GATE=FULL_XCTEST_THEN_FINAL_LITERAL_HEAD_CI_QA
PROGRAM_HUMAN_ACCEPTANCE=NOT_STARTED
```
