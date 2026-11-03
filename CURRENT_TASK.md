# FloatTabs Current Task

**Task ID:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001`  
**Card ID:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001-WP2-001`  
**Title:** Replace fixed-count normal Runtime reclaim with staged Automatic lifecycle  
**Status:** **ACTIVE / WP2 XCTEST WEBKIT PROCESS-ISOLATION VALIDATION**  
**Mode:** `DIAGNOSE / TEST-RUNNER A-B ONLY / EXISTING DRAFT PR / NO PRODUCT MUTATION / NO MERGE OR RELEASE`  
**Task class:** `WEB RUNTIME / LIFECYCLE POLICY + XCTEST WEBKIT INCIDENT`  
**Baseline:** `origin/main@2a52800f770266f7c901eb612a0b319ddca142df`  
**Branch:** `codex/adaptive-lifecycle-wp2-policy`  
**PR:** `#195 OPEN / DRAFT / UNMERGED`

## Authority

Durable WP2 policy: `docs/architecture/FloatTabs_Runtime_Lifecycle_Policy_V7.md`  
WP1 regression authority: `docs/architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md`

Product policy remains frozen. No production lifecycle mutation is authorized by this task.

## Verified incident boundary

The process-state diagnostic established:

```text
FRESH_AFFECTED_FAMILY=PASS_62_OF_62
LONG_PREFIX_FULL_SUITE=FAIL_SAME_13_CASE_FAMILY
AFFECTED_WEBVIEW_PROCESS_TERMINATION=DISPROVEN
AFFECTED_WEBVIEW_JS_NOT_READY=DISPROVEN
NAVIGATION_COMPLETION_MISMATCH=SUPPORTED
FIRST_FAILURE_IS_LOADING=TRUE
FIRST_FAILURE_NAVIGATION_CALLBACKS=NONE
FIRST_FAILURE_MINIMAL_JS_LIVENESS=PASS
FIRST_FAILURE_DOM_DEPENDENT_JS=FAIL_DOM_NOT_LOADED
ROOT_CAUSE_PROVEN=NO
```

The first failing WebView remains alive and executes JavaScript, but its new `loadHTMLString` navigation never begins after accumulated same-process suite activity. The observed XPC/WebKit errors are correlation only; the private WebKit mechanism is not established.

The previous fixture teardown experiment is also closed as a sufficient-cause hypothesis: the teardown defect is real, but the same 13-case family reproduced unchanged after cleanup.

Preserve without modification:

- `/Volumes/Jack-Dev/Projects/FloatTabs-adaptive-lifecycle-wp2-policy` — uncommitted fixture-cleanup experiment;
- `/private/tmp/FloatTabs-WP2-DIAG-6a55` — process-state diagnostic checkout.

## Hard evidence gate

```text
MISSING_FACT = Whether the full canonical test inventory is stable when the affected WebKit-heavy classes run in a separate fresh XCTest process instead of after the accumulated main-suite prefix.

BLOCKED_DECISION = Whether a test-runner/CI process-isolation corrective is sufficient and appropriate, or whether a deeper WebKit test-architecture investigation is still required.
```

## Current authorization — process-isolation A/B only

Use a clean isolated checkout of the current PR head. Do not use or clean either preserved evidence worktree.

Do not change test source for this experiment unless a temporary external runner script is strictly necessary to select tests; prefer existing `xcodebuild` selection flags and keep any helper outside tracked repository state.

Run the same canonical test inventory as two fresh XCTest processes:

### Partition A — non-affected inventory

Run every canonical FloatTabs test except these three classes:

- `WebFocusAdapterTests`
- `WebViewFactoryTests`
- `WebsiteLayoutGeometryRegressionTests`

### Partition B — isolated WebKit-heavy affected family

In a new fresh XCTest process, run exactly:

- `WebFocusAdapterTests`
- `WebViewFactoryTests`
- `WebsiteLayoutGeometryRegressionTests`

Before accepting results, prove:

```text
UNION_PARTITION_A_B = CANONICAL_TEST_INVENTORY
INTERSECTION_PARTITION_A_B = EMPTY
OMITTED_TESTS = NONE
DUPLICATED_TESTS = NONE
ASSERTIONS_CHANGED = NO
```

If both partitions pass, repeat the same two-part execution once more using fresh XCTest processes.

## Interpretation

### If split execution passes twice

Return:

```text
XCTEST_PROCESS_ISOLATION_EFFECT=SUPPORTED
NAVIGATION_STALL_REPRODUCED_UNDER_SPLIT=NO
```

Then STOP. Do not implement the CI/test-runner corrective in the same pass. The next task reconciliation may authorize making this isolation durable.

### If either partition fails

Capture the exact failing methods and whether the same navigation-stall boundary appears, then STOP.

Return:

```text
XCTEST_PROCESS_ISOLATION_EFFECT=DISPROVEN_OR_INSUFFICIENT
```

Do not broaden automatically into WebsiteData, process pool, production source, or timing changes.

## Mutation boundary

Authorized:

- local fresh checkouts/worktrees;
- canonical `xcodebuild` invocations with test inclusion/exclusion filters;
- temporary external scripts/logs outside tracked repo state for inventory accounting;
- public process/log observation that does not mutate runtime state.

Not authorized:

- production source mutation;
- test assertion/source mutation;
- committing/pushing any experiment;
- CI workflow mutation;
- data-store changes;
- process-pool changes;
- lifecycle policy changes;
- timeout changes;
- test skip as a permanent solution;
- Browser Profile/session/cookie/website-data clearing;
- private WebKit SPI;
- killing/restarting WebKit helpers as root-cause proof;
- WP3/WP4 implementation;
- merge/release.

## Return contract

```text
VALIDATION_CHECKOUT
AUTHORITY_HEAD
CANONICAL_TEST_INVENTORY_COUNT
PARTITION_A_TEST_COUNT
PARTITION_B_TEST_COUNT
UNION_PARTITION_A_B
INTERSECTION_PARTITION_A_B
OMITTED_TESTS
DUPLICATED_TESTS

SPLIT_RUN_1_PARTITION_A
SPLIT_RUN_1_PARTITION_B
SPLIT_RUN_1_FAILURE_SET

SPLIT_RUN_2_PARTITION_A
SPLIT_RUN_2_PARTITION_B
SPLIT_RUN_2_FAILURE_SET

ORIGINAL_13_METHOD_FAILURE_FAMILY
NAVIGATION_STALL_REPRODUCED_UNDER_SPLIT
XCTEST_PROCESS_ISOLATION_EFFECT
ROOT_CAUSE_PROVEN
RECOMMENDED_NEXT_BOUNDARY

FILES_CHANGED=NONE
COMMIT=NONE
PUSH=NONE
PRODUCTION_FILES_CHANGED=NONE
PRESERVED_FIXTURE_WORKTREE=UNCHANGED
PRESERVED_DIAGNOSTIC_CHECKOUT=UNCHANGED
PR_STATE
HUMAN_UI_ACCEPTANCE=BLOCKED_NOT_STARTED
WP3_SCHEDULING_MUTATION=NOT_STARTED
WP4_OTHER_MUTATION=NOT_STARTED
```

Do not merge PR #195. Do not release.
