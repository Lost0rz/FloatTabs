# FloatTabs — ChatGPT Attention Construction Plan V1

> Status: **FROZEN PLAN** — implementation has not started.
> Contract authority: `docs/product/FloatTabs_ChatGPT_Attention_Contract_V1.md`
> Contract branch: `contract/chatgpt-ready-attention-v1`
> Base main: `ad810e94549cade77ec00bd0f2aee1b170d8023c`

## 1. Delivery objective

Implement ChatGPT generation attention without changing existing Slot persistence or Hot/Warm/Cold policy semantics.

The finished V1 must provide this loop:

```text
Idle -> Generating -> Ready when completion occurs off-screen
Ready -> Idle when the actual ChatGPT WebView becomes user-visible
```

`Generating` and `Ready` are protected from FloatTabs-initiated eviction. Only `Ready` renders the favicon red dot.

## 2. Current architecture and ownership

Existing authoritative boundaries remain:

- `TabStore` / `WebAppProfile`: persisted Web App configuration and selected Slot identity.
- `WebViewPool`: ownership of live WKWebView runtimes and actual resident Slot IDs.
- `SlotLifecycleCoordinator`: Hot/Warm/Cold release timing, Warm LRU/memory-pressure handling, media protection, hidden-active grace.
- `PanelController`: real FloatTabs presentation/fullscreen state and coordination of selected WebView presentation.
- `ExternalControlZoneView`: transient Tab rail rendering.

New V1 ownership must be:

- `WebAttentionCoordinator`: sole native runtime authority for Slot attention state (`Idle`, `Generating`, `Ready`).
- `ChatGPTAttentionBridge`: per-WKWebView sensor/adapter. It reports normalized events only and owns no persisted/product state.
- `WebViewPool`: owns bridge lifetime together with its WKWebView and forwards normalized events/reset signals.
- `SlotLifecycleCoordinator`: consumes derived attention protection; it must not become a second attention state store.
- `PanelController`: remains visibility authority and performs acknowledgement routing; it must not contain ChatGPT DOM detection logic.
- `ExternalControlZoneView`: receives a transient Ready-ID projection for red-dot rendering only.

## 3. Architecture constraints

1. Do not add attention fields to `WebAppProfile`, profile JSON, backups, or preferences.
2. Do not change residency policy to Hot when generation begins.
3. Media protection and attention protection are independent OR conditions.
4. Every eviction path must re-check attention protection, including timer expiry, Warm LRU, and memory pressure.
5. Releasing/rebuilding/removing a WKWebView must invalidate its bridge and old callbacks.
6. WebContent process termination and document/runtime replacement reset old attention without synthesizing Ready.
7. A newly attached supported ChatGPT document establishes a baseline; idle baseline cannot create Ready.
8. Only supported main-frame ChatGPT documents may drive attention.
9. No prompt/response content is persisted or forwarded natively.
10. Do not build a generic website notification framework in V1.
11. Avoid expanding already-large `PanelController.swift`; state-machine and ChatGPT adapter logic belong in dedicated Web-layer files.
12. Avoid touching `WebViewFactory.swift` unless technically unavoidable. PR #59 independently modifies that file, and the attention bridge can be installed on the created WKWebView before its first load from `WebViewPool`.

## 4. Planned files

Expected new production files:

- `FloatTabs/Web/WebAttentionCoordinator.swift`
- `FloatTabs/Web/ChatGPTAttentionBridge.swift`

Expected existing production files touched across the feature:

- `FloatTabs/Web/WebViewPool.swift`
- `FloatTabs/Web/SlotLifecycleCoordinator.swift`
- `FloatTabs/Panel/PanelController.swift`
- `FloatTabs/UI/ExternalTabRail.swift`
- `FloatTabs.xcodeproj/project.pbxproj`

Expected tests:

- new focused attention/state-machine tests, preferably `FloatTabsTests/WebAttentionCoordinatorTests.swift`
- bridge/WebViewPool coverage in a focused new test file or `WebViewPoolTests.swift`
- lifecycle protection regression coverage in `WebViewPoolTests.swift`
- visibility/rail rendering coverage in focused tests or `ExternalShellTests.swift`

Do not keep adding unrelated helpers into already-large test files when a focused test file gives cleaner ownership.

## 5. Stage plan

### Stage A — Runtime state authority

Goal: establish the pure native state machine before WebKit/DOM integration.

Implement:

- `WebAttentionState`: `idle`, `generating`, `ready`.
- normalized events: generation started, generation finished, runtime reset.
- `WebAttentionCoordinator` keyed by Slot ID.
- explicit methods for event handling, acknowledgement, reset, Ready projection, and protection query.
- completion decision receives authoritative current visibility from caller.

Required semantics:

- Idle + started -> Generating.
- Generating + finished + visible -> Idle.
- Generating + finished + not visible -> Ready.
- Ready + visible acknowledgement -> Idle.
- Ready + started -> Generating.
- runtime reset -> Idle.
- idle baseline/reset must never synthesize Ready.

Non-scope:

- no WKUserScript;
- no WebViewPool wiring;
- no lifecycle changes;
- no UI changes.

Gate: independent audit PASS before Stage B.

### Stage B — ChatGPT bridge and WKWebView lifetime

Goal: observe current ChatGPT generation state and feed only normalized events into Stage A.

Implement:

- per-WKWebView `ChatGPTAttentionBridge`;
- supported host validation for `chatgpt.com` subdomains and practical legacy `chat.openai.com`;
- main-frame-only script/message path;
- named `WKContentWorld`;
- event-driven `MutationObserver` with debounce/coalescing;
- semantic detection using stable controls/roles/aria/data attributes where possible;
- per-document identity/baseline so top-level document replacement resets stale state;
- bridge install in `WebViewPool` before first load;
- bridge invalidation on release/rebuild/remove;
- process-termination reset signal before existing recovery policy proceeds.

Native message payload must contain status/lifecycle metadata only, never prompt/response bodies.

Non-scope:

- no lifecycle eviction changes;
- no red dot;
- no generic site adapters.

Gate: independent audit PASS before Stage C.

### Stage C — Residency protection integration

Goal: make Stage 5E honor attention protection without changing residency policy.

Implement:

- attention protection query derived from `WebAttentionCoordinator` state;
- protect Generating and Ready in Cold expiry;
- protect Generating and Ready in Warm TTL;
- exclude protected Slots from Warm LRU;
- exclude protected Slots from warning/critical memory-pressure proactive eviction;
- retain independent media protection behavior;
- when protection ends because of runtime reset while already inactive, restart normal Warm/Cold handling from a fresh lifecycle boundary.

Do not duplicate `Idle/Generating/Ready` inside `SlotLifecycleCoordinator`.

Gate: independent audit PASS before Stage D.

### Stage D — Real visibility and acknowledgement

Goal: acknowledge Ready only when the actual ChatGPT WebView is presented.

Implement a narrow `PanelController` visibility mapping that covers:

- normal visible Web source;
- WebKit-owned fullscreen source during locked fullscreen session;
- visible fullscreen companion.

Rules:

- selected + hidden is not visible;
- showing a Ready selected normal Slot acknowledges when presented;
- selecting a Ready Slot in a visible presentation acknowledges when presented;
- fullscreen source completion while presented does not latch Ready;
- companion presentation can acknowledge its own Ready state;
- no dwell/scroll/occlusion heuristics.

Gate: independent audit PASS before Stage E.

### Stage E — Ready indicator

Goal: render Ready independently from residency color.

Implement:

- transient `readySlotIDs` projection in `ExternalControlZoneView`;
- `ExternalWebAppTabView` Ready state;
- small red dot anchored to favicon top-right;
- no trailing-row badge that moves with Dock magnification;
- full-color/grayscale residency semantics unchanged;
- Ready updates must not write through `TabStore` persistence.

Gate: independent audit PASS before Stage F.

### Stage F — Cross-feature closure

Goal: validate all stages together and remove temporary/duplicated logic.

Required coverage:

- Warm generating survives TTL/LRU and becomes Ready off-screen.
- Cold generating survives 30-second grace and becomes Ready off-screen.
- Ready survives time/memory-pressure proactive eviction attempts.
- viewed Ready clears and later deactivation starts fresh Warm/Cold lifecycle.
- Hot remains resident before/after acknowledgement.
- selected hidden completion -> Ready; show -> acknowledge.
- visible completion -> no Ready.
- fullscreen-source completion -> no false Ready.
- bridge/runtime replacement -> no stale Ready/protection.
- media + attention protection coexist without one clearing the other.
- relaunch has no stale Ready persistence.
- non-ChatGPT Slots remain unaffected.

Gate: FEATURE IMPLEMENTED only after independent Stage F audit PASS.

## 6. Per-stage execution loop

Every stage follows:

```text
pre-construction repository audit
-> exact AI Assistant construction command
-> AI construction result
-> independent real diff/code/test audit
-> precise fix command if needed
-> repeat until stage audit PASS
```

Before each stage verify branch/HEAD/main/PR/Contract again. Do not trust prior summaries if repository state moved.

## 7. Final audit gate

Feature implementation is not completion.

After Stage F passes, run full affected-architecture audits for:

- stale/dead/duplicate code;
- second Source of Truth;
- Contract/business conflict;
- races, stale callbacks, retain cycles, resource leaks;
- timer/lifecycle holes;
- WKWebView rebuild/process termination problems;
- oversized/God Object growth and misplaced responsibilities;
- test gaps and tests that only assert implementation details.

Requirement: **TWO CONSECUTIVE CLEAN ROUNDS**.

Any material finding resets the clean-round count after repair.

## 8. Real validation gate

Only after two consecutive clean rounds provide the real-Mac acceptance checklist.

Real validation must include at least:

- two or more ChatGPT Slots generating independently;
- Warm and Cold off-screen completion;
- hidden FloatTabs completion;
- completion while actively viewing;
- returning to Ready Slot clears dot;
- normal post-ack residency behavior;
- fullscreen ChatGPT behavior;
- no prompt/response content exposed by FloatTabs UI/log/storage;
- ordinary non-ChatGPT Web Apps unaffected.

Failure returns to diagnosis/fix/audit. No merge on failed real validation.

## 9. Merge and Release gate

After real validation PASS:

1. fetch latest main;
2. audit whether main moved;
3. final PR/commit/diff audit;
4. deliberately integrate independent PR #59 if still desired and compatible;
5. merge approved feature work to main;
6. test/build merged main;
7. follow current FloatTabs version/build and Release conventions;
8. build official artifact from merged main;
9. publish latest Release;
10. verify tag/version/build/artifact identity.

Never publish the official Release directly from an unmerged feature branch.

## 10. Current known branch interaction

PR #59 (`fix/chatgpt-first-mouse`) is independent, Draft, and unmerged. It modifies `WebViewFactory.swift` and its tests.

This attention plan should avoid `WebViewFactory.swift` unless required. If both features are later merged in one release, perform a final combined diff audit instead of silently stacking branches during construction.

PR #60 remains the docs/Contract authority until the implementation branch is created from its frozen HEAD or the Contract is deliberately merged first.
