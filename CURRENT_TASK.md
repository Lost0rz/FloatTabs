# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Title:** Runtime Lifecycle / Memory redesign — Phase 7 Real-Mac acceptance preparation  
**Status:** `ACTIVE / PHASE 7 REAL-MAC ACCEPTANCE PREPARATION`  
**Mode:** `ACCEPTANCE TOOLING / REAL-MAC EVIDENCE / HUMAN VALIDATION`  
**Task class:** `WEB RUNTIME / LIFECYCLE / MEMORY`  
**JSC root cause:** `UNKNOWN`

## Authorization state

Phase 7 PR #188 remains `OPEN / DRAFT / UNMERGED`.

The previous final literal machine head `d401a156a9a1d8419221240f4a9b1d099e16db43` passed required macOS CI #1343 and QA DMG #662 on the same head. Product construction and corrective work are complete.

The user has now explicitly authorized proceeding to Phase 7 acceptance preparation. This task authorizes benchmark/runbook/test-tooling changes only. Production lifecycle/runtime behavior is frozen unless new Real-Mac evidence proves a defect and authority is reconciled first.

## Current authority

Program contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V5.md`

Phase 7 frozen execution contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase7_Automatic_Lifecycle_Implementation_Contract_V1.md`

Domain navigation:

`docs/architecture/DOMAIN_MAP.md`

Implementation/acceptance branch:

`codex/ft-runtime-lifecycle-phase7-automatic-001`

Current PR:

`#188 OPEN / DRAFT / UNMERGED`

## Frozen product policy under acceptance

```text
Automatic   (default)
Keep Loaded

normal Automatic target   = 2
Automatic inactive grace  = 30 seconds
warning Automatic target  = 1
critical Automatic target = 0
```

Hard protection:

- active / actually presented;
- fullscreen source;
- supplemental visible Web surface;
- Attention Generating;
- active/pending allowed-background-media protection;
- current materialization/restoring ownership.

Keep Loaded resists ordinary reclaim but may be reclaimed under critical pressure when inactive and otherwise unprotected.

Legacy Hot/Warm/Cold is compatibility-only and must not appear as current acceptance semantics.

## Machine gate evidence

Exact head `d401a156a9a1d8419221240f4a9b1d099e16db43`:

```text
MACOS_CI_1343=PASS
DEBUG_ARM64=PASS
RELEASE_ARM64=PASS
NATIVE_RELEASE_ARCH=PASS
UNIT_TESTS=PASS
QA_DMG_662=PASS
EXACT_DIFF_AUDIT=PASS
PR_IDENTITY=OPEN_DRAFT_UNMERGED
```

This clears the project to enter Phase 7 Real-Mac acceptance preparation.

## Acceptance tooling problem

The existing benchmark harness is a historical Stage 5E Hot/Warm/Cold workflow. It currently encodes old policy names, separate Warm/Cold timing, old hidden-active grace and old acceptance phases. It must not be used as Phase 7 evidence without replacement.

## Authorized work packages

### A1 — retire historical current-use acceptance semantics

Update benchmark documentation and lifecycle harness so current acceptance no longer instructs users to configure or judge Hot/Warm/Cold behavior.

Historical compatibility code/data may remain only when clearly labeled non-current and not used by the Phase 7 run path.

### A2 — Phase 7 acceptance model

The new Real-Mac path must collect evidence for:

1. three or more loaded Automatic Slots;
2. selected/active Slot protection;
3. Automatic inactive plan and reclaim after the 30s grace;
4. normal steady-state Automatic resident target `2`;
5. deterministic LRU ordering when observable from the control/status evidence;
6. Keep Loaded surviving ordinary reclaim pressure;
7. warning target `1` and critical target `0` only if the current debug control already provides a safe explicit trigger;
8. Phase 6 restore after reclaim;
9. Browser Profile/login/Cookie/session continuity checked by the user on restored real sites;
10. RSS/WebKit process-tree trends as supporting evidence, not exact per-Slot WebContent attribution.

### A3 — evidence outputs

A Phase 7 acceptance session should produce at least:

```text
session.json
lifecycle-timeline.csv
lifecycle-events.json
lifecycle-summary.json
lifecycle-report.md
lifecycle-chart.html
acceptance-result.json or equivalent explicit PASS/FAIL/NOT_PROVEN disposition
```

The report must distinguish machine-observed facts from user-observed session/login continuity.

### A4 — validation

Before asking the user to run Real-Mac acceptance:

- Python syntax/compile PASS;
- harness self-tests PASS;
- no current Hot/Warm/Cold acceptance instructions remain in the active Phase 7 runbook;
- diff scope is limited to authorized tooling/docs/tests;
- if the repository head changes, rerun required macOS CI and QA DMG on the exact resulting head before using it as acceptance evidence.

## Authorized paths

Primary:

- `CURRENT_STATUS.md`
- `CURRENT_TASK.md`
- `tools/benchmark/README.md`
- `tools/benchmark/floattabs_lifecycle_benchmark.py`

Conditional:

- `tools/benchmark/floattabs_benchmark.py` only for canonical Phase 7 status/config projection;
- benchmark-specific tests/self-test fixtures;
- architecture/acceptance docs needed to define Phase 7 Real-Mac evidence.

## Production mutation boundary

**No production `FloatTabs/**` lifecycle/runtime mutation is authorized in this work package.**

If the current debug benchmark control lacks a required safe trigger or canonical field, STOP and reconcile instead of extending production/debug host behavior silently.

## Acceptance completion gate

Phase 7 may move to merge-readiness only after:

1. acceptance harness/runbook is Phase 7-native;
2. exact acceptance head passes required CI + QA if changed;
3. Real-Mac Automatic/Keep Loaded evidence is captured;
4. user verifies login/session continuity and the intended UI/runtime behavior;
5. evidence review has no unresolved lifecycle correctness defect;
6. fresh final exact-diff audit PASS.

## Current execution state

```text
PHASE7_PR=#188_OPEN_DRAFT_UNMERGED
MACHINE_VERIFICATION=PASS
PHASE7_REAL_MAC_WP5=PREPARING
CURRENT_STAGE=PHASE7_REAL_MAC_ACCEPTANCE_PREPARATION
AUTHORIZED_MUTATION=BENCHMARK_DOCS_TEST_TOOLING_ONLY
PRODUCTION_RUNTIME_MUTATION=FROZEN
HUMAN_UI_ACCEPTANCE=READY_AFTER_HARNESS_GATE
PR_188_MERGE_READY=NO
NEXT_REQUIRED_GATE=PHASE7_NATIVE_ACCEPTANCE_HARNESS
```
