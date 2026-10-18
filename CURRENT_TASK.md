# FloatTabs Current Task

**Task ID:** `FT-RELEASE-0.5.3-001`
**Title:** Publish FloatTabs v0.5.3 Build 21 and close the release lifecycle
**Status:** `ACTIVE`
**Mode:** `RELEASE`

## Objective

Publish the current accepted `main` product baseline as **FloatTabs v0.5.3 (Build 21)** with downloadable GitHub Release assets, then reconcile the release lifecycle back to a clean no-active-task state.

## Authority / baseline

- Project rules: `AGENTS.md`.
- Current release baseline: `main@869bfaeb7eb6b00d9f2460fd638cb922f3200981`.
- Previous public release: `v0.5.2` / Build 20.
- Release branch: `release/v0.5.3`.
- Release publisher: `.github/workflows/publish-release.yml`.
- Release packaging: `tools/release/build_dmg.sh`.
- Diagnostics/history PR #124 remains separate and out of scope.

## Authorized release delta

Release preparation may change only release/control material:

- `FloatTabs.xcodeproj/project.pbxproj`: `MARKETING_VERSION 0.5.2 → 0.5.3`, `CURRENT_PROJECT_VERSION 20 → 21` for the app target Debug and Release configurations;
- `docs/release/FloatTabs_v0.5.3.md`;
- `CURRENT_STATUS.md` / `CURRENT_TASK.md` for release authorization and closeout;
- a temporary release-preparation workflow is permitted only if required to apply the bounded project-file metadata edit safely through GitHub, must be branch-scoped, self-delete before the release PR is merged, and must leave no workflow delta in the final release PR.

No production Swift/runtime behavior change is authorized.

## Release content

The release summarizes accepted changes already merged since v0.5.2, including:

- selectable unread/Ready Tab attention styles and palettes, with Browser Profile color removed from Tab presentation;
- shell movement refinement that keeps window movement on the bounded inner Web-surface affordance rather than the external shell/Tab rail;
- ChatGPT latest-response speech ownership correction so Read Latest targets the latest assistant-owned response;
- Hot/Warm residency lifecycle reliability corrections;
- privacy-bounded runtime/navigation/page-app diagnostic evidence improvements;
- DEBUG/benchmark measurement support for long-running ChatGPT performance.

Do not claim the unmerged long-term diagnostics-history feature from PR #124.

## Verification gates

1. Final release PR diff is release/control-only and contains no product/runtime source changes.
2. Version resolves exactly to `0.5.3 (21)` in the app target Debug and Release configurations.
3. Exact release PR head passes required `Build & Test (Apple Silicon arm64)` and QA DMG.
4. Final PR is current/mergeable with no unresolved review-thread blocker.
5. Merge to `main` triggers `Publish Release` successfully.
6. GitHub tag `v0.5.3` and Release exist and target the release merge identity.
7. Release exposes downloadable `FloatTabs-0.5.3.dmg`, DMG SHA-256, dSYM archive and dSYM SHA-256.
8. After publication, reconcile STATUS/TASK as terminal with `ACTIVE_PRODUCT_TASK=NONE`.

## Data safety

Release preparation and publication must not clear, migrate, reset, or rewrite Browser Profile data, Web App Slot configuration, website login/session/cookies, WebKit stores, backups, or recovery material.

## STOP conditions

STOP if the version/build edit requires product source changes, the final PR contains unexpected runtime changes, required hosted checks fail, the publisher fails, the release/tag identity is ambiguous, or PR #124 would need to be incorporated.

## Completion boundary

This task is complete only after v0.5.3 Build 21 is published and downloadable on GitHub, publication identity/assets are verified, and the release lifecycle/control plane is closed on `main`.