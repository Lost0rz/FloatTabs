# FloatTabs Current Status

**Status date:** 2026-10-24
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: NO ACTIVE ENGINEERING TASK — v0.5.7 POST-RELEASE OBSERVATION**

Most recently completed task: `FT-RELEASE-V0.5.7-001`

## Current verified baseline

```text
RELEASE_MAIN=9d92beb2433a84ca62dd6effacce22bc512dd6d4
RELEASE_PR=148
RELEASE_PR_HEAD=1aef2c57bd4d4878704d8c0a06bd7f95c4368e66
PUBLIC_RELEASE=v0.5.7
PUBLIC_BUILD=25
TAG=v0.5.7
ARCH=arm64
RELEASE_ID=422780134
PUBLISH_RELEASE_RUN=37
PUBLISH_RELEASE_RUN_ID=40102547155
POST_MERGE_MACOS_CI_RUN=1120
```

FloatTabs v0.5.7 / Build 25 is publicly published and downloadable from GitHub Releases.

The tag `v0.5.7` resolves directly to release merge commit `9d92beb2433a84ca62dd6effacce22bc512dd6d4`. The release is neither draft nor prerelease.

## Published assets

The canonical `Publish Release` workflow built and verified the Apple Silicon package and published all expected assets:

```text
FloatTabs-0.5.7.dmg
FloatTabs-0.5.7.dmg.sha256
FloatTabs-0.5.7.dSYM.zip
FloatTabs-0.5.7.dSYM.zip.sha256
```

GitHub-recorded artifact digests include:

```text
DMG_SHA256=12562e874ca0ea4b975d9c0eba234bee44eb21abf3a8e217a10366376dc95d70
DSYM_ZIP_SHA256=b6354c8de9ad8dde7468572c986eed3d053eb8f77c9944be5179b2939435943c
DMG_SIDECAR_ASSET_SHA256=0990a5d20c3e4efdad8ef5bf7c84609059c445583c50049d5656bc25663a759f
DSYM_SIDECAR_ASSET_SHA256=8977acd349f9384134a4e896b4f5c50c222f9b55313cbf95073acbb910faef5d
```

The release workflow's package-build, filename/checksum verification, and new-release publication steps all passed.

## Release verification

```text
RELEASE_PR_EXACT_HEAD_MACOS_CI_1119=PASS
RELEASE_PR_EXACT_HEAD_QA_DMG_522=PASS
RELEASE_PR_MERGE_AUDIT=PASS
PUBLISH_RELEASE_37=PASS
POST_MERGE_MACOS_CI_1120=PASS
TAG_PROVENANCE=VERIFIED
RELEASE_ASSETS=VERIFIED
DRAFT=NO
PRERELEASE=NO
```

Release notes are retained at `docs/release/FloatTabs_v0.5.7.md`.

## Accepted product state

v0.5.7 includes the accepted Web runtime / Attention corrective work completed after v0.5.6 and the Active Tab / unread Attention visual refinement:

- active Tab remains expanded at 76 pt with its label visible;
- inactive Tabs retain 40 -> 76 pt Dock/hover behavior;
- canonical unread Attention styles are Dot / Beacon / Orbit / Pulse;
- stored `halo` / `sweep` values remain safely compatible through Pulse / Orbit mappings;
- Orbit and Pulse visibility are strengthened;
- Settings uses the four-style 2x2 presentation.

The prior WebContent stall/termination root cause remains `UNKNOWN`. v0.5.7 improves FloatTabs-owned recovery correctness and diagnostics but does not claim that external root cause is proven or eliminated.

## Data safety

The release does not intentionally clear or reset Browser Profiles, website session/cookie data, Web App Slot configuration, preferences, backups, or persisted website data.

## Repository lifecycle

- PR #148: `MERGED` at `9d92beb2433a84ca62dd6effacce22bc512dd6d4`.
- GitHub Release v0.5.7: `PUBLISHED / VERIFIED`.
- Release task: `TERMINAL` after this control-only closeout.
- No further product or release authority is granted by this status.

## Next

Continue normal use/observation of v0.5.7. Any new product change or future release requires a new `CURRENT_TASK.md` authorization.
