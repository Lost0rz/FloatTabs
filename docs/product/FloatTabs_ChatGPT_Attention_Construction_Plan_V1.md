# FloatTabs — ChatGPT Attention Construction Plan V1

> Status: **ACTIVE FROZEN DELIVERY PLAN**
> Business Contract: `docs/product/FloatTabs_ChatGPT_Attention_Contract_V1.md` — FROZEN
> Base main: `ad810e94549cade77ec00bd0f2aee1b170d8023c`
> Stage A implementation: `83e98ec8f4763b792148a5a6c492b9befe087205` — independently audited PASS
> Revision: 2026-08-22 — final cross-feature audit corrected provisional observation timing. Business semantics unchanged.

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

Stage A established that `generationFinished` needs authoritative `userVisible` as an input. Therefore visibility/state routing must exist before residency protection consumes the state.

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
16. `WKUserScript` installation must be configured **before WKWebView creation** so `.atDocumentStart` is reliable. Use a narrow pre-creation `WKUserContentController` configuration seam in `WebViewFactory.makeWebView`; do not duplicate Factory configuration in `WebViewPool`.
17. PR #59 also modifies `WebViewFactory.swift`, but only the `FloatTabsWebView.acceptsFirstMouse` area. Keep Stage B's Factory change confined to the creation/configuration area and perform a final combined-file audit before merge.

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

No WebKit/lifecycle/UI wiring exists yet.

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

Create a conservative ChatGPT sensor that produces only normalized observations:

```text
generationStarted
generationFinished
runtimeReset
```

Stage B must **not** mutate `WebAttentionCoordinator`; authoritative real visibility is wired in Stage C.

### Required files / ownership

Expected production changes:

- new `FloatTabs/Web/ChatGPTAttentionBridge.swift`;
- `FloatTabs/Web/WebViewPool.swift`;
- `FloatTabs/Web/SlotNavigationObserver.swift`;
- narrowly `FloatTabs/Web/WebViewFactory.swift` for a pre-creation user-content configuration seam;
- `FloatTabs.xcodeproj/project.pbxproj`.

Expected focused tests:

- new `FloatTabsTests/ChatGPTAttentionBridgeTests.swift`;
- only add to large existing test files when a focused new test cannot cover the integration boundary.

`WebViewPool` owns one bridge per live WKWebView/Slot:

```text
slotID -> WKWebView
       -> SlotNavigationObserver
       -> PopupCoordinator
       -> ChatGPTAttentionBridge
```

Expose one transient observation callback from `WebViewPool` for Stage C. It is not state and must not be persisted.

### Shared ChatGPT host policy

Stage B needs the same ChatGPT host family already used by `SiteCompatibilityPolicy`. Do not create two drifting host lists.

Use one small shared provider predicate (it may live in the bridge/provider file) and reuse it from both attention validation and existing ChatGPT compatibility logic without changing existing rendering behavior.

Accept:

- `chatgpt.com`;
- subdomains of `chatgpt.com`;
- legacy `chat.openai.com` where practical.

Reject lookalikes such as:

- `evilchatgpt.com`;
- `chatgpt.com.evil.example`;
- unrelated `openai.com` pages.

### WebKit pre-creation installation

`WebViewFactory` currently creates `WKWebViewConfiguration` internally. Add only an optional configuration seam, conceptually:

```text
makeWebView(renderingProfile:, configureUserContentController: ... = nil)
```

Factory remains authoritative for:

- persistent website data store;
- fullscreen preference;
- browser identity;
- website mode;
- existing hidden-scrollbar script;
- actual `FloatTabsWebView` creation.

The optional callback receives the Factory-owned `WKUserContentController` **before** `FloatTabsWebView` is constructed.

Then `WebViewPool.createWebView()` uses this order:

```text
create bridge object
-> WebViewFactory.makeWebView(... configureUserContentController: bridge.install)
-> attach returned WKWebView identity to bridge
-> install SlotNavigationObserver / PopupCoordinator ownership
-> store bridge in pool
-> first load(...)
```

Do not recreate a separate `WKWebViewConfiguration` in `WebViewPool`.

Use:

- named `WKContentWorld`;
- main-frame-only `WKUserScript` at document start;
- script message handler in the same content world;
- individual handler removal for that name/content world on invalidation.

Do **not** call `removeAllUserScripts()` because it would remove unrelated Factory scripts.

### Generation detector

Use conservative exact controls.

Primary current signal:

- `[data-testid="stop-button"]`

Narrow compatibility fallback may include:

- `[data-testid="fruitjuice-stop-button"]`

Do not use broad `aria-label*="Stop"`, broad class scans, response text, page text, or send-button-disabled state as primary detection.

Only a rendered/current control should count as generating.

Use `MutationObserver` or equivalent event-driven observation with a short trailing debounce/coalescing window. Native output is emitted only when normalized generation state changes.

### Baseline semantics

Each supported document establishes a baseline:

- first observed idle => baseline only, no finish;
- first observed generating => `generationStarted` is allowed;
- subsequent generating -> idle => one `generationFinished`;
- duplicate same-state observations => no native event.

The bridge must de-duplicate defensively even if injected JS is noisy.

### Message validation / privacy

Native acceptance must validate:

- expected WKWebView identity;
- main-frame source;
- supported source security origin/host;
- protocol/version;
- current accepted document token;
- valid minimal payload types.

Do not validate only against `webView.url`, because stale old-document messages can race navigation.

Payload may contain only minimal metadata such as:

- protocol version;
- opaque document token;
- baseline/state kind;
- generating boolean.

Never include prompt text, response text, conversation HTML/body, or user content.

### Document identity / BFCache / stale-event protection

Every active document/runtime epoch carries an opaque document token created by injected JS.

Requirements:

- superseded document messages cannot affect the current document;
- rebuilt/released WKWebView callbacks cannot affect the Slot;
- committed replacement clears the accepted epoch and requires a current-document baseline;
- BFCache/history restoration must re-establish a baseline, e.g. via `pageshow`, because a restored document may not receive a fresh document-start injection;
- SPA route changes that do not replace the top-level document do not automatically reset the bridge.

V1 follows generation state represented by the Slot's **current ChatGPT document**. It does not attempt to track multiple server-side conversation jobs no longer represented by that current DOM inside one Slot.

### Navigation lifecycle

Reuse `SlotNavigationObserver`; do not create a second `WKNavigationDelegate`.

Forward the minimum top-level lifecycle events to the bridge.

**didStartProvisionalNavigation**

- do not reset the old runtime before commit;
- continue accepting and emitting validated observations from the current
  accepted old-document epoch;
- document identity does not change until commit.

**didCommit**

- document replacement is real;
- emit/forward `runtimeReset` for the old runtime;
- clear accepted document identity and accept/await a fresh baseline.

**didFailProvisionalNavigation**

- do not reset or replay attention observations;
- the still-present old document simply remains the current epoch;
- preserve existing one-shot HTTP fallback semantics;
- if fallback starts another load, that new load gets its own provisional-start boundary.

**didFail after commit**

- do not resurrect pre-commit state.

**WebContent process termination**

- emit/forward `runtimeReset` before current reload/deferred-reload recovery;
- clear current document identity;
- keep the bridge installation usable for the recovered document unless the WKWebView itself is replaced.

### Release / rebuild / remove

Before dropping/replacing a WKWebView:

- invalidate its bridge;
- remove its specific message handler;
- reject queued callbacks after invalidation;
- forward one reset boundary where applicable;
- then drop bridge/WKWebView ownership.

Rendering-profile rebuild must invalidate the old bridge and create a new bridge for the replacement WebView while preserving the existing resident-set semantics.

### Stage B non-scope

Do not:

- apply observations to `WebAttentionCoordinator`;
- decide `userVisible`;
- change Hot/Warm/Cold;
- add attention eviction protection;
- acknowledge Ready;
- render the red dot;
- modify persisted models/backups/preferences;
- alter first-mouse semantics from PR #59;
- touch compatibility branches.

### Stage B test gate

Focused tests must cover at least:

1. supported host acceptance and lookalike rejection;
2. existing ChatGPT compatibility identity behavior remains unchanged after shared-host refactor;
3. script is document-start + main-frame-only + named content world;
4. another WKWebView/source frame is rejected;
5. idle baseline emits no finish;
6. generating baseline emits one start;
7. duplicate generating emits nothing extra;
8. generating -> idle emits one finish;
9. duplicate idle emits nothing extra;
10. unsupported host cannot emit observations;
11. provisional start leaves the current old-document observation stream
    emitting without reset;
12. provisional failure emits no reset and does not replay observations;
13. committed replacement emits reset and requires current epoch;
14. stale old-document message after commit is rejected;
15. BFCache/pageshow baseline behavior is represented/tested at the bridge reducer/lifecycle level;
16. WebContent termination emits reset before existing recovery action;
17. release invalidates bridge/stale callbacks;
18. rendering-profile rebuild invalidates old bridge and creates new bridge;
19. one Slot bridge removal does not disturb another;
20. bridge configuration is installed before first load;
21. bridge invalidation removes only its own message handler, not all user scripts;
22. existing HTTP fallback/content-process tests remain green;
23. full existing test suite passes;
24. `git diff --check` passes.

Gate: independent Stage B audit PASS before Stage C.

## 7. Stage C — Real Visibility + State Routing/Acknowledgement

### Goal

Connect Stage B observations to the Stage A authority using actual presentation visibility.

Recommended composition:

- application composition creates/injects one `WebAttentionCoordinator`;
- `PanelController` receives it and owns only routing/presentation decisions;
- `WebViewPool` remains observation source;
- no second attention map is added anywhere.

Routing:

```text
Bridge observation
-> WebViewPool callback
-> PanelController actual visibility
-> WebAttentionCoordinator.apply(...)
```

- `generationStarted` -> `.generationStarted`;
- `generationFinished` -> compute actual visibility, then `.generationFinished(userVisible:)`;
- `runtimeReset` -> `.runtimeReset`.

Actual visibility must distinguish:

1. normal active WebView actually presented in visible source host;
2. WebKit-owned fullscreen source;
3. visible fullscreen companion.

Inactive Hot WebViews can remain attached/resident and must not count as visible merely because their window exists.

When a Ready Slot becomes actually presented, acknowledge `Ready -> Idle`. Selected-but-hidden never acknowledges.

Gate: independent Stage C audit PASS before Stage D.

## 8. Stage D — Residency Protection

Extend accepted Stage 5E rules with:

```text
proactive eviction allowed only when
!mediaProtected && !attentionProtected
```

`attentionProtected` is queried from the one coordinator; do not copy state into lifecycle storage.

Protect Generating/Ready from:

- Cold expiry;
- Warm TTL;
- Warm LRU;
- warning memory-pressure Warm eviction;
- critical memory-pressure Warm eviction;
- final proactive release path.

Attention protection does not prevent logical deactivation/detachment; it only prevents FloatTabs-initiated runtime eviction.

If attention protection ends because of reset/failure while a Warm/Cold Slot is already inactive, restart normal policy timing from a fresh lifecycle boundary.

Media protection remains independent; removing one protection cannot bypass the other.

Gate: independent Stage D audit PASS before Stage E.

## 9. Stage E — Ready Red Dot

Implement:

- transient `readySlotIDs` projection into `ExternalControlZoneView`;
- Ready state on `ExternalWebAppTabView`;
- small red dot anchored to favicon top-right;
- no trailing-edge badge tied to Dock width animation;
- existing full-color/grayscale residency semantics unchanged;
- no persistence/TabStore write.

Gate: independent Stage E audit PASS before Stage F.

## 10. Stage F — Cross-feature Closure

Required combined coverage:

- Warm generating survives TTL/LRU and becomes Ready off-screen;
- Cold generating survives grace and becomes Ready off-screen;
- Ready survives proactive memory-pressure eviction attempts;
- viewed Ready clears; later deactivation starts fresh policy lifecycle;
- Hot remains Hot;
- selected hidden completion -> Ready; show -> acknowledgement;
- visible completion -> Idle/no dot;
- fullscreen source completion -> no false Ready;
- companion completion while presented -> no false Ready;
- committed replacement -> reset/no stale Ready;
- failed provisional navigation preserves valid old runtime state and does not
  defer or replay same-document observations;
- process termination -> reset then normal recovery;
- release/rebuild -> no stale bridge callbacks;
- media + attention protection coexist independently;
- relaunch has no persisted Ready;
- non-ChatGPT sites unaffected;
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

Before every stage verify branch / HEAD / origin/main / Contract / active plan / open PRs / relevant code / tests / worktree.

## 12. Final audit gate

After Stage F, audit the whole affected architecture for:

- stale/dead/duplicate code;
- second Source of Truth;
- Contract/business conflict;
- stale callbacks / races / retain cycles / resource leaks;
- timer/lifecycle holes;
- navigation/BFCache/rebuild/process-termination holes;
- oversized/God Object growth and misplaced responsibilities;
- test gaps / implementation-detail-only tests.

Requirement: **TWO CONSECUTIVE CLEAN ROUNDS**.

Any material finding resets the clean count after repair.

## 13. Real validation gate

After two clean rounds, real-Mac validation must cover at least:

- two or more independent ChatGPT Slots;
- Warm and Cold off-screen completion;
- hidden FloatTabs completion;
- completion while actively viewing;
- Ready dot clears on actual return;
- post-ack residency behavior;
- element fullscreen source;
- fullscreen companion;
- non-ChatGPT sites unaffected;
- no conversation content written/logged by the feature.

Failure => diagnose/fix/audit again. No merge.

## 14. Merge and Release gate

After real validation PASS:

1. fetch latest `main`;
2. audit main movement;
3. audit final PR/commit/diff;
4. deliberately integrate PR #59 only if still desired/compatible;
5. merge approved feature to main;
6. test/build merged main;
7. follow version/build conventions;
8. build official artifact from merged main;
9. publish Release;
10. verify tag/version/build/artifact.

Never publish the official Release directly from an unmerged feature branch.

## 15. Current branch interaction

- PR #59: `fix/chatgpt-first-mouse`, Draft/unmerged. Its `WebViewFactory.swift` patch is confined to `FloatTabsWebView.acceptsFirstMouse`; Stage B Factory edits must remain in the creation/configuration area.
- PR #60: docs/Contract authority, Draft/unmerged.
- PR #40: old Draft branch is materially diverged from current main and also touches `WebViewPool`/`PanelController`; do not stack or merge it into this feature.
- Implementation branch: `feature/chatgpt-attention-v1`.
