# FloatTabs Current Status

**Status date:** 2026-11-03  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: ADAPTIVE LIFECYCLE — WP2 FULL-XCTEST INCIDENT / PR-LEVEL ATTRIBUTION VERIFY**

Current task: `FT-ADAPTIVE-LIFECYCLE-RESTORE-001 / WP2-001` — **ACTIVE / READ-ONLY PR-LEVEL ATTRIBUTION VERIFY**.

Branch: `codex/adaptive-lifecycle-wp2-policy`  
Draft PR: `#195`  
Baseline: `main@2a52800f770266f7c901eb612a0b319ddca142df`  
Original WP2 implementation evidence head: `647178030b5a448916537745e7a993e4eca0a238`  
WP2 corrective base head: `f0705747c6a095f24d50c9ffdac21675a1bfc662`  
WP2 corrective semantic head: `cc44537635ef451a78dc8894484c9ce9328de936`  
Durable policy: `docs/architecture/FloatTabs_Runtime_Lifecycle_Policy_V7.md`

## Verified WP2 / corrective state

```text
WP1=COMPLETE / HUMAN_ACCEPTED
WP2_FIXED_RESIDENT_COUNT=REMOVED
WP2_STAGED_AUTOMATIC_POLICY=IMPLEMENTED
WP2_CORRECTIVE_A=PASS
WP2_CORRECTIVE_B=PASS
WP2_CORRECTIVE_C=PASS
FOCUSED_CORRECTIVE_TESTS=PASS
AFFECTED_LIFECYCLE_WP1_REGRESSIONS=PASS
DEBUG_RELEASE_ARM64=PASS
NATIVE_ARM64=PASS
PACKAGE_LOCK=UNCHANGED
QA_DMG=PASS
INDEPENDENT_CORRECTIVE_DIFF_AUDIT=NO_POLICY_OR_OWNERSHIP_BLOCKER
CORRECTIVE_ATTRIBUTION=DISPROVEN
FULL_SUITE_ROOT_CAUSE=NARROWED
HUMAN_UI_ACCEPTANCE=BLOCKED_NOT_STARTED
PR_195=OPEN_DRAFT_UNMERGED
WP3_SCHEDULING_MUTATION=NOT_STARTED
WP4_OTHER_MUTATION=NOT_STARTED
```

## XCTest incident diagnosis result

Read-only incident diagnosis established:

- the same 13 WebFocusAdapter / WebViewFactory / WebsiteLayoutGeometryRegression methods fail in canonical full-suite runs on corrective base `f0705747...` and corrective semantic head `cc445376...`;
- all 13 pass together in fresh-process same-order and reverse-order batches;
- serial full-suite execution still fails, so parallel execution is not required;
- a long ordered prefix reproduces the first focus failure, while the target passes without that accumulated prefix;
- memory pressure remained low during comparable runs, while WebKit WebContent process count accumulated substantially and logs reported `Could not signal service com.apple.WebKit.WebContent: 113` before failures;
- the exact underlying WebKit/shared-process mechanism remains unknown.

Verdict:

```text
H1_CORRECTIVE_REGRESSION=DISPROVEN
H2_PREEXISTING_AT_CORRECTIVE_BASE=CONFIRMED
H3_TEST_ORDER_SHARED_STATE=STRONGLY_SUPPORTED
H4_WEBKIT_HOST_RESOURCE=UNPROVEN
H5_PARALLEL_CONCURRENCY=NOT_NECESSARY
CORRECTIVE_ATTRIBUTION=DISPROVEN
FULL_SUITE_ROOT_CAUSE=NARROWED
MUTATION_RECOMMENDATION=NONE
```

## Important identity fact

GitHub comparison confirms `647178030b5a448916537745e7a993e4eca0a238 → f0705747c6a095f24d50c9ffdac21675a1bfc662` changes only:

- `CURRENT_STATUS.md`
- `CURRENT_TASK.md`

There is no production-source or test-source delta between those two heads. Historical full XCTest passed at `6471780...`, while the current same-source/test `f070...` full run fails. This materially supports nondeterministic accumulated XCTest/WebKit host/shared-process state, but it does not by itself prove that the entire WP2 PR is unrelated because both refs already contain the WP2 implementation.

## Remaining gate — whole-WP2 attribution

Before WP2 may enter Human UI acceptance, close the remaining attribution question with a same-host/same-command read-only baseline comparison:

```text
main@2a52800f770266f7c901eb612a0b319ddca142df
vs
647178030b5a448916537745e7a993e4eca0a238
```

Use the canonical full-XCTest command on the same Mac/toolchain. If outcomes differ, alternate/repeat enough to determine whether the difference is stable.

Decision:

```text
if main and 647 reproduce the same failure family:
    WP2_PR_ATTRIBUTION=DISPROVEN

if main repeatedly passes and 647 repeatedly fails:
    WP2_PR_ATTRIBUTION=SUPPORTED / further localization required

if outcomes vary across identical-source/test reruns:
    WP2_PR_ATTRIBUTION=UNPROVEN / harness-host nondeterminism remains
```

No production/test mutation is authorized by this status.

## Preserved WP2 policy

- normal Runtime count is never a reclaim reason;
- Keep Loaded / Pinned is never automatically reclaimed by normal, warning, or critical FloatTabs policy;
- Automatic stages remain RECENT `<30s`, IDLE `>=30s && <600s`, LONG_IDLE `>=600s`;
- 30s remains anti-thrash protection; 600s remains the initial tunable long-idle default;
- warning reclaims only eligible IDLE/LONG_IDLE Automatic progressively;
- critical may include RECENT Automatic but never Keep Loaded or hard-protected Runtime;
- pressure progression remains fresh-fact, oldest-first, one-step-at-a-time;
- WP1 presentation/readiness, generation/Attention, media/fullscreen, notification privacy/routing, and Browser Profile/session data safety remain regression boundaries.

## Next gate

```text
same-host canonical full XCTest on main@2a528... and 6471780...
→ determine WP2_PR_ATTRIBUTION
→ reconcile machine-gate disposition
→ only then decide Human UI acceptance
```

Do not merge PR #195, release, or begin WP3/WP4 before that gate is complete.
