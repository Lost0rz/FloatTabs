# FloatTabs Current Task

**Task ID:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001`  
**Card ID:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001-WP2-001`  
**Title:** Replace fixed-count normal Runtime reclaim with staged Automatic lifecycle  
**Status:** **ACTIVE / WP2 PR-LEVEL XCTEST ATTRIBUTION VERIFY**  
**Mode:** `READ-ONLY VERIFY / EXISTING DRAFT PR / NO PRODUCT OR TEST MUTATION / NO MERGE OR RELEASE`  
**Task class:** `WEB RUNTIME / LIFECYCLE POLICY`  
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
PACKAGE_LOCK=UNCHANGED
QA_DMG=PASS
INDEPENDENT_CORRECTIVE_DIFF_AUDIT=NO_POLICY_OR_OWNERSHIP_BLOCKER
CORRECTIVE_ATTRIBUTION=DISPROVEN
FULL_SUITE_ROOT_CAUSE=NARROWED
MUTATION_RECOMMENDATION=NONE
HUMAN_UI_ACCEPTANCE=BLOCKED_NOT_STARTED
WP3_SCHEDULING_MUTATION=NOT_STARTED
WP4_OTHER_MUTATION=NOT_STARTED
```

The read-only incident diagnosis reproduced the same 13-method full-suite failure on both corrective base `f0705747c6a095f24d50c9ffdac21675a1bfc662` and corrective semantic head `cc44537635ef451a78dc8894484c9ce9328de936`. The 13 methods pass in fresh-process same-order and reverse-order batches. Serial full-suite execution still fails. A long ordered prefix is required to reproduce the first focus failure. This disproves attribution to Correctives A/B/C and strongly supports cumulative XCTest/WebKit shared-process state; the exact mechanism is still unknown.

GitHub comparison additionally confirms that `647178030b5a448916537745e7a993e4eca0a238 → f0705747c6a095f24d50c9ffdac21675a1bfc662` modifies only `CURRENT_STATUS.md` and `CURRENT_TASK.md`, with no source/test delta. Historical full XCTest passed at `6471780...`, while a current same-source/test run at `f070...` fails, reinforcing nondeterministic host/shared-process evidence.

## Current authorization — final read-only WP2 PR attribution check

The remaining decision is not whether Correctives A/B/C caused the failure; that question is closed as `DISPROVEN`.

The remaining decision is whether the full-suite failure is attributable to the WP2 PR as a whole or is independently reproducible on the pre-WP2 baseline.

Run the canonical full-XCTest command under the same Mac/toolchain/environment on clean isolated checkouts of:

1. `main@2a52800f770266f7c901eb612a0b319ddca142df`
2. `647178030b5a448916537745e7a993e4eca0a238`

Use the same invocation used by self-hosted CI. Do not edit source/tests/workflow. Do not clear caches, website data, Browser Profiles, or kill/restart WebKit helpers as part of the primary comparison.

If the first A/B outcomes differ, alternate/repeat enough to distinguish a stable ref-dependent difference from nondeterministic host/shared-process behavior.

## Required decision

Return exactly one whole-PR attribution verdict:

```text
WP2_PR_ATTRIBUTION=DISPROVEN
WP2_PR_ATTRIBUTION=SUPPORTED
WP2_PR_ATTRIBUTION=UNPROVEN
```

Interpretation:

- `DISPROVEN`: pre-WP2 main reproduces the same material failure family under comparable conditions.
- `SUPPORTED`: main repeatedly passes while the WP2 implementation ref repeatedly fails under comparable conditions; further localization is required before mutation.
- `UNPROVEN`: outcomes vary or evidence is otherwise insufficient to distinguish ref effect from harness/host nondeterminism.

Also return:

```text
MAIN_BASELINE_FULL_XCTEST_RESULT
WP2_647_FULL_XCTEST_RESULT
ALTERNATING_REPEAT_RESULT
FAILURE_SET_COMPARISON
HOST_TOOLCHAIN_IDENTITY
WP2_PR_ATTRIBUTION
FULL_SUITE_ROOT_CAUSE
MUTATION_RECOMMENDATION
```

## Machine-gate disposition

Do not promote Human UI acceptance yet.

After the whole-PR attribution verdict:

- if WP2 attribution is `SUPPORTED`, stop and reconcile a bounded corrective/diagnostic scope before mutation;
- if attribution is `DISPROVEN`, return to Project Governance to decide how the known unrelated harness/full-suite failure should be dispositioned without weakening or silently bypassing the canonical test gate;
- if attribution is `UNPROVEN`, keep the machine gate blocked and return the unresolved evidence.

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

Stop and report evidence if verification would require:
- product source/test mutation;
- CI workflow mutation;
- increasing timeouts or disabling tests;
- clearing Browser Profile/session/cache/website data;
- private WebKit SPI;
- killing/restarting WebKit helpers as root-cause proof;
- entering WP3/WP4;
- merge/release.

## Return contract

```text
DIAGNOSTIC_BASELINE
MAIN_BASELINE_FULL_XCTEST_RESULT
WP2_647_FULL_XCTEST_RESULT
ALTERNATING_REPEAT_RESULT
FAILURE_SET_COMPARISON
HOST_TOOLCHAIN_IDENTITY
WP2_PR_ATTRIBUTION
FULL_SUITE_ROOT_CAUSE
MUTATION_RECOMMENDATION
HUMAN_UI_ACCEPTANCE=BLOCKED_NOT_STARTED
WP3_SCHEDULING_MUTATION=NOT_STARTED
WP4_OTHER_MUTATION=NOT_STARTED
PR_STATE
```

Do not merge PR #195. Do not release.
