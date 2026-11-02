# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Title:** Runtime Lifecycle / Memory redesign — Phase 7 automatic lifecycle retirement  
**Status:** `ACTIVE / FINAL LITERAL-HEAD VERIFICATION`  
**Mode:** `VERIFY / SELF-AUDIT TO MERGE-READY`  
**Task class:** `WEB RUNTIME / LIFECYCLE / MEMORY`  
**JSC root cause:** `UNKNOWN`

## Authorization state

Phase 6 PR #187 is merged. Phase 7 PR #188 remains `OPEN / DRAFT / UNMERGED`.

Phase 7 product construction, bounded product corrective, broad test-contract corrective, and the final single-test CI corrective are complete. This paired control sync establishes the final user-authored PR head for literal-head verification.

No further mutation is authorized unless the exact final head produces new machine evidence requiring a reconciled corrective.

## Current authority

Program contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V5.md`

Phase 7 frozen execution contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase7_Automatic_Lifecycle_Implementation_Contract_V1.md`

Implementation branch:

`codex/ft-runtime-lifecycle-phase7-automatic-001`

Current PR:

`#188 OPEN / DRAFT / UNMERGED`

Last verified corrective head before this paired control sync:

`212546f692738b396f0e1cb14d6a43f66ac109e7`

Final literal head:

`the branch head produced by this CURRENT_TASK.md control commit`

## Frozen product policy

```text
Automatic   (default)
Keep Loaded

normal target   = 2 Automatic runtimes
inactive grace  = 30 seconds
warning target  = 1
critical target = 0
```

Hard protection remains active/presented, fullscreen, supplemental-visible, Attention generating, active/pending allowed-background-media, and current materialization/restoring ownership.

Legacy Hot/Warm/Cold remains compatibility-only. Browser Profile/session/cache safety and Phase 6 restore ownership remain unchanged.

## Completed corrective evidence

### Product / architecture

- current Hot/Warm/Cold shortcut controls retired;
- Runtime Retention UI is Automatic / Keep Loaded;
- Warm/Cold timing settings no longer drive current lifecycle;
- Hot hidden WebView host architecture removed;
- historical 120-second production hidden-active retention removed;
- Cold runtime release no longer owns website-cache cleanup;
- canonical persistence is `runtimeRetentionPreference` with bounded legacy projection;
- lifecycle writer remains `SlotLifecycleCoordinator` using existing `WebViewPool` release/hibernate boundaries.

### Machine-test corrective

Initial stale Phase 4/5 Hot/Warm/Cold tests were rewritten/retired only where machine evidence proved obsolete current-product semantics. No production file changed during the broad machine-test corrective.

The final formal CI failure on earlier head `e1814064...` was one environment-sensitive assertion in `WebAttentionCrossFeatureTests`. The accepted ownership contract is now tested directly:

```text
showFloatTabs() while ChatA is selected
→ ChatA has no inactive plan

select Plain
→ ChatA gains an Automatic inactive plan
```

Final corrective run:

```text
RUN=41367458150
ONE_TEST_FILE_SCOPE=PASS
FULL_XCTEST=PASS
TEMP_WORKFLOW_REMOVED=YES
FINAL_CORRECTIVE_COMMIT=212546f692738b396f0e1cb14d6a43f66ac109e7
```

### Exact-diff self-audit

PASS. No new production issue found:

- no active Hot/Warm/Cold product policy;
- no second lifecycle writer;
- no hidden Runtime continuity workaround;
- no destructive Browser Profile/session/cache behavior;
- no Phase 6 restore redesign;
- compatibility seams remain bounded.

## Final verification gates

The exact final PR head created by this paired control sync must pass all of the following without further mutation:

1. required `Build & Test (Apple Silicon arm64)` on the established self-hosted Apple Silicon runner;
2. Debug arm64 build;
3. Release arm64 build;
4. native Release architecture verification;
5. Unit tests;
6. QA DMG on the same head;
7. fresh PR identity check proves head unchanged and PR still unmerged;
8. exact-diff audit remains PASS.

Checks from earlier heads do not satisfy these gates.

## Real-Mac / human boundary

Phase 7 WP5 Real-Mac lifecycle evidence remains an independent gate where available. The repository's existing benchmark harness is historical Hot/Warm/Cold Stage 5E and must not be represented as Phase 7 Automatic/Keep Loaded acceptance evidence.

Human UI/runtime acceptance remains `NOT_STARTED` until explicitly performed by the user.

## STOP conditions

If final-head CI or QA proves a new product defect, STOP and reconcile before any production mutation. Do not alter Browser Profile/session data, cache ownership, restore architecture, lifecycle ownership, or release/version metadata without new authority.

## Current execution state

```text
PHASE7_PR=#188_OPEN_DRAFT_UNMERGED
PHASE7_PRODUCT_CORRECTIVE=COMPLETE
PHASE7_MACHINE_TEST_CORRECTIVE=COMPLETE
PHASE7_FINAL_TEST_CORRECTIVE=COMPLETE
PHASE7_FINAL_CORRECTIVE_XCTEST=PASS / RUN 41367458150
PHASE7_EXACT_DIFF_AUDIT=PASS
CURRENT_STAGE=FINAL_LITERAL_HEAD_VERIFICATION
CURRENT_LITERAL_HEAD=THIS_CONTROL_COMMIT
NEXT_REQUIRED_GATE=SAME_HEAD_MACOS_CI_AND_QA_DMG
PROGRAM_HUMAN_ACCEPTANCE=NOT_STARTED
```
