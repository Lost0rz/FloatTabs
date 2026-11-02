# FloatTabs — Architecture Document Status

Read [`../README.md`](../README.md) first. It is the repository-wide documentation authority/status index.

## Current Runtime Lifecycle / Memory authority

For the current lifecycle/performance program:

- [`FloatTabs_Runtime_Lifecycle_Memory_Contract_V6.md`](FloatTabs_Runtime_Lifecycle_Memory_Contract_V6.md) — **CURRENT / ACCEPTED / FROZEN LONG-TERM DESIGN AUTHORITY**;
- [`FloatTabs_Runtime_Lifecycle_Phase8_Adaptive_Memory_Budget_Implementation_Contract_V1.md`](FloatTabs_Runtime_Lifecycle_Phase8_Adaptive_Memory_Budget_Implementation_Contract_V1.md) — **ORIGINAL PHASE 8 BUDGET CONTRACT / STOPPED AT GATE 0; budget construction deferred**;
- [`FloatTabs_Runtime_Lifecycle_Phase8_WP0_Measurement_Feasibility_Report_V1.md`](FloatTabs_Runtime_Lifecycle_Phase8_WP0_Measurement_Feasibility_Report_V1.md) — **WP0 COMPLETE / GATE 0 FAIL: aggregate WebContent/GPU attribution not provable with supported public production APIs**;
- [`FloatTabs_Runtime_Lifecycle_Phase8_Pressure_Efficiency_Rescope_Contract_V1.md`](FloatTabs_Runtime_Lifecycle_Phase8_Pressure_Efficiency_Rescope_Contract_V1.md) — **CURRENT IMPLEMENTATION CONTRACT / ACCEPTED / FROZEN / D_COMBINE**;
- `CURRENT_STATUS.md` — verified current state;
- `CURRENT_TASK.md` — only active mutation authorization;
- [`DOMAIN_MAP.md`](DOMAIN_MAP.md) — derived navigation/current-source routing.

## Phase 1-7 delivered foundations

Phase 1-7 remain delivered and reusable:

- persistent Slot/Profile/session lifetime is separate from disposable `WKWebView` Runtime lifetime;
- Ready/unread is decoupled from Runtime residency;
- native completion routing survives Runtime reclaim;
- `SlotLifecycleCoordinator` is the lifecycle writer;
- `WebViewPool` owns Runtime create/hibernate/restore/release mechanics;
- hidden generation remains protected while bounded host-side work may be reduced;
- Phase 6 perceived-fast restore remains the restore path;
- Phase 7 `Automatic | Keep Loaded` is current shipped retention configuration.

Current shipped healthy/normal tuning remains:

```text
normal Automatic target = 2
inactive Automatic release path = 30s
```

The current re-scope deliberately preserves those two healthy-state semantics.

## Gate 0 platform boundary

Phase 8 WP0 proved that production can read per-process footprint and deterministically attribute the Networking helper, but cannot use supported public APIs to determine which dominant WebContent/GPU XPC instances belong to the FloatTabs host.

Therefore:

```text
aggregate FloatTabs/WebKit working-set budget input = NOT PROVABLE
memory-budget enforcement = DEFERRED / PLATFORM-BLOCKED
best-effort/correlation attribution = FORBIDDEN
Runtime-count substitution = FORBIDDEN
```

The V6 adaptive budget remains a future architecture direction only. Reopening it requires new supported deterministic attribution evidence.

## User reconciliation — D_COMBINE

The user selected on 2026-11-02:

```text
B now
→ execute measurement-independent pressure + efficiency work

A later
→ revisit aggregate memory budget only when the platform exposes a safe deterministic capability
```

No best-effort `C` path is accepted.

## Current implementation architecture

### R1 — progressive system-memory-pressure ladder

Primary owner: `SlotLifecycleCoordinator`.

```text
warning
→ eligible inactive Automatic only
→ one Runtime at a time
→ Keep Loaded preserved
→ revalidate latest pressure + current ownership/protection between steps

critical
→ Automatic first
→ then inactive/unprotected Keep Loaded if still required
→ active/hard-protected untouched
→ one Runtime at a time

normal pressure
→ stop/cancel pending progression
→ no mass restore
→ restore remains demand-driven
```

The pressure path must use the existing supported system memory-pressure signal. It does not use an aggregate FloatTabs memory estimate.

### R2 — background lifecycle efficiency

Current allowed architecture is host-side only:

- event-first completion sensing where current ownership permits;
- bounded/adaptive hidden fallback probing;
- suppression/coalescing of redundant hidden host work;
- prompt cancellation of stale observer/tasks across document/runtime generation changes;
- prevention of duplicate observer/task registration across hibernate/restore/rebuild;
- exact-current ownership validation before stale callbacks mutate state.

Required semantic chain remains:

```text
Generating
→ hard Runtime protection
→ completion sensing
→ Ready/unread + native notification
→ generating protection ends
→ existing normal lifecycle resumes
```

No provider-semantic redesign, invasive page mutation, private freeze SPI, or renderer-memory claim is authorized.

## Current ownership

- `WebViewPool` — live Runtime creation/hibernate/restore/rebuild/release mechanism;
- `SlotLifecycleCoordinator` — sole Runtime lifecycle executor and pressure-policy writer;
- `TabStore` / `WebAppProfile` — persistent Slot configuration and per-Slot Automatic/Keep Loaded preference;
- `WebAttentionCoordinator` — native Attention authority;
- `ChatGPTAttentionBridge` — provider sensing / bounded liveness fallback;
- `PanelController` — presentation truth + restore orchestration, not a second lifecycle writer;
- Website Cache domain — cache cleanup only, not Runtime lifecycle;
- `RuntimeDiagnostics` — evidence only.

No current owner exists for a production aggregate-memory budget input because Gate 0 failed.

## Current construction sequence

```text
PR #190 WP0/reconciliation closeout
→ literal new head required self-hosted macOS CI
→ exact-diff/base-head/mergeability check
→ merge #190
→ fresh main
→ one successor implementation branch/PR
→ Gate R0 focused source reconciliation
→ R1 pressure ladder + focused tests
→ R2 background efficiency + focused tests
→ full XCTest + Debug/Release arm64 + native architecture
→ literal-head self-hosted macOS CI
→ fresh exact-diff/ownership audit
→ merge-readiness decision
```

No `FloatTabs/**` mutation belongs on the #190 closeout branch.

## Deferred architecture

The following V6 target concepts remain documented but are not executable under the current task:

```text
Memory Budget: Auto / Custom / Unlimited
aggregate working-set observation
high/low watermarks
budget-driven normal reclaim
memory-budget Settings/persistence
aggregate-memory A/B acceptance
```

If the platform boundary changes in the future, those concepts require a fresh task reconciliation before implementation.

## Historical routing

Treat as historical/deferred for current construction:

- `FloatTabs_Runtime_Lifecycle_Memory_Contract_V5.md`;
- `FloatTabs_Runtime_Lifecycle_Phase7_Automatic_Lifecycle_Implementation_Contract_V1.md`;
- `FloatTabs_Runtime_Lifecycle_Phase8_Adaptive_Memory_Budget_Implementation_Contract_V1.md` beyond its recorded Gate 0 evidence/STOP boundary;
- V1-V4 lifecycle contracts;
- old fixed-count/residency plans and Hot/Warm/Cold benchmark material.

Preserve them as evidence. Current mutation follows `CURRENT_TASK.md` plus the pressure/efficiency re-scope contract.
