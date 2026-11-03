# FloatTabs Current Task

**Task ID:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001`  
**Card ID:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001-WP2-001`  
**Title:** Replace fixed-count normal Runtime reclaim with staged Automatic lifecycle  
**Status:** **ACTIVE / WP2 XCTEST PROCESS-ISOLATION CORRECTIVE**  
**Mode:** `EXECUTE / TEST-RUNNER + CI CORRECTIVE / EXISTING DRAFT PR / NO PRODUCT MUTATION / NO MERGE OR RELEASE`  
**Task class:** `WEB RUNTIME / LIFECYCLE POLICY + XCTEST RUNNER CORRECTIVE`  
**Baseline:** `origin/main@2a52800f770266f7c901eb612a0b319ddca142df`  
**Branch:** `codex/adaptive-lifecycle-wp2-policy`  
**PR:** `#195 OPEN / DRAFT / UNMERGED`

## Authority

Durable WP2 policy: `docs/architecture/FloatTabs_Runtime_Lifecycle_Policy_V7.md`  
WP1 regression authority: `docs/architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md`

Product policy remains frozen. No production lifecycle mutation is authorized by this task.

## Verified incident / validation state

```text
WEBFOCUS_FIXTURE_TEARDOWN_OMISSION=CONFIRMED_DEFECT
FIXTURE_TEARDOWN_AS_SUFFICIENT_INCIDENT_CAUSE=DISPROVEN
AFFECTED_WEBVIEW_PROCESS_TERMINATION=DISPROVEN
AFFECTED_WEBVIEW_JS_NOT_READY=DISPROVEN
NAVIGATION_COMPLETION_MISMATCH=SUPPORTED
ROOT_CAUSE_PROVEN=NO

CANONICAL_TEST_INVENTORY=1165
PARTITION_A=1103
PARTITION_B=62
UNION_A_B=CANONICAL_INVENTORY
INTERSECTION_A_B=EMPTY
OMITTED_TESTS=NONE
DUPLICATED_TESTS=NONE
SPLIT_RUN_1_A=PASS_1103_OF_1103
SPLIT_RUN_1_B=PASS_62_OF_62
SPLIT_RUN_2_A=PASS_1103_OF_1103
SPLIT_RUN_2_B=PASS_62_OF_62
ORIGINAL_13_METHOD_FAILURE_FAMILY=ABSENT_UNDER_SPLIT
NAVIGATION_STALL_REPRODUCED_UNDER_SPLIT=NO
XCTEST_PROCESS_ISOLATION_EFFECT=SUPPORTED
SAFE_CORRECTIVE_BOUNDARY=TEST_RUNNER_PROCESS_ISOLATION
```

The evidence supports a durable test-runner/CI isolation corrective. It does not prove the internal WebKit root cause.

## Current authorization — durable process-isolation corrective

Implement the smallest maintainable repository/CI change that makes the validated two-process execution the canonical machine gate.

### Required partition contract

**Partition A** — all canonical FloatTabs tests except:

- `WebFocusAdapterTests`
- `WebViewFactoryTests`
- `WebsiteLayoutGeometryRegressionTests`

**Partition B** — exactly those three classes in a second fresh XCTest process.

The implementation must preserve complete test coverage. The current observed inventory is 1103 + 62 = 1165, but those numbers are validation evidence, not a hard-coded permanent contract. New tests must not silently disappear from the canonical machine gate.

Prefer the smallest existing-runner/workflow integration. A test-runner helper or workflow adjustment is allowed when necessary. Do not create a parallel testing framework or duplicate unrelated CI logic.

## Mutation boundary

Authorized:

- existing test-runner scripts/config required to perform the two fresh XCTest invocations;
- CI workflow changes required to make the split execution the canonical unit-test gate;
- bounded tests for runner/inventory logic if needed;
- control-file updates reflecting verified results;
- commit/push to the existing PR branch after local verification.

Not authorized:

- production application source changes;
- `SlotLifecycleCoordinator`, `WebViewPool`, production `WebViewFactory`, Browser Profile/session/persistence changes;
- WebsiteData semantics changes;
- process-pool behavior changes;
- lifecycle policy changes;
- test assertion weakening;
- permanent test omission/skipping;
- timeout increases/retry wrappers as the fix;
- private WebKit SPI;
- Browser Profile/session/cookie/website-data clearing;
- WP3/WP4 implementation;
- merge or release.

The three WebKit-heavy classes are **isolated, not skipped**. Both partitions are required for the machine gate to pass.

## Preserved evidence workspaces

Do not modify, reset, clean, delete, or implicitly commit:

- `/Volumes/Jack-Dev/Projects/FloatTabs-adaptive-lifecycle-wp2-policy` — uncommitted fixture-cleanup experiment;
- `/private/tmp/FloatTabs-WP2-DIAG-6a55` — process-state diagnostic checkout;
- `/private/tmp/FloatTabs-WP2-ISO-VAL` — process-isolation validation checkout.

Use a fresh clean construction worktree/check-out for this corrective.

## Verification / acceptance

Before delivery, prove locally:

```text
PARTITION_A_LOCAL=PASS
PARTITION_B_LOCAL=PASS
REPEAT_SPLIT_RUN_LOCAL=PASS
CANONICAL_INVENTORY_COVERAGE=PASS
OMITTED_TESTS=NONE
DUPLICATED_TESTS=NONE
AFFECTED_LIFECYCLE_REGRESSIONS=PASS
NO_PRODUCTION_SOURCE_MUTATION=YES
```

After commit/push, require literal-head PR verification:

```text
SELF_HOSTED_PR_CI=PASS
UNIT_TEST_GATE_USES_TWO_FRESH_XCTEST_PROCESSES=YES
PARTITION_A_CI=PASS
PARTITION_B_CI=PASS
REQUIRED_QA_DMG_JOB=PASS_IF_TRIGGERED
EXACT_DIFF_AUDIT=PASS
```

If either partition fails after the durable change, capture the exact failing set and STOP. Do not broaden automatically into production/WebKit/data-store/process-pool changes.

## Fixture-cleanup experiment disposition

Do not include the previously uncommitted fixture-teardown experiment in this corrective unless a separate reconciliation explicitly authorizes it. The validated fix boundary is process isolation; keep causal scope clean.

## Human / merge gate

This corrective does not materially change product UI. Human UI acceptance for WP2 remains **BLOCKED / NOT STARTED** until the machine gate is reconciled; do not infer product acceptance from CI.

Do not merge PR #195 or release. After machine verification passes, return to Project Governance for exact-diff/control reconciliation and the next acceptance decision.

## Return contract

```text
START_HEAD
FINAL_HEAD
WORKTREE_PATH
FILES_CHANGED
PRODUCTION_FILES_CHANGED
TEST_RUNNER_FILES_CHANGED
CI_FILES_CHANGED

PARTITION_IMPLEMENTATION
CANONICAL_INVENTORY_COVERAGE
OMITTED_TESTS
DUPLICATED_TESTS
PARTITION_A_LOCAL
PARTITION_B_LOCAL
REPEAT_SPLIT_RUN_LOCAL
AFFECTED_LIFECYCLE_REGRESSIONS

COMMIT
REMOTE_BRANCH_HEAD
SELF_HOSTED_PR_CI
PARTITION_A_CI
PARTITION_B_CI
REQUIRED_QA_DMG_JOB
EXACT_DIFF_AUDIT

ROOT_CAUSE_PROVEN
SAFE_CORRECTIVE_BOUNDARY
GIT_STATUS
PR_STATE
MERGE=NOT_MERGED
HUMAN_UI_ACCEPTANCE=BLOCKED_NOT_STARTED
WP3_SCHEDULING_MUTATION=NOT_STARTED
WP4_OTHER_MUTATION=NOT_STARTED
```

Do not merge PR #195. Do not release.
