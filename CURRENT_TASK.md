# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`
**Title:** Runtime Lifecycle / Memory redesign — Phase 1 Safe Hibernate + Restore
**Status:** `ACTIVE / PHASE 1 IMPLEMENTATION`
**Mode:** `EXECUTE`
**Task class:** `HIGH-RISK WEB RUNTIME LIFECYCLE / MEMORY`
**Implementation baseline main:** `672f7122f352f6cfb1704109db6488519480c628`
**Frozen program contract:** `docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md`
**Frozen Phase 1 plan:** `docs/architecture/FloatTabs_Runtime_Lifecycle_Phase1_Safe_Hibernate_Restore_Plan_V1.md`
**JSC root cause:** `UNKNOWN`

## Authorization

Phase 1 implementation is authorized now, but only inside the frozen Phase 1 plan.

The executor must read the control files and Phase 1 plan before mutation. The concise construction card is a bounded handoff and must not replace/restate the full contract.

## Exact production scope

Authorized:

- `FloatTabs/Web/WebViewPool.swift`
- `FloatTabs/Web/SlotLifecycleCoordinator.swift`
- `FloatTabs/Web/SlotNavigationObserver.swift`

Expected behavior:

```text
hibernate(slotID:)
  capture compatible opaque interaction state
  → deterministic teardown
  → retain one memory-local restore snapshot

release(slotID:)
  clear pending restore state
  → deterministic destructive teardown
```

Only normal eligible inactive lifecycle reclamation / eligible critical Warm memory-pressure reclamation changes to hibernate.

Destructive release/rebuild/reset/delete/profile/cache/recovery paths remain destructive and must clear pending restore state.

## Restore contract

Use public `WKWebView.interactionState`.

- memory-local only;
- opaque value, no assumed serialized schema;
- never log/persist its contents;
- validate Slot/Profile/effective-rendering/current-URL compatibility before replay;
- compatible restore builds the full fresh WebView/bridge/observer/popup runtime first, then assigns interaction state;
- compatible restore must not issue ordinary initial URL load;
- missing/incompatible state uses the existing safe currentURL/home fallback;
- if real supported macOS shows silent interaction-state failure requiring arbitrary timer/double-navigation hacks, STOP and reconcile instead.

## Deterministic teardown contract

Before old Runtime is considered released:

1. freeze required diagnostic navigation metadata;
2. invalidate Attention bridge;
3. invalidate Response bridge;
4. close/discard PopupCoordinator;
5. explicitly invalidate SlotNavigationObserver including KVO + liveness/navigation/probe tasks;
6. clear `navigationDelegate`;
7. clear `uiDelegate`;
8. call `stopLoading()`;
9. clear all transient per-Slot Pool maps, including pending termination incident context;
10. detach old WebView from superview if still present;
11. remove old WebView/runtime diagnostic identity;
12. emit truthful hibernate/release/restore evidence and resident-set change.

Do not claim weak WebKit delegates caused the historical memory problem; clearing is deterministic lifecycle hygiene.

## Authorized tests

- `FloatTabsTests/WebViewPoolTests.swift`
- `FloatTabsTests/WebAttentionLifecycleTests.swift`
- `FloatTabsTests/WebFocusAdapterTests.swift` only if required for the narrow existing SlotNavigationObserver fixture

Must cover the exact test matrix frozen in the Phase 1 plan, including:

- state capture/restore without duplicate initial load;
- URL fallback;
- destructive release clears state;
- Profile/rendering mismatch invalidation;
- same-profile sibling isolation;
- deterministic teardown/old callback rejection;
- fresh runtime identity;
- weak old-WebView deallocation where deterministic;
- Warm/Cold + eligible critical pressure hibernate;
- unchanged visible/fullscreen/supplemental/media/Attention protection;
- unchanged Generating/Ready semantics.

## Authorized benchmark tooling

Only if needed:

- `tools/benchmark/floattabs_lifecycle_benchmark.py`
- `tools/benchmark/README.md`

Use existing Debug benchmark control channel. Do not create a new control plane.

Primary memory measurement is Warm lifecycle hibernation, not Cold, to avoid cache-cleanup confounding.

Matrix: `1 / 2 / 4 / 8` loaded Slots.

For heavy 4/8 cases, use at least 3 repeated cycles/equivalent clean runs.

Memory PASS:

```text
exact resident-count reduction
+ protected runtimes unchanged
+ positive/repeatable process-tree memory reduction
+ median reclaimed signal > 2× same-family no-op/control drift
+ directionally consistent as more heavy runtimes hibernate
+ no duplicate runtime after restore
```

Restore performance STOP guard:

```text
median interaction-state restore regression vs URL fallback
> max(20%, 300 ms)
=> STOP / reconcile
```

## Out of scope / STOP before touching

Do not modify without task reconciliation:

- `PanelController.swift` product semantics;
- `FullscreenSourceHost.swift`;
- `WebFocusRouter.swift`;
- `WebViewContainer.swift`;
- Browser Profile datastore behavior/schema;
- Attention generating/ready semantics;
- durable Unread semantics;
- completion notification;
- Hot/Warm/Cold UI/timing values;
- automatic Runtime Budget/ranking;
- Website Cache policy/data types;
- permanent process-pool topology;
- server Push/service-worker behavior;
- native conversation preview.

STOP if:

- old WebView remains strongly reachable after the deterministic teardown contract;
- Profile/session/user-data safety would change;
- public interactionState is unreliable without unsupported hacks;
- controlled 4/8 memory evidence stays inside no-op drift;
- proven download/fullscreen/focus ownership requires new cross-domain semantics;
- private WebKit behavior is required;
- overlapping unique work appears;
- required tests/CI fail.

## Required executor outcome

The executor must:

1. refresh `origin/main` and verify this task/plan still match;
2. implement only the frozen Phase 1 scope;
3. run focused tests then required broader tests/builds;
4. run the accepted benchmark matrix and preserve raw/report evidence;
5. update STATUS/TASK with factual evidence only as required by the task;
6. commit and push one Phase 1 branch/PR;
7. stop at:

`WAITING_FOR_INDEPENDENT_WEB_AUDIT`

Do not merge and do not publish/release.

## Rollback

Rollback must remain data-safe:

- hibernate callers can return to destructive release;
- restore snapshot storage/application can be removed independently;
- deterministic teardown can remain if independently verified;
- no migration or persisted user-data rewrite exists in Phase 1.

Production release is not authorized.
