# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Title:** Runtime Lifecycle / Memory redesign — Phase 1 Safe Hibernate + Restore  
**Status:** `WAITING / REQUIRED PR CI ON RECONCILED PHASE 1 IMPLEMENTATION`  
**Mode:** `VERIFY`  
**Task class:** `HIGH-RISK WEB RUNTIME LIFECYCLE / MEMORY`  
**Current program contract:** `docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V2.md`  
**Current Phase 1 plan:** `docs/architecture/FloatTabs_Runtime_Lifecycle_Phase1_Safe_Hibernate_Restore_Plan_V2.md`  
**JSC root cause:** `UNKNOWN`

## Authorization

Phase 1 product implementation is complete on PR #170. The CI routing corrective in PR #171 is merged and proved the dedicated FloatTabs self-hosted runner path.

PR #170 is reconciled with current `main` without changing the already-validated Phase 1 product/test content. The current task is verification only: required repository-host CI on the literal reconciled head, then independent web audit. Do not expand product scope.

## Phase 1 production scope — frozen

Authorized product files:

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

Only normal eligible inactive lifecycle reclamation / the already-existing eligible critical-Warm pressure path uses hibernate.

Destructive release/rebuild/reset/delete/Profile/cache/recovery paths remain destructive and clear pending restore state.

## Restore contract — frozen

Use public `WKWebView.interactionState` only.

- memory-local only;
- opaque, no assumed serialized schema;
- never log/persist contents;
- validate Slot/Profile/effective-rendering/current-URL compatibility before replay;
- compatible restore constructs the fresh Runtime and all sidecars first, then assigns interaction state;
- compatible restore must not issue the ordinary initial URL load;
- missing/incompatible state uses the existing safe currentURL/home fallback;
- arbitrary timer/double-navigation/private-API workarounds are not authorized.

## Deterministic teardown contract — frozen

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

Stale callbacks from the old Runtime must not mutate the new Runtime.

## Authorized tests

- `FloatTabsTests/WebViewPoolTests.swift`
- `FloatTabsTests/WebAttentionLifecycleTests.swift`
- `FloatTabsTests/WebFocusAdapterTests.swift` only if required for the narrow existing observer fixture

Required coverage includes compatible restore without duplicate initial load, fallback, destructive release clearing restore state, Profile/rendering mismatch invalidation, same-Profile sibling isolation, deterministic teardown, stale callback rejection, fresh Runtime identity, eligible lifecycle/critical-Warm hibernate, and unchanged active/fullscreen/supplemental/media/Attention/Generating/Ready protection.

## Current evidence

```text
PR=#170 OPEN / UNMERGED
MAIN_AFTER_CI_CORRECTIVE=ce92f99777507dd03a2e7267c33607fe5aea4c56
RUNNER_CORRECTIVE_PR=#171 MERGED
RUNNER=macmini-floattabs-01
RUNNER_LABELS=self-hosted,macOS,ARM64,mac-mini-ci
RUNNER_CORRECTIVE_RUN=41255270977 PASS

focused tests: 146 executed / 0 failures
full tests: 1073 executed / 3 skipped / 0 failures
Debug build: PASS
Release build: PASS
bounded live smoke: 2 existing Slots; resident drop and interactionState restore observed
strict 1/2/4/8 benchmark: NOT RUN / DEFERRED TO PHASE 4
required PR CI on reconciled head: PENDING
```

The earlier zero-run state on PR #170 was caused by its merge conflict with `main`; it was not evidence that the local runner was offline. The dedicated runner is now registered, online, and has already successfully executed the exact CI workflow on PR #171.

## Phase 1 verification gate — current

Required before merge:

1. focused lifecycle regression tests pass;
2. full unit suite has no new Phase 1 failures;
3. Debug build passes;
4. Release build passes;
5. bounded 1–2 existing-Slot live Runtime smoke remains accepted evidence for the unchanged implementation content;
6. required GitHub `Build & Test (Apple Silicon arm64)` passes on the literal reconciled PR #170 head on the dedicated self-hosted runner;
7. independent web audit passes.

If the reconciliation changes any of the five authorized product/test blobs, prior implementation evidence no longer transfers automatically; STOP and investigate. Control/workflow-only ancestry changes do not by themselves invalidate the unchanged product implementation evidence, but exact-head CI is still required.

## Deferred to Phase 4 — not blockers

Do not block Phase 1 on:

- strict `1 / 2 / 4 / 8` loaded-Slot matrix;
- >=9 configured-Slot fixture;
- heavy 4/8 repeated runs;
- no-op/control drift study;
- `median reclaimed > 2× drift` threshold;
- final process-tree memory curve;
- final restore p50/p95 policy threshold;
- Runtime budget/ranking selection.

## STOP conditions

STOP if:

- reconciled PR #170 product/test blobs differ from the validated implementation unexpectedly;
- required CI fails due to Phase 1 product behavior;
- old WebView remains strongly reachable after deterministic teardown;
- Profile/session/user-data safety requires a behavior/schema change;
- public interactionState requires arbitrary timer/double-navigation/private API behavior;
- stale old-Runtime callbacks can mutate the restored Runtime;
- destructive paths accidentally retain/replay hibernate state;
- proven Download/Fullscreen/Focus/Panel ownership requires new cross-domain semantics;
- overlapping unique work appears.

Do not STOP merely because strict scale benchmarking is deferred.

## Required next outcome

1. allow required self-hosted CI to run on reconciled PR #170 literal head;
2. verify runner identity, arm64, Debug, Release, native architecture and unit tests;
3. if CI passes, stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT` without modifying product code;
4. independent web audit then evaluates exact diff, Authority, CI, runtime evidence, Browser Profile/session safety and mergeability;
5. do not merge or release Phase 1 product code before that audit passes.

Production release remains unauthorized.
