# FloatTabs Current Task

**Task ID:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001`  
**Card ID:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001-WP2-001`  
**Title:** Replace fixed-count normal Runtime reclaim with staged Automatic lifecycle  
**Status:** **ACTIVE / WP2 XCTEST WEBKIT FIXTURE LIFECYCLE CORRECTIVE**  
**Mode:** `TEST-HARNESS EXECUTE / EXISTING DRAFT PR / NO PRODUCTION MUTATION / NO MERGE OR RELEASE`  
**Task class:** `WEB RUNTIME / LIFECYCLE POLICY + XCTEST HARNESS CORRECTIVE`  
**Baseline:** `origin/main@2a52800f770266f7c901eb612a0b319ddca142df`  
**Branch:** `codex/adaptive-lifecycle-wp2-policy`  
**PR:** `#195 OPEN / DRAFT / UNMERGED`

## Authority

Durable WP2 policy: `docs/architecture/FloatTabs_Runtime_Lifecycle_Policy_V7.md`  
WP1 regression authority: `docs/architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md`

WP2 Correctives A/B/C are implemented at semantic head `cc44537635ef451a78dc8894484c9ce9328de936`. Product policy remains frozen.

## Verified diagnosis state

```text
CORRECTIVE_A_HOSTED_RELEASE=PASS
CORRECTIVE_B_STALE_ASYNC_PRESSURE=PASS
CORRECTIVE_C_INJECTED_TIME=PASS
FOCUSED_CORRECTIVE_TESTS=PASS
AFFECTED_LIFECYCLE_WP1_REGRESSIONS=PASS
DEBUG_RELEASE_ARM64=PASS
QA_DMG=PASS
CORRECTIVE_ATTRIBUTION=DISPROVEN
WEBFOCUS_FIXTURE_TEARDOWN_OMISSION=CONFIRMED
TEST_ORDER_SHARED_STATE=STRONGLY_SUPPORTED
TEST_FIXTURE_RESOURCE_ACCUMULATION=SUPPORTED
WEBKIT_SHARED_HOST_ACCUMULATION=SUPPORTED_NOT_MECHANISM_PROVEN
WP2_PRODUCTION_POLICY_ATTRIBUTION=NO_DIRECT_EVIDENCE
ROOT_CAUSE_PROVEN=NO
HUMAN_UI_ACCEPTANCE=BLOCKED_NOT_STARTED
WP3_SCHEDULING_MUTATION=NOT_STARTED
WP4_OTHER_MUTATION=NOT_STARTED
```

Evidence supporting corrective action:

- the 13-method WebFocusAdapter / WebViewFactory / WebsiteLayoutGeometryRegression failure family passes in fresh XCTest processes but fails after a long accumulated suite prefix;
- serial execution still fails, so parallel execution is not necessary;
- WebContent process count accumulated during long runs while memory pressure stayed low, and logs showed `Could not signal service com.apple.WebKit.WebContent: 113` before failures;
- `WebFocusAdapterTests` creates real ordered-front `NSWindow` + `WKWebView` fixtures retained in `retainedWindows` with no explicit teardown;
- related Factory/Geometry tests also use real WebKit/AppKit fixtures with partial/inconsistent explicit cleanup;
- no direct production `SlotLifecycleCoordinator` retain-cycle evidence has been established.

The exact WebKit/shared-process causal mechanism remains unknown. The confirmed actionable defect is the test fixture lifecycle omission; its causal contribution to the full-suite incident is supported and will be tested by the corrective itself.

## Current authorization — test-harness corrective

The previous whole-WP2 `main@2a528...` vs `6471780...` attribution A/B is not a required prerequisite for this corrective.

Implement the smallest deterministic XCTest fixture lifecycle repair within the existing PR/workspace.

### Primary scope

`WebFocusAdapterTests`

- establish explicit cleanup for every real `WKWebView` / `NSWindow` fixture created by the class;
- stop active loading before release where applicable;
- clear WebKit delegates/handlers owned by the fixture where safe and relevant;
- detach WebView/content ownership from its host window;
- order out / close real windows rather than relying only on XCTest instance deallocation;
- release retained test references at the test boundary;
- preserve existing behavioral assertions and production semantics.

### Secondary bounded scope

Audit and normalize equivalent real WebKit/AppKit fixture cleanup only where needed in:

- `WebViewFactoryTests`
- `WebsiteLayoutGeometryRegressionTests`

A shared test-only cleanup helper may be introduced if it reduces duplication without changing product behavior.

Use `.nonPersistent()` only for a test whose semantics clearly do not require the default website data store; document the justification in the diff/receipt. Do not use data-store changes merely to mask missing lifecycle cleanup.

## Mutation boundary

Authorized:

- test source changes required for deterministic fixture teardown;
- test-only helper changes required by the same cleanup;
- control-file updates reflecting verified outcome;
- normal commit/push to the existing PR branch after verification.

Not authorized without task reconciliation:

- production `SlotLifecycleCoordinator`, `WebViewPool`, `WebViewFactory`, profile/session/persistence behavior changes;
- lifecycle policy changes;
- CI workflow weakening;
- test skipping or assertion weakening;
- increasing timeouts as the fix;
- Browser Profile/session/cookie/website-data clearing;
- private WebKit SPI;
- killing/restarting WebKit helpers as root-cause proof;
- WP3/WP4 implementation;
- merge or release.

If test-only repair is insufficient and evidence points to production ownership, STOP and return the evidence before expanding scope.

## Verification / acceptance

Run the smallest relevant verification first, then the canonical gate.

Required:

```text
TARGETED_WEBFOCUS_TESTS=PASS
TARGETED_FACTORY_GEOMETRY_TESTS=PASS_IF_CHANGED
AFFECTED_LIFECYCLE_REGRESSIONS=PASS
CANONICAL_FULL_XCTEST_RUN_1=PASS
CANONICAL_FULL_XCTEST_RUN_2=PASS
SELF_HOSTED_PR_CI=PASS
REQUIRED_QA_DMG_JOB=PASS_IF_TRIGGERED
NO_PRODUCTION_SOURCE_MUTATION=YES
```

For the two full-suite runs, use the repository canonical/self-hosted CI XCTest invocation and fresh test processes. Do not kill WebKit helpers between runs to manufacture isolation.

Capture before/after observational evidence where practical:

```text
WEBCONTENT_PROCESS_COUNT_TREND
WINDOW_RETENTION_TREND_IF_OBSERVABLE
ORIGINAL_13_METHOD_FAILURE_FAMILY_PRESENT_OR_ABSENT
```

Those observations support causal confidence but do not substitute for the canonical full-suite/CI gate.

If full XCTest still fails after the bounded cleanup, return the new exact failure set and resource observations and STOP. Do not automatically change production code.

## Frozen product/regression boundary

Preserve:

- no fixed normal resident count;
- Keep Loaded/Pinned never FloatTabs-auto-reclaimed under normal/warning/critical;
- RECENT `<30s`, IDLE `30s..<600s`, LONG_IDLE `>=600s`;
- progressive fresh-fact pressure reclaim;
- WP1 presentation/readiness;
- generation/media/fullscreen protection;
- Browser Profile/session/login/cookie data safety.

## Human / merge gate

Human UI acceptance remains blocked until the corrective machine gate is green.

Do not merge PR #195 or release. After machine verification passes, return to Project Governance for exact-diff/control reconciliation and the next acceptance decision.

## Return contract

```text
START_HEAD
FINAL_HEAD
FILES_CHANGED
PRODUCTION_FILES_CHANGED
TEST_FIXTURE_CHANGES
TARGETED_WEBFOCUS_TESTS
TARGETED_FACTORY_GEOMETRY_TESTS
AFFECTED_LIFECYCLE_REGRESSIONS
CANONICAL_FULL_XCTEST_RUN_1
CANONICAL_FULL_XCTEST_RUN_2
SELF_HOSTED_PR_CI
REQUIRED_QA_DMG_JOB
WEBCONTENT_PROCESS_COUNT_TREND
WINDOW_RETENTION_TREND_IF_OBSERVABLE
ORIGINAL_13_METHOD_FAILURE_FAMILY
ROOT_CAUSE_PROVEN
TEST_FIXTURE_RESOURCE_ACCUMULATION
GIT_STATUS
REMOTE_BRANCH_HEAD
PR_STATE
HUMAN_UI_ACCEPTANCE=BLOCKED_NOT_STARTED
WP3_SCHEDULING_MUTATION=NOT_STARTED
WP4_OTHER_MUTATION=NOT_STARTED
```

Do not merge PR #195. Do not release.
