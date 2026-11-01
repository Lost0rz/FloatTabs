# FloatTabs Documentation Authority / Status Index

> **Current document-routing index.** Read this before using any document under `docs/` for implementation decisions.

## 1. Authority order

Repository engineering authority is:

```text
AGENTS.md
→ CURRENT_STATUS.md
→ CURRENT_TASK.md
→ this docs/README.md routing index
→ current architecture/design contract explicitly linked by current Authority
→ docs/architecture/DOMAIN_MAP.md for navigation only
→ current production source + regression tests + fresh runtime/repository evidence
```

A document does **not** become current Authority merely because its body contains words such as `canonical`, `FROZEN`, `LOCKED`, `accepted`, `implemented`, `current`, or `CONSTRUCTION_GATE_READY`. Those labels describe the document's historical acceptance context unless current Authority explicitly restores it.

## 2. Current cross-cutting contracts

These are current entry points when their scope applies:

- [`architecture/README.md`](architecture/README.md) — current architecture-document routing and status.
- [`architecture/DOMAIN_MAP.md`](architecture/DOMAIN_MAP.md) — derived source/Domain/test navigation; not task Authority.
- [`architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V3.md`](architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V3.md) — accepted/frozen current Runtime Lifecycle / Memory program contract and program-level verification/acceptance cadence.
- [`architecture/FloatTabs_Runtime_Lifecycle_Phase3_Native_Completion_Notification_Plan_V1.md`](architecture/FloatTabs_Runtime_Lifecycle_Phase3_Native_Completion_Notification_Plan_V1.md) — accepted/frozen active Phase 3 implementation plan.
- [`design/FloatTabs_UI_Design_System_v1.3.md`](design/FloatTabs_UI_Design_System_v1.3.md) — current shell/rail interaction baseline where not superseded by a newer bounded design contract or production source/tests.
- [`design/FloatTabs_Attention_Active_Tab_Visual_Refinement_V1.md`](design/FloatTabs_Attention_Active_Tab_Visual_Refinement_V1.md) — accepted active-tab/unread visual refinement for its bounded UI surface.

Current implementation truth still comes from production source/tests and fresh evidence. Current task authorization still comes only from `CURRENT_TASK.md`.

## 3. Runtime Lifecycle V3 execution cadence

For `FT-RUNTIME-LIFECYCLE-MEMORY-001`, Program Contract V3 uses this sequence:

```text
phase-focused audit / freeze
→ implementation
→ phase-local machine verification + required CI
→ merge
→ continue next architecture phase
...
Phases 1–6 structurally complete
→ one unified independent program audit
→ one user-owned full human acceptance pass
→ final closeout / release decision
```

Do not use older per-phase human acceptance or per-phase formal-audit wording to block an intermediate phase when current V3 Authority has deferred those gates to the final integrated architecture.

Phase-specific machine evidence that determines architecture remains phase-local. In particular, Phase 4 still owns the scale/performance benchmark required to choose Runtime Budget/policy.

## 4. Current / delivered Runtime Lifecycle phase plans

- [`architecture/FloatTabs_Runtime_Lifecycle_Phase3_Native_Completion_Notification_Plan_V1.md`](architecture/FloatTabs_Runtime_Lifecycle_Phase3_Native_Completion_Notification_Plan_V1.md) — **ACTIVE / ACCEPTED / FROZEN** Phase 3 plan.
- [`architecture/FloatTabs_Runtime_Lifecycle_Phase2_Ready_Unread_Decoupling_Plan_V2.md`](architecture/FloatTabs_Runtime_Lifecycle_Phase2_Ready_Unread_Decoupling_Plan_V2.md) — delivered Phase 2 semantic/implementation evidence; Phase 2 is complete and merged.
- [`architecture/FT_RUNTIME_LIFECYCLE_PHASE2_SCOPE_RECONCILIATION_001.md`](architecture/FT_RUNTIME_LIFECYCLE_PHASE2_SCOPE_RECONCILIATION_001.md) — accepted Phase 2 test-only corrective evidence.
- [`architecture/FloatTabs_Runtime_Lifecycle_Phase1_Safe_Hibernate_Restore_Plan_V2.md`](architecture/FloatTabs_Runtime_Lifecycle_Phase1_Safe_Hibernate_Restore_Plan_V2.md) — delivered Phase 1 plan evidence.

Delivered phase plans do not authorize mutation in the active phase unless current `CURRENT_TASK.md` explicitly says so.

## 5. Accepted feature contracts versus historical execution documents

Some feature contracts remain useful because they define durable product concepts. They are **bounded references**, not global current Authority.

Examples:

- Browser Profiles contracts: durable Profile/data-isolation concepts remain relevant, but old lifecycle/Hot-Warm-Cold wording yields to current Runtime source/tests and the current lifecycle contract.
- Runtime Diagnostics contract: durable evidence-plane/privacy/ownership boundaries remain relevant, but old task/gate/incident statements are historical.
- ChatGPT Attention/Unread contracts and amendments: useful historical semantics/evidence, but current Attention/Unread behavior is defined by production source/tests, Program Contract V3 and the active Phase 3 plan.
- Menu Bar feature contracts: bounded historical/accepted feature references; current source and newer design/architecture contracts win on conflicts.

See [`product/README.md`](product/README.md) for per-category routing.

## 6. Runtime Lifecycle historical routing

The following remain historical evidence and must not override current V3/current task Authority:

- `architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md`
- `architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V2.md`
- `architecture/FloatTabs_Runtime_Lifecycle_Phase1_Safe_Hibernate_Restore_Plan_V1.md`
- `architecture/FloatTabs_Runtime_Lifecycle_Phase2_Ready_Unread_Decoupling_Plan_V1.md`

V2 remains useful evidence for separating structural correctness from Phase 4 scale tuning. V3 supersedes its repeated per-phase acceptance cadence for current program execution.

## 7. Historical by default

Unless current Authority explicitly restores a claim, treat these classes as **historical evidence only**:

- files named `Stage_*` or `FloatTabs_Stage_*`;
- dated plans and all `superpowers/plans/*`;
- `*_Construction_Plan_*` after the feature/task closed;
- point-in-time audits such as `FT-DIAG-*` audit reports;
- old product specs such as `FloatTabs_Product_Development_Spec_v0.5.md`;
- old technical architecture versions such as `FloatTabs_Technical_Architecture_v1.2.md`;
- benchmark protocols tied to an earlier lifecycle/product model;
- validation/acceptance files for historical Stages;
- release records and release baselines;
- anything under an `archive/` directory;
- generated Stitch/UI reference assets unless a current design contract explicitly points to them.

Historical documents may contain accurate observations or useful rationale. They must not override current task scope, current product source/tests, or a newer accepted contract.

## 8. Directory routing

| Directory | Current role |
| --- | --- |
| `docs/architecture/` | Current architecture entry/contracts plus clearly marked historical architecture baselines |
| `docs/design/` | Current bounded UI contracts plus historical Stage/rendering design evidence |
| `docs/product/` | Historical/accepted feature contracts, amendments, old specs and Stage plans; use `product/README.md` first |
| `docs/diagnostics/` | Point-in-time diagnostic audits/evidence unless architecture README explicitly promotes a current contract |
| `docs/performance/` | Historical benchmark protocols/results unless current task explicitly adopts one |
| `docs/validation/` | Historical acceptance/validation evidence; never current task authorization |
| `docs/release/` | Historical release records/evidence |
| `docs/superpowers/` | Historical plans from an older workflow; never current Engineering Governance authority |
| `docs/uiux/` | Generated/reference UI material; non-authoritative unless explicitly linked by current design contract |

## 9. Conflict rule

When a historical document disagrees with current source/tests or a newer accepted contract:

1. preserve the historical document as evidence;
2. do not silently rewrite its historical result;
3. follow current Authority/current source;
4. add/update a status banner or routing index if the conflict could mislead future work.

For the active Runtime Lifecycle / Memory program, old Hot/Warm/Cold Stage contracts, old Attention residency-protection contracts and superseded per-phase acceptance gates are historical inputs only. They do not override `CURRENT_TASK.md`, `architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V3.md`, or the active Phase 3 plan.
