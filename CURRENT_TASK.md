# FloatTabs Current Task

**TASK_ID:** `FT-PANEL-CROSS-DISPLAY-001`  
**TASK_CLASS:** `CORRECTIVE`  
**TITLE:** Respect user-positioned display across hide/reopen; bound explicit previous-app reactivation  
**STATE:** `AUTHORIZED / CORRECTIVE 005 IMPLEMENTED AND LOCALLY VERIFIED / START HEAD 53be4d8151b6b2bf68ab03b97acf869b390c0ace / REMOTE DELIVERY PENDING / PRIOR HUMAN ACCEPTANCE FAIL / RETEST PENDING / PR #195 UNCHANGED`
**BRANCH:** `codex/panel-cross-display-position-001`  
**BASE OBSERVATION:** `main@2a52800f770266f7c901eb612a0b319ddca142df`

## Authority and isolation

The user approved this new independent Panel / Window / Focus behavior corrective on 2026-11-04. `CURRENT_TASK.md` in this branch owns this authorization. `AGENTS.md` and the existing UI/shell accepted design contracts govern owner boundaries; use `docs/README.md` and `docs/architecture/DOMAIN_MAP.md` for navigation.

Do not modify pending PR #195 or its checkout. PR #195 is a separate, independently write-capable Draft delivery pending human acceptance. The new task is branched from merged `main` rather than stacked onto PR #195; before final merge, refresh main and preserve any independently merged lifecycle changes. Before local edits, check exact refs and classify relevant checkout/worktree unique work, overlapping writers and local branch occupancy. Use an existing safe checkout when possible; no routine new physical worktree.

## User-authorized global-hotkey corrective 004 — 2026-11-04

The user authorized this continuation under the same task and PR #196. Retain the completed cross-display window-positioning and pinned hide-focus changes already present in this worktree. The active corrective is limited to the global shortcut route:

- If the shell window is visible, one shortcut press calls the existing explicit hide path regardless of Pinned state, shell Key Window state, or source-window Key Window state.
- If the shell window is hidden, one shortcut press presents FloatTabs and preserves the normal native/WebView Focus Handshake.
- Make `shouldHideForGlobalShortcut()` visibility-only and update its old unit-test assertions in `ExternalShellTests.swift`.
- Preserve the existing fullscreen/session-locked handling in the hide/show paths and the previous cross-display focus-release policy. Do not bypass or rewrite those guards.
- No unrelated changes, new task/branch/worktree, PR #195 changes, commit, push, merge, CI, or release. Keep human UI acceptance PENDING.
- After the focused affected tests, Debug/Release arm64 builds, and `git diff --check` pass, build a **new, unique local QA DMG** using `tools/release/build_dmg.sh`, with fresh source/diff provenance. Do not reuse the prior Focus-QA DMG.

At the local QA stage, this corrective stopped before remote delivery and awaited the user's manual result. On 2026-11-04 the user subsequently authorized a task commit and push to the existing PR #196 branch so remote reviewers/checks can inspect the changes; see the remote-review authorization below. The canonical full-XCTest gate remains deferred pending PR #195's normal acceptance/merge, and human UI acceptance remains PENDING.

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
- `FloatTabsTests/ExternalShellTests.swift`: focused pure-decision regressions for explicit previous-app activation and hide/deactivation policy when source change warrants it.
- `CURRENT_STATUS.md`, `CURRENT_TASK.md`: material status/authorization alignment only.

Touching source host, fullscreen, focus adapters, or settings beyond these paths requires explicit task-scope reconciliation **before mutation**.

## Execution gates

**Gate 0 / Baseline:** read controls and current refs, worktree ownership and diff, avoid overlapping writers. STOP if unsafe or ambiguous.

**Gate 1 / Focused implementation:** implement smallest position-first fix, no generic multi-monitor framework. Make pure decision testable. Avoid `NSScreen.main` or `NSEvent.mouseLocation` becoming the owner of an already-positioned panel. For same-display previous-app restoration preserve existing intent unless shown unsafe; for moved-across-display suppress explicit reactivation without claiming control of OS Space selection.

**Gate 2 / Regression tests:** assert A→B→hide→show remains B despite mouse on A; initial presentation behavior unchanged; B unplug recovers visible frame; B remains connected across hide; screen-change callback does not thrash; viewport resize, fixed/per-App sizes, frame persistence, shell/source synchronization, pin/auto-hide, same-display focus behavior and fullscreen restoration are preserved. Focused tests first. Use the **actual workflow on this task branch** as the canonical XCTest gate. At control bootstrap this branch inherits main's single-process `.github/workflows/macos-ci.yml` (not the unmerged PR #195 A+B partition workflow). Do not silently import #195's CI partitions or claim its test evidence applies to this branch. If the branch's formal full suite fails, classify the failure against the exact inherited baseline and STOP rather than skipping tests; if upstream merges materially change the CI contract, reconcile before further execution. Run arm64 Debug/Release and architecture/package checks proportional to high-risk Panel/focus changes. No pointless performance probes.

   **Current diagnostic-compatibility corrective:** preserve the legacy integer `previous_display_id` diagnostics while treating the captured `NSScreen.main` value strictly as a diagnostic observation. The newly added failure and affected Panel/ScreenPositioning/ExternalShell/Fullscreen suites are the bounded verification for this corrective. The previously observed 13 exact-base single-process failures remain the canonical gate blocker; do not rerun baseline diagnosis, skip tests, or import PR #195's workflow. The user-authorized corrective below permits its focused suites and conditional local Debug/Release arm64 builds and QA DMG. The canonical full suite, CI, and remote delivery remain deferred until PR #195 completes its normal acceptance and merges; then safely coordinate with current `main` and execute the contract current at that time.

**Gate 3 / Delivery and acceptance:** fresh exact-diff ownership/data-safety review, commit/push only this task's authorized branch after new refs and writer checks, verify delivered ref, run literal-head CI and QA DMG where applicable. Keep Draft/unmerged until user tests A→B→hide→reopen, cross-display prior-app behavior, click-outside, global hotkey, display detach and ordinary fullscreen/restore. The prior local build's `HUMAN_UI_ACCEPTANCE=FAIL`; the corrected-build retest remains pending until explicit user verdict.

## Prior canonical execution evidence — 2026-11-04

- Focused Panel/ScreenPositioning/ExternalShell/Fullscreen suites passed `161/161` on arm64.
- Canonical single-process XCTest on the task branch completed `1,153 passed / 14 failed` (`1,167` total).
- Exact inherited baseline `main@2a52800f770266f7c901eb612a0b319ddca142df` completed `1,144 passed / 13 failed` (`1,157` total). The same 13 failures reproduced on both runs; the branch adds one failure in `WebAttentionCrossFeatureTests.testCompletedPresentationTraceIsClearedBeforeIndependentDismissTrace` because the corrective removed `previous_display_id` from restore request/result diagnostics.
- The branch introduced one additional diagnostic compatibility failure on top of the exact-base 13. The user then authorized a narrow corrective and deferred the canonical gate until PR #195 is accepted and merged.

## Current diagnostic corrective — 2026-11-04

- Restored `PreviousApplicationContext.displayID` solely for diagnostics and restored integer `display_id` / `previous_display_id` fields on the legacy capture, skipped, requested and request-result events. No focus or positioning decision reads that value.
- `WebAttentionCrossFeatureTests.testCompletedPresentationTraceIsClearedBeforeIndependentDismissTrace`: passed, 1/1.
- Panel / ScreenPositioning / ExternalShell / Fullscreen focused suites: passed, 161/161.
- No full XCTest, Debug/Release build, CI, commit/push or QA DMG was run for this narrow corrective. Prior full and exact-base xcresults remain preserved; no baseline rerun was performed.
- PR #195 remains a separate OPEN / DRAFT dependency. After its normal acceptance and merge, refresh current `main`, reconcile safely, then run the canonical formal gates before delivery.

## User-authorized Pinned hide/focus corrective — 2026-11-04

The user reported that the prior local build failed manual acceptance: after moving a Pinned panel from display A to B and directly hiding it, macOS returned frontmost focus or the visible Space to A. The actual system selection point remains unisolated: the observed production order is shell `panel.orderOut(nil)`, safe source-window `orderOutIfSafe()`, then `NSApp.deactivate()`, followed by optional explicit previous-app activation. Do not attribute the result specifically to either order-out call or deactivation without runtime evidence.

This continuation authorizes a bounded `PanelController` hide/focus policy and focused regressions:

- Explicit hide, Pinned, and observed A→B movement during this visible presentation: do not request `NSApp.deactivate()` and do not explicitly activate the captured previous app. Still order out both shell and source windows, cancel pending presentation-focus work, and verify neither hidden window remains key.
- Pinned same-display hide and unpinned same-display hide: preserve current deactivation and safe previous-app restore behavior.
- Unpinned outside-click/application-activation auto-hide: preserve external-app focus ownership.
- Missing previous-app context: apply the same bounded deactivate decision without inventing or activating another app.
- Fullscreen/session-locked dismissal: preserve the existing guarded path.
- Fast hide/show: an old focus generation must not key or focus a window after dismissal; the next explicit show remains functional.

Do not make focus policy depend on `previous_display_id`/`NSScreen.main`; those values remain diagnostic observations. Do not introduce a second writer, focus framework, private API, simulated click, Finder activation, position-policy change, or source-host mutation.

Run the affected Panel/Focus/ScreenPositioning/ExternalShell/Fullscreen suites and diagnostic compatibility test. If they pass, run `git diff --check`, Debug arm64, and Release arm64. Produce a local QA DMG with exact source/ref/diff provenance only if all these gates pass and code/tests show both hidden windows are not key. These are local corrective gates only: do not rerun the known full-suite baseline, skip or weaken official tests, import PR #195's workflow, run CI, commit, push, merge, or release. A QA DMG does not establish human acceptance; keep the corrected-build retest pending.

### Local corrective outcome — 2026-11-04

- Focused `ExternalShellTests`, `ScreenPositioningTests`, `WebFocusAdapterTests`, plus the diagnostic compatibility test: **166 passed / 0 failed** on arm64 macOS 26.6.2. Result bundle: `/tmp/FT-PANEL-CROSS-DISPLAY-001-FOCUS-CORRECTIVE-003-20261104.xcresult`.
- The hide/reopen test observed both shell and source windows hidden and not key after dismissal; a subsequent show made the shell visible again. The policy matrix covers Pinned cross-display, Pinned same-display, Unpinned same-display, and Unpinned cross-display decisions.
- Debug arm64 build: **PASS**. Release arm64 build: **PASS**; binary verified arm64-only. `git diff --check`: **PASS**.
- Local QA DMG: `/Users/ox_miles/Downloads/FloatTabs-Panel-Focus-QA-20261104-1558/FloatTabs-0.5.8.dmg`; `hdiutil verify` and strict ad-hoc signature verification passed. Embedded source is HEAD `a42df8b46d6d9116151efce80d540fc4da732488`, tree `dirty`, exact flag `false`. Adjacent provenance file records the branch, local diff hashes and gate results.
- Cross-display runtime behavior is **not yet verified**. The prior user-reported return-to-A failure remains the last human result; the corrected-build two-display retest is pending. Causal attribution between ordering out the windows and AppKit deactivation remains unknown.
- No canonical full XCTest, CI, commit, push, merge, or release was run. PR #196 remains Draft at remote head `a42df8b`; PR #195 remains a separate Draft and was not modified.

## Global-hotkey visibility corrective 004 outcome — 2026-11-04

- `toggleOrPresentFloatTabs()` now hides on the first shortcut press whenever the shell is visible, regardless of Pinned or Key Window state. When hidden, it calls the normal presentation route and starts the existing native/WebView Focus Handshake.
- `shouldHideForGlobalShortcut()` now takes only shell visibility. The updated predicate and integration tests cover both Pinned and Unpinned hide/show cycles, hidden shell/source windows, cleared pending focus state on hide, and focus-handshake start on show.
- The existing `hideFloatTabs()` fullscreen/session-locked guard and cross-display focus-release policy are unchanged. The prior cross-display location correction remains in this worktree.
- Focused `ExternalShellTests`, `ScreenPositioningTests`, `WebFocusAdapterTests`, plus `WebAttentionCrossFeatureTests.testCompletedPresentationTraceIsClearedBeforeIndependentDismissTrace`: **166 passed / 0 failed** on arm64 macOS 26.6.2. Result bundle: `/tmp/FT-PANEL-CROSS-DISPLAY-001-HOTKEY-CORRECTIVE-004-20261104.xcresult`.
- Debug arm64 build: **PASS**. Release arm64 build: **PASS**, binary verified arm64-only. `git diff --check`: **PASS**.
- New local QA DMG: `/Users/ox_miles/Downloads/FloatTabs-Hotkey-QA-20261104-1652/FloatTabs-0.5.8.dmg`; `hdiutil verify` and strict ad-hoc signature verification passed. Embedded source is HEAD `a42df8b46d6d9116151efce80d540fc4da732488`, tree `dirty`, exact flag `false`. DMG SHA-256: `3078b4df832034767d11786e8af5069f942a0dedb7ccfd8108794e1944e3dba3`. Provenance is adjacent to the DMG.
- Machine verification establishes code behavior and packaged source, not real two-display macOS acceptance. Human UI acceptance for this new build is **PENDING**; the prior reported failure remains the latest actual human result until the user retests.
- PR #196 remains OPEN / DRAFT at `a42df8b46d6d9116151efce80d540fc4da732488`; PR #195 remains unchanged, OPEN / DRAFT at `a9f07ca02df10d2ea3d0292d1afa5669d115da42`. No canonical full XCTest, CI, commit, push, merge, or release was run.

## User-authorized remote-review delivery — 2026-11-04

The user subsequently requested that the related task changes be pushed so the remote can inspect them. This explicitly supersedes the local-only/no-commit/no-push limit above for this delivery step:

- Commit the five task-owned tracked modifications currently in the PR #196 worktree (`CURRENT_STATUS.md`, `CURRENT_TASK.md`, `FloatTabs/Panel/PanelController.swift`, `FloatTabsTests/ExternalShellTests.swift`, `FloatTabsTests/ScreenPositioningTests.swift`) on the existing branch `codex/panel-cross-display-position-001`.
- Pre-push baseline was local HEAD = `origin/codex/panel-cross-display-position-001` = PR #196 head `a42df8b46d6d9116151efce80d540fc4da732488`; no staged or untracked work was present.
- Push this task commit to that existing branch for remote review/checks. Do not create or change branches/PRs, touch PR #195, merge, or release.
- The push may trigger the repository's normal PR workflows; do not rewrite workflow policy or skip any result. Preserve the canonical full-suite deferral and prior exact-base failures as documented above. Keep human UI acceptance PENDING.

### Remote-review delivery outcome

- Code/test/control commit `566cdfb7c73642ef3d9942ab642459476510ad75` (`fix: preserve panel display and toggle shortcut visibility`) was created and pushed to the existing branch.
- Push verification confirmed the remote branch and PR #196 head both resolved to that SHA. PR #196 remains OPEN / DRAFT / MERGEABLE; the repository reported `Build & Test (Apple Silicon arm64)` and `build-dmg` running on the pushed revision.
- PR #195 remains OPEN / DRAFT at `a9f07ca02df10d2ea3d0292d1afa5669d115da42` and was not modified. No merge or release occurred. Human UI acceptance remains PENDING.

## User-authorized Cross-Display Focus Ownership corrective 005 — 2026-11-04

The user reports that manual acceptance failed on the preceding build: with FloatTabs opened on A, pinned, moved to B, then hidden without activating another B application, macOS returned to A. This is the latest human result (`FAIL`); no machine test or earlier build changes that result. The failure path remains causally unisolated.

Gate 0 refresh on this continuation:

- Local branch and PR #196 head are `codex/panel-cross-display-position-001` at `53be4d8151b6b2bf68ab03b97acf869b390c0ace`; worktree is clean before corrective edits. The remote branch matches.
- PR #196 is OPEN / DRAFT / MERGEABLE against `main@2a52800f770266f7c901eb612a0b319ddca142df`. `Build & Test (Apple Silicon arm64)` and `build-dmg` both completed successfully on this exact head.
- PR #195 remains OPEN / DRAFT at `a9f07ca02df10d2ea3d0292d1afa5669d115da42`. Its separate checkout contains pre-existing unique dirty work and must remain untouched.
- Existing hide diagnostics record a focus decision only after both order-out calls. They do not record the foreground PID and Shell/Source key/display states before hide or after each order-out, so they cannot identify whether the system's focus choice followed an explicit application action or window hiding.

This continuation stays within `FT-PANEL-CROSS-DISPLAY-001` and PR #196. Preserve the existing position, fullscreen, hotkey, and hide-focus corrections. The bounded correction is:

- Snapshot FloatTabs active state, `NSWorkspace` frontmost PID, Shell/Source Key Window state, Pinned state, and Shell/Source display observations before hiding.
- Permit explicit app deactivation or previous-app activation only when FloatTabs still owns the foreground as required by the decision and display evidence is sufficient. A hidden app must not reactivate its stale captured app or deactivate itself. A saved previous-app context must not override a currently selected foreground app.
- Track the initial Shell display for each presentation, its actual current display from the Shell frame, explicit cross-display movement, and connected-display membership. Unknown display evidence is not same-display evidence. Reopening on B and hiding again without moving starts a fresh B→B comparison.
- Calculate the focus decision before either window is ordered out. Keep `PanelController` the sole focus-policy writer; preserve task cancellation, window synchronization, fullscreen/session-lock protections, and auto-hide focus ownership.
- Use existing Diagnostics first, then add only the five bounded hide-stage snapshots needed to correlate foreground, key-window, display, decision, and Space-change observations. Do not infer causality from event proximity. If all explicit focus requests are skipped and macOS still chooses A, stop changing release policy.
- Add focused regression coverage in `ExternalShellTests.swift` and, where needed, `ScreenPositioningTests.swift` for cross-display, reopened-on-B/no-move, other-app-foreground, same-display, ordinary hide, hidden-window key state, one-press hotkey, and fullscreen protection.
- Do not change WebView lifecycle, Browser Profiles, cookies, sessions, persistence formats, private APIs, synthetic clicks, or unrelated tests/files.

After affected XCTest, arm64 Debug/Release, and diff audit pass, commit and push the corrective to this existing PR #196 branch, verify the literal remote head, and run its required macOS CI and QA DMG workflow. Keep PR #196 Draft and do not merge or release. Human UI acceptance remains PENDING until the user separately retests Scenario A (no other-app activation on B) and Scenario B (activate another B app before hide); the prior reported result remains FAIL until then.

### Corrective 005 local machine outcome — 2026-11-04

- `ExternalShellTests`, `ScreenPositioningTests`, and `FullscreenRestoreCompletionTests`: **144 passed, 0 failed** on the local Apple Silicon arm64 Mac. Result bundle: `/tmp/FT-PANEL-CROSS-DISPLAY-001-FOCUS-OWNERSHIP-005-03.xcresult`.
- Explicit macOS arm64 Debug and Release builds: **PASS**. Release app executable architecture: `arm64` only.
- `git diff --check`: **PASS**. No full canonical XCTest run was performed; its existing baseline gate remains deferred pending PR #195's separate acceptance and merge.
- PR #196 start-head checks on `53be4d8151b6b2bf68ab03b97acf869b390c0ace`: arm64 CI **PASS**, QA DMG workflow **PASS**. Corrective 005 has not yet been pushed, so literal corrective-head checks are pending.
- Local QA DMG for corrective 005 has not yet been built. Human UI acceptance is **PENDING** for both user-owned scenarios; the prior build's reported result remains **FAIL**. Runtime root cause remains **UNKNOWN**.

## STOP

- position policy silently changes Browser Profiles, WKWebView/session lifecycle, notification or URL restore;
- independent source window gets a second canonical frame writer;
- old previous-app activation causes known cross-display hijack after patch;
- a hidden shell or source window retains keyboard focus, a stale focus task reactivates either window, or public AppKit behavior cannot meet the focus-safety condition;
- unknown dirty/unique work, stale or contradictory task refs, non-fast-forward, canonical required CI or focused regression failure;
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
