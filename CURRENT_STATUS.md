# FloatTabs Current Status

**Observed date:** 2026-11-04  
**Repository:** `Lost0rz/FloatTabs`  
**Branch:** `codex/panel-cross-display-position-001`  
**Observed base:** `main@2a52800f770266f7c901eb612a0b319ddca142df` (provenance, not an immutable equality lock)

## Active scope

**ACTIVE TASK: `FT-PANEL-CROSS-DISPLAY-001` — PINNED HIDE-FOCUS CORRECTIVE RETAINED; HOTKEY VISIBILITY-TOGGLE CORRECTIVE 004 IMPLEMENTED. FOCUSED TESTS, DEBUG/RELEASE ARM64, AND NEW LOCAL QA DMG PASS; HUMAN ACCEPTANCE PENDING; CANONICAL GATE DEFERRED PENDING PR #195.**

The user authorized the next bounded corrective on the existing PR #196 worktree. Preserve the completed cross-display position/hide-focus work. Change `PanelController.toggleOrPresentFloatTabs()` so one global-shortcut press hides any visible shell regardless of Pinned or Key Window state; when hidden, show and run the existing presentation/WebView Focus Handshake. Update `shouldHideForGlobalShortcut()` and its `ExternalShellTests.swift` assertions to use visibility only. Keep fullscreen/session-locked guards and the existing cross-display focus-release policy. Run affected focused tests, Debug/Release arm64 builds, and diff checks; after all pass, produce a new local QA DMG with fresh provenance. The local-only delivery boundary was later superseded by the user's explicit authorization to commit and push this task to the existing PR #196 branch for remote verification. Do not merge/release, modify PR #195, create a task/branch/worktree, or claim human acceptance; it remains PENDING.

User report: open FloatTabs on display A, manually drag its shell/Web host to display B, dismiss without clicking B's desktop, and observe unexpected movement/return toward A (either the window on subsequent presentation or the frontmost app/Space on dismissal). The product decision is to respect the last user-positioned connected display and avoid explicit cross-display previous-app reactivation. macOS deactivation can independently select another frontmost app; this is not fully controllable and must not be masked by synthetic Finder activation or fake clicks.

Latest user acceptance for the prior local build: **FAIL**. In the Pinned A→B→direct-hide scenario, macOS returned frontmost focus or the visible Space to A. The report does not isolate whether `orderOut()` or `NSApp.deactivate()` caused that selection. This user-authorized continuation adds a bounded hide/focus corrective: for a Pinned panel moved across displays during the visible presentation, hide both owned windows without explicitly deactivating FloatTabs or reactivating the captured previous app; verify neither hidden window remains key and stale presentation focus work cannot reclaim focus. Same-display and auto-hide behavior remain regression gates. The corrective is now present locally; its cross-display release behavior still awaits the user's two-display retest.

Baseline source audit before the local corrective, at PR #195 head `a9f07ca02df10d2ea3d0292d1afa5669d115da42` (the bullets below describe the pre-corrective implementation):
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
PRODUCT_SOURCE_MUTATION=LOCAL_UNCOMMITTED
DIAGNOSTIC_COMPATIBILITY_TEST=PASS_1_OF_1_INCLUDED_IN_FOCUSED_RUN
FOCUSED_TESTS=PASS_166_OF_166
CANONICAL_XCTEST=NOT_RERUN_AFTER_NARROW_DIAGNOSTIC_CORRECTIVE
BASELINE_XCTEST=FAIL_1144_PASS_13_FAIL_OF_1157_AT_2A52800F
BASELINE_SHARED_FAILURES=13_OF_13
INTRODUCED_FAILURE=WebAttentionCrossFeatureTests.testCompletedPresentationTraceIsClearedBeforeIndependentDismissTrace_FIXED_FOCUSED_TEST_PASS
CANONICAL_CI_BLOCKER=DEFERRED_PENDING_PR_195_ACCEPTANCE_AND_MERGE; THEN_REFRESH_MAIN_AND_RUN_CURRENT_OFFICIAL_GATE
STOP=WAITING_FOR_PR_195_NORMAL_ACCEPTANCE_AND_MERGE_BEFORE_CANONICAL_GATE
HOTKEY_CORRECTIVE_004=IMPLEMENTED; FOCUSED_TESTS_DEBUG_RELEASE_DIFF_AND_NEW_QA_DMG_PASS
HOTKEY_VISIBLE_PRESS=HIDE_REGARDLESS_OF_PIN_OR_KEY_STATE
HOTKEY_HIDDEN_PRESS=SHOW_AND_RUN_EXISTING_FOCUS_HANDSHAKE
HOTKEY_FULLSCREEN_SESSION_GUARD=PRESERVE_EXISTING_HIDE_SHOW_GUARDS
HOTKEY_CROSS_DISPLAY_FOCUS_POLICY=PRESERVE_EXISTING
HOTKEY_QA_DMG=/Users/ox_miles/Downloads/FloatTabs-Hotkey-QA-20261104-1652/FloatTabs-0.5.8.dmg; ARM64_ADHOC_VERIFIED_NOT_NOTARIZED
HOTKEY_HUMAN_UI_ACCEPTANCE=PENDING
DEBUG_RELEASE_BUILDS=PASS_ARM64_DEBUG_AND_RELEASE
CI=DEFERRED
QA_DMG=PASS_LOCAL_ARM64_ADHOC_SIGNED_NOT_NOTARIZED
HUMAN_UI_ACCEPTANCE=PRIOR_FOCUS_BUILD_FAILED; HOTKEY_CORRECTIVE_004_BUILD_PENDING_USER_TEST
LATEST_HUMAN_UI_ACCEPTANCE=PRIOR_FOCUS_BUILD_FAILED; HOTKEY_CORRECTIVE_004_HUMAN_RESULT_PENDING
NEW_TASK_MERGE_READY=NO
PR_195_HUMAN_UI_ACCEPTANCE=PENDING
PINNED_CROSS_DISPLAY_HIDE_CAUSE=NOT_ISOLATED; ORDER_OUT_AND_DEACTIVATE_SEQUENCE_CONFIRMED
PINNED_HIDE_FOCUS_CORRECTIVE=IMPLEMENTED_LOCALLY; TWO_DISPLAY_RUNTIME_UNVERIFIED
LOCAL_FOCUSED_TESTS_AND_BUILDS=PASS_166_TESTS_DEBUG_RELEASE_ARM64; HOTKEY_CORRECTIVE_004
LOCAL_QA_DMG=/Users/ox_miles/Downloads/FloatTabs-Hotkey-QA-20261104-1652/FloatTabs-0.5.8.dmg
BUILD_PROVENANCE=/Users/ox_miles/Downloads/FloatTabs-Hotkey-QA-20261104-1652/BUILD_PROVENANCE.md
REMOTE_DELIVERY=USER_AUTHORIZED_COMMIT_AND_PUSH_PENDING; EXISTING_PR_196_BRANCH; NO_MERGE_OR_RELEASE
```

Authority: `AGENTS.md`, `CURRENT_TASK.md`; documentation routes via `docs/README.md` and `docs/architecture/DOMAIN_MAP.md`. Product WebKit/runtime lifecycle, Browser Profiles and site/session data remain outside this task.
