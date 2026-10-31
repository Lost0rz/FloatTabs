# FloatTabs Current Status

**Status date:** `2026-10-31`
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 1 AUDIT COMPLETE / PLAN FREEZE**

Current program/task: `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

Current execution state: `ACTIVE / PHASE 1 PLAN PR`.

Runtime product mutation is **NOT YET AUTHORIZED**. The Phase 1 focused read-only audit is complete and its exact implementation contract is being frozen in PR #167. Product mutation starts only after that plan merges, Control Alignment moves `CURRENT_TASK.md` to `PHASE 1 IMPLEMENTATION`, and a concise construction card is issued.

## Canonical / current state

```text
AUDIT_BASE_MAIN=1ba0ec7fe70c3d8a6fd42d586dcc813ed87d9088
PRE_PROGRAM_PRODUCT_BASELINE=26d1669198a6f94faa769fb27d2cd00d0fcd1184
PR_162=MERGED
JSC_ROOT_CAUSE=UNKNOWN
JSC_CRASH_ELIMINATED=NOT_CLAIMED
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26

ACTIVE_PROGRAM=FT-RUNTIME-LIFECYCLE-MEMORY-001
PHASE_0_CONTRACT_FREEZE=COMPLETE
HISTORICAL_DOC_GATE=COMPLETE
PHASE_1_FOCUSED_AUDIT=COMPLETE
PHASE_1_PLAN=docs/architecture/FloatTabs_Runtime_Lifecycle_Phase1_Safe_Hibernate_Restore_Plan_V1.md
PHASE_1_PLAN_PR=#167 OPEN / DRAFT / UNMERGED
CURRENT_PRODUCT_MUTATION=NOT_AUTHORIZED
OPEN_PRS_BEFORE_PHASE1_PLAN=0
```

## Documentation / Authority

Use:

```text
AGENTS.md
→ CURRENT_STATUS.md
→ CURRENT_TASK.md
→ docs/README.md
→ docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md
→ docs/architecture/FloatTabs_Runtime_Lifecycle_Phase1_Safe_Hibernate_Restore_Plan_V1.md
→ docs/architecture/DOMAIN_MAP.md for navigation
→ current source/tests/fresh evidence
```

The repository-wide historical-document reconciliation is complete. Historical Stage/design/audit/plan wording cannot override current Authority.

## Phase 1 audit verdict

**VERDICT: IMPLEMENTATION DESIGN IS SUFFICIENT TO FREEZE.**

The audit found no need to rewrite the whole Web container architecture. Phase 1 can remain bounded to the Web Runtime mechanism/lifecycle boundary.

### Key audited facts

1. `WebViewPool` already separates live `WKWebView` runtime from persistent Slot/Profile data.
2. `BrowserProfileDataStoreProvider` resolves persistent Default/custom `WKWebsiteDataStore` independently from Runtime lifetime.
3. current `release(slotID:)` removes runtime maps/bridges/observers but is not a complete hibernation primitive: it does not capture `interactionState`, explicitly `stopLoading`, explicitly clear delegates, explicitly invalidate the navigation KVO token, or clear `pendingTerminationIncidentContexts`.
4. current lifecycle release order is correct: final protection checks → preparation → container detach → Pool teardown → callback.
5. current `release()` has destructive callers (Slot deletion, stored-state/profile replacement, cache preparation, rebuild/recovery). It must not be globally redefined as hibernate.
6. Phase 1 therefore requires an explicit semantic split:

```text
hibernate(slotID:) = capture bounded restore state + deterministic teardown
release(slotID:)   = clear restore state + deterministic destructive teardown
```

7. only normal inactive lifecycle reclamation / eligible critical Warm pressure switches to `hibernate`; destructive callers remain destructive.
8. public `WKWebView.interactionState` is available on macOS 12+ and is explicitly intended to restore back-forward list/current page/scroll/form state to another WebView. FloatTabs macOS 13+ baseline is compatible.
9. the interaction state must remain opaque and memory-local in Phase 1; it is never persisted/logged.
10. `WebPanelContainerView`, `WebSlotHostView`, `WebFocusRouter.currentWebView`, and Fullscreen source observed WebView references are weak. There is currently no evidence requiring Phase 1 changes in Panel/Fullscreen/Focus.
11. ChatGPT Attention/Response bridges already use weak WebView references and explicit invalidation; stale async probe paths already validate runtime/WebView/navigation identity.
12. `SlotNavigationObserver` needs an explicit idempotent invalidation seam so KVO/tasks are stopped deterministically instead of depending on deinit timing.
13. current Cold release may trigger Website Cache cleanup, but cleanup is limited to disk/memory/fetch caches and excludes login/session data. Primary Phase 1 memory benchmark will use Warm release to avoid cache-cleanup confounding.
14. the existing Debug benchmark control channel and lifecycle benchmark already capture process-tree RSS/CPU, helper counts and exact resident Slot count; no second benchmark control plane is needed.

## Frozen Phase 1 implementation scope

Expected production changes are limited to:

- `FloatTabs/Web/WebViewPool.swift`
- `FloatTabs/Web/SlotLifecycleCoordinator.swift`
- `FloatTabs/Web/SlotNavigationObserver.swift`

Expected tests/tooling are limited to:

- `FloatTabsTests/WebViewPoolTests.swift`
- `FloatTabsTests/WebAttentionLifecycleTests.swift`
- `FloatTabsTests/WebFocusAdapterTests.swift` only if needed for the narrow observer invalidation fixture
- `tools/benchmark/floattabs_lifecycle_benchmark.py` only if Phase 1 reporting needs adaptation
- `tools/benchmark/README.md` only for the accepted Phase 1 benchmark runbook

Full exact behavior/tests/benchmark/STOP conditions are frozen in the Phase 1 plan.

## Explicit Phase 1 non-scope

Do not change in Phase 1 unless a STOP condition forces task reconciliation:

- Ready/Unread semantics;
- ChatGPT completion notification;
- Hot/Warm/Cold UI/timings;
- automatic Runtime Budget/ranking;
- Browser Profile persistence/schema;
- Website Cache data types/policy;
- Panel/Fullscreen/Focus product semantics;
- process-pool topology;
- server Push;
- recent-conversation native preview.

## Primary implementation/validation gate

After implementation, Phase 1 only passes if controlled evidence shows:

- logical resident runtime count falls exactly for eligible hibernated Slots;
- protected/visible Slots remain resident;
- process-tree memory reduction for multiple heavy runtimes is positive/repeatable and larger than 2× the measured no-op/control drift;
- restore creates one new runtime, preserves Profile/session/product invariants, and does not issue a competing URL load on compatible interaction-state restore;
- paired restore timing does not regress versus URL fallback by more than `max(20%, 300 ms)` in median;
- all required tests/CI/manual acceptance pass.

If runtime count falls but memory remains within control noise, or interaction-state restore needs private API/double-navigation/timer hacks, STOP before Phase 2+.

## Next gate

1. complete independent read-only audit of PR #167;
2. required GitHub CI must pass;
3. merge #167 if scope/Authority remain clean;
4. run Control Alignment on `main` to authorize `ACTIVE / PHASE 1 IMPLEMENTATION`;
5. issue one concise local construction card referencing the frozen Phase 1 plan;
6. local executor implements/tests/benchmarks and stops at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`.

No production release is authorized.
