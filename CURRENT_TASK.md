# FloatTabs Current Task

**TASK_ID:** `FT-PANEL-CROSS-DISPLAY-SUMMON-001`
**TASK_CLASS:** BOUNDED PRODUCT CORRECTIVE — PANEL / MULTI-DISPLAY SUMMON
**STATE:** IMPLEMENTED / LOCAL_MACHINE_GATES_PASS / FINAL_REMOTE_CI_QA_AUDIT_AND_ACCEPTANCE_PENDING
**BRANCH:** `codex/ft-panel-cross-display-summon-001`
**BASELINE:** `main@d64c9ec62660e9a855056c08e013a71a58db821b`
**PR:** #200 OPEN / DRAFT; do not merge until independent exact-diff audit, explicit human UI acceptance and exact-head host gates.
**CONTROL_MODE:** FILE_CONTROL (unchanged).

## Authority and preceding work

User reported and explicitly authorized correcting this regression on 2026-11-05: FloatTabs opened previously on display A, then hidden, must reappear on the screen containing the mouse cursor (display B) when explicitly summoned by global shortcut or menu bar action. Reverse B->A also applies. PR #196, product commit a39b87a91be60f70c40cf8b600f5b3b7725f6568, is already merged on main at d64c9ec6 and human accepted its other Panel/Focus behavior. The previous main CURRENT_STATUS/CURRENT_TASK snapshot of PR #196 as unmerged was POST_MERGE_DRIFT and is reconciled here as the first control-only change of a genuinely new product corrective task. Do not reopen or revert #196 wholesale.

This is a new engineering purpose, independent of the ongoing Draft lifecycle PR #195 and governance migration PR #199. Main remains FILE_CONTROL until verified ISSUE_CONTROL migration merge. A handoff card is transport, not a second authority.

## Observed defect and code seam

- `FloatTabs/Panel/PanelController.swift::positionPanelForCurrentScreens()` correctly resolves the target by `ScreenPositioning.targetScreen()`, but PR #196 changed the already-positioned Shell's `ScreenPositioning.relocatedFrame` input from `[targetScreen.visibleFrame]` to `screens.map(\.visibleFrame)`.
- With A still connected, `bestVisibleFrame` selects A by intersection with the saved/current frame even if the pointer and new summon action are on B. This is a code-supported likely regression seam; no new real-Mac corrective was validated yet.
- Reproduce with existing installed build and record exact installed app/build provenance if accessible. Do not infer installed HEAD solely from GitHub source.
- Preflight found no running FloatTabs process, so installed-build provenance was unavailable. Deterministic geometry regressions reproduced A→B and B→A before correction; a controller-path restored A→B regression was also verified red when the original all-connected-screen placement was temporarily reinstated.

## Frozen expected behavior

1. When Shell is hidden, explicit user summon via global hotkey or menu-bar action uses the current pointer-containing connected display for placement. A -> B and B -> A must both work. The presented Web surface gets normal owned native focus/readiness behavior.
2. Same-display summon preserves the user-chosen frame origin and preferred viewport size to the extent allowed by that display's visible frame.
3. Move pointer between displays while Shell is already visible: do not automatically move Shell. Dragging Shell manually still moves and persists normally. Preserve existing one-press visible->hide toggle semantics.
4. First restoration of a saved frame, later already-positioned summons, display disconnect/reconnect, invalid/unknown mouse target fallback, fixed/per-WebApp viewport, fullscreen companion/Source Host synchronization must behave safely. If pointer target is unknown, choose a deterministic existing valid-screen fallback rather than relocating to an arbitrary invalid screen.
5. No forced app reactivation loop, spurious previous-app activation, focus stealing on other displays, duplicate Window/Runtime ownership, or new WebView navigation/reload. Preserve other improvements of merged PR #196.

## Authorized scope

- `FloatTabs/Panel/PanelController.swift`: only explicit-summon placement and directly necessary call-site discrimination between summon vs passive topology repair; preserve focus, fullscreen and previous-application logic unless a directly evidenced adjacent bug requires a scope decision.
- `FloatTabs/Panel/ScreenPositioning.swift`: only minimal geometry/pure helper when genuinely needed.
- `FloatTabsTests/ScreenPositioningTests.swift`, `FloatTabsTests/ExternalShellTests.swift`: focused deterministic A/B screen-frame placement, first restored-frame and fallback tests and relevant Panel toggling regressions.
- `CURRENT_TASK.md` / `CURRENT_STATUS.md`: current task evidence and state as materially needed.
- Any additional code/test files require a reasoned scope reconciliation before mutation.

OUT OF SCOPE: WebKit Runtime lifecycle/reclaim, PR #195 ChatGPT cold restore/experimental fixture teardown, PR #199 Issue Control migration, CI workflow policy, persisted Browser Profiles/Cookies/Session/site data, broad Focus/Window rewrite, new Settings UI, arbitrary cursor-follow-on-move behavior, release.

## Gates / work packages

**G0 — Worktree/authority.** Refresh main/branch/PR, reread AGENTS and this Task from the actual selected checkout, identify writer ownership, check all worktrees and unique/uncommitted work. Prefer safely reusing the clean canonical checkout for this new short corrective if verified. Do not overwrite or checkout across the dirty PR #195 worktree (four tracked modifications and untracked WebKitFixtureTeardown.swift), the detached restore worktree, or the Draft #199 governance branch. Stop if branch/ref diverges or an overlapping writer exists. The remote task branch has an initial control-only commit before code.

**G1 — bounded audit/red-green.** Confirm actual event entry paths for both global hotkey and menu bar (avoid assuming identical entry without code proof), including when Shell is already visible vs hidden, panel/screen/Source Host frames, target fallback and fullscreen guards. Add a regression that fails on the original A->B/B->A hidden summon implementation while confirming preservation of same-screen placement and the current #196 focus safeguards. Do not use actual display-mutation hacks in deterministic unit tests.

**G2 — smallest correction.** Make the explicit summon target pointer display authoritative without changing passive display-topology clamping/dragging. Prefer reusing existing `targetScreen` and `relocatedFrame` logic, with narrow branch split only where required. Preserve user size, saved origin on same display, normal focus handshake and source-host frame sync. No WebView reload/reset, persistence corruption or arbitrary new window movement.

**G3 — machine verification.** Run focused ScreenPositioningTests + ExternalShellTests and relevant Panel/focus/source/fullscreen regressions (including current #196 cases). Confirm both Debug/Release arm64 build and exact-diff review; follow project current canonical XCTest/CI rules proportional to product change. Report actual exact-head CI results, separate known monolithic WebKit XCTest baseline failures from new regressions, do not silently waive required checks or rewrite CI to mask failures. QA DMG must be provenance-matched to the corrected source head.

**G4 — fresh review and human acceptance.** Independent exact-diff safety review, then user-owned real dual-display QA: hide A, pointer B + hotkey and menu bar summon => B, reverse B->A, same-display no jump, mouse-only no move, drag/persistence, one-press hide/show, focus and fullscreen/screen disconnect if available. HUMAN_UI_ACCEPTANCE=PENDING until explicit user verdict. Do not mark Ready/merge/release without independently verified host gates, no conflicting PR state and explicit user merge decision.

## Stop/safety

Stop on unknown local unique-work ownership, conflicting branch/checkouts, failure to preserve prior #196 semantics, loss of focus/readiness, fullscreen/source window regression, changes to Browser Profile/session data, required test regression, inability to make both entry paths use the same correct target screen or unclear UI behavior requiring a new product decision. Do not use reset/stash/clean/force push or cleanup of unrelated worktrees as ordinary recovery.

## Execution evidence — 2026-11-05

- G0 passed: clean canonical checkout was reused; target branch and PR #200 matched the observed `798522034329fc54ca8f80fb1145e4ef103ba15c` head; no local writer occupied that branch. PR #195's dirty WP2 worktree and detached restore worktree remain untouched. PR #199 remains OPEN / DRAFT / unmerged, so FILE_CONTROL remains active.
- G1 passed: both menu-bar and global-hotkey hidden-window paths reach `showFloatTabs()` and its explicit placement call. Synthetic A/B pointer selection is tested through the selector used by `targetScreen`. Geometry A→B/B→A regressions fail on the old all-connected-display behavior. A controller-path restored A→B regression was verified red when the old relocation was temporarily reinstated.
- G2 implemented in `PanelController.swift` and `ScreenPositioning.swift`; restored and already-positioned frames share the explicit-summon path. Fullscreen companion placement and passive topology clamping retain the connected-display behavior.
- G3 local passed on 2026-11-06: focused `ScreenPositioningTests`, `ExternalShellTests`, and `WebFocusAdapterTests` passed 175/175; the full arm64 XCTest passed 1,175, skipped 4, failed 0; final placement regressions passed 4/4; Debug and Release arm64 builds exited 0. The Xcode host emitted a CoreSimulator version mismatch warning, while macOS tests completed successfully.
- Earlier remote CI and QA-DMG runs passed on the preceding implementation commit `7ad4d9fc7d218f5debd7bbf28bbc1a83cbe0bd85`. They do not cover the new controller-path tests and selector refactor; exact corrected-source reruns and a provenance-matched QA DMG are pending.
- G4 independent exact-diff audit passed: separate code-review agent reviewed `d64c9ec62660e9a855056c08e013a71a58db821b..7ad4d9fc7d218f5debd7bbf28bbc1a83cbe0bd85` plus the current worktree diff. It confirmed the full path set, controller regression coverage, preserved PR #196 focus and Source Host behavior, fullscreen/topology separation, and no lifecycle, product-data, or new window-state writer changes. The reviewer did not rerun tests or verify host state.
- No real dual-display test has been performed. `HUMAN_UI_ACCEPTANCE=PENDING`.

## Required return receipt

Report `GOVERNANCE_ROUTE`, `SKILLS_USED`, branch and actual baseline/head, writer/worktree safety, changed files, evidence that old A->B/B->A behavior fails and new behavior passes, focused/arm64/canonical CI/QA DMG results, exact diff, data safety, remote commit/ref/PR state, independent audit provenance, `HUMAN_UI_ACCEPTANCE`, `CONTROL_ALIGNMENT`, merge and next safe action. No success labels without observed evidence.
