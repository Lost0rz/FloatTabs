# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Title:** Runtime Lifecycle / Memory redesign — Phase 2 Ready / Unread Decoupling  
**Status:** `ACTIVE / PHASE 2 IMPLEMENTATION — MACHINE VERIFIED / MERGE-READY AFTER LITERAL-HEAD CI`  
**Mode:** `EXECUTE`  
**Task class:** `HIGH-RISK ATTENTION / DURABLE UNREAD / RUNTIME LIFECYCLE HANDOFF`  
**Program contract:** `docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V3.md`  
**Phase 2 plan:** `docs/architecture/FloatTabs_Runtime_Lifecycle_Phase2_Ready_Unread_Decoupling_Plan_V2.md`  
**Scope reconciliation:** `docs/architecture/FT_RUNTIME_LIFECYCLE_PHASE2_SCOPE_RECONCILIATION_001.md`  
**JSC root cause:** `UNKNOWN`

## Authorization

Continue the same Phase 2 implementation and close it under Program Contract V3.

V3 changes the program acceptance cadence, not the Phase 2 product semantics or production scope:

```text
phase-local focused audit/freeze
→ bounded implementation
→ machine verification + required CI
→ merge
→ continue next architecture phase
...
Phases 1–6 complete
→ unified independent audit
→ one user-owned full human acceptance pass
```

Do not run or require Phase 2 human UI/runtime acceptance now. Do not retry CUA-driven ChatGPT live smoke as a construction gate. The prior Phase 2 independent audit is useful extra evidence but is no longer a routine per-phase merge gate under V3.

## Frozen Phase 2 semantic contract

```text
WebAttentionCoordinator
  idle       -> not Runtime-protected
  generating -> Runtime-protected
  ready      -> transient compatibility/diagnostic state only; not Runtime-protected

ChatGPTUnreadResponseCoordinator + UnreadResponseStore
  -> canonical durable unread owner
  -> survives hibernate/runtimeReset/fresh Runtime/relaunch
  -> canonical source for persistent rail/menu unread presentation
```

For a valid hidden completion:

```text
Runtime Attention completion transition
→ durable unread commit
→ unread presentation sync
→ protection-ended lifecycle restart
→ existing policy may later hibernate Runtime
```

Durable unread commit must precede reclaim.

## Authorized production files

Only:

- `FloatTabs/Web/WebAttentionCoordinator.swift`
- `FloatTabs/Panel/PanelController.swift`
- `FloatTabs/App/AppCoordinator.swift`
- `FloatTabs/MenuBar/StatusItemController.swift`

## Authorized test files

- `FloatTabsTests/WebAttentionCoordinatorTests.swift`
- `FloatTabsTests/WebAttentionLifecycleTests.swift`
- `FloatTabsTests/WebAttentionCrossFeatureTests.swift`
- `FloatTabsTests/WebAttentionPresentationTests.swift`
- `FloatTabsTests/UnreadResponseTests.swift` only when narrowly needed
- `FloatTabsTests/BrowserProfileDuplicateTests.swift` only for the reconciled Ready-protection assertion

The BrowserProfileDuplicate corrective remains test-only; the adjacent Generating-protected case must remain protected.

## Current observed implementation evidence

```text
BrowserProfileDuplicate corrective: 1 / 0 failures
targeted menu/unread projection regression: 4 / 0 failures
focused Phase 2: 241 executed / 3 skipped / 0 failures
full XCTest: 1073 executed / 3 skipped / 0 failures
Debug arm64: PASS
Release arm64: PASS
scope/data-safety audit: PASS
pre-V3 semantic head: 654eaef06b8c9e919a47bbe3842866033d9b69ea
pre-V3 required CI: 41263638003 / PASS / macmini-floattabs-01
pre-V3 QA DMG: 41263637956 / PASS
independent web audit: PASS on pre-V3 semantic product head; extra evidence under V3
human UI acceptance: DEFERRED TO PROGRAM FINAL
```

The V3 edits on PR #176 are Authority/docs-only. They must not mutate the already machine-verified Phase 2 product/test implementation.

## Required Phase 2 outcomes

1. Generating remains Attention-based Runtime protection.
2. Ready is no longer Attention-based Runtime protection.
3. Ready remains transient compatibility/diagnostic state.
4. Durable unread commit remains ordered before lifecycle reclaim can resume.
5. Existing lifecycle restart path is used; no second timer/policy path.
6. Rail/menu persistent unread derives from durable unread.
7. Runtime reset/hibernate/recreation does not clear durable unread.
8. Existing acknowledgement/visibility/response-identity semantics remain intact.
9. Durable unread mutations refresh both rail and menu/status projection.
10. No Browser Profile/session/configuration production mutation.

## Machine verification and delivery

For Phase 2, required product machine verification is already satisfied on the semantic implementation. Because this task now updates Authority/docs on the same open PR, repository-host gates still apply to the new literal PR head.

Before merge:

- confirm the V3 delta is Authority/docs-only beyond the existing Phase 2 implementation;
- required `Build & Test (Apple Silicon arm64)` must PASS on the final literal PR #176 head using `macmini-floattabs-01`;
- PR must remain mergeable with no required host/review blocker.

After those literal-head gates pass, **merge PR #176 without waiting for Phase 2 human acceptance or another per-phase formal independent audit**.

After merge, Phase 2 is structurally complete for program sequencing. The next program step is Phase 3 focused read-only audit and scope freeze before Phase 3 product mutation.

## Program-final acceptance — deferred

Do not set Phase 2 `HUMAN_UI_ACCEPTANCE=PASS/FAIL` as an isolated phase outcome.

The user will perform one full integrated runtime/UI acceptance pass only after:

1. Phases 1–6 are structurally implemented, machine-verified and merged;
2. one unified fresh independent audit of the combined architecture passes.

Until then:

`PROGRAM_HUMAN_ACCEPTANCE=PENDING`

## Explicit non-scope / forbidden expansion

Do not modify without STOP/reconciliation:

- `ChatGPTAttentionBridge.swift`
- `ChatGPTResponseBridge.swift`
- `ChatGPTResponseExtraction.swift`
- `ChatGPTUnreadResponseCoordinator.swift`
- `UnreadResponseStore.swift`
- `SlotLifecycleCoordinator.swift`
- `WebViewPool.swift`
- Browser Profile / Tab production persistence schema or behavior
- attention visual-style renderer
- native notification delivery
- Runtime budget/ranking/timer policy
- release/version metadata

No user-data reset/deletion is authorized.

## STOP conditions

STOP/reconcile if:

- final literal-head required CI fails for a new Phase 2/V3 reason;
- V3 Authority/docs edits unexpectedly mutate Phase 2 product/test semantics;
- Generating becomes reclaimable;
- code inspection/tests show reclaim may begin before durable unread commit;
- correct Phase 2 implementation requires forbidden production/schema scope;
- a competing unread/Attention/lifecycle writer would be required;
- overlapping unique work makes the writer unsafe.

Do **not** STOP merely because:

- Phase 2 human UI/runtime acceptance has not run;
- AI/CUA live smoke is absent or inconclusive;
- no new per-phase independent audit is run after the V3 control/docs-only cadence update.

## Delivery boundary

Keep all Phase 2 product/test semantics unchanged from the already verified implementation. The only remaining work on PR #176 is the V3 Authority/docs cadence update plus its literal-head repository-host gate.

Do not release, bump version, or begin Phase 3 product mutation inside PR #176.

Expected Phase 2 terminal sequence:

```text
final literal-head CI PASS
→ PR #176 merge
→ Phase 2 structurally complete
→ Phase 3 focused audit / freeze
```

Program-level independent audit and human acceptance remain deferred until Phases 1–6 are complete.