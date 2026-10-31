# FloatTabs Current Status

**Status date:** `2026-10-31`
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 1 IMPLEMENTATION AUTHORIZED**

Current program/task: `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

Current execution state: `ACTIVE / PHASE 1 IMPLEMENTATION`.

The Phase 1 focused audit and implementation-plan freeze are complete. Product mutation is now authorized only within the exact Phase 1 scope defined below and in the frozen Phase 1 plan.

## Canonical / current state

```text
MAIN_AFTER_PHASE1_PLAN=672f7122f352f6cfb1704109db6488519480c628
PHASE_1_AUDIT_BASE=1ba0ec7fe70c3d8a6fd42d586dcc813ed87d9088
PRE_PROGRAM_PRODUCT_BASELINE=26d1669198a6f94faa769fb27d2cd00d0fcd1184
PR_162=MERGED
JSC_ROOT_CAUSE=UNKNOWN
JSC_CRASH_ELIMINATED=NOT_CLAIMED
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26

ACTIVE_PROGRAM=FT-RUNTIME-LIFECYCLE-MEMORY-001
PHASE_0_CONTRACT_FREEZE=COMPLETE
HISTORICAL_DOC_GATE=COMPLETE
PHASE_1_FOCUSED_AUDIT=COMPLETE
PHASE_1_PLAN_PR=#167 MERGED
PHASE_1_PLAN_PR_HEAD=77508a34bf800199b55c78586c98cf132d4d8bca
PHASE_1_PLAN_MERGE=672f7122f352f6cfb1704109db6488519480c628
PHASE_1_PLAN_REQUIRED_CI_RUN=41209314609 PASS
CURRENT_PHASE=PHASE_1_SAFE_HIBERNATE_RESTORE_IMPLEMENTATION
PRODUCT_MUTATION=AUTHORIZED_WITHIN_FROZEN_PHASE1_SCOPE
```

## Current Authority

Read in this order:

```text
AGENTS.md
→ CURRENT_STATUS.md
→ CURRENT_TASK.md
→ docs/README.md
→ docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md
→ docs/architecture/FloatTabs_Runtime_Lifecycle_Phase1_Safe_Hibernate_Restore_Plan_V1.md
→ docs/architecture/DOMAIN_MAP.md for navigation
→ current source/tests/fresh evidence
```

## Phase 1 implementation target

Implement a safe semantic split:

```text
hibernate(slotID:)
  capture compatible opaque WKWebView interaction state
  → deterministic teardown
  → keep one memory-local restore snapshot

release(slotID:)
  clear pending restore state
  → deterministic destructive teardown
```

Only normal eligible inactive lifecycle reclamation, including eligible critical Warm memory pressure, switches to hibernate.

All destructive callers remain destructive.

## Authorized production files

- `FloatTabs/Web/WebViewPool.swift`
- `FloatTabs/Web/SlotLifecycleCoordinator.swift`
- `FloatTabs/Web/SlotNavigationObserver.swift`

## Authorized tests / benchmark tooling

- `FloatTabsTests/WebViewPoolTests.swift`
- `FloatTabsTests/WebAttentionLifecycleTests.swift`
- `FloatTabsTests/WebFocusAdapterTests.swift` only if needed for the narrow observer invalidation fixture
- `tools/benchmark/floattabs_lifecycle_benchmark.py` only if Phase 1 matrix/reporting needs adaptation
- `tools/benchmark/README.md` only for the Phase 1 runbook

Control/design documents may be updated only for factual progress/evidence.

## Key invariants

- Browser Profile / `WKWebsiteDataStore` identity and persistent session data remain independent from Runtime lifetime.
- `WKWebView.interactionState` remains opaque and memory-local; never persist or log contents.
- compatible interaction-state restore must not also issue a competing ordinary URL load.
- missing/incompatible state uses the existing currentURL/home fallback.
- deterministic teardown explicitly invalidates bridges/popup/navigation observer, clears delegates, calls `stopLoading()`, clears transient Pool state including pending termination incident context, and removes the old runtime identity.
- restored Runtime receives a fresh runtime generation/WebView instance identity.
- current active/fullscreen/supplemental-visible/media/Attention protection remains unchanged.
- current Generating/Ready protection remains unchanged in Phase 1.
- Cold website-cache cleanup semantics remain separate and unchanged.

## Phase 1 validation gate

Implementation is not accepted merely because tests compile.

Required evidence includes:

1. focused regression tests for hibernate/restore, destructive release, compatibility invalidation, teardown and stale callbacks;
2. existing Browser Profile/Attention/lifecycle/diagnostics/build suites remain green;
3. controlled 1/2/4/8 Slot runtime benchmark using existing Debug lifecycle tooling;
4. primary memory evidence uses Warm release to avoid Cold cache-cleanup confounding;
5. resident runtime count drops exactly for eligible hibernated Slots;
6. protected/visible runtimes remain resident;
7. heavy 4/8 scenario process-tree reclaimed-memory signal is positive/repeatable and median exceeds `2×` same-family no-op/control drift;
8. paired compatible interaction-state restore does not regress median versus URL fallback by more than `max(20%, 300 ms)`;
9. manual macOS acceptance preserves Profile login/session, same conversation, sane history/scroll/form state, no visible double-load, and no focus/fullscreen regression.

If logical residency falls but memory stays within control noise, verdict is `FAIL / UNKNOWN` and Phase 2+ does not begin.

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

The next action is local Phase 1 implementation using one concise construction card that references the frozen Phase 1 plan rather than duplicating it.

The executor must:

- verify fresh `origin/main` and task authority before mutation;
- preserve one canonical writer;
- stop on any frozen STOP condition;
- implement/tests/benchmark within scope;
- commit and push the Phase 1 branch/PR;
- stop at `WAITING_FOR_INDEPENDENT_WEB_AUDIT`.

Merge and release are not authorized by the construction card.

## Non-claims

- Historical JSC root cause remains `UNKNOWN`.
- No Runtime Budget number is accepted yet.
- No claim is made that ChatGPT generation survives WebView destruction.
- No newer public release is authorized.
