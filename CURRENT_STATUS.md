# FloatTabs Current Status

**Status date:** `2026-11-01`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 4 REFERENCE-DERIVED AUTOMATIC RUNTIME MANAGEMENT**

Current program/task: `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

Current execution state: `ACTIVE / PHASE 4 IMPLEMENTATION AUTHORIZED — RECONCILED 2026-11-01`.

## Canonical state

```text
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
JSC_ROOT_CAUSE=UNKNOWN

PHASE_1_SAFE_HIBERNATE_RESTORE=COMPLETE
PHASE_2_READY_UNREAD_DECOUPLING=COMPLETE / MERGED
PHASE_3_NATIVE_COMPLETION_NOTIFICATION=COMPLETE / MERGED
PHASE_4_FOCUSED_AUDIT=COMPLETE
PHASE_4_PLAN_V1=HISTORICAL / SUPERSEDED FOR TUNING GATE ONLY
PHASE_4_IMPLEMENTATION=AUTHORIZED
PHASE_4_POLICY_SOURCE=REFERENCE_DERIVED / CHROMIUM-LIKE LIFECYCLE PRINCIPLES
PHASE_4_EMPIRICAL_TUNING=DEFERRED
PHASE_5=NOT_STARTED / NOT_AUTHORIZED
PHASE_6=NOT_STARTED / NOT_AUTHORIZED
CI_RUNNER=macmini-floattabs-01 / self-hosted / macOS / ARM64 / mac-mini-ci
```

## Reconciled Phase 4 decision

The user explicitly changed Phase 4 sequencing on 2026-11-01:

- do **not** block implementation on the Real-Mac `1 / 2 / 4 / 8` budget-selection benchmark;
- derive the first production policy from mature browser lifecycle mechanisms;
- ship a conservative default first, then tune thresholds with real measurements later;
- keep correctness, data safety and required repository CI as merge gates.

The architecture mapping is:

```text
Chromium-style lifecycle principles
(active/pinned/audible protected, inactive recency ranking, proactive discard,
stronger pressure response, reload/materialize on activation)
→ FloatTabs existing ownership
(Hot pin + visible/fullscreen/media/generating protection + lastUsedAt LRU)
→ SlotLifecycleCoordinator remains sole runtime lifecycle writer
→ WebViewPool remains hibernate/restore mechanism owner
```

This is a mechanism reference, not a claim that Chromium uses FloatTabs' exact numeric thresholds.

## Phase 4 product policy

- Hot remains an explicit user pin and is excluded from automatic budget eviction.
- Warm/Cold are automatically managed.
- Active/presented, fullscreen, supplemental-visible, media-protected and Attention `generating` Runtime are hard protected.
- Attention `ready`, durable unread and native notification do not protect Runtime.
- Candidate order: `Cold → Warm`, then older `lastUsedAt`, then UUID lexical tie-break.
- Normal/warning policy uses a conservative default managed resident target of **3 Warm/Cold runtimes**. This is an initial product assumption, not measured truth.
- Critical memory pressure uses target `0` for eligible inactive Warm/Cold runtimes.
- Existing Warm/Cold timers remain maximum retention boundaries; budget pressure may reclaim an eligible inactive Runtime earlier.
- Hot or hard-protected runtimes may oversubscribe the managed target; user intent and visible work win over the target.

## Verification boundary

Deferred to a later tuning pass:

- strict `1 / 2 / 4 / 8` scale matrix;
- no-op drift measurement;
- candidate `4 → 3 → 2` tuning tournament;
- restore latency median/p95 tuning evidence.

Still required before merge:

- exact scope/data-safety review;
- compilation/full existing repository test suite through the required self-hosted `Build & Test (Apple Silicon arm64)` check;
- PR mergeable with no required host blocker.

No release/version bump is authorized in Phase 4.

## Current Authority

```text
AGENTS.md
→ CURRENT_STATUS.md
→ CURRENT_TASK.md
→ docs/README.md
→ docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V3.md
→ current production source/tests/fresh evidence
```

The old Phase 4 V1 benchmark-selection plan remains historical rationale only where it conflicts with this reconciled task.

## Next action

Implement the reference-derived automatic Runtime policy on one branch/PR. Keep lifecycle ownership in `SlotLifecycleCoordinator`, preserve `WebViewPool` hibernate/restore semantics and all Browser Profile/session data. Stop at the Phase 4 merge gate after required CI; tuning remains a follow-up.