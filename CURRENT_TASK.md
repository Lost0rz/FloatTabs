# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Title:** Runtime Lifecycle / Memory redesign — Phase 2 Ready / Unread Decoupling  
**Status:** `ACTIVE / PHASE 2 IMPLEMENTATION — TEST-SCOPE CORRECTIVE AUTHORIZED`  
**Mode:** `EXECUTE`  
**Task class:** `HIGH-RISK ATTENTION / DURABLE UNREAD / RUNTIME LIFECYCLE HANDOFF`  
**Program contract:** `docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V2.md`  
**Phase 2 plan:** `docs/architecture/FloatTabs_Runtime_Lifecycle_Phase2_Ready_Unread_Decoupling_Plan_V1.md`  
**Scope reconciliation:** `docs/architecture/FT_RUNTIME_LIFECYCLE_PHASE2_SCOPE_RECONCILIATION_001.md`  
**JSC root cause:** `UNKNOWN`

## Authorization

Implement only the frozen Phase 2 Ready / Unread decoupling plan plus the accepted test-only scope reconciliation.

The focused read-only audit established that durable unread already exists independently from Runtime Attention; the required task is to stop transient Ready from indefinitely protecting a completed Runtime and to make persistent unread presentation derive from the durable unread owner.

The first construction attempt then exposed one stale cross-domain regression assertion in `FloatTabsTests/BrowserProfileDuplicateTests.swift`. That test-only mismatch is now reconciled without expanding production scope.

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
capture pre-transition facts
→ Runtime Attention completion transition
→ durable unread commit
→ unread presentation sync
→ generation-completed callback as applicable
→ protection-ended lifecycle restart
→ existing policy may later hibernate Runtime
```

Durable unread commit must precede the lifecycle restart/reclaim boundary.

## Authorized production files

Only:

- `FloatTabs/Web/WebAttentionCoordinator.swift`
- `FloatTabs/Panel/PanelController.swift`
- `FloatTabs/App/AppCoordinator.swift`
- `FloatTabs/MenuBar/StatusItemController.swift`

Do not add another Runtime/unread writer.

## Authorized test files

- `FloatTabsTests/WebAttentionCoordinatorTests.swift`
- `FloatTabsTests/WebAttentionLifecycleTests.swift`
- `FloatTabsTests/WebAttentionCrossFeatureTests.swift`
- `FloatTabsTests/WebAttentionPresentationTests.swift`
- `FloatTabsTests/UnreadResponseTests.swift` only when narrowly needed for durable-survival regression coverage
- `FloatTabsTests/BrowserProfileDuplicateTests.swift` **only** for the reconciled stale Ready-protection cross-domain regression assertion

### Corrective test-only boundary

In `BrowserProfileDuplicateTests.swift`, the executor may:

- rename `testSuccessfulDuplicateLeavesSourceRuntimeAndReadyAttentionUntouched` only if needed for semantic accuracy;
- change its historical Ready-protection assertion to the Phase 2 expectation that Ready is **not** Attention-protected;
- preserve its source WebView identity, source Attention bridge identity, Browser Profile identity, transient Ready-state, duplicate isolation and resident-runtime assertions.

The adjacent `testProtectedSourceDuplicateDoesNotAskSwitchConfirmation` uses a **Generating** source and must continue to verify protected behavior.

No Browser Profile production-code change, persistence/schema change, lifecycle-policy change or additional test-domain expansion is authorized by this corrective.

## Required implementation outcomes

1. Generating remains Attention-based Runtime protection.
2. Ready is no longer Attention-based Runtime protection.
3. Existing Ready state remains transient; do not remove it as a broad state-machine migration.
4. Hidden completion writes durable unread before normal lifecycle reclaim can resume.
5. Existing lifecycle fresh-plan restart is used; do not invent a second timer/policy path.
6. Rail unread remains driven by durable unread.
7. Status/menu unread count is driven by durable unread, with semantically truthful `unread` naming rather than `readyCount` naming.
8. Runtime reset/hibernate/recreation never clears durable unread.
9. Existing acknowledgement/visibility/response-identity behavior remains intact.
10. No Browser Profile/session/configuration production mutation.

## Verification

Required before handoff to independent audit:

- affected BrowserProfileDuplicate regression PASS after the narrow corrective;
- focused Phase 2 tests PASS;
- full XCTest PASS;
- Debug arm64 build PASS;
- Release arm64 build PASS;
- bounded real-runtime smoke from the frozen plan completed with evidence;
- exact implementation diff remains in scope;
- one Phase 2 implementation PR created/updated;
- required `Build & Test (Apple Silicon arm64)` passes on the literal PR head using `macmini-floattabs-01` before merge readiness can be claimed.

The construction executor must not mark human UI acceptance PASS. If all machine gates pass, stop for independent web audit and user-owned UI acceptance.

## Explicit non-scope / forbidden expansion

Do not modify without STOP/reconciliation:

- `FloatTabs/Web/ChatGPTAttentionBridge.swift`
- `FloatTabs/Web/ChatGPTResponseBridge.swift`
- `FloatTabs/Web/ChatGPTResponseExtraction.swift`
- `FloatTabs/Web/ChatGPTUnreadResponseCoordinator.swift`
- `FloatTabs/Persistence/UnreadResponseStore.swift`
- `FloatTabs/Web/SlotLifecycleCoordinator.swift`
- `FloatTabs/Web/WebViewPool.swift`
- Browser Profile / Tab production persistence schema or behavior
- attention visual-style renderer
- native notification delivery
- Runtime budget/ranking/timer policy
- release/version metadata

No user-data reset/deletion is authorized.

## STOP conditions

STOP and report evidence without workaround if:

- durable unread can be lost on hibernate/runtimeReset/recreation;
- reclaim can begin before durable unread commit;
- a Generating Slot becomes reclaimable;
- correct implementation requires any forbidden production file or schema change;
- new competing unread/Attention/lifecycle writer would be required;
- Phase 3 notification or Phase 4 policy work is required to make Phase 2 pass;
- focused/full tests, Debug/Release build, or required CI still fail after the authorized stale-test correction because of the Phase 2 change;
- any additional unauthorized test file proves to encode a materially conflicting semantic that requires mutation;
- overlapping unique work appears in an authorized file;
- human UI acceptance later fails.

## Delivery boundary

Resume the same implementation branch/workspace; do not discard the eight already-authorized uncommitted implementation files.

Implementation may commit/push and create or update exactly one Phase 2 implementation PR.

Do **not** merge, release, bump version, or start Phase 3/4.

Terminal machine state for the construction handoff is one of:

- `WAITING_FOR_INDEPENDENT_WEB_AUDIT`
- `WAITING_FOR_HUMAN_UI_ACCEPTANCE` when independent audit has already occurred elsewhere and human UI is the only remaining gate
- `STOP_RECONCILE` with exact evidence

Return a receipt containing governance route, skills used, execution topology/subagents, start/final/remote heads, changed paths, focused/full/build/smoke results, scope/STOP assessment, PR state, merge state, and final STATUS/TASK state.