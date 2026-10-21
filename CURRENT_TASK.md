# FloatTabs Current Task

**Task ID:** `FT-RELEASE-V0.5.6-001`
**Title:** Publish FloatTabs v0.5.6 diagnostics-efficiency observation release
**Status:** `TERMINAL — PUBLISHED / VERIFIED`
**Mode:** `TERMINAL`
**Task class:** `RELEASE`

> This release task is complete and grants no further product, release, branch, data, or recovery mutation authority.

## Terminal result

FloatTabs v0.5.6 / Build 24 has been merged, published, and verified as the current public observation release for continued long-term normal use on the Air.

```text
VERSION=0.5.6
BUILD=24
ARCH=arm64
SOURCE_PR=141
SOURCE_MERGE=940fd8e80792eb32c5571bc6b159ffb7db13017f
SOURCE_SEMANTIC_HEAD=e6f0fd8c671c720721fdc4b8ca71d2e993db3a89
RELEASE_PR=142
RELEASE_COMMIT=17f1bf1760625833d0b82397009223b2165521c7
TAG=v0.5.6
TAG_TARGET=17f1bf1760625833d0b82397009223b2165521c7
SOURCE_POST_MERGE_CI=39620963744_PASS
RELEASE_PR_EXACT_CI=39622419627_PASS
RELEASE_PR_EXACT_QA_DMG=39622419742_PASS
PUBLISH_RUN=39623668661_PASS
POST_MERGE_MAIN_CI=39623668662_PASS
PUBLIC_RELEASE_ID=256913481
ROOT_CAUSE=UNKNOWN
BUG_FIXED_CLAIM=NO
RELEASE_STATE=PUBLISHED_VERIFIED
```

## Published assets

The public GitHub Release exposes exactly the expected four assets:

- `FloatTabs-0.5.6.dmg`
- `FloatTabs-0.5.6.dmg.sha256`
- `FloatTabs-0.5.6.dSYM.zip`
- `FloatTabs-0.5.6.dSYM.zip.sha256`

Verified release asset digests:

```text
DMG_SHA256=d3773236177489426371663782321b6473775285282fd7223575ad57c155097a
DSYM_ZIP_SHA256=9f217713b2e722bc5895fea9054f590cd27083a6f5a4c70fa3a22b16aa1c4ec2
```

The publisher also verified both checksum sidecars against the built artifacts with `shasum -a 256 -c`, and `hdiutil verify` reported the DMG checksum as valid.

## Release scope

v0.5.6 publishes the accepted diagnostics-efficiency work from PR #141:

- less repetitive long-run diagnostics volume;
- long-run page-app totals plus identity-safe deltas/rates instead of 255-saturating counters;
- transient bounded per-Slot delta baselines;
- Release-safe observer/detector/liveness workload evidence that instruments work already performed;
- bounded workload WebKit capture with a five-second maximum and one outstanding request budget;
- no new persistent observer, timer, polling cadence, automatic recovery, or product interaction behavior.

A representative equivalent periodic-log fixture measured 21,382 bytes before and 13,702 bytes after, a 35.918% reduction. The earlier 50% target was not reached and is not claimed.

## Data / recovery boundary

This release did not clear, migrate, or rewrite Browser Profiles, cookies, sessions, WebsiteData, Slots, preferences, backups, or existing diagnostic history. It did not add automatic reload/reset/rebuild behavior, private WebKit process attribution, or page-content capture.

The existing ChatGPT/WebKit slowdown and WebContent termination root cause remains **UNKNOWN**. This observation release is not a claim that the runtime incident is fixed.

## Operational next step

Install v0.5.6 / Build 24 on the Air and use FloatTabs normally for long-term observation. If the sidebar/share/image-viewer slowdown, WebContent termination, or another runtime degradation occurs, export Runtime Diagnostics before reload/restart when practical and note the approximate incident time.

A later causal-investigation task should be authorized from fresh v0.5.6 evidence rather than guessing a root cause from the release itself.
