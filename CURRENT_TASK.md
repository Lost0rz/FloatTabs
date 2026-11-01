# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Title:** Runtime Lifecycle / Memory redesign — Phase 6 perceived-fast restore  
**Status:** `WAITING_FOR_PHASE_6_IMPLEMENTATION_AUTHORIZATION`  
**Mode:** `AUDIT COMPLETE / DESIGN PROPOSED / NO PRODUCT MUTATION`  
**Task class:** `WEB RUNTIME / RESTORE RESPONSIVENESS`  
**JSC root cause:** `UNKNOWN`

## Authorization state

Phase 5 merged on 2026-11-01 via PR #183. The user then authorized a detailed Phase 6 audit. That audit is complete.

The current authorization **does not permit Phase 6 product implementation**. Source/test mutation must wait for explicit implementation authorization and task reconciliation.

Durable audit/design record:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Audit_V1.md`

Status: `AUDIT COMPLETE / PROPOSED DESIGN / NOT IMPLEMENTATION AUTHORITY`.

## Verified audit findings

1. Safe hibernate/restore already exists and should remain the foundation.
2. `WebViewPool` keeps one memory-local opaque interaction-state snapshot and recreates Runtime against the same Browser Profile datastore.
3. incompatible Browser Profile/rendering/URL state is invalidated and uses URL fallback.
4. the strongest perceived-latency boundary is synchronous presentation ordering: `PanelController.synchronizeSlotState()` can create/restore a fresh WKWebView before the hidden shell is ordered front.
5. `WebPanelContainerView` has no explicit restoring presentation state.
6. current `web_runtime.restore.completed` proves state handoff, not first visual/usable content.
7. existing structural tests cover restore correctness but do not establish the real-WKWebView callback/paint sequence of `interactionState` restoration.
8. existing navigation commit handling already validates the exact current WebView and is used as a page-readiness signal for presentation focus; this ownership should be reused.

## Selected recommendation

**Option A — two-stage native restore shell + deferred materialization.**

Proposed flow:

```text
current selected Slot is non-resident
→ PanelController creates a private materialization generation
→ clear stale selected-WebView focus target
→ WebPanelContainerView presents lightweight native restoring state
→ existing shell/source window group becomes visible without waiting for WKWebView
→ return to AppKit run loop
→ next bounded main-actor turn revalidates generation/slot/visibility/fullscreen lock
→ existing WebViewPool.webView(for:) materializes/restores Runtime
→ attach fresh WebView under restoring state
→ existing lifecycle/fullscreen/focus ownership resumes
→ dismiss restoring state on proven current-Runtime readiness
```

Resident Slot switching keeps the existing direct fast path.

## Rejected alternatives for V1

### Screenshot cache

Do not use a page image snapshot as the default Phase 6 continuity mechanism. Public WebKit snapshot capture is asynchronous and would introduce page-content handling, extra memory, staleness/privacy concerns and a new capture race at hibernate.

### Prewarm / larger Runtime budget

Do not raise the Phase 4 budget or retain extra hidden WebViews merely to hide restore latency.

### Restore rewrite

Do not replace `interactionState` / Browser Profile restore without evidence of a correctness problem.

## Open evidence gate

Before freezing implementation readiness semantics, run one bounded Real-Mac probe using an actually hibernated existing Slot and record content-free timestamps/events for:

```text
selection / summon
→ native shell ordered
→ WKWebView allocated
→ interactionState assigned
→ navigation provisional / commit / finish, if any
→ isLoading transitions
→ bounded page/renderer readiness
→ focus success
```

This determines the exact overlay-dismiss signal. Do not guess it from structural tests.

## Proposed implementation scope after authorization

Expected product files:

- `FloatTabs/Panel/PanelController.swift`
- `FloatTabs/Web/WebViewContainer.swift`
- `FloatTabs/Web/WebViewPool.swift` only if a narrow read-only materialization/restore-source seam is required
- `FloatTabs/Web/SlotNavigationObserver.swift` only if current navigation callbacks cannot expose the final evidence-backed readiness boundary without ownership drift

Expected tests:

- `FloatTabsTests/ExternalShellTests.swift`
- `FloatTabsTests/WebViewPoolTests.swift` for unchanged restore invariants
- existing focus tests if the deferred path touches focus timing

## Acceptance gates for eventual implementation

1. resident Slot fast path remains direct;
2. reclaimed visible Slot gets native restore feedback before fresh WebView materialization starts;
3. no extra persistent WKWebView residency;
4. stale materialization generations cannot attach/focus/activate;
5. selection change/dismiss/fullscreen lock cancels pending presentation work;
6. existing `WebViewPool` restore semantics and Browser Profile/session identity remain unchanged;
7. no duplicate URL load on compatible interactionState restore;
8. Phase 4 Runtime budget semantics remain unchanged;
9. no page content / screenshot / opaque interaction state is persisted or logged;
10. focused tests, full XCTest, Debug/Release arm64 and required PR CI pass;
11. Real-Mac smoke captures request → shell-visible → WebView-attached → readiness/focus evidence before merge.

## STOP conditions

STOP/reconcile if implementation requires:

- a second Runtime lifecycle writer;
- Browser Profile/session/persistent data mutation;
- private WebKit API;
- hidden persistent WebViews as continuity objects;
- Phase 4 budget expansion merely to make restore look faster;
- screenshot persistence;
- arbitrary reload/double-navigation/timer workaround to manufacture readiness;
- Attention semantics change;
- unresolved fullscreen source ownership outside the existing session-lock boundary;
- release/version work.

## Reconciliation status

```text
PHASE_6_AUDIT=COMPLETE
RECOMMENDED_OPTION=TWO_STAGE_NATIVE_RESTORE_SHELL
PRODUCT_IMPLEMENTATION=NOT_AUTHORIZED
OPEN_EVIDENCE=REAL_MAC_INTERACTIONSTATE_READINESS
TASK_RECONCILIATION_REQUIRED=YES
```

Next mutation requires explicit user authorization for the bounded Phase 6 implementation.