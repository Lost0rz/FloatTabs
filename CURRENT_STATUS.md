# FloatTabs Current Status

**Status date:** 2026-10-21
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: ACTIVE RELEASE — v0.5.6 / Build 24 / PR #142 GATES PENDING**

Current task: `FT-RELEASE-V0.5.6-001`

## Current verified baseline

```text
MAIN_AFTER_PR141=940fd8e80792eb32c5571bc6b159ffb7db13017f
SOURCE_PR=141
SOURCE_SEMANTIC_HEAD=e6f0fd8c671c720721fdc4b8ca71d2e993db3a89
LATEST_PUBLIC_RELEASE=v0.5.5
LATEST_PUBLIC_BUILD=23
TARGET_RELEASE=v0.5.6
TARGET_BUILD=24
RELEASE_PR=142
ARCH=arm64
ROOT_CAUSE=UNKNOWN
```

PR #141 is merged. Its accepted diagnostics-efficiency implementation reduces repetitive long-run logging, preserves identity-safe page-app deltas/rates, exposes bounded Release observer/workload evidence, and keeps long-term workload WebKit capture bounded by timeout and a single outstanding request budget.

The accepted source validation before merge included:

- focused bridge/diagnostics tests: 105 passed, 0 failed;
- privacy/rotation tests: 35 passed, 0 failed;
- full XCTest: 1,357 passed, 0 failed;
- Debug arm64 and Release arm64 builds: PASS;
- exact-head macOS CI and QA DMG: PASS;
- independent Web/runtime acceptance: PASS;
- representative periodic-log fixture reduction: 21,382 bytes to 13,702 bytes, 35.918% reduction; the 50% target was not claimed.

## Release preparation

Release branch `release/ft-v0.5.6` and Draft PR #142 are open against protected `main`.

Verified release-only tree delta currently consists of:

- `FloatTabs.xcodeproj/project.pbxproj` — app Debug/Release metadata at v0.5.6 / Build 24;
- `docs/release/FloatTabs_v0.5.6.md`;
- `CURRENT_STATUS.md`;
- `CURRENT_TASK.md`.

The temporary one-time metadata helper used on the release branch was removed before PR creation and is not part of the release PR tree delta.

## Release intent

v0.5.6 is an observation release for continued Air normal use. It publishes the accepted diagnostics-efficiency changes without adding new recovery or product behavior.

The release preserves these boundaries:

- no Browser Profile, cookie, session, WebsiteData, Slot, preference, backup, or diagnostic-history clearing/migration;
- no new automatic reload/reset/rebuild behavior;
- no private WebKit process attribution;
- no page text, prompt/response, selector text, cookies, tokens, or session values in diagnostics;
- root cause of the existing ChatGPT/WebKit slowdown/termination incident remains **UNKNOWN**.

## Release gates

Before publication:

1. merged source `main` at `940fd8e...` must pass post-merge macOS CI run `39620963744`;
2. release metadata must remain exactly v0.5.6 / Build 24 / arm64;
3. release PR #142 literal head must pass macOS CI and QA DMG;
4. release PR must not contain new product/runtime behavior;
5. post-merge release `main` CI must pass;
6. Publish Release must succeed and expose the expected DMG/checksum/dSYM assets with tag/target integrity.

Current gate state:

```text
SOURCE_POST_MERGE_CI=PENDING
RELEASE_PR_CI=PENDING
RELEASE_PR_QA_DMG=PENDING
PUBLICATION=PENDING
```

## Observation after release

Install v0.5.6 / Build 24 on the Air and use FloatTabs normally. If the sidebar/share/image-viewer slowdown, WebContent termination, or another runtime degradation occurs, preserve/export Runtime Diagnostics before reload/restart when practical and correlate the fresh evidence by time, Slot, runtime identity, page-app trend, observer workload, and termination boundaries.
