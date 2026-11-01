# FloatTabs Current Status

**Status date:** `2026-11-01`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 5 BACKGROUND GENERATION THRIFT**

Current program/task: `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

Current execution state: `WAITING_FOR_PHASE_5_MERGE_GATE`.

## Canonical state

```text
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
JSC_ROOT_CAUSE=UNKNOWN

PHASE_1_SAFE_HIBERNATE_RESTORE=COMPLETE
PHASE_2_READY_UNREAD_DECOUPLING=COMPLETE / MERGED
PHASE_3_NATIVE_COMPLETION_NOTIFICATION=COMPLETE / MERGED
PHASE_4_REFERENCE_DERIVED_RUNTIME_MANAGEMENT=COMPLETE / MERGED
PHASE_4_MERGE_COMMIT=c910441a954bddbaeca710395cd0d6ed89ec5e5c
PHASE_4_EMPIRICAL_TUNING=DEFERRED / FUTURE SETTINGS-BACKED TUNING
PHASE_5_IMPLEMENTATION=COMPLETE / PR #183 OPEN / MERGE GATE
PHASE_5_IMPLEMENTATION_SEMANTIC_HEAD=e36589d4729f86b2e76609bcb699107e50f63919
PHASE_5_REQUIRED_CI_ON_SEMANTIC_HEAD=PASS / RUN 1287
PHASE_5_QA_DMG_ON_SEMANTIC_HEAD=PASS / RUN 623
PHASE_6=NOT_STARTED / NOT_AUTHORIZED
PROGRAM_HUMAN_ACCEPTANCE=PENDING
CI_RUNNER=macmini-floattabs-01 / self-hosted / macOS / ARM64 / mac-mini-ci
```

## Authority/document reconciliation

The stale Runtime Lifecycle document routing has been corrected on PR #183:

- `FloatTabs_Runtime_Lifecycle_Memory_Contract_V4.md` is the current accepted program contract;
- the former V3 Phase 4 strict `1 / 2 / 4 / 8` benchmark-selection gate is historical/deferred tuning rather than current Phase 4 correctness authority;
- `docs/README.md` and `docs/architecture/README.md` now route to V4 and the active Phase 5 plan;
- `DOMAIN_MAP.md` now reflects actual delivered source ownership, including the Phase 4 private `RuntimeBudgetPolicy` inside `SlotLifecycleCoordinator.swift`;
- old contracts/plans remain historical evidence and were not rewritten to pretend they were current.

## Delivered Phase 5 behavior

Focused audit identified the fixed native liveness-watchdog cadence as the smallest safe FloatTabs-owned optimization boundary. The primary page detector remains event-driven/mutation-coalesced and is not replaced with polling.

Delivered policy:

```text
page visible / visibility unknown
→ 2s liveness-watchdog cadence

page hidden + generation age < 30s
→ 2s cadence

page hidden + generation age >= 30s
→ 5s cadence

first liveness probe says not-generating
→ existing 250ms confirmation
→ second current-context false required before synthetic finish
```

`document.visibilityState` is local bridge scheduling metadata only. `PanelController` remains canonical product/presentation visibility authority.

The implementation preserves:

- `WebAttentionCoordinator` as Attention authority;
- `generating` as Runtime-protecting for the full generation;
- `SlotLifecycleCoordinator` as sole Runtime lifecycle executor;
- `WebViewPool` hibernate/restore semantics;
- natural completion and existing token/document/runtime stale-callback guards;
- Browser Profile/session/configuration/persistence boundaries.

The 30s/5s values are conservative engineering defaults, not measured optimum. Later machine/user tuning remains a separately authorized Settings-backed performance task.

## Verification evidence

Semantic implementation head `e36589d4729f86b2e76609bcb699107e50f63919` passed:

- Debug arm64 build;
- Release arm64 build;
- native Release architecture verification;
- full existing XCTest suite including focused Phase 5 cadence/probe coverage;
- required `Build & Test (Apple Silicon arm64)` on `macmini-floattabs-01` — run `1287`;
- QA DMG — run `623`;
- final diff/scope review: only 9 expected control/docs/source/test files; no `WebViewPool`, `SlotLifecycleCoordinator`, Browser Profile/session/persistence, release/version or Phase 6 mutation.

## Current authority

```text
AGENTS.md
→ CURRENT_STATUS.md
→ CURRENT_TASK.md
→ docs/README.md
→ docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V4.md
→ docs/architecture/FloatTabs_Runtime_Lifecycle_Phase5_Background_Generation_Thrift_Plan_V1.md
→ docs/architecture/DOMAIN_MAP.md
→ current production source/tests/fresh evidence
```

## Merge gate

PR #183 is the single Phase 5 delivery PR. This control-alignment commit is control-only drift after the verified semantic implementation head.

Before merge, the **literal current PR head** must still satisfy:

- required `Build & Test (Apple Silicon arm64)` PASS;
- clean/mergeable PR state;
- changed paths remain inside Phase 5/document-reconciliation scope;
- no ownership/data-safety/Phase 6/release drift.

## Next action

Run the literal-head merge gate. If green and mergeable, Phase 5 is ready for the user's next merge decision. Do not merge or begin Phase 6 without that authorization.