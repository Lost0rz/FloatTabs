# FloatTabs Current Status

**Status date:** 2026-10-18
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: RELEASE_0_5_4_ACTIVE**

`FT-RELEASE-0.5.4-001` is active. The objective is to publish the accepted current `main` baseline as **FloatTabs v0.5.4 / Build 22** through the repository's existing GitHub Release pipeline, then close the release lifecycle.

## Authorized release baseline

- Release source baseline: `main@66de8f18c55d46cf882723c05f0afea8249d9e1b`.
- The baseline includes the accepted long-term local diagnostics/history reintegration from PR #130.
- Human Real-Mac acceptance for that product baseline: PASS on 2026-10-18.
- Historical PR #124 is CLOSED / SUPERSEDED / UNMERGED.
- There are no open product PRs at release start.
- Previous public release: `v0.5.3` / Build 21.

## Release target

- Version: `0.5.4`.
- Build: `22`.
- Tag: `v0.5.4`.
- Distribution: Apple Silicon arm64.
- Release scope is metadata, release notes, packaging/publication, and control-plane lifecycle only; no new product/runtime/persistence semantics are authorized.

## Required release gates

1. Bump app Debug/Release version metadata to `0.5.4 (22)` without unrelated project-file changes.
2. Add `docs/release/FloatTabs_v0.5.4.md` describing the accepted long-term diagnostics-history delta and inherited accepted baseline.
3. Release PR changes only control files, release metadata and release notes after temporary preparation tooling self-removes.
4. Exact release PR head macOS CI: PASS.
5. Exact release PR head QA DMG: PASS.
6. Merge release PR only after final merge-readiness audit.
7. `Publish Release` on merged `main`: PASS.
8. GitHub Release `v0.5.4` exists as non-draft / non-prerelease with DMG, DMG SHA-256, dSYM ZIP, and dSYM SHA-256 assets.
9. Reconcile `CURRENT_STATUS.md` / `CURRENT_TASK.md` to terminal release lifecycle state after publication.

## Data safety

- Do not reset, migrate, delete or rewrite Browser Profiles, Web App Slots, website session/cookie/WebKit data, backups, recovery data, or existing diagnostic history.
- Do not change runtime/focus/navigation/recovery/attention ownership under this release task.

## Current posture

```text
ACTIVE_PRODUCT_TASK=FT-RELEASE-0.5.4-001
TASK_STATE=ACTIVE
RELEASE_BASE_MAIN=66de8f18c55d46cf882723c05f0afea8249d9e1b
TARGET_VERSION=0.5.4
TARGET_BUILD=22
TARGET_TAG=v0.5.4
LATEST_RELEASE=v0.5.3_BUILD_21
ROOT_CAUSE=N/A
```

## Next

Prepare the release metadata and notes on `release/ft-0.5.4`, open the release PR, complete exact-head verification, merge, wait for the automatic Publish Release workflow, verify the published assets, then perform post-release lifecycle closeout.
