# FloatTabs Current Status

**Status date:** 2026-10-18
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: NO_ACTIVE_PRODUCT_TASK**

`FT-RELEASE-0.5.3-001` is completed. **FloatTabs v0.5.3 (Build 21)** is published on GitHub with downloadable release assets. No active product or release task is authorized.

## Current release

- Latest public release: `v0.5.3` / Build 21.
- Release PR #127: MERGED.
- Release PR final head: `25c3508832e8fa384cc3282f569222c06fc67b16`.
- Release merge commit / publication source: `7d275762de0e2abba9fd1efcb0efb1dc87e00a99`.
- GitHub Release ID: `416230888`.
- Release title: `FloatTabs v0.5.3`.
- Draft: NO.
- Prerelease: NO.
- Publish Release workflow run `39097105718`: PASS.
- Distribution remains Apple Silicon arm64.

## Published assets

- `FloatTabs-0.5.3.dmg` — uploaded; GitHub SHA-256 digest `036015d1fbcafd3e0017807c255a7b968a9f62648f51fdb636b93e5ee4755a2b`.
- `FloatTabs-0.5.3.dmg.sha256` — uploaded.
- `FloatTabs-0.5.3.dSYM.zip` — uploaded; GitHub SHA-256 digest `565cd72fa5d4195eb1818bf26bbd9995e464af88cd264989f036b5dc8b88fa1e`.
- `FloatTabs-0.5.3.dSYM.zip.sha256` — uploaded.

## Release verification

- Release PR changed only control files, app version/build metadata, and v0.5.3 release notes.
- App target Debug and Release configurations resolve to `0.5.3 (21)`.
- Exact release PR head macOS CI: PASS.
- Exact release PR head QA DMG: PASS.
- Final PR mergeability/review-thread audit: PASS.
- Release package build and Apple Silicon verification: PASS.
- Release filename and checksum verification: PASS.
- New GitHub Release publication: PASS.
- Tag/release target is `7d275762de0e2abba9fd1efcb0efb1dc87e00a99`.
- Diagnostics/history PR #124 remains separate and is not part of v0.5.3.

## v0.5.3 product baseline

This release includes already-accepted work since v0.5.2, including:

- Dot / Beacon / Halo / Orbit / Pulse / Sweep unread attention styles and separate palettes;
- Browser Profile color removed from Tab presentation while compatibility metadata is preserved;
- General: Interface Appearance + Unread Tab Attention; Audio: Ready Alerts + Speech;
- responsive 3×2 Attention Style chooser and Reduce Motion-safe effects;
- shell movement refinement to the bounded inner Web-surface movement affordance;
- latest-assistant-response speech ownership correction;
- Hot background recovery and Warm retention/memory-pressure reliability corrections;
- privacy-bounded runtime/navigation/page-app diagnostic evidence improvements;
- DEBUG/benchmark long-running ChatGPT measurement support.

The long-term diagnostics-history work in PR #124 remains unmerged/parked and is not part of this release.

## Data safety

- Browser Profile data was not reset or migrated.
- Web App Slot configuration was not reset or migrated.
- Website login/session/cookie/WebKit stores were not cleared.
- Backups/recovery data were not destructively modified.
- Existing rollback bundles are outside this remote release closeout and are not authorized for deletion here.

## Current posture

```text
ACTIVE_PRODUCT_TASK=NONE
LAST_COMPLETED_TASK=FT-RELEASE-0.5.3-001
TASK_STATE=COMPLETED
LATEST_RELEASE=v0.5.3
LATEST_RELEASE_BUILD=21
RELEASE_PR=127_MERGED
RELEASE_PR_FINAL_HEAD=25c3508832e8fa384cc3282f569222c06fc67b16
RELEASE_MERGE_COMMIT=7d275762de0e2abba9fd1efcb0efb1dc87e00a99
RELEASE_WORKFLOW=39097105718_PASS
RELEASE_ASSETS=DMG,DMG_SHA256,DSYM_ZIP,DSYM_SHA256
DIAGNOSTICS_PR_124=PARKED_UNCHANGED
ROOT_CAUSE=N/A
```

## Next

The release lifecycle is complete. Start or reconcile a new `CURRENT_TASK.md` before any new product, release, cleanup, or diagnostics mutation.