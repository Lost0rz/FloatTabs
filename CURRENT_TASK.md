# FloatTabs Current Task

**Task ID:** `FT-RELEASE-0.5.4-001`
**Title:** Publish FloatTabs v0.5.4 Build 22 and close the release lifecycle
**Status:** `ACTIVE`
**Mode:** `RELEASE`

## Objective

Publish the already accepted current `main` product baseline as **FloatTabs v0.5.4 / Build 22** through the existing GitHub Release pipeline, then reconcile the release lifecycle to a clean terminal state.

This is a release task only. It does not authorize new product behavior.

## Authority / baseline

- Authorized source: `main@66de8f18c55d46cf882723c05f0afea8249d9e1b`.
- Latest completed product task: `FT-DIAG-HISTORY-REINTEGRATION-001`.
- Product PR #130: MERGED; Human Real-Mac acceptance PASS.
- Historical PR #124: CLOSED / SUPERSEDED / UNMERGED.
- Previous public release: `v0.5.3` / Build 21.

## Target release

- Marketing version: `0.5.4`.
- Build: `22`.
- Tag: `v0.5.4`.
- Distribution: Apple Silicon arm64.
- Release notes: `docs/release/FloatTabs_v0.5.4.md`.

## Authorized changes

- `CURRENT_STATUS.md` / `CURRENT_TASK.md` lifecycle state;
- `FloatTabs.xcodeproj/project.pbxproj` version/build metadata only;
- `docs/release/FloatTabs_v0.5.4.md`;
- temporary bounded release-preparation workflow is allowed only if it self-removes before the release PR final diff.

No production Swift/runtime/persistence behavior change is authorized.

## Verification gates

### Gate 0 — release identity
- release branch starts from `main@66de8f18...`;
- target is exactly `v0.5.4 / Build 22`;
- no unrelated open product PR needs inclusion first.

### Gate 1 — metadata / diff
- Debug and Release app configurations resolve to `MARKETING_VERSION = 0.5.4` and `CURRENT_PROJECT_VERSION = 22`;
- no unrelated `project.pbxproj` change;
- release notes exist at the canonical path;
- temporary preparation tooling leaves no final diff.

### Gate 2 — hosted verification
- exact release PR head macOS CI PASS;
- exact release PR head QA DMG PASS;
- final PR mergeable and no unresolved review blockers.

### Gate 3 — publication
- merge the accepted release PR;
- automatic `Publish Release` workflow completes successfully on merged `main`;
- GitHub Release `v0.5.4` is non-draft / non-prerelease;
- release target matches the merged release source;
- DMG, DMG SHA-256, dSYM ZIP and dSYM SHA-256 assets are present;
- checksums/package verification in the publisher workflow PASS.

### Gate 4 — lifecycle closeout
- update `CURRENT_STATUS.md` / `CURRENT_TASK.md` to terminal state on main through a control-only closeout;
- record release tag/version/build, merge source, publish workflow and public asset state;
- no active product/release task remains.

## Data safety / boundaries

Do not reset, delete, migrate or rewrite user configuration, Browser Profiles, Web App Slots, website login/session/cookies, WebKit stores, backups, recovery data or existing diagnostics data.

Do not change current attention, focus, navigation, window, runtime, diagnostics ownership or persistence semantics.

## STOP conditions

STOP rather than improvising if:
- release metadata cannot be changed without unrelated project-file drift;
- exact-head CI or QA DMG fails;
- main moves with overlapping release/product work before merge;
- publication attempts to overwrite an unexpected existing `v0.5.4` release;
- release asset identity or target commit is ambiguous.

## Completion

Task completes only when `v0.5.4 / Build 22` is publicly downloadable from GitHub, publisher verification passes, controls are reconciled to terminal state, and no active release task remains.
