# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Title:** Runtime Lifecycle / Memory redesign — Phase 6 perceived-fast restore  
**Status:** `ACTIVE / WP1 NATIVE RESTORING PRESENTATION`  
**Mode:** `EXECUTION ACTIVE / PRODUCT MUTATION RELEASED BY GATE0 OUTCOME_A`  
**Task class:** `WEB RUNTIME / RESTORE RESPONSIVENESS`  
**JSC root cause:** `UNKNOWN`

## Authorization state

Phase 6 audit/design is complete and the implementation contract is frozen.

Durable audit/rationale record:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Audit_V1.md`

Frozen implementation contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Implementation_Contract_V1.md`

The user explicitly instructed FloatTabs to start remote Phase 6 construction on `2026-11-01`. The mandatory WP0 / Gate 0 Real-Mac verification has now completed with **OUTCOME_A**. Product source/test mutation inside the frozen Phase 6 implementation boundary is therefore authorized; no successor task or redesign is required.

## Gate 0 accepted evidence

The Real-Mac verification used an actually hibernated existing Slot and returned the repository to its pre-run state with no source mutation.

Accepted facts:

```text
hibernate completed with interaction_state_present=true
→ target Runtime reclaimed from resident set
→ reactivation used restore_source=interaction_state
→ fresh Runtime identity created
→ exact fresh Runtime emitted navigation.provisional_started
→ navigation.commit
→ navigation.finished
→ stale=false for the observed callback sequence
→ bounded exact-current-Runtime liveness also succeeded
→ focus recognition succeeded
```

The fresh Runtime identity differed from the pre-hibernate Runtime identity. No duplicate ordinary URL load was observed. Browser Profile/session/persistent user data were not reset or rewritten.

Classification: **Outcome A — navigation-backed readiness**.

The existing bounded cross-world observation also succeeded and remains corroborating evidence, not a replacement truth owner.

`web_runtime.restore.completed` alone remains insufficient readiness truth.

## Frozen objective

Make a reclaimed persistent Slot feel immediately responsive without retaining extra heavyweight `WKWebView` runtimes:

```text
reclaimed Slot selected/summoned
→ native FloatTabs shell + lightweight restoring state immediately
→ return to AppKit run loop
→ revalidate current materialization request
→ existing WebViewPool creates/restores fresh Runtime
→ attach Runtime under restoring state
→ Outcome-A exact-current-Runtime navigation readiness
→ remove restoring state
→ existing focus/input ownership resumes
```

Resident Slot switching keeps the current direct fast path.

## Frozen ownership

- `PanelController` — Phase 6 presentation/materialization orchestration and stale request generation;
- `WebPanelContainerView` — native restoring presentation only;
- `WebViewPool` — existing Runtime creation/restore mechanism;
- `SlotLifecycleCoordinator` — sole lifecycle/budget executor;
- `SlotNavigationObserver` / existing Web Runtime seams — narrow navigation/readiness evidence only;
- `WebFocusRouter` / existing Panel focus path — focus ownership unchanged;
- `WebAttentionCoordinator` — Attention unchanged;
- `RuntimeDiagnostics` — evidence only.

No second Runtime lifecycle or presentation truth owner is authorized.

## Authorized implementation scope

Expected production files:

- `FloatTabs/Panel/PanelController.swift`
- `FloatTabs/Web/WebViewContainer.swift`
- `FloatTabs/Web/WebViewPool.swift` only for a narrow read-only/query/callback seam if needed; no semantic restore rewrite
- `FloatTabs/Web/SlotNavigationObserver.swift` only for the narrow Outcome-A readiness seam if required

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
14. Outcome-A readiness completion must correlate the current materialization generation, current Slot and exact current Runtime before removing restoring UI.

## Work packages

### WP0 — Gate 0 evidence — COMPLETE / OUTCOME_A

Real-Mac evidence established navigation-backed readiness on an exact fresh current Runtime. No product-source mutation occurred during verification.

### WP1 — native restoring presentation — ACTIVE

Add the bounded native restoring surface to `WebPanelContainerView` with focused deterministic tests. The surface must be lightweight, contain no page/user data, and remain visually above a newly attached restoring WebView until the current request reaches the approved readiness boundary.

### WP2 — two-stage orchestration

Update `PanelController` so a visible reclaimed Slot first presents native shell/restoring state, returns to the AppKit run loop, then materializes through the existing `WebViewPool`. Add a private materialization generation/request and reject stale selection/dismiss/fullscreen/reset work.

Dependency: WP1.

### WP3 — readiness completion

Wire Outcome A through the smallest existing navigation owner/seam. A navigation callback may complete restoring presentation only when the materialization generation, active Slot and exact pooled Runtime all still match. No timer, reload or duplicate navigation may become readiness truth.

Dependency: WP1/WP2.

### WP4 — verification and merge readiness

Run focused tests, full XCTest, Debug/Release arm64, required literal-head PR CI and bounded Real-Mac restore smoke; then independent exact-diff audit.

This work-package structure is not a mandated Sub Agent topology.

## Verification gates

1. **Gate 0 Real-Mac evidence:** PASS / Outcome A.
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
- restoring-state dismissal uses Outcome-A exact-current-Runtime navigation readiness;
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
- release/version work.

## Current execution state

```text
PHASE_6_AUDIT=COMPLETE
PHASE_6_CONTRACT=ACCEPTED / FROZEN
SELECTED_OPTION=TWO_STAGE_NATIVE_RESTORE_SHELL
READINESS_POLICY=OUTCOME_A_NAVIGATION_BACKED_EXACT_CURRENT_RUNTIME
EXECUTION_START_RELEASED=YES / 2026-11-01
WP0_GATE0=COMPLETE / OUTCOME_A
WP1_NATIVE_RESTORING_PRESENTATION=ACTIVE
WP2_TWO_STAGE_ORCHESTRATION=PENDING
WP3_READINESS_COMPLETION=PENDING
WP4_VERIFICATION=PENDING
PRODUCT_IMPLEMENTATION=STARTED
PRODUCT_MUTATION=AUTHORIZED_WITHIN_FROZEN_SCOPE
NEXT_USER_START_REQUIRED=NO
TASK_RECONCILIATION_REQUIRED=NO
PROGRAM_HUMAN_ACCEPTANCE=PENDING
```

Next action: implement WP1, then continue directly through WP2/WP3 on the same branch and PR before WP4 verification.
