# FloatTabs — ChatGPT Attention Construction Plan V1

> Status: **ACTIVE FROZEN DELIVERY PLAN**
> Business Contract: `docs/product/FloatTabs_ChatGPT_Attention_Contract_V1.md` — FROZEN
> Base main: `ad810e94549cade77ec00bd0f2aee1b170d8023c`
> Stage A implementation: `83e98ec8f4763b792148a5a6c492b9befe087205` — independently audited PASS
> Revision: 2026-08-21 — technical stage order corrected after Stage A audit. Business semantics unchanged.

## 1. Delivery objective

Implement ChatGPT generation attention without changing persisted Slot semantics or Hot/Warm/Cold policy semantics.

Finished V1:

```text
Idle -> Generating
Generating -> Idle   when completion occurs while actually user-visible
Generating -> Ready  when completion occurs while not user-visible
Ready -> Idle        when the actual WebView becomes user-visible
```

`Generating` and `Ready` are protected from FloatTabs-initiated eviction. Only `Ready` renders the favicon red dot.

## 2. Authority and ownership

Existing authorities remain:

- `TabStore` / `WebAppProfile`: persisted Web App configuration and selected Slot identity.
- `WebViewPool`: live WKWebView ownership and resident Slot IDs.
- `SlotLifecycleCoordinator`: Hot/Warm/Cold lifecycle, Warm LRU, memory pressure, media protection, hidden-active grace.
- `PanelController`: actual presentation/fullscreen coordination.
- `ExternalControlZoneView`: transient rail rendering.

Attention V1 ownership:

- `WebAttentionCoordinator`: **sole native runtime authority** for Slot `Idle / Generating / Ready`.
- `ChatGPTAttentionBridge`: per-WKWebView sensor only; emits normalized observations and owns no business state.
- `WebViewPool`: owns bridge lifetime with WKWebView and forwards normalized observations/reset signals.
- `PanelController`: authoritative real-visibility mapping and state-routing/acknowledgement boundary.
- `SlotLifecycleCoordinator`: consumes a derived attention-protection query; never stores duplicate attention state.
- Tab rail: receives a transient Ready-ID projection only.

No attention state may be persisted in `WebAppProfile`, profile JSON, backups, preferences, or current URL.

## 3. Corrected stage order

The original plan placed residency protection before real visibility routing. Stage A proved that `generationFinished` requires authoritative `userVisible` as an input, so that order was technically invalid.

Correct order:

```text
Stage A  Runtime State Authority                     PASS
Stage B  ChatGPT Bridge + WKWebView/Document Lifetime
Stage C  Real Visibility + State Routing/Acknowledgement
Stage D  Residency Protection
Stage E  Ready Red Dot
Stage F  Cross-feature Closure
Final Audit Round 1
Final Audit Round 2
Real User Validation
Merge main
Release
```

This revision changes construction order only. It does not change the frozen business Contract.

## 4. Global architecture constraints

1. Never add attention fields to persisted Slot/profile state.
2. Never convert a generating/Ready Slot to Hot as an implementation shortcut.
3. `mediaProtected || attentionProtected` must independently block proactive eviction.
4. `PanelController` is the only real-presentation authority; `activeTabID` alone is never visibility proof.
5. `WebAttentionCoordinator` is the only `Idle/Generating/Ready` authority.
6. Bridge events are observations, not state.
7. Bridge lifetime follows WKWebView lifetime.
8. New committed top-level documents, unsupported hosts, runtime replacement, release/rebuild, and WebContent termination reset the old attention runtime without synthesizing completion.
9. A failed provisional navigation must not prematurely discard the still-present old document's attention runtime.
10. Only supported main-frame ChatGPT documents may drive observations.
11. Reject stale messages from superseded documents/WKWebViews.
12. No prompt/response text may be intentionally copied into native payloads, logs, persistence, or analytics.
13. Observation must be event-driven and debounced/coalesced; no token-by-token native messages.
14. V1 does not build a generic website notification framework.
15. Avoid growing the already-large `PanelController.swift`; provider logic and state-machine logic remain in dedicated Web-layer types.
16. Avoid touching `WebViewFactory.swift`. PR #59 independently modifies it; Stage B can install the bridge after Factory creation and before first `load` in `WebViewPool`.

## 5. Stage A — Runtime State Authority — CLOSED

Implemented and independently audited at:

`83e98ec8f4763b792148a5a6c492b9befe087205`

Authority:

```text
private var states: [UUID: WebAttentionState]
```

Derived projections only:

- `state(for:)`
- `isAttentionProtected(_:)`
- `readySlotIDs`

Required Stage A semantics are covered by focused tests. No WebKit/lifecycle/UI wiring exists yet.

Stage A status:

```text
Business Contract: PASS
Contract Alignment: PASS
Source of Truth: PASS
Persistence Boundary: PASS
Implementation: PASS
Tests: PASS
Stage A: CLOSED
```

## 6. Stage B — ChatGPT Bridge + WKWebView/Document Lifetime

### Goal

Create a conservative ChatGPT sensor that produces only normalized runtime observations:

```text
generationStarted
generationFinished
runtimeReset
```

Stage B must **not** mutate `WebAttentionCoordinator` because authoritative real visibility is not wired until Stage C.

### Required architecture

Create a focused type, preferably:

`FloatTabs/Web/ChatGPTAttentionBridge.swift`

`WebViewPool` owns one bridge per live WKWebView/Slot, e.g.:

```text
slotID -> WKWebView
       -> SlotNavigationObserver
       -> PopupCoordinator
       -> ChatGPTAttentionBridge
```

Expose one transient observation callback from `WebViewPool`, for later Stage C routing. It is not state and must not be persisted.

### WebKit installation

Install the bridge in `WebViewPool.createWebView()`:

```text
WebViewFactory.makeWebView(...)
-> install ChatGPTAttentionBridge
-> install navigation/popup ownership
-> first load(...)
```

Do not modify `WebViewFactory.swift`.

Use:

- named `WKContentWorld`;
- main-frame-only `WKUserScript`;
- script message handler in the same content world;
- explicit handler removal/invalidation on WKWebView release/rebuild.

### Supported hosts

Native validation must accept only:

- `chatgpt.com`;
- subdomains of `chatgpt.com`;
- legacy `chat.openai.com` where practical.

Reject lookalikes such as:

- `evilchatgpt.com`;
- `chatgpt.com.evil.example`;
- unrelated `openai.com` pages.

Validate the source frame/message security origin, not only `webView.url`, because stale messages may arrive during navigation.

### Generation detector

Prefer precise stable generation controls.

Initial V1 detector should be conservative. Current known exact selectors include:

- `[data-testid="stop-button"]`
- `[data-testid="fruitjuice-stop-button"]` as a narrow compatibility fallback if present.

Do not use broad selectors such as `aria-label*="Stop"`, generic disabled-send-button logic, page text, response text, or broad class-name scans as the primary V1 signal.

Only a rendered/current generation control should count as generating.

### Baseline semantics

Each supported document establishes a baseline:

- first observed idle => baseline only, **no** `generationFinished`;
- first observed generating => normalized `generationStarted` is allowed;
- subsequent generating -> idle => `generationFinished`;
- duplicate same-state observations => no native event.

The bridge must defensively de-duplicate even if DOM mutations are noisy.

### Document identity and stale-event protection

Every active document/runtime epoch must carry an opaque document token generated inside the injected script.

Requirements:

- old document messages cannot affect the current document;
- old WKWebView callbacks cannot affect a rebuilt/released Slot;
- after a committed replacement, only the current document epoch may be accepted;
- BFCache/history restoration must re-establish a current baseline (for example through `pageshow`) rather than leaving native state permanently waiting for an initial script injection that may not rerun;
- SPA route changes that do not replace the top-level document do not automatically reset the bridge.

V1 follows the generation state represented by the Slot's current ChatGPT document. It does not attempt to track multiple server-side conversations/jobs that are no longer represented by the current DOM inside one Slot.

### Navigation lifecycle

Reuse `SlotNavigationObserver`; do not create another `WKNavigationDelegate`.

Required behavior:

**didStartProvisionalNavigation**
- suspend acceptance of old-document observations during the provisional transition;
- do not yet emit `runtimeReset`, because the old document may remain if navigation fails.

**didCommit**
- the top-level document has actually been replaced;
- emit/forward `runtimeReset` for the old runtime;
- clear accepted document identity and await/accept a fresh current-document baseline.

**didFailProvisionalNavigation**
- resume the still-present old document/runtime without emitting a false reset;
- existing HTTP fallback behavior remains authoritative and must continue unchanged.

**didFail after commit**
- do not resurrect the pre-commit document state.

**WebContent process termination**
- emit/forward `runtimeReset` before existing reload/deferred-reload recovery proceeds;
- clear old document identity;
- keep the bridge infrastructure usable for the recovered document unless the WKWebView itself is replaced.

### Release/rebuild/remove

Before dropping/replacing a WKWebView:

- invalidate its bridge;
- remove its script message handler from the named content world;
- prevent queued/stale callbacks from emitting after invalidation;
- forward one runtime reset boundary where applicable;
- then drop the bridge/WKWebView ownership.

Do not call `removeAllUserScripts()` because it would also destroy unrelated existing scripts such as scrollbar policy.

### Performance/privacy

Use `MutationObserver` or equivalent event-driven observation with a short trailing debounce/coalescing window.

Native payload may contain only minimal metadata such as:

- protocol/version;
- opaque document token;
- generating boolean / normalized status.

Do not include:

- prompt text;
- response text;
- conversation body;
- DOM HTML;
- message contents.

### Stage B non-scope

Do not:

- apply events to `WebAttentionCoordinator`;
- decide `userVisible`;
- change Hot/Warm/Cold;
- add attention eviction protection;
- acknowledge Ready;
- render the red dot;
- modify persisted models;
- modify `WebViewFactory.swift`;
- merge PR #59;
- touch compatibility branches.

### Stage B test gate

Focused tests must cover at least:

1. exact supported-host acceptance and lookalike rejection;
2. main-frame-only acceptance;
3. message originating from another WKWebView is rejected;
4. idle baseline emits no finish;
5. generating baseline emits one start;
6. duplicate generating observation emits nothing extra;
7. generating -> idle emits one finish;
8. duplicate idle emits nothing extra;
9. unsupported-host payload cannot emit state;
10. provisional navigation suspends old observations without reset;
11. provisional failure resumes old document without reset;
12. committed replacement emits reset and requires a fresh document epoch;
13. stale old-document messages after commit are rejected;
14. BFCache/pageshow baseline path is represented/tested at the bridge state-machine level;
15. WebContent termination emits reset before recovery behavior;
16. release invalidates bridge and stale callbacks;
17. rendering-profile rebuild invalidates old bridge and creates a new bridge;
18. removing one Slot does not disturb another bridge;
19. bridge installation occurs before the initial load path;
20. no persistence/model files change;
21. existing HTTP fallback/content-process tests still pass;
22. full existing test suite passes.

Gate: independent Stage B audit PASS before Stage C.

## 7. Stage C — Real Visibility + State Routing/Acknowledgement

### Goal

Connect Stage B observations to the Stage A authority using **actual presentation visibility**.

Recommended composition:

- application composition creates/injects one `WebAttentionCoordinator`;
- `PanelController` receives the coordinator and owns only routing/presentation decisions;
- `WebViewPool` remains observation source;
- no second attention map is added anywhere.

Routing:

```text
Bridge observation
-> WebViewPool callback
-> PanelController real visibility decision
-> WebAttentionCoordinator.apply(...)
```

For `generationStarted`:
- apply `.generationStarted`.

For `generationFinished`:
- determine actual Slot visibility at that exact routing boundary;
- apply `.generationFinished(userVisible: true/false)`.

For `runtimeReset`:
- apply `.runtimeReset` without synthesizing completion.

### Real visibility rules

A Slot counts as visible only when its actual WKWebView is currently presented in one of:

1. normal visible source presentation;
2. WebKit-owned element-fullscreen source;
3. visible fullscreen companion.

Do not use `activeTabID` alone.

Normal inactive Hot WebViews may remain attached/resident and must not be misclassified as visible merely because their window is visible.

### Ready acknowledgement

When a Ready Slot is actually presented:

- acknowledge `Ready -> Idle`;
- selected-but-hidden does not acknowledge;
- showing a selected Ready Slot acknowledges only once its WebView is actually presented;
- fullscreen source and companion use the same actual-presentation rule.

No dwell, scroll, occlusion, or read-proof heuristics in V1.

Gate: independent Stage C audit PASS before Stage D.

## 8. Stage D — Residency Protection

### Goal

Extend accepted Stage 5E eviction rules with the derived attention protection condition:

```text
protected = mediaProtected || attentionProtected
```

`attentionProtected` is queried from the one `WebAttentionCoordinator`; do not copy its state into lifecycle storage.

Must protect Generating/Ready from:

- Cold expiry;
- Warm TTL;
- Warm LRU;
- warning memory-pressure proactive Warm eviction;
- critical memory-pressure proactive Warm eviction;
- any final proactive-release path.

Attention protection does not prevent normal logical deactivation/detachment; it only prevents FloatTabs-initiated runtime eviction.

When attention protection ends while a Warm/Cold Slot is already inactive because of runtime reset/failure, restart normal lifecycle timing from a fresh boundary so a skipped old timer cannot leave the Slot permanently resident.

Media protection remains independent; removing attention protection must not accidentally make a still-media-protected Slot evictable.

Gate: independent Stage D audit PASS before Stage E.

## 9. Stage E — Ready Red Dot

Render only `Ready` as a transient favicon overlay.

Implement:

- transient `readySlotIDs` projection into `ExternalControlZoneView`;
- Ready state on `ExternalWebAppTabView`;
- small red dot anchored to favicon top-right;
- no trailing-edge badge tied to Dock width animation;
- residency color semantics remain unchanged;
- no persistence or TabStore writes.

Gate: independent Stage E audit PASS before Stage F.

## 10. Stage F — Cross-feature Closure

Required combined coverage:

- Warm generating survives TTL/LRU and becomes Ready off-screen;
- Cold generating survives Cold grace and becomes Ready off-screen;
- Ready survives proactive memory-pressure eviction attempts;
- viewed Ready clears; later deactivation starts fresh policy lifecycle;
- Hot remains Hot;
- selected hidden completion -> Ready; show -> acknowledgement;
- visible completion -> Idle/no dot;
- fullscreen source completion -> no false Ready;
- visible companion completion -> no false Ready;
- committed document replacement -> reset/no stale Ready;
- failed provisional navigation does not destroy valid old runtime state;
- process termination -> reset then normal recovery;
- release/rebuild -> no stale bridge callbacks;
- media + attention protection coexist independently;
- relaunch has no persisted Ready;
- non-ChatGPT sites remain unaffected;
- PR #59 behavior remains isolated.

Gate: FEATURE IMPLEMENTED only after independent Stage F audit PASS.

## 11. Per-stage execution loop

Every stage:

```text
pre-construction repository audit
-> exact AI Assistant construction command
-> implementation
-> independent actual diff/source/test audit
-> precise repair command if needed
-> repeat until PASS
```

Before every stage verify:

- branch / HEAD / origin/main;
- Contract and active Construction Plan;
- open PRs;
- actual touched code;
- tests;
- worktree cleanliness.

## 12. Final audit gate

After Stage F, run full affected-architecture audits for:

- stale/dead/duplicate code;
- second Source of Truth;
- Contract/business conflicts;
- stale callbacks / races / retain cycles / resource leaks;
- timer/lifecycle holes;
- navigation/BFCache/rebuild/process-termination holes;
- oversized/God Object growth and misplaced responsibilities;
- test gaps or implementation-detail-only tests.

Requirement: **TWO CONSECUTIVE CLEAN ROUNDS**.

Any material finding resets the clean-round count after repair.

## 13. Real validation gate

Only after two consecutive clean rounds provide real-Mac validation.

At minimum validate:

- two or more independent ChatGPT Slots;
- Warm and Cold off-screen generation completion;
- hidden FloatTabs completion;
- completion while actively viewing;
- Ready dot clears on actual return;
- post-ack normal residency behavior;
- element fullscreen source;
- fullscreen companion;
- non-ChatGPT sites unaffected;
- no conversation content written/logged by the feature.

Failure => diagnose/fix/audit again. No merge.

## 14. Merge and Release gate

After real validation PASS:

1. fetch latest `main`;
2. audit whether main moved;
3. audit final PR/commit/diff;
4. deliberately integrate independent PR #59 only if still desired and compatible;
5. merge approved feature work to main;
6. test/build merged main;
7. follow current version/build conventions;
8. build official artifact from merged main;
9. publish latest Release;
10. verify tag/version/build/artifact.

Never publish the official Release directly from an unmerged feature branch.

## 15. Current branch interaction

- PR #59: `fix/chatgpt-first-mouse`, Draft/unmerged; modifies `WebViewFactory.swift` and `WebViewFactoryTests.swift` only.
- PR #60: docs/Contract authority, Draft/unmerged.
- Implementation branch: `feature/chatgpt-attention-v1`.

Stage B must remain independent from #59 and should not touch compatibility branches.
