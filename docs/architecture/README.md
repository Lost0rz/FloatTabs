# FloatTabs — Architecture Document Status

Read [`../README.md`](../README.md) first. It is the repository-wide documentation authority/status index.

Use this file to distinguish current architecture navigation/contracts from historical architecture and Stage documents.

## Current navigation

For source/Authority routing, use:

- [`DOMAIN_MAP.md`](DOMAIN_MAP.md) — derived Domain/source/test navigation map;
- production code and regression tests on the current Delivery / Semantic HEAD.

`DOMAIN_MAP.md` is navigation only. It does not override product/design contracts or `CURRENT_TASK.md`.

## Current runtime lifecycle / memory contract

For the accepted Runtime Lifecycle / Memory redesign, use:

- [`FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md`](FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md) — **ACCEPTED / FROZEN** architecture contract for program `FT-RUNTIME-LIFECYCLE-MEMORY-001`;
- `CURRENT_STATUS.md` — current phase/progress and verified repository state;
- `CURRENT_TASK.md` — the only active execution authorization;
- production source and regression tests on the current Delivery / Semantic HEAD.

The contract freezes ownership, phase order, data-safety invariants, Attention/unread handoff direction, native completion-notification direction, automatic Runtime Budget direction, benchmark/STOP gates, and prohibited shortcuts. It does **not** claim that unimplemented phases are current production behavior.

Each implementation phase must first pass its focused pre-implementation audit and repository task reconciliation before product mutation. Execution cards are bounded handoffs only; they do not replace the repository contract.

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

The current incident-oriented diagnostics path can correlate a bounded incident identity across emitters in Web, Panel and Attention while `FloatTabs/Diagnostics/` owns the shared diagnostic event vocabulary, privacy filtering, persistence/export and bounded snapshot representation.

Important boundaries:

- `SlotNavigationObserver` owns navigation/runtime observations and emits liveness, stall, termination, recovery-progress and healthy-closure evidence;
- `WebViewPool` / `SlotLifecycleCoordinator` own runtime/recovery/residency decisions and expose their dispositions as evidence;
- `ChatGPTAttentionBridge` owns Attention runtime behavior and emits typed abnormal-path evidence without transferring Attention business-state ownership to Diagnostics;
- `PanelController` can contribute bounded presentation/focus snapshot facts without making Diagnostics a window authority;
- `RuntimeDiagnostics` and related Diagnostics types correlate and persist privacy-filtered evidence but never define root cause from event presence alone.

Public WebKit APIs do not provide reliable per-WebContent-process memory attribution. Current diagnostics therefore record that limitation explicitly rather than assigning host RSS or memory-pressure evidence to a WebContent child process without proof.

The historical WebContent stall/termination root cause remains `UNKNOWN`. Recovery by reload/reset/restart is evidence about the recovery boundary, not causal proof.

## Historical architecture references

### `FloatTabs_Technical_Architecture_v1.2.md`

**Historical architecture baseline only.** It contains several deliberately preserved old assumptions, including the earlier Hot/Warm/Cold residency model, pre-custom-Profile website-data model, and older UI routing. Those statements must not be used as current Runtime/Profile/UI authority.

Use it only for historical rationale that remains consistent with current source/contracts. The original body is preserved through its historical wrapper/archive path.

### `Stage_1_Interaction_Baseline.md`

Historical pointer only. The complete original pre-Slot baseline is retained at [`archive/Stage_1_Interaction_Baseline.md`](archive/Stage_1_Interaction_Baseline.md).

## Historical design / Stage references

- `../design/FloatTabs_UI_Design_System_v1.2.md` is explicitly superseded by v1.3 for current shell interaction/geometry.
- `../design/Stage_3_Rendering_Profile_V2.md` and `V3.md` are historical Stage records. Verify current rendering behavior in source/tests instead of trusting their old `current`/`accepted` wording.
- old Stage 5 Residency/Resource Lifecycle documents under `../product/` are historical inputs only for the active Runtime Lifecycle / Memory program.

## Rule

When a versioned architecture/design/product document disagrees with current production code or a newer accepted contract, treat the older statement as historical unless explicitly restored by `CURRENT_TASK.md` or a current linked contract.

Never use a historical `FROZEN`, `LOCKED`, `accepted`, `canonical`, or `CONSTRUCTION_GATE_READY` label as present-day execution authority.