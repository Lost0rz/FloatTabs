# FT-DIAG-001 — Stuck-Slot Diagnostic Architecture Audit

**Audit date:** 2026-10-04  
**Audited main:** `68d03a0991be4ed1569b41816628b62b0a3677a1`  
**Mode:** remote read-only  
**Root-cause status:** **UNKNOWN**  
**Verdict:** **CONSTRUCTION_GATE_READY**

## Executive conclusion

FloatTabs already has a mature general runtime-diagnostics substrate and several strong owner-local stale-event guards. The stuck/blank/black Slot problem is not blocked by insufficient internal log volume. It is blocked by missing **cross-owner identity and boundary evidence**.

Current code can independently observe Slot selection, resident runtimes, navigation callbacks, WebContent termination, panel/source visibility, fullscreen restore, lifecycle protection/release, and ChatGPT bridge state. It cannot reliably prove that these facts refer to the same physical `WKWebView`, navigation, and document at the incident boundary, and normal-state WebView attachment/presentation is materially less observable than fullscreen restoration.

The next change should therefore be a bounded, observation-only probe foundation:

`session → source/build → slot → physical WKWebView → navigation generation → document epoch → incident capture`

No recovery, automatic reset, speculative workaround, or broad periodic sampler is authorized.

## Evidence discipline

Keep separate:

- **verified source facts** from current `main`;
- **historical runtime observations**;
- **historical experiments** in abandoned #99/#100/#101;
- **plausible mechanisms**;
- **proposed discriminators**.

Historical recovery success is not causal proof.

Historical observations relevant to the design:

- full app restart has recovered the symptom;
- Reload has sometimes remained visibly stuck despite WebKit commit/finish evidence;
- one historical incident was classified as `POST_COMMIT_NAVIGATION_STALL_WITH_RESPONSIVE_RENDERER`; JavaScript responded and navigation later finished, but no network/resource/page-app root cause was proven;
- separate WebContent terminations have occurred;
- an older stuck capture had completed navigation plus ChatGPT shell/composer/bridge evidence while a loading state remained;
- a later fresh incident recovered after replacing only the affected per-Slot runtime, in the same app process/session/Slot/profile and without a coincident network-path transition. That narrows the boundary toward per-Slot runtime/document/presentation state, but does not identify which layer was causal.

## Authority map

| Domain | Owner |
| --- | --- |
| Persisted Slot selection/configuration | `TabStore` |
| Resident physical WebViews | `WebViewPool` |
| Inactive/release policy | `SlotLifecycleCoordinator` |
| Normal WebView presentation | `WebPanelContainerView` |
| Fullscreen source/session | `FullscreenSourceHostController` |
| Navigation delegate lifecycle | `SlotNavigationObserver` |
| ChatGPT document/generation | `ChatGPTAttentionBridge` |
| ChatGPT response-document identity | `ChatGPTResponseBridge` |
| Web focus | `WebFocusRouter` |
| Observation/event envelope | `RuntimeDiagnostics` |

Diagnostics must remain non-authoritative.

# A. State-machine map

## A1. Persisted state / active Slot

**Owner:** `TabStore`

Effective flow:

`repository load → sanitize/normalize → restore lastActiveTabID | fallback first Slot → explicit selection → persist runtime state`.

Existing events cover selection requested/changed/failed.

**Gap:** startup restore is not bound to exact source/build, restored Slot reason, or page class.

## A2. Slot lifecycle

**Owner:** `SlotLifecycleCoordinator`

Effective axes:

- active Slot;
- panel visible/hidden;
- fullscreen source protected;
- supplemental visible;
- Hot/Warm/Cold residency;
- pending inactive plan;
- media/attention/speech protection;
- hidden-active grace;
- resident/nonresident runtime.

Stale delayed release work is already strongly guarded with `InactivePlan.token` and hidden-active tokens.

Existing diagnostics cover logical activate/deactivate/protection/release decisions.

**Gap:** those events do not prove the physical WebView result: attached/detached, host hidden, expected window, or physical instance.

## A3. Physical WebView / pool lifecycle

**Owner:** `WebViewPool`

Effective flow:

`absent → creating → resident → reused`

with:

- `resident → rebuilt → resident(new WKWebView)`;
- `resident → released → absent`;
- `resident + content termination → reload-now`;
- `resident + inactive termination → deferred reload → reload-on-activation`.

A WebContent termination can recover on the **same physical WKWebView**, so physical WebView identity and content-process/document recovery are distinct concepts.

Current callbacks often guard `existingWebView(slotID) === webView`, which is good local stale-work rejection.

**Critical gap:** no persisted `runtime_generation` or opaque `webview_instance_id`.

## A4. Normal presentation / attachment

**Owners:** `PanelController` + `WebPanelContainerView`

Hot effective flow:

`host absent → attached+visible → attached+hidden → visible → removed`.

Warm/Cold flow:

`detached → transient attached → detached → release/reuse`.

`PanelController.synchronizeSlotState()` obtains the pool WebView, presents it through the container, updates focus routing, activates lifecycle, and registers fullscreen observation.

The container itself performs the physical reparent/hide/remove operations.

**Critical gap:** ordinary presentation emits no direct evidence answering:

- does the pool WebView equal the presented WebView?
- is it descendant of the expected container?
- is any host/ancestor hidden?
- what window actually owns it?
- is that window visible/key?
- are frame/bounds nonzero?
- is it normal source, fullscreen-private, companion, none, or other?

Fullscreen restoration already performs comparable hierarchy checks; normal presentation does not.

## A5. Navigation lifecycle

**Owner:** `SlotNavigationObserver`

Effective flow:

`idle → provisional → committed → finished`

with provisional/post-provisional failure and content-termination exits.

Instant Back has a separate requested/activated/cancelled correlation path.

Existing events cover provisional start, commit, finish, fail, termination and Instant Back.

**Critical gaps:**

- no `navigation_generation` or navigation ticket;
- overlapping/superseded same-WebView navigations are difficult to reconstruct;
- late old-navigation callbacks cannot be tied to a durable generation;
- no current provisional/post-commit stall watchdog;
- the current finish-time JS runtime probe cannot run if finish never arrives.

## A6. ChatGPT document/generation

**Owner:** `ChatGPTAttentionBridge`

Current document admission states:

- awaiting supported baseline;
- active supported document;
- unsupported current document;
- awaiting authorized resync.

Strong existing identities/guards:

- opaque document token;
- monotonic document epoch within bridge;
- physical WebView `ObjectIdentifier`;
- resync generation;
- liveness watchdog generation.

The bridge rejects stale WebView/document callbacks correctly.

### Important blind spot

During an active generation, the liveness watchdog calls `evaluateJavaScript`, but the production probe has **no timeout**. If WebContent/JS never calls back, that liveness cycle can remain suspended and no explicit renderer-unresponsive classification is emitted.

The watchdog is also generation-specific, not a general stuck-page detector.

## A7. ChatGPT response-document state

**Owner:** `ChatGPTResponseBridge`

Strong local identity:

- current opaque document token;
- pending request ID;
- physical WebView object identity.

Async results are rejected when WebView/document identity changes.

**Gap:** this identity/readiness is not projected into general incident diagnostics.

## A8. Fullscreen source/session

**Owner:** `FullscreenSourceHostController`

States:

`idle → entering → fullscreen → exiting → restoring → idle`.

Identity: `restoreGeneration`.

This path already records source lock/unlock, state transitions, restore begin/completion/timeout and checks WebView/container/window hierarchy.

**Conclusion:** fullscreen is sufficiently observable for the next wave and provides the design pattern for normal-state presentation probes.

## A9. App/window/focus presentation

Current snapshot already includes requested visibility, shell/source visibility/key state, app active, screen IDs, active Slot, resident count, fullscreen state, focus target and presentation-focus generation.

**Gap:** it does not bind those facts to physical WebView instance, navigation generation or document epoch.

# B. Boundary map

| Boundary | Status | Missing discriminator |
| --- | --- | --- |
| Persisted state → restored active Slot | PARTIALLY_OBSERVED | startup restore/build provenance |
| User selection → activeTabID | OBSERVED | — |
| Active Slot → pool WebView | PARTIALLY_OBSERVED | physical instance/generation |
| Pool WebView → visible normal container | **UNOBSERVED** | binding/hierarchy snapshot |
| Normal source ↔ fullscreen/private/companion | PARTIALLY_OBSERVED | unify physical identity |
| Navigation → provisional/commit/finish/fail | PARTIALLY_OBSERVED | navigation generation/ticket |
| UI process → WebContent | PARTIALLY_OBSERVED | bounded generic JS round-trip |
| WebContent → admitted document | PARTIALLY_OBSERVED | project document epoch/readiness |
| Document → ChatGPT app state | PARTIALLY_OBSERVED | explicit incident health snapshot |
| Document/WebKit → actual rendered pixels | **UNOBSERVED** | deferred render-surface discriminator |
| OS network path → WebKit resource behavior | **UNOBSERVED** | deferred network evidence |
| Termination → reload/defer recovery | OBSERVED, weak correlation | physical/nav identity |
| Rebuild/recreate → new physical WebView | PARTIALLY_OBSERVED | before/after instance identity |
| Restart → runtime reconstruction | PARTIALLY_OBSERVED | source revision + restored Slot provenance |

WebKit provides a public content-process termination delegate boundary. It does not give this application a supported WebContent PID identity that should be invented in diagnostics.

A successful bounded JavaScript round trip is evidence that WebContent/JS execution responded at that moment. Timeout means **unresponsive candidate**, not confirmed process death.

`WKWebView.takeSnapshot` is deliberately deferred from Wave A: rendered-pixel handling introduces extra privacy and interpretation obligations and is only justified if hierarchy + JS + app-state evidence still leaves a compositor/render ambiguity.

# C. Probe inventory and gap analysis

## Existing high-value observations — do not duplicate

Keep and reuse:

- process/session envelope and monotonic sequence;
- Tab selection traces;
- panel/source window visibility and key state;
- presentation focus generation;
- fullscreen restore generation and hierarchy checks;
- Slot lifecycle tokens/protection/release events;
- pool create/reuse/rebuild/release/termination events;
- navigation delegate boundaries;
- attention document token/epoch stale rejection;
- response-document stale async rejection.

## P0 Probe Foundation — next authorized construction scope

### P0.1 Exact build/source provenance

Add bounded launch/export metadata:

- `source_revision`;
- `build_channel`;
- `qa_label`;
- optional host PID.

Purpose: prevent incidents from different QA/source heads being merged.

Event cost: launch/export only.

### P0.2 Physical WebView identity spine

For every physical WebView created by the pool assign:

- process-local monotonic `runtime_generation`;
- opaque UUID `webview_instance_id`.

Rules:

- reuse preserves both;
- release removes them;
- rebuild/recreate gets new identity;
- content-process termination does not pretend the physical WebView changed.

Add these as fields to existing runtime/navigation events instead of creating steady-state log volume.

### P0.3 Navigation generation/ticket

Add per-physical-runtime monotonic `navigation_generation`, internally correlated to the current `WKNavigation` object.

Requirements:

- one true provisional navigation advances generation;
- duplicate current-navigation callback does not create another generation;
- commit/finish/fail resolve to their ticket;
- stale old-navigation callbacks cannot complete/advance current diagnostic state.

### P0.4 Observation-only stall classifier

Fresh implementation from current `main`; do not import #100 recovery.

- one provisional watchdog;
- commit replaces it with one post-commit watchdog;
- default 120-second bound unless separately amended;
- finish/fail/new navigation/release/rebuild/known termination invalidates old work;
- at most one stall per navigation generation.

Classes:

- `PRE_COMMIT_NAVIGATION_STALL`;
- `POST_COMMIT_NAVIGATION_STALL`.

No reload/recovery.

### P0.5 Bounded renderer/JS round trip

Trigger only on:

- a navigation stall; or
- explicit QA incident capture.

Read only:

- `document.readyState`;
- `document.visibilityState`.

Required:

- 5-second timeout;
- physical runtime + navigation generation guard;
- late callback ignored;
- `success | failed | timeout`;
- latency;
- no recovery.

### P0.6 Manual QA incident snapshot

Add explicit QA-only action: **Capture Stuck Tab Snapshot (QA)**.

It must not navigate, reload, reset, rebuild, focus, select, clear state, or create a missing runtime.

Create one `incident_id` and capture:

#### Identity
- session ID;
- source revision/build label;
- Slot ID;
- runtime generation;
- WebView instance ID;
- latest navigation generation;
- ChatGPT document epoch when available.

Do not persist the document token.

#### Physical presentation
- active Slot matches captured Slot;
- pool WebView matches presented WebView;
- expected container/host relationship;
- WebView descendant of expected container;
- WebView/window role: source, shell/companion, fullscreen-private, none/other;
- view/host hidden facts;
- window visible/key;
- nonzero frame/bounds;
- residency;
- pending lifecycle release/protection;
- fullscreen session/restore generation.

#### Navigation
- `isLoading`;
- `estimatedProgress`;
- current phase/generation;
- sanitized origin/page class only.

#### Document/app
Run the bounded JS probe.

For supported ChatGPT documents record content-free booleans only:

- attention bridge has admitted document;
- document epoch;
- response bridge document-ready;
- generating when safely available;
- shell/composer presence;
- loading indicator present/visible;
- coarse page-error indicator.

No page text, title, prompt/response body, conversation ID, raw URL query/fragment, HTML, cookie/storage, JS error message/stack or screenshot bytes.

### P0.7 Termination/rebuild correlation

Enhance existing content-termination and rebuild events with the same runtime/navigation identity and native presentation snapshot.

Do not change current recovery policy.

## Explicitly deferred

FT-DIAG-002 does **not** authorize:

- automatic reload/recovery;
- `reloadFromOrigin` escalation;
- per-Slot reset/runtime replacement experiment;
- hard replacement on JS timeout;
- periodic health sampling;
- broad DOM/error logging;
- network request interception;
- private WebKit SPI;
- cache/cookie/site-data clearing;
- screenshots or persisted image data;
- automatic `takeSnapshot`;
- network-path monitoring unless a later evidence review requires it.

# D. Deterministic diagnosis flow

## Required identity tuple

`source_revision + build + session_id + incident_id + slot_id + runtime_generation + webview_instance_id + navigation_generation + document_epoch(if supported)`

Do not merge evidence that cannot be tied to the relevant tuple.

## Fresh incident procedure

1. Do **not** Reload/Home/restart/reset first.
2. Trigger **Capture Stuck Tab Snapshot (QA)**.
3. Preserve the incident UUID.
4. Let the bounded JS/app-health probe finish or timeout.
5. Export recent diagnostics.
6. Only afterwards may a separately authorized recovery experiment run.

## Discriminator 1 — physical presentation

If active Slot / pool runtime / presented WebView / expected container/window hierarchy disagree:

`PRESENTATION_OWNERSHIP_OR_HIERARCHY_FAILURE`

Stop before blaming navigation/network/page state.

## Discriminator 2 — known content-process termination

Matching termination events for the same runtime:

`KNOWN_WEB_CONTENT_PROCESS_TERMINATION`

Recovery result remains separate evidence.

## Discriminator 3 — navigation

No commit before bound:

`PRE_COMMIT_NAVIGATION_STALL`

Committed but not finished before bound:

`POST_COMMIT_NAVIGATION_STALL`

Finished/no active stall:

continue upward to document/app/presentation.

## Discriminator 4 — bounded JS responsiveness

Timeout:

`WEB_CONTENT_OR_JS_UNRESPONSIVE_CANDIDATE`

Immediate evaluation failure:

`WEB_CONTENT_JS_EVALUATION_FAILURE`

Success:

WebContent/JS responded at that moment; continue.

## Discriminator 5 — document/app health

Bridge/document absent or epoch inconsistent:

`DOCUMENT_BRIDGE_IDENTITY_OR_ADMISSION_FAILURE`

Responsive document with persistent app loading/error:

`PAGE_APPLICATION_STATE_CANDIDATE`

Responsive/healthy app state + correct native hierarchy + visible black/blank:

`RENDER_OR_PRESENTATION_COMPOSITOR_CANDIDATE`

This last class may justify a later privacy-safe render-surface discriminator.

## Network/resource interpretation

Responsive renderer plus navigation/app loading is compatible with network/resource trouble but does not prove it.

Use only:

`NETWORK_OR_RESOURCE_LAYER_CANDIDATE`

until a request/resource or reproducible network-correlated boundary is observed.

## Recovery interpretation

If Reload, per-Slot replacement or full restart later restores the symptom, record:

`RECOVERY_SUCCEEDED(<method>)`

Do not convert recovery into cause.

# E. Construction Gate

## Verdict

**CONSTRUCTION_GATE_READY**

The root cause remains unknown, but probe placement is now sufficiently determined. No unresolved source-architecture question remains that would materially change the first-wave observation points.

## FT-DIAG-002 acceptance criteria

1. Diagnostics do not select, navigate, reload, focus, reset, rebuild, release, or change recovery policy.
2. Launch/export identify exact source revision and bounded QA/build label.
3. Same physical WebView reuse preserves runtime identity; rebuild/recreate changes it; old identity is removed.
4. Navigation generations are monotonic per physical runtime; stale callbacks cannot complete current diagnostic state.
5. Provisional/post-commit stall classifiers are one-shot and invalidated on finish/fail/new nav/release/rebuild/termination.
6. Renderer probe has success/failure/5-second-timeout and ignores late/stale completion.
7. Manual incident capture is explicit, read-only, does not create a runtime, and returns a bounded unavailable result when no resident active runtime exists.
8. Physical hierarchy/binding facts cover Hot, Warm/Cold, normal source, fullscreen source and companion presentation without changing ownership.
9. No sensitive page/content/document-token/screenshot data is persisted.
10. No periodic sampler; new events occur only for incident/stall/failure/rebuild boundaries; otherwise add identity fields to existing events.
11. Focused tests cover identity, tickets, timeout and stale callbacks; regress existing content-process recovery, lifecycle, attention, Instant Back and fullscreen ownership.
12. Full XCTest and Debug/Release arm64 CI pass.
13. Real-Mac fresh incident capture is a later evidence gate; CI cannot claim root cause or real-incident diagnosis.

## Construction stop conditions

Stop rather than improvise if implementation would require:

- changing navigation/recovery authority;
- private WebKit API;
- screenshot/content persistence;
- weakening bridge document identity;
- changing #102;
- importing #100/#101 recovery logic;
- broad periodic sampling.
