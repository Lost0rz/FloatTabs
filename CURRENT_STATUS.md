# FloatTabs Current Status

**Status date:** 2026-10-24
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: ACTIVE CORRECTIVE — INDEPENDENT WEB/RUNTIME ACCEPTANCE PASS / FINAL MERGE AUDIT PENDING**

Current task: `FT-WEB-RUNTIME-RECOVERY-ATTENTION-001`

## Verified baseline

```text
MAIN=17f1bf1760625833d0b82397009223b2165521c7
LATEST_RELEASE=v0.5.6
BUILD=24
ARCH=arm64
TASK_BRANCH=codex/ft-web-runtime-recovery-attention-001
TASK_PR=144_OPEN_DRAFT_UNMERGED
FINAL_CORRECTIVE_SEMANTIC_HEAD=c63578e6e8163a28d210ef60987d7ccd39d51af1
PRE_ACCEPTANCE_CONTROL_HEAD=50f688f069cd14758853493d80ed9e74aa2a330b
ROOT_CAUSE=UNKNOWN
```

v0.5.6 remains an observation release. Repeated WebContent process termination and non-termination runtime stall/near-stall remain real incident evidence; no shared root cause is established.

## Independent Web/runtime acceptance

Fresh independent re-audit of PR #144 at semantic head `c63578e6e8163a28d210ef60987d7ccd39d51af1` is **PASS**.

Accepted implementation state:

```text
RECOVERY_NAVIGATION_IDENTITY=PASS
RECOVERY_COMMIT_WITHOUT_PROVISIONAL=PASS
RECOVERY_FINISH_STATE=PASS
STALE_RECOVERY_CALLBACK_REJECTION=PASS
DEFERRED_RECOVERY_EXACT_NAVIGATION=PASS
POST_FINISH_STALL_ELIGIBILITY=PASS
PHYSICAL_RUNTIME_EPOCH=PASS
SAME_RUNTIME_REQUEST_BUDGET_BOUNDING=PASS
ORDINARY_DOCUMENT_REPLACEMENT_NO_NEW_CAPACITY=PASS
PHYSICAL_REPLACEMENT_FRESH_CAPACITY=PASS
OLD_EPOCH_CALLBACK_NOOP=PASS
ATTENTION_HOT_PATH_OPTIMIZATION=PASS
STANDARD_NATIVE_COUNTER_STORAGE=PASS
STANDARD_FAILURE_STATE_PROJECTION=PASS
STANDARD_EARLY_SUPPRESSION_PROJECTION=PASS
PRIVACY_DATA_SAFETY=PASS
INDEPENDENT_WEB_RUNTIME_ACCEPTANCE=PASS
ROOT_CAUSE=UNKNOWN
```

No new production blocker was found in the final corrective.

## Final corrective evidence

Semantic implementation commit:

`c63578e6e8163a28d210ef60987d7ccd39d51af1`

The final corrective:

- projects the four bounded native Attention timeout/suppression counters into long-term diagnostic fields for normal, unavailable, timeout, stale, evaluation-failed, and early-suppressed outcomes without an extra JavaScript probe;
- preserves bridge-lifetime health evidence independently from document admission;
- proves ordinary document replacement cannot manufacture liveness physical-request capacity;
- proves authoritative WebContent replacement restores a fresh finite request budget and old callbacks remain harmless;
- proves inactive deferred recovery retains exact returned `WKNavigation` identity through commit/finish;
- proves recovered `navigation_phase=finished` restores post-finish dual-timeout stall-candidate eligibility;
- does not change recovery disposition, residency policy, Browser Profile/session data, or detector/liveness cadence.

Verification receipts:

```text
FULL_XCTEST=1367_PASS_0_FAIL_3_SKIPPED_OF_1370
DEBUG_ARM64=PASS
RELEASE_ARM64=PASS
LARGE_DOM_FIXTURE=PASS
GIT_DIFF_CHECK=PASS
SEMANTIC_MACOS_CI_1102=SUCCESS_40086444312
SEMANTIC_QA_DMG_514=SUCCESS_40086444322
PRE_ACCEPTANCE_CONTROL_MACOS_CI_1103=SUCCESS_40086995308
PRE_ACCEPTANCE_CONTROL_QA_DMG_515=SUCCESS_40086995311
```

## Safety boundary

No authorization or evidence to:

- claim the WebContent termination/stall root cause is known;
- add reload/reset/rebuild/restart mitigation;
- change Hot/Warm/Cold residency policy;
- clear or migrate Browser Profiles, cookies, sessions, WebsiteData, Slots, preferences, backups, or diagnostics history;
- use private WebKit APIs;
- capture prompt/response text, page content, selector text, cookies, tokens, or session values.

## Repository lifecycle

- PR #143 remains `CLOSED / SUPERSEDED / UNMERGED`.
- PR #144 remains `OPEN / DRAFT / UNMERGED` pending literal-final-head verification and final merge audit.
- No further production mutation is authorized by this acceptance unless a new blocking finding appears.

## Next milestone

1. verify the new control-only final PR head differs from the accepted semantic head only by `CURRENT_STATUS.md` / `CURRENT_TASK.md`;
2. wait for literal-final-head macOS CI and QA DMG to complete successfully;
3. perform final merge audit;
4. if no base/head drift or new blocker appears, PR #144 may be marked Ready and merged;
5. any later release remains separately authorized; `ROOT_CAUSE=UNKNOWN` must remain explicit.
