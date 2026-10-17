# FloatTabs Current Task

**Task ID:** `FT-CHATGPT-PERF-001`
**Title:** Establish ChatGPT long-running performance measurement
**Status:** `COMPLETED`
**Mode:** `MEASUREMENT_IMPLEMENTATION`

> This task is terminal. The authorization below records the completed implementation scope and grants no further implementation authority.

## Objective

Establish a trustworthy, low-observer-effect measurement seam for long-running ChatGPT Hot runtimes so later performance changes can be evaluated with A/B evidence instead of subjective feel.

This task measures current behavior. It does **not** optimize or change ChatGPT Attention / Web runtime semantics.

## Authority / baseline

- Project rules: `AGENTS.md`.
- Domain/navigation: `docs/architecture/DOMAIN_MAP.md`.
- Existing benchmark authority: `docs/performance/FloatTabs_Stage_5_Resource_Benchmark.md`.
- ChatGPT Attention semantics: `docs/product/FloatTabs_ChatGPT_Attention_Contract_V1.md` and accepted amendments.
- Authorization-time literal `main`: `871f225e8d6ca66a8adefdf766245717ea56de44`.
- Current product semantic baseline: `ec4f7ded7a768bef38933a80af5d7801aa0361d4`; later main drift through the authorization-time HEAD is control-only.

## Authorized scope

- Add DEBUG-only / benchmark-only, content-free, bounded ChatGPT runtime performance measurement.
- Reuse the existing `BenchmarkControlServer` and Real-Mac benchmark harness rather than emitting high-frequency RuntimeDiagnostics events.
- Add only the read-only bridge / WebViewPool / Panel benchmark seams needed to capture current-runtime measurements.
- Extend `tools/benchmark/**`, benchmark reports/self-tests, and focused Swift tests needed to prove measurement correctness and lifecycle safety.
- If isolated-world measurement requires asynchronous benchmark-control response handling, that change is authorized only inside the DEBUG benchmark path.
- Keep one canonical runtime owner; measurement state is diagnostic projection only and must not become product authority.

## Minimum useful evidence

The implementation should obtain a low-overhead equivalent of the following where practical:

- ChatGPT observer callback / scheduling / evaluate counts for the current document;
- evaluate timing aggregate and peak;
- liveness-probe count / latency / failure / recovered-completion counts;
- response-identity-resolution count / timing;
- low-cadence JavaScript round-trip health latency;
- document visibility / generating state plus runtime/document identity needed to reject stale samples;
- existing Real-Mac process CPU / RSS evidence from the benchmark harness.

Exact field representation may be refined if implementation evidence shows a simpler or lower-overhead equivalent.

## Non-goals

This task must not:

- narrow or otherwise redesign the MutationObserver;
- change generation detection or response-identity semantics;
- change liveness watchdog interval, probe authority, or completion behavior;
- gate/remove the existing page-app PerformanceObserver;
- add automatic reload, reset, runtime rejuvenation, or recovery policy;
- change Hot / Warm / Cold semantics or timing;
- change Browser Profiles, cookies, website session/data, persistence, backups, or recovery data;
- change production RuntimeDiagnostics modes or make benchmark counters durable product state;
- claim a root cause or performance improvement from measurement code alone.

## Verification gates

1. Focused unit / real-WKWebView tests prove enable/reset/snapshot behavior, bounded/content-free fields, current-runtime identity, and cleanup across navigation/runtime replacement.
2. Existing ChatGPT Attention / Generation / lifecycle regressions remain green.
3. Benchmark Python compile + self-tests remain green.
4. macOS CI/build remains green for the exact task head.
5. A short Real-Mac smoke run produces correlated FloatTabs/WebContent CPU/RSS plus ChatGPT measurement output.
6. Measurement observer effect is checked by a paired short run with measurement disabled vs enabled. Do not invent a pass threshold before evidence exists; report the observed delta and any noise/limitations.

The 30-minute / 2-hour / 6-hour long-running baseline is the next validation gate after this implementation is proven usable; it is not required to claim this code-construction task complete.

## STOP conditions

STOP and report evidence if:

- measurement requires production persistence or user-data mutation;
- it changes Attention, response, lifecycle, residency, reload, or recovery semantics;
- it introduces periodic production polling or high-frequency RuntimeDiagnostics logging;
- runtime/document identity cannot prevent stale samples from being treated as current;
- task-relevant `main` / Authority changes materially;
- overlapping unique work or another canonical writer appears;
- required focused tests or Real-Mac smoke cannot establish that the measurement seam is usable without material observer effect.

## Completion record

The completion boundary was satisfied and the measurement implementation was accepted:

- Implementation and harness evidence are delivered in PR #122 at semantic implementation HEAD `285361ca3670ca6c112a54b8473ec932d3ad677f`.
- Focused verification and exact-head Benchmark Tool CI, QA DMG, and macOS CI passed.
- Real-Mac paired session `ft-chatgpt-perf-001-smoke-20261017-104716` produced valid disabled/enabled captures with content-free output and stable current runtime/document identity. Web acceptance: `PASS`.
- The disabled capture had a large startup CPU transient, making its whole-window CPU delta non-causal. Active-generation measurement remains unvalidated; neither limitation blocks this measurement-implementation task.

This completed task no longer authorizes implementation work, Observer/Liveness optimization, or a long-running baseline. A 30-minute / 2-hour / 6-hour baseline is the next task decision and requires separate authorization before it begins. Any optimization decision must follow baseline evidence and a subsequent task decision.
