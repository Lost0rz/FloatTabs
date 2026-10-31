# FloatTabs Runtime Lifecycle — Phase 1 Safe Hibernate + Restore Plan V1

**Program:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Phase:** `1 — Safe Hibernate + Restore`  
**Status:** `ACCEPTED / FROZEN IMPLEMENTATION PLAN`  
**Audit baseline:** `main @ 1ba0ec7fe70c3d8a6fd42d586dcc813ed87d9088`  
**Product mutation:** authorized only after this plan/control reconciliation merges  

This document is the concrete Phase 1 implementation contract under the parent [`FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md`](FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md). It does not authorize Phase 2+ semantics.

## 1. Phase objective

Prove that FloatTabs can safely reclaim a live `WKWebView` Runtime for an eligible inactive Slot, preserve a bounded in-memory restore state, and later create a fresh `WKWebView` using the same Browser Profile / `WKWebsiteDataStore` without losing durable product state or accepting stale callbacks.

The Phase 1 mechanism must answer:

```text
Does clean WKWebView reclamation produce a meaningful and repeatable memory reduction
without breaking Browser Profile/session/product-state invariants?
```

If this cannot be demonstrated, the lifecycle program stops before Phase 2/3/4.

## 2. Audited current facts

### 2.1 Existing persistent/runtime separation is already correct

`WebViewPool` already treats live WebViews as per-Slot runtime objects, while Browser Profile stores are resolved independently by `BrowserProfileDataStoreProvider`:

- Default Profile → `WKWebsiteDataStore.default()`;
- custom Profile on supported systems → `WKWebsiteDataStore(forIdentifier:)`;
- custom Profile identity never silently falls back to Default;
- explicit Profile data deletion is separate from runtime release.

Phase 1 must preserve that boundary.

### 2.2 Current `release(slotID:)` is destructive and incomplete as a hibernation primitive

Current `WebViewPool.release(slotID:)` removes Pool sidecars and the WebView but does **not**:

- capture `WKWebView.interactionState`;
- explicitly call `stopLoading()`;
- explicitly clear `navigationDelegate` / `uiDelegate`;
- explicitly invalidate `SlotNavigationObserver`'s KVO observation before dropping it;
- clear `pendingTerminationIncidentContexts`.

The public WebKit header defines both navigation and UI delegates as weak, so they are not an established retain-cycle root cause. They are still cleared in Phase 1 to make teardown deterministic and to suppress callbacks after the release boundary.

### 2.3 Current lifecycle release ordering is sound

`SlotLifecycleCoordinator.releaseInactiveSlot` already performs:

```text
final visibility/protection checks
→ prepareRuntimeForRelease
→ WebPanelContainerView.removeSlot
→ WebViewPool release
→ cancel inactive plan
→ onRuntimeReleased
```

`WebPanelContainerView` and `WebSlotHostView` keep their WebView references weak; removal from the AppKit hierarchy occurs before Pool teardown. Keep this order.

### 2.4 Not every `release()` means hibernation

Current product has destructive release callers that must **not** acquire restore semantics:

- Slot deletion;
- stored-state/profile replacement;
- Browser Profile / website-cache preparation;
- stale custom-Profile cleanup;
- rendering/Browser-Profile WebView rebuild;
- fullscreen restore-timeout rebuild/recovery;
- explicit runtime reset/replacement paths.

Therefore Phase 1 must not silently redefine `release()` as “hibernate”.

### 2.5 Attention / visibility protection stays unchanged in Phase 1

Current lifecycle protection includes:

- active Slot;
- fullscreen source Slot;
- supplemental-visible Slot;
- media-protected Slot;
- Attention-protected Slot.

Current Attention behavior protects `generating` and `ready`. That remains unchanged in Phase 1. Ready/Unread decoupling belongs to Phase 2.

### 2.6 Focus / fullscreen owners do not currently provide a proven strong WebView edge

`WebFocusRouter.currentWebView`, `WebPanelContainerView` WebView references, `WebSlotHostView.webView`, and `FullscreenSourceHostController.observedWebView` are weak. No evidence currently justifies expanding Phase 1 into Focus/Fullscreen behavior changes.

If post-implementation weak-deallocation or process-tree memory evidence fails, re-open the retain graph under the STOP gate rather than preemptively changing those domains.

### 2.7 Download handling does not justify a Phase 1 protection redesign

`SlotNavigationObserver` converts a WebKit navigation into `WKDownload` and hands it to the shared `DownloadCoordinator`, which owns the `WKDownload`. The coordinator does not retain the originating WebView directly. Existing download behavior is therefore left unchanged in Phase 1.

If live evidence shows a download keeps a released WebContent runtime resident or breaks transfer continuity, STOP and reconcile; do not silently add a new lifecycle authority inside this phase.

### 2.8 Website Cache is separate from Runtime reclamation

Cold runtime release currently may request cache cleanup after the last live runtime for a Browser Profile disappears. The cleanup service is explicitly limited to:

- disk cache;
- memory cache;
- fetch cache.

It does not include cookies/login/session/local storage. Phase 1 does not change cache policy. Runtime-hibernation effectiveness benchmarks use Warm release as the primary path to avoid conflating runtime memory reclamation with Cold cache cleanup.

## 3. Public WebKit restore mechanism

Use public `WKWebView.interactionState`.

WebKit documents it as an opaque, copyable state that can be retrieved from one WebView and assigned to another to restore:

- back-forward list;
- currently loaded page;
- scroll position;
- form data;
- related interaction state.

It is publicly available on macOS 12+, while FloatTabs supports macOS 13+.

### Phase 1 state handling rules

- Store the value as opaque in-memory state; do not assume it is a stable serialized `Data` format.
- Do not write it to UserDefaults, backups, logs, diagnostics, or other persistent storage in Phase 1.
- Never log form/page contents from the state.
- One Slot may have at most one pending restore snapshot.
- A successful destructive release/rebuild clears any pending snapshot.

## 4. Semantic split: Hibernate versus Release

Phase 1 introduces two explicit mechanisms.

### `hibernate(slotID:)`

Used only by normal eligible lifecycle reclamation.

```text
capture compatible restore state
→ deterministic teardown
→ keep transient restore snapshot
→ Runtime becomes non-resident
```

### `release(slotID:)`

Remains destructive transient-runtime release.

```text
clear any restore snapshot
→ deterministic teardown
→ Runtime becomes non-resident
```

All existing destructive callers stay on `release()` / `remove()`.

Only `SlotLifecycleCoordinator.releaseInactiveSlot(...)`, including its critical-memory-pressure path, changes from destructive release to hibernate.

## 5. Restore snapshot contract

Keep the snapshot private to the Web Runtime domain, preferably as a private/nested value in `WebViewPool.swift`.

Conceptual shape:

```swift
struct WebRuntimeRestoreSnapshot {
    let interactionState: Any
    let capturedURL: URL
    let browserProfileIdentity: BrowserProfileIdentity
    let runtimeRenderingProfile: WebRenderingProfile
}
```

Exact Swift spelling may vary, but semantics may not.

### Snapshot capture conditions

Capture only when all are true:

- a live WebView exists for the Slot;
- the current URL used for restore validation is safe;
- `interactionState` is non-nil;
- current applied Browser Profile identity is known;
- current applied runtime rendering profile is known.

If `interactionState` is nil or capture metadata is incomplete, hibernation still releases the runtime but stores no restore snapshot. Later activation follows the existing URL-load fallback.

### Snapshot compatibility on restore

Before applying a snapshot, verify:

1. Slot identity is the same dictionary key;
2. Browser Profile identity equals the currently requested profile identity;
3. effective runtime rendering profile equals the current requested effective runtime rendering profile for the captured/current safe URL;
4. persisted/current safe URL has not materially moved away from the captured URL.

If any compatibility check fails:

```text
discard snapshot
→ create normal runtime
→ load safe currentURL/homeURL using existing fallback rules
```

Do not attempt to partially merge an old interaction state with a changed Browser Profile or rendering identity.

## 6. Exact restore ordering

For a compatible snapshot:

```text
resolve same Browser Profile data store
→ construct Attention/Response bridges
→ install document-start scripts/message handlers in WKUserContentController
→ create fresh WKWebView
→ assign new runtime generation / WebView instance identity
→ attach bridges
→ create navigation observer
→ create PopupCoordinator / install delegates
→ store all new Pool sidecars/maps
→ assign webView.interactionState = snapshot.interactionState
→ consume snapshot
```

Do **not** also issue the normal URL `load()` on the interaction-state restore path. A simultaneous load can race or overwrite restored history/document state.

URL fallback is used when the snapshot is missing/incompatible. If a real supported macOS runtime demonstrates that an accepted `interactionState` assignment can silently fail to initiate restoration, STOP and reconcile a bounded fallback design rather than adding an arbitrary timer in the initial implementation.

## 7. Deterministic teardown ordering

Introduce one private common teardown primitive used by:

- `hibernate(slotID:)`;
- destructive `release(slotID:)`;
- `rebuildWebView(...)` where compatible with existing resident-set semantics.

The common teardown sequence is:

```text
1. freeze diagnostic/native navigation fields needed for release evidence
2. invalidate ChatGPT Attention bridge
3. invalidate ChatGPT Response bridge
4. close/discard PopupCoordinator
5. explicitly invalidate SlotNavigationObserver
   - cancel liveness task
   - cancel navigation-stall/probe tasks
   - invalidate KVO token
   - reject future diagnostic callbacks
6. set webView.navigationDelegate = nil
7. set webView.uiDelegate = nil
8. webView.stopLoading()
9. clear per-Slot transient maps:
   - navigation observer
   - applied rendering
   - applied Browser Profile identity
   - lastKnownURL
   - deferred reload marker
   - pending termination incident context
   - popup/bridge maps
10. remove WebView from AppKit superview if still attached
11. remove WebView + runtime diagnostic identity from Pool
12. emit truthful release/hibernate diagnostics
13. notify resident-set change when logical residency actually changed
```

### `SlotNavigationObserver`

Add an explicit idempotent teardown method rather than relying on observer deinit timing. It must invalidate the KVO token and existing diagnostic/liveness tasks. Pool remains responsible for clearing WebView delegates.

### Stale async results

Preserve and extend the existing runtime/WebView/navigation-generation checks. A callback launched by the pre-hibernate runtime must never mutate the restored runtime.

## 8. Diagnostics contract

Add bounded metadata only; never log interaction state contents.

Recommended evidence:

- `web_runtime.hibernate.begin`
- `web_runtime.hibernate.captured`
  - `interaction_state_present: Bool`
  - safe existing runtime identity fields
- `web_runtime.hibernate.completed`
- `web_runtime.restore.begin`
- `web_runtime.restore.completed`
  - `restore_source = interaction_state | url_fallback`
- destructive `web_runtime.released` remains distinguishable from hibernate.

Exact event naming can be adjusted to existing Diagnostics vocabulary, but diagnostics must clearly distinguish:

```text
hibernate
vs destructive release
vs rebuild
vs restore-from-state
vs URL fallback
```

Diagnostics remains observational and must not make the restore decision.

## 9. Exact implementation file scope

### Authorized production files

1. `FloatTabs/Web/WebViewPool.swift`
   - restore snapshot store;
   - `hibernate(slotID:)`;
   - deterministic common teardown;
   - restore-vs-load creation path;
   - snapshot compatibility/invalidation;
   - bounded diagnostics.

2. `FloatTabs/Web/SlotLifecycleCoordinator.swift`
   - normal inactive/critical-pressure lifecycle reclamation calls `hibernate` instead of destructive `release`;
   - no timer/policy redesign.

3. `FloatTabs/Web/SlotNavigationObserver.swift`
   - explicit idempotent teardown/invalidation for KVO + pending diagnostic/liveness work.

### Authorized tests

4. `FloatTabsTests/WebViewPoolTests.swift`

5. `FloatTabsTests/WebAttentionLifecycleTests.swift`

6. `FloatTabsTests/WebFocusAdapterTests.swift` only if the existing observer test fixture is the narrowest place to verify explicit observer invalidation; otherwise leave unchanged.

### Authorized benchmark tooling

7. `tools/benchmark/floattabs_lifecycle_benchmark.py` only as needed to add/report Phase 1 hibernate/restore matrix evidence using the existing Debug benchmark control channel.

8. `tools/benchmark/README.md` only to document the accepted Phase 1 benchmark invocation/output.

### Control/design files

`CURRENT_STATUS.md`, `CURRENT_TASK.md`, this plan, and architecture routing may be updated for phase state/evidence.

## 10. Explicitly out of scope

Do not modify unless a STOP condition forces task reconciliation:

- `PanelController.swift` product semantics;
- `FullscreenSourceHost.swift`;
- `WebFocusRouter.swift`;
- `WebViewContainer.swift`;
- `BrowserProfileDataStoreProvider.swift` behavior;
- Browser Profile schemas/migrations;
- Attention generating/ready semantics;
- durable Unread semantics;
- ChatGPT completion notification;
- Hot/Warm/Cold UI or timer values;
- automatic Runtime Budget/candidate ranking;
- Website Cache cleanup policy/data types;
- manual process-pool topology;
- server Push / service-worker behavior;
- native recent-conversation preview.

If implementation requires changing one of these product boundaries, STOP and update the task/contract before mutation.

## 11. Regression test contract

### `WebViewPoolTests`

Add focused tests covering at least:

1. **hibernate capture + restore path**
   - injected/controlled opaque interaction state captured from old WebView;
   - old runtime removed;
   - recreated WebView receives the state;
   - ordinary initial URL loader is not invoked on compatible state restore.

2. **nil state fallback**
   - hibernate with no interaction state;
   - recreate loads `currentURL`/home using current fallback rules.

3. **destructive release clears snapshot**
   - hibernate creates pending state;
   - destructive release/remove invalidates it;
   - next create follows URL load.

4. **Browser Profile mismatch invalidates snapshot**
   - Default/custom identity change must not replay old interaction state.

5. **rendering mismatch invalidates snapshot**
   - WebView-rebuild-level rendering identity change must not replay old state.

6. **same-profile sibling isolation**
   - hibernating/restoring Slot A must not affect Slot B even if both share one custom data store.

7. **deterministic teardown**
   - old Attention/Response bridges invalidated;
   - popup coordinator discarded;
   - original WebView delegates cleared;
   - old observer explicitly invalidated;
   - pending termination incident context not carried into new runtime;
   - Pool/runtime identity maps no longer reference the old runtime.

8. **stale async result rejection across hibernate/restore**
   - extend existing health/page-app probe replacement tests where needed.

9. **runtime identity monotonicity**
   - restored Runtime receives a new physical runtime generation/WebView instance ID.

10. **weak deallocation proof**
   - with no test-owned strong reference, the original WebView becomes nil after teardown/autorelease settling. If this cannot be made deterministic in XCTest because WebKit internally delays object lifetime, record that limitation and rely on the process-tree benchmark; do not fake a PASS.

### `WebAttentionLifecycleTests`

Add/adjust tests to prove:

- inactive Warm/Cold release invokes the hibernate mechanism;
- critical eligible Warm pressure also hibernates;
- active/fullscreen/supplemental-visible/media/Attention-protected Slots remain protected exactly as before;
- Phase 1 does not alter Ready/Generating protection semantics.

All existing Browser Profile and Attention suites must remain green.

## 12. Runtime benchmark contract

Use the existing Debug benchmark control channel and `tools/benchmark/floattabs_lifecycle_benchmark.py`. Do not create a second benchmark control plane.

### Measurement scope

Measure:

- FloatTabs host RSS/CPU;
- attributed WebContent/Networking/GPU RSS where existing macOS process attribution can observe it;
- total FloatTabs process-tree RSS/CPU;
- WebContent/helper process counts;
- `resident_slot_count` / IDs from `WebViewPool`;
- hibernate/release/restore diagnostic boundaries;
- activation/restore timing.

Never claim public-WebKit-proven exact per-Slot WebContent memory attribution.

### Primary isolation path

Use **Warm** lifecycle release for primary Phase 1 memory evidence so Cold cache cleanup does not confound Runtime reclamation. Cold remains a regression path, not the primary memory measurement.

### Matrix

Run controlled configurations with:

```text
1 configured/loaded Slot  — baseline/control
2 loaded Slots
4 loaded Slots
8 loaded Slots
```

For 2/4/8, make all target pages resident before the release window, then leave one selected and allow the others to cross the Warm hibernate boundary.

Use representative heavy ChatGPT conversations plus at least one simpler Web page/local fixture when practical, so a site-specific result is not mistaken for a WebKit mechanism result.

### Repetition and control drift

For each meaningful 4/8 heavy-runtime scenario:

- run at least 3 repeated cycles or equivalent clean runs;
- measure a stable no-op/control window before hibernate;
- compare pre-hibernate stable-tail RSS with post-hibernate stable-tail RSS after a bounded settle period;
- record process count and resident Runtime count at both boundaries.

### Memory PASS definition

A Phase 1 memory PASS requires all of:

1. eligible `resident_slot_count` falls by the exact number of hibernated Slots;
2. no protected/visible Slot is released;
3. total process-tree memory reduction is positive and repeatable in the controlled heavy-runtime 4/8 scenarios;
4. the median reclaimed-memory signal is larger than **2× the absolute no-op/control drift** measured in the same run family;
5. the memory signal grows or remains directionally consistent as more heavy runtimes are hibernated; it must not be explainable only by one constant host-process fluctuation;
6. restore does not recreate extra duplicate resident runtimes.

If 4/8 heavy-runtime results remain inside control noise, or runtime count falls while memory does not show a repeatable signal beyond noise, Phase 1 primary gate is **FAIL/UNKNOWN** and Phase 2+ must not proceed.

### Restore performance evidence

For paired hibernated-state restore versus ordinary URL fallback on the same machine/site:

- record restore-to-visible/usable timing using the existing harness/diagnostic seams where measurable;
- record p50/p95 over repeated samples;
- interaction-state restore must not be materially slower than URL fallback. Treat `> max(20%, 300 ms)` median regression as a STOP/reconcile signal rather than accepting a supposedly “fast restore” path.

This is a Phase 1 usability guard, not the final Phase 6 perceived-speed target.

## 13. Runtime/manual acceptance

After machine tests pass, perform manual macOS acceptance on a QA/debug build:

- ChatGPT custom/default Browser Profile remains logged in;
- same conversation returns after hibernate;
- back/forward history is sensible;
- scroll position is restored where WebKit supports it;
- unsent/form state survives in a controlled test page where appropriate;
- no duplicate page load is visibly triggered on interaction-state restore;
- inactive ChatGPT generation/Ready protection remains unchanged from pre-Phase1 behavior;
- Hot/Warm/Cold controls still behave under their current production semantics;
- fullscreen/source restoration and focus switching show no regression.

The user owns final visual/manual UI acceptance.

## 14. Phase 1 acceptance criteria

Phase 1 implementation may close only when:

1. hibernate and destructive release are semantically distinct;
2. deterministic teardown covers all audited Web Runtime sidecars;
3. public interaction-state restore works on supported macOS evidence/QA;
4. Browser Profile identity/session/cookies/product config are preserved;
5. compatible state restore does not issue a competing ordinary load;
6. incompatible/missing state falls back safely to current URL/home;
7. old runtime callbacks are stale-rejected;
8. current visible/media/Attention protection semantics remain unchanged;
9. focused + full required test/build gates pass;
10. controlled runtime benchmark satisfies the Memory PASS definition above;
11. restore performance does not trip the paired-regression STOP guard;
12. independent web audit finds no ownership/data-safety regression;
13. no Phase 2+ behavior has leaked into this phase.

## 15. STOP conditions

STOP implementation and reconcile instead of expanding locally if:

- old WebView remains strongly reachable from a FloatTabs-owned graph after the deterministic teardown contract;
- hibernation requires changing Browser Profile/session persistence semantics;
- interaction state cannot be restored reliably through public API on the supported macOS baseline;
- restore requires an arbitrary timer/double-navigation hack to be usable;
- controlled process-tree memory remains within no-op drift despite multiple heavy runtimes becoming non-resident;
- downloads, fullscreen, focus or another cross-domain owner is proven to block safe teardown and requires new product semantics;
- required fix crosses into Ready/Unread decoupling, notification, Runtime Budget, or other Phase 2+ scope;
- required repository-host CI fails;
- unknown overlapping unique work appears in the affected Runtime files.

## 16. Rollback boundary

The rollback is bounded:

- lifecycle call sites can return from `hibernate` to destructive `release` while keeping deterministic teardown improvements if those improvements independently pass tests;
- restore snapshot storage/application can be removed without touching Browser Profile persistence;
- no schema migration or user-data transformation is introduced in Phase 1;
- no released Runtime is required to delete website/session data.

Therefore a Phase 1 rollback must never require clearing Browser Profiles, cookies, sessions, Slot configuration, backups or unread state.

## 17. Construction handoff rule

After this plan and the reconciled `CURRENT_STATUS.md` / `CURRENT_TASK.md` merge, local construction may start under one bounded execution card.

The card must reference this plan rather than duplicating it, must preserve one canonical writer, and must stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT` after implementation/tests/benchmark evidence are pushed. Merge/release are separate web-audit decisions.
