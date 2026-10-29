# FloatTabs Current Status

**Status date:** 2026-10-29
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: SPEECH RETIREMENT ACCEPTED / JSC INCIDENT SEPARATED / PRE-MERGE RECHECK**

Current task: `FT-SPEECH-RETIRE-001` — WP1-WP6 acceptance is complete. Post-acceptance soak reproduced the pre-existing JavaScriptCore WebContent crash family, so incident repair is explicitly separated from the Speech-retirement task rather than broadening PR #160 into an unrelated runtime fix.

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

Speech/TTS retirement remains accepted as a product/runtime simplification. The post-retirement crash does not make the retirement task fail. Native evidence now proves the crash belongs to the same historical JavaScriptCore crash family that existed before Speech retirement.

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

The runtime logs record seven distinct ChatGPT WebContent terminations in the same post-retirement soak session:

```text
2026-10-29T06:22:17Z  slot B3328965  inactive  incident F7870DA5  recovery deferred
2026-10-29T06:45:52Z  slot 8D649ABB  inactive  incident 4A6CD7F1  reload_now
2026-10-29T08:15:43Z  slot 1FA8BE8B  active    incident A3D1F0E5  reload_now
2026-10-29T08:35:23Z  slot B3328965  inactive  incident EA263B85  recovery deferred
2026-10-29T09:25:13Z  slot 1FA8BE8B  inactive  incident 0E094547  reload_now
2026-10-29T11:20:11Z  slot B3328965  inactive  warm  generating  attention-protected  recovered healthy
2026-10-29T11:20:59Z  slot 1FA8BE8B  inactive  hot   generating  attention-protected  recovered healthy
```

Air macOS Unified Log evidence correlates all seven runtime events. WebKit reports the system-level termination reason as `Crash` for each correlated WebContent process.

Across all seven runtime-recorded crashes:

```text
CHATGPT_GENERATING_AT_TERMINATION=7/7
ATTENTION_PROTECTED_AT_TERMINATION=7/7
ACTIVE_SLOT_TERMINATION_COUNT=1
INACTIVE_SLOT_TERMINATION_COUNT=6
HOT_AND_WARM_RESIDENCY_BOTH_REPRODUCE=YES
ALL_RUNTIME_RECORDED_TERMINATIONS_RECOVERED=YES
SYSTEM_CONFIRMED_REASON_CRASH_COUNT=7
```

This correlation does not prove that ChatGPT generation or Attention causes the native crash. It does establish that inactive-slot release/residency alone does not explain the failures.

## Exact post-retirement native crash classification

A new native report was successfully persisted for the `19:20:11` local crash:

```text
FILE=com.apple.WebKit.WebContent-2026-10-29-192012.ips
SHA256=d37e0ddba2233ccb60c61fa21070420435b3736a81e9db5d03f19866e199ee6d
INCIDENT_ID=788084DA-0DAB-4EF4-80BE-5A22E47EF6DF
PID=12848
TIMESTAMP=2026-10-29 19:20:12 +0800
```

The report classifies the failure as:

```text
EXCEPTION=EXC_BAD_ACCESS
SIGNAL=SIGSEGV
SUBTYPE=KERN_INVALID_ADDRESS at 0x0000000000000048
TERMINATION=SIGNAL / Segmentation fault: 11
FAULT_ADDRESS=0x48
FAULTING_THREAD=main thread
```

The JavaScriptCore image is exactly the same binary as the historical 2026-10-25 and 2026-10-28 reports:

```text
JSC_VERSION=22625.1.29.11.28
JSC_UUID=798e8d5d-b1a1-3ab1-89c7-8329cb6c0d15
JSC_BASE=7210815488
OS=macOS 27.0.1 (26A434)
```

Most importantly, all three reports fault at the exact same native program counter in that same JSC binary:

```text
FAULT_PC=7221987548
IMAGE_OFFSET=11172060
SYMBOL=llint_entry_osr_function_for_call
SYMBOL_LOCATION=120
FAR=72 / 0x48
```

The new report also repeats the same higher-level async/microtask path:

```text
llint_entry_osr_function_for_call
llint_function_for_call_prologue
JSC::asyncGeneratorUnwrapYieldResumption(...)
JSC::asyncGeneratorNext(...)
JSC::runInternalMicrotask(...)
JSC::MicrotaskQueue::drainWithoutUseCallOnEachMicrotask(...)
WebCore::MicrotaskQueue::performMicrotaskCheckpoint(...)
WebCore::EventLoop::run(...)
```

The 2026-10-25 and 2026-10-28 reports share the same exact fault PC and `asyncGeneratorUnwrapYieldResumption` frame, but their lower async continuation uses `asyncIteratorNextWithDriver` / `llint_slow_path_async_iterator_next_with_driver` before reaching the microtask queue. The 2026-10-29 report instead uses `asyncGeneratorNext` on that lower portion of the path.

Therefore the evidence supports:

```text
SAME_HISTORICAL_JSC_CRASH_FAMILY=YES
SAME_EXACT_JSC_FAULT_SITE=YES
LOWER_ASYNC_CONTINUATION_VARIANT=YES
EXACT_TRIGGER=UNKNOWN
ROOT_CAUSE=UNKNOWN
```

This is stronger than a generic similarity claim: the post-retirement crash reaches the same crashing instruction in the same JavaScriptCore binary with the same near-null fault address as the pre-retirement historical crashes.

## Memory-pressure correlation

The narrow `19:18 .. 19:23` Unified Log window shows substantial WebContent memory pressure around the final two crashes. PID `12848` reached about `1639 MB` and received `system vm pressure critical: 1` before its crash. PID `17992` also received repeated critical pressure and later reached about `2209 MB` footprint before the second crash.

Memory pressure is therefore a supported co-occurring condition and may be an amplifier or trigger condition worth testing. It is not established as root cause. The persisted native report proves the first final-pair failure is a JavaScriptCore `EXC_BAD_ACCESS / SIGSEGV` at `0x48`, not a Jetsam/memory-kill classification.

## Post-finish stall evidence

The earlier candidate at `2026-10-29T09:28:25Z` recovered to `healthy_current_runtime`. A separate later incident reached the diagnostic confirmation threshold:

```text
09:32:34Z  post_finish_stall_candidate / dual timeout #1
09:33:09Z  post_finish_stall_detected / confirmed / dual timeout #2
09:33:22Z  incident closed: superseded_navigation
```

Thus at least one post-retirement `POST_FINISH_RUNTIME_STALL` was confirmed. Its closure by superseding navigation is a recovery boundary, not a root-cause explanation.

No Speech/TTS/synth runtime residue was found in the soak session.

## Current interpretation

```text
SPEECH_RETIREMENT_ACCEPTANCE=PASS
POST_RETIREMENT_WEBCONTENT_CRASH_REPRODUCED=YES
POST_RETIREMENT_RUNTIME_TERMINATION_COUNT=7
SYSTEM_CONFIRMED_REASON_CRASH_COUNT=7
POST_RETIREMENT_NATIVE_IPS_AUDITED=YES
SAME_HISTORICAL_JSC_CRASH_FAMILY=YES
SAME_EXACT_JSC_FAULT_SITE=YES
FAULT=EXC_BAD_ACCESS / SIGSEGV / KERN_INVALID_ADDRESS 0x48
FAULT_SYMBOL=llint_entry_osr_function_for_call+120
MEMORY_PRESSURE_CORRELATION=SUPPORTED_NOT_ROOT_CAUSE
CONFIRMED_POST_FINISH_STALL=YES
SPEECH_CAUSALITY_SUPPORTED=NO
JSC_EXACT_TRIGGER=UNKNOWN
JSC_ROOT_CAUSE=UNKNOWN
PR160_INCIDENT_REPAIR_SCOPE=SEPARATED
MERGE_READINESS=REQUIRES_FINAL_LITERAL_HEAD_GATE_RECHECK
RELEASE=NOT_AUTHORIZED
```

## Current decision

Do not broaden PR #160 into JSC/WebContent incident repair. The Speech-retirement implementation and acceptance remain valid, and the reproduced crash is now proven to be the same historical JSC family that predates retirement. The prior incident-based merge hold is therefore replaced by a normal final literal-head merge-readiness recheck for PR #160.

Any new investigation or production change aimed at the JSC crash must be authorized as a separate incident task. The next incident hypothesis should remain evidence-driven and should distinguish at least: JavaScriptCore async-generator/microtask execution, ChatGPT active generation, long-lived WebContent state, and memory-pressure amplification. No root-cause fix is authorized from the current evidence alone.