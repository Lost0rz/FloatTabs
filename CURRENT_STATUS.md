# FloatTabs Current Status

**Status date:** 2026-11-03  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: ADAPTIVE LIFECYCLE — WP2 XCTEST WEBKIT PROCESS-ISOLATION VALIDATION**

Current task: `FT-ADAPTIVE-LIFECYCLE-RESTORE-001 / WP2-001` — **ACTIVE / TEST-RUNNER ISOLATION A-B AUTHORIZED**.

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
SELF_HOSTED_CI=FAIL_AT_UNIT_TESTS
HUMAN_UI_ACCEPTANCE=BLOCKED_NOT_STARTED
PR_195=OPEN_DRAFT_UNMERGED
WP3=NOT_STARTED
WP4=NOT_STARTED
```

## Incident findings now established

Two prior bounded hypotheses are closed:

1. deterministic `WKWebView` / `NSWindow` fixture teardown is a real test-harness hygiene defect, but repairing it did not change the original 13-case full-suite failure family;
2. the affected WebViews are not terminated and their JavaScript engine remains live at failure time.

The process-state probe established the exact first-failure boundary:

```text
FRESH_AFFECTED_FAMILY=PASS_62_OF_62
LONG_PREFIX_FULL_SUITE=FAIL_SAME_13_CASE_FAMILY
AFFECTED_WEBVIEW_PROCESS_TERMINATION=DISPROVEN
AFFECTED_WEBVIEW_JS_NOT_READY=DISPROVEN
NAVIGATION_COMPLETION_MISMATCH=SUPPORTED
IS_LOADING_AT_FIRST_FAILURE=TRUE
NAVIGATION_CALLBACKS_AT_FIRST_FAILURE=NONE
MINIMAL_JS_LIVENESS=PASS_1_PLUS_1_EQUALS_2
TARGET_DOM_JS=FAIL_DOM_NOT_LOADED
ROOT_CAUSE_PROVEN=NO
```

For the first failing `WebFocusAdapterTests` case, `loadHTMLString(..., baseURL: https://chatgpt.com/)` was accepted but produced no provisional-start, commit, finish, or failure callback. `isLoading` stayed true through the settle boundary. At the same instant `evaluateJavaScript("1+1")` returned `2`, while DOM-dependent JavaScript failed because the expected loaded document never appeared.

This localizes the incident to a **navigation pipeline stall after accumulated same-XCTest-host WebKit activity**, not to WebContent termination, dead JavaScript execution, fixture teardown, or a proven WP2 production lifecycle defect.

Correlated WebKit/XPC errors remain supporting observations only. Their internal causal mechanism is not proven.

## Preserved experiments

The following local evidence must remain untouched until disposition:

- dirty fixture-cleanup experiment: `/Volumes/Jack-Dev/Projects/FloatTabs-adaptive-lifecycle-wp2-policy`;
- process-state diagnostic checkout: `/private/tmp/FloatTabs-WP2-DIAG-6a55`.

Neither experiment is part of PR #195.

## Current missing fact

```text
MISSING_FACT = Whether the complete canonical test inventory becomes stable when the three WebKit-heavy affected classes execute in a fresh XCTest process instead of after the accumulated main-suite prefix.

BLOCKED_DECISION = Whether the minimum safe corrective is XCTest/test-runner process isolation for WebKit-heavy integration tests, or whether the navigation stall persists across fresh-process partitioning and requires a deeper WebKit/test-architecture investigation.
```

## Next gate — process-isolation A/B

Run the exact test inventory without deleting, skipping, weakening, or reinterpreting any test:

1. **Partition A:** all canonical FloatTabs tests except `WebFocusAdapterTests`, `WebViewFactoryTests`, and `WebsiteLayoutGeometryRegressionTests` in one fresh XCTest process;
2. **Partition B:** those three excluded classes together in a second fresh XCTest process;
3. confirm union(A,B) equals the canonical test inventory and intersection(A,B) is empty;
4. repeat the two-part run once if the first split run is green, to establish stability.

Do not modify production source, WebsiteData semantics, process-pool policy, lifecycle policy, assertions, timeouts, Browser Profile/session data, or kill/restart WebKit helpers as proof.

If both partitions pass repeatedly with complete inventory coverage, the next corrective boundary may move to the test runner / CI execution architecture. If either partition still reproduces the navigation stall, stop and return the exact failure boundary before any corrective.

## Preserved WP2 policy / safety boundary

- normal Runtime count is never a reclaim reason;
- Keep Loaded / Pinned is never automatically reclaimed by normal, warning, or critical FloatTabs policy;
- Automatic stages remain RECENT `<30s`, IDLE `>=30s && <600s`, LONG_IDLE `>=600s`;
- warning reclaims only eligible IDLE/LONG_IDLE Automatic progressively;
- critical may include RECENT Automatic but never Keep Loaded or hard-protected Runtime;
- pressure progression remains fresh-fact, oldest-first, one-step-at-a-time;
- WP1 presentation/readiness, generation/Attention, media/fullscreen, notification privacy/routing, and Browser Profile/session data safety remain regression boundaries.

Do not merge PR #195, release, or begin WP3/WP4 while the machine XCTest gate is failing.
