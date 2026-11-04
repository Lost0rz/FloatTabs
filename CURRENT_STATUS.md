# FloatTabs Current Status

**Status date:** 2026-11-04  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode and current authorization

**MODE: CHATGPT COLD RESTORE MECHANISM — CODE DELIVERED / CI AND QA PASS / HUMAN ACCEPTANCE PENDING**

Current task: `FT-ADAPTIVE-LIFECYCLE-RESTORE-001`, card `FT-ADAPTIVE-LIFECYCLE-RESTORE-001-CHATGPT-URL-RESTORE-002`. User-approved bounded mechanism-first change: on a **hibernated ChatGPT Runtime only**, prefer fresh navigation to the saved conversation URL instead of applying old `interactionState`; leave resident Runtime reuse, other-site interaction-state recovery, Browser Profiles and WebKit cache untouched.

Task authority and verification/STOP: `CURRENT_TASK.md`. Existing frozen WP2 lifecycle policy: `docs/architecture/FloatTabs_Runtime_Lifecycle_Policy_V7.md`. Existing WP1 presentation/readiness regression contract: `docs/architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md`.

## Fresh observed repository state

```text
MAIN=2a52800f770266f7c901eb612a0b319ddca142df
PR_195=OPEN_DRAFT_UNMERGED
PR_195_HEAD_BEFORE_CONTROL_TRANSITION=4a6153a4409b46f6d6b9682ce66275a8a7f754b8
PR_195_BRANCH=codex/adaptive-lifecycle-wp2-policy
WP1=MERGED_HUMAN_ACCEPTED
WP2_POLICY=IMPLEMENTED_UNCHANGED
WP2_PREVIOUS_CI_TEST_BOUNDARY=COMPLETE
WP2_HUMAN_SHORT_SMOKE=PASS_NO_VISIBLE_ISSUE
WP2_FIELD_OBSERVATION=PAUSED_BY_USER_NEW_RESTORE_SCOPE
PR_195_CURRENT_HEAD_AT_ATTEMPT=ade9914a4f7bd2e089ee22d32054641af9c33c5a
PR_195_CODE_PATCH_COMMIT=7ccdda8f188f097f52389600ce605cc90338a6cc
PR_195_CONTROL_DELIVERY_COMMIT=bb5adbd4bd170ae5873fc2909b1f8ee1bb7698c0
PR_195_FULL_CI_HEAD=bb5adbd4bd170ae5873fc2909b1f8ee1bb7698c0
PR_195_QA_DMG_HEAD=bb5adbd4bd170ae5873fc2909b1f8ee1bb7698c0
CHATGPT_URL_RESTORE_SOURCE_CHANGE=COMMITTED_AND_PUSHED
CHATGPT_URL_RESTORE_FOCUSED_TESTS=PASS_477_0_FAILED
CHATGPT_URL_RESTORE_MONOLITHIC_XCTEST=KNOWN_BASELINE_FAILURE_1153_PASSED_13_FAILED
CHATGPT_URL_RESTORE_CANONICAL_XCTEST=PASS_A1104_B62_COVERAGE_1166_NO_GAPS_OR_OVERLAPS
CHATGPT_URL_RESTORE_DEBUG_RELEASE_ARM64=PASS
CHATGPT_URL_RESTORE_PACKAGE_LOCK=UNCHANGED
CHATGPT_URL_RESTORE_MACHINE_GATE=PASS_FORMAL_CI_AND_QA_HUMAN_UI_PENDING
CHATGPT_URL_RESTORE_CI=PASS_RUN_41771005820_HEAD_bb5adbd_A1104_B62
CHATGPT_URL_RESTORE_QA_DMG=PASS_RUN_41771656563_HEAD_bb5adbd_ARTIFACT_13295447361
CHATGPT_URL_RESTORE_COMMIT_PUSH=PASS_CODE_7ccdda8_CONTROL_BB5adbd
CHATGPT_URL_RESTORE_DELIVERY_BLOCKER=CLEARED_AFTER_READ_ONLY_OWNERSHIP_AUDIT
CHATGPT_URL_RESTORE_HUMAN_ACCEPTANCE=PENDING
WP3_SCHEDULING=NOT_STARTED
WP4_INTEGRATION=NOT_STARTED
PR_195_MERGE_READY=NO
RELEASE_READY=NO
```

These are point-in-time pre-implementation identities, not permanent HEAD equality locks. Prior WP2 CI/test and smoke evidence remains relevant to the unchanged policy but does not verify the new ChatGPT URL restore.

The four-file code patch was committed as `7ccdda8f188f097f52389600ce605cc90338a6cc`; a control-only delivery update is at `bb5adbd4bd170ae5873fc2909b1f8ee1bb7698c0`. Exact-head full CI run `41771005820` passed on `bb5adbd`: self-hosted `macmini-floattabs-01` ARM64, Debug/Release builds, Release arm64-only check, and official Partition A 1,104/1,104 plus Partition B 62/62. QA DMG run `41771656563` passed on the same head; artifact `13295447361` contains the QA DMG and dSYM. Downloaded DMG and dSYM checksums matched, `hdiutil verify` passed, and the mounted app provenance reports revision `bb5adbd4bd170ae5873fc2909b1f8ee1bb7698c0`, `revision_exact=true`, `tree_state=clean`, Release, arm64, with a valid code signature. Focused restore/WP1/WP2/notification suites passed (477/477); the A+B identifiers are disjoint and cover all 1,166 tests once. The earlier monolithic run (1,153 passed / 13 failed) reproduced on the unmodified baseline and remains recorded as a known baseline failure with `ROOT_CAUSE=UNKNOWN`. The other worktree's changes remain untouched and non-overlapping. Human UI acceptance remains pending; PR #195 remains Draft.

## Focused read-only source audit

- `WebViewPool.hibernate(slotID:)` currently captures opaque, memory-local interaction state before teardown; `webView(for:)` selects a compatible restore snapshot or loads `profile.currentURL ?? profile.homeURL`.
- `WebViewPool.createWebViewAfterBegin` currently applies compatible `interactionState` **instead** of initial URL load, while URL fallback uses `.useProtocolCachePolicy`.
- `SlotNavigationObserver` observes safe URL changes; `TabStore.updateCurrentURL` persists current URL. Reuse this exact existing route for conversation navigation identity.
- `SlotLifecycleCoordinator` owns hibernation policy and hard protections; no policy change. `PanelController` owns exact Runtime restore presentation/readiness; no gate change.
- Existing `WebViewPoolTests` cover generic hibernate snapshot, URL fallback, custom-profile isolation, runtime replacement, and navigation projection. The new ChatGPT regression covers deep-URL cold restore, no interaction-state capture/apply, warm reuse, custom Profile continuity, and same-Profile sibling isolation.
- Official ChatGPT web release notes dated 2026-08-21 confirm chunked long-conversation loading; this does not establish any deterministic cache budget or a guaranteed cold-restore speedup.

## Safety and acceptance

No Browser Profile/session/cookie/site-data clearing; no cache-policy changes; no fixed resident-count fallback; no WebKit private SPI; no DOM/page-message intervention; no new instrumentation/performance spike by default. User validates real-Mac exact conversation reopen and unchanged warm reuse after a QA build. No merge or release before applicable gates and explicit user decision.
