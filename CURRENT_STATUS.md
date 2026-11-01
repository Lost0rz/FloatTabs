# FloatTabs Current Status

**Status date:** `2026-11-01`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 1 COMPLETE**

Current program: `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

Current execution state: `PHASE 1 COMPLETE / WAITING FOR NEXT PHASE AUTHORIZATION`.

Phase 1 established the architecture-first Runtime lifecycle primitive: persistent Slot/Profile/product state is now separated from disposable `WKWebView` Runtime residency. Strict scale/performance tuning remains intentionally deferred to Phase 4.

## Canonical / current state

```text
MAIN_AFTER_PHASE_1=188c524fd02e1c31b8a152b2bec224c947526610
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
JSC_ROOT_CAUSE=UNKNOWN
JSC_CRASH_ELIMINATED=NOT_CLAIMED

ACTIVE_PROGRAM=FT-RUNTIME-LIFECYCLE-MEMORY-001
PHASE_0_CONTRACT_FREEZE=COMPLETE
HISTORICAL_DOC_GATE=COMPLETE
PHASE_1_FOCUSED_AUDIT=COMPLETE
PHASE_1_V2_CONTRACT=ACCEPTED_FROZEN
PHASE_1_V2_PLAN=ACCEPTED_FROZEN
PHASE_1_IMPLEMENTATION=COMPLETE
PHASE_1_IMPLEMENTATION_PR=#170 MERGED
PHASE_1_MERGE_COMMIT=188c524fd02e1c31b8a152b2bec224c947526610
CI_RUNNER_CORRECTIVE_PR=#171 MERGED
CI_RUNNER_CORRECTIVE_MERGE=ce92f99777507dd03a2e7267c33607fe5aea4c56
CI_RUNNER=macmini-floattabs-01 / self-hosted / macOS / ARM64 / mac-mini-ci
PHASE_1_REQUIRED_CI_RUN=41257207390 PASS
PHASE_1_REQUIRED_CI_JOB=124702806620 PASS
PHASE_1_INDEPENDENT_AUDIT=PASS_WITH_FOLLOWUPS
STRICT_SCALE_BENCHMARK=DEFERRED_TO_PHASE_4
PHASE_2=NOT_STARTED / NOT_AUTHORIZED
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
→ current source/tests/fresh runtime evidence
```

The V1 lifecycle contract and Phase 1 V1 plan remain historical evidence only.

## Phase 1 delivered architecture

```text
Persistent Slot / Browser Profile / product state
                    │
                    ▼
           memory-local restore snapshot
                    │
                    ▼
             WKWebView Runtime
                LIVE / NIL
```

Implemented semantic split:

```text
hibernate(slotID:)
  capture compatible opaque interaction state when available
  → deterministic teardown
  → retain at most one memory-local restore snapshot
  → Runtime becomes non-resident

release(slotID:)
  clear pending restore state
  → deterministic destructive teardown
  → Runtime becomes non-resident
```

Normal eligible inactive lifecycle reclamation, including the already-existing eligible critical-Warm path, uses `hibernate`. Destructive delete/reset/rebuild/Profile/cache/recovery paths remain destructive.

Compatible restore:

```text
resolve same Browser Profile data store
→ construct fresh Runtime + bridges/observer/popup/sidecars
→ assign fresh Runtime identity
→ apply WKWebView.interactionState
→ consume snapshot
```

The compatible interaction-state path does not also issue the ordinary initial URL load. Missing/incompatible state uses the existing safe URL fallback.

## Phase 1 evidence

Local/focused evidence on the validated implementation content:

```text
FOCUSED_TESTS=146 executed / 0 failures
FULL_TESTS=1073 executed / 3 skipped / 0 failures
DEBUG_BUILD=PASS
RELEASE_BUILD=PASS
LIVE_SMOKE=2 existing Slots; resident Runtime drop + fresh Runtime restore observed
PROFILE_IDENTITY=default preserved
SESSION_STORE_MUTATION=NONE OBSERVED
DOUBLE_LOAD=NO COMPETING ORDINARY LOAD OBSERVED
STRICT_1_2_4_8_BENCHMARK=NOT_RUN / DEFERRED_TO_PHASE_4
```

Repository-host gate on literal PR #170 head `2e13d5eba51197fe991278caf4fb027c10a25893`:

```text
WORKFLOW=macOS CI
RUN=41257207390
JOB=124702806620
JOB_NAME=Build & Test (Apple Silicon arm64)
RUNNER=macmini-floattabs-01
RUNNER_LABELS=self-hosted,macOS,ARM64,mac-mini-ci
DEBUG_BUILD=PASS
RELEASE_BUILD=PASS
NATIVE_ARM64_VERIFICATION=PASS
UNIT_TESTS=PASS
CONCLUSION=SUCCESS
```

Independent web audit result: `PASS_WITH_FOLLOWUPS`.

No blocking scope, ownership, Browser Profile/session-data, stale-callback, duplicate-load, CI, or mergeability defect remained before merge.

## Non-blocking follow-ups

- The bounded live smoke did not independently capture explicit login text from the accessory surface. It did preserve the Default Browser Profile identity, restore the same ChatGPT URL through `interactionState`, and observed no Profile/session-store mutation. This is not a Phase 1 blocker under the accepted V2 gate.
- Strict multi-Slot memory curves, control-drift thresholds, restore p50/p95 at scale, and automatic Runtime Budget/ranking remain Phase 4 work.
- Historical JSC/WebContent stall root cause remains `UNKNOWN`; Phase 1 does not claim to fix that historical root cause.

## Next phase boundary

Phase 2 (`Ready / Unread decoupling`) is **not started and not authorized**.

Before Phase 2 product mutation:

1. reread current Authority and the V2 program contract;
2. perform the Phase 2 focused read-only audit of Attention/Ready/Unread ownership and Runtime protection paths;
3. freeze Phase 2 exact scope, acceptance and STOP conditions in repository Authority;
4. only then issue a bounded construction card.

Do not start Phase 4 performance tuning merely because Phase 1 merged; performance policy remains a later phase.

## Release state

No new public release is authorized or claimed by Phase 1 closeout.
