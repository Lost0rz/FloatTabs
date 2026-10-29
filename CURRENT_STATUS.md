# FloatTabs Current Status

**Status date:** 2026-10-29
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: POST-RETIREMENT SOAK INCIDENT / MERGE HOLD**

Current task: `FT-SPEECH-RETIRE-001` — WP1-WP6 acceptance is complete, but PR lifecycle closeout is intentionally held because post-acceptance soak produced new WebContent termination evidence.

## Verified baseline

```text
REMOTE_MAIN=fbdcdaa4e1d1dfa953cea6a9ee2078d4fce827e5
IMPLEMENTATION_BRANCH=codex/ft-speech-retire-001
WP5_SEMANTIC_HEAD=79668cf69aba2a179cf09e3f648732a103fc7929
PRE_SOAK_CONTROL_HEAD=36a64e951725bd30f79153f570cdc2560d6debba
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
IMPLEMENTATION_PR_160=OPEN / DRAFT / UNMERGED
JSC_ROOT_CAUSE=UNKNOWN
```

Speech/TTS retirement remains accepted as a product/runtime simplification. A post-retirement WebContent termination does not make the retirement task fail, and it does not prove or disprove the historical JavaScriptCore root cause.

## Work-package acceptance

```text
WP1=COMPLETE / POST_AUDIT PASS
WP2=COMPLETE / POST_AUDIT PASS
WP3=COMPLETE / POST_AUDIT PASS
WP4=COMPLETE / POST_AUDIT PASS
WP5=COMPLETE / POST_AUDIT PASS
WP6=COMPLETE / POST_AUDIT PASS
HUMAN_UI_ACCEPTANCE=PASS
REAL_RUNTIME_ACCEPTANCE=PASS
```

The bounded WP6 acceptance window (`2026-10-29T05:55:14Z .. 06:06:58Z`) had no crash/stall/termination/recovery event and no Speech/TTS runtime residue. Repository gates for the then-current control head passed (`macOS CI #1194`, `QA DMG #577`).

## Post-acceptance soak evidence

Uploaded runtime logs cover the older AB build and the retired-Speech soak build. The retired-Speech soak runtime is identified by:

```text
SOURCE_REVISION=2b1701a3f84e1e808939a03035dcebabfbbc4200
SOURCE_REVISION_EXACT=true
QA_LABEL=release
SESSION_ID=45E2C8A2-8325-4A0B-A098-B0243E8690F5
APP_LAUNCH=2026-10-29T06:16:11Z
```

Within that soak session, five distinct ChatGPT WebContent terminations were recorded:

```text
2026-10-29T06:22:17Z  slot B3328965  inactive  incident F7870DA5  recovery deferred
2026-10-29T06:45:52Z  slot 8D649ABB  inactive  incident 4A6CD7F1  reload_now
2026-10-29T08:15:43Z  slot 1FA8BE8B  active    incident A3D1F0E5  reload_now
2026-10-29T08:35:23Z  slot B3328965  inactive  incident EA263B85  recovery deferred
2026-10-29T09:25:13Z  slot 1FA8BE8B  inactive  incident 0E094547  reload_now
```

All five report `origin=https://chatgpt.com`; four occurred while the Slot was inactive and one while active. All five later reached `web_runtime.incident.closed` with `incident_outcome=healthy_current_runtime` after recovery.

One system memory-pressure warning was recorded at `2026-10-29T09:17:10Z`; it occurs only before the fifth termination and therefore does not explain the first four. WebContent resource attribution remains unavailable through the public API.

At the end of the uploaded log, the same soak session records an unresolved candidate only:

```text
2026-10-29T09:28:25Z
web_runtime.post_finish_stall_candidate
slot=1FA8BE8B
incident=E00F4B13-1C16-412E-9597-2BECE8059247
trigger=cross_world_dual_timeout
main_world_probe=timeout
isolated_world_probe=timeout
post_finish_dual_timeout_count=1
```

The uploaded file ends at that trigger, so confirmation/closure is not available. Treat it as `STALL_CANDIDATE`, not a confirmed stall.

No Speech/TTS/synth runtime match was found in the soak session.

## Current interpretation

```text
SPEECH_RETIREMENT_ACCEPTANCE=PASS
POST_RETIREMENT_WEBCONTENT_TERMINATION_REPRODUCED=YES
POST_RETIREMENT_TERMINATION_COUNT=5
ACTIVE_SLOT_TERMINATION_COUNT=1
INACTIVE_SLOT_TERMINATION_COUNT=4
ALL_RECORDED_TERMINATIONS_RECOVERED=YES
LATEST_STALL_CANDIDATE=UNRESOLVED_IN_UPLOADED_SLICE
JSC_ROOT_CAUSE=UNKNOWN
SAME_JSC_CRASH_FAMILY=UNKNOWN_UNTIL_NATIVE_IPS_EVIDENCE
MERGE_READINESS=HOLD
RELEASE=NOT_AUTHORIZED
```

The JSONL proves WebContent termination/recovery events but does not provide the native crash stack needed to classify them as the historical JavaScriptCore SIGSEGV family. Preserve matching macOS WebContent `.ips` reports, if produced, before making a root-cause/family claim.

## Current decision

Keep PR #160 Draft/Open/Unmerged. Continue using the soak build only as an evidence source; do not interpret successful auto-recovery as root-cause resolution. Next evidence gate is native crash-report correlation for the five termination timestamps plus a continuation log after the `09:28:25Z` stall candidate. No production fix is authorized from this status alone.
