# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`
**Title:** Runtime Lifecycle / Memory redesign — governed phased implementation
**Status:** `ACTIVE / PHASE 1 PLAN FREEZE`
**Mode:** `AUDIT CLOSEOUT / DESIGN FREEZE`
**Task class:** `HIGH-RISK WEB RUNTIME LIFECYCLE / MEMORY`
**Audit baseline main:** `1ba0ec7fe70c3d8a6fd42d586dcc813ed87d9088`
**Frozen program contract:** `docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md`
**Phase 1 plan:** `docs/architecture/FloatTabs_Runtime_Lifecycle_Phase1_Safe_Hibernate_Restore_Plan_V1.md`
**Active PR:** `#167` / `codex/ft-runtime-lifecycle-memory-001-phase1-audit-freeze`
**JSC root cause:** `UNKNOWN`

## Current authorization

The Phase 1 focused read-only audit is complete. The only currently authorized mutation is this control/design freeze PR.

**Runtime product mutation is not authorized until PR #167 merges and a post-merge Control Alignment explicitly changes this task to `ACTIVE / PHASE 1 IMPLEMENTATION`.**

After that alignment, one concise construction card may authorize local implementation exactly within the frozen Phase 1 plan.

## Accepted Phase 1 design

### Semantic split

Phase 1 introduces explicit Runtime hibernation without changing destructive release semantics:

```text
hibernate(slotID:)
  capture compatible opaque interaction state
  → deterministic teardown
  → retain one memory-local restore snapshot

release(slotID:)
  clear pending restore snapshot
  → deterministic destructive teardown
```

Only normal eligible lifecycle reclamation, including eligible critical Warm pressure, changes to `hibernate`.

Deletion, profile/stored-state replacement, website-cache preparation, rendering/Profile rebuild, fullscreen recovery/rebuild, and explicit reset/replacement remain destructive.

### Restore state

Use public `WKWebView.interactionState` only.

Snapshot semantics:

- memory-local only;
- opaque `Any`/WebKit state; do not assume stable serialized `Data`;
- never log or persist contents;
- store Browser Profile identity, effective runtime rendering identity and safe captured URL alongside the state for compatibility validation;
- at most one pending snapshot per Slot.

Restore only when Slot/Profile/rendering/URL compatibility matches. Otherwise discard and follow the existing currentURL/home URL load fallback.

For compatible state restore:

```text
same datastore/configuration
→ install scripts/bridges before WebView creation
→ create fresh WebView/runtime identity
→ install observer/popup/delegates/maps
→ assign interactionState
→ consume snapshot
```

Do not issue a competing ordinary URL load on this path.

### Deterministic teardown

The shared teardown primitive must cover:

1. Attention bridge invalidation;
2. Response bridge invalidation;
3. PopupCoordinator close/discard;
4. explicit `SlotNavigationObserver` invalidation including KVO and pending liveness/navigation/probe work;
5. `navigationDelegate = nil`;
6. `uiDelegate = nil`;
7. `stopLoading()`;
8. clearing every per-Slot transient Pool map, including `pendingTerminationIncidentContexts`;
9. AppKit superview removal if still attached;
10. WebView/runtime identity removal and truthful resident-set diagnostics.

WebKit delegates are publicly weak; explicit clearing is a deterministic callback boundary, not a claim that they caused the historical memory issue.

## Authorized Phase 1 implementation files after Control Alignment

### Production

- `FloatTabs/Web/WebViewPool.swift`
- `FloatTabs/Web/SlotLifecycleCoordinator.swift`
- `FloatTabs/Web/SlotNavigationObserver.swift`

### Tests

- `FloatTabsTests/WebViewPoolTests.swift`
- `FloatTabsTests/WebAttentionLifecycleTests.swift`
- `FloatTabsTests/WebFocusAdapterTests.swift` only if it is the narrowest existing fixture for observer invalidation

### Benchmark tooling

- `tools/benchmark/floattabs_lifecycle_benchmark.py` only if necessary for Phase 1 matrix/reporting
- `tools/benchmark/README.md` only for the Phase 1 runbook

### Control/design

- current STATUS/TASK and the accepted architecture plan for factual progress/evidence only.

## Explicitly not authorized in Phase 1

Do not change without STOP/reconciliation:

- `PanelController.swift` product semantics;
- `FullscreenSourceHost.swift`;
- `WebFocusRouter.swift`;
- `WebViewContainer.swift`;
- Browser Profile datastore behavior/schema;
- Attention generating/ready semantics;
- durable Unread semantics;
- ChatGPT completion notifications;
- Hot/Warm/Cold UI or configured timer values;
- automatic Runtime Budget/ranking;
- Website Cache data types/policy;
- process-pool topology;
- server Push/service-worker behavior;
- native conversation preview.

## Exact test contract

Implementation must add/adjust tests for:

1. compatible hibernate captures interaction state and restores it to a fresh WebView without invoking ordinary initial load;
2. nil state falls back to currentURL/home;
3. destructive release clears any pending hibernate state;
4. Browser Profile mismatch invalidates restore state;
5. runtime rendering mismatch invalidates restore state;
6. same-profile sibling Slot remains isolated;
7. deterministic teardown invalidates bridges/popup/observer, clears delegates/maps/pending termination incident context;
8. stale async health/page-app/liveness results from old runtime are rejected after restore;
9. restored runtime gets a new physical runtime generation/WebView instance identity;
10. old WebView weak-deallocation evidence where deterministic XCTest behavior permits;
11. inactive Warm/Cold lifecycle and critical eligible Warm path invoke hibernate;
12. active/fullscreen/supplemental-visible/media/Attention-protected behavior remains unchanged;
13. current Generating/Ready protection remains unchanged in Phase 1.

Existing Browser Profile, Attention, lifecycle, diagnostics and build tests must remain green.

## Runtime benchmark contract

Use the existing Debug benchmark control plane and lifecycle benchmark; do not create a second control service.

Primary memory measurement uses **Warm** release so Cold website-cache cleanup does not confound runtime reclamation.

Matrix:

```text
1 loaded Slot baseline
2 loaded Slots
4 loaded Slots
8 loaded Slots
```

For heavy 4/8 scenarios use at least 3 repeated cycles/equivalent clean runs.

Collect:

- host RSS/CPU;
- existing attributed WebContent/Networking/GPU RSS evidence;
- total process-tree RSS/CPU;
- helper process counts;
- exact Pool resident Slot count/IDs;
- hibernate/restore diagnostic boundaries;
- restore timing.

Do not claim exact public-WebKit-proven per-Slot WebContent memory.

### Memory PASS

All must hold:

- resident runtime count drops exactly for hibernated Slots;
- protected/visible runtimes are untouched;
- process-tree reclaimed-memory signal is positive/repeatable in heavy 4/8 scenarios;
- median signal exceeds `2×` absolute no-op/control drift measured in the same run family;
- direction remains consistent as more heavy runtimes are hibernated;
- restoration creates no duplicate resident runtime.

If logical residency falls but memory stays inside control noise, verdict is `FAIL / UNKNOWN`; STOP before Phase 2+.

### Restore performance guard

Pair compatible interaction-state restore against ordinary URL fallback on the same machine/site.

Record p50/p95. If median interaction-state restore is slower by more than `max(20%, 300 ms)`, STOP/reconcile rather than claiming a fast restore path.

## Manual acceptance

After machine gates:

- Default/custom Profile login remains intact;
- same ChatGPT conversation returns;
- back/forward and scroll restoration are sane;
- controlled form state restores where WebKit supports it;
- no visible double load on interaction-state restore;
- current Attention protection behavior remains unchanged;
- current Hot/Warm/Cold behavior remains functionally intact;
- focus/fullscreen show no regression.

User owns final visual/manual acceptance.

## STOP conditions

STOP and reconcile if:

- a FloatTabs-owned strong edge keeps the old WebView alive after the deterministic teardown contract;
- Browser Profile/session/user-data safety would need to change;
- public interactionState is unreliable on supported macOS without arbitrary timer/double-navigation hacks;
- controlled 4/8 runtime memory evidence stays within no-op drift;
- a proven download/fullscreen/focus owner requires new cross-domain semantics;
- implementation needs Panel/Fullscreen/Focus/Profile/Attention/Unread/Notification/Runtime-Budget changes;
- private/unsupported WebKit behavior is required;
- required CI fails;
- overlapping unique work appears in the authorized files.

## Rollback

Rollback never touches user data:

- lifecycle can switch hibernate call sites back to destructive release;
- restore snapshot storage/application can be removed independently;
- deterministic teardown improvements may remain if independently verified;
- no schema migration/user-data rewrite exists in Phase 1.

## Gate to implementation

PR #167 must first:

1. contain only control/architecture documentation;
2. pass required `Build & Test (Apple Silicon arm64)`;
3. pass independent plan/Authority audit;
4. merge into `main`.

Then run Control Alignment to `ACTIVE / PHASE 1 IMPLEMENTATION` and issue one concise local execution card referencing the Phase 1 plan.

Local executor must implement, test and gather benchmark evidence, push the result, and stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`. Merge/release are not authorized by the construction card.
