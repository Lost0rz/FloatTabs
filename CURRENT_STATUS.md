# FloatTabs Current Status

**Status date:** 2026-10-24
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: ACTIVE RELEASE — v0.5.7 / Build 25**

Active task: `FT-RELEASE-V0.5.7-001`

## Current verified baseline

```text
BASE_MAIN=098182e64890dabb68832c3bd4d868ff499ac95d
CURRENT_PUBLIC_RELEASE=v0.5.6
CURRENT_PUBLIC_BUILD=24
TARGET_RELEASE=v0.5.7
TARGET_BUILD=25
ARCH=arm64
RELEASE_BRANCH=release/ft-v0.5.7
OPEN_PRS_AT_START=0
V0_5_7_EXISTS_AT_START=NO
```

The latest accepted product baseline includes the merged Active Tab / unread Attention refinement and prior bounded Web runtime / Attention corrective work.

The previous WebContent stall/termination root cause remains `UNKNOWN`. Publishing v0.5.7 does not change or close that incident conclusion.

## Release target

Publish a new GitHub Release rather than refreshing v0.5.6:

```text
VERSION=0.5.7
BUILD=25
TAG=v0.5.7
DRAFT=NO
PRERELEASE=NO
EXPECTED_DMG=FloatTabs-0.5.7.dmg
EXPECTED_DMG_SHA256=FloatTabs-0.5.7.dmg.sha256
EXPECTED_DSYM=FloatTabs-0.5.7.dSYM.zip
EXPECTED_DSYM_SHA256=FloatTabs-0.5.7.dSYM.zip.sha256
```

The repository's existing `Publish Release` workflow is the canonical publisher. It derives version/build from the Xcode project, requires matching release notes, builds the arm64 DMG/dSYM package, verifies checksum sidecars, and creates the GitHub Release.

## Scope boundary

This release task may change only release metadata, release notes, and control state. No product/runtime/UI/persistence/session behavior change is authorized.

## Evidence already carried into release preparation

- PR #146 product merge and its exact-head macOS CI / QA DMG passed before merge.
- The subsequent control closeout PR #147 passed its required macOS CI and merged.
- Current `main` is protected and has no open PR at release-task start.
- Latest public release is v0.5.6 / Build 24.

## Next

Prepare v0.5.7 / Build 25 metadata and release notes on `release/ft-v0.5.7`, open one bounded release PR, pass current host gates, merge to `main`, verify the canonical publisher and public assets, then close the release task through a control-only closeout.
