# FloatTabs — Architecture Document Status

Read [`../README.md`](../README.md) first. It is the repository-wide documentation authority/status index.

## Current Runtime Lifecycle / Memory authority

For `FT-RUNTIME-LIFECYCLE-MEMORY-001`:

- [`FloatTabs_Runtime_Lifecycle_Memory_Contract_V3.md`](FloatTabs_Runtime_Lifecycle_Memory_Contract_V3.md) — **ACCEPTED / FROZEN** program contract;
- [`FloatTabs_Runtime_Lifecycle_Phase4_Automatic_Runtime_Budget_Policy_Plan_V1.md`](FloatTabs_Runtime_Lifecycle_Phase4_Automatic_Runtime_Budget_Policy_Plan_V1.md) — **ACTIVE / ACCEPTED / FROZEN** Phase 4 plan;
- `CURRENT_STATUS.md` — current state/evidence;
- `CURRENT_TASK.md` — only active execution authorization;
- [`DOMAIN_MAP.md`](DOMAIN_MAP.md) — navigation only;
- production source/tests/fresh evidence.

Program cadence:

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
```

## Delivered lifecycle foundations

### Phase 1 — Safe Hibernate + Restore

Complete. Persistent Slot/Profile/session lifetime is separated from disposable `WKWebView` Runtime lifetime. Eligible hibernate retains only bounded memory-local restore state.

### Phase 2 — Ready / Unread Decoupling

Complete, merged in PR #176 / `3b8270de6917b0342143a36d2457686bb59dcc25`.

```text
Generating -> Runtime-protected
Ready      -> transient, not Runtime-protected
Durable unread -> survives Runtime reclamation
```

### Phase 3 — Native ChatGPT Completion Notification

Complete, merged in PR #179 / `e182dd51a1bfd21a614e09f33643bf4acea551dc`.

```text
hidden valid completion
→ durable unread .marked
→ native macOS notification
→ persistent Slot UUID route
→ exact Slot presentation
→ existing Runtime restore if absent
→ existing acknowledgement semantics
```

The delivered Phase 3 V2 plan remains implementation evidence, not active mutation authority.

## Active Phase 4 — Automatic Runtime Budget / Policy

Phase 4 introduces a central pure decision layer without moving Runtime ownership:

```text
WebViewPool live Runtime cache
→ read-only resident/protection/recency facts
→ RuntimeBudgetPolicy pure decision
→ SlotLifecycleCoordinator sole executor
→ existing hibernate boundary
```

### Frozen product semantics

- **Hot** remains an explicit user pin after activation and is not automatically budget-evicted.
- **Warm / Cold** are automatic-budget managed; their existing timers remain maximum normal retention boundaries.
- Over-budget Warm/Cold may hibernate earlier than their timer.
- Cold ranks before Warm; within a class, least-recently-used by persisted `lastUsedAt` ranks first; UUID is deterministic tie-break.
- Active/presented, fullscreen, supplemental-visible, media-protected and Generating Runtime are hard protected.
- Ready, durable unread and native-notification presence do not protect Runtime.
- Critical memory pressure uses the same policy with managed target `0`; warning does not invent a tighter target.
- Hot/hard protection may cause truthful oversubscription above the managed budget.
- `SlotLifecycleCoordinator` remains the only writer that performs lifecycle release/hibernate.
- no private WebKit API or exact per-Slot WebContent memory attribution is introduced.

### Phase 4 machine decision evidence

The normal managed budget is not pre-guessed. It is selected from fresh Real-Mac evidence:

```text
raw loaded-Warm curve: 1 / 2 / 4 / 8
→ repeated 8-resident no-op drift
→ candidates 4 → 3 → 2
→ >=3 repeated 8-resident runs per candidate
→ choose largest candidate with median reclaim > 2× median absolute control drift
→ >=10 reclaimed-Slot restore/materialization cycles, report median/p95
```

The restore metric is host-side Runtime materialization through the product path, not click-to-interactive/page-ready. Phase 6 owns perceived-fast restore.

The benchmark must use safe existing configured Slots, restore temporary policy/media/visibility/active-Slot changes and never create/delete/reset user data merely to satisfy the fixture.

See the Phase 4 V1 plan for exact scope, candidate rules, tests and STOP conditions.

## Runtime diagnostics architecture

Diagnostics remains evidence-only.

Current ownership:

- `WebViewPool` — Runtime creation/hibernate/restore mechanism;
- `SlotLifecycleCoordinator` — lifecycle execution and Phase 4 budget execution boundary;
- `RuntimeBudgetPolicy` — Phase 4 pure decision only, no WebKit/persistence side effects;
- `ChatGPTAttentionBridge` / `WebAttentionCoordinator` — Attention sensing/transient state;
- `ChatGPTUnreadResponseCoordinator` / `UnreadResponseStore` — durable unread truth;
- `ChatGPTCompletionNotificationCoordinator` — Phase 3 notification projection/routing;
- `PanelController` — presentation and bounded cross-domain composition;
- `RuntimeDiagnostics` — privacy-filtered evidence only.

Public WebKit APIs do not provide reliable exact per-WebContent-process-to-Slot memory attribution. Aggregate responsible-process evidence must remain labelled accordingly.

Historical JSC/WebContent stall root cause remains `UNKNOWN`; recovery boundaries are not causal proof.

## Adjacent current design

For unaffected shell/rail behavior use:

- [`../design/FloatTabs_UI_Design_System_v1.3.md`](../design/FloatTabs_UI_Design_System_v1.3.md);
- [`../design/FloatTabs_Attention_Active_Tab_Visual_Refinement_V1.md`](../design/FloatTabs_Attention_Active_Tab_Visual_Refinement_V1.md);
- current production source/tests.

Supported release architecture remains Apple Silicon arm64.

## Delivered / superseded lifecycle documents

- [`FloatTabs_Runtime_Lifecycle_Phase3_Native_Completion_Notification_Plan_V2.md`](FloatTabs_Runtime_Lifecycle_Phase3_Native_Completion_Notification_Plan_V2.md) — delivered Phase 3 evidence.
- `FloatTabs_Runtime_Lifecycle_Phase3_Native_Completion_Notification_Plan_V1.md` — superseded Phase 3 freeze evidence.
- [`FloatTabs_Runtime_Lifecycle_Phase2_Ready_Unread_Decoupling_Plan_V2.md`](FloatTabs_Runtime_Lifecycle_Phase2_Ready_Unread_Decoupling_Plan_V2.md) — delivered Phase 2 evidence.
- [`FT_RUNTIME_LIFECYCLE_PHASE2_SCOPE_RECONCILIATION_001.md`](FT_RUNTIME_LIFECYCLE_PHASE2_SCOPE_RECONCILIATION_001.md) — delivered Phase 2 corrective evidence.
- [`FloatTabs_Runtime_Lifecycle_Phase1_Safe_Hibernate_Restore_Plan_V2.md`](FloatTabs_Runtime_Lifecycle_Phase1_Safe_Hibernate_Restore_Plan_V2.md) — delivered Phase 1 evidence.
- `FloatTabs_Runtime_Lifecycle_Memory_Contract_V2.md` / V1 — historical program contracts superseded by V3.

## Rule

Older architecture/product/Stage documents are historical unless current Authority explicitly restores them. When they conflict with current V3/Phase 4/source/tests, preserve them as evidence but follow the current Authority.
