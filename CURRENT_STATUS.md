# FloatTabs Current Status

**Status date:** 2026-11-03  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: ADAPTIVE LIFECYCLE — WP2 XCTEST WEBKIT FIXTURE LIFECYCLE CORRECTIVE**

Current task: `FT-ADAPTIVE-LIFECYCLE-RESTORE-001 / WP2-001` — **ACTIVE / TEST-HARNESS CORRECTIVE AUTHORIZED**.

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
INDEPENDENT_CORRECTIVE_DIFF_AUDIT=NO_POLICY_OR_OWNERSHIP_BLOCKER
CORRECTIVE_ATTRIBUTION=DISPROVEN
FULL_XCTEST=FAIL
SELF_HOSTED_CI=FAIL_AT_UNIT_TESTS
HUMAN_UI_ACCEPTANCE=BLOCKED_NOT_STARTED
PR_195=OPEN_DRAFT_UNMERGED
WP3=NOT_STARTED
WP4=NOT_STARTED
```

## XCTest incident — current evidence

Read-only diagnosis now establishes a concrete test-harness defect and a supported failure relationship:

- the same 13 WebFocusAdapter / WebViewFactory / WebsiteLayoutGeometryRegression methods fail after a long full-suite prefix but pass together in fresh XCTest processes;
- serial full-suite execution still fails, so parallel execution is not required;
- memory pressure stayed low while WebKit WebContent process count accumulated materially and logs reported `Could not signal service com.apple.WebKit.WebContent: 113` before failures;
- `WebFocusAdapterTests` creates real `WKWebView` + real borderless `NSWindow`, orders the window front, retains it in `retainedWindows`, and has no explicit fixture teardown;
- `WebViewFactoryTests` and `WebsiteLayoutGeometryRegressionTests` also create real WebKit/AppKit fixtures with incomplete or inconsistent explicit cleanup;
- the relevant test files are source-identical across pre-corrective/current WP2 comparison points, and no direct production `SlotLifecycleCoordinator` retain-cycle evidence was found.

Current verdict:

```text
WEBFOCUS_FIXTURE_TEARDOWN_OMISSION=CONFIRMED
TEST_ORDER_SHARED_STATE=STRONGLY_SUPPORTED
TEST_FIXTURE_RESOURCE_ACCUMULATION=SUPPORTED
WEBKIT_SHARED_HOST_ACCUMULATION=SUPPORTED_NOT_MECHANISM_PROVEN
WP2_CORRECTIVE_ATTRIBUTION=DISPROVEN
WP2_PRODUCTION_POLICY_ATTRIBUTION=NO_DIRECT_EVIDENCE
ROOT_CAUSE_PROVEN=NO
```

The exact WebKit/shared-process causal mechanism remains unknown. Do not promote correlation to a proven WebKit root cause.

## Direction change — corrective now authorized

The previous `main@2a528...` vs `6471780...` whole-WP2 attribution A/B is **no longer a blocking prerequisite** for repair. It may remain optional diagnostic evidence, but the active goal is now to repair the confirmed XCTest fixture lifecycle defect and use before/after suite behavior as the direct corrective test.

Authorized corrective scope:

1. add deterministic explicit teardown for real `WKWebView` / `NSWindow` fixtures in `WebFocusAdapterTests`;
2. audit and normalize equivalent fixture cleanup in `WebViewFactoryTests` and `WebsiteLayoutGeometryRegressionTests` where current cleanup is incomplete;
3. keep changes test-harness-only unless new evidence proves a production defect; production mutation requires task reconciliation first;
4. do not weaken assertions, skip tests, increase timeouts as a substitute for cleanup, clear Browser Profile/session/site data, or kill/restart WebKit helpers as proof;
5. use `.nonPersistent()` only where test semantics clearly do not require the default data store and the change is separately justified by the test intent.

## Corrective acceptance gate

Required machine evidence after the smallest harness fix:

```text
TARGETED_WEBKIT_FIXTURE_TESTS=PASS
AFFECTED_LIFECYCLE_REGRESSIONS=PASS
CANONICAL_FULL_XCTEST_RUN_1=PASS
CANONICAL_FULL_XCTEST_RUN_2=PASS
SELF_HOSTED_PR_CI=PASS
REQUIRED_QA_DMG_JOB=PASS_IF_TRIGGERED
NO_PRODUCTION_SOURCE_MUTATION=YES
```

Also record whether WebContent/window accumulation materially improves. This observation strengthens causality but does not replace the canonical test gate.

If the targeted cleanup is correct but canonical full XCTest still fails, stop after capturing the new failure family and resource observations; do not expand automatically into production lifecycle changes.

## Preserved WP2 policy / safety boundary

- normal Runtime count is never a reclaim reason;
- Keep Loaded / Pinned is never automatically reclaimed by normal, warning, or critical FloatTabs policy;
- Automatic stages remain RECENT `<30s`, IDLE `>=30s && <600s`, LONG_IDLE `>=600s`;
- warning reclaims only eligible IDLE/LONG_IDLE Automatic progressively;
- critical may include RECENT Automatic but never Keep Loaded or hard-protected Runtime;
- pressure progression remains fresh-fact, oldest-first, one-step-at-a-time;
- WP1 presentation/readiness, generation/Attention, media/fullscreen, notification privacy/routing, and Browser Profile/session data safety remain regression boundaries.

## Next gate

```text
XCTest WebKit fixture lifecycle corrective
→ targeted tests
→ canonical full XCTest twice
→ literal-head self-hosted PR CI
→ reconcile machine-gate disposition
→ only then decide Human UI acceptance
```

Do not merge PR #195, release, or begin WP3/WP4 before the corrective machine gate is complete.
