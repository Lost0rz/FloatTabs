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

For `FT-RUNTIME-LIFECYCLE-MEMORY-001`:

- [`architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V5.md`](architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V5.md) — **CURRENT / ACCEPTED / FROZEN** program contract;
- [`architecture/FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Implementation_Contract_V1.md`](architecture/FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Implementation_Contract_V1.md) — delivered Phase 6 scoped contract; PR #187 merged into `main@54f2e43b0fbc224affa52d9662ac2ba5aa5b963c`;
- [`architecture/FloatTabs_Runtime_Lifecycle_Phase7_Automatic_Lifecycle_Implementation_Contract_V1.md`](architecture/FloatTabs_Runtime_Lifecycle_Phase7_Automatic_Lifecycle_Implementation_Contract_V1.md) — **CURRENT PHASE 7 / ACCEPTED / FROZEN** implementation contract; product implementation and Real-Mac acceptance are complete on PR #188 pending final merge-host gate;
- [`architecture/README.md`](architecture/README.md) — architecture routing/status;
- [`architecture/DOMAIN_MAP.md`](architecture/DOMAIN_MAP.md) — derived source/test navigation only.

Current mutation authorization comes only from `CURRENT_TASK.md`.

## 3. Current lifecycle product truth

Phase 7 retires Hot/Warm/Cold as current product policy. The current model is:

```text
Automatic   — default
Keep Loaded — normal-operation retention preference

normal Automatic target   = 2
Automatic inactive grace  = 30 seconds
warning Automatic target  = 1
critical Automatic target = 0
```

Legacy compatibility remains bounded:

```text
hot       -> Keep Loaded
warm/cold -> Automatic
```

Browser Profile, cookie, login and website-session data are not lifecycle-reclaim data and must not be cleared by Runtime recovery/reclaim.

## 4. Program phase status

- Phase 1 Safe Hibernate + Restore — delivered / merged.
- Phase 2 Ready / Unread Decoupling — delivered / merged.
- Phase 3 Native Completion Notification — delivered / merged.
- Phase 4 managed Runtime-budget foundation — delivered / merged; legacy Hot/Warm/Cold policy superseded by Phase 7.
- Phase 5 Background Generation Thrift — delivered / merged.
- Phase 6 Perceived-fast Restore — delivered / merged in PR #187.
- Phase 7 Automatic Lifecycle Simplification + Legacy Residency Retirement — implementation complete on PR #188; required machine checks and bounded Real-Mac acceptance passed on semantic head `b894641a254e7ffb49c84b4ed32d9c70a3f28ad7`; final control-only closeout and literal-head merge gate remain.

## 5. Phase 6 / Phase 7 boundary

Phase 6 owns restore presentation/readiness after a Runtime has been reclaimed.

Phase 7 owns the policy deciding which inactive Runtime may remain resident. `SlotLifecycleCoordinator` remains the sole lifecycle writer; `WebViewPool` remains the Runtime mechanism owner.

## 6. Current vs historical lifecycle docs

Current:

- `FloatTabs_Runtime_Lifecycle_Memory_Contract_V5.md`;
- Phase 7 implementation contract for the current merge boundary;
- `architecture/README.md` and `architecture/DOMAIN_MAP.md` for routing/navigation.

Delivered/historical evidence:

- Phase 6 implementation contract after PR #187 merge;
- `FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md` through V4;
- old Phase 4 automatic-budget plan;
- delivered Phase 1-5 plans;
- old Stage residency/resource lifecycle docs and Stage 5E Hot/Warm/Cold benchmark material.

Do not rewrite historical evidence into current product truth.

## 7. Other bounded current contracts

- [`design/FloatTabs_UI_Design_System_v1.3.md`](design/FloatTabs_UI_Design_System_v1.3.md) — shell/rail interaction baseline where not superseded by newer bounded contracts or source/tests.
- [`design/FloatTabs_Attention_Active_Tab_Visual_Refinement_V1.md`](design/FloatTabs_Attention_Active_Tab_Visual_Refinement_V1.md) — accepted active-tab/unread visual refinement.

## 8. Directory routing

| Directory | Current role |
| --- | --- |
| `docs/architecture/` | Current architecture entry/contracts plus historical architecture evidence |
| `docs/design/` | Current bounded UI contracts plus historical design evidence |
| `docs/product/` | Historical/accepted feature contracts and old Stage plans |
| `docs/diagnostics/` | Diagnostic evidence unless promoted by current architecture routing |
| `docs/performance/` | Historical/tuning evidence unless current task explicitly adopts it |
| `docs/validation/` | Historical validation evidence; never task authorization |
| `docs/release/` | Historical release evidence |
| `docs/superpowers/` | Historical plans from older workflow |
| `docs/uiux/` | Generated/reference UI material unless explicitly promoted |

## 9. Conflict rule

When historical material disagrees with current source/tests or V5/current phase contracts:

1. preserve the historical file as evidence;
2. follow current Authority/current source;
3. update routing/status when the conflict could mislead future work.
