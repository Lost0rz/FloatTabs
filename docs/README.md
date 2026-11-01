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

A historical document does not become current Authority because it contains labels such as `canonical`, `FROZEN`, `accepted` or `current`.

## 2. Current Runtime Lifecycle / Memory authority

For `FT-RUNTIME-LIFECYCLE-MEMORY-001`:

- [`architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V3.md`](architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V3.md) — accepted/frozen program contract and machine-first intermediate cadence;
- [`architecture/FloatTabs_Runtime_Lifecycle_Phase4_Automatic_Runtime_Budget_Policy_Plan_V1.md`](architecture/FloatTabs_Runtime_Lifecycle_Phase4_Automatic_Runtime_Budget_Policy_Plan_V1.md) — **ACTIVE / ACCEPTED / FROZEN** Phase 4 plan;
- [`architecture/README.md`](architecture/README.md) — architecture routing/status;
- [`architecture/DOMAIN_MAP.md`](architecture/DOMAIN_MAP.md) — derived source/test navigation only.

Current task authorization comes only from `CURRENT_TASK.md`. Production truth still comes from current source/tests/fresh evidence.

## 3. Runtime Lifecycle V3 cadence

```text
phase-focused audit / freeze
→ implementation
→ phase-local machine verification + required CI
→ merge
→ next architecture phase
...
Phases 1–6 structurally complete
→ one unified independent program audit
→ one user-owned full human acceptance pass
→ final closeout / release decision
```

Do not use superseded per-phase human-acceptance or formal-audit wording to block intermediate phases.

Phase 4 is different from ordinary intermediate phases only in one respect: its Real-Mac 1/2/4/8 scale benchmark is required **machine design evidence** because the production Runtime budget must be selected from data rather than guessed.

## 4. Current / delivered phase plans

- [`architecture/FloatTabs_Runtime_Lifecycle_Phase4_Automatic_Runtime_Budget_Policy_Plan_V1.md`](architecture/FloatTabs_Runtime_Lifecycle_Phase4_Automatic_Runtime_Budget_Policy_Plan_V1.md) — **ACTIVE** Phase 4 implementation/evidence plan.
- [`architecture/FloatTabs_Runtime_Lifecycle_Phase3_Native_Completion_Notification_Plan_V2.md`](architecture/FloatTabs_Runtime_Lifecycle_Phase3_Native_Completion_Notification_Plan_V2.md) — delivered Phase 3 evidence; Phase 3 merged at `e182dd51a1bfd21a614e09f33643bf4acea551dc`.
- `architecture/FloatTabs_Runtime_Lifecycle_Phase3_Native_Completion_Notification_Plan_V1.md` — superseded Phase 3 freeze evidence.
- [`architecture/FloatTabs_Runtime_Lifecycle_Phase2_Ready_Unread_Decoupling_Plan_V2.md`](architecture/FloatTabs_Runtime_Lifecycle_Phase2_Ready_Unread_Decoupling_Plan_V2.md) — delivered Phase 2 evidence.
- [`architecture/FT_RUNTIME_LIFECYCLE_PHASE2_SCOPE_RECONCILIATION_001.md`](architecture/FT_RUNTIME_LIFECYCLE_PHASE2_SCOPE_RECONCILIATION_001.md) — delivered Phase 2 corrective evidence.
- [`architecture/FloatTabs_Runtime_Lifecycle_Phase1_Safe_Hibernate_Restore_Plan_V2.md`](architecture/FloatTabs_Runtime_Lifecycle_Phase1_Safe_Hibernate_Restore_Plan_V2.md) — delivered Phase 1 evidence.

Delivered phase plans do not authorize mutation in the active phase unless `CURRENT_TASK.md` explicitly restores them.

## 5. Other current bounded contracts

- [`design/FloatTabs_UI_Design_System_v1.3.md`](design/FloatTabs_UI_Design_System_v1.3.md) — shell/rail interaction baseline where not superseded by newer bounded contracts or production source/tests.
- [`design/FloatTabs_Attention_Active_Tab_Visual_Refinement_V1.md`](design/FloatTabs_Attention_Active_Tab_Visual_Refinement_V1.md) — accepted active-tab/unread visual refinement.

Browser Profile, diagnostics, Attention/Unread and menu-bar historical contracts may still contain useful durable concepts, but current V3/current task/source win on conflicts.

## 6. Historical by default

Unless current Authority explicitly restores a claim, treat as historical evidence only:

- Stage documents and archived plans;
- old Runtime Lifecycle contract versions;
- superseded phase plans;
- point-in-time audits;
- old product/technical architecture specs;
- old benchmark protocols/results;
- validation/release records;
- generated reference UI material.

Historical evidence may inform current design but cannot override current task scope or production truth.

## 7. Directory routing

| Directory | Current role |
| --- | --- |
| `docs/architecture/` | Current architecture entry/contracts plus historical architecture evidence |
| `docs/design/` | Current bounded UI contracts plus historical design evidence |
| `docs/product/` | Historical/accepted feature contracts and old Stage plans; use `product/README.md` first |
| `docs/diagnostics/` | Diagnostic evidence unless promoted by current architecture routing |
| `docs/performance/` | Historical benchmark evidence unless current task explicitly adopts a protocol |
| `docs/validation/` | Historical validation evidence; never task authorization |
| `docs/release/` | Historical release evidence |
| `docs/superpowers/` | Historical plans from older workflow |
| `docs/uiux/` | Generated/reference UI material unless explicitly promoted |

## 8. Conflict rule

When historical material disagrees with current source/tests or a newer accepted contract:

1. preserve the historical file as evidence;
2. do not rewrite its historical result;
3. follow current Authority/current source;
4. update routing/status when the conflict could mislead future work.

For the active Runtime Lifecycle program, old timer-only Residency assumptions do not override the Phase 4 V1 automatic-budget plan. Phase 4 nevertheless explicitly preserves Hot as a user pin and preserves stored Hot/Warm/Cold raw values unless a future accepted contract says otherwise.
