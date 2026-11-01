# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Title:** Runtime Lifecycle / Memory redesign — Phase 5 long-running background generation thrift  
**Status:** `WAITING_FOR_PHASE_5_MERGE_GATE`  
**Mode:** `VERIFY / MERGE GATE`  
**Task class:** `WEB RUNTIME / ATTENTION OBSERVATION THRIFT`  
**JSC root cause:** `UNKNOWN`

## Authorized objective

Reduce FloatTabs-owned observation work during long-running background ChatGPT generation without interrupting provider generation, weakening Runtime protection, changing Browser Profile/session semantics or moving canonical ownership.

## Delivered implementation

PR #183 delivers the Phase 5 mechanism on semantic implementation head:

`e36589d4729f86b2e76609bcb699107e50f63919`

Delivered behavior:

```text
visible / unknown page
→ 2s liveness fallback

hidden page + generation age < 30s
→ 2s fallback

hidden page + generation age >= 30s
→ 5s fallback

first false probe
→ existing 250ms confirmation
→ second current-context false required for synthetic completion
```

The liveness probe now carries `document.visibilityState` only as local bridge scheduling metadata. It does not replace `PanelController` product/presentation visibility truth.

The implementation does not alter the primary event-driven ChatGPT detector, provider generation, Runtime hibernate/release behavior or persistent user data.

## Ownership / safety preserved

- `WebAttentionCoordinator` remains sole Attention state authority.
- `.generating` remains Runtime-protecting for the complete generation.
- `SlotLifecycleCoordinator` remains sole lifecycle release/hibernate executor.
- `WebViewPool` remains Runtime mechanism/bridge-lifetime owner; its hibernate/restore contract is unchanged.
- existing document token, semantic generation, physical Runtime epoch, watchdog-generation, WebView identity and timeout/stale-callback guards remain in force.
- natural completion still stops the watchdog and does not require the fallback probe.
- no Browser Profile/session/configuration/schema/reset/delete behavior changed.
- no private WebKit API, Phase 6 work or release/version mutation was introduced.

## Architecture/document reconciliation

The same PR also closes the stale authority-routing gap identified after Phase 4:

- current program contract advanced to `FloatTabs_Runtime_Lifecycle_Memory_Contract_V4.md`;
- active Phase 5 plan frozen in `FloatTabs_Runtime_Lifecycle_Phase5_Background_Generation_Thrift_Plan_V1.md`;
- `docs/README.md`, architecture README and `DOMAIN_MAP.md` now route to delivered truth;
- V1–V3 contracts and the old Phase 4 strict benchmark plan remain historical evidence rather than active authority.

## Verification evidence

Semantic implementation head passed:

- Debug arm64 build;
- Release arm64 build;
- native arm64 architecture verification;
- full existing XCTest suite including new cadence/visibility tests;
- required `Build & Test (Apple Silicon arm64)` run `1287` on `macmini-floattabs-01`;
- QA DMG run `623`.

Final semantic diff review found only the intended 9 files:

- `CURRENT_STATUS.md`;
- `CURRENT_TASK.md`;
- `FloatTabs/Web/ChatGPTAttentionBridge.swift`;
- `FloatTabsTests/ChatGPTAttentionBridgeTests.swift`;
- `docs/README.md`;
- `docs/architecture/README.md`;
- `docs/architecture/DOMAIN_MAP.md`;
- V4 Runtime Lifecycle contract;
- Phase 5 V1 plan.

No temporary construction workflow/script remains in the final diff.

## Literal-head merge gate

This task is now control-only drift after the verified semantic implementation head. Before merge confirm against the **literal current PR head**:

1. PR #183 remains open and scope-clean;
2. required `Build & Test (Apple Silicon arm64)` is green for the literal head;
3. PR is mergeable;
4. changed paths remain the expected 9 files;
5. no Runtime ownership, Browser Profile/session/persistence, Phase 6 or release/version drift is present.

## STOP conditions

STOP/reconcile if the literal-head gate reveals:

- a second Attention or Runtime lifecycle writer;
- Generating Runtime becoming reclaimable;
- provider-generation pause/cancel semantics;
- `WebViewPool` or `SlotLifecycleCoordinator` contract redesign;
- canonical product visibility moving into page JavaScript;
- persistence/schema/user-data reset/delete;
- private WebKit APIs;
- Phase 6/release work;
- required CI failure.

## Delivery boundary

Current terminal state:

`WAITING_FOR_PHASE_5_MERGE_GATE`

Do not merge PR #183 or begin Phase 6 without the user's next merge authorization.