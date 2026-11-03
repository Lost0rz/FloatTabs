# FloatTabs Current Status

**Status date:** 2026-11-03  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: ADAPTIVE LIFECYCLE — WP2 MACHINE GATE GREEN / WAITING FOR HUMAN UI ACCEPTANCE**

Current task: `FT-ADAPTIVE-LIFECYCLE-RESTORE-001 / WP2-001` — **ACTIVE / HUMAN UI ACCEPTANCE PENDING**.

Branch: `codex/adaptive-lifecycle-wp2-policy`  
Draft PR: `#195`  
Baseline: `main@2a52800f770266f7c901eb612a0b319ddca142df`  
Machine-verified implementation head: `1f33637b215cf742e20f5a8012818ac14ad459c9`  
Durable policy: `docs/architecture/FloatTabs_Runtime_Lifecycle_Policy_V7.md`

## Verified WP2 state

```text
WP1=COMPLETE / HUMAN_ACCEPTED
WP2_STAGED_AUTOMATIC_POLICY=IMPLEMENTED
WP2_CORRECTIVE_A=PASS
WP2_CORRECTIVE_B=PASS
WP2_CORRECTIVE_C=PASS
FOCUSED_CORRECTIVE_TESTS=PASS
AFFECTED_LIFECYCLE_WP1_REGRESSIONS=PASS
DEBUG_RELEASE_ARM64=PASS
NATIVE_ARM64=PASS
QA_DMG=PASS
CORRECTIVE_ATTRIBUTION=DISPROVEN
XCTEST_PROCESS_ISOLATION_EFFECT=SUPPORTED
TEST_RUNNER_ISOLATION_IMPLEMENTED=YES
CANONICAL_INVENTORY_COVERAGE=PASS
LOCAL_REPEAT_SPLIT_RUN=PASS
SELF_HOSTED_PR_CI=PASS
PARTITION_A_CI=PASS
PARTITION_B_CI=PASS
EXACT_DIFF_AUDIT=PASS
NO_PRODUCTION_SOURCE_MUTATION=YES
MACHINE_GATE=GREEN
HUMAN_UI_ACCEPTANCE=PENDING
PR_195=OPEN_DRAFT_UNMERGED
WP3=NOT_STARTED
WP4=NOT_STARTED
```

## XCTest incident disposition

The blocked full-suite incident is closed at the evidence-supported corrective boundary:

```text
WEBFOCUS_FIXTURE_TEARDOWN_OMISSION=CONFIRMED_DEFECT
FIXTURE_TEARDOWN_AS_SUFFICIENT_INCIDENT_CAUSE=DISPROVEN
AFFECTED_WEBVIEW_PROCESS_TERMINATION=DISPROVEN
AFFECTED_WEBVIEW_JS_NOT_READY=DISPROVEN
NAVIGATION_COMPLETION_MISMATCH=SUPPORTED
WEBKIT_NAVIGATION_PIPELINE_STALL_AFTER_ACCUMULATED_SAME_XCTEST_HOST_ACTIVITY=SUPPORTED_BOUNDARY
ROOT_CAUSE_PROVEN=NO
SAFE_CORRECTIVE_BOUNDARY=TEST_RUNNER_PROCESS_ISOLATION
```

The internal WebKit/XPC mechanism remains unknown and is not required to close WP2. Do not reopen private-mechanism diagnosis unless the isolated canonical gate regresses again.

## Durable process-isolation corrective — verified

Commit `1f33637b215cf742e20f5a8012818ac14ad459c9` changes only `.github/workflows/macos-ci.yml`.

Canonical unit testing now uses two mandatory fresh XCTest processes:

- **Partition A:** all canonical tests except `WebFocusAdapterTests`, `WebViewFactoryTests`, and `WebsiteLayoutGeometryRegressionTests`;
- **Partition B:** exactly those three WebKit-heavy classes.

The partition is class-filter driven; the observed `1103 + 62 = 1165` count is validation evidence, not a hard-coded permanent inventory.

Verified local evidence:

```text
RUN_1_A=PASS_1103_OF_1103
RUN_1_B=PASS_62_OF_62
RUN_2_A=PASS_1103_OF_1103
RUN_2_B=PASS_62_OF_62
UNION_A_B=CANONICAL_INVENTORY
INTERSECTION_A_B=EMPTY
OMITTED_TESTS=NONE
DUPLICATED_TESTS=NONE
AFFECTED_LIFECYCLE_REGRESSIONS=PASS_304_OF_304
```

Verified literal implementation-head remote evidence:

```text
MACOS_CI_RUN=41579374549_PASS
PARTITION_A_STEP=PASS
PARTITION_B_STEP=PASS
QA_DMG_RUN=41579374564_PASS
```

Fresh exact-diff audit confirms the corrective commit is one commit ahead of the prior control head and changes only `.github/workflows/macos-ci.yml` (`+51/-14`); production and test source are untouched.

## Fixture-cleanup experiment disposition

The preserved fixture-teardown experiment is **SUPERSEDED FOR THIS TASK / NOT FOR MERGE**.

Its teardown omission remains a legitimate test-hygiene observation, but the experiment did not affect the incident and must not be mixed into PR #195. No successor hygiene task is active. The local evidence workspaces may remain preserved through WP2 closeout and can be cleaned after the PR disposition is final.

## Human UI acceptance gate

Machine acceptance is complete. WP2 now waits for explicit human product acceptance using the verified QA build from implementation head `1f33637b` (or a later control-only head with identical product source).

Human checks should confirm:

1. existing Slots, Browser Profiles, logins and sessions remain intact;
2. `Automatic` slots switch/show/hide normally and recover cleanly after inactivity without blank/stuck UI or requiring manual reload/restart;
3. `Keep Loaded` slots remain immediately usable across inactivity and switching;
4. Runtime Retention selection persists after relaunch;
5. active/generating/media/fullscreen protected behavior shows no visible lifecycle regression.

A human PASS is required before PR #195 may leave Draft/merge consideration. A human FAIL reopens the task with the exact observed product behavior; do not merge around a failed acceptance.

## Preserved WP2 policy / safety boundary

- normal Runtime count is never a reclaim reason;
- Keep Loaded / Pinned is never automatically reclaimed by normal, warning, or critical FloatTabs policy;
- Automatic stages remain RECENT `<30s`, IDLE `>=30s && <600s`, LONG_IDLE `>=600s`;
- warning reclaims only eligible IDLE/LONG_IDLE Automatic progressively;
- critical may include RECENT Automatic but never Keep Loaded or hard-protected Runtime;
- pressure progression remains fresh-fact, oldest-first, one-step-at-a-time;
- WP1 presentation/readiness, generation/Attention, media/fullscreen, notification privacy/routing, and Browser Profile/session data safety remain regression boundaries.

Do not merge PR #195, release, or begin WP3/WP4 until human UI acceptance and final Project Governance closeout are complete.
