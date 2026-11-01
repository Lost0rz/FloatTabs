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

- [`architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V5.md`](architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V5.md) — **CURRENT / ACCEPTED / FROZEN** program contract; supersedes V4 for current execution;
- [`architecture/FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Implementation_Contract_V1.md`](architecture/FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Implementation_Contract_V1.md) — **CURRENT PR #187-SCOPED PHASE 6 CONTRACT**; Phase 6 closeout remains pending;
- [`architecture/FloatTabs_Runtime_Lifecycle_Phase7_Automatic_Lifecycle_Implementation_Contract_V1.md`](architecture/FloatTabs_Runtime_Lifecycle_Phase7_Automatic_Lifecycle_Implementation_Contract_V1.md) — **CURRENT PHASE 7 / ACCEPTED / FROZEN / IMPLEMENTATION NOT STARTED**;
- [`architecture/FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Audit_V1.md`](architecture/FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Audit_V1.md) — Phase 6 rationale evidence;
- [`architecture/README.md`](architecture/README.md) — architecture routing/status;
- [`architecture/DOMAIN_MAP.md`](architecture/DOMAIN_MAP.md) — derived source/test navigation only.

Current mutation authorization comes only from `CURRENT_TASK.md`.

## 3. Contract reconciliation

Fresh Real-Mac QA plus source audit showed that V4 cannot be the program-final contract because current Phase 4 semantics remain a hybrid legacy model:

```text
Hot       -> explicit normal/critical automatic-budget exclusion
Warm/Cold -> automatic budget + separate user timers
managed target -> 3
```

Current UI and persistence still expose those classes. Several legacy Hot ChatGPT Slots may therefore remain resident indefinitely by design.

V5 retains all delivered lifecycle foundations and Phase 6 restore, but adds a final Phase 7 that retires Hot/Warm/Cold from current product semantics.

Target model:

```text
Automatic (default)
Keep Loaded (normal-operation preference)
```

Initial Automatic defaults:

```text
normal target 2
30s inactive grace
warning target 1
critical target 0
```

Legacy Hot maps to Keep Loaded; Warm/Cold map to Automatic. Browser Profile/session data remains untouched.

## 4. Program phase status

- Phase 1 Safe Hibernate + Restore — delivered.
- Phase 2 Ready / Unread Decoupling — delivered.
- Phase 3 Native Completion Notification — delivered.
- Phase 4 Reference-derived managed budget — delivered foundation; final Hot/Warm/Cold policy superseded by V5 Phase 7 target.
- Phase 5 Background Generation Thrift — delivered.
- Phase 6 Perceived-fast Restore — implemented on PR #187; corrective head machine gates pass; bounded Real-Mac smoke + fresh exact-diff audit still required before merge.
- Phase 7 Automatic Lifecycle Simplification + Legacy Residency Retirement — contract frozen; implementation held until Phase 6 merge and explicit user start.

## 5. Phase 6 / Phase 7 boundary

Phase 6 owns only the restore experience after a Runtime has been reclaimed.

Phase 7 owns the final automatic policy deciding which inactive Runtime may remain resident.

Do not solve Phase 7 by expanding PR #187 product code. Finish and merge the Phase 6 prerequisite first, then implement Phase 7 from fresh main.

## 6. Current vs historical lifecycle docs

Current:

- `FloatTabs_Runtime_Lifecycle_Memory_Contract_V5.md`;
- Phase 6 implementation contract for PR #187 scope;
- Phase 7 implementation contract for next construction.

Historical/superseded for current execution:

- `FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md` through V4;
- old Phase 4 automatic-budget plan;
- delivered Phase 1-5 plans;
- old Stage residency/resource lifecycle docs.

Do not rewrite historical documents to mimic current truth.

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
