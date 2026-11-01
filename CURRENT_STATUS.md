# FloatTabs Current Status

**Status date:** `2026-11-01`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 4 REFERENCE-DERIVED AUTOMATIC RUNTIME MANAGEMENT**

Current program/task: `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

Current execution state: `WAITING_FOR_PHASE_4_MERGE_GATE`.

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
PHASE_4_IMPLEMENTATION=COMPLETE / PR #181 OPEN
PHASE_4_IMPLEMENTATION_SEMANTIC_HEAD=ce0231628a976ad41afba1e78ef1b0726212f95e
PHASE_4_POLICY_SOURCE=REFERENCE_DERIVED / CHROMIUM-LIKE LIFECYCLE PRINCIPLES
PHASE_4_EMPIRICAL_TUNING=DEFERRED
PHASE_4_REQUIRED_CI_ON_IMPLEMENTATION_HEAD=PASS / RUN 1282
PHASE_4_QA_DMG_ON_IMPLEMENTATION_HEAD=PASS / RUN 621
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

## Delivered Phase 4 behavior

- Hot remains an explicit user pin and is excluded from automatic budget eviction.
- Warm/Cold are automatically managed.
- Active/presented, fullscreen, supplemental-visible, media-protected and Attention `generating` Runtime are hard protected.
- Media-query windows are conservatively protected so an async playback check cannot race budget eviction.
- Attention `ready`, durable unread and native notification do not protect Runtime.
- Candidate order: `Cold → Warm`, then older `lastUsedAt`, then UUID lexical tie-break.
- Normal/warning policy uses a conservative default managed resident target of **3 Warm/Cold runtimes**. This is an initial product assumption, not measured truth.
- Critical memory pressure uses target `0` for eligible inactive Warm/Cold runtimes.
- Existing Warm/Cold timers remain maximum retention boundaries; budget pressure may reclaim an eligible inactive Runtime earlier.
- Hot or hard-protected runtimes may oversubscribe the managed target; user intent and visible work win over the target.
- Runtime reclamation still uses the existing `WebViewPool.hibernate` boundary; Browser Profile/session/persistence semantics are unchanged.

## Verification evidence

Implementation semantic head `ce0231628a976ad41afba1e78ef1b0726212f95e` passed:

- Debug arm64 build;
- Release arm64 build;
- native Release architecture verification;
- full existing XCTest suite;
- required `Build & Test (Apple Silicon arm64)` on `macmini-floattabs-01` — run `1282`;
- QA DMG — run `621`.

The first CI attempt exposed two stale memory-pressure diagnostic expectations. Compatibility was corrected without changing the new budget behavior; the next full XCTest run passed. A subsequent static lifecycle review found and corrected the pending-media-query eviction race before the final implementation evidence above.

Deferred to a later tuning pass:

- strict `1 / 2 / 4 / 8` scale matrix;
- no-op drift measurement;
- candidate `4 → 3 → 2` tuning tournament;
- restore latency median/p95 tuning evidence.

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

## Merge gate

PR #181 is the single Phase 4 implementation PR. This control-alignment commit is control-only drift after the verified implementation head; repository branch protection still requires the literal PR head to satisfy `Build & Test (Apple Silicon arm64)` before merge. GitHub's live PR/check state is authoritative for that final host gate.

## Next action

Do not mutate product code unless the final host gate exposes a real blocker. When the literal PR head is green and mergeable, Phase 4 is ready for merge. Do not release, bump version or begin Phase 5 in this task.