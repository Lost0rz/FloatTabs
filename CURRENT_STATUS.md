# FloatTabs Current Status

**Status date:** `2026-11-01`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 4 COMPLETE / MERGED**

Current program/task: `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

Current execution state: `PHASE_4_MERGED / READY_FOR_NEXT_AUTHORIZED_WORK`.

## Canonical state

```text
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
JSC_ROOT_CAUSE=UNKNOWN

PHASE_1_SAFE_HIBERNATE_RESTORE=COMPLETE
PHASE_2_READY_UNREAD_DECOUPLING=COMPLETE / MERGED
PHASE_3_NATIVE_COMPLETION_NOTIFICATION=COMPLETE / MERGED
PHASE_4_REFERENCE_DERIVED_RUNTIME_MANAGEMENT=COMPLETE / MERGED
PHASE_4_PR=#181
PHASE_4_MERGE_COMMIT=c910441a954bddbaeca710395cd0d6ed89ec5e5c
PHASE_4_FINAL_PR_HEAD=70584485b7a0444aba3df0ea5e4613681b6e5a14
PHASE_4_REQUIRED_CI=PASS / RUN 1283
PHASE_4_QA_DMG=PASS / RUN 622
PHASE_4_EMPIRICAL_TUNING=DEFERRED
PHASE_5=NOT_STARTED / NOT_AUTHORIZED
PHASE_6=NOT_STARTED / NOT_AUTHORIZED
CI_RUNNER=macmini-floattabs-01 / self-hosted / macOS / ARM64 / mac-mini-ci
```

## Delivered Phase 4 behavior

- Hot remains an explicit user pin and is excluded from automatic budget eviction.
- Warm/Cold are automatically managed.
- Active/presented, fullscreen, supplemental-visible, media-protected, media-query-pending and Attention `generating` Runtime are hard protected.
- Attention `ready`, durable unread and native notification do not protect Runtime.
- Candidate order: `Cold → Warm`, then older `lastUsedAt`, then UUID lexical tie-break.
- Normal/warning managed target currently defaults to **3 resident Warm/Cold runtimes** as a reference-derived initial product assumption, not measured truth.
- Critical memory pressure targets `0` eligible inactive Warm/Cold runtimes.
- Existing Warm/Cold timers remain maximum retention boundaries; budget pressure may reclaim eligible inactive Runtime earlier.
- Runtime reclamation continues to use the existing `WebViewPool.hibernate` boundary; Browser Profile/session/persistence semantics are unchanged.

## Verification evidence

Final literal PR head `70584485b7a0444aba3df0ea5e4613681b6e5a14` passed:

- Debug arm64 build;
- Release arm64 build;
- native Release architecture verification;
- full existing XCTest suite;
- required `Build & Test (Apple Silicon arm64)` on `macmini-floattabs-01` — run `1283`;
- QA DMG — run `622`.

PR #181 was squash-merged to `main` as `c910441a954bddbaeca710395cd0d6ed89ec5e5c`.

## Deferred tuning direction

Phase 4 deliberately did not freeze machine-specific performance thresholds from a one-time benchmark.

Future performance tuning should prefer a Settings-backed configuration model with conservative defaults and machine/user-specific override rather than hard-coding one universal value. Exact UI, ranges, presets and persistence semantics require a separately authorized design/implementation task.

Safety boundaries remain non-negotiable configuration constraints: settings must not enable automatic eviction of Hot, active/presented, fullscreen, media-protected or Attention `generating` Runtime.

## Current Authority

```text
AGENTS.md
→ CURRENT_STATUS.md
→ CURRENT_TASK.md
→ docs/architecture/README.md
→ docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V3.md
→ docs/architecture/DOMAIN_MAP.md
→ current production source/tests/fresh evidence
```

## Next action

Phase 4 is complete. Do not begin Phase 5/6 or implement the future performance-settings surface without a new authorized task/scope reconciliation.
