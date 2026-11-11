# FloatTabs Runtime Lifecycle — Phase 6 Perceived-fast Restore Audit V1

**Program:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Phase:** `6 — Perceived-fast Restore`  
**Status:** `AUDIT COMPLETE / PROPOSED DESIGN / NOT IMPLEMENTATION AUTHORITY`  
**Parent contract:** `FloatTabs_Runtime_Lifecycle_Memory_Contract_V4.md`  
**Audit baseline:** `main@ed81f6d7879e7142a300a5d070a488b6747b27bb`

This is a historical Phase 6 source/test/design audit, not a current implementation instruction. Its proposed next steps, task-reconciliation and approval language applied only to the original audited revision.

## 1. Executive verdict

Phase 6 should **not** redesign hibernate/restore correctness. Phase 1 already established the right WebKit mechanism and the current source preserves it:

- eligible inactive Runtime reclamation captures one memory-local opaque `WKWebView.interactionState` snapshot;
- the old Runtime is deterministically torn down;
- a compatible restore creates a fresh Runtime against the same Browser Profile datastore before applying `interactionState`;
- incompatible/missing state falls back to the safe current/home URL path;
- the snapshot is neither persisted nor logged as product data;
- Browser Profile/session identity remains independent from live `WKWebView` lifetime.

The primary Phase 6 UX problem is **presentation ordering**.

For a reclaimed active Slot, current `PanelController.synchronizeSlotState()` synchronously calls `webViewPool.webView(for:)`. Fresh Runtime creation includes datastore resolution, bridge/script/observer construction, `WKWebView` allocation and restore-state application. When FloatTabs is summoned from hidden state, `showFloatTabs` performs that synchronous synchronization **before** `panel.orderFrontRegardless()`.

Therefore user-visible shell presentation can be blocked behind fresh WebKit Runtime materialization. After creation, the WebView is attached directly to the visible container; there is no explicit native `restoring` presentation state and no product-owned "first usable content" boundary.

### Recommended Phase 6 direction

Implement a **two-stage native restore presentation**:

```text
user selects/summons reclaimed Slot
→ immediately present existing native FloatTabs shell + lightweight restoring surface
→ return to AppKit run loop
→ materialize the fresh WKWebView on the next bounded main-actor turn
→ attach the fresh WebView underneath the restoring surface
→ preserve existing WebKit interactionState / URL-fallback restore semantics
→ clear restoring surface only on an approved current-Runtime readiness boundary
→ existing presentation-focus handshake owns input focus
```

This improves perceived responsiveness without retaining additional heavyweight WebViews and without changing Runtime budget semantics.

## 2. Verified current restore call path

### Reclaim

```text
SlotLifecycleCoordinator
→ prepareRuntimeForRelease(slotID)
→ WebPanelContainerView.removeSlot
→ WebViewPool.hibernate(slotID)
→ capture opaque interactionState + compatible URL/Profile/Rendering identity
→ deterministic old-Runtime teardown
→ Slot remains persistent; live Runtime becomes nil
```

The lifecycle coordinator remains the sole reclamation executor.

### Re-activation / materialization

For a non-resident selected Slot:

```text
PanelController.synchronizeSlotState
→ deactivate previous selected Slot if needed
→ WebViewPool.webView(for: activeProfile)
    → resolve navigation URL
    → resolve same Browser Profile WKWebsiteDataStore
    → validate pending restore snapshot
    → construct Attention/Response bridges + scripts + observer/delegates
    → create fresh WKWebView + fresh Runtime identity
    → compatible snapshot: assign interactionState, consume snapshot
       OR
       no compatible snapshot: ordinary URL load
→ WebPanelContainerView.show(webView:slotID:residencyPolicy:)
→ WebFocusRouter.setCurrentWebView
→ SlotLifecycleCoordinator.activate
→ fullscreen observation
```

### Hidden → visible presentation ordering

The ordinary summon path currently performs:

```text
position shell/source host
→ SlotLifecycleCoordinator.setPanelVisible(true)
→ synchronizeSlotState()        // may synchronously materialize WKWebView
→ panel.orderFrontRegardless()  // shell becomes visible only after above returns
→ app activation / focus handoff
```

This is the strongest verified Phase 6 perceived-latency boundary.

### Navigation/focus readiness

`SlotNavigationObserver` emits navigation commit/finish callbacks. `WebViewPool` validates that commit callbacks still belong to the exact current WebView before forwarding committed-URL change. `PanelController` already treats committed navigation as a readiness signal for one deferred standard-presentation focus attempt.

This existing current-Runtime validation should be reused rather than introducing polling or a second navigation authority.

## 3. Ownership map

| Concern | Current / proposed owner | Phase 6 rule |
| --- | --- | --- |
| persistent Slot/Profile/session | existing persistence/Profile domains | unchanged |
| Runtime materialization / interactionState | `WebViewPool` | unchanged |
| Runtime reclaim decision/execution | `SlotLifecycleCoordinator` | unchanged |
| product/presentation visibility | `PanelController` | remains authority |
| native restoring surface | `WebPanelContainerView`, orchestrated by `PanelController` | presentation only |
| page navigation callbacks | `SlotNavigationObserver` → `WebViewPool` | unchanged authority |
| input focus | existing `PanelController` / `WebFocusRouter` handshake | unchanged |
| Attention | `WebAttentionCoordinator` | unchanged |
| evidence | `RuntimeDiagnostics` | evidence only |

No new Runtime owner or lifecycle writer is required.

## 4. Current data-safety findings

### Verified safe

- Default Browser Profile recreation resolves `WKWebsiteDataStore.default()`.
- Custom Browser Profile recreation resolves the same UUID-backed `WKWebsiteDataStore(forIdentifier:)` on supported macOS versions.
- Restore snapshot compatibility includes Browser Profile identity, normalized Runtime rendering and captured/navigation URL.
- mismatch invalidates the transient snapshot instead of forcing it onto an incompatible Runtime.
- destructive `release` semantics remain distinct from normal hibernate.
- stale old-Runtime navigation callbacks are rejected through current WebView/runtime identity checks.

### Must remain forbidden

- deleting/recreating website data to make restore appear clean;
- persisting/logging opaque `interactionState`;
- private WebKit restore APIs;
- keeping reclaimed WebViews hidden merely to avoid restore latency.

## 5. Latency / UX risk inventory

### R1 — shell presentation is behind synchronous WebView materialization

**Severity:** HIGH  
**Confidence:** HIGH

A reclaimed Slot can force fresh WebKit creation inside `synchronizeSlotState()` before the shell window is ordered front. The user can therefore experience a summon/switch as "nothing happened yet" even if the eventual page restore is correct.

### R2 — no explicit native restoring presentation state

**Severity:** HIGH  
**Confidence:** HIGH

`WebPanelContainerView` supports native non-Web states such as empty/unsupported states, but there is no restoring state. A newly created/restoring WebView becomes the content surface directly, so blank/unfinished WebKit presentation is exposed to the user.

### R3 — `web_runtime.restore.completed` is not a first-visual/usable boundary

**Severity:** MEDIUM  
**Confidence:** HIGH

Current restore completion diagnostics are emitted after the opaque interaction state is assigned. That proves restore-state handoff, not first paint, navigation commit, DOM readiness or usable input. Existing evidence therefore cannot quantify the actual perceived-restore path.

### R4 — current structural restore tests do not prove real-WebKit presentation timing

**Severity:** MEDIUM  
**Confidence:** HIGH

`WebViewPoolTests` cover compatible restore, URL fallback, Profile/rendering mismatch, destructive release and sibling isolation. Their interaction-state fixtures inject provider/applier seams; they do not establish the callback/paint sequence of a real reclaimed `WKWebView` on the target sites/OS versions.

### R5 — immediate synchronous materialization cannot cheaply suppress rapid stale selections

**Severity:** MEDIUM  
**Confidence:** MEDIUM

Every non-resident selected Slot enters materialization in the same synchronous selection path. A two-stage request generation can cancel a selection that becomes stale before materialization starts, reducing avoidable WebView churn. Once `WKWebView` creation has started on the main actor it is not treated as cancellable.

### R6 — Browser Profile/session restore architecture is not the current bottleneck

**Severity:** LOW / protective finding  
**Confidence:** HIGH

The existing datastore identity and interaction-state architecture already matches the Phase 1 contract. Reworking this layer would add risk without evidence that it solves the observed perceived latency.

## 6. Candidate designs

### Option A — two-stage native restore shell + deferred materialization

**Recommendation: SELECT**

Mechanism:

1. detect that the selected active Slot has no resident WebView;
2. establish a new private presentation-materialization generation in `PanelController`;
3. clear the current Web focus target for that pending presentation;
4. show a lightweight native restoring view using existing Slot name/favicon/theme data only;
5. order the existing shell/source window group normally with no WebView focus requirement;
6. return to the AppKit run loop;
7. on the next bounded main-actor turn, revalidate generation + active Slot + presentation/fullscreen state;
8. call existing `WebViewPool.webView(for:)` unchanged in ownership;
9. attach the fresh WebView under the restoring presentation;
10. keep existing lifecycle/bridge/fullscreen/focus ownership;
11. dismiss the restoring presentation on a proven current-Runtime readiness signal.

Benefits:

- immediate deterministic user feedback is no longer coupled to WebKit creation time;
- no extra persistent WKWebView residency;
- no page-content snapshot storage;
- no Browser Profile/session changes;
- rapid stale requests can be discarded before materialization begins;
- highly reversible and localized.

Primary unresolved detail:

- the exact public readiness signal for `interactionState` restoration must be validated on Real Mac. Ordinary URL fallback has navigation commit/finish signals; current tests do not prove whether every relevant interaction-state restore produces the same callback sequence.

### Option B — cached page-image snapshot placeholder

**Recommendation: REJECT for Phase 6 V1**

A `WKWebView` can capture an image snapshot through public WebKit API, but capture is asynchronous. Using screenshots for continuity would introduce page-content handling, additional memory, freshness/privacy concerns and a new asynchronous capture race at the hibernate boundary.

This may be reconsidered only if the neutral native restore shell is insufficient after measurement. It must never be persisted by default as ordinary restore state.

### Option C — prewarm / retain more WebViews

**Recommendation: REJECT**

Predictive prewarm or a larger resident Runtime budget could improve actual readiness when prediction is correct, but it directly fights the Phase 4 memory objective and can create churn/oversubscription. Phase 6 must not hide restore latency by retaining heavyweight Runtime objects.

### Option D — rewrite interactionState/session restoration

**Recommendation: REJECT**

No current evidence justifies replacing the public WebKit interaction-state mechanism. The existing implementation is already isolated, memory-local and Browser-Profile-safe.

## 7. Proposed bounded Phase 6 implementation

Implementation should remain narrow:

### `PanelController.swift`

- add one private pending materialization generation/request;
- preserve resident-Slot fast path;
- for a visible/requested non-resident Slot, present restore shell before materialization;
- defer fresh materialization by one controlled main-loop scheduling seam;
- revalidate slot/presentation/fullscreen generation before materialization and before attachment;
- clear focus target while no selected WebView exists;
- reuse existing navigation/focus ownership after attachment;
- cancel pending request on selection change, dismissal, reset/termination or fullscreen lock transition.

### `WebViewContainer.swift`

- add a lightweight native restoring surface/overlay;
- use only existing non-sensitive app metadata (for example Slot name/favicon if already available in presentation state);
- allow fresh WebView attachment under the restoring overlay;
- explicit show/hide methods with no lifecycle policy.

### `WebViewPool.swift`

Prefer no semantic restore change. A narrowly scoped read-only materialization/restore-source result or query is acceptable only if `PanelController` cannot reliably distinguish the pending restore path without duplicating Runtime truth.

Do not move presentation state into `WebViewPool`.

### `SlotNavigationObserver.swift`

No ownership change. Existing current-WebView navigation events may be reused for readiness evidence. Add a narrowly scoped callback only if required after the Real-Mac readiness probe.

### Tests

Use existing test files where possible:

- `ExternalShellTests.swift` / Panel fixtures for presentation ordering and stale request cancellation;
- `WebViewPoolTests.swift` only for unchanged restore invariants;
- focus tests for no stale focus handoff.

## 8. Required pre-implementation evidence

One unresolved evidence item remains before the exact overlay-dismiss rule can be frozen:

### E1 — Real-Mac interactionState readiness sequence

Using an existing safe Slot that has actually been hibernated, observe only public facts for the fresh Runtime:

```text
selection / summon request
→ native shell ordered
→ WKWebView allocated
→ interactionState assigned
→ navigation provisional/commit/finish callbacks, if any
→ isLoading transitions
→ first successful bounded page/renderer readiness observation
→ focus success
```

The evidence must distinguish interaction-state restore from URL fallback and must not log page content.

This is a bounded restore-behavior probe, not a performance tuning matrix.

## 9. Acceptance gates for the eventual implementation

1. Resident Slot switching keeps the current direct fast path.
2. Reclaimed visible Slot presents native restore feedback before fresh WebView materialization starts.
3. The shell/source windows can be ordered without waiting for a WebView.
4. Exactly one current materialization request may attach a WebView; stale generations cannot attach/focus/activate.
5. Dismiss/switch/fullscreen-lock before materialization prevents stale presentation work.
6. `WebViewPool` still owns all Runtime creation and interaction-state restore semantics.
7. compatible interactionState restore still issues no duplicate ordinary initial URL load.
8. Browser Profile/session identity remains unchanged after hibernate/restore.
9. Phase 4 Runtime budget and Hot/Warm/Cold semantics remain unchanged.
10. no page screenshot or opaque interaction state is persisted/logged.
11. existing navigation/focus stale guards remain intact.
12. focused tests + full XCTest + Debug/Release arm64 builds pass.
13. required literal-head `Build & Test (Apple Silicon arm64)` passes on `macmini-floattabs-01`.
14. Real-Mac smoke records bounded timestamps for request → shell-visible → WebView-attached → readiness/focus; no absolute latency target is claimed until baseline evidence exists.

## 10. STOP conditions

STOP/reconcile if implementation requires:

- retaining additional hidden WebViews as continuity objects;
- changing the Phase 4 managed-resident budget merely to make restore look fast;
- a second Runtime lifecycle writer;
- moving product presentation truth into `WebViewPool` or Diagnostics;
- Browser Profile/session/persistent user-data mutation;
- persisting screenshots or opaque interaction state as an implicit cache;
- private WebKit API;
- arbitrary reload/double-navigation/timer workaround to manufacture readiness;
- changing Attention semantics;
- unresolved fullscreen ownership/race that cannot be handled by the existing source-session lock boundary.

## 11. Research alignment

The proposed architecture follows mature browser separation rather than copying Chromium internals:

- discarded browser tabs keep lightweight browser UI identity while page content is unloaded and restored/reloaded on activation;
- public WebKit `WKWebView.interactionState` exists specifically to capture interaction state and restore it to another `WKWebView`;
- public `WKWebView.takeSnapshot` exists, but it is asynchronous and is therefore intentionally not selected as the first-line Phase 6 mechanism.

FloatTabs should preserve its native shell/Slot identity as the continuity layer and let disposable WebKit Runtime remain disposable.

## 12. Audit disposition

```text
PHASE_6_AUDIT=COMPLETE
RECOMMENDED_OPTION=A / TWO-STAGE NATIVE RESTORE SHELL
PRODUCT_IMPLEMENTATION=NOT_AUTHORIZED
OPEN_EVIDENCE=REAL-MAC INTERACTIONSTATE READINESS SEQUENCE
TASK_RECONCILIATION_REQUIRED=YES
```

Before implementation, reconcile `CURRENT_TASK.md` from audit-only into a bounded Phase 6 implementation contract after explicit user authorization. The implementation contract must freeze the final readiness signal based on E1 evidence rather than guessing it.
