# FloatTabs Current Status

**Status date:** 2026-10-30
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: JSC / WEBCONTENT RUNTIME STABILITY — AIR SOAK REPRODUCED**

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

## Air soak result for optimized build

Uploaded runtime logs contain a fresh session for the optimized exact revision:

```text
SESSION_ID=6DAB3F8F-4FA2-42CA-A1F9-A14093E73C94
SOURCE_REVISION=5de2d0f2b8ec8934b60103e700d625f646dc8be6
OBSERVED_RANGE=2026-10-29T12:49:56Z..2026-10-29T16:41:19Z
WEBCONTENT_TERMINATION_EVENTS=6
```

All six new termination incident snapshots were again recorded while the affected ChatGPT Slot was generating and Attention-protected:

```text
CHATGPT_GENERATING_AT_TERMINATION=6/6
ATTENTION_PROTECTED_AT_TERMINATION=6/6
ACTIVE_SLOT_TERMINATIONS=1
INACTIVE_SLOT_TERMINATIONS=5
HOT_TERMINATIONS=2
WARM_TERMINATIONS=4
ALL_SIX_INCIDENTS_RECOVERED_TO_HEALTHY_CURRENT_RUNTIME=YES
```

The new JSONL package does not contain matching Unified Log or new `.ips` evidence. Therefore these six events prove that WebContent process termination still reproduces after the 2s→5s optimization, but they do not by themselves prove that every event is the exact historical JSC `SIGSEGV / 0x48 / llint_entry_osr_function_for_call+120` family.

The available slice-level event rate is not sufficient for a causal efficacy claim. The previous session slice in the same archive recorded 7 terminations over about 3h21m, while the optimized session recorded 6 over about 3h51m. This is directionally lower but uncontrolled and too small to establish improvement.

Interpretation:

```text
WATCHDOG_2S_TO_5S_ELIMINATED_TERMINATION=NO
CORE_WEBCONTENT_TERMINATION_REPRODUCED=YES
SAME_NEW_JSC_NATIVE_SIGNATURE=UNVERIFIED_PENDING_NATIVE_EVIDENCE
JSC_ROOT_CAUSE=UNKNOWN
PR161_MERGE_READINESS=HOLD
```

## Stall / other runtime observations

The optimized session recorded one `post_finish_stall_candidate` caused by a dual-world timeout. It did not reach the confirmed-stall threshold and later closed as `superseded_navigation`.

No `attention.liveness_probe.abnormal` event was observed in the optimized session.

Other warnings were lower priority and currently do not establish a product defect:

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
AIR_SOAK_RESULT=WEBCONTENT_TERMINATION_REPRODUCED
PR161_MERGE_READINESS=HOLD
NEXT_RUNTIME_GATE=COLLECT_NATIVE/SYSTEM EVIDENCE FOR NEW TERMINATIONS THEN SELECT NEXT BOUNDED HYPOTHESIS
UNREAD_VISIBLE_COMPLETION_FINDING=SEPARATE PRODUCT FOLLOWUP
PRODUCTION_RELEASE=NOT_AUTHORIZED
```
