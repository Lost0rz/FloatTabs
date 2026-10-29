# FloatTabs Current Task

**Task ID:** `FT-JSC-RUNTIME-STABILITY-001`
**Title:** Reduce JSC/WebContent crash exposure and long-lived runtime pressure
**Status:** `ACTIVE / AUTHORIZED`
**Mode:** `EXECUTE`
**Task class:** `RUNTIME STABILITY / EVIDENCE-DRIVEN CORRECTIVE`
**Authorized baseline:** `main@26c81d83d3bdd771e98e355337b78622e2b25b17`
**Public baseline:** `v0.5.8` / Build `26`
**JSC root cause:** `UNKNOWN`

## Purpose

Use the now-confirmed WebContent crash evidence to make the smallest evidence-supported runtime optimization that reduces crash exposure and long-lived WebContent pressure, then produce a fresh QA DMG for real Air soak validation.

This task does not claim to fix Apple JavaScriptCore itself. Success means reducing FloatTabs-owned pressure/workload while preserving core product behavior and producing measurable runtime evidence.

## Verified incident signature

The post-Speech-retirement crash is the same historical JavaScriptCore family:

```text
EXCEPTION=EXC_BAD_ACCESS
SIGNAL=SIGSEGV
FAULT_ADDRESS=0x48
JSC_VERSION=22625.1.29.11.28
FAULT_SYMBOL=llint_entry_osr_function_for_call+120
FAULT_PC=7221987548
SAME_HISTORICAL_JSC_CRASH_FAMILY=YES
SAME_EXACT_JSC_FAULT_SITE=YES
```

Observed correlation from the accepted soak:

```text
SYSTEM_CONFIRMED_WEBCONTENT_CRASHES=7
CHATGPT_GENERATING_AT_CRASH=7/7
ATTENTION_PROTECTED_AT_CRASH=7/7
ACTIVE_SLOT_CRASHES=1
INACTIVE_SLOT_CRASHES=6
HOT_AND_WARM_BOTH_REPRODUCE=YES
MEMORY_PRESSURE_CORRELATION=SUPPORTED_NOT_ROOT_CAUSE
CONFIRMED_POST_FINISH_STALL=YES
JSC_EXACT_TRIGGER=UNKNOWN
JSC_ROOT_CAUSE=UNKNOWN
```

## Authorized work

### Gate 1 — bounded PRE_AUDIT

Before product mutation, map the current production path for:

- ChatGPT generation/status observation;
- Attention/Unread ownership and protection;
- cross-world liveness/probe cadence and other repeated JavaScript evaluation;
- page-app telemetry / observer workload;
- Slot residency and memory-pressure handling;
- WebContent termination/recovery and stall handling;
- tests covering those paths.

Quantify which FloatTabs-owned work continues during active/background generation and which work is product-essential versus diagnostic/optional.

### Gate 2 — smallest evidence-supported optimization

After PRE_AUDIT establishes a safe boundary, implement the smallest coherent optimization that materially reduces FloatTabs-owned WebContent pressure/workload. Prefer removing/reducing redundant work over adding recovery resets.

Candidate optimization classes are authorized only when supported by the audit:

1. reduce redundant JavaScript/DOM/probe/observer work while a ChatGPT Slot is generating;
2. coalesce or back off non-essential periodic work under elevated runtime pressure;
3. improve residency/memory-pressure response for non-active, non-generating, non-attention-protected Slots without deleting persistent website data;
4. improve diagnostics needed to compare pre/post optimization crash, stall and pressure behavior.

Do not combine multiple speculative mitigations if one bounded intervention can be validated independently.

### Gate 3 — verification and QA artifact

Required before handoff for Air soak:

- focused regression tests for touched runtime/Attention/residency paths;
- full required XCTest suite;
- required Debug/Release build gates;
- exact-head CI/QA DMG checks;
- no active regression in Attention/Unread, generation tracking, RemoteOrbit focus, background media, Browser Profiles or recovery;
- fresh QA DMG tied to exact source revision and hash;
- runtime diagnostics remain enabled for comparison during Air soak.

## Mandatory preserve boundary

```text
ChatGPT generation must continue normally
Attention / Unread / 有回复
Stable response identity / trusted interaction
Ready Alert sound
RemoteOrbit voice-input focus
Background media behavior
Normal Calibre browsing
Browser Profiles
Website cookies / sessions
Slot configuration
Persistence / backups / recovery data
All user data
```

Do not use deletion/reset/rebuild of Browser Profiles, cookies, sessions, Slot data, backups or user preferences as a recovery or optimization mechanism.

Do not use reload/restart/reset as evidence of root cause or as the primary optimization.

## Interpretation rules

```text
LOWER_CRASH_RATE != ROOT_CAUSE_PROVEN
NO_CRASH_DURING_BOUNDED_SOAK != FIX_PROVEN
MEMORY_PRESSURE_CORRELATION != MEMORY_ROOT_CAUSE
JSC_NATIVE_CRASH_SITE != FLOATTABS_SOURCE_LINE_PROVEN
```

Any new `.ips` matching the fixed signature should be classified as the same incident family unless contrary native evidence appears.

## STOP conditions

STOP and report evidence instead of broadening implementation if:

- the audit cannot establish a bounded FloatTabs-owned workload to optimize;
- the proposed change would interrupt ChatGPT generation or suppress required Attention/Unread behavior;
- the change requires destructive user-data/session/profile mutation;
- the only proposed mitigation is routine reload/reset/restart;
- the intervention requires changing WebView canonical ownership without a separate architecture decision;
- tests/builds fail because of the optimization;
- new native evidence contradicts the current incident classification.

## Completion boundary

This task is ready for Air soak only when one bounded optimization is implemented, verified, delivered to the task PR, and a fresh QA DMG is produced.

Final receipt must distinguish:

```text
OPTIMIZATION_IMPLEMENTED=<what changed>
FLOATTABS_OWNED_RUNTIME_WORK_REDUCED=<evidence>
FULL_TEST_BUILD_GATE=<result>
CI_GATE=<result>
QA_DMG=<path/artifact identity>
JSC_ROOT_CAUSE=UNKNOWN unless separately proven
AIR_SOAK=READY | BLOCKED
```

Production release is not authorized by this task. The immediate product gate is QA DMG soak on the Air.
