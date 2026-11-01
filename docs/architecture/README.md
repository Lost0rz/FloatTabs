# FloatTabs — Architecture Document Status

Read [`../README.md`](../README.md) first. It is the repository-wide documentation authority/status index.

## Current Runtime Lifecycle / Memory authority

For `FT-RUNTIME-LIFECYCLE-MEMORY-001`:

- [`FloatTabs_Runtime_Lifecycle_Memory_Contract_V4.md`](FloatTabs_Runtime_Lifecycle_Memory_Contract_V4.md) — **CURRENT / ACCEPTED / FROZEN** program contract;
- [`FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Implementation_Contract_V1.md`](FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Implementation_Contract_V1.md) — **CURRENT PHASE 6 / ACCEPTED / FROZEN / GATE 0 OUTCOME A / WP4 CORRECTIVE ACTIVE**;
- [`FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Audit_V1.md`](FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Audit_V1.md) — **AUDIT / RATIONALE EVIDENCE**; no longer the execution-scope authority;
- `CURRENT_STATUS.md` — verified current state/evidence;
- `CURRENT_TASK.md` — only active mutation authorization;
- [`DOMAIN_MAP.md`](DOMAIN_MAP.md) — navigation only;
- current production source/tests/fresh evidence.

Program cadence remains:

```text
focused phase audit / freeze
→ bounded implementation
→ machine verification + required CI
→ independent exact-diff audit
→ merge
...
Phases 1–6 complete
→ integrated independent program audit
→ one user-owned final human acceptance pass
```

## Delivered lifecycle foundations

### Phase 1 — Safe Hibernate + Restore

Complete / merged. Persistent Slot/Profile/session lifetime is separated from disposable `WKWebView` Runtime lifetime. One memory-local opaque `interactionState` snapshot may bridge normal hibernate to a compatible fresh Runtime; incompatible state falls back safely to URL loading.

### Phase 2 — Ready / Unread Decoupling

Complete / merged.

```text
Generating -> Runtime-protected
Ready      -> transient, not Runtime-protected
Durable unread -> survives Runtime reclamation
```

### Phase 3 — Native ChatGPT Completion Notification

Complete / merged. Hidden valid completion can persist unread truth, notify natively and route back to the exact persistent Slot independently of Runtime residency.

### Phase 4 — Reference-derived Automatic Runtime Management

Complete / merged in PR #181 / `c910441a954bddbaeca710395cd0d6ed89ec5e5c`.

Current production semantics:

- Hot is an explicit pin outside automatic eviction;
- Warm/Cold are managed automatically;
- Cold ranks before Warm, then older `lastUsedAt`, then UUID;
- active/presented/fullscreen/supplemental/media/Attention-generating Runtime is protected;
- normal/warning managed target defaults to 3;
- critical pressure targets 0 eligible inactive Warm/Cold Runtime;
- reclaim executes through `SlotLifecycleCoordinator` → existing `WebViewPool.hibernate`.

The value 3 is a reference-derived initial default, not measured optimum. The old strict Phase 4 benchmark-selection gate remains historical and deferred to future Settings-backed tuning.

### Phase 5 — Background Generation Thrift

Complete / merged in PR #183 / `745d401bf9f282d19bc756c81be3f46f17161e4b`.

Delivered fallback cadence:

```text
visible/unknown document                  -> 2s
hidden document, generation age < 30s     -> 2s
hidden document, generation age >= 30s    -> 5s
first false probe                          -> existing 250ms confirmation
```

The primary ChatGPT page detector remains event-driven. `document.visibilityState` is bridge-local scheduling metadata only; `PanelController` remains product/presentation visibility authority.

## Phase 6 — Perceived-fast Restore

**Audit:** complete.  
**Implementation contract:** accepted/frozen.  
**Gate 0:** complete / **OUTCOME_A — navigation-backed readiness**.  
**WP1–WP3:** implemented on PR #187.  
**WP4:** active / **EXACT-DIFF AUDIT CHANGES REQUIRED**.  
**Merge readiness:** blocked pending bounded corrective + fresh verification.

Frozen architecture remains:

```text
reclaimed Slot selected/summoned
→ native shell + lightweight restoring state immediately
→ return to AppKit run loop
→ revalidate materialization request
→ existing WebViewPool materializes/restores fresh Runtime
→ attach fresh WebView under restoring state
→ exact-current-Runtime navigation-backed readiness
→ remove restoring state
→ existing focus/input ownership resumes
```

Resident Slot switching remains on the direct existing path.

### Gate 0 accepted evidence

A Real-Mac verification drove an existing Slot through real product hibernate/reclaim and then reactivated it through the existing compatible `interactionState` restore path.

The fresh restored Runtime emitted this exact non-stale navigation sequence:

```text
navigation.provisional_started
→ navigation.commit
→ navigation.finished
```

The callback Runtime identity matched the fresh `web_runtime.restore.completed` / `web_runtime.created` identity and differed from the pre-hibernate Runtime. The same Runtime also passed the existing bounded cross-world liveness observation. No duplicate ordinary URL load, private API, arbitrary fixed readiness delay, unbounded polling, screenshot persistence, Browser Profile/session reset, extra persistent WebView or ownership change was required.

Therefore the implementation uses **Outcome A**: exact-current-Runtime navigation-backed readiness. `web_runtime.restore.completed` remains state-handoff evidence only.

### WP1–WP3 implementation evidence

Implementation head `0ad45bff7869cdf66ac26994396ff013c89b0fbe` contains only the frozen production/test paths:

- `PanelController.swift` — deferred materialization + stale request generation;
- `WebViewContainer.swift` — lightweight native restoring presentation;
- `WebViewPool.swift` — narrow exact-current navigation completion projection;
- `SlotNavigationObserver.swift` — narrow finish/failure evidence seam;
- `ExternalShellTests.swift` / `WebViewPoolTests.swift` — regression coverage.

Local focused/full XCTest, Debug/Release native arm64, required macOS CI run 1302 and QA DMG run 627 passed on that implementation head.

### WP4 independent exact-diff audit findings

The independent review found four bounded implementation corrections; none requires architecture redesign:

1. **Focus/input ordering:** deferred attach currently can resume native/DOM focus while restoring UI is still present. The frozen order requires accepted readiness, then restoring removal, then canonical focus/input flow resumes.
2. **Attention physical visibility:** a WebView covered by the opaque restoring surface must not be treated as physically user-visible merely because the source window is key. Attention authority and policy remain unchanged; only the presentation fact is corrected.
3. **Restoring animation lifetime:** hiding the attached overlay must stop its native progress animation.
4. **HTTP fallback terminal classification:** a provisional failure that starts the existing safe HTTP-entry fallback is not terminal for the Phase 6 transaction. The fallback navigation's own finish/failure must decide completion.

Review record: PR #187 review `5728444391`.

### Current bounded corrective boundary

The corrective remains inside the same frozen production paths. It must not change:

- `WebViewPool` interaction-state restore semantics;
- Browser Profile/session/persistence;
- Phase 4 Runtime budget/ranking/protection;
- Attention/Unread authority or product policy;
- background cadence;
- fullscreen architecture;
- release/version;
- private WebKit API usage.

Fresh verification after the corrective must include focused/full XCTest, Debug/Release native arm64, fresh literal-head required CI, bounded Real-Mac restore smoke and fresh independent exact-diff audit.

### Rejected Phase 6 V1 alternatives

- screenshot cache as the default continuity mechanism;
- predictive prewarm or larger resident Runtime budget;
- Browser Profile / interaction-state restore rewrite without evidence;
- arbitrary timer/polling/reload tricks to manufacture readiness.

## Current ownership

- `WebViewPool` — live Runtime creation/hibernate/restore mechanism and bridge lifetime;
- `SlotLifecycleCoordinator` — sole Runtime lifecycle executor and automatic budget executor;
- private `RuntimeBudgetPolicy` inside `SlotLifecycleCoordinator.swift` — deterministic budget decision only;
- `WebAttentionCoordinator` — sole native Attention state authority;
- `ChatGPTAttentionBridge` — provider sensing and bounded liveness fallback;
- `PanelController` — presentation truth and Phase 6 materialization orchestration;
- `WebPanelContainerView` — visible Web surface/native restoring presentation, not lifecycle policy;
- `UnreadResponseStore` / unread coordinator — durable unread truth;
- native notification coordinator — notification projection/routing;
- `RuntimeDiagnostics` — evidence only.

Public WebKit APIs do not provide trustworthy exact per-Slot WebContent memory attribution. Historical JSC/WebContent stall root cause remains `UNKNOWN`.

## Historical / superseded lifecycle documents

The following remain useful evidence but are not current execution authority:

- `FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md`, V2, V3;
- `FloatTabs_Runtime_Lifecycle_Phase4_Automatic_Runtime_Budget_Policy_Plan_V1.md`;
- delivered Phase 1–5 plans and reconciliation records;
- the Phase 6 audit document for execution scope after the implementation contract freeze.

Do not rewrite historical results to mimic current state. When they conflict with V4/current Phase 6 implementation contract/current source/tests, follow current Authority.
