# FloatTabs Current Task

**Task ID:** `FT-DIAG-HISTORY-REINTEGRATION-001`
**Title:** Reintegrate long-term local diagnostics history onto the current v0.5.3 main baseline
**Status:** `ACTIVE`
**Mode:** `IMPLEMENT_AND_VERIFY`

## Objective

Restore the already-developed long-term local diagnostics/history functionality from historical Draft PR #124 onto current `main`, preserving all later accepted v0.5.3 product behavior and ownership boundaries.

This is a reintegration task, not a direct stale-branch merge.

## Authority / source evidence

- Authorized base: `main@fef824c4d9f7783dca80e831c3812dae8e5f0833`.
- Historical source implementation: PR #124 / `product/ft-diagnostics-history-001@e8bc90ad5d9897585974a84aef92e89bf3c2f2cb`.
- PR #124 control/history text is not current Authority; only its bounded product implementation and tests are source evidence for the missing feature.
- Current main and accepted v0.5.3 behavior remain authoritative where later changes overlap.

## Required product outcome

Advanced → Runtime Diagnostics must provide the enhanced local-history workflow:

- `Keep local diagnostic history` enable/disable control;
- diagnostic `Detail level` with Standard / Verbose behavior;
- `Long-term performance observation` opt-in control;
- `Export Recent Diagnostics…`;
- `Open Saved Logs Folder`;
- bounded local sanitized JSONL history using the existing diagnostics pipeline;
- seven-day retention intent with bounded segment/rotation limits from the prior implementation;
- low-cadence, content-free selected-Slot health/performance checkpoints (approximately once per minute) when enabled;
- fail-soft behavior and no remote telemetry / automatic AI analysis.

Preserve the previously accepted implementation semantics from PR #124 where compatible with current main.

## Protected boundaries

Do not regress or redesign:

- current unread Tab Attention styles/palette/Settings layout;
- current Settings IA outside the Runtime Diagnostics section;
- Browser Profile/session/WebKit data ownership;
- Tab/Web runtime, focus, navigation, recovery, window/fullscreen ownership;
- current v0.5.3 version/build metadata during this product task;
- existing diagnostics export/privacy contract except where required to restore the accepted local-history behavior.

Do not delete/reset/migrate user configuration, Browser Profiles, website session/cookies, WebKit stores, backups, or diagnostics data.

## Integration strategy

1. Start from the authorized current-main baseline on `product/ft-diagnostics-history-reintegration-001`.
2. Compare the PR #124 implementation against its merge-base and current main.
3. Port only the long-term diagnostics product delta and its relevant tests/project-file registration.
4. Where files changed later on main, merge semantically: current main wins for unrelated later behavior; diagnostics-history additions are reintroduced only within their owned boundaries.
5. Do not copy stale `CURRENT_STATUS.md` / `CURRENT_TASK.md` from PR #124.
6. Keep historical PR #124 open until the fresh integration candidate is verified; only then may it be marked SUPERSEDED/CLOSED.

## Verification gates

### Gate 0 — identity / scope
- branch starts from `main@fef824c4…`;
- only this integration branch writes the reintegration;
- PR #124 remains source-only during implementation;
- unknown overlapping unique work => STOP.

### Gate 1 — preferences / persistence
- local-history mode preference round-trips;
- detail level round-trips;
- long-term observation preference round-trips;
- disabling history safely disables dependent observation projection without destructive data deletion;
- no Profile/Slot/session storage used.

### Gate 2 — Settings / UX
- Advanced shows `Keep local diagnostic history`, `Detail level`, `Long-term performance observation`, `Export Recent Diagnostics…`, `Open Saved Logs Folder`;
- controls synchronize correctly across relaunch/view appearance;
- existing Backup & Restore / About remain intact.

### Gate 3 — writer / retention / observation
- existing diagnostics writer remains canonical;
- local history uses bounded rotation/retention from the prior accepted implementation;
- observation cadence remains low-frequency and content-free;
- selected Slot only; no second durable diagnostics store;
- no remote telemetry/upload/AI runtime integration.

### Gate 4 — regression / hosted verification
- relevant diagnostics, preferences, Settings, attention cross-feature, WebViewPool tests;
- full XCTest;
- Debug and Release arm64 builds;
- exact-head GitHub macOS CI and QA DMG;
- inspect no regression to later Tab Attention / Settings IA behavior.

### Gate 5 — Human Real-Mac acceptance
Install exact Release candidate and confirm:
- Advanced shows the restored controls;
- enabling local history writes local saved logs as designed;
- `Open Saved Logs Folder` exposes the retained files;
- long-term observation can be enabled only with history active and does not visibly disrupt normal use;
- existing General/Audio/Browser settings and unread Tab Attention remain correct;
- no user/session/Profile data regression.

## STOP conditions

STOP if reintegration requires:
- destructive migration/reset of user or WebKit/Profile/session data;
- a second canonical diagnostics writer/store;
- remote telemetry or automatic AI upload/analysis;
- changes to attention acknowledgement/runtime ownership;
- unbounded/high-frequency observation polling;
- unresolved conflict where current-main ownership cannot be preserved safely;
- required hosted CI or Human Real-Mac acceptance failure.

## Completion

Task completes only when the fresh current-main-based implementation passes all applicable automated/hosted gates and Human Real-Mac acceptance, is merged, control files are reconciled, and historical PR #124 receives a clear `SUPERSEDED` lifecycle disposition.