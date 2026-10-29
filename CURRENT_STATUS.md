# FloatTabs Current Status

**Status date:** 2026-10-29
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: POST-RETIREMENT SOAK INCIDENT / MERGE HOLD**

Current task: `FT-SPEECH-RETIRE-001` — WP1-WP6 acceptance is complete, but PR lifecycle closeout is intentionally held because post-acceptance soak produced repeated WebContent crashes and a confirmed post-finish stall.

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

Speech/TTS retirement remains accepted as a product/runtime simplification. Post-retirement crashes do not make the retirement task fail, but they prove that removing Speech/TTS did not eliminate the broader WebContent runtime failure family.

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

## Post-acceptance soak identity

The retired-Speech soak runtime is identified by:

```text
SOURCE_REVISION=2b1701a3f84e1e808939a03035dcebabfbbc4200
SOURCE_REVISION_EXACT=true
QA_LABEL=release
SESSION_ID=45E2C8A2-8325-4A0B-A098-B0243E8690F5
APP_LAUNCH=2026-10-29T06:16:11Z
```

## Repeated WebContent crash evidence

The first uploaded runtime slice recorded five distinct ChatGPT WebContent terminations:

```text
2026-10-29T06:22:17Z  slot B3328965  inactive  incident F7870DA5  recovery deferred
2026-10-29T06:45:52Z  slot 8D649ABB  inactive  incident 4A6CD7F1  reload_now
2026-10-29T08:15:43Z  slot 1FA8BE8B  active    incident A3D1F0E5  reload_now
2026-10-29T08:35:23Z  slot B3328965  inactive  incident EA263B85  recovery deferred
2026-10-29T09:25:13Z  slot 1FA8BE8B  inactive  incident 0E094547  reload_now
```

The Air evidence bundle then supplied matching macOS Unified Log evidence for all five timestamps. For each event WebKit reported:

```text
WebProcessProxy::didClose: (web process 0 crash)
WebProcessProxy::processDidTerminateOrFailedToLaunch: reason=Crash
WebPageProxy::processDidTerminate: reason=Crash
```

The matching WebContent PIDs were:

```text
14:22:17 local  PID 3307
14:45:52 local  PID 3314
16:15:43 local  PID 3312
16:35:23 local  PID 10744
17:25:13 local  PID 11674
```

ReportCrash started for each crash and attempted a type-309 WebContent report. However, each report creation failed with:

```text
client log create type 309 result FAILED: Log limit exceeded
```

Therefore no new native `.ips` was persisted for these five post-retirement crashes. The evidence bundle contains two older WebContent `.ips` files only, with embedded timestamps `2026-10-25 20:55:34 +0800` and `2026-10-28 12:03:16 +0800`; both are historical `EXC_BAD_ACCESS / SIGSEGV / KERN_INVALID_ADDRESS 0x48` crashes with JavaScriptCore frames including `llint_entry_osr_function_for_call`, async generator/iterator handling and microtask execution. Those old reports establish the historical crash family but cannot be transferred to the new crash identities.

The continuation runtime log adds two more WebContent terminations in the same soak session:

```text
2026-10-29T11:20:11Z  slot B3328965  inactive  warm  generating  attention-protected  recovered healthy
2026-10-29T11:20:59Z  slot 1FA8BE8B  inactive  hot   generating  attention-protected  recovered healthy
```

The captured Unified Log window ended before these two later crashes, so native/system correlation for them is still pending.

Across all seven runtime-recorded terminations:

```text
CHATGPT_GENERATING_AT_TERMINATION=7/7
ATTENTION_PROTECTED_AT_TERMINATION=7/7
ACTIVE_SLOT_TERMINATION_COUNT=1
INACTIVE_SLOT_TERMINATION_COUNT=6
HOT_AND_WARM_RESIDENCY_BOTH_REPRODUCE=YES
ALL_RUNTIME_RECORDED_TERMINATIONS_RECOVERED=YES
```

This correlation does not prove that ChatGPT generation or Attention causes the native crash. It does establish that inactive-slot release/residency alone does not explain the failures and that the repeated crash family remains present after Speech retirement.

One system memory-pressure warning was recorded at `2026-10-29T09:17:10Z`; it occurs only after the first four crashes and therefore cannot explain the series as a whole.

## Post-finish stall evidence

The previously unresolved candidate at `2026-10-29T09:28:25Z` is resolved by the continuation log:

```text
09:28:25Z  candidate / dual timeout #1
09:28:56Z  both worlds responsive again
09:28:56Z  incident closed: healthy_current_runtime
```

A separate later incident then reproduced on the same Slot/runtime:

```text
09:32:34Z  post_finish_stall_candidate / dual timeout #1
09:33:09Z  post_finish_stall_detected / confirmed / dual timeout #2
09:33:22Z  incident closed: superseded_navigation
```

Thus at least one post-retirement `POST_FINISH_RUNTIME_STALL` reached the diagnostic confirmation threshold. Its closure by superseding navigation is a recovery/ownership boundary, not a root-cause explanation.

No Speech/TTS/synth runtime residue was found in the soak session.

## Current interpretation

```text
SPEECH_RETIREMENT_ACCEPTANCE=PASS
POST_RETIREMENT_WEBCONTENT_CRASH_REPRODUCED=YES
POST_RETIREMENT_RUNTIME_TERMINATION_COUNT=7
SYSTEM_CONFIRMED_REASON_CRASH_COUNT=5
LATER_RUNTIME_ONLY_TERMINATION_COUNT=2
REPORTCRASH_TYPE_309_ATTEMPTED=5/5
NEW_IPS_PERSISTED=NO_LOG_LIMIT_EXCEEDED
HISTORICAL_JSC_SIGSEGV_REPORTS_PRESENT=YES
NEW_CRASH_NATIVE_STACK=UNAVAILABLE
SAME_JSC_CRASH_FAMILY=UNKNOWN
CONFIRMED_POST_FINISH_STALL=YES
JSC_ROOT_CAUSE=UNKNOWN
MERGE_READINESS=HOLD
RELEASE=NOT_AUTHORIZED
```

## Current decision

Keep PR #160 Draft/Open/Unmerged. Continue using the soak build only as an evidence source. The next bounded evidence step is to capture a narrow Air Unified Log window around the two later terminations at `2026-10-29T11:20:11Z` and `11:20:59Z` (19:20 local) and preserve future crash evidence before the OSAnalytics type-309 log quota prevents native report persistence again.

No production fix is authorized from this status alone. Do not infer a JavaScriptCore root-cause fix or exact crash-family identity without native stack evidence.