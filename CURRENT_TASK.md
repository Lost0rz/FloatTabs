# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Title:** Runtime Lifecycle / Memory redesign — Phase 7 automatic lifecycle retirement  
**Status:** `ACTIVE / FINAL VERIFICATION`  
**Mode:** `VERIFY / SELF-AUDIT TO MERGE-READY`  
**Task class:** `WEB RUNTIME / LIFECYCLE / MEMORY`  
**JSC root cause:** `UNKNOWN`

## Authorization state

Phase 6 PR #187 merged to `main` as `54f2e43b0fbc224affa52d9662ac2ba5aa5b963c`.

The user authorized remote Phase 7 construction and continuation through the bounded machine-test corrective. Product corrective and machine-test corrective are now complete; the task is in final verification on PR #188.

This remains the same task `FT-RUNTIME-LIFECYCLE-MEMORY-001`; no new product scope is opened.

## Current authority

Program contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V5.md`

Phase 7 frozen execution contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase7_Automatic_Lifecycle_Implementation_Contract_V1.md`

Implementation branch:

`codex/ft-runtime-lifecycle-phase7-automatic-001`

Current PR:

`#188 OPEN / DRAFT / UNMERGED`

Verified test-corrective head before this final control sync:

`cc924603e876edbc7f9789edc0e4a9180cfa8012`

## Final objective

Deliver persistent Slots whose disposable `WKWebView` Runtime is automatically managed by default:

```text
persistent Slot/Profile/session
→ Automatic Runtime policy
→ active/protected/recent Runtime may stay live
→ inactive Runtime reclaimed deterministically
→ Phase 6 restore when selected again
```

Current user-facing policy is only:

```text
Automatic   (default)
Keep Loaded
```

Legacy Hot/Warm/Cold exists only as bounded compatibility input/projection where required for rollback or external protocol compatibility.

## Frozen lifecycle defaults

```text
normal Automatic target = 2
Automatic grace          = 30 seconds
warning target           = 1
critical target          = 0
```

Hard protection remains:

- active / actually presented;
- fullscreen source;
- supplemental visible surface;
- Attention generating;
- active/pending allowed-background-media protection;
- current materialization/restoring ownership.

Keep Loaded resists ordinary reclaim but may be reclaimed under critical pressure when inactive and otherwise unprotected.

## Completed corrective work

### Product corrective

Completed before `f3ac1d98...`:

- current Hot/Warm/Cold shortcut bindings retired;
- Shortcuts Settings Mode section retired;
- dead Hot-only hidden host architecture removed;
- historical 120-second production hidden-active retention removed;
- stale Cold-only runtime release callback/HUD projection removed;
- Browser Profile/session/cache and Phase 6 restore boundaries preserved.

### Machine-test corrective

Fresh XCTest diagnostics proved the remaining failures were obsolete current-product Hot/Warm/Cold assumptions. The corrective updated test contracts instead of restoring retired production APIs.

Corrective run `41366231928` passed:

- helper/scope guard;
- test-only whitelist;
- `git diff --check` equivalent hygiene;
- full XCTest.

The verified corrective was committed as `cc924603...`; temporary corrective workflow/helper and accidental temporary remote branches were removed.

Net corrective paths after `f3ac1d98...` are only the two control files plus eight test files. No production file changed during the machine-test corrective.

## Final verification gates

Merge readiness still requires:

1. current literal PR head passes required `Build & Test (Apple Silicon arm64)`;
2. QA DMG passes for that same literal head;
3. bounded Real-Mac lifecycle/memory evidence is collected where remotely provable;
4. fresh exact-diff self-audit confirms canonical ownership, compatibility safety, no active Hot/Warm/Cold policy, no hidden Runtime workaround, no cache/session destruction and no Phase 6 regression;
5. PR remains unmerged until all machine gates pass and merge readiness is explicitly established.

Human UI/runtime acceptance remains `NOT_STARTED` until explicitly performed by the user.

## Current authorized scope

Final verification is read/execute/audit only unless fresh evidence proves a new defect.

Production mutation is not authorized merely to satisfy obsolete tests. If a fresh final-head machine failure proves an actual production defect, STOP and reconcile the corrective scope before changing product code.

Control files may be kept aligned with current state. Release/version work is excluded.

## STOP conditions

STOP/reconcile if final verification would require:

- Browser Profile/cookie/session reset or destructive migration;
- restoring Hot/Warm/Cold current controls or policy;
- a second lifecycle writer;
- hidden persistent WebViews;
- private WebKit memory attribution;
- an unplanned persistence schema/version migration;
- release/version work.

## Current execution state

```text
PROGRAM_CONTRACT=V5_ACCEPTED_FROZEN
PHASE6=MERGED
PHASE7_CONTRACT=ACCEPTED_FROZEN_RECONCILED
PHASE7_PR=#188_OPEN_DRAFT_UNMERGED
PHASE7_PRODUCT_CORRECTIVE=COMPLETE
PHASE7_MACHINE_TEST_CORRECTIVE=COMPLETE
PHASE7_TEST_CORRECTIVE_HEAD=cc924603e876edbc7f9789edc0e4a9180cfa8012
PHASE7_FULL_XCTEST=PASS / RUN 41366231928
CURRENT_STAGE=FINAL_VERIFICATION
CURRENT_LITERAL_HEAD=THIS_CONTROL_SYNC_HEAD
NEXT_REQUIRED_GATE=LITERAL_HEAD_CI_AND_QA_DMG
PROGRAM_HUMAN_ACCEPTANCE=NOT_STARTED
```
