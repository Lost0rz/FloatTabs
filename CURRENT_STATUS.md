# FloatTabs Current Status

**Observed date:** 2026-11-04  
**Repository:** `Lost0rz/FloatTabs`  
**Branch:** `codex/panel-cross-display-position-001`  
**Observed base:** `main@2a52800f770266f7c901eb612a0b319ddca142df` (provenance, not an immutable equality lock)

## Active scope

**ACTIVE TASK: `FT-PANEL-CROSS-DISPLAY-001` — WINDOW POSITION / FOCUS CORRECTIVE; LOCAL IMPLEMENTATION PENDING.**

User report: open FloatTabs on display A, manually drag its shell/Web host to display B, dismiss without clicking B's desktop, and observe unexpected movement/return toward A (either the window on subsequent presentation or the frontmost app/Space on dismissal). The product decision is to respect the last user-positioned connected display and avoid explicit cross-display previous-app reactivation. macOS deactivation can independently select another frontmost app; this is not fully controllable and must not be masked by synthetic Finder activation or fake clicks.

Verified source audit at PR #195 head `a9f07ca02df10d2ea3d0292d1afa5669d115da42` (window source path matches this base for the inspected behavior):
- `PanelController.showFloatTabs` calls `positionPanelForCurrentScreens` at each show.
- For `hasPositionedPanel`, `positionPanelForCurrentScreens` calls `ScreenPositioning.relocatedFrame` with **only** `[targetScreen.visibleFrame]`, where `ScreenPositioning.targetScreen` is chosen from `NSEvent.mouseLocation`. It therefore intentionally relocates a B-positioned window to A when the mouse is on A.
- `PanelFrameStore` already saves full panel geometry. `persistPanelFrame` runs at hide/termination; no new persistence store is needed.
- `hideFloatTabs` records a previous app, deactivates FloatTabs and may activate that app after a display-ID equality check. The previous display ID comes from `NSScreen.main`, not reliably from the actual previous app window; cross-screen focus/Space effect is *plausible but not proven* as a runtime root cause.
- The physical WKWebView source host is a second window whose frame follows the shell through `FullscreenSourceHostController.synchronizeFrame`. Positioning must change only through existing shell/Panel ownership.

## Concurrent, intentionally unchanged delivery

PR #195 `codex/adaptive-lifecycle-wp2-policy` remains **OPEN / DRAFT / UNMERGED** at `a9f07ca02df10d2ea3d0292d1afa5669d115da42`; its ChatGPT URL cold-restore change passed 1,166 formal A+B tests, arm64 build, exact-head CI and QA DMG, but **human acceptance is still PENDING**. Do not rewrite #195, claim user acceptance, or merge it as a side effect of this new independent Panel task.

Main at this task start contains merged WP1; the historical WP1-closeout status embedded in main before this control transition is stale and superseded by verified merge evidence. This branch's control transition authorizes only the new Panel task. If #195 merges while this task is open, refresh/reconcile the branch against current main before final merge checks without discarding either task's unique work.

## Design/verification status

```text
WINDOW_POSITION_ROOT_CAUSE=KNOWN_SOURCE_PATH
CROSS_DISPLAY_FOCUS_CAUSALITY=PARTIAL_NOT_RUNTIME_PROVEN
TASK_AUTHORIZED=YES
PRODUCT_SOURCE_MUTATION=NOT_STARTED
MACHINE_VERIFICATION=NOT_RUN
HUMAN_UI_ACCEPTANCE=PENDING
NEW_TASK_MERGE_READY=NO
PR_195_HUMAN_UI_ACCEPTANCE=PENDING
```

Authority: `AGENTS.md`, `CURRENT_TASK.md`; documentation routes via `docs/README.md` and `docs/architecture/DOMAIN_MAP.md`. Product WebKit/runtime lifecycle, Browser Profiles and site/session data remain outside this task.
