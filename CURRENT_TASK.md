# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Title:** Runtime Lifecycle / Memory redesign — Phase 6 perceived-fast restore  
**Status:** `ACTIVE / WP4 EXACT-DIFF CORRECTIVE`  
**Mode:** `EXECUTION ACTIVE / MERGE BLOCKED PENDING BOUNDED CORRECTIVE`  
**Task class:** `WEB RUNTIME / RESTORE RESPONSIVENESS`  
**JSC root cause:** `UNKNOWN`

## Authorization state

Phase 6 audit/design is complete and the implementation contract is frozen.

Durable audit/rationale record:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Audit_V1.md`

Frozen implementation contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Implementation_Contract_V1.md`

The user explicitly instructed FloatTabs to start remote Phase 6 construction on `2026-11-01`. WP0 / Gate 0 completed with **OUTCOME_A**. WP1–WP3 have now been implemented and pushed on PR #187. Machine verification is green, but WP4 independent exact-diff audit found bounded correctness issues that must be corrected before merge. This remains the same task and same frozen architecture; no successor task or redesign is authorized or required.

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
- `WebViewPool` — existing Runtime creation/restore mechanism plus narrow read-only readiness projection;
- `SlotLifecycleCoordinator` — sole lifecycle/budget executor;
- `SlotNavigationObserver` — narrow navigation/readiness/terminal evidence seam only;
- `WebFocusRouter` / existing Panel focus path — focus ownership unchanged;
- `WebAttentionCoordinator` — Attention authority unchanged;
- `RuntimeDiagnostics` — evidence only.

No second Runtime lifecycle, focus, Attention or presentation truth owner is authorized.

## Authorized implementation scope

Expected production files remain:

- `FloatTabs/Panel/PanelController.swift`
- `FloatTabs/Web/WebViewContainer.swift`
- `FloatTabs/Web/WebViewPool.swift`
- `FloatTabs/Web/SlotNavigationObserver.swift`

Expected tests remain:

- `FloatTabsTests/ExternalShellTests.swift`
- `FloatTabsTests/WebViewPoolTests.swift`
- existing focus-related tests only if the corrective needs deterministic focus timing coverage.

No production scope expansion is authorized.

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
15. Existing focus/input flow resumes only after accepted readiness and restoring-state removal.
16. Physical page visibility/Attention acknowledgement must not claim user visibility while the opaque restoring surface still covers the WebView.

## Work packages

### WP0 — Gate 0 evidence — COMPLETE / OUTCOME_A

Real-Mac evidence established navigation-backed readiness on an exact fresh current Runtime.

### WP1 — native restoring presentation — COMPLETE

Implemented in `WebPanelContainerView` with native presentation-only restoring UI and regression coverage.

### WP2 — two-stage orchestration — COMPLETE

Implemented deferred main-run-loop materialization plus generation-scoped stale rejection for selection/dismiss/fullscreen/termination boundaries.

### WP3 — readiness completion — COMPLETE / CORRECTIVE REQUIRED

Exact-current Runtime finish/failure projection is implemented through the existing navigation/pool ownership path. WP4 audit found that focus/input and physical Attention visibility are resumed too early around this completion boundary, and that provisional fallback terminal classification needs correction.

### WP4 — verification and merge readiness — ACTIVE / CHANGES REQUIRED

Observed machine evidence on implementation head `0ad45bff7869cdf66ac26994396ff013c89b0fbe`:

- focused Phase 6 tests: PASS;
- `ExternalShellTests`: PASS;
- `WebViewPoolTests`: PASS;
- full XCTest: PASS (~1379 / 0 failures);
- Debug build: PASS;
- Release build: PASS;
- native arm64: PASS;
- required literal-head CI `Build & Test (Apple Silicon arm64)`: PASS, run 1302;
- QA DMG: PASS, run 627.

Independent exact-diff audit: **CHANGES REQUIRED**. Review record: PR #187 review `5728444391`.

Bounded Real-Mac WP4 smoke remains pending until the corrective is pushed.

## WP4 bounded corrective contract

Correct only the following four findings. Do not broaden scope.

### C1 — restore focus/input only after Outcome-A readiness — BLOCKER

Current deferred attach can make the restoring WebView current for focus and can call native `orderFrontAndFocus` before `navigation.finished`; the existing commit path can also schedule DOM input focus while restoring is still active.

Required behavior:

```text
attach fresh Runtime under opaque restoring surface
→ keep Phase 6 focus/input flow gated
→ exact-current Runtime navigation.finished accepted
→ remove restoring surface
→ resume the existing canonical native/DOM focus flow exactly once
```

Do not create a new focus owner or polling loop. Existing presentation-focus ownership remains canonical.

### C2 — restoring overlay is not page-visible Attention — BLOCKER

An attached WebView underneath the opaque restoring surface must not be treated as actually user-visible merely because its source window is visible/key.

Keep `WebAttentionCoordinator` semantics and authority unchanged. Correct only the physical presentation fact/acknowledgement boundary so Attention acknowledgement cannot happen until the restoring surface is removed and the page is actually presented.

### C3 — stop hidden spinner animation — CORRECTIVE

`showRestoringState` / `hideRestoringState` must explicitly start/stop the native progress indicator. The hidden overlay may remain attached, but it must not continue animation indefinitely.

Add deterministic regression coverage.

### C4 — provisional HTTP fallback is not terminal — CORRECTIVE

For `didFailProvisionalNavigation`, evaluate the existing safe HTTP-entry fallback before projecting the Phase 6 terminal failure. If a fallback load is started, keep the pending materialization/restoring transaction alive. Let the fallback navigation's own exact-current finish or terminal failure decide completion.

Do not change the existing fallback eligibility semantics and do not add reload/double-navigation behavior.

## Verification gates after corrective

1. Focused tests covering C1–C4.
2. Existing Phase 6 focused suite remains PASS.
3. Full XCTest PASS.
4. Debug + Release + native arm64 PASS.
5. Fresh literal-head required CI PASS on the corrective head.
6. Bounded Real-Mac smoke: resident switch, compatible reclaimed restore, safe fallback if reproducible, rapid switch-away, dismiss during pending restore.
7. Fresh independent exact-diff audit PASS.
8. Only then may PR #187 become merge-ready.
9. Program-final user-owned human UI/runtime acceptance remains after integrated Phase 6 closeout; machine verification does not replace it.

## Acceptance criteria

Merge readiness requires all of the following:

- native shell/restoring state becomes visible before fresh Runtime materialization for a reclaimed visible Slot;
- resident Slot path remains direct;
- no extra persistent WebView residency;
- stale materialization work cannot affect a newer selection/presentation;
- interaction-state restore/session safety remains intact;
- restoring-state dismissal uses Outcome-A exact-current-Runtime navigation readiness;
- focus/input is not resumed before accepted readiness;
- opaque restoring presentation is not counted as user-visible page presentation;
- recoverable HTTP fallback remains within the same pending restore transaction;
- hidden restoring UI does not retain active animation work;
- Phase 4 budget semantics remain unchanged;
- no screenshot/page-content/opaque-state persistence/logging;
- focused/full tests and builds pass;
- fresh required literal-head CI passes;
- bounded Real-Mac restore smoke passes;
- fresh independent exact-diff audit passes.

## Explicit non-scope

- Settings-backed Runtime budget tuning;
- managed target/ranking changes;
- predictive prewarm;
- screenshot continuity cache;
- Browser Profile migration/reset;
- persistence schema change;
- Attention/Unread policy change;
- background-generation cadence changes;
- fullscreen redesign;
- generic WebView threading redesign;
- private WebKit API;
- release/version bump.

## STOP conditions

STOP/reconcile if the corrective requires:

- a second Runtime lifecycle writer or second presentation/focus/Attention truth owner;
- Browser Profile/session/persistent-data mutation;
- private WebKit API;
- hidden persistent WebViews as continuity objects;
- larger Runtime budget merely to mask restore cost;
- screenshot persistence;
- arbitrary reload/double-navigation/fixed-delay workaround;
- unbounded readiness polling;
- material production scope outside the frozen paths;
- release/version work.

## Current execution state

```text
PHASE_6_AUDIT=COMPLETE
PHASE_6_CONTRACT=ACCEPTED / FROZEN
SELECTED_OPTION=TWO_STAGE_NATIVE_RESTORE_SHELL
READINESS_POLICY=OUTCOME_A_NAVIGATION_BACKED_EXACT_CURRENT_RUNTIME
WP0_GATE0=COMPLETE / OUTCOME_A
WP1_NATIVE_RESTORING_PRESENTATION=COMPLETE
WP2_TWO_STAGE_ORCHESTRATION=COMPLETE
WP3_READINESS_COMPLETION=COMPLETE / CORRECTIVE REQUIRED
WP4_VERIFICATION=ACTIVE / EXACT_DIFF_AUDIT_CHANGES_REQUIRED
WP4_IMPLEMENTATION_HEAD=0ad45bff7869cdf66ac26994396ff013c89b0fbe
WP4_REQUIRED_CI=PASS / RUN 1302
WP4_QA_DMG=PASS / RUN 627
WP4_REAL_MAC_SMOKE=PENDING AFTER CORRECTIVE
MERGE_READINESS=BLOCKED
PRODUCT_MUTATION=AUTHORIZED WITHIN FROZEN CORRECTIVE SCOPE
NEXT_USER_START_REQUIRED=NO
TASK_RECONCILIATION_REQUIRED=NO
PROGRAM_HUMAN_ACCEPTANCE=PENDING
```

Next action: apply C1–C4 as one bounded corrective on the same branch and PR, then rerun the fresh WP4 gates. Do not merge or release before fresh independent audit passes.
