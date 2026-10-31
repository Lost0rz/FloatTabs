# FloatTabs Current Status

**Status date:** `2026-10-31`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 1 ARCHITECTURE-FIRST IMPLEMENTATION**

Current program/task: `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

Current execution state: `ACTIVE / PHASE 1 IMPLEMENTATION — V2 ACCEPTANCE`.

The program cadence has been intentionally refrozen: establish the Runtime lifecycle architecture first, prove bounded live correctness, merge the structural primitive, and defer strict multi-Slot scale/performance tuning to Phase 4 Runtime Budget / Policy.

## Canonical / current state

```text
MAIN_BEFORE_V2_REFREEZE=e5b1a14b45277ff2eb8d109bac606a536e7938cd
PRE_PROGRAM_PRODUCT_BASELINE=26d1669198a6f94faa769fb27d2cd00d0fcd1184
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
PRODUCT_MUTATION=AUTHORIZED_WITHIN_PHASE1_V2_SCOPE
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

V1 lifecycle contract/Phase 1 plan remain historical evidence for the original audit and benchmark rationale. They do not override V2's current phase gate.

## Phase 1 target

Implement and finish the structural split:

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

Only normal eligible inactive lifecycle reclamation, including the already-existing eligible critical-Warm path, uses hibernate.

All destructive callers remain destructive.

## Authorized production scope

- `FloatTabs/Web/WebViewPool.swift`
- `FloatTabs/Web/SlotLifecycleCoordinator.swift`
- `FloatTabs/Web/SlotNavigationObserver.swift`

## Authorized tests

- `FloatTabsTests/WebViewPoolTests.swift`
- `FloatTabsTests/WebAttentionLifecycleTests.swift`
- `FloatTabsTests/WebFocusAdapterTests.swift` only if needed for the narrow observer-invalidation fixture

Existing benchmark tooling may be preserved, but strict benchmark expansion is not required for Phase 1 completion.

## Current implementation evidence

Local executor reported before this V2 refreeze:

```text
FOCUSED_TESTS=174/174 PASS
FULL_TESTS=1073 executed / 3 skipped / 0 failures
DEBUG_BUILD=PASS
RELEASE_BUILD=PASS
STRICT_1_2_4_8_BENCHMARK=NOT_RUN
LOCAL_IMPLEMENTATION=DIRTY / UNCOMMITTED
PR=NONE
```

The strict benchmark did not run because the real configuration contains five Slots and the old 8-Slot matrix required at least nine configured Slots.

Under V2 this is no longer a Phase 1 blocker. Those test/build results remain prior evidence and must be refreshed as appropriate on the final committed diff.

## Phase 1 validation gate — current

Phase 1 merge readiness now requires:

1. exact hibernate vs destructive-release semantics remain correct;
2. deterministic teardown and stale-callback rejection remain correct;
3. Browser Profile / cookies / session / Slot configuration remain untouched;
4. focused regression tests pass;
5. full unit suite has no new Phase 1 failures;
6. Debug and Release builds pass;
7. bounded live 1–2 Slot Runtime smoke proves resident-count drop, fresh single Runtime restore, intact login/session/page/conversation, and no obvious competing double-load;
8. required GitHub `Build & Test (Apple Silicon arm64)` passes on the PR head;
9. independent web audit passes before merge.

The following are deferred to Phase 4 and are **not** Phase 1 merge blockers:

- strict `1 / 2 / 4 / 8` matrix;
- >=9 configured-Slot fixture;
- 4/8 heavy repeated runs;
- `median reclaimed > 2× control drift`;
- final memory curve / Runtime budget / ranking;
- scale restore p50/p95 policy thresholds.

## Key invariants

- Browser Profile / `WKWebsiteDataStore` identity and persistent session data remain independent from Runtime lifetime.
- `WKWebView.interactionState` remains opaque and memory-local; never persist or log contents.
- compatible interaction-state restore must not also issue a competing ordinary URL load.
- missing/incompatible state uses the existing currentURL/home fallback.
- deterministic teardown explicitly invalidates bridges/popup/navigation observer, clears delegates, calls `stopLoading()`, clears transient Pool state including pending termination incident context, and removes the old Runtime identity.
- restored Runtime receives a fresh Runtime generation/WebView instance identity.
- current active/fullscreen/supplemental-visible/media/Attention protection remains unchanged.
- current Generating/Ready protection remains unchanged in Phase 1.
- Cold website-cache cleanup semantics remain separate and unchanged.

## Explicit non-scope

Do not modify without STOP/reconciliation:

- Panel/Fullscreen/Focus product semantics;
- Browser Profile datastore behavior/schema;
- Attention Generating/Ready semantics;
- durable Unread semantics;
- completion notifications;
- Hot/Warm/Cold UI or timer values;
- automatic Runtime Budget/ranking;
- Website Cache policy/data types;
- process-pool topology;
- server Push/service-worker behavior;
- native conversation preview.

## Execution / handoff state

The next action is to continue the existing local Phase 1 implementation, not restart it.

The local executor must:

- preserve the current dirty implementation and unknown local work;
- refresh and read V2 Authority;
- inspect the existing diff against the V2 boundary;
- correct only real mismatches;
- rerun focused/full verification and Debug/Release builds on the final diff;
- perform the bounded 1–2 Slot live Runtime smoke;
- commit + push one Phase 1 implementation branch and open/update one PR;
- stop for independent web audit.

Do not create temporary production Slots solely to satisfy the former V1 benchmark matrix.

Merge and release are not authorized by the construction handoff.

## Non-claims

- Historical JSC root cause remains `UNKNOWN`.
- No final Runtime Budget number is accepted yet.
- No large-scale memory curve is accepted yet.
- No claim is made that ChatGPT generation survives WebView destruction.
- No newer public release is authorized.
