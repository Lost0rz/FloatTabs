# FloatTabs — Architecture Document Status

Read [`../README.md`](../README.md) first. It is the repository-wide documentation authority/status index.

## Current Runtime Lifecycle / Memory authority

For `FT-RUNTIME-LIFECYCLE-MEMORY-001`:

- [`FloatTabs_Runtime_Lifecycle_Memory_Contract_V5.md`](FloatTabs_Runtime_Lifecycle_Memory_Contract_V5.md) — **CURRENT / ACCEPTED / FROZEN** program contract;
- [`FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Implementation_Contract_V1.md`](FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Implementation_Contract_V1.md) — delivered Phase 6 scoped contract; PR #187 merged;
- [`FloatTabs_Runtime_Lifecycle_Phase7_Automatic_Lifecycle_Implementation_Contract_V1.md`](FloatTabs_Runtime_Lifecycle_Phase7_Automatic_Lifecycle_Implementation_Contract_V1.md) — **CURRENT PHASE 7 / ACCEPTED / FROZEN** implementation contract;
- `CURRENT_STATUS.md` — verified current state/evidence;
- `CURRENT_TASK.md` — only active mutation authorization;
- [`DOMAIN_MAP.md`](DOMAIN_MAP.md) — navigation/current-source routing only.

V4 and earlier program contracts are historical for current execution.

## Delivered lifecycle foundations

### Phase 1 — Safe Hibernate + Restore

Delivered / merged. Persistent Slot/Profile/session lifetime is separated from disposable `WKWebView` Runtime lifetime.

### Phase 2 — Ready / Unread Decoupling

Delivered / merged. Generating protects Runtime; Ready/unread does not require Runtime residency.

### Phase 3 — Native Completion Notification

Delivered / merged. Hidden valid completion can route back to the exact persistent Slot independently of Runtime residency.

### Phase 4 — Managed Runtime budget foundation

Delivered / merged. Deterministic resident-set evaluation, `lastUsedAt` ranking facts, memory-pressure input and `SlotLifecycleCoordinator` as sole lifecycle executor remain reusable; legacy Hot/Warm/Cold policy is superseded by Phase 7.

### Phase 5 — Background Generation Thrift

Delivered / merged. Generating remains Runtime-protected while hidden liveness fallback work is reduced.

### Phase 6 — Perceived-fast Restore

Delivered / merged in PR #187 at `main@54f2e43b0fbc224affa52d9662ac2ba5aa5b963c`.

Architecture:

```text
reclaimed Slot selected/summoned
→ native shell/restoring state
→ deferred current request
→ WebViewPool restore/create
→ exact-current Runtime readiness
→ restoring state removed
→ canonical focus/input resumes
```

Phase 6 does not own residency policy.

## Phase 7 — Automatic Lifecycle Simplification

Implementation is complete on PR #188 and is at final merge closeout.

Current product policy:

```text
Automatic   — default
Keep Loaded — explicit normal-operation preference

normal target = 2 Automatic runtimes
inactive grace = 30s
warning target = 1 Automatic runtime
critical target = 0 Automatic runtimes
```

Legacy compatibility:

```text
Hot       -> Keep Loaded
Warm/Cold -> Automatic
```

Hard protections remain:

- active / actually presented;
- fullscreen source;
- supplemental visible Web surface;
- Attention Generating;
- active/pending allowed-background-media protection;
- current Phase 6 materialization/restoring ownership.

Keep Loaded does not preload at launch, does not require hidden presentation ownership, survives ordinary reclaim and may be reclaimed under critical pressure when inactive and otherwise unprotected.

Legacy Cold-based website-cache cleanup coupling is retired; Runtime reclaim and website-cache cleanup remain separate domains.

## Phase 7 verification status

Semantic/acceptance head:

`b894641a254e7ffb49c84b4ed32d9c70a3f28ad7`

Verified on that identity:

- required `Build & Test (Apple Silicon arm64)` / macOS CI #1349 — PASS;
- QA DMG #668 — PASS;
- Benchmark Tool CI #139 — PASS;
- fresh product exact-diff audit — PASS;
- bounded Real-Mac Automatic/Keep Loaded acceptance — PASS;
- Keep Loaded relaunch non-preload check — PASS;
- session continuity check — PASS;
- no unresolved product/runtime defect found.

Control/routing status alignment may advance the literal PR head without changing product semantics. Before merge, the required repository-host check must pass on the final literal head and PR #188 must remain mergeable.

## Current ownership

- `WebViewPool` — live Runtime creation/hibernate/restore and renderer recovery mechanism;
- `SlotLifecycleCoordinator` — sole Runtime lifecycle/budget executor;
- Runtime budget policy/value logic — read-only deterministic decision support inside Web lifecycle;
- `TabStore` / `WebAppProfile` — persistent Slot configuration and Automatic/Keep Loaded preference;
- `WebAttentionCoordinator` — native Attention authority;
- `PanelController` — presentation truth + Phase 6 orchestration;
- `WebPanelContainerView` — presentation only, with no hidden Hot host ownership;
- Website Cache domain — cache cleanup only, not Runtime lifecycle;
- `RuntimeDiagnostics` — evidence only.

## Program sequence from here

```text
final control/routing alignment
→ required check on literal PR head
→ merge PR #188 if mergeable
→ fresh post-merge integrated Phases 1-7 audit
→ user-owned final integrated acceptance / release decision
```

Do not treat old Stage residency docs, V1-V4 contracts or the Phase 4 planning document as current policy authority.
