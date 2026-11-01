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
- [`architecture/FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Implementation_Contract_V1.md`](architecture/FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Implementation_Contract_V1.md) — **CURRENT PHASE 6 / ACCEPTED / FROZEN / EXECUTION ACTIVE / GATE 0 OUTCOME A**;
- [`architecture/FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Audit_V1.md`](architecture/FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Audit_V1.md) — **PHASE 6 AUDIT / RATIONALE EVIDENCE**; execution scope is superseded by the Phase 6 implementation contract;
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
- Phase 5 Long-running Background Generation Thrift — delivered in PR #183 / `745d401bf9f282d19bc756c81be3f46f17161e4b`.
- Phase 6 Perceived-fast Restore — audit complete; implementation contract **accepted/frozen**; execution **active**; WP0 / Gate 0 completed with **Outcome A — navigation-backed readiness**; product mutation is released within the frozen scope and WP1 is active.

The old [`architecture/FloatTabs_Runtime_Lifecycle_Phase4_Automatic_Runtime_Budget_Policy_Plan_V1.md`](architecture/FloatTabs_Runtime_Lifecycle_Phase4_Automatic_Runtime_Budget_Policy_Plan_V1.md) is historical Phase 4 planning evidence. Its strict benchmark-selection gate was superseded by the user's later reference-derived-default decision and is not current execution authority.

Likewise `FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md`, V2 and V3 are superseded historical contracts for current execution.

## 5. Phase 4 tuning status

The production Phase 4 default managed target is currently 3 Warm/Cold runtimes as a conservative reference-derived assumption, not measured optimum.

The old strict `1 / 2 / 4 / 8` scale matrix, drift baseline, `4 → 3 → 2` candidate tournament and restore-latency tuning are deferred. Future tuning should prefer Settings-backed conservative presets/overrides rather than permanently hard-coding one machine-independent optimum. Safety protections remain non-overridable.

## 6. Phase 6 current status

Selected architecture:

```text
native restore shell immediately
→ return to AppKit run loop
→ bounded deferred fresh Runtime materialization
→ attach fresh WebView under restoring surface
→ exact-current-Runtime navigation-backed readiness
→ existing focus handoff
```

Resident Slot switching remains direct.

The prior future-session hold was released by the user's explicit start instruction on `2026-11-01`. The active task remains `FT-RUNTIME-LIFECYCLE-MEMORY-001`; no successor task or redesign is required.

### Gate 0 result

The mandatory Real-Mac Gate 0 ran against an actually hibernated existing Slot and completed with **Outcome A**:

- hibernate captured a memory-local interaction state and reclaimed the old Runtime;
- reactivation created a fresh Runtime through the existing `WebViewPool` interaction-state restore path;
- the exact fresh Runtime emitted `navigation.provisional_started → navigation.commit → navigation.finished`, with the callbacks classified non-stale;
- the existing bounded cross-world observation on the same Runtime also succeeded and reported a current, complete, non-loading renderer;
- focus recognition succeeded and no duplicate ordinary URL load was required.

The verification made no source change, did not reset Browser Profile/session/persistent data, and restored the temporary Slot policy/active/panel state afterward.

Therefore Phase 6 may use the existing exact-current-Runtime navigation completion path as its readiness trigger. `web_runtime.restore.completed` remains state-handoff evidence only, not readiness truth.

### Current work

Execution now proceeds directly through:

```text
WP1 native restoring presentation
→ WP2 two-stage PanelController materialization
→ WP3 Outcome-A navigation-backed completion
→ WP4 focused/full verification + required CI + Real-Mac smoke + independent audit
```

The current source already contains the required navigation owner: `SlotNavigationObserver` has a bounded `onNavigationFinish` seam. Phase 6 should reuse that existing finish fact through the smallest `WebViewPool` projection instead of adding a new readiness probe or changing restore semantics.

## 7. Other bounded current contracts

- [`design/FloatTabs_UI_Design_System_v1.3.md`](design/FloatTabs_UI_Design_System_v1.3.md) — shell/rail interaction baseline where not superseded by newer bounded contracts or production source/tests.
- [`design/FloatTabs_Attention_Active_Tab_Visual_Refinement_V1.md`](design/FloatTabs_Attention_Active_Tab_Visual_Refinement_V1.md) — accepted active-tab/unread visual refinement.

## 8. Historical by default

Treat as historical evidence unless current Authority explicitly restores a claim:

- old Runtime Lifecycle contract versions;
- delivered/superseded phase plans;
- Stage documents and archived plans;
- point-in-time audits;
- old benchmark protocols/results;
- validation/release records;
- generated reference UI material.

Do not rewrite historical evidence to make it look current. Update routing/status instead.

## 9. Directory routing

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

## 10. Conflict rule

When historical material disagrees with current source/tests or a newer accepted contract:

1. preserve the historical file as evidence;
2. follow current Authority/current source;
3. update routing/status when the conflict could mislead future work.
