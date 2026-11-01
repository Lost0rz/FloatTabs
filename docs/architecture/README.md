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

- [`FloatTabs_Runtime_Lifecycle_Memory_Contract_V3.md`](FloatTabs_Runtime_Lifecycle_Memory_Contract_V3.md) — **ACCEPTED / FROZEN** current program-level contract and unified final acceptance cadence;
- [`FloatTabs_Runtime_Lifecycle_Phase3_Native_Completion_Notification_Plan_V1.md`](FloatTabs_Runtime_Lifecycle_Phase3_Native_Completion_Notification_Plan_V1.md) — **ACTIVE / ACCEPTED / FROZEN** current Phase 3 implementation plan;
- `CURRENT_STATUS.md` — current program/phase/evidence state;
- `CURRENT_TASK.md` — the only active execution authorization;
- production code/tests/fresh evidence.

Program Contract V3 preserves the target architecture — persistent Slot/Profile/product state with disposable `WKWebView` Runtime cache — and keeps intermediate phases on a machine-first cadence:

```text
phase-focused audit / freeze
→ implementation
→ machine verification + required CI
→ merge
→ next dependent architecture phase
...
Phases 1–6 complete
→ unified independent program audit
→ one user-owned full human acceptance pass
→ final closeout / release decision
```

## Delivered lifecycle foundations

### Phase 1 — Safe Hibernate + Restore

Complete. Runtime lifetime is separated from persistent Slot/Profile/session lifetime; eligible Runtime reclaim may preserve bounded memory-local restore state.

### Phase 2 — Ready / Unread Decoupling

Complete and merged in PR #176 / merge commit `3b8270de6917b0342143a36d2457686bb59dcc25`.

Current ownership split:

```text
Runtime Attention
  generating -> protects Runtime
  ready      -> transient only; does not protect Runtime

Durable Unread
  ChatGPTUnreadResponseCoordinator + UnreadResponseStore
  -> survives Runtime reclamation
  -> owns persistent rail/menu unread presentation
```

The delivered Phase 2 V2 plan and scope reconciliation remain implementation evidence, not active Phase 3 mutation authority.

## Active Phase 3 — Native ChatGPT Completion Notification

Phase 3 adds one native macOS notification projection for unseen ChatGPT completion without creating new Runtime or unread ownership.

Frozen flow:

```text
valid hidden completion
→ durable unread result .marked
→ generic native notification keyed only by persistent Slot UUID
→ Runtime may be reclaimed normally
→ notification default-action tap
→ exact Slot selection/presentation
→ existing Runtime restore/recreation if needed
→ existing presentation-aware unread acknowledgement
```

Phase 3 architecture boundaries:

- new notification delivery/response owner belongs to the App composition layer;
- native notification is a one-shot projection, never canonical unread state;
- `Slot.id` is the stable routing identity; notification state never retains `WKWebView`, Runtime generation, document token or Browser Profile identity;
- notification payload/body is privacy-bounded and contains no prompt, assistant response, URL or session data;
- existing attention sound remains independent and keeps its current generic valid-completion semantics;
- notification permission denial must not affect unread, sound, generation, reclaim/restore or user data;
- exact stale/deleted Slot activation fails safely with no fallback to another Slot;
- Phase 3 does not modify detector/response extraction, durable unread persistence, Runtime lifecycle policy or Phase 4+ behavior.

See the Phase 3 V1 plan for exact source scope, test matrix, STOP conditions and machine gate.

## Current behavior / adjacent design

For shell interaction, rail geometry, movement, resize and fullscreen coordination, use:

- [`../design/FloatTabs_UI_Design_System_v1.3.md`](../design/FloatTabs_UI_Design_System_v1.3.md) for unaffected shell/rail behavior;
- [`../design/FloatTabs_Attention_Active_Tab_Visual_Refinement_V1.md`](../design/FloatTabs_Attention_Active_Tab_Visual_Refinement_V1.md) for the accepted active-Tab and unread-Attention refinement merged in PR #146;
- production code and regression tests on `main`.

Phase 3 adds native notification routing only. It does not redesign rail/status attention visuals.

The supported runtime and release architecture is Apple Silicon arm64 only.

## Runtime diagnostics architecture

Runtime Diagnostics is an evidence plane, not a product-state owner. Canonical runtime, navigation, lifecycle, focus, Attention, unread, notification projection and persistence authorities remain in their owning domains.

Current boundaries:

- `SlotNavigationObserver` owns navigation/runtime observations;
- `WebViewPool` / `SlotLifecycleCoordinator` own Runtime/recovery/residency execution;
- `ChatGPTAttentionBridge` owns Attention runtime sensing;
- `WebAttentionCoordinator` owns transient Attention state;
- `ChatGPTUnreadResponseCoordinator` / `UnreadResponseStore` own durable unread semantics;
- `PanelController` composes completion handoff, presentation and exact Slot activation without becoming persistence owner;
- Phase 3 notification coordinator owns only `UNUserNotificationCenter` projection/response plumbing;
- `RuntimeDiagnostics` records evidence only and never becomes product truth.

Public WebKit APIs do not provide reliable exact per-WebContent-process-to-Slot memory attribution. Diagnostics must preserve that limitation.

The historical WebContent stall/termination root cause remains `UNKNOWN`. Reload/reset/restart/hibernate recovery proves only a recovery boundary unless causal evidence establishes more.

## Completed / superseded Runtime Lifecycle documents

- [`FloatTabs_Runtime_Lifecycle_Phase2_Ready_Unread_Decoupling_Plan_V2.md`](FloatTabs_Runtime_Lifecycle_Phase2_Ready_Unread_Decoupling_Plan_V2.md) — delivered Phase 2 plan evidence; no longer active execution plan.
- [`FT_RUNTIME_LIFECYCLE_PHASE2_SCOPE_RECONCILIATION_001.md`](FT_RUNTIME_LIFECYCLE_PHASE2_SCOPE_RECONCILIATION_001.md) — delivered Phase 2 test-scope evidence.
- [`FloatTabs_Runtime_Lifecycle_Memory_Contract_V2.md`](FloatTabs_Runtime_Lifecycle_Memory_Contract_V2.md) — historical program contract superseded by V3.
- [`FloatTabs_Runtime_Lifecycle_Phase2_Ready_Unread_Decoupling_Plan_V1.md`](FloatTabs_Runtime_Lifecycle_Phase2_Ready_Unread_Decoupling_Plan_V1.md) — historical Phase 2 plan evidence.
- [`FloatTabs_Runtime_Lifecycle_Phase1_Safe_Hibernate_Restore_Plan_V2.md`](FloatTabs_Runtime_Lifecycle_Phase1_Safe_Hibernate_Restore_Plan_V2.md) — delivered Phase 1 plan evidence.
- [`FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md`](FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md) — historical program-contract evidence.
- [`FloatTabs_Runtime_Lifecycle_Phase1_Safe_Hibernate_Restore_Plan_V1.md`](FloatTabs_Runtime_Lifecycle_Phase1_Safe_Hibernate_Restore_Plan_V1.md) — historical Phase 1 audit/plan evidence.

Their facts/rationale remain useful where they do not conflict with current Authority.

## Historical architecture references

### `FloatTabs_Technical_Architecture_v1.2.md`

Historical architecture baseline only. It contains deliberately preserved old assumptions. Verify present behavior in current source/tests.

### `Stage_1_Interaction_Baseline.md`

Historical pointer only. The complete original pre-Slot baseline is retained at [`archive/Stage_1_Interaction_Baseline.md`](archive/Stage_1_Interaction_Baseline.md).

## Rule

When a versioned architecture/design/product document disagrees with current production code or a newer accepted contract, treat the older statement as historical unless explicitly restored by `CURRENT_TASK.md` or a current linked contract.

Never use a historical `FROZEN`, `LOCKED`, `accepted`, `canonical`, or `CONSTRUCTION_GATE_READY` label as present-day execution authority.
