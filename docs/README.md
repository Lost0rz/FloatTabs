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
- [`architecture/FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Implementation_Contract_V1.md`](architecture/FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Implementation_Contract_V1.md) — **CURRENT PHASE 6 / ACCEPTED / FROZEN / EXECUTION ACTIVE / GATE 0 OUTCOME A / WP4 CORRECTIVE**;
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
- Phase 6 Perceived-fast Restore — Gate 0 complete with Outcome A; WP1–WP3 implemented; local/full machine checks and implementation-head CI passed; WP4 independent exact-diff audit found four bounded correctives, so merge readiness is currently blocked pending corrective + fresh verification.

The old [`architecture/FloatTabs_Runtime_Lifecycle_Phase4_Automatic_Runtime_Budget_Policy_Plan_V1.md`](architecture/FloatTabs_Runtime_Lifecycle_Phase4_Automatic_Runtime_Budget_Policy_Plan_V1.md) is historical Phase 4 planning evidence. Its strict benchmark-selection gate was superseded by the user's later reference-derived-default decision and is not current execution authority.

Likewise `FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md`, V2 and V3 are superseded historical contracts for current execution.

## 5. Phase 4 tuning status

The production Phase 4 default managed target is currently 3 Warm/Cold runtimes as a conservative reference-derived assumption, not measured optimum.

The old strict `1 / 2 / 4 / 8` scale matrix, drift baseline, `4 → 3 → 2` candidate tournament and restore-latency tuning are deferred. Future tuning should prefer Settings-backed conservative presets/overrides rather than permanently hard-coding one machine-independent optimum. Safety protections remain non-overridable.

## 6. Phase 6 current status

Selected architecture remains:

```text
native restore shell immediately
→ return to AppKit run loop
→ bounded deferred fresh Runtime materialization
→ attach fresh WebView under restoring surface
→ exact-current-Runtime navigation-backed readiness
→ remove restoring surface
→ existing focus/input handoff
```

Resident Slot switching remains direct.

### Gate 0 result

The mandatory Real-Mac Gate 0 ran against an actually hibernated existing Slot and completed with **Outcome A**. Compatible `interactionState` restore created a fresh Runtime and that exact Runtime emitted `navigation.provisional_started → navigation.commit → navigation.finished` with non-stale correlation. Existing bounded cross-world liveness also succeeded. No restore semantic rewrite, duplicate ordinary URL load, Browser Profile/session reset, private API or arbitrary readiness timer was required.

### WP1–WP3 implementation

Implementation head `0ad45bff7869cdf66ac26994396ff013c89b0fbe` delivered the authorized paths only:

- native restoring presentation in `WebPanelContainerView`;
- deferred two-stage materialization + generation-scoped stale rejection in `PanelController`;
- exact-current Runtime navigation completion/failure projection through `SlotNavigationObserver` / `WebViewPool`;
- focused regression coverage.

Focused tests, full XCTest, Debug/Release native arm64, required macOS CI run 1302 and QA DMG run 627 passed on that implementation head.

### WP4 independent exact-diff audit

WP4 is **ACTIVE / CHANGES REQUIRED**. Four bounded issues must be corrected before merge:

1. native/DOM focus can resume before approved `navigation.finished` readiness;
2. the underlying WebView can be treated as physically user-visible/Attention-acknowledgeable while the opaque restoring surface still covers it;
3. the hidden restoring spinner can continue animating because the overlay stays attached;
4. recoverable provisional HTTP-entry fallback is currently projected as terminal before fallback classification.

These are corrective implementation details inside the frozen Phase 6 paths, not an architecture redesign. Current Authority is `CURRENT_STATUS.md` / `CURRENT_TASK.md`; PR #187 review `5728444391` is the audit evidence record.

Next sequence:

```text
bounded C1–C4 corrective
→ focused/full tests + Debug/Release arm64
→ fresh literal-head required CI
→ bounded Real-Mac WP4 smoke
→ fresh independent exact-diff audit
→ merge readiness decision
```

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
