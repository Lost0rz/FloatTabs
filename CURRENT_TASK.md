# FloatTabs Current Task

**Task ID:** FT-ADAPTIVE-LIFECYCLE-RESTORE-001
**Card ID:** FT-ADAPTIVE-LIFECYCLE-RESTORE-001-WP2-001
**Title:** Replace fixed-count normal Runtime reclaim with staged Automatic lifecycle
**Status:** ACTIVE / WP2 IMPLEMENTATION AUTHORIZED
**Mode:** SOURCE IMPLEMENTATION / ONE DRAFT PR / NO MERGE OR RELEASE
**Task class:** WEB RUNTIME / LIFECYCLE POLICY
**Baseline:** origin/main@2a52800f770266f7c901eb612a0b319ddca142df
**Branch:** codex/adaptive-lifecycle-wp2-policy
**PR:** #195 OPEN / DRAFT; do not reuse PR #194

## Authorization

Implement WP2 staged Automatic lifecycle policy after completing and remotely verifying the control/design-only bootstrap in this branch. PR #194 is merged; WP1 is complete and accepted. This task does not reopen WP1 and does not authorize WP3 scheduling or WP4 integration work.

Durable policy authority: [Runtime Lifecycle Policy V7](docs/architecture/FloatTabs_Runtime_Lifecycle_Policy_V7.md).
WP1 regression authority: [Adaptive Lifecycle Restore Contract V2](docs/architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md).

## Frozen product policy

- Remove the fixed normal resident-count reclaim policy. Runtime count is never a normal reclaim reason or RAM estimate.
- Keep Loaded / Pinned is never automatically reclaimed by normal, warning, or critical FloatTabs policy. Explicit user/config lifecycle actions retain their existing semantics; macOS external process termination is outside this policy.
- Automatic inactivity stages: RECENT <30s; IDLE >=30s and <600s; LONG_IDLE >=600s. Thirty seconds is anti-thrash protection, not destructive lifetime. Six hundred seconds is an initial tunable implementation default.
- Under normal pressure, RECENT and IDLE remain resident. An inactive, unprotected LONG_IDLE Automatic Runtime may hibernate exactly once for automatic_long_idle_expired.
- Warning progressively reclaims eligible inactive/unprotected IDLE or LONG_IDLE Automatic Runtime only. RECENT and Keep Loaded remain protected.
- Critical may bypass RECENT, but only inactive/unprotected Automatic Runtime are eligible. Keep Loaded/Pinned and all hard-protected Runtime are never candidates.
- Pressure reclaim is oldest-first and progressive, with current pressure/identity/protection revalidation after each step. Pressure normalization cancels pending continuation and does not restore already-reclaimed Runtime.
- SlotLifecycleCoordinator remains the sole lifecycle policy writer. Inactivity timers/plans are exact-token and generation bounded. Reactivation, visibility/current ownership, removal, or identity-invalidating change makes old callbacks no-ops. Protection end re-evaluates current facts with a fresh valid plan/token.
- Preserve generation/Attention, active media, fullscreen, supplemental visibility, WP1 presentation/readiness, notification privacy/routing, and all Browser Profile/session/login/cookie data.

The full policy, boundaries, diagnostic requirements, and 15 required regression cases are frozen in Policy V7.

## Explicitly forbidden

- Replacing target=2 with another fixed count;
- automatic reclaim of Keep Loaded/Pinned;
- inferring RAM from Runtime count;
- private WebKit SPI or helper-process killing;
- reload/reset/restart workarounds;
- clearing Browser Profile, login, cookies, session, cache, or conversation data;
- a second lifecycle policy writer or diagnostics as policy authority;
- changes to WP1 restore/session mechanics beyond call adaptation strictly required by the new lifecycle trigger;
- changes to generation detection, notification semantics, inactiveSchedulingPolicy, snapshots/screenshots, GiB budgets, or unrelated UI.

## Control-only bootstrap gate

Before product source mutation:

1. Fetch origin and verify PR #194 merged, fresh origin/main contains the merge, and the new branch starts from that exact fresh main.
2. Preserve the old WP1 branch/worktree and all unique local work.
3. Reconcile CURRENT_STATUS.md and this file to WP2.
4. Create Policy V7; update documentation routing and supersession notices only where needed.
5. Commit and push only the control/design bootstrap; verify the remote branch contains that commit.
6. Create one Draft PR separate from PR #194.

Product source mutation is authorized only after step 5 is remotely verified. The control bootstrap must not include source or test changes.

## Bootstrap completion

The control/design-only bootstrap is remotely verified:

~~~text
CONTROL_BOOTSTRAP_HEAD=e289171eff3d5045c48a86c229b7967e126ec087
REMOTE_REF=origin/codex/adaptive-lifecycle-wp2-policy
REMOTE_DELIVERY=PUSHED_VERIFIED
WP2_DRAFT_PR=195 / OPEN / DRAFT
~~~

The required source-mutation gate is satisfied. Continue implementation on this branch and PR only.

## Implementation boundary

Primary policy owner: FloatTabs/Web/SlotLifecycleCoordinator.swift. Inspect and adapt only the existing lifecycle policy/timer/pressure/diagnostic call paths needed for V7. Add or update focused lifecycle and integration regressions in current owning test files. WebViewPool remains mechanism-only and may change only for a call adaptation strictly required by the new trigger. Do not move policy into Panel, Tabs, notifications, or diagnostics.

## Required verification

Focused suites: lifecycle; WebAttentionLifecycleTests; WebAttentionCrossFeatureTests; WebViewPool reclaim regressions; ExternalShell/WP1 presentation regressions; affected runtime diagnostic/privacy tests.

Then full XCTest, Debug arm64, Release arm64, native arm64 verification, package-lock check, exact-head self-hosted macOS CI on [self-hosted, macOS, ARM64, mac-mini-ci], exact-head QA DMG, and a fresh independent exact-diff / ownership / data-safety audit. Do not infer exact-head evidence from earlier commits. Do not silently use hosted macOS CI.

The 15 acceptance cases are enumerated in Policy V7. Stop after machine evidence and independent audit. Do not merge or release. HUMAN_UI_ACCEPTANCE=PENDING / USER_OWNED until the user validates integrated real-Mac multi-Slot use, long-idle restore through the WP1 gate, pinned retention, background generation protection, and intact login/session/conversation.

## STOP conditions

Stop if PR #194 is not merged or fresh main lacks it; an overlapping predecessor has unknown unique work; source requires another lifecycle writer; normal reclaim still depends on Runtime count; Keep Loaded can be pressure-reclaimed; a stale token can reclaim a reactivated/current Runtime; WP1 restore/readiness or generation/media/fullscreen protection regresses; user/session data is mutated; private SPI/helper kill/reload/reset workaround is required; or a WP2-attributable required machine gate fails.

## Return contract

Return the verified values for:

~~~text
BASELINE_MAIN
CONTROL_BOOTSTRAP_HEAD
WP2_BRANCH
WP2_DRAFT_PR
FINAL_BRANCH_HEAD
CHANGED_FILES
REMOTE_DELIVERY
FIXED_RESIDENT_COUNT_REMOVED
AUTOMATIC_STAGE_MODEL
RECENT_30S_RESULT
IDLE_NORMAL_RESULT
LONG_IDLE_RESULT
PINNED_NORMAL_RESULT
PINNED_WARNING_RESULT
PINNED_CRITICAL_RESULT
WARNING_PRESSURE_RESULT
CRITICAL_PRESSURE_RESULT
PROTECTION_RESULT
STALE_PLAN_RESULT
PRESSURE_NORMALIZATION_RESULT
WP1_PRESENTATION_REGRESSION
WP1_A_B_A_REGRESSION
NOTIFICATION_REGRESSION
GENERATION_PROTECTION_REGRESSION
DATA_SAFETY_RESULT
FOCUSED_TESTS
FULL_XCTEST
DEBUG_BUILD
RELEASE_BUILD
ARM64_VERIFICATION
PACKAGE_LOCK
CI_STATE
QA_DMG_STATE
INDEPENDENT_AUDIT
HUMAN_UI_ACCEPTANCE=PENDING
WP3_SCHEDULING_MUTATION=NOT_STARTED
WP4_OTHER_MUTATION=NOT_STARTED
PR_STATE
~~~
