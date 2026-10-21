# FloatTabs Current Task

**Task ID:** `FT-RELEASE-V0.5.6-001`
**Title:** Publish FloatTabs v0.5.6 diagnostics-efficiency observation release
**Status:** `ACTIVE — RELEASE PREPARATION`
**Mode:** `RELEASE`
**Task class:** `RELEASE`

## Authority

This release task is authorized by the user after PR #141 passed final merge audit and merged to protected `main`.

```text
BASE_MAIN=940fd8e80792eb32c5571bc6b159ffb7db13017f
SOURCE_PR=141
SOURCE_SEMANTIC_HEAD=e6f0fd8c671c720721fdc4b8ca71d2e993db3a89
PREVIOUS_PUBLIC_RELEASE=v0.5.5
TARGET_RELEASE=v0.5.6
TARGET_BUILD=24
ARCH=arm64
ROOT_CAUSE=UNKNOWN
```

## Objective

Publish the accepted diagnostics-efficiency implementation as FloatTabs v0.5.6 / Build 24 so the Air can return to long-term normal-use observation with lower-volume, higher-value runtime diagnostics.

This is an observation release. It does **not** claim that the ChatGPT control slowdown or WebContent termination root cause has been fixed.

## Authorized release changes

- Bump `MARKETING_VERSION` from `0.5.5` to `0.5.6` for all app build configurations.
- Bump `CURRENT_PROJECT_VERSION` from `23` to `24` for all app build configurations.
- Add `docs/release/FloatTabs_v0.5.6.md` describing the accepted diagnostics changes, validation evidence, privacy/data-safety boundary, and observation intent.
- Update `CURRENT_STATUS.md` / `CURRENT_TASK.md` with verified release lifecycle facts.
- Use branch `release/ft-v0.5.6` and one release PR against protected `main`.

## Required gates

1. Source implementation PR #141 is merged and accepted.
2. Post-merge source `main` macOS CI must complete successfully before release PR merge.
3. Release PR literal head must pass macOS CI and QA DMG.
4. Release metadata must resolve exactly to `0.5.6` / Build `24` / arm64.
5. Release PR must contain release/control metadata only; no new product/runtime behavior.
6. After release PR merge, post-merge `main` CI must pass.
7. `Publish Release` must complete successfully and create public GitHub Release `v0.5.6` with DMG, DMG SHA-256, dSYM archive, and dSYM SHA-256 assets.
8. Tag/release target must match the release merge commit.

## Safety / non-goals

- Do not change Web runtime, recovery, residency, focus/input, window, persistence, or Browser Profile behavior in this task.
- Do not clear or rewrite Browser Profiles, cookies, sessions, WebsiteData, Slots, preferences, backups, or diagnostic history.
- Do not use reload/reset/restart as a root-cause claim.
- Do not claim the existing runtime incident is fixed.
- Preserve `ROOT_CAUSE=UNKNOWN`.

## STOP conditions

STOP before merge/publication if:

- post-merge source `main` CI fails;
- release PR exact-head macOS CI or QA DMG fails;
- release metadata is not exactly v0.5.6 / Build 24 / arm64;
- the release PR acquires production/runtime changes beyond the already accepted source merge;
- publisher verification or release asset integrity fails;
- tag or release target does not resolve to the intended release commit.

## Delivery

```text
BRANCH=release/ft-v0.5.6
PR=TO_BE_CREATED
TARGET_VERSION=0.5.6
TARGET_BUILD=24
ROOT_CAUSE=UNKNOWN
NEXT=RELEASE_METADATA_AND_NOTES
```
