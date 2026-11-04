# FloatTabs Current Task

**TASK_ID:** `FT-PANEL-CROSS-DISPLAY-001`  
**TASK_CLASS:** `CORRECTIVE`  
**TITLE:** Respect user-positioned display across hide/reopen; bound explicit previous-app reactivation  
**STATE:** `AUTHORIZED / LOCAL IMPLEMENTATION PENDING`  
**BRANCH:** `codex/panel-cross-display-position-001`  
**BASE OBSERVATION:** `main@2a52800f770266f7c901eb612a0b319ddca142df`

## Authority and isolation

The user approved this new independent Panel / Window / Focus behavior corrective on 2026-11-04. `CURRENT_TASK.md` in this branch owns this authorization. `AGENTS.md` and the existing UI/shell accepted design contracts govern owner boundaries; use `docs/README.md` and `docs/architecture/DOMAIN_MAP.md` for navigation.

Do not modify pending PR #195 or its checkout. PR #195 is a separate, independently write-capable Draft delivery pending human acceptance. The new task is branched from merged `main` rather than stacked onto PR #195; before final merge, refresh main and preserve any independently merged lifecycle changes. Before local edits, check exact refs and classify relevant checkout/worktree unique work, overlapping writers and local branch occupancy. Use an existing safe checkout when possible; no routine new physical worktree.

## Frozen product behavior

1. **User-positioned window wins.** If the Panel was previously placed on any currently connected display B, hiding and showing it must preserve B's actual position even when mouse, frontmost app, Dock or global hotkey originate from display A. Initial show with no valid saved/placed frame may use mouse-based screen choice.
2. **No gratuitous reposition.** Resolve a target display using the existing frame's intersection with **all connected** screens when the Panel already has a placement. Do not clamp a valid B frame to a single mouse-selected screen. Preserve requested viewport size, user-resized dimensions and top-left anchoring semantics; keep shell and separately hosted source window synchronized.
3. **Disconnected displays.** If last frame has no valid intersection with any connected screen, relocate safely to an available visible frame without inventing new screen-ID persistence. Never force the panel offscreen. Do not silently expand the feature into migration/Settings.
4. **Hide focus ownership.** When an explicitly restored previous app would send focus back across a screen after the user moved FloatTabs, do not explicitly activate it. Existing `previousApplicationContext` uses `NSScreen.main` and must not be presented as authoritative external-window placement. Distinguish explicit previous-app activation from macOS `NSApp.deactivate()` default behavior: do not promise macOS will keep desktop B active with no B foreground app. Preserve correct same-display restoration when safe and preserve external-click auto-hide focus ownership. No synthetic desktop click, Finder activation or private API.
5. **Single writer.** `PanelController` remains sole position/visibility/focus decision owner. `ScreenPositioning` is pure geometry. `FullscreenSourceHostController` follows shell, not an independent placement writer. Do not modify WebView lifecycle/pool, ChatGPT URL restore, persistence schemas, Browser Profile, session or cache data.

## Authorized source/test scope

- `FloatTabs/Panel/PanelController.swift`: presentation screen selection for positioned vs unpositioned panel, hide/previous-app focus decision as strictly warranted, save/restore and source-frame synchronization.
- `FloatTabs/Panel/ScreenPositioning.swift`: bounded pure geometry helper if needed, reuse existing `relocatedFrame`, `bestVisibleFrame`, and fallback logic where sufficient.
- `FloatTabsTests/ScreenPositioningTests.swift`: A to B drag position, hide and reopen while mouse A, initial presentation, display unplug, size/edge cases.
- `FloatTabsTests/ExternalShellTests.swift`: focused pure-decision regression for explicit previous-app activation only if source change warrants it.
- `CURRENT_STATUS.md`, `CURRENT_TASK.md`: material status/authorization alignment only.

Touching source host, fullscreen, focus adapters, or settings beyond these paths requires explicit task-scope reconciliation **before mutation**.

## Execution gates

**Gate 0 / Baseline:** read controls and current refs, worktree ownership and diff, avoid overlapping writers. STOP if unsafe or ambiguous.

**Gate 1 / Focused implementation:** implement smallest position-first fix, no generic multi-monitor framework. Make pure decision testable. Avoid `NSScreen.main` or `NSEvent.mouseLocation` becoming the owner of an already-positioned panel. For same-display previous-app restoration preserve existing intent unless shown unsafe; for moved-across-display suppress explicit reactivation without claiming control of OS Space selection.

**Gate 2 / Regression tests:** assert A→B→hide→show remains B despite mouse on A; initial presentation behavior unchanged; B unplug recovers visible frame; B remains connected across hide; screen-change callback does not thrash; viewport resize, fixed/per-App sizes, frame persistence, shell/source synchronization, pin/auto-hide, same-display focus behavior and fullscreen restoration are preserved. Focused tests first. Run formal repo-prescribed Partition A+B when required, arm64 Debug/Release and architecture/package checks proportional to high-risk Panel/focus changes. No pointless performance probes.

**Gate 3 / Delivery and acceptance:** fresh exact-diff ownership/data-safety review, commit/push only this task's authorized branch after new refs and writer checks, verify delivered ref, run literal-head CI and QA DMG where applicable. Keep Draft/unmerged until user tests A→B→hide→reopen, cross-display prior-app behavior, click-outside, global hotkey, display detach and ordinary fullscreen/restore. `HUMAN_UI_ACCEPTANCE=PENDING` until explicit user verdict.

## STOP

- position policy silently changes Browser Profiles, WKWebView/session lifecycle, notification or URL restore;
- independent source window gets a second canonical frame writer;
- old previous-app activation causes known cross-display hijack after patch;
- unknown dirty/unique work, stale or contradictory task refs, non-fast-forward, required CI or focused regression failure;
- fix requires controlling macOS system desktop/Space selection through private APIs, synthetic input or unreliable inferred display identity;
- #195 is modified or inadvertently merged/released.

Report a bounded blocker with preserved local work, rather than reset, workaround reload or blanket Skip.

## Expected receipt

```text
CARD_ID=
TASK_ID=
MODE=
CAPABILITY=
OUTCOME=
START_IDENTITY=
FINAL_IDENTITY=
CHANGED_PATHS=
POSITION_PRESERVED_A_TO_B=
FIRST_SHOW_FALLBACK=
DISCONNECTED_DISPLAY_FALLBACK=
SHELL_SOURCE_ALIGNMENT=
PREVIOUS_APP_CROSS_DISPLAY=
SAME_DISPLAY_RESTORE=
FOCUSED_TESTS=
CANONICAL_XCTEST_A_B=
ARM64_DEBUG_RELEASE=
CI=
QA_DMG=
HUMAN_UI_ACCEPTANCE=
LOCAL_COMMIT=
REMOTE_DELIVERY=
REMOTE_REF=
REMOTE_COMMIT=
OTHER_WORKTREE_UNIQUE_WORK=
CONTROL_ALIGNMENT=
PR=
BLOCKERS=
NEXT_SAFE_ACTION=
```
