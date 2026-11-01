# FloatTabs — Architecture Document Status

Read [`../README.md`](../README.md) first. It is the repository-wide documentation authority/status index.

## Current Runtime Lifecycle / Memory authority

For `FT-RUNTIME-LIFECYCLE-MEMORY-001`:

- [`FloatTabs_Runtime_Lifecycle_Memory_Contract_V4.md`](FloatTabs_Runtime_Lifecycle_Memory_Contract_V4.md) — **CURRENT / ACCEPTED / FROZEN** program contract;
- [`FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Audit_V1.md`](FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Audit_V1.md) — **CURRENT PHASE 6 AUDIT / PROPOSED DESIGN / NOT IMPLEMENTATION AUTHORITY**;
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

Detailed source/test/design audit is complete. Product implementation is **not authorized**.

Audit verdict:

- current `WebViewPool` interaction-state restore and Browser Profile/session boundaries remain the correct foundation;
- the strongest perceived-latency boundary is synchronous presentation ordering: a reclaimed selected Slot can synchronously materialize a fresh `WKWebView` before a hidden FloatTabs shell is ordered front;
- the visible container has no explicit native `restoring` state;
- current restore diagnostics prove state handoff, not first visual/usable readiness;
- structural restore tests do not prove the real-WKWebView callback/paint sequence of `interactionState` restoration.

Selected recommendation:

**two-stage native restore shell + deferred fresh Runtime materialization**.

```text
reclaimed Slot selected/summoned
→ native shell + restoring surface immediately
→ return to AppKit run loop
→ revalidate current request
→ existing WebViewPool materializes/restores fresh Runtime
→ attach WebView under restoring surface
→ existing navigation/focus ownership establishes readiness
→ remove restoring surface
```

The exact interaction-state readiness callback must be frozen from a bounded Real-Mac public-API observation before implementation. See the Phase 6 audit document.

Rejected for Phase 6 V1:

- screenshot cache as default continuity mechanism;
- predictive prewarm or larger resident Runtime budget;
- Browser Profile/interactionState restore rewrite without evidence.

## Current ownership

- `WebViewPool` — live Runtime creation/hibernate/restore mechanism and bridge lifetime;
- `SlotLifecycleCoordinator` — sole Runtime lifecycle executor and automatic budget executor;
- private `RuntimeBudgetPolicy` inside `SlotLifecycleCoordinator.swift` — deterministic budget decision only;
- `WebAttentionCoordinator` — sole native Attention state authority;
- `ChatGPTAttentionBridge` — provider sensing and bounded liveness fallback;
- `PanelController` — presentation truth and bounded cross-domain composition;
- `WebPanelContainerView` — visible Web surface and native presentation states, not lifecycle policy;
- `UnreadResponseStore` / unread coordinator — durable unread truth;
- native notification coordinator — notification projection/routing;
- `RuntimeDiagnostics` — evidence only.

Public WebKit APIs do not provide trustworthy exact per-Slot WebContent memory attribution. Historical JSC/WebContent stall root cause remains `UNKNOWN`.

## Historical / superseded lifecycle documents

The following remain useful evidence but are not current execution authority:

- `FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md`, V2, V3;
- `FloatTabs_Runtime_Lifecycle_Phase4_Automatic_Runtime_Budget_Policy_Plan_V1.md`;
- delivered Phase 1–5 plans and reconciliation records.

Do not rewrite historical results to mimic current state. When they conflict with V4/current source/tests, follow current Authority.
