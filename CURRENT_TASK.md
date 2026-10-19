# FloatTabs Current Task

**Task ID:** `FT-RELEASE-V0.5.5-001`
**Title:** Publish FloatTabs v0.5.5 diagnostic observation release
**Status:** `ACTIVE — RELEASE PREP`
**Mode:** `RELEASE`
**Task class:** `RELEASE`
**Base:** `main@1d6f80a9e59a2fcbee1c846be562b14c6b6e2fea`
**Branch:** `release/ft-v0.5.5`
**Target version:** `0.5.5`
**Target build:** `23`

## Objective

Publish the already-merged bounded diagnostic infrastructure as FloatTabs v0.5.5 / Build 23 for long-term normal-use observation on the Air. Root cause remains `UNKNOWN`; this release must not claim the stall is fixed.

## Verified basis

- PR #138 merged to protected `main` at `1d6f80a9e59a2fcbee1c846be562b14c6b6e2fea`.
- Post-merge main macOS CI run `39227623989` passed, including Debug build, Release build, native arm64 verification, and unit tests.
- Latest published release before this task is v0.5.4 / Build 22.
- Tag/release `v0.5.5` does not exist at task start.
- Repository `Publish Release` workflow is the canonical publisher and reads version/build metadata from `FloatTabs.xcodeproj/project.pbxproj` plus matching `docs/release/FloatTabs_v<version>.md`.

## Authorized scope

1. Bump only the app release metadata from v0.5.4 / Build 22 to v0.5.5 / Build 23 in the app target Debug/Release configurations.
2. Add `docs/release/FloatTabs_v0.5.5.md` describing the diagnostic-observation release and its limitations.
3. Keep product semantics unchanged from merged main; no additional runtime/recovery behavior is authorized.
4. Open a release PR to protected `main` and require exact-head CI + QA DMG PASS before merge.
5. After merge, verify post-merge CI and the `Publish Release` workflow.
6. Verify the public `v0.5.5` release, tag target, DMG, checksum, dSYM, and dSYM checksum assets before declaring publication complete.
7. Browser Profiles, cookies, sessions, WebsiteData, Slots, preferences, backups, and existing diagnostics history must not be touched.

## Release gate

The release PR may merge only when:

- diff is limited to release controls, version/build metadata, and the v0.5.5 release note;
- app metadata is exactly `0.5.5` / `23` for Debug and Release;
- exact-head `Build & Test (Apple Silicon arm64)` passes;
- exact-head QA DMG passes;
- PR remains clean/mergeable;
- release note explicitly preserves `ROOT_CAUSE=UNKNOWN` and no-fix claim.

Publication completes only after the repository publisher succeeds and the public release assets are verified.

## Explicitly unauthorized

- Product feature or runtime semantic changes.
- Root-cause claims or claims that the stall is fixed.
- Automatic reload/reset/rebuild/recovery changes.
- Residency-policy changes.
- User-data or Browser Profile/session mutations.

## Expected terminal state

`v0.5.5 / Build 23` is publicly downloadable for Air long-term observation, with diagnostic export/log access preserved. A later fresh Air incident remains causal evidence for the continuing investigation.
