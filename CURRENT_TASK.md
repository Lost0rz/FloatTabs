# FloatTabs Current Task

**Task ID:** `FT-RELEASE-0.5.4-001`
**Title:** Publish FloatTabs v0.5.4 Build 22 and close the release lifecycle
**Status:** `COMPLETED`
**Mode:** `TERMINAL`

> This task is terminal. It records the completed v0.5.4 release lifecycle and grants no further product, release, cleanup or diagnostics mutation authority.

## Completed objective

FloatTabs **v0.5.4 / Build 22** has been published as a downloadable GitHub Release from the accepted current main baseline containing the reintegrated long-term local diagnostics/history capability.

## Delivery identity

- Release preparation base: `main@66de8f18c55d46cf882723c05f0afea8249d9e1b`.
- Release PR: #132 — `Release FloatTabs v0.5.4 Build 22`.
- Final release PR head: `b5e3c9951000f67d3ce31f43b41e5e425c7b4d3d`.
- Release merge commit / publisher source: `439590659a42d52abd985c323dee4e1e0fbe9b47`.
- Tag: `v0.5.4`.
- GitHub Release ID: `416270008`.
- Published version/build: `0.5.4 (22)`.
- Publish Release workflow: `39103088335` — PASS.

## Verification record

- Final release PR changed only `CURRENT_STATUS.md`, `CURRENT_TASK.md`, `FloatTabs.xcodeproj/project.pbxproj`, and `docs/release/FloatTabs_v0.5.4.md`.
- App target Debug/Release metadata: `MARKETING_VERSION = 0.5.4`, `CURRENT_PROJECT_VERSION = 22`.
- Exact release PR head macOS CI run `39102628192`: PASS.
- Exact release PR head QA DMG run `39102628179`: PASS.
- Final PR mergeability/review-thread audit: PASS.
- Publish Release package build and Apple Silicon verification: PASS.
- Release filename/checksum verification: PASS.
- New GitHub Release publication: PASS.
- Release target commit: `439590659a42d52abd985c323dee4e1e0fbe9b47`.

## Published assets

- `FloatTabs-0.5.4.dmg` — SHA-256 `ec2c732275bcf85081fbaafd2a6d820eb7064d65cd9ed5aabe40e2d62a2abdde`.
- `FloatTabs-0.5.4.dmg.sha256`.
- `FloatTabs-0.5.4.dSYM.zip` — SHA-256 `e9f840292ba804551b41330e0a3ef5386f3253c21b5e823d9840a12541f31084`.
- `FloatTabs-0.5.4.dSYM.zip.sha256`.

## Product baseline delivered

The release includes the previously accepted current product state, including:

- long-term local diagnostic history;
- Standard / Verbose detail level;
- opt-in low-cadence selected-Slot performance observation;
- `Open Saved Logs Folder` and bounded sanitized JSONL retention/rotation;
- diagnostics-only runtime/WebView/navigation identity evidence and manual reload boundary;
- accepted unread Tab Attention styles/palette and Settings IA;
- preserved Browser Profile/session/WebKit ownership and current focus/navigation/window/runtime behavior.

## Scope / data safety

- The release task introduced no new Swift/runtime/persistence product semantics.
- No Browser Profile, Slot, website login/session/cookie, WebKit store, backup, recovery data or existing diagnostic history was reset, deleted or migrated.
- The temporary release-preparation workflow was absent from the final release PR diff.

## Terminal boundary

No further mutation is authorized under this task. Lifecycle management may now perform read-only inventory/audit. Any branch/worktree/rollback-bundle deletion or other state-changing cleanup requires a new/reconciled task authority before execution.
