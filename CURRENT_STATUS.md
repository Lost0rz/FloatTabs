# FloatTabs Current Status

**Status date:** 2026-10-18
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: RELEASE_0.5.3_ACTIVE**

`FT-RELEASE-0.5.3-001` is active. The accepted product baseline has already merged and passed Human/runtime acceptance; this task is release-only and targets **FloatTabs v0.5.3 (Build 21)**.

## Release baseline

- Current release-task base: `main@869bfaeb7eb6b00d9f2460fd638cb922f3200981`.
- Previous public release: `v0.5.2` / Build 20.
- Release branch: `release/v0.5.3`.
- Current project metadata before release prep: `0.5.2 (20)`.
- Target metadata: `0.5.3 (21)`.
- Existing publisher: `.github/workflows/publish-release.yml`.
- Existing package builder: `tools/release/build_dmg.sh`.
- Distribution remains Apple Silicon arm64.
- Diagnostics/history PR #124 remains parked, separate and untouched.

## Accepted product baseline included in v0.5.3

The release packages already-merged, accepted work since v0.5.2. User-facing/reliability highlights include:

- selectable unread/Ready Tab attention styles: Dot, Beacon, Halo, Orbit, Pulse and Sweep;
- independent Red / Amber / Blue / Violet / Mint / Spectrum attention palettes, with classic red Dot retained;
- Browser Profile color removed from Tab presentation while compatibility metadata remains preserved;
- General owns Interface Appearance + Unread Tab Attention; Audio owns Ready Alerts + Speech;
- responsive 3×2 Attention Style chooser and Reduce Motion-safe decorative animation;
- outer shell/complete Tab rail no longer acquire window movement; the bounded inner Web-surface movement affordance remains;
- Read Latest Response uses positively assistant-owned latest-response content rather than a mixed user/assistant ancestor;
- corrected Hot background recovery and Warm retention/memory-pressure semantics;
- expanded privacy-bounded runtime/navigation/page-app diagnostic evidence;
- DEBUG/benchmark measurement support for long-running ChatGPT performance.

The unmerged long-term diagnostics-history work in PR #124 is not part of this release.

## Release gates

- release/control-only diff;
- exact app metadata `0.5.3 (21)`;
- exact-head macOS CI PASS;
- exact-head QA DMG PASS;
- final mergeability/review-thread audit PASS;
- `Publish Release` PASS after merge;
- `v0.5.3` tag and GitHub Release verified;
- DMG/checksum/dSYM/checksum assets verified downloadable;
- post-release STATUS/TASK lifecycle closeout merged.

## Data safety

No release step is authorized to clear/reset/migrate Browser Profiles, Web App Slots, website sessions/cookies/WebKit data, backups, recovery data, or user configuration.

## Current posture

```text
ACTIVE_PRODUCT_TASK=FT-RELEASE-0.5.3-001
TASK_STATE=ACTIVE
TASK_MODE=RELEASE
RELEASE_BRANCH=release/v0.5.3
RELEASE_BASE_MAIN=869bfaeb7eb6b00d9f2460fd638cb922f3200981
PREVIOUS_RELEASE=v0.5.2_BUILD_20
TARGET_RELEASE=v0.5.3_BUILD_21
PRODUCT_SOURCE_CHANGE_AUTHORIZED=NO
DIAGNOSTICS_PR_124=PARKED_UNCHANGED
ROOT_CAUSE=N/A
```

## Next

Prepare the bounded release metadata and notes, pass exact-head hosted release gates, merge the release PR, verify GitHub publication/assets, then perform control-only lifecycle closeout.