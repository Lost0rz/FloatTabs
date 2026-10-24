# FloatTabs Current Task

**Task ID:** `FT-RELEASE-V0.5.7-001`
**Title:** Publish FloatTabs v0.5.7 Build 25
**Status:** `TERMINAL — PUBLISHED / PROVENANCE VERIFIED / CONTROL CLOSED`
**Mode:** `TERMINAL`
**Task class:** `RELEASE`

> This task is complete and grants no further product, release, branch, data, or recovery authority.

## Terminal result

FloatTabs **v0.5.7 / Build 25** was published through the repository's canonical release workflow and is available from GitHub Releases.

```text
BASE_MAIN=098182e64890dabb68832c3bd4d868ff499ac95d
RELEASE_PR=148
RELEASE_PR_HEAD=1aef2c57bd4d4878704d8c0a06bd7f95c4368e66
RELEASE_MAIN=9d92beb2433a84ca62dd6effacce22bc512dd6d4
TAG=v0.5.7
PUBLIC_RELEASE=v0.5.7
PUBLIC_BUILD=25
ARCH=arm64
RELEASE_ID=422780134
PUBLISH_RELEASE_RUN=37
PUBLISH_RELEASE_RUN_ID=40102547155
RELEASE_AUTHORIZED=NO
```

## Release gate evidence

### Metadata / scope

- app Debug and Release build settings resolve to version 0.5.7 / Build 25;
- release notes are `docs/release/FloatTabs_v0.5.7.md`;
- release PR #148 changed only the Xcode version/build metadata, release notes, and release control state;
- the final Xcode project diff contained only the four intended version/build lines;
- no product/runtime/UI/persistence/session code or release-workflow logic changed for publication.

### Pre-merge host gates

```text
RELEASE_PR_EXACT_HEAD=1aef2c57bd4d4878704d8c0a06bd7f95c4368e66
MACOS_CI_RUN_1119=PASS
QA_DMG_RUN_522=PASS
PR_MERGEABLE=YES
REVIEW_THREADS=0
SUBMITTED_REVIEWS=0
PR_MERGE_AUDIT=PASS
```

PR #148 was then merged to protected `main` at `9d92beb2433a84ca62dd6effacce22bc512dd6d4`.

### Publisher / provenance

Canonical `Publish Release` run #37 (`40102547155`) ran on exact release-main identity `9d92beb2433a84ca62dd6effacce22bc512dd6d4` and completed successfully.

The workflow successfully completed:

- release metadata resolution;
- new-release state verification;
- Apple Silicon release package build/verification;
- release filename/checksum verification;
- creation of the new GitHub Release.

The lightweight tag `v0.5.7` resolves directly to `9d92beb2433a84ca62dd6effacce22bc512dd6d4`.

GitHub Release state:

```text
DRAFT=NO
PRERELEASE=NO
RELEASE_NAME=FloatTabs v0.5.7
RELEASE_TARGET=9d92beb2433a84ca62dd6effacce22bc512dd6d4
```

### Public assets

```text
FloatTabs-0.5.7.dmg
FloatTabs-0.5.7.dmg.sha256
FloatTabs-0.5.7.dSYM.zip
FloatTabs-0.5.7.dSYM.zip.sha256
```

GitHub-recorded artifact digest for the downloadable DMG:

```text
SHA256=12562e874ca0ea4b975d9c0eba234bee44eb21abf3a8e217a10366376dc95d70
```

The dSYM ZIP digest is:

```text
SHA256=b6354c8de9ad8dde7468572c986eed3d053eb8f77c9944be5179b2939435943c
```

### Post-merge verification

```text
POST_MERGE_MACOS_CI_RUN=1120
POST_MERGE_MACOS_CI=PASS
RELEASE_PROVENANCE=VERIFIED
RELEASE_ASSETS=VERIFIED
```

## Release contents / safety

v0.5.7 publishes the already accepted product changes since v0.5.6, including the bounded Web runtime / Attention corrective and Active Tab / unread Attention visual refinement.

The prior WebContent stall/termination root cause remains `UNKNOWN`; this release does not claim otherwise.

No Browser Profile, website login/session/cookie data, Web App Slot configuration, user preference, backup, or persisted website-data reset/clearing is part of the release lifecycle.

## Lifecycle

- Release PR #148: `MERGED`.
- Public release v0.5.7: `PUBLISHED / VERIFIED`.
- This release task is closed.
- No further release is authorized.
- Any future product work or release requires a new task authorization.
