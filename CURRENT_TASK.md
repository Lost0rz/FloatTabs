# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Title:** Runtime Lifecycle / Memory redesign — Phase 1 Safe Hibernate + Restore  
**Status:** `CLOSED / PHASE 1 COMPLETE`  
**Mode:** `CLOSED`  
**Task class:** `HIGH-RISK WEB RUNTIME LIFECYCLE / MEMORY`  
**Current program contract:** `docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V2.md`  
**Phase 1 plan:** `docs/architecture/FloatTabs_Runtime_Lifecycle_Phase1_Safe_Hibernate_Restore_Plan_V2.md`  
**JSC root cause:** `UNKNOWN`

## Terminal outcome

Phase 1 Safe Hibernate + Restore is complete and merged.

```text
IMPLEMENTATION_PR=#170 MERGED
IMPLEMENTATION_HEAD=2e13d5eba51197fe991278caf4fb027c10a25893
MERGE_COMMIT=188c524fd02e1c31b8a152b2bec224c947526610
REQUIRED_CI_RUN=41257207390 PASS
REQUIRED_CI_JOB=124702806620 PASS
REQUIRED_CI_RUNNER=macmini-floattabs-01
INDEPENDENT_WEB_AUDIT=PASS_WITH_FOLLOWUPS
PRODUCT_RELEASE=NOT PERFORMED
```

The CI routing blocker was separately corrected and merged in PR #171:

```text
CI_CORRECTIVE_PR=#171 MERGED
CI_CORRECTIVE_MERGE=ce92f99777507dd03a2e7267c33607fe5aea4c56
RUNNER_LABELS=self-hosted,macOS,ARM64,mac-mini-ci
```

## Delivered Phase 1 contract

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

Only normal eligible inactive lifecycle reclamation and the existing eligible critical-Warm pressure path use hibernate. Destructive delete/reset/rebuild/Profile/cache/recovery paths remain destructive.

Compatible restore creates a fresh Runtime and all sidecars before applying public `WKWebView.interactionState`; it does not issue a competing ordinary initial URL load. Missing/incompatible state uses the existing safe URL fallback.

Deterministic teardown invalidates Attention/Response bridges, PopupCoordinator, `SlotNavigationObserver` KVO/liveness/navigation/probe work, clears delegates, calls `stopLoading()`, clears transient Pool state including pending termination context, detaches/removes the old Runtime, and gives restored Runtime a fresh identity.

## Accepted evidence

```text
focused tests: 146 executed / 0 failures
full tests: 1073 executed / 3 skipped / 0 failures
Debug build: PASS
Release build: PASS
bounded live smoke: PASS for architecture-level Runtime behavior
required exact-head CI: PASS
independent web audit: PASS_WITH_FOLLOWUPS
```

The bounded smoke observed an eligible inactive Runtime become non-resident and one fresh Runtime restore through interaction state with no competing ordinary load. Default Browser Profile identity was preserved and no Profile/session-store mutation was observed.

Explicit login text was not independently captured by the automation surface. Under the accepted V2 architecture-first gate this remains a non-blocking follow-up, not a Phase 1 failure.

## Deferred work

The following are not Phase 1 blockers and remain deferred to Phase 4 Runtime Budget / Policy:

- strict `1 / 2 / 4 / 8` loaded-Slot matrix;
- >=9 configured-Slot fixture;
- heavy 4/8 repeated runs;
- no-op/control drift study;
- `median reclaimed > 2× drift` threshold;
- final process-tree memory curve;
- final restore p50/p95 policy threshold;
- automatic Runtime budget/ranking selection.

Historical JSC/WebContent stall root cause remains `UNKNOWN`; no claim is made that Phase 1 fixes it.

## Next authorization

There is no active construction authorization after this closeout.

Phase 2 (`Ready / Unread decoupling`) is `NOT STARTED / NOT AUTHORIZED`.

Before Phase 2 implementation:

1. perform the required focused read-only audit of Attention/Ready/Unread ownership and Runtime protection;
2. freeze Phase 2 scope, affected owners, acceptance criteria and STOP conditions in repository Authority;
3. issue a new bounded construction handoff only after that freeze.

Do not infer Phase 2 authorization from Phase 1 completion.

## Release

No production release is authorized by this closed task.
