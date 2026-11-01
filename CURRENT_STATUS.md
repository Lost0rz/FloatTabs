# FloatTabs Current Status

**Status date:** `2026-11-01`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 1 IMPLEMENTATION PR CI**

Current program/task: `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

Current execution state: `WAITING / REQUIRED PR CI ON RECONCILED PHASE 1 IMPLEMENTATION`.

The Phase 1 cadence remains architecture-first: finish the structural Runtime hibernate/restore primitive, prove bounded real-runtime correctness, merge the structural primitive, and defer strict multi-Slot scale/performance tuning to Phase 4 Runtime Budget / Policy.

## Canonical / current state

```text
MAIN_AFTER_CI_RUNNER_CORRECTIVE=ce92f99777507dd03a2e7267c33607fe5aea4c56
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
JSC_ROOT_CAUSE=UNKNOWN
JSC_CRASH_ELIMINATED=NOT_CLAIMED

ACTIVE_PROGRAM=FT-RUNTIME-LIFECYCLE-MEMORY-001
PHASE_0_CONTRACT_FREEZE=COMPLETE
HISTORICAL_DOC_GATE=COMPLETE
PHASE_1_FOCUSED_AUDIT=COMPLETE
PHASE_1_V1_PLAN=SUPERSEDED_FOR_CURRENT_EXECUTION
PHASE_1_V2_CONTRACT=ACCEPTED_FROZEN
PHASE_1_V2_PLAN=ACCEPTED_FROZEN
CURRENT_PHASE=PHASE_1_SAFE_HIBERNATE_RESTORE_IMPLEMENTATION
PHASE_1_IMPLEMENTATION_PR=#170 OPEN / UNMERGED
CI_RUNNER_CORRECTIVE_PR=#171 MERGED
CI_RUNNER=macmini-floattabs-01 / self-hosted / macOS / ARM64 / mac-mini-ci
CI_RUNNER_CORRECTIVE_RUN=41255270977 PASS
PHASE_1_REQUIRED_PR_CI=PENDING_ON_RECONCILED_LITERAL_HEAD
STRICT_SCALE_BENCHMARK=DEFERRED_TO_PHASE_4
```

## Current Authority

Read in this order:

```text
AGENTS.md
→ CURRENT_STATUS.md
→ CURRENT_TASK.md
→ docs/README.md
→ docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V2.md
→ docs/architecture/FloatTabs_Runtime_Lifecycle_Phase1_Safe_Hibernate_Restore_Plan_V2.md
→ docs/architecture/DOMAIN_MAP.md for navigation
→ current source/tests/fresh evidence
```

V1 lifecycle contract/Phase 1 plan remain historical evidence only and do not override V2.

## Phase 1 target

```text
hibernate(slotID:)
  capture compatible opaque WKWebView interaction state when available
  → deterministic teardown
  → retain one memory-local restore snapshot
  → Runtime becomes non-resident

release(slotID:)
  clear pending restore state
  → deterministic destructive teardown
  → Runtime becomes non-resident
```

Only normal eligible inactive lifecycle reclamation, including the already-existing eligible critical-Warm path, uses hibernate. All destructive callers remain destructive.

## Authorized production scope

- `FloatTabs/Web/WebViewPool.swift`
- `FloatTabs/Web/SlotLifecycleCoordinator.swift`
- `FloatTabs/Web/SlotNavigationObserver.swift`

## Authorized tests

- `FloatTabsTests/WebViewPoolTests.swift`
- `FloatTabsTests/WebAttentionLifecycleTests.swift`
- `FloatTabsTests/WebFocusAdapterTests.swift` only if needed for the narrow observer-invalidation fixture

## Current implementation evidence

PR #170 implementation evidence before repository-host CI:

```text
FOCUSED_TESTS=146 executed / 0 failures
FULL_TESTS=1073 executed / 3 skipped / 0 failures
DEBUG_BUILD=PASS
RELEASE_BUILD=PASS
STRICT_1_2_4_8_BENCHMARK=NOT_RUN / DEFERRED_TO_PHASE_4
LIVE_SMOKE=bounded 2 existing Slots; resident drop, fresh Runtime identity, interactionState restore observed
PROFILE_IDENTITY=default preserved
SESSION_STORE_MUTATION=NONE OBSERVED
DOUBLE_LOAD=NO COMPETING ORDINARY LOAD OBSERVED
```

The earlier PR #170 no-run condition was infrastructure, not a product test failure: the PR conflicted with `main`, so GitHub did not create a pull-request workflow run. PR #171 corrected FloatTabs CI to the dedicated local self-hosted runner and proved that route with run `41255270977`, job `124696994671`, runner `macmini-floattabs-01`, arm64, all steps passing.

PR #170 has now been reconciled onto current `main` while preserving the validated Phase 1 production/test blobs. The next gate is required GitHub `Build & Test (Apple Silicon arm64)` on the literal reconciled PR head.

## Phase 1 validation gate — current

Required before merge:

1. exact hibernate vs destructive-release semantics remain correct;
2. deterministic teardown and stale-callback rejection remain correct;
3. Browser Profile / cookies / session / Slot configuration remain untouched;
4. focused regression tests pass;
5. full unit suite has no new Phase 1 failures;
6. Debug and Release builds pass;
7. bounded live 1–2 Slot Runtime smoke proves resident-count drop, fresh single Runtime restore, intact page/conversation/session behavior to the extent observable, and no obvious competing double-load;
8. required GitHub `Build & Test (Apple Silicon arm64)` passes on the literal reconciled PR head using the dedicated self-hosted runner;
9. independent web audit passes before merge.

Deferred to Phase 4 and not Phase 1 blockers:

- strict `1 / 2 / 4 / 8` matrix;
- >=9 configured-Slot fixture;
- heavy 4/8 repeated runs;
- no-op/control drift study;
- `median reclaimed > 2× drift` threshold;
- final process-tree memory curve;
- final restore p50/p95 policy threshold;
- Runtime budget/ranking selection.

## Key invariants

- Browser Profile / `WKWebsiteDataStore` identity and persistent session data remain independent from Runtime lifetime.
- `WKWebView.interactionState` remains opaque and memory-local; never persist or log contents.
- compatible interaction-state restore must not also issue a competing ordinary URL load.
- missing/incompatible state uses the existing safe currentURL/home fallback.
- deterministic teardown invalidates bridges/popup/navigation observer, clears delegates, calls `stopLoading()`, clears transient Pool state including pending termination incident context, and removes the old Runtime identity.
- restored Runtime receives a fresh Runtime generation/WebView instance identity.
- current active/fullscreen/supplemental-visible/media/Attention protection remains unchanged.
- current Generating/Ready protection remains unchanged in Phase 1.
- Cold website-cache cleanup semantics remain separate and unchanged.

## Execution / handoff state

Current action:

```text
PR #170 reconciled with current main
→ required self-hosted PR CI
→ independent web audit
→ merge decision
```

Do not merge or release Phase 1 product code before the required CI and independent web audit pass.

## Non-claims

- Historical JSC root cause remains `UNKNOWN`.
- No final Runtime Budget number is accepted yet.
- No large-scale memory curve is accepted yet.
- No claim is made that ChatGPT generation survives WebView destruction.
- No newer public release is authorized.
