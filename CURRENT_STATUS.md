# FloatTabs Current Status

**Status date:** 2026-11-04  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode and current authorization

**MODE: CHATGPT COLD RESTORE MECHANISM — LOCAL IMPLEMENTATION PENDING**

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
CHATGPT_URL_RESTORE_SOURCE_CHANGE=NOT_STARTED
CHATGPT_URL_RESTORE_MACHINE_GATE=NOT_RUN
CHATGPT_URL_RESTORE_HUMAN_ACCEPTANCE=PENDING
WP3_SCHEDULING=NOT_STARTED
WP4_INTEGRATION=NOT_STARTED
PR_195_MERGE_READY=NO
RELEASE_READY=NO
```

These are point-in-time pre-implementation identities, not permanent HEAD equality locks. Prior WP2 CI/test and smoke evidence remains relevant to the unchanged policy but does not verify the new ChatGPT URL restore.

## Focused read-only source audit

- `WebViewPool.hibernate(slotID:)` currently captures opaque, memory-local interaction state before teardown; `webView(for:)` selects a compatible restore snapshot or loads `profile.currentURL ?? profile.homeURL`.
- `WebViewPool.createWebViewAfterBegin` currently applies compatible `interactionState` **instead** of initial URL load, while URL fallback uses `.useProtocolCachePolicy`.
- `SlotNavigationObserver` observes safe URL changes; `TabStore.updateCurrentURL` persists current URL. Reuse this exact existing route for conversation navigation identity.
- `SlotLifecycleCoordinator` owns hibernation policy and hard protections; no policy change. `PanelController` owns exact Runtime restore presentation/readiness; no gate change.
- Existing `WebViewPoolTests` cover generic hibernate snapshot, URL fallback, custom-profile isolation, runtime replacement, and navigation projection. Add ChatGPT-specific branch coverage, do not delete existing tests.
- Official ChatGPT web release notes dated 2026-08-21 confirm chunked long-conversation loading; this does not establish any deterministic cache budget or a guaranteed cold-restore speedup.

## Safety and acceptance

No Browser Profile/session/cookie/site-data clearing; no cache-policy changes; no fixed resident-count fallback; no WebKit private SPI; no DOM/page-message intervention; no new instrumentation/performance spike by default. User validates real-Mac exact conversation reopen and unchanged warm reuse after a QA build. No merge or release before applicable gates and explicit user decision.
