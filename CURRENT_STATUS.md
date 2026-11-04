# FloatTabs Current Status

**Status date:** 2026-11-04  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode and current authorization

**MODE: CHATGPT COLD RESTORE MECHANISM — PATCH DELIVERED / EXACT-HEAD CI AND QA PENDING**

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
PR_195_CURRENT_HEAD_AFTER_DELIVERY=7ccdda8f188f097f52389600ce605cc90338a6cc
CHATGPT_URL_RESTORE_SOURCE_CHANGE=COMMITTED_AND_PUSHED
CHATGPT_URL_RESTORE_FOCUSED_TESTS=PASS_477_0_FAILED
CHATGPT_URL_RESTORE_MONOLITHIC_XCTEST=KNOWN_BASELINE_FAILURE_1153_PASSED_13_FAILED
CHATGPT_URL_RESTORE_CANONICAL_XCTEST=PASS_A1104_B62_COVERAGE_1166_NO_GAPS_OR_OVERLAPS
CHATGPT_URL_RESTORE_DEBUG_RELEASE_ARM64=PASS
CHATGPT_URL_RESTORE_PACKAGE_LOCK=UNCHANGED
CHATGPT_URL_RESTORE_MACHINE_GATE=LOCAL_CANONICAL_TESTS_AND_BUILDS_PASS_CI_PENDING
CHATGPT_URL_RESTORE_CI=NOT_RUN_WAITING_FOR_EXACT_HEAD_CI
CHATGPT_URL_RESTORE_QA_DMG=NOT_RUN_CI_PENDING
CHATGPT_URL_RESTORE_COMMIT_PUSH=PASS_7ccdda8f188f097f52389600ce605cc90338a6cc
CHATGPT_URL_RESTORE_DELIVERY_BLOCKER=CLEARED_AFTER_READ_ONLY_OWNERSHIP_AUDIT
CHATGPT_URL_RESTORE_HUMAN_ACCEPTANCE=PENDING
WP3_SCHEDULING=NOT_STARTED
WP4_INTEGRATION=NOT_STARTED
PR_195_MERGE_READY=NO
RELEASE_READY=NO
```

These are point-in-time pre-implementation identities, not permanent HEAD equality locks. Prior WP2 CI/test and smoke evidence remains relevant to the unchanged policy but does not verify the new ChatGPT URL restore.

The four-file local patch was committed as `7ccdda8f188f097f52389600ce605cc90338a6cc` and pushed to `codex/adaptive-lifecycle-wp2-policy`; GitHub confirms PR #195 points to this commit and remains Draft. Focused restore/WP1/WP2/notification suites passed (477/477). The official workflow's separate XCTest partitions passed: A 1,104/1,104 and B 62/62; their test identifiers are disjoint and cover all 1,166 current tests exactly once. The earlier monolithic run (1,153 passed / 13 failed) reproduced the same failures on the unmodified baseline, so it is recorded as a known baseline failure. Locked package resolution left `Package.resolved` unchanged; Debug and Release arm64 builds passed and the Release binary is arm64-only. A read-only ownership check found no active Codex task, terminal cwd, Git lock or relevant writer for the other worktree. Its four modified files and untracked fixture helper do not overlap these four patch paths and remain untouched. Exact-head CI and QA DMG remain pending. No human UI acceptance occurred.

## Focused read-only source audit

- `WebViewPool.hibernate(slotID:)` currently captures opaque, memory-local interaction state before teardown; `webView(for:)` selects a compatible restore snapshot or loads `profile.currentURL ?? profile.homeURL`.
- `WebViewPool.createWebViewAfterBegin` currently applies compatible `interactionState` **instead** of initial URL load, while URL fallback uses `.useProtocolCachePolicy`.
- `SlotNavigationObserver` observes safe URL changes; `TabStore.updateCurrentURL` persists current URL. Reuse this exact existing route for conversation navigation identity.
- `SlotLifecycleCoordinator` owns hibernation policy and hard protections; no policy change. `PanelController` owns exact Runtime restore presentation/readiness; no gate change.
- Existing `WebViewPoolTests` cover generic hibernate snapshot, URL fallback, custom-profile isolation, runtime replacement, and navigation projection. The new ChatGPT regression covers deep-URL cold restore, no interaction-state capture/apply, warm reuse, custom Profile continuity, and same-Profile sibling isolation.
- Official ChatGPT web release notes dated 2026-08-21 confirm chunked long-conversation loading; this does not establish any deterministic cache budget or a guaranteed cold-restore speedup.

## Safety and acceptance

No Browser Profile/session/cookie/site-data clearing; no cache-policy changes; no fixed resident-count fallback; no WebKit private SPI; no DOM/page-message intervention; no new instrumentation/performance spike by default. User validates real-Mac exact conversation reopen and unchanged warm reuse after a QA build. No merge or release before applicable gates and explicit user decision.
