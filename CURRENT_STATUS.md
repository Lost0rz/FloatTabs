# FloatTabs Current Status

**Status date:** 2026-10-30
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: JSC / WEBCONTENT MULTI-RUNTIME PRESSURE INVESTIGATION**

Current task: `FT-JSC-MULTI-RUNTIME-002` — `ACTIVE / AUTHORIZED`.

PR #161 (`FT-JSC-RUNTIME-STABILITY-001`) is closed `ARCHIVE-ONLY / UNMERGED`. Its `2s -> 5s` watchdog experiment reduced periodic workload but did not eliminate WebContent crash reproduction and must not be treated as production state.

## Canonical baseline

```text
MAIN=26c81d83d3bdd771e98e355337b78622e2b25b17
ACTIVE_BRANCH=codex/ft-jsc-multi-runtime-002
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
PREDECESSOR_PR_161=CLOSED / ARCHIVE_ONLY / UNMERGED
JSC_ROOT_CAUSE=UNKNOWN
```

`AGENTS.md` was reviewed for this task transition; no durable project-rule change was required.

## Confirmed historical native family

```text
EXCEPTION=EXC_BAD_ACCESS
SIGNAL=SIGSEGV
COMMON_FAULT_ADDRESS=0x48
COMMON_FAULT_SYMBOL=llint_entry_osr_function_for_call+120
ASYNC_PATH=async-generator / async-iterator / microtask
SAME_HISTORICAL_JSC_CRASH_FAMILY=YES
JSC_EXACT_TRIGGER=UNKNOWN
JSC_ROOT_CAUSE=UNKNOWN
```

## Negative predecessor experiment

PR #161 exact QA build reproduced six system-confirmed WebContent crashes after the generation liveness watchdog cadence was reduced from 2 seconds to 5 seconds.

```text
SYSTEM_CONFIRMED_WEBCONTENT_CRASHES=6/6
CHATGPT_GENERATING_AT_TERMINATION=6/6
ATTENTION_PROTECTED_AT_TERMINATION=6/6
ACTIVE_SLOT_TERMINATIONS=1
INACTIVE_SLOT_TERMINATIONS=5
HOT_TERMINATIONS=2
WARM_TERMINATIONS=4
WATCHDOG_2S_TO_5S_ELIMINATED_CRASH=NO
WATCHDOG_CADENCE_AS_PRIMARY_CAUSE=WEAKENED
```

All six were classified by WebKit as `reason=Crash`. No new optimized-soak `.ips` persisted because each ReportCrash type-309 attempt failed with `Log limit exceeded`.

## Resource / clustering update

```text
ELEVATED_WEBCONTENT_FOOTPRINT_COMMON=YES
SYSTEM_VM_PRESSURE_CRITICAL_REQUIRED_FOR_CRASH=NO
MEMORY_PRESSURE_ROOT_CAUSE=UNKNOWN
MULTI_SLOT_CRASH_CLUSTER_1=~18.4s
MULTI_SLOT_CRASH_CLUSTER_2=~1.6s
```

Critical system VM pressure was not observed before most crashes, so it is not a required observed trigger. The strongest next evidence axis is the combination of multiple long-lived ChatGPT runtimes, concurrent generation, Attention protection, and shared/system resource pressure.

This remains correlation, not a causal claim.

## Active investigation direction

The new task must first map:

```text
simultaneous generating ChatGPT Slots
× Attention-protected runtime count
× WKWebView / WebContent / process-pool / data-store topology
× per-Slot repeated FloatTabs-owned work
× long-lived residency
× non-protected runtime footprint under shared pressure
× clustered termination timing
```

The next product mutation, if any, must be one smallest evidence-supported intervention. Do not inherit PR #161's watchdog change by default.

## Separate product follow-up

Optimized-session logs and current code confirm that valid ChatGPT completions occurring while the Slot is actually presented intentionally skip persistent unread/red-dot state.

```text
ACTIVE_VISIBLE_COMPLETION_NO_RED_DOT=CONFIRMED_CURRENT_SEMANTICS
PRODUCT_SEMANTIC_CHANGE_REQUIRED_IF_RED_DOT_SHOULD_ALWAYS_APPEAR=YES
SEPARATE_FROM_RUNTIME_TASK=YES
```

No red-dot semantic change is authorized in `FT-JSC-MULTI-RUNTIME-002`.

## Current decision

```text
ACTIVE_TASK=FT-JSC-MULTI-RUNTIME-002
NEXT_GATE=LOCAL PRE_AUDIT
PRODUCT_CODE_CHANGE=NONE_YET
PR161=ARCHIVED_NEGATIVE_EXPERIMENT
PRODUCTION_RELEASE=NOT_AUTHORIZED
JSC_ROOT_CAUSE=UNKNOWN
```
