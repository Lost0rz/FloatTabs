# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Title:** Runtime Lifecycle / Memory redesign — Phase 1 Safe Hibernate + Restore  
**Status:** `ACTIVE / BLOCKING CI ROUTING CORRECTIVE`  
**Mode:** `EXECUTE`  
**Task class:** `HIGH-RISK WEB RUNTIME LIFECYCLE / MEMORY + BOUNDED CI INFRA CORRECTIVE`  
**Current program contract:** `docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V2.md`  
**Current Phase 1 plan:** `docs/architecture/FloatTabs_Runtime_Lifecycle_Phase1_Safe_Hibernate_Restore_Plan_V2.md`  
**JSC root cause:** `UNKNOWN`

## Authorization

The Phase 1 product implementation is complete on PR #170, but required repository-host CI did not start. A bounded CI routing corrective is authorized under the same task because it blocks the current Phase 1 acceptance gate.

Do not modify Phase 1 Web Runtime product behavior during this corrective.

Fresh diagnosis established:

- PR #170 head `b40bf1d63735700cb0c297d901bd284da1ac105a` is currently conflicting with `main`, so GitHub does not create `pull_request` workflow runs for it until the conflict is resolved;
- `.github/workflows/macos-ci.yml` uses `runs-on: macos-26`, which selects a GitHub-hosted macOS runner instead of the intended local Apple Silicon self-hosted runner;
- the established local runner labels are `[self-hosted, macOS, ARM64, mac-mini-ci]`;
- FloatTabs is public, so self-hosted CI must not execute arbitrary fork PR code by default.

## CI corrective scope

Authorized now:

- `AGENTS.md` — durable local-runner and PR-conflict CI rule;
- `CURRENT_STATUS.md` — factual corrective state;
- `CURRENT_TASK.md` — this bounded authorization;
- `.github/workflows/macos-ci.yml` — runner routing / same-repository PR guard only.

Expected workflow change:

```text
runs-on: macos-26
```

becomes:

```text
runs-on: [self-hosted, macOS, ARM64, mac-mini-ci]
```

and PR jobs must be guarded so fork heads do not execute on the self-hosted runner by default.

Do not rename the required job `Build & Test (Apple Silicon arm64)` because branch protection currently requires that exact check context.

Do not alter build/test commands merely to make the runner switch pass unless fresh evidence proves a host-compatibility correction is required; in that case STOP and reconcile before broadening the CI corrective.

## CI corrective verification

Required evidence before merging the CI corrective:

1. corrective diff contains no FloatTabs product source or product-test changes;
2. workflow syntax remains valid;
3. the corrective PR receives a `macOS CI` workflow run;
4. the required job remains named `Build & Test (Apple Silicon arm64)`;
5. observed job routing is to a matching self-hosted runner, not GitHub-hosted `macos-26`;
6. runner architecture remains `arm64`;
7. existing Debug build, Release build, native architecture verification and unit-test steps execute successfully;
8. if the job remains queued because no matching runner is available, STOP with repository runner registration/access as the remaining infrastructure blocker; do not silently fall back to GitHub-hosted CI.

## PR #170 reconciliation after CI corrective

After the CI corrective is merged:

1. refresh `main`;
2. reconcile PR #170 onto current `main` while preserving its already-validated Phase 1 implementation;
3. resolve control-file conflicts in favor of current Authority plus accurate PR #170 implementation evidence;
4. do not discard/rewrite valid Web Runtime implementation merely to resolve history;
5. confirm PR #170 becomes mergeable;
6. required `Build & Test (Apple Silicon arm64)` must then run on the local self-hosted runner for the literal reconciled PR head;
7. only after that required check succeeds may the independent web audit produce a merge-readiness verdict.

## Phase 1 product scope — unchanged

Authorized product files remain:

- `FloatTabs/Web/WebViewPool.swift`
- `FloatTabs/Web/SlotLifecycleCoordinator.swift`
- `FloatTabs/Web/SlotNavigationObserver.swift`

Expected behavior remains:

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

## Restore contract — unchanged

Use public `WKWebView.interactionState` only.

- memory-local only;
- opaque, no assumed serialized schema;
- never log/persist contents;
- validate Slot/Profile/effective-rendering/current-URL compatibility before replay;
- compatible restore constructs the fresh Runtime and all sidecars first, then assigns interaction state;
- compatible restore must not issue the ordinary initial URL load;
- missing/incompatible state uses the existing safe currentURL/home fallback;
- arbitrary timer/double-navigation/private-API workarounds are not authorized.

## Deterministic teardown contract — unchanged

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

## Current Phase 1 evidence

PR #170 currently reports:

```text
focused tests: 146 executed / 0 failures
full tests: 1073 executed / 3 skipped / 0 failures
Debug build: PASS
Release build: PASS
bounded live smoke: 2 existing Slots; resident drop and interactionState restore observed
strict 1/2/4/8 benchmark: NOT RUN / DEFERRED TO PHASE 4
PR: #170 OPEN
PR head: b40bf1d63735700cb0c297d901bd284da1ac105a
required PR CI: NO RUN CREATED
mergeability: CONFLICTING
```

These remain implementation evidence but cannot satisfy the repository-host gate until PR #170 is reconciled with current `main` and the required check runs on the literal reconciled head.

## Phase 1 verification gate — unchanged

Required before Phase 1 merge:

1. focused lifecycle regression tests pass;
2. full unit suite has no new Phase 1 failures;
3. Debug build passes;
4. Release build passes;
5. bounded 1–2 existing-Slot live Runtime smoke passes;
6. required GitHub `Build & Test (Apple Silicon arm64)` passes on the literal PR head;
7. independent web audit passes.

## Deferred to Phase 4 — unchanged

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

STOP and reconcile if:

- the CI corrective requires changing product source/tests;
- the required check name would change and no branch-protection reconciliation is authorized;
- no self-hosted runner matching `[self-hosted, macOS, ARM64, mac-mini-ci]` is available to FloatTabs after the corrective workflow is triggered;
- the self-hosted runner is not arm64;
- CI failure establishes an environment/toolchain incompatibility requiring broader runner bootstrap changes;
- PR #170 reconciliation would discard or rewrite unknown unique product work;
- any existing Phase 1 V2 STOP condition fires.

Do not treat `workflow runs = 0` on a conflicting PR as proof that the self-hosted runner is offline.

## Required executor outcome

For the CI corrective:

1. change only the authorized control/workflow files;
2. push one corrective branch/PR;
3. observe actual workflow creation and runner assignment;
4. if required check passes on the self-hosted runner, merge the CI corrective;
5. reconcile PR #170 with the new `main`;
6. allow required Phase 1 PR CI to run;
7. stop for independent web audit;
8. do not merge or release Phase 1 product code without that audit.

Production release remains unauthorized.
