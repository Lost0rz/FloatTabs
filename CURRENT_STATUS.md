# FloatTabs Current Status

**Status date:** 2026-10-29
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: JSC / WEBCONTENT RUNTIME STABILITY OPTIMIZATION**

Current task: `FT-JSC-RUNTIME-STABILITY-001` — `ACTIVE / AUTHORIZED`.

PR #160 (`FT-SPEECH-RETIRE-001`) has been merged. Speech/TTS retirement is complete and is no longer the active task. The repeated WebContent failure is now an independent runtime-stability incident.

## Verified baseline

```text
MAIN_AFTER_PR160=26c81d83d3bdd771e98e355337b78622e2b25b17
PR160=MERGED
PR160_HEAD=d46a23c553c965d415dbda155ce200e6f91dcfb0
PR160_LITERAL_HEAD_MACOS_CI=#1200 SUCCESS
PR160_LITERAL_HEAD_QA_DMG=#583 SUCCESS
ACTIVE_BRANCH=codex/ft-jsc-runtime-stability-001
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
```

## Confirmed crash family

Post-retirement native evidence proves the same JavaScriptCore crash family remains present:

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

The confirmed post-retirement `.ips` is `com.apple.WebKit.WebContent-2026-10-29-192012.ips`; it repeats the historical async-generator/microtask execution family.

## Runtime correlation

The accepted soak produced seven system-confirmed WebContent crashes:

```text
SYSTEM_CONFIRMED_WEBCONTENT_CRASHES=7
CHATGPT_GENERATING_AT_CRASH=7/7
ATTENTION_PROTECTED_AT_CRASH=7/7
ACTIVE_SLOT_CRASHES=1
INACTIVE_SLOT_CRASHES=6
HOT_AND_WARM_BOTH_REPRODUCE=YES
ALL_RUNTIME_RECORDED_CRASHES_RECOVERED=YES
```

A separate post-finish stall also reached the diagnostic confirmation threshold.

## Memory-pressure evidence

The final crash pair occurred with substantial WebContent memory pressure. Observed WebContent footprints included approximately `1.6 GB` and `2.2 GB`, with `system vm pressure critical: 1` recorded before the crashes.

Interpretation:

```text
MEMORY_PRESSURE_CORRELATION=SUPPORTED
MEMORY_PRESSURE_ROOT_CAUSE=UNKNOWN
JETSAM_KILL_CLASSIFICATION=NO
```

Memory pressure is therefore a valid optimization/investigation axis, but the native termination remains a JSC `EXC_BAD_ACCESS / SIGSEGV` rather than a proven memory kill.

## Prior exclusions / reduced hypotheses

```text
SPEECH_CAUSALITY_SUPPORTED=NO
INACTIVE_PERIODIC_LIVENESS_PROBE_REQUIRED_FOR_CRASH=NO
INACTIVE_SLOT_RELEASE_ALONE_EXPLAINS_FAILURE=NO
RELOAD_RESET_RESTART_PROVES_ROOT_CAUSE=NO
```

## Active optimization direction

The authorized task now audits and optimizes the FloatTabs-owned runtime path around:

```text
ChatGPT generation/status observation
× Attention/Unread protection
× repeated JS / DOM / cross-world work
× long-lived Slot residency
× memory-pressure response
```

The first implementation must be one bounded, evidence-supported intervention. It must reduce FloatTabs-owned runtime pressure/workload without interrupting ChatGPT generation, weakening required Attention/Unread behavior, or mutating Browser Profiles/sessions/user data.

## Current decision

```text
ACTIVE_TASK=FT-JSC-RUNTIME-STABILITY-001
ACTIVE_PR=TO_BE_OPENED
PRODUCT_CODE_CHANGE=NONE_YET
NEXT_GATE=LOCAL PRE_AUDIT -> BOUNDED OPTIMIZATION -> TEST/CI/QA DMG
TARGET_VALIDATION=AIR SOAK
PRODUCTION_RELEASE=NOT_AUTHORIZED
```
