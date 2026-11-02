# FloatTabs — Architecture Document Status

Read [`../README.md`](../README.md) first. It is the repository-wide documentation authority/status index.

## Current Runtime Lifecycle / Memory authority

For the current lifecycle/performance program:

- [`FloatTabs_Runtime_Lifecycle_Memory_Contract_V6.md`](FloatTabs_Runtime_Lifecycle_Memory_Contract_V6.md) — **CURRENT / ACCEPTED / FROZEN DESIGN AUTHORITY**;
- [`FloatTabs_Runtime_Lifecycle_Phase8_Adaptive_Memory_Budget_Implementation_Contract_V1.md`](FloatTabs_Runtime_Lifecycle_Phase8_Adaptive_Memory_Budget_Implementation_Contract_V1.md) — **CURRENT PHASE 8 / ACCEPTED / FROZEN / IMPLEMENTATION STOPPED AT GATE 0**;
- [`FloatTabs_Runtime_Lifecycle_Phase8_WP0_Measurement_Feasibility_Report_V1.md`](FloatTabs_Runtime_Lifecycle_Phase8_WP0_Measurement_Feasibility_Report_V1.md) — **CURRENT PHASE 8 / WP0 EXECUTED 2026-11-02 / GATE 0 VERDICT: FAIL — aggregate WebContent attribution not provable with supported public APIs; budget construction stopped before WP2; awaiting user reconciliation decision**;
- `CURRENT_STATUS.md` — verified current shipped state + frozen target state;
- `CURRENT_TASK.md` — only active mutation authorization;
- [`DOMAIN_MAP.md`](DOMAIN_MAP.md) — derived navigation/current-source routing;
- [`archive/FloatTabs_Runtime_Lifecycle_Phase7_Closeout_Snapshot_2026-11-02.md`](archive/FloatTabs_Runtime_Lifecycle_Phase7_Closeout_Snapshot_2026-11-02.md) — historical Phase 7/V5 closeout snapshot.

V5 and the Phase 7 implementation contract are delivered historical evidence for future construction. They remain valid descriptions of the Phase 7 work that produced `main@2b414982...`, but their fixed-count normal policy is superseded as the Phase 8 target.

## Delivered lifecycle foundations

### Phase 1 — Safe Hibernate + Restore

Delivered / merged. Persistent Slot/Profile/session lifetime is separated from disposable `WKWebView` Runtime lifetime.

### Phase 2 — Ready / Unread Decoupling

Delivered / merged. Generating protects Runtime; Ready/unread does not require Runtime residency.

### Phase 3 — Native Completion Notification

Delivered / merged. Hidden valid completion can route back to the exact persistent Slot independently of Runtime residency.

### Phase 4 — Managed Runtime budget foundation

Delivered / merged. Deterministic lifecycle decision support, `lastUsedAt`, memory-pressure input and `SlotLifecycleCoordinator` as sole lifecycle executor remain reusable. Old count/residency policy is historical.

### Phase 5 — Background Generation Thrift

Delivered / merged. Generating remains Runtime-protected while hidden fallback work is reduced.

### Phase 6 — Perceived-fast Restore

Delivered / merged in PR #187.

Architecture:

```text
reclaimed Slot selected/summoned
→ native shell/restoring state
→ deferred current request
→ WebViewPool restore/create
→ exact-current Runtime readiness
→ restoring surface removed
→ canonical focus/input resumes
```

### Phase 7 — Automatic / Keep Loaded + legacy residency retirement

Delivered / merged in PR #188 at:

`main@2b414982710b3f042fc7d6e9c88eb2d7117b4e38`

Delivered structural result:

```text
Automatic / Keep Loaded
no hidden Hot host
no current Hot/Warm/Cold product controls
Runtime reclaim independent from website/session cleanup
Phase 6 restore preserved
Generating hard-protected
Keep Loaded does not preload at launch
```

The merged Phase 7 tuning remains current production truth until Phase 8 lands:

```text
normal Automatic target = 2
inactive release path = 30s
warning target = 1
critical target = 0
```

These values are not the frozen Phase 8 target.

## Phase 8 — Adaptive Memory Budget + Background Efficiency

Phase 8 design is frozen; implementation has not started.

Target product model:

```text
Memory Budget
├─ Auto — Recommended
├─ Custom GiB
└─ Unlimited
```

Initial reference Auto formula:

```text
clamp(physical RAM × 20%, 1.5 GiB, 6 GiB)
```

Target reclaim semantics:

```text
under budget
→ keep useful inactive Runtime resident
→ no fixed resident-count ceiling

above high watermark (105%)
→ choose one eligible inactive Automatic Runtime
→ hibernate through WebViewPool
→ remeasure aggregate footprint
→ stop <= low watermark (90%)
→ otherwise repeat one at a time
```

System memory pressure remains independent:

```text
warning
→ progressively reclaim eligible Automatic

critical
→ Automatic first
→ inactive/unprotected Keep Loaded only if still required
```

The existing 30-second value becomes a normal-budget anti-thrash eligibility grace, not an unconditional Runtime lifetime.

Proactive long-idle cleanup is OFF by default in the V6 baseline.

## Resource measurement boundary

A GiB budget requires a production-safe aggregate FloatTabs/WebKit footprint estimate.

Desired observation:

```text
FloatTabs host
+ attributable WebContent
+ attributable WebKit Networking/GPU/other helper processes
```

This is application aggregate evidence only. Exact per-Slot WebContent memory attribution remains unsupported as a trustworthy public policy input.

Phase 8 Gate 0 must prove a supported production mechanism before budget enforcement. Benchmark-only responsible-PID evidence does not automatically authorize an in-app implementation. **Gate 0 was executed 2026-11-02 (WP0) and FAILED**: the WP0 measurement feasibility report records that public per-pid footprint reading and Networking attribution exist, but WebContent/GPU attribution to the host app does not; budget construction is stopped before WP2 pending user reconciliation.

A read-only `RuntimeResourceMonitor`-like component may supply resource facts; it must never become a lifecycle writer or kill/reload Runtime itself.

## Background-generation architecture under V6

Current accepted semantic chain remains:

```text
Generating
→ hard Runtime protection
→ completion sensing
→ Ready/unread + native notification
→ generating protection ends
→ normal lifecycle resumes
```

Phase 8 may reduce host-side observer/probe/diagnostic work while hidden generation remains live, but it does not claim that arbitrary WKWebView JS/network work can be deeply frozen while continuing to generate.

Private WebKit inactive-scheduling/freeze SPI is not authorized.

## Current ownership

- `WebViewPool` — live Runtime creation/hibernate/restore/rebuild/release mechanism;
- `SlotLifecycleCoordinator` — sole Runtime lifecycle/budget executor;
- future aggregate resource monitor — read-only resource fact provider only;
- `AppPreferencesStore` — durable global memory-budget configuration;
- `TabStore` / `WebAppProfile` — persistent Slot configuration and per-Slot Automatic/Keep Loaded preference;
- `WebAttentionCoordinator` — native Attention authority;
- `ChatGPTAttentionBridge` — provider sensing / bounded liveness fallback;
- `PanelController` — presentation truth + restore orchestration;
- Website Cache domain — cache cleanup only, not Runtime lifecycle;
- `RuntimeDiagnostics` — evidence only.

## Frozen Phase 8 construction sequence

```text
WP0 exact source audit + production measurement feasibility
→ WP1 passive budget config/resource monitor
→ WP2 memory-budget scheduler/progressive normal reclaim
→ WP3 system-pressure ladder
→ WP4 Advanced Runtime & Memory UI + persistence/backup
→ WP5 background-generation/observer efficiency corrective
→ WP6 Real-Mac + Phase7-vs-Phase8 A/B acceptance
→ fresh exact-diff/ownership audit
→ merge-readiness
```

The current design task authorizes documentation/control only. No `FloatTabs/**` product mutation begins until a later explicit implementation task is opened.

## Reference-derived direction

Design references support:

- separating proactive inactivity from urgent pressure reclaim;
- using user resource policy rather than a fixed tab count;
- protecting active/media/generating work;
- progressive reclaim/re-evaluation;
- lazy materialization and real Runtime sleep/restore.

Reference projects do not override FloatTabs ownership or WebKit public-API constraints.

## Historical routing

Treat these as historical for new construction:

- `FloatTabs_Runtime_Lifecycle_Memory_Contract_V5.md`;
- `FloatTabs_Runtime_Lifecycle_Phase7_Automatic_Lifecycle_Implementation_Contract_V1.md`;
- V1-V4 lifecycle contracts;
- old Phase 4 fixed-count/residency plans;
- Stage Hot/Warm/Cold lifecycle/benchmark material.

Preserve them as evidence; do not rewrite them into V6 wording.
