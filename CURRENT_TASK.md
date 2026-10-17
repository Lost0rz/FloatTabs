# FloatTabs Current Task

**Task ID:** `FT-SHELL-INNER-DRAG-001`
**Title:** Remove external window-drag acquisition and keep inner Web-surface movement
**Status:** `ACTIVE`
**Mode:** `PRODUCT_INTERACTION_IMPLEMENTATION`

## Objective

Remove FloatTabs-owned window-movement hit regions from the shell exterior and the complete left Tab rail so those surfaces no longer compete with normal clicking. Preserve only the existing movement affordance inside the Web surface.

The requested product behavior is explicit: the left Tab area, including hover-expanded Tab geometry and uncovered rail space, must not move the FloatTabs window; outer transparent shell gutters must not be movement targets; the bounded inner Web-edge movement band remains the supported way to drag the window.

## Authority / baseline

- Project rules: `AGENTS.md`.
- Domain navigation: `docs/architecture/DOMAIN_MAP.md`.
- Current shell interaction contract: `docs/design/FloatTabs_UI_Design_System_v1.3.md`.
- Production source and regression tests on the task branch are runtime/interaction truth.
- Authorization-time `main`: `a4c9ad63831cc15ad75257976982b416e7101c3a`.
- PR #122 is merged at that baseline; its post-merge Benchmark Tool CI and macOS CI both passed.
- Fresh open-PR inventory at authorization found no overlapping open PR.
- Authorized task branch: `product/ft-shell-inner-drag-001`.
- Draft PR: #123 — `Refine shell movement to inner Web surface only`.

## Audited implementation boundary

The current shell movement path is split across two owners:

1. `PanelPerimeterDragView` (`FloatTabs/Web/WebViewContainer.swift`) owns external/shell movement acquisition. Its geometry includes outer Web-edge gutters plus a narrow `blankRail` leading strip; it also owns the move cursor and the low-alpha acquisition surface used to make those transparent pixels reliably receive a mouse-down.
2. `WebSourceEdgeDragView` (`FloatTabs/Panel/FullscreenSourceHost.swift`) owns the inner Web-edge movement bands and moves the shell from global pointer deltas.

Supporting geometry is in `FloatTabs/Panel/ScreenPositioning.swift`:

- `outerInteractionGutter = 12` is both shell/layout spacing and the old outer movement depth;
- `innerMovementOverlap = 12` is the inner Web movement depth;
- `collapsedRailLeadingInset = 12` is a physical collapse inset and must remain part of layout even after it stops being a movement target.

The accepted UI v1.3 contract currently says rail gaps / leading gutter remain movable. This task intentionally supersedes that movement rule and must update the contract in the same implementation.

## New interaction contract

After this task:

- **Only** the inner Web-surface movement band may move FloatTabs.
- Outer top / right / bottom transparent shell gutters must not initiate window movement.
- The complete left Tab rail must not initiate window movement in expanded or collapsed state.
- Uncovered rail gaps and the former narrow leading `blankRail` strip must not initiate window movement.
- The collapsed 12 pt leading inset remains physical geometry for rail collapse/fold presentation, but is **not** a movement target.
- No outer move cursor or synthetic low-alpha movement acquisition surface may remain.
- Visible rail controls keep their existing click/cursor semantics.
- Tab drag continues to mean Tab reordering, not window movement.
- `WebSourceEdgeDragView` remains responsible for inner Web-edge window movement.

## Authorized scope

The implementation may change only what is necessary to enact and verify the contract above, including:

- `docs/design/FloatTabs_UI_Design_System_v1.3.md` — revise Sections 4/6/9 or equivalent current shell movement/acceptance text so the accepted contract no longer requires external/rail movement targets;
- `FloatTabs/Web/WebViewContainer.swift` — remove or neutralize external perimeter/rail movement hit testing, cursor registration and acquisition drawing while preserving required shell/fullscreen z-ordering;
- `FloatTabs/Panel/ScreenPositioning.swift` — separate stale movement terminology from layout geometry if needed, without changing nominal panel/viewport formulas or the 12 pt physical collapse inset;
- `FloatTabs/Panel/FullscreenSourceHost.swift` — preserve `WebSourceEdgeDragView` as the inner movement owner; only bounded comments/geometry adjustments needed to keep the new single-owner contract coherent are authorized;
- `FloatTabs/UI/ExternalTabRail.swift` — only bounded interaction/hit-test adjustments if evidence shows they are necessary to preserve Tab/control clicks or Tab reorder after external movement removal;
- `FloatTabsTests/ExternalShellTests.swift` and the narrowest directly relevant tests — replace old outer-movement expectations with the new contract and preserve inner movement, Tab, fold and resize regressions;
- `CURRENT_STATUS.md` / `CURRENT_TASK.md` at terminal control alignment.

Implementation choice may retain an inert shell overlay/layering anchor if removing the existing `PanelPerimeterDragView` object would unnecessarily disturb fullscreen z-ordering. Any retained object must own **zero** movement hit targets, move cursors and acquisition pixels.

## Protected behavior / non-goals

Do **not** change:

- persisted panel/viewport size formulas;
- `externalControlZoneWidth = 76` or the physical 12 pt collapsed leading inset solely to accomplish drag removal;
- bottom-right resize ownership or geometry;
- Tab selection, Tab ordering/reorder threshold, Add/Settings/Pin/Speech control semantics;
- rail fold/unfold animation timing or persisted collapse state;
- WebKit source-window/runtime ownership;
- fullscreen source-session lifecycle or restoration policy;
- focus authority, global hotkeys, app-command routing;
- Browser Profiles, cookies, website sessions/data, persistence or backups;
- Attention/Speech/Diagnostics/performance-measurement semantics;
- long-running performance baseline or any performance optimization.

Do not replace the removed external drag target with another invisible window-drag zone elsewhere in the rail/shell.

## Verification gates

### Gate 0 — baseline / ownership

Before code mutation:

- refresh refs;
- confirm the task branch derives from the authorized `main` baseline or only contains the expected control-plane authorization drift;
- inspect local worktree state and preserve unknown local/untracked work;
- stop on material main/Authority drift or overlapping unique writer work.

### Gate 1 — focused code/test proof

Add/update focused regression coverage proving at minimum:

- external perimeter movement geometry is absent/inert;
- expanded rail gaps and hover-expanded Tab regions cannot become window-movement targets;
- collapsed 12 pt leading inset is not a movement target;
- inner `WebSourceEdgeDragView` still exposes its bounded four-edge movement regions with the resize exclusion preserved;
- rail controls retain `mouseDownCanMoveWindow == false` behavior;
- Tab reorder behavior remains distinct from window movement;
- fold/collapse geometry and nominal viewport formulas remain unchanged;
- resize ownership remains unchanged.

Run the narrowest relevant XCTest target(s) first, then broaden to the project macOS test/build gate because this touches shell hit testing and window interaction.

### Gate 2 — build / hosted CI

- Debug build: PASS.
- Release arm64 build: PASS.
- exact-head macOS CI: PASS before merge readiness.
- any other automatically triggered required repository checks must be reported from the literal PR head.

### Gate 3 — Real-Mac interaction acceptance

On a real Mac using the exact task build, verify and record:

1. From another foreground application, the first click on a Tab selects it; no two-click activation regression.
2. A hover-expanded Tab remains clickable over its complete visual frame.
3. Dragging a Tab still reorders Tabs and does not move the window.
4. Dragging/clicking uncovered expanded left-rail space does not move FloatTabs and no move cursor is advertised there.
5. In collapsed mode, the physical 12 pt leading strip does not move FloatTabs and no move cursor is advertised there.
6. Outer top / right / bottom transparent gutters do not move FloatTabs and do not retain the old low-alpha acquisition behavior. Where those pixels are visually external/transparent, verify they no longer steal the gesture as FloatTabs window movement.
7. Dragging from each intended inner Web edge still moves the FloatTabs shell coherently.
8. Bottom-right resize still resizes rather than moving the window.
9. Fold → unfold remains visually synchronized and does not introduce geometry drift.
10. If implementation changes shell layering/anchors rather than merely neutralizing the old drag layer, also perform a focused fullscreen enter/exit smoke proving source/companion ordering and restoration remain coherent.

Static tests cannot substitute for this Real-Mac acceptance.

## STOP conditions

STOP and report evidence if:

- implementation requires changing persisted sizing, Browser Profile/session data, Web runtime lifecycle, focus authority, fullscreen ownership, or recovery semantics outside the bounded shell change;
- removing the outer drag acquisition cannot be separated from a larger shell/window architecture rewrite;
- visually transparent external pixels still behave as FloatTabs movement targets after the proposed change;
- inner Web-edge movement is lost or conflicts with resize/rail controls;
- Tab click/reorder or first-click activation regresses;
- fullscreen/source ordering regresses because of shell-layer changes;
- task-relevant `main` / accepted interaction Authority changes materially;
- overlapping unique writer work appears;
- required tests/build/Real-Mac evidence cannot establish the new interaction contract safely.

## Completion boundary

This task is complete only when:

- the accepted UI interaction contract is updated;
- external/rail window-movement acquisition is removed on the task branch;
- only inner Web-surface movement remains;
- focused regressions and project build/CI are green;
- Real-Mac acceptance confirms Tab click/reorder, external non-drag, inner drag, resize and fold behavior;
- the implementation is remotely delivered through Draft PR #123;
- terminal Control Alignment updates `CURRENT_STATUS.md` / `CURRENT_TASK.md` and closes the task/PR/workspace lifecycle cleanly.
