# FloatTabs Current Status

**Status date:** 2026-10-30
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: ARCHIVED NEGATIVE RUNTIME EXPERIMENT**

Task `FT-JSC-RUNTIME-STABILITY-001` is closed `ARCHIVE-ONLY / UNMERGED`.

PR #161 tested one bounded intervention: ChatGPT generation liveness watchdog cadence `2s -> 5s`. Verification passed, but the optimized Air soak reproduced six system-confirmed WebContent crashes. The branch is historical evidence only and is not production truth.

## Experiment identity

```text
BASE_MAIN=26c81d83d3bdd771e98e355337b78622e2b25b17
PR=#161
PRODUCT_COMMIT=8ceb99aa9fe30b0159d9cb5ad5d14d6e3e53f39f
SOAK_SOURCE_REVISION=5de2d0f2b8ec8934b60103e700d625f646dc8be6
OPTIMIZATION=CHATGPT_GENERATION_LIVENESS_WATCHDOG_2S_TO_5S
MACOS_CI=#1205 SUCCESS
QA_DMG=#585 SUCCESS
DISPOSITION=ARCHIVE_ONLY / DO_NOT_MERGE
JSC_ROOT_CAUSE=UNKNOWN
```

## Optimized Air soak result

```text
SESSION_ID=6DAB3F8F-4FA2-42CA-A1F9-A14093E73C94
SYSTEM_CONFIRMED_WEBCONTENT_CRASHES=6/6
CHATGPT_GENERATING_AT_TERMINATION=6/6
ATTENTION_PROTECTED_AT_TERMINATION=6/6
ACTIVE_SLOT_TERMINATIONS=1
INACTIVE_SLOT_TERMINATIONS=5
HOT_TERMINATIONS=2
WARM_TERMINATIONS=4
ALL_SIX_INCIDENTS_RECOVERED=YES
```

WebKit classified all six as `reason=Crash`. ReportCrash attempted type-309 reports for all six but each failed with `Log limit exceeded`, so no new optimized-soak `.ips` persisted.

## Hypothesis update

```text
WATCHDOG_2S_TO_5S_ELIMINATED_CRASH=NO
WATCHDOG_CADENCE_AS_PRIMARY_CAUSE=WEAKENED
SYSTEM_VM_PRESSURE_CRITICAL_REQUIRED_FOR_CRASH=NO
ELEVATED_WEBCONTENT_FOOTPRINT_COMMON=YES
MEMORY_PRESSURE_ROOT_CAUSE=UNKNOWN
MULTI_SLOT_CRASH_CLUSTER_1=~18.4s
MULTI_SLOT_CRASH_CLUSTER_2=~1.6s
NEXT_PRIORITY=MULTI_GENERATING / LONG_LIVED_WEBCONTENT / SHARED_RESOURCE_PRESSURE
JSC_ROOT_CAUSE=UNKNOWN
```

Historical native evidence still identifies the recurring family as JavaScriptCore `EXC_BAD_ACCESS / SIGSEGV`, commonly `KERN_INVALID_ADDRESS 0x48`, at `llint_entry_osr_function_for_call+120` on an async-generator / iterator / microtask path. The exact trigger remains unknown.

## Separate product finding

Visible active ChatGPT completions intentionally skip persistent unread under the current V1 Attention contract. Changing that red-dot behavior requires a separate product-semantic task and must not be mixed into this archived runtime experiment.

## Final decision

```text
PR161=ARCHIVE_ONLY
MERGE=NO
RELEASE=NO
SUCCESSOR_RUNTIME_TASK_REQUIRED=YES
```
