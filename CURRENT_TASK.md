# FloatTabs Current Task

**Task ID:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001`  
**Card ID:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001-WP2-001`  
**Title:** Replace fixed-count normal Runtime reclaim with staged Automatic lifecycle  
**Status:** **ACTIVE / WP2 FULL-XCTEST INCIDENT DIAGNOSIS**  
**Mode:** `READ-ONLY INCIDENT DIAGNOSIS / EXISTING DRAFT PR / NO PRODUCT MUTATION / NO MERGE OR RELEASE`  
**Task class:** `WEB RUNTIME / LIFECYCLE POLICY`  
**Baseline:** `origin/main@2a52800f770266f7c901eb612a0b319ddca142df`  
**Branch:** `codex/adaptive-lifecycle-wp2-policy`  
**PR:** `#195 OPEN / DRAFT / UNMERGED`

## Authority

Durable WP2 policy: `docs/architecture/FloatTabs_Runtime_Lifecycle_Policy_V7.md`  
WP1 regression authority: `docs/architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md`

WP2 Correctives A/B/C are implemented at semantic head `cc44537635ef451a78dc8894484c9ce9328de936`. The product policy is frozen and must not be redesigned during this incident diagnosis.

## Verified corrective state

```text
CORRECTIVE_A_HOSTED_RELEASE=PASS
CORRECTIVE_B_STALE_ASYNC_PRESSURE=PASS
CORRECTIVE_C_INJECTED_TIME=PASS
FOCUSED_CORRECTIVE_TESTS=PASS
AFFECTED_LIFECYCLE_WP1_REGRESSIONS=PASS
DEBUG_RELEASE_ARM64=PASS
PACKAGE_LOCK=UNCHANGED
QA_DMG=PASS
INDEPENDENT_CORRECTIVE_DIFF_AUDIT=NO_POLICY_OR_OWNERSHIP_BLOCKER
FULL_XCTEST=FAIL
SELF_HOSTED_CI=FAIL_AT_UNIT_TESTS
FULL_SUITE_FAILURE_ROOT_CAUSE=UNKNOWN
CORRECTIVE_ATTRIBUTION=UNPROVEN
HUMAN_UI_ACCEPTANCE=BLOCKED_NOT_STARTED
WP3_SCHEDULING_MUTATION=NOT_STARTED
WP4_OTHER_MUTATION=NOT_STARTED
```

The full-suite failure reproduces in unchanged WebFocusAdapter, WebViewFactory, and WebsiteLayoutGeometryRegression tests. The same 13 failing methods pass when run individually. Current evidence includes WebKit fixture/page-load timeouts and related WebContent/runtime errors. These facts narrow the incident but do not prove whether the corrective caused it, exposed a pre-existing shared-state/test-order issue, or coincided with runner/WebKit host instability.

## Current authorization — bounded incident diagnosis

Before any further product/test mutation, establish causal attribution for the full XCTest failure using controlled read-only executions and existing artifacts.

Required hypotheses to distinguish:

1. **Corrective regression:** the corrective semantic changes cause cumulative/shared WebKit failure during the full suite.
2. **Pre-existing WP2/full-suite issue:** the same failure reproduces on corrective base `f0705747c6a095f24d50c9ffdac21675a1bfc662` under the same command/environment.
3. **Test-order/shared-state contamination:** a preceding test/suite poisons WebKit state and the 13 tests fail only after a specific prefix or within a shared full-suite process.
4. **Runner/WebKit host instability/resource exhaustion:** process/bootstrap/load failure appears independently of the corrective and correlates with host/runtime state rather than product semantics.
5. **Parallel/concurrency interaction:** full-suite concurrency changes the result while serial execution does not.

Diagnosis must prefer exact A/B evidence over intuition. Retry/pass, runner restart, service restart, or app restart is recovery evidence only and never root-cause proof.

## Required diagnostic matrix

Use clean temporary worktrees or equivalent isolated checkouts. Preserve all unique work. Do not mutate the active WP2 branch during diagnosis.

### A — exact failure inventory

From the failing `.xcresult` / CI diagnostics, record:
- exact 13 failing test methods;
- first failing test in execution order;
- failure timestamps/order;
- WebKit/WebContent/NetworkProcess errors immediately preceding the first load timeout;
- whether failures are primary load-timeout failures followed by dependent assertions.

### B — current corrective head, fresh-process batch

On corrective semantic head `cc44537635ef451a78dc8894484c9ce9328de936` (or a control-only descendant only after proving source/test identity):
- run the 13 failing methods together in one fresh xcodebuild process in the same order;
- run them together in reverse order;
- record PASS/FAIL and first failure.

### C — full-suite causal A/B against corrective base

Run the same full XCTest command, same machine/toolchain/environment, on:
- corrective base `f0705747c6a095f24d50c9ffdac21675a1bfc662`;
- corrective semantic head `cc44537635ef451a78dc8894484c9ce9328de936`.

Prefer alternating runs rather than completing all runs on one ref first. Obtain at least one fresh comparable full run per ref. If outcomes differ, repeat enough to determine whether the difference is stable or flaky. Do not infer causality from different machines/toolchains.

### D — order/prefix contamination

If the 13-test batch passes but full suite fails:
- identify the test/suite prefix immediately before the first failing method;
- run that prefix followed by the first failing test in one xcodebuild process;
- narrow the smallest practical poisoning prefix by grouped/binary search;
- do not edit product code while narrowing.

### E — serial/concurrency diagnostic

If the canonical full-suite command permits test parallelism, run a diagnostic-only serial equivalent (`-parallel-testing-enabled NO` or repository-appropriate equivalent) on the same ref.

This is diagnostic evidence only. Do not weaken the canonical CI gate or change workflow configuration solely because serial execution passes.

### F — bounded host/runtime observations

During comparable runs capture non-destructive observations only:
- WebKit.WebContent / Network process counts before, during, after;
- relevant process/fd counts where practical;
- macOS memory-pressure state if available through supported ordinary tools;
- exact WebKit bootstrap/sandbox/process errors from failing runs.

Do not kill helpers, clear caches, delete website data, restart services, or reboot as part of primary diagnosis.

## Decision gate

Return one of:

```text
CORRECTIVE_ATTRIBUTION=PROVEN
CORRECTIVE_ATTRIBUTION=DISPROVEN
CORRECTIVE_ATTRIBUTION=UNPROVEN
```

and:

```text
FULL_SUITE_ROOT_CAUSE=KNOWN
FULL_SUITE_ROOT_CAUSE=NARROWED
FULL_SUITE_ROOT_CAUSE=UNKNOWN
```

Only after evidence supports a specific bounded mutation may another EXECUTE corrective be authorized. Do not modify production source or tests during this read-only incident stage.

## Frozen product/regression boundary

Preserve:
- no fixed normal resident count;
- Keep Loaded/Pinned never FloatTabs-auto-reclaimed under normal/warning/critical;
- RECENT `<30s`, IDLE `30s..<600s`, LONG_IDLE `>=600s`;
- progressive fresh-fact pressure reclaim;
- WP1 presentation/readiness;
- generation/media/fullscreen protection;
- Browser Profile/session/login/cookie data safety.

## STOP conditions

Stop and report evidence if diagnosis would require:
- product source/test mutation;
- clearing Browser Profile/session/cache/website data;
- private WebKit SPI;
- killing WebKit helpers;
- weakening canonical CI/full-XCTest acceptance;
- treating restart/retry success as root cause;
- entering WP3/WP4;
- merge/release.

## Return contract

Return observed values for:

```text
DIAGNOSTIC_BASELINE
CURRENT_CORRECTIVE_HEAD
FAILURE_SET
FIRST_FAILURE
PRIMARY_FAILURE_PATTERN
CURRENT_13_SAME_ORDER_RESULT
CURRENT_13_REVERSE_ORDER_RESULT
BASE_F070_FULL_XCTEST_RESULT
CURRENT_CC445_FULL_XCTEST_RESULT
ALTERNATING_REPEAT_RESULT
POISONING_PREFIX_RESULT
SERIAL_FULL_XCTEST_RESULT
WEBKIT_PROCESS_OBSERVATIONS
WEBKIT_ERROR_EVIDENCE
CORRECTIVE_ATTRIBUTION
FULL_SUITE_ROOT_CAUSE
MUTATION_RECOMMENDATION
HUMAN_UI_ACCEPTANCE=BLOCKED_NOT_STARTED
WP3_SCHEDULING_MUTATION=NOT_STARTED
WP4_OTHER_MUTATION=NOT_STARTED
PR_STATE
```

Do not merge PR #195. Do not release.
