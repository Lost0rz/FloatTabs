# FloatTabs Current Task

**Task ID:** `FT-WEB-RUNTIME-RECOVERY-ATTENTION-001`
**Title:** Correct recovery navigation state and reduce bounded ChatGPT attention runtime overhead
**Status:** `TERMINAL — MERGED / POST-MERGE VERIFIED`
**Mode:** `TERMINAL`
**Task class:** `CORRECTIVE`

> This task is complete and grants no further product, release, branch, data, or recovery authority.

## Terminal result

PR #144 was independently accepted, passed the final merge gate, merged to protected `main`, and passed post-merge macOS CI.

```text
BASE_MAIN=17f1bf1760625833d0b82397009223b2165521c7
PUBLIC_RELEASE=v0.5.6
PUBLIC_BUILD=24
ARCH=arm64
PR=144
FINAL_CORRECTIVE_SEMANTIC_HEAD=c63578e6e8163a28d210ef60987d7ccd39d51af1
FINAL_PR_HEAD=8b71f42a6a516a86bb41a0ac038446d9405bf4c4
MERGE_COMMIT=4477a0f8a8d7d37a5202e209920e04b0330a93f6
ROOT_CAUSE=UNKNOWN
BUG_FIXED_CLAIM=NO
RELEASE_AUTHORIZED=NO
```

## Accepted corrective

- Retain and register the exact `WKNavigation` identity for immediate and deferred recovery before commit/finish handling.
- Reject stale/superseded recovery callbacks and restore correct finished navigation state after recovery.
- Restore post-finish stall-candidate eligibility after recovered navigation completes.
- Own finite liveness/resync request capacity by the physical WebContent runtime epoch rather than ordinary document replacement.
- Restore a fresh finite request budget only on authoritative WebContent process replacement; late old-epoch callbacks remain harmless.
- Preserve the accepted ChatGPT Attention hot-path optimization and cadence.
- Project bounded native Attention timeout/suppression counters into Standard diagnostics across normal and failure/suppression outcomes without adding another JavaScript probe.

No new reload/reset/rebuild mitigation, Hot/Warm/Cold residency behavior, Browser Profile/session migration, private WebKit API, or page/prompt/response content capture was added.

## Verification evidence

```text
FOCUSED_AND_RELATED_TESTS=PASS
FULL_XCTEST=1367_PASS_0_FAIL_3_SKIPPED_OF_1370
DEBUG_ARM64=PASS
RELEASE_ARM64=PASS
LARGE_DOM_FIXTURE=PASS
GIT_DIFF_CHECK=PASS
SEMANTIC_MACOS_CI_1102=SUCCESS_40086444312
SEMANTIC_QA_DMG_514=SUCCESS_40086444322
PRE_ACCEPTANCE_CONTROL_MACOS_CI_1103=SUCCESS_40086995308
PRE_ACCEPTANCE_CONTROL_QA_DMG_515=SUCCESS_40086995311
INDEPENDENT_WEB_RUNTIME_ACCEPTANCE=PASS
FINAL_HEAD_QA_DMG_517=SUCCESS_40087782157
FINAL_HEAD_MACOS_CI_1105=SUCCESS_40087782148_RERUN
FINAL_MERGE_AUDIT=PASS_WITH_FOLLOWUP
POST_MERGE_MACOS_CI_1106=SUCCESS_40093073048
```

## CI stability note

The first macOS CI attempt at final head `8b71f42a...` failed only in `WebViewPoolTests.testHiddenSelectedColdGetsRecentActiveGraceBeforeColdRelease`. The exact same head passed on rerun and the merged `main` passed post-merge CI. Treat that result as a timing-sensitive XCTest stability follow-up. It is not evidence that PR #144 introduced a product regression, and it does not change `ROOT_CAUSE=UNKNOWN`.

## Safety / durable boundary

- Do not claim the WebContent termination/stall root cause is known.
- Do not infer root cause from reload/reset/restart recovery.
- Do not clear or migrate Browser Profiles, cookies, sessions, WebsiteData, Slots, preferences, backups, or diagnostic history as ordinary recovery.
- Any future release requires separate authorization.
- Any test-stability corrective is a separate bounded task if pursued.

## Delivery

```text
PR_STATE=MERGED
POST_MERGE_VERIFICATION=PASS
TASK_STATE=TERMINAL
ROOT_CAUSE=UNKNOWN
RELEASE=NOT_AUTHORIZED
NEXT=NORMAL_V0.5.6_OBSERVATION_OR_NEW_EXPLICIT_TASK
```
