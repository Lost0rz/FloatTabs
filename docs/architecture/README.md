# FloatTabs — Architecture Document Status

Read [`../README.md`](../README.md) first. It is the repository-wide documentation authority/status index.

## Current Runtime Lifecycle / Memory authority

For `FT-RUNTIME-LIFECYCLE-MEMORY-001`:

- [`FloatTabs_Runtime_Lifecycle_Memory_Contract_V4.md`](FloatTabs_Runtime_Lifecycle_Memory_Contract_V4.md) — **CURRENT / ACCEPTED / FROZEN** program contract;
- [`FloatTabs_Runtime_Lifecycle_Phase5_Background_Generation_Thrift_Plan_V1.md`](FloatTabs_Runtime_Lifecycle_Phase5_Background_Generation_Thrift_Plan_V1.md) — **ACTIVE / ACCEPTED / FROZEN** Phase 5 plan;
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

Complete. Persistent Slot/Profile/session lifetime is separated from disposable `WKWebView` Runtime lifetime.

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
- reclaim still executes through `SlotLifecycleCoordinator` → existing `WebViewPool.hibernate`.

The value 3 is a reference-derived initial default, not measured optimum. The old Phase 4 strict benchmark-selection gate is historical and deferred to future Settings-backed tuning.

## Active Phase 5 — Background Generation Thrift

Phase 5 reduces FloatTabs-owned fallback observation work without controlling provider generation.

Audited route:

```text
ChatGPT page detector
→ event-driven generationStarted
→ WebAttentionCoordinator .generating
→ Runtime remains protected
→ ChatGPTAttentionBridge liveness watchdog is fallback only
```

The primary page detector already uses event-driven mutation observation with bounded coalescing and excludes streamed token `characterData`. Phase 5 therefore keeps that detector intact and adapts only the native liveness-watchdog cadence.

Frozen initial cadence:

```text
visible/unknown document                  -> 2s
hidden document, generation age < 30s     -> 2s
hidden document, generation age >= 30s    -> 5s
first false probe                          -> existing 250ms confirmation
```

`document.visibilityState` is local bridge scheduling metadata only. `PanelController` remains authoritative product/presentation visibility truth.

## Current ownership

- `WebViewPool` — live Runtime creation/hibernate/restore mechanism and bridge lifetime;
- `SlotLifecycleCoordinator` — sole Runtime lifecycle executor and automatic budget executor;
- private `RuntimeBudgetPolicy` inside `SlotLifecycleCoordinator.swift` — Phase 4 deterministic budget decision only;
- `WebAttentionCoordinator` — sole native Attention state authority;
- `ChatGPTAttentionBridge` — provider sensing and bounded liveness fallback;
- `PanelController` — presentation truth and bounded cross-domain composition;
- `UnreadResponseStore` / unread coordinator — durable unread truth;
- native notification coordinator — notification projection/routing;
- `RuntimeDiagnostics` — evidence only.

Public WebKit APIs do not provide trustworthy exact per-Slot WebContent memory attribution. Historical JSC/WebContent stall root cause remains `UNKNOWN`.

## Phase 6

Perceived-fast Restore remains `NOT STARTED / NOT AUTHORIZED`.

## Historical / superseded lifecycle documents

The following remain useful evidence but are not current execution authority:

- `FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md`, V2, V3;
- `FloatTabs_Runtime_Lifecycle_Phase4_Automatic_Runtime_Budget_Policy_Plan_V1.md`;
- delivered Phase 1–3 plans and reconciliation records.

Do not rewrite their historical results to mimic current state. When they conflict with V4/current source/tests, follow current Authority.
