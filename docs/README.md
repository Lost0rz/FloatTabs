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

- [`architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V4.md`](architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V4.md) — **CURRENT / ACCEPTED / FROZEN** program contract;
- [`architecture/FloatTabs_Runtime_Lifecycle_Phase5_Background_Generation_Thrift_Plan_V1.md`](architecture/FloatTabs_Runtime_Lifecycle_Phase5_Background_Generation_Thrift_Plan_V1.md) — **ACTIVE / ACCEPTED / FROZEN** Phase 5 plan;
- [`architecture/README.md`](architecture/README.md) — architecture routing/status;
- [`architecture/DOMAIN_MAP.md`](architecture/DOMAIN_MAP.md) — derived source/test navigation only.

Current mutation authorization comes only from `CURRENT_TASK.md`. Production truth still comes from current source/tests/fresh evidence.

## 3. Program cadence

```text
phase-focused audit / freeze
→ bounded implementation
→ phase-local machine verification + required CI
→ merge
→ next architecture phase
...
Phases 1–6 structurally complete
→ one fresh integrated independent audit
→ one user-owned full human acceptance pass
→ final closeout / release decision
```

Do not use superseded per-phase human-acceptance wording to block intermediate phases.

## 4. Current and delivered phases

- Phase 1 Safe Hibernate + Restore — delivered.
- Phase 2 Ready / Unread Decoupling — delivered.
- Phase 3 Native ChatGPT Completion Notification — delivered.
- Phase 4 Reference-derived Automatic Runtime Management — delivered in PR #181 / `c910441a954bddbaeca710395cd0d6ed89ec5e5c`.
- Phase 5 Long-running Background Generation Thrift — **active** under the Phase 5 V1 plan.
- Phase 6 Perceived-fast Restore — not started / not authorized.

The old [`architecture/FloatTabs_Runtime_Lifecycle_Phase4_Automatic_Runtime_Budget_Policy_Plan_V1.md`](architecture/FloatTabs_Runtime_Lifecycle_Phase4_Automatic_Runtime_Budget_Policy_Plan_V1.md) is historical Phase 4 planning evidence. Its strict benchmark-selection gate was superseded by the user's later reference-derived-default decision and is not current execution authority.

Likewise `FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md`, V2 and V3 are superseded historical contracts for current execution.

## 5. Phase 4 tuning status

The production Phase 4 default managed target is currently 3 Warm/Cold runtimes as a conservative reference-derived assumption, not measured optimum.

The old strict `1 / 2 / 4 / 8` scale matrix, drift baseline, `4 → 3 → 2` candidate tournament and restore-latency tuning are deferred. Future tuning should prefer Settings-backed conservative presets/overrides rather than permanently hard-coding one machine-independent optimum. Safety protections remain non-overridable.

## 6. Other bounded current contracts

- [`design/FloatTabs_UI_Design_System_v1.3.md`](design/FloatTabs_UI_Design_System_v1.3.md) — shell/rail interaction baseline where not superseded by newer bounded contracts or production source/tests.
- [`design/FloatTabs_Attention_Active_Tab_Visual_Refinement_V1.md`](design/FloatTabs_Attention_Active_Tab_Visual_Refinement_V1.md) — accepted active-tab/unread visual refinement.

## 7. Historical by default

Treat as historical evidence unless current Authority explicitly restores a claim:

- old Runtime Lifecycle contract versions;
- delivered/superseded phase plans;
- Stage documents and archived plans;
- point-in-time audits;
- old benchmark protocols/results;
- validation/release records;
- generated reference UI material.

Do not rewrite historical evidence to make it look current. Update routing/status instead.

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

When historical material disagrees with current source/tests or a newer accepted contract:

1. preserve the historical file as evidence;
2. follow current Authority/current source;
3. update routing/status when the conflict could mislead future work.
