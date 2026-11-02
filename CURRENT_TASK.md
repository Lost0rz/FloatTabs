# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Title:** Runtime Lifecycle / Memory redesign — Phase 7 final closeout and merge boundary  
**Status:** `ACTIVE / PHASE 7 FINAL CLOSEOUT / MERGE AUTHORIZED AFTER LITERAL-HEAD HOST GATE`  
**Mode:** `EVIDENCE AUDIT / CONTROL ALIGNMENT / MERGE`  
**Task class:** `WEB RUNTIME / LIFECYCLE / MEMORY`  
**JSC root cause:** `UNKNOWN`

## Authorization state

The user authorized a fresh independent closeout audit and, if no blocking issue remains, merge of PR #188.

Phase 7 product implementation is frozen. No further `FloatTabs/**` runtime/lifecycle mutation is authorized unless new evidence proves a defect and this task is reconciled first.

The fresh closeout audit found no blocking product/runtime defect. It did find stale current-status/routing projections that still described Phase 7 as not started or only preparing for Real-Mac acceptance. Those control/routing files are being aligned as control-only closeout; this does not change the verified product semantics.

## Current authority

Program contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V5.md`

Phase 7 frozen implementation contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase7_Automatic_Lifecycle_Implementation_Contract_V1.md`

Documentation routing:

`docs/README.md`

Domain/navigation:

`docs/architecture/README.md`  
`docs/architecture/DOMAIN_MAP.md`

PR:

`#188 — codex/ft-runtime-lifecycle-phase7-automatic-001 → main`

## Frozen product policy

```text
Automatic   (default)
Keep Loaded

normal Automatic target   = 2
Automatic inactive grace  = 30 seconds
warning Automatic target  = 1
critical Automatic target = 0
```

Hard protection remains:

- active / actually presented;
- fullscreen source;
- supplemental visible Web surface;
- Attention Generating;
- active/pending allowed-background-media protection;
- current materialization/restoring ownership.

Keep Loaded resists ordinary reclaim, is not proactively materialized at launch, and may be reclaimed under critical pressure when inactive and otherwise unprotected.

Legacy Hot/Warm/Cold is compatibility-only and must not return as current product UI/settings/shortcut/lifecycle policy.

## Verified semantic / acceptance identity

Product + Real-Mac acceptance semantic head:

`b894641a254e7ffb49c84b4ed32d9c70a3f28ad7`

Verified on that identity:

```text
MACOS_CI_1349=PASS
REQUIRED_BUILD_AND_TEST_ARM64=PASS
QA_DMG_668=PASS
BENCHMARK_TOOL_CI_139=PASS
PRODUCT_EXACT_DIFF_AUDIT=PASS
REAL_MAC_ACCEPTANCE=PASS
KEEP_LOADED_RELAUNCH_NON_PRELOAD=PASS
SESSION_CONTINUITY=PASS
WARNINGS=NONE
```

Real-Mac evidence establishes:

1. Automatic normal-budget/LRU convergence;
2. 30-second grace behavior;
3. active Slot protection;
4. Rapid A → B → A correctness;
5. Background Generation protection followed by ordinary reclaim;
6. Keep Loaded ordinary retention;
7. reclaim → restore with Browser Profile/session continuity;
8. Keep Loaded preference persistence without proactive relaunch materialization;
9. aggregate WebKit/RSS directional support without unsupported exact per-Slot memory attribution.

Warning target `1` / critical target `0` remain deterministically covered by machine tests because current Debug control has no safe explicit system-pressure injection trigger.

## Fresh closeout audit disposition

Audit basis: fresh repository/PR/CI evidence review at the merge boundary.

Required claims:

```text
CURRENT_BASE_MAIN=54f2e43b0fbc224affa52d9662ac2ba5aa5b963c
SEMANTIC_HEAD=b894641a254e7ffb49c84b4ed32d9c70a3f28ad7
BASE_DRIFT=NONE
PRODUCT_SCOPE=PASS
CANONICAL_LIFECYCLE_WRITER=PASS
LEGACY_ACTIVE_POLICY_RETIRED=PASS
HIDDEN_HOT_HOST_RETIRED=PASS
SESSION_DATA_SAFETY=PASS
PHASE6_RESTORE_PRESERVED=PASS
REAL_MAC_WP5=PASS
OPEN_REVIEW_THREADS=NONE
OVERLAPPING_OPEN_PRS=NONE
```

The only audit finding was stale control/document-routing status; it is being corrected without product-source mutation.

## Final merge gate

Control-only closeout commits may advance the literal PR HEAD beyond the semantic head above. Per `AGENTS.md`, that does not invalidate product implementation/acceptance evidence, but repository-host protection still applies to the literal final HEAD.

Before merge:

1. verify PR #188 final literal HEAD and unchanged `main@54f2e43b0fbc224affa52d9662ac2ba5aa5b963c`;
2. verify no production `FloatTabs/**` change was introduced by closeout alignment;
3. required `Build & Test (Apple Silicon arm64)` check must be `success` on that literal HEAD;
4. required auxiliary PR workflows must have no failure;
5. PR must remain mergeable with no unresolved review thread;
6. mark Draft PR ready for review if GitHub requires it;
7. merge using `expected_head_sha` so a moved head cannot be merged accidentally.

Do not perform release/version work in this task.

## After merge

The Runtime Lifecycle / Memory program remains active for the contract-required post-merge integrated Phases 1–7 audit. That audit is a new read-only program-final acceptance boundary, not additional Phase 7 product construction.

```text
CURRENT_STAGE=PHASE7_FINAL_MERGE_GATE
PRODUCT_RUNTIME_MUTATION=FROZEN
SEMANTIC_ACCEPTANCE_HEAD=b894641a254e7ffb49c84b4ed32d9c70a3f28ad7
CONTROL_ONLY_CLOSEOUT=ACTIVE
PR_188_MERGE_AUTHORIZED=YES_AFTER_LITERAL_HEAD_HOST_GATE
POST_MERGE_NEXT=INTEGRATED_PHASES_1_TO_7_AUDIT
```
