# FloatTabs — Architecture Document Status

Read [`../README.md`](../README.md) first. It is the repository-wide documentation authority/status index.

## Current Runtime Lifecycle / Memory authority

For `FT-RUNTIME-LIFECYCLE-MEMORY-001`:

- [`FloatTabs_Runtime_Lifecycle_Memory_Contract_V5.md`](FloatTabs_Runtime_Lifecycle_Memory_Contract_V5.md) — **CURRENT / ACCEPTED / FROZEN** program contract;
- [`FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Implementation_Contract_V1.md`](FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Implementation_Contract_V1.md) — **CURRENT PR #187-SCOPED PHASE 6 CONTRACT**;
- [`FloatTabs_Runtime_Lifecycle_Phase7_Automatic_Lifecycle_Implementation_Contract_V1.md`](FloatTabs_Runtime_Lifecycle_Phase7_Automatic_Lifecycle_Implementation_Contract_V1.md) — **CURRENT PHASE 7 / ACCEPTED / FROZEN / IMPLEMENTATION NOT STARTED**;
- `CURRENT_STATUS.md` — verified current state/evidence;
- `CURRENT_TASK.md` — only active mutation authorization;
- [`DOMAIN_MAP.md`](DOMAIN_MAP.md) — navigation/current-source routing only.

V4 and earlier program contracts are historical for current execution.

## Audit result that caused V5

The current source still implements a hybrid legacy residency model:

- Hot is explicitly non-evictable by the normal/critical automatic managed-budget policy;
- Warm/Cold use separate persisted timers;
- the current Tab menu exposes Hot/Warm/Cold;
- Performance Settings exposes Warm retention and Cold release delay;
- inactive Hot keeps its WebView attached in a hidden Hot host;
- normal managed target is 3 Warm/Cold runtimes;
- Phase 6 deliberately leaves those semantics unchanged.

Real-Mac QA therefore exposed a program-level mismatch: Phase 6 can make restore responsive, but legacy Hot can still keep several heavyweight ChatGPT runtimes resident indefinitely.

V5 classifies V4 as `STOP` for final program acceptance while preserving the delivered Phase 6 architecture.

## Delivered lifecycle foundations

### Phase 1 — Safe Hibernate + Restore

Complete / merged. Persistent Slot/Profile/session lifetime is separated from disposable `WKWebView` Runtime lifetime.

### Phase 2 — Ready / Unread Decoupling

Complete / merged. Generating protects Runtime; Ready/unread does not require Runtime residency.

### Phase 3 — Native Completion Notification

Complete / merged. Hidden valid completion can route back to the exact persistent Slot independently of Runtime residency.

### Phase 4 — Managed Runtime budget foundation

Complete / merged in PR #181.

Reusable mechanism remains valid: deterministic resident-set evaluation, `lastUsedAt` ranking facts, memory-pressure input and `SlotLifecycleCoordinator` as sole executor.

Its Hot/Warm/Cold current-product policy and target `3` are superseded by the V5 Phase 7 target once Phase 7 lands.

### Phase 5 — Background Generation Thrift

Complete / merged in PR #183. Generating remains Runtime-protected while hidden liveness fallback work is reduced.

## Phase 6 — Perceived-fast Restore

PR #187 is OPEN / DRAFT / UNMERGED.

Current product head:

`76c092523fe343eacc0592bfac25086da0d0d83d`

Current evidence:

- Gate 0 Outcome A navigation-backed readiness: PASS;
- C1-C4 functional corrective: applied;
- required macOS CI run 1312: PASS;
- QA DMG run 637: PASS;
- bounded Real-Mac restore smoke: still needs completion;
- fresh independent exact-diff audit: pending;
- known comment-only churn must be cleaned or explicitly accepted before merge.

Phase 6 architecture remains:

```text
reclaimed Slot selected/summoned
→ native shell/restoring state
→ deferred current request
→ WebViewPool restore/create
→ exact-current Runtime readiness
→ restoring state removed
→ canonical focus/input resumes
```

Phase 6 does not own the final residency policy.

## Phase 7 — Automatic Lifecycle Simplification

Contract frozen; implementation not started.

Target product policy:

```text
Automatic   — default
Keep Loaded — explicit normal-operation preference
```

Legacy compatibility:

```text
Hot       -> Keep Loaded
Warm/Cold -> Automatic
```

Initial automatic defaults:

```text
normal target = 2
inactive grace = 30s
warning target = 1
critical target = 0
```

Hard protection remains active/presented, fullscreen, supplemental-visible, Attention generating and active/pending allowed-background-media protection.

Keep Loaded does not preload at launch, does not require a hidden presentation host and may be reclaimed under critical pressure when inactive and otherwise unprotected.

Legacy Cold-based website-cache cleanup coupling is retired; Runtime reclaim and website cache cleanup remain separate domains.

## Current ownership

- `WebViewPool` — live Runtime creation/hibernate/restore and renderer recovery mechanism;
- `SlotLifecycleCoordinator` — sole Runtime lifecycle/budget executor;
- Runtime budget policy/value logic — read-only deterministic decision support owned inside Web lifecycle;
- `TabStore` / `WebAppProfile` — persistent Slot configuration and future Automatic/Keep Loaded preference;
- `WebAttentionCoordinator` — native Attention authority;
- `PanelController` — presentation truth + Phase 6 orchestration;
- `WebPanelContainerView` — presentation only; Phase 7 removes policy-specific hidden Hot host responsibility;
- Website Cache domain — cache cleanup only, not Runtime lifecycle;
- `RuntimeDiagnostics` — evidence only.

## Program sequence from here

```text
finish Phase 6 smoke + fresh exact-diff audit
→ merge PR #187
→ implement Phase 7 from fresh main
→ focused/full machine gates + required CI
→ bounded Real-Mac lifecycle/memory evidence
→ fresh integrated independent audit
→ one user-owned final human acceptance
→ closeout/release decision
```

Do not treat old Stage residency docs, V1-V4 contracts or the Phase 4 planning document as current policy authority.
