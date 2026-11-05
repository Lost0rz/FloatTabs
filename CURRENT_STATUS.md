# FloatTabs Current Status

**Verified date:** 2026-11-05
**Repository:** Lost0rz/FloatTabs
**Control mode:** FILE_CONTROL
**Current authorized task:** FT-PANEL-CROSS-DISPLAY-SUMMON-001
**Current stage:** IMPLEMENTED / LOCAL_MACHINE_GATES_PASS / REMOTE_CI_QA_AND_ACCEPTANCE_PENDING
**Branch:** `codex/ft-panel-cross-display-summon-001`
**PR:** #200 OPEN / DRAFT; starting PR head `798522034329fc54ca8f80fb1145e4ef103ba15c`
**Base main:** `d64c9ec62660e9a855056c08e013a71a58db821b`
**Release:** NOT_AUTHORIZED

## Verified previous task closeout

PR #196 (`FT-PANEL-CROSS-DISPLAY-001`) was verified MERGED/CLOSED; merge commit `d64c9ec62660e9a855056c08e013a71a58db821b`, preserving previously human-accepted Panel/Focus corrective. Root main's former Task/Status captured PRE-MERGE gate and was stale after merge. This new material task branch's initial control-only commits reconcile that external host event; no new status-only PR has been created.

## Reported regression: explicit summons selects wrong display

User observed: after Shell was opened on display A then hidden, pointer moves to display B; global hotkey or menu-bar activation still opens on A, unless Shell is manually dragged to B. Reverse B->A should also work. This is a user-observed product regression, not a WebView keyboard-focus defect.

The code cause is confirmed in `PanelController.positionPanelForCurrentScreens()`: the already-positioned Shell was relocated against all connected screens, so `ScreenPositioning.relocatedFrame` preferred the original frame's overlapping display instead of the pointer target. A new deterministic A→B/B→A test failed in both directions against that behavior. No FloatTabs process was running during preflight, so installed-app build provenance and real two-display reproduction remain unavailable.

Product expected: hidden -> explicitly summon on mouse-containing connected display, while same-display placement and size, manual drag persistence, visible-window pointer moves (no auto-jump), hotkey toggle, menu bar action, Source Host, fullscreen, and prior PR #196 focus safety remain correct.

Authoritative details, scope, acceptance and STOP: `CURRENT_TASK.md` on this branch. `AGENTS.md` unchanged; no changes to Browser Profiles, Cookies, Session, runtime lifecycle policy or persistence.

## Separate work and isolation

- PR #195 OPEN/DRAFT/UNMERGED at last observed `a9f07ca02df10d2ea3d0292d1afa5669d115da42`, product ChatGPT hibernate restore. Its older dirty local worktree at `d02b1a24` with four tracked test/project changes and untracked WebKitFixtureTeardown.swift is UNIQUE EXPERIMENTAL WORK, preserved. The experimental teardown was marked SUPERSEDED_FOR_THIS_INCIDENT / NOT_FOR_MERGE and focused 62/62 local tests do not prove monolithic flake resolved. Do not touch it.
- PR #199 OPEN/DRAFT/UNMERGED at last observed `b69c86c551fc5c7d3bb400c3bd2243678b1b5aae`: issue-control migration incomplete, neither Issue #197/#198 yet has verified independent SPEC_APPROVAL_V1. Its CI had monolithic WebKit XCTest baseline class failures. Main remains FILE_CONTROL until actual verified migration merge.
- Existing #195 and #199 Task/Status/AGENTS proposals do not authorize this new Panel corrective and must not be carried into this branch as task controls. Later merges need explicit conflict reconciliation so no stale Task or FILE_CONTROL control mode is reintroduced.

## Task gates

```ini
G0_LOCAL_WRITER_PREFLIGHT=PASS
G1_MINIMAL_REGRESSION_REPRO=PASS (red/green A->B and B->A)
G2_CORRECTIVE_IMPLEMENTATION=IMPLEMENTED
G3_LOCAL_MACHINE_TESTS=PASS (focused 171/171; full XCTest 1171 passed, 4 skipped, 0 failed)
G3_ARM64_BUILDS=PASS (Debug and Release)
G3_REMOTE_CI=PENDING
G3_QA_DMG=PENDING
G4_INDEPENDENT_AUDIT=PENDING (self-check only so far)
HUMAN_UI_ACCEPTANCE=PENDING
PR_MERGE_READY=NO
MERGE=NOT_MERGED
RELEASE=NOT_AUTHORIZED
```

Proceed with safely isolated implementation only under current Task and existing Project Governance rules. Do not overwrite unknown local work or auto-clean worktrees. Produce truthful exact-head verification and human UI acceptance before any merge.
