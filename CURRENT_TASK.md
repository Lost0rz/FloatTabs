# FloatTabs Current Task

**Task ID:** `FT-WEBCONTENT-JSC-AB-001`
**Title:** Isolate background liveness-probe contribution to repeated JavaScriptCore WebContent crashes
**Status:** `ACTIVE / AUTHORIZED`
**Mode:** `EXECUTE`
**Task class:** `DIAGNOSTIC / EXPERIMENT`
**Authorized semantic baseline:** `main@ecd615602075cea6cbdb4bda4a9e2132cd682d55`
**Public baseline:** `v0.5.8` / Build `26`
**Historical runtime root cause:** `UNKNOWN`

## Purpose

Determine whether FloatTabs' periodic background cross-world JavaScript liveness evaluation is **required to trigger or materially amplify** the repeated JavaScriptCore crash family observed during the v0.5.8 runtime observation period.

This task authorizes one minimal QA-only diagnostic variant. It does **not** authorize a production fix, release, recovery-policy change, residency change, persistence change, Browser Profile/session mutation, or broad observability expansion.

## Evidence basis

Fresh evidence now supports the following fault boundary:

```text
FAILURE_CLASS=WebContent native crash
FAULTING_SUBSYSTEM=JavaScriptCore
DIRECT_TERMINATION=SIGSEGV / JSC fatal crash family
DOMINANT_AREA=JIT / OSR / DFG / optimized CodeBlock lifecycle
EXACT_TRIGGER=UNKNOWN
ROOT_CAUSE=UNKNOWN
```

The preserved corpus contains 38 FloatTabs-attributed `com.apple.WebKit.WebContent` crash reports on macOS `27.0.1 (26A434)` / WebKit `22625.1.29.11.28`. The dominant signatures are repeated `llint_entry_osr_function_for_call`, `JSC::ScriptExecutable::newReplacementCodeBlockFor -> operationOptimize`, and JSC CodeBlock/JIT-to-DFG fatal paths during async/microtask execution.

A fresh v0.5.8 incident also showed successful JavaScript liveness evaluation less than one second before a WebContent `SIGSEGV`. That temporal relationship is a hypothesis input only; it does not prove the probe caused the crash.

## Blocked decision

```text
MISSING_FACT=
Is FloatTabs periodic background cross-world JavaScript probing required for this JSC crash family to occur?

BLOCKED_DECISION=
Whether future production work should change FloatTabs liveness-probe behavior or instead treat the crash primarily as a page/WebKit/JSC runtime defect outside the probe path.
```

## Authorized experiment

### A — existing baseline

Use the already-preserved v0.5.8 / Build 26 runtime and `.ips` corpus as the A-side evidence. Do not mutate or rebuild A merely to create symmetry.

### B — minimal diagnostic variant

Implement the smallest source change that:

1. suppresses the **periodic cross-world JavaScript liveness evaluation** when the target Slot is inactive;
2. leaves the same liveness evaluation unchanged for active Slots;
3. does not change Slot residency, WebView ownership/lifecycle, navigation, recovery, Attention business state, focus/input, persistence, Browser Profiles, sessions, timeout thresholds or user data;
4. does not add a general diagnostics framework or broad new telemetry;
5. may add at most one bounded experiment marker/counter, only if needed to prove that the inactive-probe suppression path actually executed;
6. remains a QA/diagnostic variant and is not released as production behavior under this task.

If safely suppressing only the diagnostic probe would require materially new cross-Domain ownership, changing canonical runtime semantics, or coupling Attention/business state into Web runtime ownership, **STOP** and report the exact dependency instead of broadening scope.

## Implementation route

Use `docs/architecture/DOMAIN_MAP.md` to locate the Web runtime liveness-probe owner and its relevant tests. Preserve canonical ownership.

Prefer an implementation that changes the narrow scheduling/evaluation gate for inactive Slots rather than modifying JavaScript payloads, page state, reload/reset behavior, or WebView lifecycle.

No source-level workaround for JavaScriptCore/JIT behavior is authorized.

## Verification

Before runtime observation, prove all of the following:

1. focused tests cover:
   - active Slot -> periodic cross-world liveness evaluation still executes;
   - inactive Slot -> periodic cross-world liveness evaluation is suppressed in the B variant;
   - suppression does not trigger reload/reset/recovery or change residency;
2. existing relevant Web runtime regression tests pass;
3. full required macOS build/test gate for the experimental branch passes;
4. the QA build is clearly identifiable as the B diagnostic variant;
5. no product data or Browser Profile/session data is reset or migrated.

## Runtime evidence gate

Run the B variant on the same affected Mac under normal ChatGPT use, specifically including inactive/background ChatGPT generation workloads.

Preserve:

- B build/source identity;
- runtime diagnostics covering inactive-probe suppression and WebContent terminations;
- any fresh `com.apple.WebKit.WebContent` `.ips` report;
- incident time / Slot / site / active state / generation state;
- recovery action/result if recovery is needed.

Interpretation rules:

```text
IF same JSC crash family reproduces while inactive probe is suppressed:
    background probe is NOT REQUIRED for the crash family;
    do not propose a probe-based production fix from this task.

IF no crash reproduces during bounded B observation:
    record NON_REPRODUCTION only;
    do not claim the probe is causal or that the issue is fixed.

IF a materially different crash/failure appears:
    preserve it separately;
    do not merge failure classes without evidence.
```

## Safety boundaries

```text
RECOVERY_POLICY=UNCHANGED
RELOAD_RESET_BEHAVIOR=UNCHANGED
RESIDENCY_POLICY=UNCHANGED
ATTENTION_BUSINESS_STATE=UNCHANGED
FOCUS_POLICY=UNCHANGED
TIMEOUT_THRESHOLDS=UNCHANGED
BROWSER_PROFILES=UNCHANGED
WEBSITE_SESSIONS_DATA=UNCHANGED
PERSISTENCE=UNCHANGED
USER_DATA=UNTOUCHED
ACTIVE_SLOT_LIVENESS_PROBING=UNCHANGED
PRODUCTION_RELEASE=NOT_AUTHORIZED
```

No Browser Profile, website session, cookie, preference, backup or persisted website data may be deleted, reset, recreated or overwritten for this experiment.

## STOP conditions

STOP and report evidence if:

- the current repository/task authority no longer matches this task materially;
- an overlapping write-capable PR/worktree contains unknown unique work;
- the liveness probe cannot be isolated without changing product/runtime ownership or unrelated behavior;
- required tests/build gates fail for reasons caused by this experiment;
- the experimental build cannot be distinguished reliably from v0.5.8 baseline;
- safe runtime observation would require resetting user/site data;
- evidence proves a different missing fact must be answered before the A/B decision is meaningful.

## Completion boundary

This task ends with an evidence-backed diagnostic disposition. It does not merge a production runtime behavior change or publish a release.

The final result must report:

```text
A_BASELINE_EVIDENCE=<summary>
B_IMPLEMENTATION_IDENTITY=<commit/build>
B_PROBE_SUPPRESSION_VERIFIED=<YES/NO>
B_RUNTIME_EXPOSURE=<observed workload/window>
B_JSC_CRASH_REPRODUCED=<YES/NO/UNKNOWN>
B_CRASH_SIGNATURE=<signature or NONE>
PROBE_REQUIRED_FOR_CRASH=<SUPPORTED / NOT_SUPPORTED / UNKNOWN>
ROOT_CAUSE=<KNOWN / UNKNOWN>
PRODUCTION_FIX_AUTHORIZED=NO
```
