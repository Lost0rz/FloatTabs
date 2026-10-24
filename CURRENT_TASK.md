# FloatTabs Current Task

**Task ID:** `FT-RELEASE-V0.5.7-001`
**Title:** Publish FloatTabs v0.5.7 Build 25
**Status:** `ACTIVE / RELEASE PREPARATION AUTHORIZED`
**Mode:** `EXECUTE`
**Task class:** `RELEASE`

## Authority

The user explicitly authorized publishing a downloadable release from the current accepted `main` baseline.

This task is the only active release authorization. It does not reopen prior product tasks or authorize unrelated product/runtime changes.

## Baseline

```text
BASE_MAIN=098182e64890dabb68832c3bd4d868ff499ac95d
CURRENT_PUBLIC_RELEASE=v0.5.6
CURRENT_PUBLIC_BUILD=24
TARGET_RELEASE=v0.5.7
TARGET_BUILD=25
ARCH=arm64
RELEASE_BRANCH=release/ft-v0.5.7
RELEASE_AUTHORIZED=YES
```

The latest public GitHub Release is v0.5.6 / Build 24. No v0.5.7 release exists at task start. The current `main` contains the accepted runtime/Attention corrective work and the merged Active Tab / unread Attention visual refinement.

The prior WebContent stall/termination root cause remains `UNKNOWN`; this release does not claim otherwise.

## Objective

Publish FloatTabs **v0.5.7 / Build 25** through the repository's canonical `Publish Release` workflow so the user can download the DMG from GitHub Releases.

## Authorized changes

Only the release lifecycle is authorized:

- update `FloatTabs.xcodeproj/project.pbxproj` from v0.5.6 / Build 24 to v0.5.7 / Build 25 for both app build configurations;
- add `docs/release/FloatTabs_v0.5.7.md`;
- update `CURRENT_STATUS.md` / `CURRENT_TASK.md` for release lifecycle state;
- create and merge the bounded release PR after required host gates pass;
- allow the existing `.github/workflows/publish-release.yml` to create tag/release/assets;
- verify tag/source provenance, DMG, checksum sidecars, dSYM assets and published release metadata;
- perform a control-only closeout after publication evidence is complete.

## Non-goals / protected boundaries

Do not change product runtime/source behavior, WebKit ownership, Attention semantics, UI behavior, persistence, Browser Profiles, website/session data, diagnostics behavior, release workflow logic, signing policy, or architecture support merely to publish this version.

Do not overwrite or force-refresh v0.5.6. v0.5.7 must be a new release.

## Release contents

Release notes must accurately summarize material user-visible and runtime changes since v0.5.6 without overstating unresolved root cause:

- stronger Web runtime/recovery and Attention-runtime correctness/diagnostic boundaries merged after v0.5.6;
- Active Tab remains expanded with its label visible;
- unread Attention styles are Dot / Beacon / Orbit / Pulse with safe legacy compatibility;
- Orbit/Pulse visual clarity improvements and 2x2 Settings presentation;
- no Browser Profile/session reset or destructive migration;
- WebContent stall/termination root cause remains `UNKNOWN`.

## Gates

### Gate 0 — Baseline

- fresh `main` identity equals task baseline or only reconciled control-only drift is present;
- no overlapping open PR/writer exists;
- latest public release is v0.5.6 / Build 24;
- v0.5.7 does not already exist.

### Gate 1 — Release metadata

- version/build are exactly 0.5.7 / 25 in both app Debug and Release build settings;
- `docs/release/FloatTabs_v0.5.7.md` exists and matches repository release contract;
- no unrelated production files change.

### Gate 2 — Pre-merge verification

- release PR exact head is mergeable;
- required macOS CI passes on the literal release PR head;
- any QA/package validation triggered for the release PR must pass;
- release diff remains bounded to version/release/control files.

### Gate 3 — Merge / publisher

- merge the release PR to protected `main` only after Gate 2 passes;
- observe `Publish Release` for the resulting `main` identity;
- publisher must build and verify Apple Silicon release package and checksums successfully.

### Gate 4 — Release provenance

Verify:

```text
TAG=v0.5.7
VERSION=0.5.7
BUILD=25
DRAFT=NO
PRERELEASE=NO
ASSETS=FloatTabs-0.5.7.dmg,FloatTabs-0.5.7.dmg.sha256,FloatTabs-0.5.7.dSYM.zip,FloatTabs-0.5.7.dSYM.zip.sha256
```

The release/tag must resolve to the release-main identity produced by this task.

### Gate 5 — Closeout

After publication is verified, update controls to terminal/public-release state through a control-only protected-branch-safe closeout. No further release/product authority remains.

## STOP conditions

Stop rather than publish if:

- current `main` has materially changed outside reconciled authority;
- v0.5.7 already exists with conflicting provenance;
- version/build or notes do not match target;
- required CI/package/publisher validation fails;
- release assets or tag provenance cannot be verified;
- publication would require destructive data handling or unrelated product changes.

## Required final state

```text
TASK_STATE=TERMINAL
PUBLIC_RELEASE=v0.5.7
PUBLIC_BUILD=25
RELEASE_PROVENANCE=VERIFIED
RELEASE_ASSETS=VERIFIED
OPEN_TASK_RELEASE_PRS=0
```
