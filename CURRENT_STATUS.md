# FloatTabs Current Status

**Status date:** `2026-11-01`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 5 BACKGROUND GENERATION THRIFT**

Current program/task: `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

Current execution state: `PHASE_5_ACTIVE / AUDIT_COMPLETE / DESIGN_FROZEN / IMPLEMENTATION_PENDING`.

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
PHASE_4_EMPIRICAL_TUNING=DEFERRED / FUTURE SETTINGS-BACKED TUNING
PHASE_5=ACTIVE / AUTHORIZED
PHASE_6=NOT_STARTED / NOT_AUTHORIZED
PROGRAM_HUMAN_ACCEPTANCE=PENDING
CI_RUNNER=macmini-floattabs-01 / self-hosted / macOS / ARM64 / mac-mini-ci
```

## Phase 4 authority cleanup

Phase 4 shipped a conservative reference-derived managed target of 3 Warm/Cold runtimes. The previously frozen 1/2/4/8 benchmark-selection gate is historical for Phase 4 and no longer current execution authority.

The current program contract is being revisioned from V3 to V4 in this Phase 5 branch so durable architecture routing matches delivered Phase 4 truth. Historical Phase 4 planning files remain evidence and are not rewritten into fake present-day facts.

## Phase 5 focused audit result

The audit found the relevant long-running generation cost boundary without requiring Runtime ownership changes:

- `WebAttentionCoordinator` remains the sole Attention authority and `generating` remains the only Attention Runtime protection.
- `SlotLifecycleCoordinator` must continue to protect Generating Runtime from automatic reclaim.
- `PanelController` remains canonical product/presentation visibility truth.
- `ChatGPTAttentionBridge` starts a native liveness watchdog when generation begins and currently evaluates a small isolated-world probe every 2 seconds until generation ends or Runtime resets.
- the ordinary page detector is already mutation-driven, coalesced, and intentionally excludes token-stream character-data churn; it is not converted into a polling loop.
- therefore the smallest Phase 5 target is the fixed native fallback cadence, not provider generation or Runtime lifetime.

## Frozen Phase 5 behavior

The bridge may use `document.visibilityState` as **local scheduling metadata only**.

Initial policy:

```text
visible/unknown document                      -> 2s watchdog
hidden document, generation age < 30s         -> 2s watchdog
hidden document, generation age >= 30s        -> 5s watchdog
probe says idle                               -> existing 250ms second confirmation
```

This reduces FloatTabs-owned WebKit JS round trips for long-running hidden generation while keeping the primary detector, generation protection, completion correctness, session state and Runtime ownership unchanged.

The 30s/5s values are initial conservative defaults. They are not represented as measured optimum; later machine/user-specific tuning belongs to the separately authorized Settings-backed performance work.

## Data-safety / ownership boundary

Phase 5 does not authorize:

- Runtime hibernate/release/reload while Attention is `generating`;
- provider-generation pause/cancel/suspend;
- Browser Profile/session/schema changes;
- persistence workarounds or user-data deletion/reset;
- private WebKit APIs;
- Diagnostics becoming product truth;
- Phase 6 perceived-fast restore;
- release/version changes.

## Current authority

```text
AGENTS.md
→ CURRENT_STATUS.md
→ CURRENT_TASK.md
→ docs/README.md
→ current Runtime Lifecycle contract (V4 after this branch reconciliation)
→ docs/architecture/DOMAIN_MAP.md
→ current production source/tests/fresh evidence
```

## Next action

Finish the Phase 5 authority/document reconciliation on the active branch, implement the bounded ChatGPT liveness-watchdog thrift behavior and focused regression tests, then run full machine verification and required literal-head CI. Stop at Phase 5 merge gate unless a blocker requires bounded correction.