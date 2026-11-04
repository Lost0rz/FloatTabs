# FloatTabs Current Status

**Observed date:** 2026-11-04  
**Repository:** `Lost0rz/FloatTabs`  
**Branch:** `codex/panel-cross-display-position-001`  
**Observed base:** `main@2a52800f770266f7c901eb612a0b319ddca142df` (provenance, not an immutable equality lock)

## Active scope

**ACTIVE TASK: `FT-PANEL-CROSS-DISPLAY-001` — CORRECTIVE 005 CODE COMMIT `a39b87a` PUSHED TO EXISTING PR #196. Exact-source macOS CI and QA DMG workflows PASS; local arm64 QA DMG is verified. Prior human A→B hide acceptance remains FAIL; corrected-build scenarios A and B remain PENDING. PR #195 remains separate and unchanged.**

Corrective 005 is committed and pushed to the existing PR #196 branch as `a39b87a91be60f70c40cf8b600f5b3b7725f6568`. The hide decision is computed before either window is ordered out; explicit deactivation and previous-app activation require FloatTabs to own the foreground, and pinned cross-display or unknown-display hides skip both. Display classification compares the presentation's initial Shell display with the final Shell frame against connected displays, so reopening on B starts a fresh B-to-B comparison. Focused ExternalShell, ScreenPositioning, and fullscreen restoration tests pass 144/144; local arm64 Debug/Release builds and `git diff --check` pass. Literal-source macOS CI passed Debug/Release, arm64 verification, 1,173 tests with 4 skipped and 0 failures; the literal-source QA DMG workflow also passed. A local, provenance-bound arm64 QA DMG is verified at `/Users/ox_miles/Downloads/FloatTabs-Focus-Ownership-QA-20261104-1800/FloatTabs-0.5.8.dmg`. Keep PR #196 Draft; do not merge/release, modify PR #195, or claim human acceptance. The prior manual result remains FAIL; corrected-build scenarios A and B remain PENDING, and runtime cause remains UNKNOWN.

User report: open FloatTabs on display A, manually drag its shell/Web host to display B, dismiss without clicking B's desktop, and observe unexpected movement/return toward A (either the window on subsequent presentation or the frontmost app/Space on dismissal). The product decision is to respect the last user-positioned connected display and avoid explicit cross-display previous-app reactivation. macOS deactivation can independently select another frontmost app; this is not fully controllable and must not be masked by synthetic Finder activation or fake clicks.

Latest user acceptance for the prior local build: **FAIL**. In the Pinned A→B→direct-hide scenario, macOS returned frontmost focus or the visible Space to A. The report does not isolate whether `orderOut()` or `NSApp.deactivate()` caused that selection. Corrective 005 retains the earlier position, hotkey, fullscreen, and hide-focus changes while fixing foreground ownership and per-presentation Shell display classification. Machine PASS results do not change this human result; the corrected build requires separate user retests for both foreground scenarios.

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
PRODUCT_SOURCE_MUTATION=DELIVERED_CODE_COMMIT_A39B87A
DIAGNOSTIC_COMPATIBILITY_TEST=PASS_1_OF_1_INCLUDED_IN_FOCUSED_RUN
FOCUSED_TESTS=PASS_144_OF_144_CORRECTIVE_005
CANONICAL_XCTEST=PASS_1173_EXECUTED_4_SKIPPED_0_FAILED_ON_A39B87A
BASELINE_XCTEST=FAIL_1144_PASS_13_FAIL_OF_1157_AT_2A52800F
BASELINE_SHARED_FAILURES=13_OF_13
INTRODUCED_FAILURE=WebAttentionCrossFeatureTests.testCompletedPresentationTraceIsClearedBeforeIndependentDismissTrace_FIXED_FOCUSED_TEST_PASS
CANONICAL_CI_BLOCKER=NONE_FOR_CORRECTIVE_005; FULL_LITERAL_SOURCE_WORKFLOW_PASS
STOP=WAITING_FOR_USER_HUMAN_UI_RETEST_SCENARIOS_A_AND_B
HOTKEY_CORRECTIVE_004=IMPLEMENTED; FOCUSED_TESTS_DEBUG_RELEASE_DIFF_AND_NEW_QA_DMG_PASS
HOTKEY_VISIBLE_PRESS=HIDE_REGARDLESS_OF_PIN_OR_KEY_STATE
HOTKEY_HIDDEN_PRESS=SHOW_AND_RUN_EXISTING_FOCUS_HANDSHAKE
HOTKEY_FULLSCREEN_SESSION_GUARD=PRESERVE_EXISTING_HIDE_SHOW_GUARDS
HOTKEY_CROSS_DISPLAY_FOCUS_POLICY=PRESERVE_EXISTING
HOTKEY_QA_DMG=/Users/ox_miles/Downloads/FloatTabs-Hotkey-QA-20261104-1652/FloatTabs-0.5.8.dmg; ARM64_ADHOC_VERIFIED_NOT_NOTARIZED
HOTKEY_HUMAN_UI_ACCEPTANCE=PENDING
DEBUG_RELEASE_BUILDS=PASS_ARM64_DEBUG_AND_RELEASE
CI=PASS_LITERAL_SOURCE_A39B87A; 1173_TESTS_4_SKIPPED_0_FAILED
QA_DMG=PASS_LOCAL_ARM64_ADHOC_NOT_NOTARIZED; PASS_LITERAL_SOURCE_WORKFLOW
HUMAN_UI_ACCEPTANCE=PRIOR_FOCUS_BUILD_FAILED; CORRECTIVE_004_AND_005_RETEST_PENDING
LATEST_HUMAN_UI_ACCEPTANCE=FAIL_PRIOR_BUILD; CORRECTIVE_005_RETEST_PENDING
NEW_TASK_MERGE_READY=NO
PR_195_HUMAN_UI_ACCEPTANCE=PENDING
PINNED_CROSS_DISPLAY_HIDE_CAUSE=NOT_ISOLATED; ORDER_OUT_AND_DEACTIVATE_SEQUENCE_CONFIRMED
PINNED_HIDE_FOCUS_CORRECTIVE_005=DELIVERED_AS_A39B87A; TWO_DISPLAY_RUNTIME_UNVERIFIED
LOCAL_FOCUSED_TESTS_AND_BUILDS=PASS_144_TESTS_DEBUG_RELEASE_ARM64; CORRECTIVE_005
LOCAL_QA_DMG=/Users/ox_miles/Downloads/FloatTabs-Focus-Ownership-QA-20261104-1800/FloatTabs-0.5.8.dmg
BUILD_PROVENANCE=/Users/ox_miles/Downloads/FloatTabs-Focus-Ownership-QA-20261104-1800/BUILD_PROVENANCE.md
REMOTE_DELIVERY=CODE_COMMIT_A39B87A_PUSHED_TO_EXISTING_PR_196; EXACT_SOURCE_CI_AND_QA_PASS; NO_MERGE_OR_RELEASE
FOCUS_OWNERSHIP_CORRECTIVE_005=IMPLEMENTED_AND_DELIVERED; TWO_DISPLAY_RUNTIME_UNVERIFIED
HIDE_DIAGNOSTIC_GAP=RESOLVED_WITH_STAGE_SNAPSHOTS; ORDEROUT_CAUSALITY_NOT_INFERRED
HUMAN_UI_ACCEPTANCE_CORRECTIVE_005=PENDING_USER_RETEST_SCENARIO_A_AND_B
PR_196=OPEN_DRAFT_MERGEABLE; CODE_HEAD_A39B87A
PR_195=OPEN_DRAFT_UNCHANGED; SEPARATE_CHECKOUT_HAS_PREEXISTING_DIRTY_UNIQUE_WORK
CORRECTIVE_005_FOCUSED_TESTS=PASS_144_OF_144_ARM64
CORRECTIVE_005_DEBUG_RELEASE=PASS_ARM64; RELEASE_BINARY_ARM64_ONLY
CORRECTIVE_005_DIFF_CHECK=PASS
CORRECTIVE_005_MACOS_CI=PASS_1173_TESTS_4_SKIPPED_0_FAILED; RUN_41813678039
CORRECTIVE_005_QA_DMG_WORKFLOW=PASS; RUN_41813678313
CORRECTIVE_005_LOCAL_QA_DMG=/Users/ox_miles/Downloads/FloatTabs-Focus-Ownership-QA-20261104-1800/FloatTabs-0.5.8.dmg
CORRECTIVE_005_LOCAL_QA_DMG_SHA256=845a2c21d8b94340b8c4c1317707aa20a4dbb34a91345a39398c0aae0ffdee34
```

Authority: `AGENTS.md`, `CURRENT_TASK.md`; documentation routes via `docs/README.md` and `docs/architecture/DOMAIN_MAP.md`. Product WebKit/runtime lifecycle, Browser Profiles and site/session data remain outside this task.
