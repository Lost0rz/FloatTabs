# FloatTabs Current Status

**Status date:** 2026-11-03  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: ADAPTIVE LIFECYCLE — WP2 XCTEST PROCESS-ISOLATION CORRECTIVE**

Current task: `FT-ADAPTIVE-LIFECYCLE-RESTORE-001 / WP2-001` — **ACTIVE / TEST-RUNNER PROCESS-ISOLATION CORRECTIVE AUTHORIZED**.

Branch: `codex/adaptive-lifecycle-wp2-policy`  
Draft PR: `#195`  
Baseline: `main@2a52800f770266f7c901eb612a0b319ddca142df`  
WP2 corrective semantic head: `cc44537635ef451a78dc8894484c9ce9328de936`  
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
FULL_XCTEST_SINGLE_PROCESS=FAIL
XCTEST_PROCESS_ISOLATION_EFFECT=SUPPORTED
SELF_HOSTED_CI=AWAITING_DURABLE_ISOLATION_CORRECTIVE
HUMAN_UI_ACCEPTANCE=BLOCKED_NOT_STARTED
PR_195=OPEN_DRAFT_UNMERGED
WP3=NOT_STARTED
WP4=NOT_STARTED
```

## Incident findings established

The incident is now localized enough to define a safe corrective boundary without claiming a private WebKit root cause.

Verified findings:

```text
WEBFOCUS_FIXTURE_TEARDOWN_OMISSION=CONFIRMED_DEFECT
FIXTURE_TEARDOWN_AS_SUFFICIENT_INCIDENT_CAUSE=DISPROVEN
AFFECTED_WEBVIEW_PROCESS_TERMINATION=DISPROVEN
AFFECTED_WEBVIEW_JS_NOT_READY=DISPROVEN
NAVIGATION_COMPLETION_MISMATCH=SUPPORTED
WEBKIT_NAVIGATION_PIPELINE_STALL_AFTER_ACCUMULATED_SAME_XCTEST_HOST_ACTIVITY=SUPPORTED_BOUNDARY
ROOT_CAUSE_PROVEN=NO
```

At the first failing affected test after the accumulated suite prefix, the WebView remained alive and could execute `1+1`, but its new `loadHTMLString` navigation never emitted provisional-start, commit, finish, or failure callbacks and remained `isLoading=true`. DOM-dependent JavaScript failed because the expected document never loaded.

The internal WebKit/XPC mechanism remains unknown. Correlated WebKit/XPC log messages are supporting observations only.

## Process-isolation validation — complete

The canonical test inventory was proven to contain 1165 unique tests. A bounded validation split it into two fresh XCTest processes without source/assertion changes:

```text
PARTITION_A=1103 tests
PARTITION_B=62 tests
UNION_A_B=1165_CANONICAL_TESTS
INTERSECTION_A_B=EMPTY
OMITTED_TESTS=NONE
DUPLICATED_TESTS=NONE
ASSERTIONS_CHANGED=NO
SOURCE_CHANGED=NO
```

Partition B contains exactly:

- `WebFocusAdapterTests`
- `WebViewFactoryTests`
- `WebsiteLayoutGeometryRegressionTests`

Two complete split runs were green:

```text
SPLIT_RUN_1_A=PASS_1103_OF_1103
SPLIT_RUN_1_B=PASS_62_OF_62
SPLIT_RUN_2_A=PASS_1103_OF_1103
SPLIT_RUN_2_B=PASS_62_OF_62
ORIGINAL_13_METHOD_FAILURE_FAMILY=ABSENT_UNDER_SPLIT
NAVIGATION_STALL_REPRODUCED_UNDER_SPLIT=NO
XCTEST_PROCESS_ISOLATION_EFFECT=SUPPORTED
```

Therefore same-XCTest-host accumulated WebKit state is a necessary environment condition for the observed incident, and **test-runner process isolation is now the minimum evidence-supported corrective boundary**. This does not prove the internal WebKit root cause.

## Current corrective authorization

Make the split execution durable in the repository/self-hosted CI while preserving the complete canonical test inventory and all existing assertions.

Required behavior:

1. run all canonical tests except the three WebKit-heavy classes in one fresh XCTest process;
2. run those three classes together in a second fresh XCTest process;
3. preserve exact inventory coverage: 1103 + 62 = 1165 at the current test inventory;
4. keep the implementation maintainable as tests are added; do not hard-code the total count as product truth;
5. do not change production behavior, WebsiteData semantics, process-pool policy, lifecycle policy, test assertions, or timeouts;
6. validate locally and through literal-head self-hosted CI before any merge decision.

A small runner/helper or CI workflow change is authorized if required to make this split deterministic. The corrective belongs to test-runner/CI architecture, not production runtime code.

## Preserved experiments / disposition

Preserve until the durable corrective has passed and evidence is reconciled:

- `/Volumes/Jack-Dev/Projects/FloatTabs-adaptive-lifecycle-wp2-policy` — uncommitted fixture-cleanup experiment;
- `/private/tmp/FloatTabs-WP2-DIAG-6a55` — process-state diagnostic checkout;
- `/private/tmp/FloatTabs-WP2-ISO-VAL` — process-isolation validation checkout.

The fixture-cleanup experiment is not required for the isolation corrective and must not be implicitly committed with it. Its later disposition is a separate reconciliation decision.

## Machine acceptance gate

```text
TEST_RUNNER_ISOLATION_IMPLEMENTED=YES
CANONICAL_INVENTORY_COVERAGE_PROVEN=YES
PARTITION_A=PASS
PARTITION_B=PASS
REPEAT_SPLIT_RUN=PASS
AFFECTED_LIFECYCLE_REGRESSIONS=PASS
SELF_HOSTED_PR_CI=PASS
REQUIRED_QA_DMG_JOB=PASS_IF_TRIGGERED
NO_PRODUCTION_SOURCE_MUTATION=YES
EXACT_DIFF_AUDIT=PASS
```

Human UI acceptance remains blocked until this machine gate is green and reconciled. Do not merge PR #195, release, or begin WP3/WP4 before then.

## Preserved WP2 policy / safety boundary

- normal Runtime count is never a reclaim reason;
- Keep Loaded / Pinned is never automatically reclaimed by normal, warning, or critical FloatTabs policy;
- Automatic stages remain RECENT `<30s`, IDLE `>=30s && <600s`, LONG_IDLE `>=600s`;
- warning reclaims only eligible IDLE/LONG_IDLE Automatic progressively;
- critical may include RECENT Automatic but never Keep Loaded or hard-protected Runtime;
- pressure progression remains fresh-fact, oldest-first, one-step-at-a-time;
- WP1 presentation/readiness, generation/Attention, media/fullscreen, notification privacy/routing, and Browser Profile/session data safety remain regression boundaries.
