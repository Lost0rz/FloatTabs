# FloatTabs Current Task

**Task ID:** `FT-JSC-RUNTIME-STABILITY-001`
**Title:** Reduce JSC/WebContent crash exposure and long-lived runtime pressure
**Status:** `CLOSED / ARCHIVE-ONLY / UNMERGED`
**Mode:** `CLOSEOUT`
**Task class:** `RUNTIME STABILITY / EVIDENCE-DRIVEN CORRECTIVE`
**Authorized baseline:** `main@26c81d83d3bdd771e98e355337b78622e2b25b17`
**Public baseline:** `v0.5.8` / Build `26`
**JSC root cause:** `UNKNOWN`

## Disposition

This task tested one bounded intervention: reducing the ChatGPT generation liveness watchdog cadence from 2 seconds to 5 seconds.

Verification passed, including focused tests, full XCTest, Debug/Release arm64 build, exact-head macOS CI and QA DMG. The intervention reduced periodic watchdog work but the optimized Air soak reproduced six system-confirmed WebContent crashes.

Therefore:

```text
WATCHDOG_WORKLOAD_REDUCTION=YES
CORE_WEBCONTENT_CRASH_ELIMINATED=NO
SYSTEM_CONFIRMED_OPTIMIZED_SOAK_CRASHES=6/6
MERGE=NO
DISPOSITION=ARCHIVE_ONLY
JSC_ROOT_CAUSE=UNKNOWN
```

The experiment is closed without merge. Its branch/PR remain historical evidence only and must not be treated as current production truth.

## Durable evidence handed forward

```text
CHATGPT_GENERATING_AT_TERMINATION=6/6
ATTENTION_PROTECTED_AT_TERMINATION=6/6
ACTIVE_SLOT_TERMINATIONS=1
INACTIVE_SLOT_TERMINATIONS=5
HOT_TERMINATIONS=2
WARM_TERMINATIONS=4
SYSTEM_VM_PRESSURE_CRITICAL_REQUIRED_FOR_CRASH=NO
ELEVATED_WEBCONTENT_FOOTPRINT_COMMON=YES
MULTI_SLOT_CRASH_CLUSTER_1=~18.4s
MULTI_SLOT_CRASH_CLUSTER_2=~1.6s
NEW_OPTIMIZED_SOAK_IPS_PERSISTED=0 due ReportCrash log limit
```

The historical native family remains:

```text
EXC_BAD_ACCESS / SIGSEGV
KERN_INVALID_ADDRESS 0x48
llint_entry_osr_function_for_call+120
async-generator / iterator / microtask path
```

The exact trigger and root cause remain unknown.

## Separate product follow-up

Visible active ChatGPT completion intentionally suppresses persistent unread under the current V1 contract. Changing that red-dot behavior is a separate product-semantic task and is not part of this runtime experiment.

## Closeout boundary

No production release is authorized from this task. Any successor runtime work must start from canonical `main` and establish a new task authority rather than extending this closed branch.