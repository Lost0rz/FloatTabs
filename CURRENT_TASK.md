# FloatTabs Current Task

**Task ID:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001`  
**Card ID:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001-WP2-001`  
**Title:** Replace fixed-count normal Runtime reclaim with staged Automatic lifecycle  
**Status:** **ACTIVE / WP2 FULL-XCTEST WEBKIT PROCESS-STATE INCIDENT DIAGNOSIS**  
**Mode:** `DIAGNOSE / TEST-ONLY PROBE AUTHORIZED / EXISTING DRAFT PR / NO PRODUCTION MUTATION / NO MERGE OR RELEASE`  
**Task class:** `WEB RUNTIME / LIFECYCLE POLICY + XCTEST WEBKIT INCIDENT`  
**Baseline:** `origin/main@2a52800f770266f7c901eb612a0b319ddca142df`  
**Branch:** `codex/adaptive-lifecycle-wp2-policy`  
**PR:** `#195 OPEN / DRAFT / UNMERGED`

## Authority

Durable WP2 policy: `docs/architecture/FloatTabs_Runtime_Lifecycle_Policy_V7.md`  
WP1 regression authority: `docs/architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md`

WP2 Correctives A/B/C remain implemented at semantic head `cc44537635ef451a78dc8894484c9ce9328de936`. Product policy remains frozen.

## Verified incident state

The bounded fixture teardown corrective has been falsified as a sufficient fix:

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
FIXTURE_CORRECTIVE_COMMIT=NONE
ROOT_CAUSE_PROVEN=NO
```

The fixture teardown omission is a real test-harness defect, but repairing it did not remove or materially alter the incident. Do not continue treating teardown cleanup as the primary root-cause line.

The failed corrective experiment remains uncommitted in `/Volumes/Jack-Dev/Projects/FloatTabs-adaptive-lifecycle-wp2-policy`. Preserve that worktree and its five changed files; do not reset/delete/commit them under this diagnostic task.

## Hard evidence gate

```text
MISSING_FACT = Whether an affected WKWebView has experienced WebContent process termination/replacement or is otherwise not navigation/JavaScript-ready at the exact point the 13-case failure family begins after the accumulated suite prefix.

BLOCKED_DECISION = Whether the next corrective belongs in test synchronization/process-state handling, test WebKit isolation architecture, or a deeper production/WebKit ownership boundary.
```

`Could not signal service com.apple.WebKit.WebContent: 113` is observational evidence only. Do not use its count as root-cause proof. Likewise, do not assume a new `WKWebViewConfiguration` implies a uniquely owned durable WebContent process; process allocation/reuse is WebKit-controlled.

## Current authorization — bounded test-only process-state probe

Use a clean isolated diagnostic checkout of the current PR head. Do not modify the dirty fixture-corrective worktree.

The probe may add temporary test-only instrumentation solely to establish the missing fact above.

Capture, for the first reproducible failing WebKit-dependent case and a fresh-process passing control where practical:

- test/method identity and timestamps;
- WebView object identity available from public/test-visible state;
- navigation start/finish/failure callbacks where already owned or safely observable;
- `webViewWebContentProcessDidTerminate(_:)` if it can be observed without replacing production delegate behavior;
- `isLoading`, URL and navigation state immediately before the failing assertion;
- exact `evaluateJavaScript` completion value and error;
- whether the same WebView can execute a minimal side-effect-free JS liveness probe at that boundary;
- relevant public WebKit/XCTest log events in the same time window.

Prefer existing delegate/observer seams. If a test-only multiplexer/proxy is required, keep it local to the diagnostic checkout and prove that the targeted tests still pass fresh before using it for the long-prefix reproduction.

Do not add broad telemetry or a permanent diagnostic framework.

## Probe decision matrix

Return one of these bounded findings:

```text
AFFECTED_WEBVIEW_PROCESS_TERMINATION=SUPPORTED | DISPROVEN | UNPROVEN
AFFECTED_WEBVIEW_JS_NOT_READY=SUPPORTED | DISPROVEN | UNPROVEN
NAVIGATION_COMPLETION_MISMATCH=SUPPORTED | DISPROVEN | UNPROVEN
```

Interpretation:

- If termination/replacement is observed immediately before the failure, localize why the test/runtime continues to use that WebView before proposing a fix.
- If no termination is observed but navigation/JS readiness is absent, localize the missing readiness boundary before proposing synchronization changes.
- If the WebView is demonstrably live/ready and JS still fails only after accumulated host state, stop with that evidence; then a separate WebKit isolation/process-churn experiment may be reconciled.

Do not implement a corrective in the same diagnostic pass.

## Mutation boundary

Authorized:

- temporary test-only diagnostic instrumentation in a clean isolated diagnostic checkout;
- local diagnostic logs/artifacts outside the repository;
- running targeted/fresh/long-prefix XCTest probes needed to establish the missing fact.

Not authorized:

- production source mutation;
- changing website data-store semantics;
- changing process-pool policy;
- changing lifecycle policy;
- committing/pushing diagnostic instrumentation;
- committing/pushing the preserved fixture-cleanup experiment;
- test skipping/assertion weakening;
- increasing timeouts as a fix;
- Browser Profile/session/cookie/website-data clearing;
- private WebKit SPI;
- killing/restarting WebKit helpers as root-cause proof;
- WP3/WP4 implementation;
- merge/release.

## Verification / STOP

First verify the diagnostic instrumentation does not break the affected test family in a fresh process. Then reproduce the smallest known long-prefix path that reaches the first failure and capture the process/navigation/JS state at that boundary.

STOP once the missing fact is established or the bounded probe cannot establish it. Do not continue into corrective implementation.

The previous whole-WP2 `main@2a528...` vs `6471780...` full-suite A/B is not the immediate gate. It remains optional evidence if this bounded process-state diagnosis cannot distinguish the mechanism.

## Frozen product/regression boundary

Preserve:

- no fixed normal resident count;
- Keep Loaded/Pinned never FloatTabs-auto-reclaimed under normal/warning/critical;
- RECENT `<30s`, IDLE `30s..<600s`, LONG_IDLE `>=600s`;
- progressive fresh-fact pressure reclaim;
- WP1 presentation/readiness;
- generation/media/fullscreen protection;
- Browser Profile/session/login/cookie data safety.

## Return contract

```text
DIAGNOSTIC_CHECKOUT
AUTHORITY_HEAD
INSTRUMENTATION_FILES_CHANGED
FRESH_CONTROL_RESULT
LONG_PREFIX_REPRO_RESULT
FIRST_FAILING_CASE
FIRST_FAILURE_TIMESTAMP
WEBVIEW_IDENTITY
PROCESS_TERMINATION_EVENT
NAVIGATION_STATE_AT_FAILURE
IS_LOADING_AT_FAILURE
URL_AT_FAILURE
EVALUATE_JAVASCRIPT_VALUE
EVALUATE_JAVASCRIPT_ERROR
MINIMAL_JS_LIVENESS_RESULT
CORRELATED_WEBKIT_EVENTS
AFFECTED_WEBVIEW_PROCESS_TERMINATION
AFFECTED_WEBVIEW_JS_NOT_READY
NAVIGATION_COMPLETION_MISMATCH
ROOT_CAUSE_PROVEN
RECOMMENDED_NEXT_BOUNDARY
COMMIT=NONE
PUSH=NONE
PRODUCTION_FILES_CHANGED=NONE
PRESERVED_FIXTURE_WORKTREE=UNCHANGED
HUMAN_UI_ACCEPTANCE=BLOCKED_NOT_STARTED
WP3_SCHEDULING_MUTATION=NOT_STARTED
WP4_OTHER_MUTATION=NOT_STARTED
PR_STATE
```

Do not merge PR #195. Do not release.
