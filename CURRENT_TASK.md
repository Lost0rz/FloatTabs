# FloatTabs Current Task

**Task ID:** `FT-JSC-MULTI-RUNTIME-002`
**Title:** Audit multi-generating long-lived ChatGPT WebContent clustering and shared resource pressure
**Status:** `ACTIVE / AUTHORIZED`
**Mode:** `EXECUTE`
**Task class:** `RUNTIME STABILITY / EVIDENCE-DRIVEN CORRECTIVE`
**Authorized baseline:** `main@26c81d83d3bdd771e98e355337b78622e2b25b17`
**Public baseline:** `v0.5.8` / Build `26`
**Predecessor:** PR #161 `CLOSED / ARCHIVE-ONLY / UNMERGED`
**JSC root cause:** `UNKNOWN`

## Purpose

Investigate the strongest remaining correlation after the negative watchdog-cadence experiment: multiple long-lived ChatGPT WebContent runtimes generating concurrently while Attention-protected, with crash events clustering across different Slots.

The task must determine whether FloatTabs-owned multi-runtime behavior or shared resource pressure exposes a bounded mitigation opportunity, then implement at most one smallest evidence-supported intervention and produce a new QA artifact for Air soak.

This task does not claim that concurrent generation, Attention protection, memory pressure, or FloatTabs itself is the proven JSC root cause.

## Verified evidence carried forward

Historical native crash family:

```text
EXCEPTION=EXC_BAD_ACCESS
SIGNAL=SIGSEGV
COMMON_FAULT_ADDRESS=0x48
COMMON_FAULT_SYMBOL=llint_entry_osr_function_for_call+120
ASYNC_PATH=async-generator / async-iterator / microtask
JSC_ROOT_CAUSE=UNKNOWN
```

Optimized soak from closed PR #161:

```text
SYSTEM_CONFIRMED_WEBCONTENT_CRASHES=6/6
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
WATCHDOG_2S_TO_5S_ELIMINATED_CRASH=NO
```

PR #161 is negative evidence only. Do not cherry-pick or inherit its `2s -> 5s` watchdog change unless new evidence independently authorizes that behavior; canonical `main` remains the baseline.

## Gate 1 — bounded PRE_AUDIT

Before any product mutation, map the exact current production path for:

1. how many ChatGPT Slots can be simultaneously `Generating` and `Attention-protected`;
2. WebView/WebContent/process-pool/data-store topology across those Slots and Browser Profiles;
3. Slot residency decisions while multiple protected runtimes coexist;
4. FloatTabs-owned repeated JavaScript, DOM, bridge, health, diagnostics and benchmark work performed per generating Slot;
5. memory-pressure handling and what non-protected runtimes remain resident while multiple protected ChatGPT runtimes are active;
6. termination/recovery ownership and whether clustered crashes share any FloatTabs-owned global coordinator, timer, queue or resource boundary;
7. existing tests and diagnostics that can distinguish single-generating versus multi-generating runtime states.

Quantify, where the code permits, which workload scales linearly with the number of generating protected Slots and which workload is globally shared.

Return:

```text
PRE_AUDIT=PASS | STOP
MULTI_GENERATING_RUNTIME_TOPOLOGY=<facts>
SCALING_FLOATTABS_WORK=<facts>
SAFE_BOUNDED_INTERVENTION=<one candidate or NONE>
```

## Gate 2 — one smallest evidence-supported intervention

Only after PRE_AUDIT passes, implement at most one coherent intervention that reduces FloatTabs-owned shared/multi-runtime pressure without interrupting ChatGPT generation.

Authorized classes, only if supported by the audit:

1. reduce or coalesce non-essential FloatTabs-owned work that scales with concurrent generating Slots;
2. stagger globally coordinated non-essential work to avoid synchronized per-Slot bursts;
3. under elevated shared runtime pressure, release or defer only **non-active, non-generating, non-Attention-protected** runtimes while preserving Browser Profile/session data;
4. add the minimal diagnostics required to measure concurrent-generating count, protected-runtime count, affected WebContent footprint/pressure context, and clustered termination relationships when no safe mitigation can yet be proven.

Do not batch multiple speculative mitigations. If no safe bounded intervention is established, STOP after diagnostics/evidence rather than inventing one.

## Local execution result (2026-10-30)

```text
PRE_AUDIT=PASS
INTERVENTION=DIAGNOSTICS_ONLY
SAFE_BOUNDED_INTERVENTION=NONE
```

The audit established a bounded measurement gap: existing diagnostics exposed
resident/protected totals but did not separate resident generating from resident
ready runtimes across Slots. A single read-only diagnostic improvement now
records `resident_attention_generating_count`,
`resident_attention_ready_count`, and `resident_attention_protected_count`
in incident snapshots, long-term checkpoints and one-shot runtime snapshots.
No generation, Attention/Unread, residency, recovery, process-pool, data-store,
profile, session or user-data behavior was changed.

Local verification completed before delivery:

```text
FOCUSED_CROSS_FEATURE_TESTS=122/122 PASSED
FULL_XCTEST=1059/1059 PASSED
DEBUG_ARM64_BUILD=SUCCEEDED
RELEASE_ARM64_BUILD=SUCCEEDED
```

## Mandatory preserve boundary

```text
ChatGPT generation must continue normally
Attention / Unread / 有回复 existing semantics
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

Do not delete/reset/rebuild Browser Profiles, cookies, sessions, Slot data, backups or preferences.

Do not use routine reload/restart/reset as the optimization or as root-cause evidence.

Do not change canonical WebView ownership, process-pool ownership, Browser Profile data-store ownership or other architecture boundaries without a separate architecture decision.

## Gate 3 — verification and QA

Before Air soak handoff:

- focused tests for every touched runtime/residency/Attention path;
- full required XCTest suite;
- Debug and Release arm64 build gates;
- exact-head CI and QA DMG checks;
- diagnostics must preserve enough evidence to compare single- vs multi-generating conditions;
- no regression in Attention/Unread, generation tracking, RemoteOrbit focus, background media, Browser Profiles or recovery;
- QA DMG must be tied to exact source revision and SHA256.

## Interpretation rules

```text
MULTI_SLOT_CLUSTER != CONCURRENT_GENERATION_ROOT_CAUSE
ELEVATED_FOOTPRINT != MEMORY_ROOT_CAUSE
LOWER_CRASH_RATE != ROOT_CAUSE_PROVEN
NO_CRASH_DURING_BOUNDED_SOAK != FIX_PROVEN
JSC_NATIVE_CRASH_SITE != FLOATTABS_SOURCE_LINE_PROVEN
```

## STOP conditions

STOP and report evidence if:

- PRE_AUDIT cannot establish a bounded FloatTabs-owned multi-runtime workload or measurement gap;
- the proposed change would interrupt or serialize user ChatGPT generation as a product behavior;
- the change would weaken required Attention/Unread protection for work still generating or unseen;
- the only proposed mitigation is destructive data/session/profile mutation or routine reload/reset/restart;
- implementation requires canonical WebView/process-pool/data-store ownership redesign;
- tests/builds fail because of the intervention;
- new native evidence contradicts the current incident classification.

## Completion boundary

This task reaches `AIR_SOAK_READY` only after one bounded intervention or evidence-critical diagnostic improvement is implemented, verified and delivered with a fresh QA DMG.

Final receipt must distinguish:

```text
PRE_AUDIT=<result>
INTERVENTION=<exactly one or DIAGNOSTICS_ONLY>
MULTI_RUNTIME_PRESSURE_REDUCED_OR_MEASURED=<evidence>
FULL_TEST_BUILD_GATE=<result>
CI_GATE=<result>
QA_DMG=<identity/path/hash>
JSC_ROOT_CAUSE=UNKNOWN unless separately proven
AIR_SOAK=READY | BLOCKED
```

Production release is not authorized by this task.

## Separate follow-up not authorized here

The active-visible ChatGPT completion red-dot behavior is a confirmed product-semantic issue: current V1 intentionally suppresses persistent unread for visible completion. Any change to that behavior requires a separate product task and must not be mixed into this runtime experiment.
