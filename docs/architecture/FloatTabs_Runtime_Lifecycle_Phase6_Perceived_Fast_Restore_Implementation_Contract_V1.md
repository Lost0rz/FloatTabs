# FloatTabs Runtime Lifecycle — Phase 6 Perceived-fast Restore Implementation Contract V1

**Program:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Phase:** `6 — Perceived-fast Restore`  
**Status:** `ACCEPTED / FROZEN / IMPLEMENTATION NOT STARTED`  
**Parent contract:** `FloatTabs_Runtime_Lifecycle_Memory_Contract_V4.md`  
**Audit basis:** `FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Audit_V1.md`  
**Freeze baseline:** `main@ac6ca739a2d6e84af8e99fe5cc6623519b727a39`

This document is the durable Phase 6 implementation contract. It freezes the selected architecture, ownership, bounded source/test scope, evidence gates, acceptance criteria and STOP conditions for the next execution session.

This freeze does **not** perform product implementation. Product source/test mutation remains held until the user gives a future explicit start instruction.

## 1. Objective

Make a reclaimed persistent Slot feel immediately responsive when selected or summoned, without retaining extra heavyweight `WKWebView` runtimes and without changing Browser Profile/session truth.

The user-visible contract is:

```text
user selects/summons a reclaimed Slot
→ FloatTabs native shell responds immediately
→ a lightweight restoring presentation explains the transient state
→ fresh WebKit Runtime materializes through the existing owner
→ current Runtime becomes ready
→ restoring presentation disappears
→ existing focus/input ownership resumes
```

Phase 6 optimizes **perceived restore responsiveness**. It does not redefine persistence, Runtime budget, Browser Profiles, Attention, or the underlying public WebKit hibernate/restore mechanism.

## 2. Frozen decisions

### User / project decisions

1. Phase 6 uses a **two-stage native restore shell + deferred Runtime materialization**.
2. FloatTabs must not keep extra hidden `WKWebView`s alive merely to fake fast restore.
3. No screenshot cache is introduced as the default continuity mechanism.
4. Existing Browser Profile / `WKWebsiteDataStore` identity and `interactionState` restore remain the restore foundation.
5. Phase 4 Runtime-budget semantics are not changed by Phase 6.
6. This freeze session updates only repository contracts/control documentation; product construction happens in a later conversation.

### Verified constraints

1. `PanelController.synchronizeSlotState()` currently materializes a missing selected Runtime synchronously.
2. On hidden → visible summon, that synchronization can occur before `panel.orderFrontRegardless()`.
3. `WebViewPool` already owns fresh Runtime creation and compatible `interactionState` restoration.
4. `SlotLifecycleCoordinator` already owns hibernate/reclaim execution and remains the only lifecycle executor.
5. Browser Profile/session lifetime is independent from live `WKWebView` lifetime.
6. Structural XCTest coverage does not prove the exact public callback/loading sequence of real `interactionState` restoration.

## 3. Frozen ownership

| Concern | Owner | Phase 6 rule |
| --- | --- | --- |
| persistent Slot/Profile/config | existing Tabs/Persistence owners | unchanged |
| Browser Profile datastore/session | existing Browser Profile/WebKit store owner | unchanged |
| Runtime creation/restore | `WebViewPool` | unchanged |
| Runtime reclaim/budget | `SlotLifecycleCoordinator` | unchanged |
| presentation intent / selected Slot composition | `PanelController` | owns Phase 6 orchestration |
| lightweight restoring presentation | `WebPanelContainerView` | presentation only; no lifecycle decisions |
| navigation truth | `SlotNavigationObserver` → `WebViewPool` | unchanged |
| focus/input | existing `PanelController` / `WebFocusRouter` path | unchanged |
| Attention | `WebAttentionCoordinator` | unchanged |
| evidence | `RuntimeDiagnostics` | observation only |

No second Runtime lifecycle writer is permitted.

## 4. Frozen two-stage flow

### 4.1 Resident Slot fast path

If the selected Slot already owns a live compatible Runtime, preserve the current direct path.

```text
selection
→ use resident WebView
→ existing container/lifecycle/focus behavior
```

Do not route resident switching through restoring UI or deferred materialization.

### 4.2 Reclaimed Slot path

For a selected Slot with no live Runtime:

```text
selection/summon request
→ create a private materialization generation/request in PanelController
→ clear stale selected-WebView focus target
→ show native restoring presentation for the current Slot
→ make the existing FloatTabs shell/source window group visible
→ return to AppKit run loop
→ next bounded main-actor turn revalidates request identity
→ WebViewPool.webView(for:) creates/restores the fresh Runtime
→ attach fresh WebView under the restoring presentation
→ existing lifecycle/fullscreen/navigation/focus owners resume
→ evidence-backed readiness resolver marks current Runtime ready
→ remove restoring presentation
```

The first native visual response must not wait for fresh `WKWebView` allocation.

## 5. Materialization generation and stale-work contract

`PanelController` owns one private monotonically advancing materialization generation or equivalent request identity.

A pending request is valid only while all required facts still match:

- requested Slot ID is still selected;
- request generation is still current;
- presentation intent still requires the Slot to be shown;
- application/session is not terminating/resetting;
- fullscreen/source-host ownership permits synchronization;
- the target has not already become resident through another valid path.

Revalidate at minimum:

1. before Runtime materialization starts;
2. after materialization returns, before container attachment/focus/lifecycle activation;
3. before readiness completion removes the restoring presentation.

A stale request may not attach, focus, activate, or remove the restoring state for a newer request.

If a fresh Runtime was created but the request becomes stale before attachment, cleanup must follow existing Runtime/lifecycle ownership rather than inventing a second release policy in `PanelController`.

## 6. Native restoring presentation contract

The restoring state is lightweight native AppKit presentation. It may use only already-available non-sensitive app metadata such as:

- Slot display name;
- existing favicon presentation if already loaded;
- neutral activity/progress affordance;
- current app appearance/theme.

It must not:

- capture or persist page screenshots;
- inspect/log page content;
- persist opaque `interactionState`;
- own navigation, Runtime lifetime or Browser Profile state;
- masquerade as a loaded page.

The restoring view may remain above the fresh WebView after attachment until readiness is proven.

## 7. Gate 0 — Real-Mac readiness evidence

Before Phase 6 product-source mutation begins, the executor must run one bounded Real-Mac observation against an actually hibernated existing Slot.

This gate is a **behavioral evidence gate**, not a performance benchmark and not final human acceptance.

Record content-free timestamps/events only:

```text
selection / summon request
→ native shell ordering boundary
→ fresh WKWebView allocation
→ interactionState assignment OR URL fallback classification
→ navigation provisional / commit / finish callbacks, if any
→ isLoading transitions, if observable through existing public seams
→ bounded current-Runtime renderer/page readiness result
→ focus success/failure boundary
```

Do not record page text, screenshots, DOM content, cookies, session values, opaque interaction state, or other user data.

### 7.1 Pre-authorized evidence outcomes

Gate 0 may continue directly into implementation only when evidence fits one of these classes:

#### Outcome A — navigation-backed restore readiness

A real compatible `interactionState` restore produces usable current-Runtime navigation/loading callbacks that can be validated against the exact current WebView/runtime generation.

Implementation may reuse those existing current-Runtime callbacks as the trigger for the final bounded readiness check.

#### Outcome B — non-navigation interaction-state readiness

A compatible `interactionState` restore does not reliably produce the same navigation callback sequence, but the fresh attached current Runtime can establish readiness through existing/public bounded renderer/page readiness observation without polling ownership drift.

Implementation may use that public current-Runtime readiness observation as the restoring-surface completion boundary.

### 7.2 Gate 0 STOP outcome

STOP and reconcile before product mutation if real evidence shows any of the following:

- no public bounded current-Runtime fact can safely distinguish ready from not-ready;
- readiness would require arbitrary fixed delays or repeated unbounded polling;
- readiness requires private WebKit API;
- interaction-state restoration behaves materially differently from the audited model in a way that changes ownership/scope;
- correct readiness would require Browser Profile/session mutation, reload/double-navigation, screenshot persistence, or extra resident WebViews.

### 7.3 Readiness rule that is frozen now

The contract freezes the **selection rule**, not an unverified callback name:

> Remove the native restoring presentation only after the current materialization generation, current Slot, and exact current Runtime all still match **and** Gate 0 has identified a public bounded readiness fact from Outcome A or Outcome B.

`web_runtime.restore.completed` alone is never sufficient because it proves state handoff, not usable presentation.

No arbitrary timer may be used as the readiness truth.

## 8. Expected production scope

Authorized implementation paths after a future explicit user start and successful Gate 0:

### `FloatTabs/Panel/PanelController.swift`

Expected responsibilities:

- pending materialization generation/request identity;
- resident-vs-reclaimed routing;
- early native shell presentation;
- one bounded deferred main-actor materialization turn;
- stale request validation/cancellation;
- attachment ordering;
- restoring-state completion orchestration;
- existing focus/fullscreen ownership integration.

### `FloatTabs/Web/WebViewContainer.swift`

Expected responsibilities:

- lightweight native restoring state;
- show/update/hide presentation API;
- allow fresh WebView attachment beneath restoring state;
- no Runtime lifecycle or navigation policy.

### `FloatTabs/Web/WebViewPool.swift`

Default expectation: **no semantic restore rewrite**.

A narrow read-only query/result may be added only if required to distinguish restore source/readiness without duplicating Runtime truth in `PanelController`.

### `FloatTabs/Web/SlotNavigationObserver.swift`

Default expectation: no ownership change.

A narrow current-Runtime readiness callback/seam may be added only when Gate 0 Outcome A proves it is necessary and current callbacks cannot already expose the required fact safely.

### Scope expansion rule

Any additional production file is a STOP/reconciliation trigger unless it is a mechanically necessary project/build reference with no semantic expansion.

## 9. Expected test scope

Primary expected tests:

- `FloatTabsTests/ExternalShellTests.swift` — early native shell/restoring presentation ordering, resident fast path, stale request cancellation, dismiss/switch/fullscreen boundaries;
- `FloatTabsTests/WebViewPoolTests.swift` — unchanged interaction-state restore invariants and no duplicate URL load;
- existing focus-related tests only if deferred materialization changes focus timing.

Add the smallest new fixture required for deterministic scheduling/generation tests. Do not create a second fake Runtime architecture merely for tests.

## 10. Work packages

### WP0 — Gate 0 evidence

**Objective:** establish the real public readiness class for compatible `interactionState` restoration.  
**Writer boundary:** evidence/control documentation only; no product-source mutation.  
**Acceptance:** Outcome A or B classified with content-free evidence, or STOP outcome recorded.

### WP1 — restoring presentation primitive

**Objective:** add the native restoring surface to `WebPanelContainerView`.  
**Dependency:** WP0 PASS.  
**Writer boundary:** `WebViewContainer.swift` + focused tests.  
**Acceptance:** deterministic show/hide/overlay behavior; no lifecycle ownership.

### WP2 — two-stage presentation orchestration

**Objective:** order shell before missing Runtime materialization and add generation/stale guards.  
**Dependency:** WP0 PASS, WP1.  
**Writer boundary:** `PanelController.swift` + focused shell/focus tests.  
**Acceptance:** reclaimed path gives native feedback before materialization; resident path remains direct.

### WP3 — readiness integration

**Objective:** wire Gate 0 Outcome A/B to current-Runtime restoring completion.  
**Dependency:** WP0 classification, WP1/WP2.  
**Writer boundary:** smallest of existing Panel/WebPool/Navigation seams.  
**Acceptance:** only the current Slot/request/Runtime can dismiss restoring UI; no timer truth.

### WP4 — verification / merge gate

**Objective:** prove correctness, data safety and regression safety.  
**Dependency:** WP1–WP3.  
**Writer boundary:** tests/control evidence only.  
**Acceptance:** all gates in Section 11 pass.

Work-package structure is planning guidance, not a mandated Sub Agent topology.

## 11. Verification and acceptance gates

### Gate A — Gate 0 Real-Mac evidence

Outcome A or B is proven before product-source mutation; otherwise STOP.

### Gate B — focused correctness

Must cover at minimum:

1. resident Slot remains direct/no restoring state;
2. reclaimed Slot shows restoring state before materialization call starts;
3. exactly one current materialization request may attach;
4. rapid selection change makes older pending request stale;
5. dismissal before materialization prevents stale attach/focus;
6. fullscreen/source-session lock does not accept unsafe pending synchronization;
7. current request only can remove restoring state;
8. restore/fallback classification does not create duplicate navigation;
9. Browser Profile/session identity remains unchanged;
10. no extra persistent Runtime residency is introduced.

### Gate C — broad regression

Full XCTest must pass with no new failures caused by Phase 6.

### Gate D — builds

Debug + Release Apple Silicon builds and native architecture verification must pass.

### Gate E — required repository CI

Literal PR head must pass:

`Build & Test (Apple Silicon arm64)`

on the established self-hosted runner labels.

### Gate F — bounded Real-Mac restore smoke

Before merge, exercise at least:

```text
resident Slot switch
reclaimed Slot restore via compatible interactionState
reclaimed Slot URL fallback if safely reproducible
rapid switch away during pending restore
hide/dismiss during pending restore
```

Capture content-free evidence for:

```text
request
→ native shell/restoring visible
→ materialization start
→ WebView attached
→ readiness established
→ focus result
```

No absolute latency target is claimed in V1; this phase proves ordering and correctness first.

### Gate G — independent exact-diff audit

Before merge, verify ownership, stale-work safety, Browser Profile/session safety, no Runtime-budget leakage, exact scope and all required evidence.

## 12. Acceptance criteria

Phase 6 V1 is merge-ready only when all are true:

1. native shell/restoring presentation is visible before fresh Runtime materialization begins for a reclaimed visible Slot;
2. resident Slot path remains direct;
3. no extra hidden persistent WebView is retained;
4. no Phase 4 managed-resident target/ranking/protection behavior changes;
5. stale materialization work cannot attach/focus/activate/dismiss newer restoring state;
6. compatible interaction-state restore still avoids duplicate normal URL load;
7. Browser Profile/session/persistent user data remain unchanged;
8. readiness uses a Gate 0-proven public bounded fact, never an arbitrary delay;
9. no screenshot/page content/opaque interaction state is persisted or logged;
10. existing fullscreen source ownership and focus ownership remain canonical;
11. focused/full tests and Debug/Release arm64 pass;
12. required literal-head PR CI passes;
13. bounded Real-Mac restore smoke passes.

## 13. Explicit non-scope

Do not include in Phase 6 V1:

- Settings-backed Runtime budget tuning;
- changing managed resident target from the Phase 4 default;
- predictive prewarming;
- screenshot continuity cache;
- Browser Profile migration or website-data reset;
- persistence schema change;
- Attention/Unread semantics change;
- background generation cadence changes;
- fullscreen redesign;
- generic WebView creation threading redesign;
- private WebKit API;
- release/version bump.

## 14. STOP conditions

STOP and reconcile if implementation needs:

- a second Runtime lifecycle writer;
- a second presentation truth owner;
- Browser Profile/session/persistent user-data mutation;
- private WebKit API;
- hidden persistent WebViews as continuity objects;
- a larger Runtime budget merely to mask restore cost;
- screenshot persistence;
- arbitrary reload/double-navigation/fixed-delay workaround to manufacture readiness;
- unbounded readiness polling;
- Attention semantics change;
- unresolved fullscreen source ownership outside the existing source-session lock boundary;
- production files outside Section 8 with material semantic responsibility;
- release/version work.

## 15. Execution hold / next-session rule

Current state after this contract freeze:

```text
PHASE_6_CONTRACT=ACCEPTED / FROZEN
PRODUCT_IMPLEMENTATION=NOT_STARTED
CURRENT_SESSION_PRODUCT_MUTATION=FORBIDDEN
NEXT_USER_START_REQUIRED=YES
```

When the user gives a future explicit start/continue instruction for Phase 6 construction:

1. refresh `main`, Authority and task-relevant repository state;
2. execute WP0 / Gate 0 first;
3. if Gate 0 is Outcome A or B and no other STOP condition fires, continue directly through the frozen implementation contract without redesigning the task;
4. if Gate 0 produces the STOP outcome, stop before product mutation and reconcile evidence;
5. do not create a new architecture plan merely because execution occurs in a new conversation or agent context.

## 16. Design disposition

```text
SELECTED_OPTION=TWO_STAGE_NATIVE_RESTORE_SHELL
READINESS_POLICY=GATE0_EVIDENCE_BOUND
RUNTIME_OWNER=WEBVIEWPOOL_UNCHANGED
LIFECYCLE_OWNER=SLOTLIFECYCLECOORDINATOR_UNCHANGED
PRESENTATION_OWNER=PANELCONTROLLER_UNCHANGED
RUNTIME_BUDGET=UNCHANGED
BROWSER_PROFILE_SESSION=UNCHANGED
TASK_RECONCILIATION_REQUIRED=NO_AFTER_THIS_FREEZE
EXECUTION_HOLD=UNTIL_FUTURE_EXPLICIT_USER_START
```

This V1 contract supersedes the Phase 6 audit document **for execution scope**, while the audit remains the durable evidence/rationale record.
