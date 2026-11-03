# FloatTabs Current Status

**Status date:** 2026-11-03  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: ADAPTIVE LIFECYCLE — WP2 FULL-XCTEST WEBKIT PROCESS-STATE INCIDENT DIAGNOSIS**

Current task: `FT-ADAPTIVE-LIFECYCLE-RESTORE-001 / WP2-001` — **ACTIVE / INCIDENT DIAGNOSIS / TEST-ONLY PROBES AUTHORIZED**.

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
FULL_XCTEST=FAIL
SELF_HOSTED_CI=FAIL_AT_UNIT_TESTS
HUMAN_UI_ACCEPTANCE=BLOCKED_NOT_STARTED
PR_195=OPEN_DRAFT_UNMERGED
WP3=NOT_STARTED
WP4=NOT_STARTED
```

## Fixture-corrective falsification result

A bounded test-only fixture cleanup experiment was executed locally and intentionally left uncommitted after the canonical gate failed.

Experiment changes were limited to `WebFocusAdapterTests`, `WebViewFactoryTests`, `WebsiteLayoutGeometryRegressionTests`, a test-only teardown helper, and Xcode test-file registration. Production files were unchanged.

Observed results:

```text
TARGETED_WEBFOCUS_TESTS=PASS_28_OF_28
TARGETED_FACTORY_TESTS=PASS_27_OF_27
TARGETED_GEOMETRY_TESTS=PASS_7_OF_7
AFFECTED_LIFECYCLE_REGRESSIONS=PASS_304_OF_304
CANONICAL_FULL_XCTEST_RUN_1=FAIL
FULL_XCTEST_TOTAL=1165
FAILED_CASES=13
ORIGINAL_13_METHOD_FAILURE_FAMILY=PRESENT_UNCHANGED
WEBCONTENT_DISTINCT_PIDS_OBSERVED=132
WEBKIT_SIGNAL_113_COUNT=75
PRODUCTION_FILES_CHANGED=NO
COMMIT=NONE
PUSH=NONE
```

The same 13 WebFocusAdapter / WebViewFactory / WebsiteLayoutGeometryRegression cases reproduced after deterministic fixture teardown. Therefore:

```text
WEBFOCUS_FIXTURE_TEARDOWN_OMISSION=CONFIRMED_DEFECT
FIXTURE_TEARDOWN_AS_SUFFICIENT_INCIDENT_CAUSE=DISPROVEN
TEST_FIXTURE_RESOURCE_ACCUMULATION_CAUSAL_SUFFICIENCY=DISPROVEN
TEST_ORDER_SHARED_STATE=STRONGLY_SUPPORTED
WEBKIT_SHARED_HOST_OR_PROCESS_STATE=SUPPORTED_NOT_LOCALIZED
WP2_CORRECTIVE_ATTRIBUTION=DISPROVEN
WP2_PRODUCTION_POLICY_ATTRIBUTION=NO_DIRECT_EVIDENCE
ROOT_CAUSE_PROVEN=NO
```

The uncommitted cleanup experiment is preserved in its local worktree as evidence and must not be reset/deleted implicitly. It is not part of PR #195.

## Evidence interpretation guardrails

- `Could not signal service com.apple.WebKit.WebContent: 113` remains an observation, not a root-cause signal. Platform guidance indicates this XPC service-not-found message may also occur during normal WebKit service shutdown.
- Do not assume a one-to-one causal mapping from `WKWebViewConfiguration` creation to a unique durable WebContent process. Actual process allocation/reuse is WebKit-controlled and implementation-dependent.
- The relevant failure boundary is the affected `WKWebView` state when JavaScript/focus assertions fail after accumulated suite activity.

## Current missing fact

```text
MISSING_FACT = Whether an affected WKWebView has experienced WebContent process termination/replacement or is otherwise not navigation/JavaScript-ready at the exact point the 13-case failure family begins after the long suite prefix.

BLOCKED_DECISION = Whether the next corrective belongs in test synchronization/process-state handling, test WebKit isolation architecture, or a deeper production/WebKit ownership boundary.
```

## Next gate

Run one bounded test-only diagnostic probe on a clean isolated diagnostic checkout of the current PR head. Preserve the dirty fixture-corrective worktree untouched.

The probe must correlate the first reproduced failing case with public WebKit lifecycle/navigation evidence, including process termination where observable, navigation completion/failure state, `isLoading`, URL, and the exact `evaluateJavaScript` result/error boundary.

Do not broaden into production code, data-store changes, process-pool policy, timeouts, test skipping, Browser Profile/session clearing, or WebKit helper killing/restarting merely to make the suite pass.

The previous whole-WP2 `main@2a528...` vs `6471780...` A/B is not the immediate next gate; it remains optional if the process-state probe cannot localize the failure.

## Preserved WP2 policy / safety boundary

- normal Runtime count is never a reclaim reason;
- Keep Loaded / Pinned is never automatically reclaimed by normal, warning, or critical FloatTabs policy;
- Automatic stages remain RECENT `<30s`, IDLE `>=30s && <600s`, LONG_IDLE `>=600s`;
- warning reclaims only eligible IDLE/LONG_IDLE Automatic progressively;
- critical may include RECENT Automatic but never Keep Loaded or hard-protected Runtime;
- pressure progression remains fresh-fact, oldest-first, one-step-at-a-time;
- WP1 presentation/readiness, generation/Attention, media/fullscreen, notification privacy/routing, and Browser Profile/session data safety remain regression boundaries.

Do not merge PR #195, release, or begin WP3/WP4 while the canonical full-XCTest gate is failing.
