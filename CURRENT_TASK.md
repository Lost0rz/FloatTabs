# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Title:** Runtime Lifecycle / Memory redesign — Phase 6 perceived-fast restore  
**Status:** `ACTIVE / WP0 GATE0 REAL-MAC EVIDENCE`  
**Mode:** `EXECUTION STARTED / PRODUCT MUTATION HELD PENDING GATE0`  
**Task class:** `WEB RUNTIME / RESTORE RESPONSIVENESS`  
**JSC root cause:** `UNKNOWN`

## Authorization state

Phase 6 audit/design is complete and the implementation contract is frozen.

Durable audit/rationale record:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Audit_V1.md`

Frozen implementation contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Implementation_Contract_V1.md`

The user explicitly instructed FloatTabs to start remote Phase 6 construction on `2026-11-01`. That instruction releases the prior future-session execution hold. This remains the same task and same frozen contract; no successor task or redesign is required.

The first executable work package is still mandatory WP0 / Gate 0. Until Gate 0 proves Outcome A or Outcome B, product source/test mutation is not authorized.

## Frozen objective

Make a reclaimed persistent Slot feel immediately responsive without retaining extra heavyweight `WKWebView` runtimes:

```text
reclaimed Slot selected/summoned
→ native FloatTabs shell + lightweight restoring state immediately
→ return to AppKit run loop
→ revalidate current materialization request
→ existing WebViewPool creates/restores fresh Runtime
→ attach Runtime under restoring state
→ evidence-backed current-Runtime readiness
→ remove restoring state
→ existing focus/input ownership resumes
```

Resident Slot switching keeps the current direct fast path.

## Frozen ownership

- `PanelController` — Phase 6 presentation/materialization orchestration and stale request generation after Gate 0 passes;
- `WebPanelContainerView` — native restoring presentation only;
- `WebViewPool` — existing Runtime creation/restore mechanism;
- `SlotLifecycleCoordinator` — sole lifecycle/budget executor;
- `SlotNavigationObserver` / existing Web Runtime seams — navigation/readiness evidence only if Gate 0 requires the narrow existing owner;
- `WebFocusRouter` / existing Panel focus path — focus ownership unchanged;
- `WebAttentionCoordinator` — Attention unchanged;
- `RuntimeDiagnostics` — evidence only.

No second Runtime lifecycle or presentation truth owner is authorized.

## WP0 / Gate 0 — current active gate

On a Real Mac, use an existing Slot that has actually been hibernated and record only content-free public facts:

```text
selection / summon request
→ shell ordering boundary
→ fresh WKWebView allocation
→ interactionState assignment OR URL fallback classification
→ navigation provisional / commit / finish callbacks, if any
→ isLoading transitions, if observable
→ bounded current-Runtime renderer/page readiness
→ focus success/failure boundary
```

Do not record page text, screenshots, DOM content, cookies, session values or opaque interaction state.

### Existing execution path

Use current production/debug evidence plumbing first. The repository already provides:

- the Debug loopback benchmark control channel for existing Slot `configure`, `activate`, `show` and `hide` operations;
- `tools/benchmark/floattabs_lifecycle_benchmark.py`, which can drive Cold inactive Slots beyond the product grace window until they are actually hibernated/reclaimed and then re-activate them;
- Runtime diagnostics for `web_runtime.hibernate.completed`, `web_runtime.restore.begin`, `web_runtime.restore.completed`, fresh Runtime identity and `navigation.provisional_started` / `navigation.commit` / `navigation.finished` callbacks;
- bounded renderer/liveness probes that are evidence-only and must remain current-Runtime guarded.

Do not add new product Runtime instrumentation merely to make Gate 0 easier unless the existing public evidence is genuinely insufficient; that insufficiency is a STOP/reconciliation condition under this frozen task.

### Gate 0 allowed outcomes

**Outcome A — navigation-backed readiness**

A compatible `interactionState` restore exposes usable current-Runtime navigation/loading callbacks. Reuse only the exact-current-Runtime validated callback path as the trigger for the final bounded readiness check.

**Outcome B — non-navigation readiness**

A compatible `interactionState` restore does not reliably expose the same navigation sequence, but readiness can be established through a bounded public current-Runtime renderer/page observation without ownership drift or unbounded polling.

**STOP outcome**

Stop before product mutation if no bounded public readiness fact exists or if readiness would require private WebKit API, arbitrary fixed delays, unbounded polling, reload/double-navigation, Browser Profile/session mutation, screenshot persistence, extra resident WebViews, or materially different ownership.

The restoring presentation may be removed only after the current materialization generation, current Slot and exact current Runtime all still match and the Gate 0-approved public readiness fact succeeds.

`web_runtime.restore.completed` alone is not readiness truth.

## Authorized implementation scope after Gate 0 PASS

Expected production files:

- `FloatTabs/Panel/PanelController.swift`
- `FloatTabs/Web/WebViewContainer.swift`
- `FloatTabs/Web/WebViewPool.swift` only for a narrow read-only query/result if needed; no semantic restore rewrite
- `FloatTabs/Web/SlotNavigationObserver.swift` only if Gate 0 Outcome A proves a narrow existing-owner readiness seam is required

Expected tests:

- `FloatTabsTests/ExternalShellTests.swift`
- `FloatTabsTests/WebViewPoolTests.swift`
- existing focus-related tests only if deferred materialization changes focus timing

Any additional production file with material semantic responsibility requires STOP/reconciliation.

## Frozen implementation requirements

1. Resident Slot fast path remains direct.
2. Reclaimed Slot receives native restoring feedback before fresh Runtime materialization starts.
3. Early shell presentation returns control to AppKit before WebKit materialization.
4. One private materialization generation/request identity prevents stale attach/focus/activation/completion.
5. Selection change, dismissal, termination/reset and incompatible fullscreen/source lock invalidate pending work.
6. Revalidate request before materialization, before attachment, and before restoring-state dismissal.
7. `WebViewPool` remains the only Runtime creation/interaction-state restore owner.
8. Browser Profile/session identity remains unchanged.
9. Compatible interaction-state restore still avoids duplicate ordinary URL load.
10. Phase 4 Runtime budget/ranking/protection semantics remain unchanged.
11. No page screenshot or opaque interaction state is persisted/logged.
12. No arbitrary fixed timer becomes readiness truth.
13. Existing focus/fullscreen ownership remains canonical.

## Work packages

### WP0 — Gate 0 evidence — ACTIVE

Real-Mac readiness classification. Evidence/control only; no product source mutation.

### WP1 — native restoring presentation

Add the bounded native restoring surface to `WebPanelContainerView` with focused deterministic tests.

Dependency: WP0 PASS.

### WP2 — two-stage orchestration

Update `PanelController` so the native shell/restoring state is presented before reclaimed Runtime materialization and stale request generations are rejected.

Dependency: WP0 PASS + WP1.

### WP3 — readiness completion

Wire the Gate 0 Outcome A/B fact into current-Runtime restore completion using the smallest existing owner/seam.

Dependency: WP0 classification + WP1/WP2.

### WP4 — verification and merge readiness

Run focused tests, full XCTest, Debug/Release arm64, required literal-head PR CI and bounded Real-Mac restore smoke; then independent exact-diff audit.

This work-package structure is not a mandated Sub Agent topology.

## Verification gates

1. **Gate 0 Real-Mac evidence:** Outcome A or B; otherwise STOP.
2. **Focused correctness:** resident fast path, restoring-before-materialization ordering, stale request rejection, dismiss/switch/fullscreen boundaries, current-request-only completion, unchanged restore/session invariants.
3. **Full XCTest:** no Phase 6 regressions.
4. **Debug + Release + native arm64:** PASS.
5. **Required PR CI:** literal head `Build & Test (Apple Silicon arm64)` PASS on the established self-hosted runner.
6. **Bounded Real-Mac smoke:** resident switch, compatible reclaimed restore, safe fallback if reproducible, rapid switch-away, dismiss during pending restore.
7. **Independent exact-diff audit:** ownership/scope/data-safety/lifecycle verification before merge.
8. **Program-final human acceptance:** one user-owned integrated UI/runtime acceptance pass after Phase 6 implementation and final independent audit; machine checks do not replace it.

No absolute latency target is frozen in V1; Phase 6 proves immediate native response ordering and correctness first.

## Acceptance criteria

Merge readiness requires all of the following:

- native shell/restoring state becomes visible before fresh Runtime materialization for a reclaimed visible Slot;
- resident Slot path remains direct;
- no extra persistent WebView residency;
- stale materialization work cannot affect a newer selection/presentation;
- interaction-state restore/session safety remains intact;
- readiness is based on Gate 0-proven public bounded evidence;
- Phase 4 budget semantics remain unchanged;
- no screenshot/page-content/opaque-state persistence/logging;
- focused/full tests and builds pass;
- required literal-head CI passes;
- bounded Real-Mac restore smoke passes.

Program closeout additionally requires the user-owned integrated human UI/runtime acceptance pass.

## Explicit non-scope

- Settings-backed Runtime budget tuning;
- managed target/ranking changes;
- predictive prewarm;
- screenshot continuity cache;
- Browser Profile migration/reset;
- persistence schema change;
- Attention/Unread changes;
- background-generation cadence changes;
- fullscreen redesign;
- generic WebView threading redesign;
- private WebKit API;
- release/version bump.

## STOP conditions

STOP/reconcile if execution requires:

- a second Runtime lifecycle writer or second presentation truth owner;
- Browser Profile/session/persistent-data mutation;
- private WebKit API;
- hidden persistent WebViews as continuity objects;
- larger Runtime budget merely to mask restore cost;
- screenshot persistence;
- arbitrary reload/double-navigation/fixed-delay workaround;
- unbounded readiness polling;
- Attention semantics change;
- unresolved fullscreen source ownership outside the current session-lock boundary;
- material production scope outside the frozen paths;
- release/version work;
- product source mutation before Gate 0 Outcome A/B.

## Current execution state

```text
PHASE_6_AUDIT=COMPLETE
PHASE_6_CONTRACT=ACCEPTED / FROZEN
SELECTED_OPTION=TWO_STAGE_NATIVE_RESTORE_SHELL
READINESS_POLICY=GATE0_EVIDENCE_BOUND
EXECUTION_START_RELEASED=YES / 2026-11-01
WP0_GATE0=ACTIVE / REAL_MAC_EVIDENCE_PENDING
PRODUCT_IMPLEMENTATION=NOT_STARTED
PRODUCT_MUTATION=HELD_PENDING_GATE0
NEXT_USER_START_REQUIRED=NO
TASK_RECONCILIATION_REQUIRED=NO
PROGRAM_HUMAN_ACCEPTANCE=PENDING
```

Next action: execute WP0 / Gate 0 on the Real Mac. Continue directly into WP1–WP4 only after Outcome A or Outcome B is proven and no STOP condition fires.
