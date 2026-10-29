# FloatTabs Current Status

**Status date:** 2026-10-30
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: JSC / WEBCONTENT RUNTIME STABILITY — OPTIMIZED AIR SOAK REPRODUCED / SYSTEM CRASH CONFIRMED**

Current task: `FT-JSC-RUNTIME-STABILITY-001` — `ACTIVE / AUTHORIZED`.

PR #160 (`FT-SPEECH-RETIRE-001`) is merged. PR #161 remains the active runtime-stability experiment and is still Draft/Open/Unmerged.

## Verified baseline

```text
MAIN_AFTER_PR160=26c81d83d3bdd771e98e355337b78622e2b25b17
ACTIVE_BRANCH=codex/ft-jsc-runtime-stability-001
ACTIVE_PR=#161 OPEN / DRAFT / UNMERGED
PRODUCT_COMMIT=8ceb99aa9fe30b0159d9cb5ad5d14d6e3e53f39f
SOAK_SOURCE_REVISION=5de2d0f2b8ec8934b60103e700d625f646dc8be6
SOAK_SOURCE_REVISION_EXACT=true
OPTIMIZATION=CHATGPT_GENERATION_LIVENESS_WATCHDOG_2S_TO_5S
MACOS_CI=#1205 SUCCESS
QA_DMG=#585 SUCCESS
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
JSC_ROOT_CAUSE=UNKNOWN
```

## Confirmed historical crash family

Native evidence from the pre-optimization soak established:

```text
EXCEPTION=EXC_BAD_ACCESS
SIGNAL=SIGSEGV
SUBTYPE=KERN_INVALID_ADDRESS 0x48
JSC_VERSION=22625.1.29.11.28
JSC_UUID=798e8d5d-b1a1-3ab1-89c7-8329cb6c0d15
FAULT_PC=7221987548
IMAGE_OFFSET=11172060
FAULT_SYMBOL=llint_entry_osr_function_for_call+120
SAME_HISTORICAL_JSC_CRASH_FAMILY=YES
SAME_EXACT_JSC_FAULT_SITE=YES
JSC_EXACT_TRIGGER=UNKNOWN
JSC_ROOT_CAUSE=UNKNOWN
```

The uploaded optimized-soak evidence bundle also contains three historical `.ips` reports. Their internal timestamps, not their filesystem mtimes, are authoritative:

```text
2026-10-24 14:50:27 +0800  EXC_BAD_ACCESS / SIGSEGV / 0x48 / llint_entry_osr_function_for_call+120
2026-10-27 18:29:53 +0800  EXC_BAD_ACCESS / SIGSEGV / 0x78 / ScriptExecutable::newReplacementCodeBlockFor -> operationOptimize
2026-10-28 12:03:16 +0800  EXC_BAD_ACCESS / SIGSEGV / 0x48 / llint_entry_osr_function_for_call+120
```

All use the same JavaScriptCore binary/version and repeat the broader async-generator / async-iterator / microtask crash family. None is a new native report for the optimized soak.

## PR #161 optimization verification

```text
PRE_AUDIT=PASS
FOCUSED_TESTS=217_PASS
FULL_XCTEST=1059_PASS
LOCAL_DEBUG_BUILD=PASS
LOCAL_RELEASE_BUILD=PASS_ARM64
MACOS_CI=#1205 SUCCESS
QA_DMG=#585 SUCCESS
```

The bounded intervention reduced the ChatGPT generation liveness watchdog cadence from 2 seconds to 5 seconds while preserving generation observation, Attention/Unread ownership and watchdog recovery semantics.

## Optimized Air soak — app/runtime evidence

Fresh optimized session:

```text
SESSION_ID=6DAB3F8F-4FA2-42CA-A1F9-A14093E73C94
SOURCE_REVISION=5de2d0f2b8ec8934b60103e700d625f646dc8be6
OBSERVED_RANGE=2026-10-29T12:49:56Z..2026-10-29T16:41:19Z
WEBCONTENT_TERMINATION_EVENTS=6
```

All six termination incident snapshots were again recorded while the affected ChatGPT Slot was generating and Attention-protected:

```text
CHATGPT_GENERATING_AT_TERMINATION=6/6
ATTENTION_PROTECTED_AT_TERMINATION=6/6
ACTIVE_SLOT_TERMINATIONS=1
INACTIVE_SLOT_TERMINATIONS=5
HOT_TERMINATIONS=2
WARM_TERMINATIONS=4
ALL_SIX_INCIDENTS_RECOVERED_TO_HEALTHY_CURRENT_RUNTIME=YES
```

## Optimized Air soak — system/native correlation

The separately captured macOS Unified Log now correlates all six optimized-session terminations one-for-one with WebKit system crash classification:

```text
2026-10-29 21:30:07.702 +0800  PID 39157  reason=Crash
2026-10-29 23:41:43.382 +0800  PID 39120  reason=Crash
2026-10-29 23:49:30.873 +0800  PID 39167  reason=Crash
2026-10-29 23:49:49.299 +0800  PID 65046  reason=Crash
2026-10-30 00:01:08.339 +0800  PID 43954  reason=Crash
2026-10-30 00:01:09.934 +0800  PID 68439  reason=Crash
```

For each event WebKit reports `WebProcessProxy::didClose: (web process 0 crash)` and `processDidTerminateOrFailedToLaunch: reason=Crash`, followed by `WebPageProxy::processDidTerminate: reason=Crash`.

ReportCrash attempted a type-309 native report for every one of the six crashes, but every attempt failed with:

```text
client log create type 309 result FAILED: Log limit exceeded
```

Therefore:

```text
OPTIMIZED_SOAK_SYSTEM_CONFIRMED_CRASHES=6/6
NEW_OPTIMIZED_SOAK_IPS_PERSISTED=0
SAME_NEW_EXACT_JSC_NATIVE_SIGNATURE=UNVERIFIED_BECAUSE_REPORTCRASH_LOG_LIMIT
```

The absence of a new `.ips` is a diagnostic retention limitation, not evidence of a different termination type.

## Memory / clustering evidence

Last observed affected-process footprints before the six crashes were approximately:

```text
PID 39157  1684 MB  memory-pressure event 16; system critical=0; policy -> Strict
PID 39120  1725 MB  memory-pressure event 16; later system critical=1; policy -> Strict
PID 39167  1102 MB  no nearby critical-pressure event found
PID 65046  2122 MB  no nearby critical-pressure event found
PID 43954  1129 MB  policy Unrestricted -> Conservative; no nearby critical-pressure event found
PID 68439  1168 MB  no nearby critical-pressure event found
```

Interpretation:

```text
ELEVATED_WEBCONTENT_FOOTPRINT_COMMON=YES
SYSTEM_VM_PRESSURE_CRITICAL_REQUIRED_FOR_CRASH=NO
MEMORY_PRESSURE_ROOT_CAUSE=UNKNOWN
```

Critical system VM pressure is therefore not a necessary observed condition for this crash set. Memory/resource pressure can remain an amplifier hypothesis, but it should not be treated as the sole next hypothesis.

Two multi-Slot crash clusters are especially notable:

```text
23:49:30.873 -> 23:49:49.299  different ChatGPT Slots, ~18.4 s apart
00:01:08.339 -> 00:01:09.934  different ChatGPT Slots, ~1.6 s apart
```

The first pair includes an inactive Warm Slot followed by the active Warm Slot. The second pair contains two inactive Warm Slots. Combined with 6/6 generating + attention-protected correlation, this increases the priority of investigating shared/multi-runtime conditions around concurrent long-lived ChatGPT generation rather than further tuning only one Slot's watchdog cadence.

The available slice-level event rate remains insufficient for a causal efficacy claim. The prior session slice recorded 7 terminations over about 3h21m, while the optimized session recorded 6 over about 3h51m. This is directionally lower but uncontrolled and too small to establish improvement.

Interpretation:

```text
WATCHDOG_2S_TO_5S_ELIMINATED_TERMINATION=NO
CORE_WEBCONTENT_CRASH_REPRODUCED=YES
OPTIMIZED_SOAK_SYSTEM_CRASH_CLASSIFICATION=CONFIRMED_6_OF_6
WATCHDOG_CADENCE_AS_PRIMARY_CAUSE=WEAKENED
SYSTEM_CRITICAL_MEMORY_PRESSURE_AS_REQUIRED_TRIGGER=NOT_SUPPORTED
NEXT_HYPOTHESIS_PRIORITY=MULTI_GENERATING_LONG_LIVED_WEBCONTENT / SHARED_RESOURCE_PRESSURE
JSC_ROOT_CAUSE=UNKNOWN
PR161_MERGE_READINESS=HOLD
```

## Stall / other runtime observations

The optimized session recorded one `post_finish_stall_candidate` caused by a dual-world timeout. It did not reach the confirmed-stall threshold and later closed as `superseded_navigation`.

No `attention.liveness_probe.abnormal` event was observed in the optimized session.

Other warnings remain lower priority and currently do not establish a product defect:

- two early `web_focus.failed` / `presentation_focus.failed` events with `dom_input_unavailable` immediately after launch/presentation;
- two provisional `NSURLErrorDomain -999` navigation cancellations and one `-1001` timeout;
- several previous-app restore observations where the external window could not be re-identified.

These are not currently promoted into the JSC incident root-cause chain.

## Separate unread / red-dot product finding

The same optimized runtime logs independently confirm the reported behavior for a visible active ChatGPT page.

During the fresh session:

```text
VALID_COMPLETIONS_NOT_PRESENTED=49 -> unread.marked reason=completion_unseen
VALID_COMPLETIONS_PRESENTED=18 -> unread.mark_skipped reason=visible_completion
```

Current code intentionally treats a valid completion as already handled when the Slot is actually user-visible. `ChatGPTUnreadResponseCoordinator.handle(...)` does not persist unread in that case, and the accepted V1 Attention contract explicitly defines visible completion as `Generating -> Idle` with no Ready red dot.

Therefore:

```text
ACTIVE_VISIBLE_COMPLETION_NO_RED_DOT=CONFIRMED_CURRENT_SEMANTICS
UI_RENDER_BUG=NO_EVIDENCE
PRODUCT_SEMANTIC_CHANGE_REQUIRED_IF_RED_DOT_SHOULD_ALWAYS_APPEAR=YES
SEPARATE_FOLLOWUP_FROM_PR161=YES
```

Do not mix this product semantic change into PR #161 unless task authority is explicitly changed.

## Current decision

```text
ACTIVE_TASK=FT-JSC-RUNTIME-STABILITY-001
ACTIVE_PR=#161 OPEN / DRAFT / UNMERGED
AIR_SOAK_RESULT=SYSTEM_CONFIRMED_WEBCONTENT_CRASH_REPRODUCED_6_OF_6
PR161_MERGE_READINESS=HOLD
CURRENT_INTERVENTION_RESULT=NEGATIVE_FOR_ELIMINATION / WORKLOAD_REDUCTION_ONLY
NEXT_RUNTIME_GATE=AUTHORIZE ONE NEW BOUNDED MULTI-RUNTIME/RESOURCE HYPOTHESIS BEFORE PRODUCT MUTATION
UNREAD_VISIBLE_COMPLETION_FINDING=SEPARATE PRODUCT FOLLOWUP
PRODUCTION_RELEASE=NOT_AUTHORIZED
```
