# FloatTabs Runtime Lifecycle — Phase 2 Ready / Unread Decoupling Plan V2

**Program:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Phase:** `2 — Ready / Unread Decoupling`  
**Status:** `HISTORICAL PHASE 2 V2 PLAN / NOT CURRENT WORKFLOW AUTHORITY`  
**Original historical successor to:** `FloatTabs_Runtime_Lifecycle_Phase2_Ready_Unread_Decoupling_Plan_V1.md`  
**Parent contract:** `FloatTabs_Runtime_Lifecycle_Memory_Contract_V2.md`

## 1. Objective

Phase 2 keeps the V1 architecture and implementation boundary unchanged:

- `generating` remains Runtime-protecting;
- transient `ready` no longer protects Runtime residency;
- durable unread remains owned by `ChatGPTUnreadResponseCoordinator` + `UnreadResponseStore`;
- persistent rail/menu unread presentation derives from durable unread;
- durable unread commit precedes any protection-ended lifecycle restart.

V2 changes the **verification cadence only**. Timing-sensitive real-product interaction is user-owned human acceptance and is no longer a construction-executor / CUA gate.

## 2. Frozen semantic contract

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
capture pre-transition Attention state + actual visibility facts
→ Runtime Attention completion transition
→ durable unread commit
→ unread presentation sync
→ generation-completed callback as applicable
→ protection-ended lifecycle restart
→ existing policy may later hibernate Runtime
```

Durable unread commit must precede the reclaim boundary.

## 3. Production and test scope

Authorized production files remain exactly:

- `FloatTabs/Web/WebAttentionCoordinator.swift`
- `FloatTabs/Panel/PanelController.swift`
- `FloatTabs/App/AppCoordinator.swift`
- `FloatTabs/MenuBar/StatusItemController.swift`

Authorized tests remain:

- `FloatTabsTests/WebAttentionCoordinatorTests.swift`
- `FloatTabsTests/WebAttentionLifecycleTests.swift`
- `FloatTabsTests/WebAttentionCrossFeatureTests.swift`
- `FloatTabsTests/WebAttentionPresentationTests.swift`
- `FloatTabsTests/UnreadResponseTests.swift` only when narrowly needed for durable-survival regression coverage
- `FloatTabsTests/BrowserProfileDuplicateTests.swift` only for the accepted stale Ready-protection assertion reconciliation

No new production scope is created by V2.

## 4. Machine verification gate

Construction must complete:

1. focused Phase 2 correctness tests, including the reconciled BrowserProfileDuplicate case;
2. full XCTest with no new Phase 2-attributable failures;
3. Debug arm64 build PASS;
4. Release arm64 build PASS;
5. exact diff / data-safety review confirming only authorized files and no user-data/schema mutation;
6. exact-head `Build & Test (Apple Silicon arm64)` PASS on `macmini-floattabs-01`;
7. independent web audit PASS.

After these machine gates pass, the phase enters:

`WAITING_FOR_HUMAN_UI_ACCEPTANCE`

The construction executor must not use CUA, Playwright, scripted clicks, or equivalent automation to manufacture final real-product interaction acceptance.

## 5. Human runtime/UI acceptance — user owned

Timing-sensitive real-product validation is performed by the user in one concentrated acceptance pass after implementation, CI and independent audit are complete.

Minimum human checks:

1. start a ChatGPT generation, then hide/switch away before completion;
2. completed hidden response shows durable unread on the Tab rail;
3. menu-bar unread badge remains after the completed Slot Runtime is reclaimed;
4. returning to the Slot restores the same conversation/session;
5. merely selecting while not actually presented does not prematurely clear unread;
6. actual presentation clears unread according to existing acknowledgement rules;
7. a currently generating inactive Slot is not reclaimed;
8. no obvious focus/fullscreen/session regression.

Human feedback may be PASS or may open a bounded corrective loop. AI tools/logs may assist diagnosis after a user-reported failure, but cannot set `HUMAN_UI_ACCEPTANCE=PASS`.

## 6. Explicit non-scope

Phase 2 still does not include:

- detector/bridge/response extraction redesign;
- unread persistence schema/store redesign;
- `SlotLifecycleCoordinator` timer/policy changes;
- `WebViewPool` hibernate/restore redesign;
- Browser Profile/session/configuration production changes;
- native completion notifications (Phase 3);
- Runtime Budget/ranking or strict scale benchmark (Phase 4);
- release/version bump.

No user-data reset/deletion is authorized.

## 7. STOP conditions

STOP/reconcile if:

- focused/full tests or required CI fail for a new Phase 2 reason;
- Generating becomes reclaimable;
- code ordering permits reclaim before durable unread commit;
- correct implementation requires forbidden production scope or schema changes;
- another canonical unread/lifecycle writer would be required;
- Phase 3/4 work leaks into the implementation;
- overlapping unique work makes the writer unsafe;
- later human acceptance reports a real product failure contradicting the frozen semantics.

A missing AI-driven live smoke is **not** a STOP condition under V2.

## 8. Historical acceptance context

The Phase 2 work originally separated machine regression evidence from user-owned macOS interaction acceptance. This record does not define present PR merge readiness, required CI breadth, or approval state.

Current product regressions remain: generating Runtime protection, durable unread commit before reclaim, no second canonical unread/lifecycle writer, and preservation of Browser Profile/session data.
