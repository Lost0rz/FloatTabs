# FloatTabs — Architecture Document Status

Read [`../README.md`](../README.md) first. It is the repository-wide documentation authority/status index.

Use this file to distinguish current architecture navigation/contracts from historical architecture and Stage documents.

## Current navigation

For source/Authority routing, use:

- [`DOMAIN_MAP.md`](DOMAIN_MAP.md) — derived Domain/source/test navigation map;
- production code and regression tests on the current Delivery / Semantic HEAD.

`DOMAIN_MAP.md` is navigation only. It does not override product/design contracts or `CURRENT_TASK.md`.

## Current Runtime Lifecycle / Memory authority

For `FT-RUNTIME-LIFECYCLE-MEMORY-001`, current architecture authority is:

- [`FloatTabs_Runtime_Lifecycle_Memory_Contract_V2.md`](FloatTabs_Runtime_Lifecycle_Memory_Contract_V2.md) — **ACCEPTED / FROZEN** current program-level contract;
- [`FloatTabs_Runtime_Lifecycle_Phase1_Safe_Hibernate_Restore_Plan_V2.md`](FloatTabs_Runtime_Lifecycle_Phase1_Safe_Hibernate_Restore_Plan_V2.md) — **ACCEPTED / FROZEN** current Phase 1 implementation plan;
- `CURRENT_STATUS.md` — current program/phase/evidence state;
- `CURRENT_TASK.md` — the only active execution authorization;
- production code/tests/fresh runtime evidence.

The V2 program contract preserves the accepted target architecture — persistent Slot/Profile/product state with disposable `WKWebView` Runtime cache — and refreezes the program cadence as architecture-first:

```text
structural correctness
→ bounded live Runtime validation
→ merge
→ dependent architecture phases
→ scale benchmark / policy tuning when Phase 4 needs it
```

Phase 1 no longer requires the strict 1/2/4/8 scale benchmark as a merge blocker. That matrix, control-drift study, heavy 4/8 repeated runs, restore distribution and final Runtime-budget decision belong to Phase 4 Runtime Budget / Policy.

Phase 1 still requires deterministic teardown, restore correctness, stale-callback safety, Browser Profile/session safety, focused/full tests, Debug/Release builds, bounded 1–2 Slot live Runtime smoke, required PR CI and independent web audit.

## Superseded Runtime Lifecycle documents

- [`FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md`](FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md) — historical program-contract evidence. Its strict Phase 1 scale-benchmark/STOP gate is superseded by V2.
- [`FloatTabs_Runtime_Lifecycle_Phase1_Safe_Hibernate_Restore_Plan_V1.md`](FloatTabs_Runtime_Lifecycle_Phase1_Safe_Hibernate_Restore_Plan_V1.md) — historical Phase 1 audit/plan evidence. Its 1/2/4/8 benchmark acceptance gate is superseded by the V2 plan.

Their audit facts and rationale remain useful historical evidence where they do not conflict with current V2 Authority.

## Current behavior

For shell interaction, rail geometry, movement, resize and fullscreen coordination, use:

- [`../design/FloatTabs_UI_Design_System_v1.3.md`](../design/FloatTabs_UI_Design_System_v1.3.md) for unaffected shell/rail behavior;
- [`../design/FloatTabs_Attention_Active_Tab_Visual_Refinement_V1.md`](../design/FloatTabs_Attention_Active_Tab_Visual_Refinement_V1.md) for the accepted active-Tab and unread-Attention refinement merged in PR #146;
- production code and regression tests on `main`;
- the current release record under `../release/` only as version-specific historical evidence.

Where the Attention/active-Tab refinement contract disagrees with the older Attention subsection in UI Design System v1.3, the refinement contract is the current accepted behavior for that bounded surface.

The supported runtime and release architecture is Apple Silicon arm64 only.

## Runtime diagnostics architecture

Runtime Diagnostics is an evidence plane, not a product-state owner. The canonical runtime, navigation, lifecycle, focus, Attention and persistence authorities remain in their owning domains.

Current boundaries:

- `SlotNavigationObserver` owns navigation/runtime observations and emits liveness, stall, termination, recovery-progress and healthy-closure evidence;
- `WebViewPool` / `SlotLifecycleCoordinator` own runtime/recovery/residency decisions and expose dispositions as evidence;
- `ChatGPTAttentionBridge` owns Attention runtime behavior and emits typed abnormal-path evidence without transferring Attention business-state ownership to Diagnostics;
- `PanelController` can contribute bounded presentation/focus facts without making Diagnostics a window authority;
- `RuntimeDiagnostics` persists/correlates privacy-filtered evidence but never defines root cause from event presence alone.

Public WebKit APIs do not provide reliable exact per-WebContent-process-to-Slot memory attribution. Diagnostics must preserve that limitation.

The historical WebContent stall/termination root cause remains `UNKNOWN`. Reload/reset/restart/hibernate recovery proves only a recovery boundary unless causal evidence establishes more.

## Historical architecture references

### `FloatTabs_Technical_Architecture_v1.2.md`

Historical architecture baseline only. It contains deliberately preserved old assumptions, including the earlier Hot/Warm/Cold residency model, pre-custom-Profile website-data model and older UI routing. Do not use those statements as current Runtime/Profile/UI authority.

### `Stage_1_Interaction_Baseline.md`

Historical pointer only. The complete original pre-Slot baseline is retained at [`archive/Stage_1_Interaction_Baseline.md`](archive/Stage_1_Interaction_Baseline.md).

## Historical design / Stage references

- `../design/FloatTabs_UI_Design_System_v1.2.md` is superseded by v1.3 for current shell interaction/geometry.
- `../design/Stage_3_Rendering_Profile_V2.md` and `V3.md` are historical Stage records. Verify current rendering behavior in source/tests instead of trusting old `current`/`accepted` wording.
- old Stage 5 Residency/Resource Lifecycle documents under `../product/` are historical inputs only for the active Runtime Lifecycle / Memory program.

## Rule

When a versioned architecture/design/product document disagrees with current production code or a newer accepted contract, treat the older statement as historical unless explicitly restored by `CURRENT_TASK.md` or a current linked contract.

Never use a historical `FROZEN`, `LOCKED`, `accepted`, `canonical`, or `CONSTRUCTION_GATE_READY` label as present-day execution authority.
