# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`
**Title:** Runtime Lifecycle / Memory redesign — Phase 1 Safe Hibernate + Restore
**Status:** `WAITING / REQUIRED PR CI ON PHASE 1 IMPLEMENTATION`
**Mode:** `EXECUTE`
**Task class:** `HIGH-RISK WEB RUNTIME LIFECYCLE / MEMORY`
**Current program contract:** `docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V2.md`
**Current Phase 1 plan:** `docs/architecture/FloatTabs_Runtime_Lifecycle_Phase1_Safe_Hibernate_Restore_Plan_V2.md`
**JSC root cause:** `UNKNOWN`

## Authorization

Continue the existing Phase 1 implementation under the V2 architecture-first cadence.

The previously frozen V1 strict scale-benchmark gate is superseded for current execution. Phase 1 now finishes the structural Runtime primitive, proves bounded real-runtime correctness, and proceeds to independent audit/merge without waiting for the Phase 4 scale benchmark.

Preserve existing local uncommitted implementation work. Do not restart or discard it merely because the phase gate changed.

## Exact production scope

Authorized:

- `FloatTabs/Web/WebViewPool.swift`
- `FloatTabs/Web/SlotLifecycleCoordinator.swift`
- `FloatTabs/Web/SlotNavigationObserver.swift`

Expected behavior:

```text
hibernate(slotID:)
  capture compatible opaque interaction state when available
  → deterministic teardown
  → retain one memory-local restore snapshot
  → Runtime becomes non-resident

release(slotID:)
  clear pending restore state
  → deterministic destructive teardown
  → Runtime becomes non-resident
```

Only normal eligible inactive lifecycle reclamation / the already-existing eligible critical-Warm pressure path changes to hibernate.

Destructive release/rebuild/reset/delete/Profile/cache/recovery paths remain destructive and clear pending restore state.

## Restore contract

Use public `WKWebView.interactionState` only.

- memory-local only;
- opaque, no assumed serialized schema;
- never log/persist contents;
- validate Slot/Profile/effective-rendering/current-URL compatibility before replay;
- compatible restore constructs the fresh Runtime and all sidecars first, then assigns interaction state;
- compatible restore must not issue the ordinary initial URL load;
- missing/incompatible state uses the existing safe currentURL/home fallback;
- arbitrary timer/double-navigation/private-API workarounds are not authorized.

## Deterministic teardown contract

Before the old Runtime is considered released:

1. freeze only required diagnostic/navigation metadata;
2. invalidate Attention bridge;
3. invalidate Response bridge;
4. close/discard PopupCoordinator;
5. explicitly invalidate SlotNavigationObserver including KVO + liveness/navigation/probe work;
6. clear `navigationDelegate`;
7. clear `uiDelegate`;
8. call `stopLoading()`;
9. clear transient per-Slot Pool maps, including pending termination incident context;
10. detach old WebView from superview if still present;
11. remove old WebView/Runtime diagnostic identity;
12. emit truthful hibernate/release/restore evidence;
13. update resident-set observation only when logical residency changes.

Stale callbacks from the old Runtime must not mutate the restored Runtime.

## Authorized tests

- `FloatTabsTests/WebViewPoolTests.swift`
- `FloatTabsTests/WebAttentionLifecycleTests.swift`
- `FloatTabsTests/WebFocusAdapterTests.swift` only if required for the narrow existing observer fixture

Required coverage remains the V2 plan matrix, including:

- compatible state capture/restore without duplicate initial load;
- URL fallback;
- destructive release clears state;
- Profile/rendering mismatch invalidation;
- same-Profile sibling isolation;
- deterministic teardown and stale callback rejection;
- fresh Runtime identity;
- weak old-WebView deallocation where deterministic;
- eligible lifecycle/critical-Warm hibernate;
- unchanged active/fullscreen/supplemental/media/Attention protection;
- unchanged Generating/Ready semantics.

## Current verification evidence

Fresh local evidence on the final diff:

```text
focused tests: 146 executed / 0 failures
full tests: 1073 executed / 3 skipped / 0 failures
Debug build: PASS
Release build: PASS
bounded live smoke: 2 existing Slots; resident drop and interactionState restore observed
strict 1/2/4/8 benchmark: NOT RUN / DEFERRED TO PHASE 4
PR: #170 OPEN; head dd12ba89dc3ef11758c5f3d7bb04207b0307fafc
required PR CI: NO_RUN_OBSERVED
```

## Phase 1 verification gate — current

Required before merge:

1. focused lifecycle regression tests pass;
2. full unit suite has no new Phase 1 failures;
3. Debug build passes;
4. Release build passes;
5. bounded 1–2 existing-Slot live Runtime smoke passes:
   - eligible inactive Runtime becomes non-resident;
   - reselect creates exactly one fresh Runtime;
   - Profile login/session remains intact;
   - same page/conversation returns through interaction-state restore or defined fallback;
   - no obvious competing double-load;
   - no obvious focus/fullscreen regression in the exercised path;
6. required GitHub `Build & Test (Apple Silicon arm64)` passes on the literal PR head;
7. independent web audit passes.

## Deferred to Phase 4 — not Phase 1 blockers

Do not block Phase 1 on:

- strict `1 / 2 / 4 / 8` loaded-Slot matrix;
- >=9 configured-Slot fixture;
- heavy 4/8 repeated runs;
- no-op/control drift study;
- `median reclaimed > 2× drift` threshold;
- final process-tree memory curve;
- final restore p50/p95 policy threshold;
- Runtime budget/ranking selection.

Do not create temporary production Slots merely to satisfy the superseded V1 benchmark requirement.

## Out of scope / STOP before touching

Do not modify without task reconciliation:

- `PanelController.swift` product semantics;
- `FullscreenSourceHost.swift`;
- `WebFocusRouter.swift`;
- `WebViewContainer.swift`;
- Browser Profile datastore behavior/schema;
- Attention generating/ready semantics;
- durable Unread semantics;
- completion notifications;
- Hot/Warm/Cold UI/timing values;
- automatic Runtime Budget/ranking;
- Website Cache policy/data types;
- permanent process-pool topology;
- server Push/service-worker behavior;
- native conversation preview.

STOP if:

- old WebView remains strongly reachable after deterministic teardown;
- Profile/session/user-data safety requires a behavior/schema change;
- public interactionState requires arbitrary timer/double-navigation/private API behavior;
- stale old-Runtime callbacks can mutate the restored Runtime;
- destructive paths accidentally retain/replay hibernate state;
- proven Download/Fullscreen/Focus/Panel ownership requires new cross-domain semantics;
- overlapping unique work appears;
- required focused/full tests, Debug/Release build or required CI fail because of the Phase 1 change.

Do not STOP merely because the real configuration has fewer than nine Slots or because the scale memory curve is not yet quantified.

## Required executor outcome

The executor must:

1. preserve and inspect the existing dirty Phase 1 implementation;
2. refresh `origin/main` after the V2 refreeze merges and reread current Authority;
3. reconcile the existing diff against V2; do not rewrite valid work;
4. correct only actual scope/correctness mismatches;
5. run focused tests, full tests, Debug build and Release build on the final diff;
6. perform the bounded 1–2 Slot live Runtime smoke without mutating real Slot/Profile data beyond normal use;
7. commit and push one Phase 1 implementation branch;
8. create/update one Phase 1 PR;
9. allow required CI to run;
10. stop for independent web audit.

Do not merge and do not publish/release from the local construction handoff.

## Rollback

Rollback remains data-safe:

- hibernate callers can return to destructive release;
- restore snapshot storage/application can be removed independently;
- deterministic teardown improvements may remain if independently verified;
- no migration or persisted user-data rewrite exists in Phase 1.

Production release is not authorized.
