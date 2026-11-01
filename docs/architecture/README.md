# FloatTabs — Architecture Document Status

Read [`../README.md`](../README.md) first. It is the repository-wide documentation authority/status index.

## Current Runtime Lifecycle / Memory authority

For `FT-RUNTIME-LIFECYCLE-MEMORY-001`:

- [`FloatTabs_Runtime_Lifecycle_Memory_Contract_V4.md`](FloatTabs_Runtime_Lifecycle_Memory_Contract_V4.md) — **CURRENT / ACCEPTED / FROZEN** program contract;
- [`FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Implementation_Contract_V1.md`](FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Implementation_Contract_V1.md) — **CURRENT PHASE 6 / ACCEPTED / FROZEN / EXECUTION STARTED / GATE 0 PENDING**;
- [`FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Audit_V1.md`](FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Audit_V1.md) — **AUDIT / RATIONALE EVIDENCE**; no longer the execution-scope authority;
- `CURRENT_STATUS.md` — verified current state/evidence;
- `CURRENT_TASK.md` — only active mutation authorization;
- [`DOMAIN_MAP.md`](DOMAIN_MAP.md) — navigation only;
- current production source/tests/fresh evidence.

Program cadence remains:

```text
focused phase audit / freeze
→ bounded implementation
→ machine verification + required CI
→ merge
→ next dependent phase
...
Phases 1–6 complete
→ integrated independent program audit
→ one user-owned final human acceptance pass
```

## Delivered lifecycle foundations

### Phase 1 — Safe Hibernate + Restore

Complete / merged. Persistent Slot/Profile/session lifetime is separated from disposable `WKWebView` Runtime lifetime. One memory-local opaque `interactionState` snapshot may bridge normal hibernate to a compatible fresh Runtime; incompatible state falls back safely to URL loading.

### Phase 2 — Ready / Unread Decoupling

Complete / merged.

```text
Generating -> Runtime-protected
Ready      -> transient, not Runtime-protected
Durable unread -> survives Runtime reclamation
```

### Phase 3 — Native ChatGPT Completion Notification

Complete / merged. Hidden valid completion can persist unread truth, notify natively and route back to the exact persistent Slot independently of Runtime residency.

### Phase 4 — Reference-derived Automatic Runtime Management

Complete / merged in PR #181 / `c910441a954bddbaeca710395cd0d6ed89ec5e5c`.

Current production semantics:

- Hot is an explicit pin outside automatic eviction;
- Warm/Cold are managed automatically;
- Cold ranks before Warm, then older `lastUsedAt`, then UUID;
- active/presented/fullscreen/supplemental/media/Attention-generating Runtime is protected;
- normal/warning managed target defaults to 3;
- critical pressure targets 0 eligible inactive Warm/Cold Runtime;
- reclaim executes through `SlotLifecycleCoordinator` → existing `WebViewPool.hibernate`.

The value 3 is a reference-derived initial default, not measured optimum. The old strict Phase 4 benchmark-selection gate remains historical and deferred to future Settings-backed tuning.

### Phase 5 — Background Generation Thrift

Complete / merged in PR #183 / `745d401bf9f282d19bc756c81be3f46f17161e4b`.

Delivered fallback cadence:

```text
visible/unknown document                  -> 2s
hidden document, generation age < 30s     -> 2s
hidden document, generation age >= 30s    -> 5s
first false probe                          -> existing 250ms confirmation
```

The primary ChatGPT page detector remains event-driven. `document.visibilityState` is bridge-local scheduling metadata only; `PanelController` remains product/presentation visibility authority.

## Phase 6 — Perceived-fast Restore

**Audit:** complete.  
**Implementation contract:** accepted/frozen.  
**Execution:** started by explicit user instruction on `2026-11-01`.  
**Current gate:** WP0 / Gate 0 Real-Mac evidence.  
**Product implementation:** not started; product mutation remains held until Gate 0 Outcome A/B.

Frozen architecture:

```text
reclaimed Slot selected/summoned
→ native shell + lightweight restoring state immediately
→ return to AppKit run loop
→ revalidate materialization request
→ existing WebViewPool materializes/restores fresh Runtime
→ attach fresh WebView under restoring state
→ Gate 0-proven current-Runtime readiness
→ remove restoring state
→ existing focus ownership resumes
```

Resident Slot switching remains on the direct existing path.

### Gate 0 readiness contract

The exact callback name is not frozen from structural fixtures. The implementation contract instead requires a Real-Mac evidence gate before product-source mutation.

Allowed evidence classes:

1. **navigation-backed readiness** — compatible `interactionState` restore exposes usable exact-current-Runtime navigation/loading callbacks that can trigger the final bounded readiness check;
2. **non-navigation readiness** — compatible restore does not reliably emit the same navigation sequence, but bounded public current-Runtime renderer/page readiness is available without polling ownership drift.

If neither class is provable without private API, arbitrary delay/unbounded polling, reload/double-navigation, persistence/session mutation, screenshot persistence, extra resident WebViews or ownership change, execution stops before product mutation.

Current repository evidence plumbing is already sufficient to execute Gate 0 without first changing product Runtime code:

- Debug benchmark control can drive existing Slot `configure`, `activate`, `show` and `hide` operations;
- `tools/benchmark/floattabs_lifecycle_benchmark.py` can cross actual Cold/Warm production timers, prove hibernate/reclaim, and later re-activate a reclaimed Slot;
- `WebViewPool` diagnostics expose hibernate/restore/create identity;
- `SlotNavigationObserver` diagnostics expose exact-current-Runtime provisional/commit/finish callbacks and bounded renderer/liveness evidence.

`web_runtime.restore.completed` remains state-handoff evidence only and is not sufficient by itself to dismiss the restoring presentation.

### Frozen implementation boundary after Gate 0 PASS

Primary expected production paths:

- `FloatTabs/Panel/PanelController.swift` — materialization generation, early shell presentation, deferred materialization and stale-request orchestration;
- `FloatTabs/Web/WebViewContainer.swift` — lightweight native restoring presentation only;
- `FloatTabs/Web/WebViewPool.swift` — no semantic restore rewrite; narrow read-only seam only if required;
- `FloatTabs/Web/SlotNavigationObserver.swift` — narrow readiness seam only when Gate 0 proves it necessary.

Primary expected tests:

- `FloatTabsTests/ExternalShellTests.swift`;
- `FloatTabsTests/WebViewPoolTests.swift`;
- existing focus tests only when focus timing is touched.

Any material production scope outside those boundaries requires reconciliation.

### Rejected Phase 6 V1 alternatives

- screenshot cache as the default continuity mechanism;
- predictive prewarm or larger resident Runtime budget;
- Browser Profile / interaction-state restore rewrite without evidence;
- arbitrary timer/polling/reload tricks to manufacture readiness.

## Current ownership

- `WebViewPool` — live Runtime creation/hibernate/restore mechanism and bridge lifetime;
- `SlotLifecycleCoordinator` — sole Runtime lifecycle executor and automatic budget executor;
- private `RuntimeBudgetPolicy` inside `SlotLifecycleCoordinator.swift` — deterministic budget decision only;
- `WebAttentionCoordinator` — sole native Attention state authority;
- `ChatGPTAttentionBridge` — provider sensing and bounded liveness fallback;
- `PanelController` — presentation truth and Phase 6 materialization orchestration after Gate 0 passes;
- `WebPanelContainerView` — visible Web surface/native restoring presentation, not lifecycle policy;
- `UnreadResponseStore` / unread coordinator — durable unread truth;
- native notification coordinator — notification projection/routing;
- `RuntimeDiagnostics` — evidence only.

Public WebKit APIs do not provide trustworthy exact per-Slot WebContent memory attribution. Historical JSC/WebContent stall root cause remains `UNKNOWN`.

## Historical / superseded lifecycle documents

The following remain useful evidence but are not current execution authority:

- `FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md`, V2, V3;
- `FloatTabs_Runtime_Lifecycle_Phase4_Automatic_Runtime_Budget_Policy_Plan_V1.md`;
- delivered Phase 1–5 plans and reconciliation records;
- the Phase 6 audit document for execution scope after the implementation contract freeze.

Do not rewrite historical results to mimic current state. When they conflict with V4/current Phase 6 implementation contract/current source/tests, follow current Authority.
