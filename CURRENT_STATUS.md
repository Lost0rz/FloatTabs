# FloatTabs Current Status

**Status date:** 2026-10-28
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: DIAGNOSTIC EXPERIMENT AUTHORIZATION**

Current task: `FT-WEBCONTENT-JSC-AB-001` — `ACTIVE / AUTHORIZED`

## Current verified baseline

```text
REMOTE_MAIN=ecd615602075cea6cbdb4bda4a9e2132cd682d55
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
RELEASE_MERGE_HEAD=36c8c1733f25095e5b1b2e0ba6d090a50aa22918
ACCEPTED_DIAGNOSTICS_SEMANTIC_HEAD=b6d9e6841da92033dbc2f5fbd5c325915e1e3864
OPEN_PRS_AT_RECONCILIATION=0
ROOT_CAUSE=UNKNOWN
FAULTING_SUBSYSTEM=JavaScriptCore
```

FloatTabs v0.5.8 / Build 26 remains the current public release. No production runtime fix has been accepted or released for the WebContent crash family.

## Fresh incident evidence

The v0.5.8 observation period produced materially stronger evidence than the previous generic WebContent termination classification.

For the 2026-10-27 21:44:55 +0800 incident:

- `com.apple.WebKit.WebContent` PID `53961` terminated as `reason=Crash`;
- `launchd` recorded `SIGSEGV`, not a normal WebKit reclamation or direct Jetsam termination;
- the WebContent process successfully completed a JavaScript-in-script-world probe roughly 0.8 seconds before the crash;
- the process had recently reached roughly 1.1 GB memory footprint and WebKit changed its memory policy from `Unrestricted` to `Conservative`, but the crash stack is not an allocator/OOM/Jetsam stack;
- ReportCrash captured corpse data for PID `53961`, but OSAnalytics did not persist that incident's `.ips` because type-309 crash-report creation returned `Log limit exceeded`.

Historical crash reports already present on the same Mac supplied the missing stack evidence. The preserved corpus contains 38 `com.apple.WebKit.WebContent` `.ips` reports attributable to FloatTabs, all on macOS `27.0.1 (26A434)` / WebKit `22625.1.29.11.28`.

Crash clustering shows:

```text
38/38  faulting queue = com.apple.main-thread
33/38  EXC_BAD_ACCESS / SIGSEGV
18/38  llint_entry_osr_function_for_call family, commonly invalid address 0x48
14/38  JSC::ScriptExecutable::newReplacementCodeBlockFor -> operationOptimize family, commonly invalid address 0x78
4/38   JSC CodeBlock / JIT-to-DFG deferred compilation WTFCrash family
2/38   other JSC faults
37/38  faulting stacks include async generator / async iterator execution
38/38  faulting stacks include the JavaScriptCore/microtask execution path
```

At least one v0.5.8 runtime incident was timestamp-correlated to a preserved `.ips` report showing the `newReplacementCodeBlockFor -> operationOptimize` family while an inactive warm ChatGPT Slot was resident, generating and Attention-protected.

## Evidence-supported fault boundary

The failure class is now narrower than the former generic WebContent termination label:

```text
FAILURE_CLASS=WebContent native crash
DIRECT_TERMINATION=SIGSEGV / JSC fatal crash family
FAULTING_SUBSYSTEM=JavaScriptCore
DOMINANT_AREA=JIT / OSR / DFG / optimized CodeBlock lifecycle during async/microtask execution
JETSAM_DIRECT_CAUSE=NOT_SUPPORTED
FLOATTABS_RECOVERY_CAUSE=NOT_SUPPORTED
EXACT_TRIGGER=UNKNOWN
ROOT_CAUSE=UNKNOWN
```

The historical `post_finish_runtime_stall` remains a separate observed failure class and must not be merged into this crash family without evidence.

## Active diagnostic question

The next blocked decision is whether FloatTabs' periodic **background cross-world JavaScript liveness probe** is required to trigger or materially amplify this repeated JavaScriptCore crash family.

The authorized diagnostic experiment therefore uses:

- **A:** existing v0.5.8 / Build 26 evidence, unchanged;
- **B:** a QA-only variant that suppresses only the periodic cross-world JavaScript liveness evaluation while a Slot is inactive, while preserving active-Slot probes and all product/runtime semantics outside that diagnostic probe.

A B-side reproduction with the same JSC signature would strongly show that the background probe is not required for the crash. A bounded B observation with no crash is only non-reproduction evidence and must not be promoted to a causal fix.

## Safety / unchanged product semantics

The experiment must preserve:

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

No Browser Profile, website session, cookie, preference, backup or persisted website data may be cleared or rebuilt for this experiment.

## Repository lifecycle

- Cleanup PR #151: `MERGED`.
- Diagnostics authorization PR #152: `MERGED`.
- Diagnostics implementation PR #153: `MERGED`.
- v0.5.8 release PR #154: `MERGED`.
- Observation closeout/corrective PRs #155 / #156: `MERGED`.
- Public release `v0.5.8`: `PUBLISHED / VERIFIED`.
- At reconciliation time, open PR count was `0`.
- The new task is diagnostic-experiment authorization only; no product implementation or release disposition has yet been established.

## Next gate

Implement the smallest B variant under `CURRENT_TASK.md`, verify the conditional suppression without changing product semantics, then run bounded real-runtime observation on the affected Mac and preserve any fresh `.ips` / runtime diagnostics.

Do not merge a production behavior change or publish a release from this task. The experiment ends at evidence collection and interpretation unless a separately reconciled task authorizes a production fix.
