# FloatTabs Documentation Authority / Status Index

> Current document-routing index. Read this before using any document under `docs/` for implementation decisions.

## 1. Authority order

```text
AGENTS.md
→ CURRENT_STATUS.md
→ CURRENT_TASK.md
→ this docs/README.md routing index
→ current architecture/design contract explicitly linked by current Authority
→ docs/architecture/DOMAIN_MAP.md for navigation only
→ current production source + regression tests + fresh runtime/repository evidence
```

Historical documents remain evidence only unless current Authority explicitly restores them.

## 2. Current Runtime Lifecycle / Memory authority

For the current lifecycle/performance program:

- [`architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V6.md`](architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V6.md) — **CURRENT / ACCEPTED / FROZEN DESIGN AUTHORITY**; supersedes V5 for future lifecycle/performance construction while preserving Phase 1-7 delivered architecture;
- [`architecture/FloatTabs_Runtime_Lifecycle_Phase8_Adaptive_Memory_Budget_Implementation_Contract_V1.md`](architecture/FloatTabs_Runtime_Lifecycle_Phase8_Adaptive_Memory_Budget_Implementation_Contract_V1.md) — **CURRENT PHASE 8 / ACCEPTED / FROZEN / IMPLEMENTATION NOT STARTED**;
- [`architecture/README.md`](architecture/README.md) — architecture routing/status;
- [`architecture/DOMAIN_MAP.md`](architecture/DOMAIN_MAP.md) — derived source/test/navigation map;
- [`architecture/archive/FloatTabs_Runtime_Lifecycle_Phase7_Closeout_Snapshot_2026-11-02.md`](architecture/archive/FloatTabs_Runtime_Lifecycle_Phase7_Closeout_Snapshot_2026-11-02.md) — archived Phase 7/V5 closeout snapshot.

Current mutation authorization comes only from `CURRENT_TASK.md`.

## 3. Current production vs target policy

### Current merged production

`main@2b414982710b3f042fc7d6e9c88eb2d7117b4e38` contains delivered Phase 7 behavior:

```text
Automatic / Keep Loaded
normal Automatic resident target = 2
Automatic inactive release path = 30s
warning target = 1
critical target = 0
```

These values remain runtime truth until Phase 8 implementation lands.

### Current frozen target

V6/Phase 8 supersedes the fixed-count normal policy with:

```text
Memory Budget = primary normal resource control
Auto / Custom / Unlimited
no normal fixed Runtime-count ceiling
progressive one-at-a-time reclaim
fresh resource remeasurement after each reclaim
independent system-memory-pressure ladder
```

Do not interpret V6 target behavior as already shipped production behavior.

## 4. Durable delivered lifecycle foundations

- Phase 1 Safe Hibernate + Restore — delivered / merged.
- Phase 2 Ready / Unread Decoupling — delivered / merged.
- Phase 3 Native Completion Notification — delivered / merged.
- Phase 4 managed Runtime-budget foundation — delivered; old residency policy superseded.
- Phase 5 Background Generation Thrift — delivered / merged.
- Phase 6 Perceived-fast Restore — delivered / merged in PR #187.
- Phase 7 Automatic Lifecycle Simplification + Legacy Residency Retirement — delivered / merged in PR #188 at `main@2b414982...`.

The Phase 1-7 architecture remains reusable under V6. V6 changes normal policy/measurement/reclaim strategy, not the core Slot/Profile/session vs Runtime ownership split.

## 5. Phase 8 target summary

The target policy is budget-driven:

```text
under budget
→ keep useful Runtime resident

above high watermark
→ choose one eligible inactive Automatic Runtime
→ hibernate through existing WebViewPool boundary
→ remeasure
→ stop when safe or continue one at a time
```

Initial V6 reference defaults:

```text
Auto budget = clamp(physical RAM × 20%, 1.5 GiB, 6 GiB)
Custom = user-selected approximate GiB budget
Unlimited = no normal budget reclaim
high watermark = 105%
low watermark = 90%
proactive long-idle cleanup = OFF by default
```

Active/presented, fullscreen, supplemental-visible, Attention Generating, protected background media and current materialization/restoring work remain hard-protected.

## 6. Background-generation boundary

Current/target product truth must distinguish:

- **generation continuity:** live generating Runtime remains protected;
- **host-side thrift:** probes/observers/diagnostics may be reduced safely while hidden;
- **renderer memory:** no claim of deep WebContent freeze while arbitrary JS/network generation continues through public WKWebView.

After completion, unread/native notification can survive without Runtime residency and the completed Runtime returns to normal lifecycle policy.

## 7. Current vs historical lifecycle documents

### Current authority

- `FloatTabs_Runtime_Lifecycle_Memory_Contract_V6.md`;
- `FloatTabs_Runtime_Lifecycle_Phase8_Adaptive_Memory_Budget_Implementation_Contract_V1.md`;
- `architecture/README.md` and `architecture/DOMAIN_MAP.md` for routing/navigation.

### Delivered / historical evidence

- `FloatTabs_Runtime_Lifecycle_Memory_Contract_V5.md` — delivered Phase 7 parent contract; **historical for new construction**;
- `FloatTabs_Runtime_Lifecycle_Phase7_Automatic_Lifecycle_Implementation_Contract_V1.md` — delivered Phase 7 implementation contract; **historical for new construction**;
- Phase 6 implementation contract after PR #187 merge;
- V1-V4 lifecycle contracts;
- old Phase 4 automatic-budget/count plans;
- delivered Phase 1-5 plans;
- old Stage residency/resource lifecycle docs and Stage 5E Hot/Warm/Cold benchmark material.

Do not rewrite historical evidence to mimic current V6 behavior. Route around it instead.

## 8. Phase 8 implementation routing

The frozen Phase 8 sequence is:

```text
WP0 measurement feasibility + exact source audit
WP1 passive budget config + resource monitor
WP2 budget scheduler + progressive reclaim
WP3 system-pressure ladder
WP4 Advanced Runtime & Memory settings + persistence/backup
WP5 background-generation/observer efficiency
WP6 Real-Mac + Phase7-vs-Phase8 identical-workload A/B evidence
```

Current design task authorizes docs/control changes only. Production construction requires a later explicit implementation authorization.

## 9. Resource-measurement rule

The target GiB budget depends on a production-safe aggregate FloatTabs/WebKit footprint estimate.

- aggregate application/helper attribution is allowed when supported and proven;
- exact per-Slot WebContent RSS is not available as a trustworthy public policy input;
- if production-safe aggregate measurement cannot be proven, Phase 8 must STOP rather than translate GiB into a disguised Runtime count.

## 10. Other bounded current contracts

- [`design/FloatTabs_UI_Design_System_v1.3.md`](design/FloatTabs_UI_Design_System_v1.3.md) — shell/rail interaction baseline where not superseded by newer bounded contracts or source/tests.
- [`design/FloatTabs_Attention_Active_Tab_Visual_Refinement_V1.md`](design/FloatTabs_Attention_Active_Tab_Visual_Refinement_V1.md) — accepted active-tab/unread visual refinement.

## 11. Directory routing

| Directory | Current role |
| --- | --- |
| `docs/architecture/` | Current architecture entry/contracts plus historical architecture evidence |
| `docs/architecture/archive/` | Explicit historical snapshots; never current task authority |
| `docs/design/` | Current bounded UI contracts plus historical design evidence |
| `docs/product/` | Historical/accepted feature contracts and old Stage plans |
| `docs/diagnostics/` | Diagnostic evidence unless promoted by current architecture routing |
| `docs/performance/` | Historical/tuning evidence unless current task explicitly adopts it |
| `docs/validation/` | Historical validation evidence; never task authorization |
| `docs/release/` | Historical release evidence |
| `docs/superpowers/` | Historical plans from older workflow |
| `docs/uiux/` | Generated/reference UI material unless explicitly promoted |

## 12. Conflict rule

When historical material disagrees with current source/tests or V6/current Phase 8 contracts:

1. distinguish current shipped production from frozen future target;
2. preserve historical files as evidence;
3. follow current Authority/current source for shipped truth;
4. follow V6/Phase 8 only for authorized future construction;
5. update routing/status when stale current-sounding wording could mislead future work.
