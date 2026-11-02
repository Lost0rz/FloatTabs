# FloatTabs Current Status

**Status date:** `2026-11-02`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 7 FINAL VERIFICATION**

Current program/task: `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

Current execution state: `V5 CONTRACT FROZEN / PHASE 6 MERGED / PHASE 7 PRODUCT + MACHINE CORRECTIVES COMPLETE / FINAL VERIFICATION ACTIVE`.

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
PHASE_7_TEST_CORRECTIVE_HEAD=cc924603e876edbc7f9789edc0e4a9180cfa8012
PHASE_7_FULL_XCTEST=PASS / CORRECTIVE RUN 41366231928
PHASE_7_NET_CORRECTIVE_DIFF=CONTROL DOCS + TESTS ONLY AFTER f3ac1d98
PHASE_7_FINAL_LITERAL_CHECKS=REQUIRED ON CURRENT PR HEAD
PROGRAM_HUMAN_ACCEPTANCE=NOT_STARTED
CI_RUNNER=macmini-floattabs-01 / self-hosted / macOS / ARM64 / mac-mini-ci
```

## Current authority

Program contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V5.md`

Phase 7 execution contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase7_Automatic_Lifecycle_Implementation_Contract_V1.md`

`CURRENT_TASK.md` is the only active mutation authorization.

## Phase 7 product state

The bounded product corrective is complete:

- current Hot/Warm/Cold keyboard shortcut bindings are removed;
- Shortcuts Settings no longer exposes the retired Mode section;
- Runtime Retention presents only Automatic / Keep Loaded;
- dead Hot-only hidden WebView host ownership is removed;
- production hidden-active grace no longer adds a historical 120-second retention layer;
- legacy `setResidency` remains bounded compatibility input only and does not project current-product HUD semantics;
- Runtime reclaim remains separate from website cache/session cleanup;
- Browser Profile/session ownership and Phase 6 restore boundaries remain unchanged.

## Machine-test corrective result

CI run `1322` first exposed obsolete Hot/Warm/Cold tests. The corrective was intentionally test-only rather than restoring retired production APIs.

Fresh diagnostics progressively reduced the suite to one final stale global-count assertion. Production inspection proved that `showFloatTabs()` calls `setPanelVisible(true, activeProfile:)` and current Slot activation cancels its own inactive plan; the observed remaining global plan belonged to a different inactive Slot. The final test therefore validates per-Slot plan ownership rather than total plan count.

Final bounded corrective evidence:

```text
CORRECTIVE_WORKFLOW_RUN=41366231928
TEST_ONLY_SCOPE_GATE=PASS
FULL_XCTEST=PASS
TEMP_CORRECTIVE_HELPER=REMOVED
TEMP_CORRECTIVE_WORKFLOW=REMOVED
ACCIDENTAL_TEMP_REMOTE_BRANCHES=REMOVED
```

Net diff from product-corrective head `f3ac1d98...` to verified test head `cc924603...` contains only:

- `CURRENT_STATUS.md`
- `CURRENT_TASK.md`
- eight `FloatTabsTests/*.swift` files

No production file changed during the machine-test corrective.

## Final execution order

```text
current control sync
→ literal-head required macOS CI
→ literal-head QA DMG
→ bounded Real-Mac lifecycle evidence where remotely provable
→ fresh exact-diff self-audit
→ merge-readiness decision
```

The current PR head itself is the authority for literal-head CI/QA. A bot-generated intermediate head produced `action_required` check records with no jobs; those are trigger semantics, not code failures, and are superseded by the user-authored final-verification head.

## Safety boundary

Final verification must not:

- clear or migrate Browser Profile cookies/session/site data;
- add a second lifecycle writer;
- restore Hot/Warm/Cold as current product policy;
- add hidden persistent WebViews;
- modify release/version metadata;
- treat intermediate-head CI/QA as evidence for a different literal head.
