# FloatTabs Current Status

**Status date:** 2026-10-19
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: ACTIVE_DIAGNOSTIC_TASK**

Active task: `FT-DIAG-POST-FINISH-STALL-001` on `codex/ft-post-finish-stall-diag-001`.

## Baseline

- Task branch was created from protected `main@3511297d5f573598556739519bae859322578768`.
- Latest public release remains `v0.5.4` / Build 22.
- The fresh incident logs under review came from clean Release source revision `439590659a42d52abd985c323dee4e1e0fbe9b47`.
- Previous lifecycle-sync task `FT-LIFECYCLE-SYNC-001` remains terminal; it grants no authority to this work.
- Browser Profiles, Slots, sessions/cookies/WebKit data, backups, preferences, diagnostics history, and installed app data are outside remote diagnostic implementation scope.

## Current incident evidence

The latest joint log/code audit has narrowed the failure to a post-navigation Web runtime boundary:

- A ChatGPT Slot can report `navigation_phase=finished`, `is_loading=false`, and progress `1` while bounded JavaScript evaluation stops responding.
- Normal page-world focus JavaScript and trusted interaction still succeeded shortly before the fresh 2026-10-19 stall.
- FloatTabs' Native host continued processing window, timeout, lifecycle, tab and reload events during the stall.
- No WebContent termination callback was emitted for that fresh stall.
- The memory-pressure warning arrived after the failed probe cycle had already begun; it is correlated evidence, not a proven trigger.
- A manual reload established a fresh admitted ChatGPT document epoch but the subsequent checkpoint could still time out; a later navigation on the same WKWebView recovered to sub-millisecond probes.
- Current Health and Page-App probes both execute in `FloatTabsChatGPTAttention` isolated world, so their simultaneous timeout does not yet distinguish an isolated-world failure from a broader WebContent/renderer stall.

## Current decision

```text
FAULT_BOUNDARY=POST_FINISH_WEB_RUNTIME_JS_EXECUTION
FAULT_BOUNDARY_CONFIDENCE=HIGH
INITIAL_CAUSAL_ROOT_CAUSE=UNKNOWN
MEMORY_PRESSURE_DIRECT_TRIGGER=NOT_PROVEN
NATIVE_HOST_STALL=NOT_SUPPORTED
NAVIGATION_STALL=NOT_SUPPORTED
FRESH_CONTENT_PROCESS_TERMINATION=NOT_OBSERVED
STALE_DOCUMENT_ONLY_FAILURE=NOT_SUPPORTED
NEXT_SAFE_ACTION=BOUNDED_DIAGNOSTIC_INSTRUMENTATION
```

## Authorized next work

The branch may add only the evidence required to distinguish:

1. main page-world JavaScript responsiveness;
2. FloatTabs isolated-world responsiveness;
3. finished-navigation post-finish stall classification;
4. bounded, truthful host/residency resource context;
5. WebContent termination epoch/count distinct from WKWebView identity.

No automatic recovery or product-policy change is authorized.

## Required next validation

1. Focused Web runtime / ChatGPT bridge / diagnostics tests on the exact diagnostic head.
2. Required Apple Silicon build/test CI.
3. Air real-Mac installation of the diagnostic build while preserving all Browser Profile/session data.
4. Normal-use fresh incident capture and Web-side joint audit.

```text
TASK_STATE=ACTIVE
BASE_MAIN=3511297d5f573598556739519bae859322578768
BRANCH=codex/ft-post-finish-stall-diag-001
PRODUCT_RECOVERY_CHANGE_AUTHORIZED=NO
USER_DATA_CHANGE_AUTHORIZED=NO
BROWSER_PROFILE_DATA_CHANGE_AUTHORIZED=NO
```
