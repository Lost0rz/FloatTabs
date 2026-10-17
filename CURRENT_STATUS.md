# FloatTabs Current Status

**Status date:** 2026-10-17
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: CHATGPT_PERFORMANCE_MEASUREMENT_ACTIVE**

The post-closeout global audit has identified a measurement gap around long-running ChatGPT Hot runtimes. FloatTabs is entering a measurement-first phase before any Observer/Liveness optimization.

## Verified baseline

- Authorization-time literal `main`: `871f225e8d6ca66a8adefdf766245717ea56de44`.
- Current product semantic baseline: `ec4f7ded7a768bef38933a80af5d7801aa0361d4`; later drift through the authorization-time main HEAD is control-only.
- PR #116 — `fix/residency-lifecycle-semantics`: `MERGED`.
- PR #102 — historical MemoX implementation evidence only: `ARCHIVE_ONLY / CLOSED / UNMERGED`.
- Fresh PR inventory before this task found no open overlapping PR.

## Audit result relevant to this phase

Confirmed code-level costs / measurement needs:

- ChatGPT Attention uses a full-document coalesced MutationObserver and provider DOM generation detection.
- Generation/liveness paths contain DOM work whose actual long-running cost is not yet quantified.
- ChatGPT page-app diagnostics include continuously installed observers whose production impact has not yet been isolated.
- Hot runtimes can remain resident for long periods; current evidence does not quantify runtime-age vs CPU/RSS/JS-latency behavior.
- Existing functional regression coverage is strong, but the Real-Mac benchmark does not currently expose trustworthy ChatGPT JS/observer latency or long-running soft-renderer degradation.

`ROOT CAUSE UNKNOWN` remains the correct incident conclusion. These findings justify measurement, not a performance-fix claim.

## Measurement design decision

- High-frequency performance counters must not be emitted as ordinary RuntimeDiagnostics events because the measurement path itself would add sanitization/encoding/queue/file overhead.
- Reuse the existing DEBUG-only `BenchmarkControlServer` and Real-Mac benchmark tools.
- Keep high-frequency counters bounded and in-memory / isolated-world only; expose read-only snapshots on demand.
- Measurement must remain content-free and tied to current runtime/document identity so stale samples cannot be accepted as current evidence.
- Production Attention, response, residency, persistence, recovery and user-data semantics remain unchanged in this phase.

## Domain baseline

- `WebViewPool` / Web own runtime identity, lifecycle, health and recovery.
- `ChatGPTAttentionBridge` remains an observation source; `WebAttentionCoordinator` remains attention-state authority.
- `PanelController` may expose read-only benchmark projection but must not become a new runtime/attention authority.
- Diagnostics remain evidence only.

## Current posture

```text
ACTIVE_PRODUCT_TASK=FT-CHATGPT-PERF-001
TASK_MODE=MEASUREMENT_IMPLEMENTATION
TASK_BRANCH=perf/ft-chatgpt-perf-001
ROOT_CAUSE=UNKNOWN
PERFORMANCE_OPTIMIZATION_AUTHORIZED=NO
MEASUREMENT_IMPLEMENTATION_AUTHORIZED=YES
```

## Deferred follow-ups

The following remain explicitly deferred until baseline evidence exists:

- removing unnecessary response-root work while generating;
- minimal generation-only liveness probe;
- narrowing MutationObserver scope;
- gating page-app PerformanceObserver;
- runtime rejuvenation or any automated reload/reset behavior.

## Next milestone

Implement and verify the `FT-CHATGPT-PERF-001` measurement seam, run a short Real-Mac observer-effect smoke, then use the resulting measurement capability for the first long-running baseline before selecting any performance optimization.
