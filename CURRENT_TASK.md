# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Title:** Runtime Lifecycle / Memory redesign — Phase 2 Ready / Unread Decoupling  
**Status:** `ACTIVE / PHASE 2 IMPLEMENTATION — MACHINE VERIFICATION`  
**Mode:** `EXECUTE`  
**Task class:** `HIGH-RISK ATTENTION / DURABLE UNREAD / RUNTIME LIFECYCLE HANDOFF`  
**Program contract:** `docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V2.md`  
**Phase 2 plan:** `docs/architecture/FloatTabs_Runtime_Lifecycle_Phase2_Ready_Unread_Decoupling_Plan_V2.md`  
**Scope reconciliation:** `docs/architecture/FT_RUNTIME_LIFECYCLE_PHASE2_SCOPE_RECONCILIATION_001.md`  
**JSC root cause:** `UNKNOWN`

## Authorization

Continue the same Phase 2 implementation. V2 changes only the verification/acceptance cadence: timing-sensitive real-product interaction is now user-owned human acceptance after machine implementation, CI and independent audit are complete.

Do not retry CUA-driven ChatGPT live smoke as a construction gate.

## Frozen semantic contract

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

The preserved local workspace reports:

```text
9 authorized dirty files
BrowserProfileDuplicate corrective: 1 / 0 failures
focused Phase 2: 241 executed / 3 skipped / 0 failures
full XCTest: 1073 executed / 3 skipped / 0 failures
Debug arm64: PASS
Release arm64: PASS
first CUA smoke: visible_completion; durable unread correctly skipped
```

The first smoke result is not a Phase 2 failure and is not a STOP condition under V2.

## Required implementation outcomes

1. Generating remains Attention-based Runtime protection.
2. Ready is no longer Attention-based Runtime protection.
3. Ready remains transient compatibility/diagnostic state.
4. Durable unread commit remains ordered before lifecycle reclaim can resume.
5. Existing lifecycle restart path is used; no second timer/policy path.
6. Rail/menu persistent unread derives from durable unread.
7. Runtime reset/hibernate/recreation does not clear durable unread.
8. Existing acknowledgement/visibility/response-identity semantics remain intact.
9. No Browser Profile/session/configuration production mutation.

## Machine verification and delivery

The local construction executor is responsible for:

- focused tests PASS;
- full XCTest PASS;
- Debug arm64 PASS;
- Release arm64 PASS;
- exact changed-path/scope/data-safety audit;
- preserving current authorized local work while reconciling fresh Authority non-destructively;
- commit + push;
- exactly one Phase 2 implementation PR;
- literal-head `Build & Test (Apple Silicon arm64)` PASS on `macmini-floattabs-01`.

After required CI, stop for independent web audit.

The executor must **not** drive ChatGPT/UI interaction through CUA/automation to satisfy final real-product acceptance.

After independent web audit passes, state becomes:

`WAITING_FOR_HUMAN_UI_ACCEPTANCE`

## Human acceptance — user owned

The user will perform the timing-sensitive runtime/UI test in one concentrated acceptance pass after machine work is complete.

The human pass covers hidden completion, durable unread, normal Runtime reclaim, unread persistence, restore/session continuity, acknowledgement, Generating protection, and obvious focus/fullscreen regression.

Only explicit user feedback can set `HUMAN_UI_ACCEPTANCE=PASS` or `FAIL`.

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

- focused/full tests, build or required CI fails for a new Phase 2 reason;
- Generating becomes reclaimable;
- code inspection/tests show reclaim may begin before durable unread commit;
- correct implementation requires forbidden production/schema scope;
- a competing unread/Attention/lifecycle writer would be required;
- Phase 3/4 work is required;
- overlapping unique work makes the writer unsafe;
- later human acceptance reports an actual product failure contradicting the frozen semantics.

Do **not** STOP merely because AI-driven live smoke is absent or inconclusive.

## Delivery boundary

Resume the same dirty implementation workspace and preserve all nine authorized changes.

Do not merge, release, bump version, or start Phase 3/4 from the construction step.

Expected construction terminal state after commit/push/PR/CI is:

`WAITING_FOR_INDEPENDENT_WEB_AUDIT`

After independent audit passes:

`WAITING_FOR_HUMAN_UI_ACCEPTANCE`
