# FloatTabs Current Task

**Task ID:** `FT-SHELL-INNER-DRAG-001`
**Title:** Remove external window-drag acquisition and keep inner Web-surface movement
**Status:** `COMPLETED`
**Mode:** `PRODUCT_INTERACTION_IMPLEMENTATION`

> This task is terminal. It records the completed scope and grants no further implementation authority.

## Objective

Remove FloatTabs-owned window-movement acquisition from the shell exterior and complete left Tab rail while preserving only the existing bounded inner Web-edge movement affordance.

## Authority / delivery

- Project rules: `AGENTS.md`.
- Shell interaction contract: `docs/design/FloatTabs_UI_Design_System_v1.3.md`.
- Authorization-time `main`: `a4c9ad63831cc15ad75257976982b416e7101c3a`.
- Task branch: `product/ft-shell-inner-drag-001`.
- Draft PR: #123 — `Refine shell movement to inner Web surface only`.
- Accepted semantic implementation head: `b21a83fb40bf86a55c8aa6186150797166fc6981`.

## Completed result

- `PanelPerimeterDragView` is retained only as an inert stacking anchor and owns no movement hit testing, move cursor, acquisition drawing or drag handlers.
- `WebSourceEdgeDragView` remains the sole window-movement owner.
- Outer top/right/bottom shell gutters and the complete expanded/collapsed left rail no longer initiate FloatTabs window movement.
- The 76 pt expanded rail, 12 pt outer/layout gutter, 12 pt collapsed leading inset and persisted panel/viewport sizing formulas remain unchanged.
- Tab click/reorder, fold/unfold, bottom-right resize, fullscreen ownership, Web runtime, Browser Profiles and user data semantics remain protected.
- `FloatTabs_UI_Design_System_v1.3.md` and focused regression tests were updated to the new interaction contract.

## Verification record

- Focused XCTest: 35 passed, 0 failed.
- Full exact-commit XCTest on Apple Silicon macOS: 1,303 passed, 0 failed, 0 skipped.
- Debug build: PASS.
- Release arm64 build: PASS.
- Exact-head macOS CI: PASS.
- Exact-head QA DMG: PASS.
- Exact Release candidate was installed at `/Applications/FloatTabs.app` and verified running from revision `b21a83fb40bf86a55c8aa6186150797166fc6981` before manual acceptance.
- User Real-Mac acceptance: PASS for the requested edge/perimeter movement correction.
- Destructive user-data actions: NONE.

## Completion boundary

Satisfied. The accepted contract, implementation, automated verification, hosted checks, remote delivery and Real-Mac interaction acceptance are complete.

This task no longer authorizes code changes, additional shell work, performance-baseline execution, logging-retention work, Observer/Liveness optimization, or any other new product objective. New work requires a separately reconciled `CURRENT_TASK.md`.
