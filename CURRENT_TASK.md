# FloatTabs Current Task

**Task ID:** `FT-RELEASE-0.5.3-001`
**Title:** Publish FloatTabs v0.5.3 Build 21 and close the release lifecycle
**Status:** `COMPLETED`
**Mode:** `TERMINAL`

> This task is terminal. It records the completed release and grants no further release or product mutation authority.

## Completed objective

FloatTabs **v0.5.3 (Build 21)** has been published as a downloadable GitHub Release from the accepted product baseline.

## Delivery identity

- Release preparation base: `main@869bfaeb7eb6b00d9f2460fd638cb922f3200981`.
- Release PR: #127 — `Release FloatTabs v0.5.3 Build 21`.
- Final release PR head: `25c3508832e8fa384cc3282f569222c06fc67b16`.
- Release merge commit / publisher source: `7d275762de0e2abba9fd1efcb0efb1dc87e00a99`.
- Tag: `v0.5.3`.
- GitHub Release ID: `416230888`.
- Published version/build: `0.5.3 (21)`.

## Verification record

- Final release PR diff: only `CURRENT_STATUS.md`, `CURRENT_TASK.md`, `FloatTabs.xcodeproj/project.pbxproj`, and `docs/release/FloatTabs_v0.5.3.md`.
- App target Debug/Release metadata: `MARKETING_VERSION = 0.5.3`, `CURRENT_PROJECT_VERSION = 21`.
- Exact PR head macOS CI: PASS.
- Exact PR head QA DMG: PASS.
- Final PR mergeability/review-thread audit: PASS.
- Publish Release workflow run `39097105718`: PASS.
- Package build/verification: PASS.
- Release filename/checksum verification: PASS.
- New GitHub Release publication: PASS.
- Release target commit: `7d275762de0e2abba9fd1efcb0efb1dc87e00a99`.

## Published assets

- `FloatTabs-0.5.3.dmg` — uploaded, SHA-256 digest reported by GitHub: `036015d1fbcafd3e0017807c255a7b968a9f62648f51fdb636b93e5ee4755a2b`.
- `FloatTabs-0.5.3.dmg.sha256` — uploaded.
- `FloatTabs-0.5.3.dSYM.zip` — uploaded, SHA-256 digest reported by GitHub: `565cd72fa5d4195eb1818bf26bbd9995e464af88cd264989f036b5dc8b88fa1e`.
- `FloatTabs-0.5.3.dSYM.zip.sha256` — uploaded.

## Scope / data safety

- No production Swift/runtime behavior was changed by the release task.
- The temporary release-preparation workflow self-deleted before PR #127 and left no net workflow diff.
- Browser Profile data, Web App Slot configuration, website login/session/cookies, WebKit stores, backups and recovery data were not reset or migrated.
- Diagnostics/history PR #124 remains separate and was not included in v0.5.3.

## Terminal boundary

No further work is authorized under `FT-RELEASE-0.5.3-001`. A later release, hotfix, product change, cleanup, or diagnostics-history decision requires a new/reconciled `CURRENT_TASK.md`.