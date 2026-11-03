# FloatTabs Current Task

**Task ID:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001`  
**Card ID:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001-WP2-001`  
**Title:** Replace fixed-count normal Runtime reclaim with staged Automatic lifecycle  
**Status:** **ACTIVE / WP2 WAITING FOR HUMAN UI ACCEPTANCE**  
**Mode:** `HUMAN ACCEPTANCE / EXISTING DRAFT PR / NO FURTHER ENGINEERING MUTATION / NO MERGE OR RELEASE`  
**Task class:** `WEB RUNTIME / LIFECYCLE POLICY + HUMAN ACCEPTANCE`  
**Baseline:** `origin/main@2a52800f770266f7c901eb612a0b319ddca142df`  
**Branch:** `codex/adaptive-lifecycle-wp2-policy`  
**PR:** `#195 OPEN / DRAFT / UNMERGED`

## Authority

Durable WP2 policy: `docs/architecture/FloatTabs_Runtime_Lifecycle_Policy_V7.md`  
WP1 regression authority: `docs/architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md`

Product policy remains frozen. The current task is no longer an implementation task unless human acceptance returns a concrete defect.

## Machine gate — verified green

Machine-verified implementation head:

`1f33637b215cf742e20f5a8012818ac14ad459c9`

Verified evidence:

```text
WP2_POLICY=IMPLEMENTED
CORRECTIVE_A_HOSTED_RELEASE=PASS
CORRECTIVE_B_STALE_ASYNC_PRESSURE=PASS
CORRECTIVE_C_INJECTED_TIME=PASS
AFFECTED_LIFECYCLE_WP1_REGRESSIONS=PASS_304_OF_304

XCTEST_PROCESS_ISOLATION_EFFECT=SUPPORTED
TEST_RUNNER_ISOLATION_IMPLEMENTED=YES
CANONICAL_INVENTORY_COVERAGE=PASS
OMITTED_TESTS=NONE
DUPLICATED_TESTS=NONE
LOCAL_RUN_1_A=PASS_1103_OF_1103
LOCAL_RUN_1_B=PASS_62_OF_62
LOCAL_RUN_2_A=PASS_1103_OF_1103
LOCAL_RUN_2_B=PASS_62_OF_62

SELF_HOSTED_PR_CI=PASS
MACOS_CI_RUN=41579374549
PARTITION_A_CI=PASS
PARTITION_B_CI=PASS
QA_DMG_RUN=41579374564_PASS
EXACT_DIFF_AUDIT=PASS
NO_PRODUCTION_SOURCE_MUTATION=YES
MACHINE_GATE=GREEN
```

Fresh exact-diff audit confirms the durable corrective commit changes only `.github/workflows/macos-ci.yml`. The canonical unit-test gate now requires two fresh XCTest processes; the three WebKit-heavy classes are isolated, not skipped.

The internal WebKit/XPC root cause remains unproven. This does not block WP2 because the minimum evidence-supported safe corrective boundary is verified and durable.

## Current authorization — human acceptance only

No further production/test/CI mutation is authorized by default.

Use the verified QA build from implementation head `1f33637b` or a later control-only head with identical product source.

Human acceptance must explicitly check the product behavior below.

### 1. Data/session safety

Confirm existing:

- Slots;
- Browser Profiles;
- website logins/sessions;
- Runtime Retention selections

remain intact. No reset/re-login/data loss is acceptable.

### 2. Automatic behavior

For at least one `Automatic` slot:

- switch away and back during ordinary use;
- hide/show FloatTabs;
- leave the slot inactive long enough to exercise lifecycle behavior where practical;
- return to it and confirm the Web App becomes usable normally without a blank/stuck surface or requiring manual reload/restart.

### 3. Keep Loaded behavior

For at least one `Keep Loaded` slot:

- switch away / hide / leave inactive;
- return and confirm it remains immediately usable and is not visibly reclaimed by FloatTabs lifecycle behavior.

### 4. Persistence

Change or confirm a Slot's Runtime Retention choice, relaunch FloatTabs, and verify the choice persists.

### 5. Protected behavior regression

During normal use, confirm no visible regression for relevant protected states used by the user, including active/generating interaction and media/fullscreen behavior where exercised.

## Acceptance decision

### If human acceptance PASS

Return an explicit human PASS with any observations. Then Project Governance may perform final literal-head/control reconciliation, decide Draft → Ready, and make the merge decision.

Do **not** merge automatically from the human test context.

### If human acceptance FAIL

Return:

- exact Slot / retention mode;
- user action sequence;
- visible failure;
- whether reload/restart changes the symptom;
- any available diagnostics/snapshot.

Then STOP. Project Governance will reconcile a bounded corrective before any new mutation.

## Incident evidence disposition

The previous fixture-teardown experiment is **SUPERSEDED FOR THIS TASK / NOT FOR MERGE**. It established a real hygiene omission but did not resolve or alter the incident.

Do not cherry-pick or mix that experiment into PR #195. No separate fixture-hygiene task is active. Preserved local evidence workspaces can be cleaned after the final PR disposition.

## Mutation boundary

Not authorized while waiting for human acceptance:

- production source changes;
- test source/assertion changes;
- CI/test-runner changes;
- WebsiteData / process-pool changes;
- lifecycle-policy changes;
- timeout/retry changes;
- Browser Profile/session/cookie clearing;
- private WebKit SPI;
- WP3/WP4 implementation;
- merge or release.

If human acceptance exposes a defect, return to Project Governance before mutation.

## Human / merge gate

```text
MACHINE_GATE=GREEN
HUMAN_UI_ACCEPTANCE=PENDING
PR_195=OPEN_DRAFT_UNMERGED
MERGE_READY=NO_UNTIL_HUMAN_PASS_AND_FINAL_RECONCILIATION
```

Do not merge PR #195 or release before explicit human acceptance and final Project Governance closeout.

## Return contract

```text
HUMAN_ACCEPTANCE_BUILD
HUMAN_DATA_SESSION_SAFETY
HUMAN_AUTOMATIC_BEHAVIOR
HUMAN_KEEP_LOADED_BEHAVIOR
HUMAN_RETENTION_PERSISTENCE
HUMAN_PROTECTED_BEHAVIOR
HUMAN_UI_ACCEPTANCE=PASS | FAIL
OBSERVED_ISSUES
PR_STATE
MERGE=NOT_MERGED
WP3_SCHEDULING_MUTATION=NOT_STARTED
WP4_OTHER_MUTATION=NOT_STARTED
```
