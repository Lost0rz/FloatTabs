# FloatTabs Current Status

**Status date:** 2026-10-17
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: SHELL_INTERACTION_REFINEMENT_ACTIVE**

The ChatGPT performance-measurement task is complete and merged. Product work has moved to a shell-input refinement: remove FloatTabs-owned external window-drag acquisition so the left Tab rail and transparent outside perimeter no longer compete with clicks, while preserving the existing inner Web-surface movement affordance.

## Verified baseline

- Current `main`: `a4c9ad63831cc15ad75257976982b416e7101c3a` — merge commit for PR #122.
- PR #122 — `Perf: establish ChatGPT long-running measurement seam`: `MERGED`.
- Post-merge `Benchmark Tool CI` and `macOS CI` on `main@a4c9ad63831cc15ad75257976982b416e7101c3a`: `PASS`.
- Fresh open-PR inventory at task authorization: none.
- Previous task `FT-CHATGPT-PERF-001`: `COMPLETED / MERGED`; long-running performance baseline remains deferred and is not part of the active product task.

## Shell interaction audit

Current code has two independent window-movement acquisition layers:

- `PanelPerimeterDragView` in the floating shell owns the **outer** half of the movement target. It advertises move cursors, draws a tiny nonzero acquisition surface, hit-tests outer Web gutters, and adds a narrow `blankRail` leading strip so uncovered Tab-rail space can move the window.
- `WebSourceEdgeDragView` in the ordinary Web source window owns the **inner** half of the movement target and moves the shell from bounded bands just inside the Web surface.

Additional verified facts:

- `FloatingPanel.isMovableByWindowBackground = false`; the problematic drag behavior is custom hit testing, not AppKit background dragging.
- `PanelMetrics.outerInteractionGutter = 12` is also part of shell/layout geometry. Removing external drag must **not** collapse this spacing or rewrite persisted panel/viewport sizing.
- `PanelMetrics.collapsedRailLeadingInset = 12` is a physical rail-collapse inset. It must remain 12 pt even though it will cease to be a movement target.
- Tab, Add, Settings, Pin and speech controls explicitly reject window movement; Tab views also own a separate drag gesture for Tab reordering. Those interaction semantics must be preserved.
- Current `FloatTabs_UI_Design_System_v1.3.md` still requires uncovered rail gaps / leading gutter to participate in movement, including the collapsed 12 pt strip. That accepted interaction contract must be revised with this task.
- Existing `ExternalShellTests` contain assertions that outer gutters and the collapsed leading gutter are movement targets; those tests are expected to change with the product contract.

## Product decision

The new shell-movement contract is:

```text
WINDOW MOVEMENT OWNER = INNER WEB-SURFACE MOVEMENT BAND ONLY
```

Required behavior:

- outer transparent top / right / bottom shell gutters do not move FloatTabs;
- the complete left Tab rail does not move FloatTabs, including uncovered gaps, the narrow leading strip, and hover-expanded Tab surroundings;
- collapsed 12 pt leading inset remains a physical layout/fold state but is not a movement target;
- no outer move cursor or synthetic acquisition surface remains;
- `WebSourceEdgeDragView` remains the movement affordance on the inner Web edges;
- Tab click, Tab reorder, rail controls, fold/unfold, bottom-right resize, window/focus ownership, fullscreen coordination, Browser Profiles, Web runtime and persistence semantics remain unchanged.

The intended UX is to remove accidental FloatTabs movement and reduce interception of clicks over visually external/transparent shell areas, especially around the left rail.

## Domain / Authority

- Window / Panel / Fullscreen owns shell/window movement and synchronization.
- Focus / Input / Commands owns click/drag routing boundaries.
- `docs/design/FloatTabs_UI_Design_System_v1.3.md` is the current shell interaction contract and must be updated as part of the implementation.
- No Tab, Web runtime, persistence, Attention, Speech, Diagnostics or Browser Profile authority changes are authorized.

## Current posture

```text
ACTIVE_PRODUCT_TASK=FT-SHELL-INNER-DRAG-001
LAST_COMPLETED_TASK=FT-CHATGPT-PERF-001
TASK_STATE=ACTIVE
TASK_BRANCH=product/ft-shell-inner-drag-001
TASK_PR=PENDING
ROOT_CAUSE=N/A
PERFORMANCE_OPTIMIZATION_AUTHORIZED=NO
LONG_RUNNING_BASELINE_AUTHORIZED=NO
```

## Acceptance posture

This is a macOS pointer/hit-testing change. Static review and unit tests are insufficient by themselves. Before merge, require focused regressions plus Real-Mac acceptance proving:

- first click still selects Tabs from a background application;
- hover-expanded Tabs remain fully clickable;
- Tab reorder still works;
- left rail / leading strip cannot move the FloatTabs window;
- outer top / right / bottom transparent gutters cannot move the FloatTabs window and do not retain the old move cursor/acquisition behavior;
- inner Web-edge drag still moves FloatTabs;
- bottom-right resize still works;
- fold/unfold geometry remains synchronized and drift-free.

## Deferred follow-ups

Performance baseline work remains independent and deferred. The active shell task does not authorize Observer/Liveness optimization, runtime rejuvenation, reload/reset policy, or performance-baseline execution.
