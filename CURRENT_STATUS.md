# FloatTabs Current Status

**Status date:** 2026-10-24
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: NO ACTIVE ENGINEERING TASK — v0.5.6 AIR OBSERVATION**

Most recently completed task: `FT-WEB-RUNTIME-RECOVERY-ATTENTION-001`

## Current verified baseline

```text
PRODUCT_MAIN_AFTER_PR144=4477a0f8a8d7d37a5202e209920e04b0330a93f6
MERGED_PR=144
FINAL_CORRECTIVE_SEMANTIC_HEAD=c63578e6e8163a28d210ef60987d7ccd39d51af1
PUBLIC_RELEASE=v0.5.6
PUBLIC_BUILD=24
ARCH=arm64
ROOT_CAUSE=UNKNOWN
```

PR #144 is merged. The accepted corrective improves FloatTabs-owned recovery/navigation identity, bounds ChatGPT Attention runtime request capacity by the physical WebContent runtime epoch, and projects bounded native Attention timeout/suppression health counters into Standard long-term diagnostics.

The corrective does **not** establish the root cause of the observed WebContent termination or non-termination stall/near-stall incidents. `ROOT_CAUSE=UNKNOWN` remains authoritative.

## Accepted behavior

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
```

No reload/reset/rebuild mitigation, residency-policy change, Browser Profile/session migration, private WebKit API, or content capture was added.

## Verification and merge evidence

```text
FULL_XCTEST=1367_PASS_0_FAIL_3_SKIPPED_OF_1370
DEBUG_ARM64=PASS
RELEASE_ARM64=PASS
LARGE_DOM_FIXTURE=PASS
SEMANTIC_MACOS_CI_1102=SUCCESS_40086444312
SEMANTIC_QA_DMG_514=SUCCESS_40086444322
PRE_ACCEPTANCE_CONTROL_MACOS_CI_1103=SUCCESS_40086995308
PRE_ACCEPTANCE_CONTROL_QA_DMG_515=SUCCESS_40086995311
FINAL_HEAD=8b71f42a6a516a86bb41a0ac038446d9405bf4c4
FINAL_HEAD_QA_DMG_517=SUCCESS_40087782157
FINAL_HEAD_MACOS_CI_1105=SUCCESS_40087782148_RERUN
FINAL_MERGE_AUDIT=PASS_WITH_FOLLOWUP
MERGE_COMMIT=4477a0f8a8d7d37a5202e209920e04b0330a93f6
POST_MERGE_MACOS_CI_1106=SUCCESS_40093073048
```

The first macOS CI attempt for the unchanged final head failed only in `WebViewPoolTests.testHiddenSelectedColdGetsRecentActiveGraceBeforeColdRelease`; the same exact head passed on rerun, and post-merge `main` CI also passed. This is recorded as a non-blocking timing-sensitive XCTest stability follow-up, not as evidence of a PR #144 product regression and not as a root-cause finding.

## Repository lifecycle

- PR #143: `CLOSED / SUPERSEDED / UNMERGED`.
- PR #144: `MERGED` at `4477a0f8a8d7d37a5202e209920e04b0330a93f6`.
- No release is authorized by this closeout.
- No product/runtime mutation is currently authorized.

## Observation next step

Continue normal use of the current v0.5.6 / Build 24 observation release. If a fresh slowdown, stall, or WebContent termination occurs, preserve/export Runtime Diagnostics before reload/restart when practical and correlate the incident by Slot, runtime identity, navigation state, Attention health counters, page-app trend, observer workload, and process-termination boundaries.
