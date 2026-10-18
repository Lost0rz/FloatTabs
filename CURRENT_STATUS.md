# FloatTabs Current Status

**Status date:** 2026-10-18
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: NO_ACTIVE_PRODUCT_TASK**

`FT-RELEASE-0.5.4-001` is completed. **FloatTabs v0.5.4 / Build 22** has been published through the canonical GitHub Release pipeline from the accepted diagnostics-enabled main baseline.

## Current release

- Release: `v0.5.4` / Build 22.
- Release PR #132: MERGED.
- Release PR final head: `b5e3c9951000f67d3ce31f43b41e5e425c7b4d3d`.
- Release merge commit / publication source: `439590659a42d52abd985c323dee4e1e0fbe9b47`.
- GitHub Release ID: `416270008`.
- Draft: NO.
- Prerelease: NO.
- Publish Release workflow run `39103088335`: PASS.
- Distribution: Apple Silicon arm64.

## Published assets

- `FloatTabs-0.5.4.dmg` — uploaded; GitHub SHA-256 digest `ec2c732275bcf85081fbaafd2a6d820eb7064d65cd9ed5aabe40e2d62a2abdde`.
- `FloatTabs-0.5.4.dmg.sha256` — uploaded.
- `FloatTabs-0.5.4.dSYM.zip` — uploaded; GitHub SHA-256 digest `e9f840292ba804551b41330e0a3ef5386f3253c21b5e823d9840a12541f31084`.
- `FloatTabs-0.5.4.dSYM.zip.sha256` — uploaded.

## Release verification

- Release source baseline before preparation: `main@66de8f18c55d46cf882723c05f0afea8249d9e1b`.
- Final release PR diff: only `CURRENT_STATUS.md`, `CURRENT_TASK.md`, `FloatTabs.xcodeproj/project.pbxproj`, and `docs/release/FloatTabs_v0.5.4.md`.
- App target Debug and Release configurations resolve to `0.5.4 (22)`.
- Exact release PR head macOS CI run `39102628192`: PASS.
- Exact release PR head QA DMG run `39102628179`: PASS.
- Final PR mergeability/review-thread audit: PASS.
- Publish Release package build and Apple Silicon verification: PASS.
- Release filename/checksum verification: PASS.
- New GitHub Release publication: PASS.
- Release target commit is `439590659a42d52abd985c323dee4e1e0fbe9b47`.
- The temporary release-preparation workflow self-removed before the release PR final diff. Its first guard run failed safely because the project contained two, not four, version/build occurrences; the guard was corrected before metadata mutation, and the successful preparation commit produced the bounded final release diff.

## v0.5.4 product baseline

This release contains the accepted current main product baseline, including:

- long-term local Runtime Diagnostics history;
- Standard / Verbose diagnostic detail level;
- opt-in low-cadence selected-Slot performance observation;
- saved-log folder access and bounded local JSONL retention/rotation;
- diagnostics-only runtime/WebView/navigation identity evidence and manual reload boundary;
- Dot / Beacon / Halo / Orbit / Pulse / Sweep unread attention styles and separate palettes;
- accepted Settings IA, Browser Profile/session ownership, shell/focus/navigation/window/runtime behavior and speech/runtime-residency fixes inherited from v0.5.3.

## Data safety

- No Browser Profile data was reset or migrated.
- No Web App Slot configuration was reset or migrated.
- No website login/session/cookie/WebKit store was cleared or migrated.
- No backup, recovery data or existing diagnostic history was destructively modified by the release task.
- No runtime/focus/navigation/recovery/attention ownership change was introduced by the release task.

## Current posture

```text
ACTIVE_PRODUCT_TASK=NONE
LAST_COMPLETED_TASK=FT-RELEASE-0.5.4-001
TASK_STATE=COMPLETED
LATEST_RELEASE=v0.5.4
LATEST_RELEASE_BUILD=22
RELEASE_PR=132_MERGED
RELEASE_PR_FINAL_HEAD=b5e3c9951000f67d3ce31f43b41e5e425c7b4d3d
RELEASE_MERGE_COMMIT=439590659a42d52abd985c323dee4e1e0fbe9b47
RELEASE_WORKFLOW=39103088335_PASS
RELEASE_ID=416270008
RELEASE_ASSETS=DMG,DMG_SHA256,DSYM_ZIP,DSYM_SHA256
PR_130=MERGED
PR_124=CLOSED_SUPERSEDED_UNMERGED
HUMAN_UI_ACCEPTANCE=PASS
MAIN_AHEAD_OF_LATEST_RELEASE=NO
ROOT_CAUSE=N/A
```

## Next

The v0.5.4 release lifecycle is complete. No active product or release task is authorized. Enter lifecycle management/read-only cleanup audit before deleting branches, worktrees, rollback bundles or other historical evidence; create/reconcile a new `CURRENT_TASK.md` before any state-changing cleanup.
