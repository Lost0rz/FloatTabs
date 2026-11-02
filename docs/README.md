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

- [`architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V6.md`](architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V6.md) — **CURRENT / ACCEPTED / FROZEN LONG-TERM DESIGN AUTHORITY**;
- [`architecture/FloatTabs_Runtime_Lifecycle_Phase8_Adaptive_Memory_Budget_Implementation_Contract_V1.md`](architecture/FloatTabs_Runtime_Lifecycle_Phase8_Adaptive_Memory_Budget_Implementation_Contract_V1.md) — **ORIGINAL PHASE 8 BUDGET CONTRACT / STOPPED AT GATE 0; budget construction deferred**;
- [`architecture/FloatTabs_Runtime_Lifecycle_Phase8_WP0_Measurement_Feasibility_Report_V1.md`](architecture/FloatTabs_Runtime_Lifecycle_Phase8_WP0_Measurement_Feasibility_Report_V1.md) — **WP0 COMPLETE / GATE 0 FAIL: deterministic aggregate WebContent/GPU attribution not available through supported public production APIs**;
- [`architecture/FloatTabs_Runtime_Lifecycle_Phase8_Pressure_Efficiency_Rescope_Contract_V1.md`](architecture/FloatTabs_Runtime_Lifecycle_Phase8_Pressure_Efficiency_Rescope_Contract_V1.md) — **CURRENT IMPLEMENTATION CONTRACT / ACCEPTED / FROZEN / D_COMBINE: pressure ladder + background efficiency now, aggregate budget later**;
- [`architecture/README.md`](architecture/README.md) — architecture routing/status;
- [`architecture/DOMAIN_MAP.md`](architecture/DOMAIN_MAP.md) — derived source/test/navigation map.

Current mutation authorization comes only from `CURRENT_TASK.md`.

## 3. Current production truth

Merged production still uses the delivered Phase 7 behavior until a successor implementation lands:

```text
Automatic / Keep Loaded
normal Automatic resident target = 2
Automatic inactive release path = 30s
warning target = 1
critical target = 0
```

For the current re-scope, the healthy/normal `target=2 + 30s` behavior is deliberately preserved. Only the warning/critical count targets are authorized to change, becoming a progressive pressure ladder.

## 4. D_COMBINE disposition

The user selected:

```text
B NOW
→ implement measurement-independent work:
   progressive system-pressure reclaim
   + background observer/task/generation efficiency

A LATER
→ keep aggregate memory-budget architecture deferred/platform-blocked
→ reopen only if supported deterministic helper attribution becomes available

C REJECTED
→ no correlation attribution, guessed per-tab memory or Runtime-count proxy
```

The long-term V6 budget design is therefore **deferred architecture**, not current implementation authority.

## 5. Current implementation target

### System-pressure ladder

```text
warning
→ one eligible inactive Automatic at a time
→ Keep Loaded preserved
→ revalidate current pressure + ownership between steps

critical
→ Automatic first
→ then inactive/unprotected Keep Loaded if still required
→ active/hard-protected untouched

normal pressure
→ cancel pending progression
→ no mass restore; restore remains demand-driven
```

### Background efficiency

Bounded host-side improvements may reduce redundant hidden fallback probes, repeated detector work, stale observer/tasks, duplicate registration and presentation-only work after detach/reclaim, while preserving generation/completion/session correctness.

No Settings or budget UI change belongs to the current re-scope.

## 6. Deferred aggregate-memory track

Blocked until a supported deterministic production capability exists:

- aggregate resource monitor as lifecycle input;
- Auto / Custom / Unlimited GiB budget;
- high/low budget watermarks;
- budget settings/persistence/backup projection;
- aggregate-memory A/B claims requiring attributable FloatTabs/WebKit working-set evidence.

Do not implement these from host+Networking-only measurement, transition correlation, private SPI, root-only tools, restricted entitlements, guessed per-tab MB or Runtime count.

## 7. Durable delivered lifecycle foundations

- Phase 1 Safe Hibernate + Restore — delivered / merged.
- Phase 2 Ready / Unread Decoupling — delivered / merged.
- Phase 3 Native Completion Notification — delivered / merged.
- Phase 4 managed Runtime-budget foundation — delivered; current lifecycle writer/recency/pressure primitives remain reusable.
- Phase 5 Background Generation Thrift — delivered / merged.
- Phase 6 Perceived-fast Restore — delivered / merged in PR #187.
- Phase 7 Automatic Lifecycle Simplification + Legacy Residency Retirement — delivered / merged in PR #188.

The persistent Slot/Profile/session vs disposable Runtime ownership split remains unchanged.

## 8. Current execution routing

```text
PR #190 WP0 + reconciliation closeout
→ literal new #190 head required CI
→ fresh exact-diff/base-head/mergeability check
→ merge #190
→ fresh main containing current task + re-scope contract
→ one successor implementation branch/PR
→ Gate R0 focused source reconciliation
→ pressure ladder implementation + focused verification
→ background-efficiency implementation + focused verification
→ full XCTest + Debug/Release arm64 + architecture
→ literal-head self-hosted macOS CI
→ fresh exact-diff/ownership audit
→ merge-readiness decision
```

Do not begin `FloatTabs/**` mutation on the #190 closeout branch.

## 9. Background-generation boundary

Current product truth must distinguish:

- **generation continuity:** live generating Runtime remains protected;
- **host-side thrift:** probes/observers/diagnostics may be reduced safely while hidden;
- **renderer memory:** no claim of deep WebContent freeze or memory reduction from host-side timer/observer changes.

After completion, unread/native notification semantics and exact Slot/session restore remain intact.

## 10. Current vs historical lifecycle documents

### Current authority

- `FloatTabs_Runtime_Lifecycle_Memory_Contract_V6.md` — long-term design direction;
- `FloatTabs_Runtime_Lifecycle_Phase8_Pressure_Efficiency_Rescope_Contract_V1.md` — current bounded implementation contract;
- `FloatTabs_Runtime_Lifecycle_Phase8_WP0_Measurement_Feasibility_Report_V1.md` — current platform-boundary evidence;
- `architecture/README.md` and `architecture/DOMAIN_MAP.md` for routing/navigation.

### Stopped / deferred contract

- `FloatTabs_Runtime_Lifecycle_Phase8_Adaptive_Memory_Budget_Implementation_Contract_V1.md` — accepted historical Phase 8 implementation contract, stopped at Gate 0; its budget construction sequence is not currently executable.

### Delivered / historical evidence

- `FloatTabs_Runtime_Lifecycle_Memory_Contract_V5.md`;
- `FloatTabs_Runtime_Lifecycle_Phase7_Automatic_Lifecycle_Implementation_Contract_V1.md`;
- Phase 1-6 implementation contracts and older lifecycle plans;
- old Stage residency/resource lifecycle docs and Hot/Warm/Cold benchmark material.

Preserve historical evidence; do not rewrite it to mimic current re-scope semantics.

## 11. Other bounded current contracts

- [`design/FloatTabs_UI_Design_System_v1.3.md`](design/FloatTabs_UI_Design_System_v1.3.md) — shell/rail interaction baseline where not superseded by newer bounded contracts or source/tests.
- [`design/FloatTabs_Attention_Active_Tab_Visual_Refinement_V1.md`](design/FloatTabs_Attention_Active_Tab_Visual_Refinement_V1.md) — accepted active-tab/unread visual refinement.

## 12. Directory routing

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

## 13. Conflict rule

When historical material disagrees with current source/tests or current re-scope Authority:

1. distinguish shipped production from future/deferred V6 target;
2. follow `CURRENT_TASK.md` + current re-scope contract for authorized mutation;
3. preserve the WP0 platform boundary unless new supported evidence disproves it;
4. do not promote a blocked budget concept into production by approximation;
5. update routing/status when stale current-sounding wording could mislead future work.
