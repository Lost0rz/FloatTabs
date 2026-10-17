# FloatTabs Current Status

**Status date:** 2026-10-17
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: LONG_TERM_DIAGNOSTICS_HISTORY_ACTIVE**

The shell-input refinement `FT-SHELL-INNER-DRAG-001` is completed and merged. Product work has moved to an optional long-running diagnostics/performance-history feature so intermittent slowdown or user-triggered reloads leave enough local evidence for later analysis without turning Diagnostics itself into a performance source.

## Verified baseline

- Current `main`: `7d473a4567ec0a7fa000c6b29dfeab95a36ebab6` — merge commit for PR #123.
- PR #123 — `Refine shell movement to inner Web surface only`: `MERGED` after exact-head CI and Real-Mac acceptance.
- Post-merge macOS CI for the new `main` was still running when this task was authorized; Gate 0 must observe it green before product-code mutation.
- Active task branch: `product/ft-diagnostics-history-001`.
- Active Draft PR: #124 — `Add optional long-term diagnostics history`.

## Diagnostics audit

FloatTabs already has a mature local diagnostics foundation and does not need a second logging platform:

- `RuntimeDiagnostics` emits structured, sanitized JSONL plus macOS Unified Logging.
- Current modes are `off / standard / verbose`; default is `standard`.
- Runtime files live under `~/Library/Application Support/FloatTabs/Diagnostics/Logs/`.
- `RuntimeDiagnosticWriter` currently uses 10 MiB segments, at most 10 managed segments, seven-day retention, buffered/debounced writes, fail-soft writer behavior, and `0700`/`0600` directory/file permissions where supported.
- Settings already expose the diagnostics mode, `Export Recent Diagnostics…`, and `Open Logs Folder`.
- The privacy boundary rejects page/DOM text, prompts, answers, inputs, cookies, auth/tokens, request bodies, raw error text/stacks, window/document titles, IP literals and other sensitive values. URLs are reduced/sanitized.
- Existing tests cover schema/mode gating/export, privacy sanitization, rotation/retention/failure isolation/order, traces and preference persistence.

The missing product capability is not raw log persistence; it is a discoverable long-term observation mode that emits bounded low-cadence performance/health checkpoints and records user recovery actions such as reload so later analysis can correlate the preceding runtime state with recovery.

## Product decision

Reuse the existing Runtime Diagnostics writer/privacy/export pipeline. Do not add a second durable log store or a competing persistence owner.

Settings direction:

```text
Keep local diagnostic history    ON / OFF
Detail level                     Standard / Verbose
                                 retained locally up to 7 days
Long-term performance observation ON / OFF (default OFF)
```

`Keep local diagnostic history` is only a clearer UI projection of the existing `runtimeDiagnosticsMode`; it must not create a second canonical retain-history preference. OFF maps to diagnostics `.off`; enabled detail maps to `.standard` or `.verbose`.

`Long-term performance observation` is a new persisted preference, default OFF. It is effective only when diagnostics are not OFF.

## Long-term observation boundary

When explicitly enabled:

- emit at most one low-cadence checkpoint approximately every 60 seconds for the currently selected Slot;
- never materialize a missing WebView/runtime just to observe it;
- record generic native runtime identity/state for any supported resident Slot;
- for an existing ChatGPT runtime, reuse the already bounded/current-identity-checked health and page-app probes to record only content-free health/aggregate counters;
- record a semantic manual-reload request before `WebViewPool.reload` so the timeline shows when the user intervened;
- preserve existing Web/runtime/navigation identities so stale results cannot be treated as current evidence;
- keep periodic output compact and aggregate-only; do not persist bounded recent page-app event arrays on every periodic tick.

The first version keeps the already proven seven-day writer retention/rotation policy unchanged. Retention-duration expansion can be considered later from real log-volume evidence rather than changing writer policy and sampling behavior simultaneously.

## Data intended for retained checkpoints

Allowed/useful categories:

- timestamp, uptime, session/build/source revision metadata already provided by the diagnostics envelope;
- Slot UUID, safe host/origin, active/visible/pinned/residency facts where available;
- runtime generation / WebView instance identity / navigation generation and phase from existing diagnostic projections;
- resident/runtime availability and relevant presentation/fullscreen facts;
- ChatGPT health-probe outcome and latency;
- document ready/visibility state, conversation shell/composer/loading/error booleans, generating boolean, document epoch;
- page-app aggregate counts such as JavaScript errors, unhandled rejections, resource load failures, HTTP errors, slow resources, lifecycle events and dropped-event count;
- manual reload intent/source and the runtime identity at that recovery boundary;
- existing lifecycle/navigation/process-termination/memory-pressure/recovery events already emitted by Runtime Diagnostics.

Explicitly excluded from this phase:

- prompt/response/page text, DOM/HTML, form/input values, cookies/session/auth data, raw headers/bodies, raw error messages/stacks;
- DEBUG benchmark mutation/detector/response-identity/liveness counters in Release;
- high-frequency MutationObserver/poll/frame logging;
- unreliable per-Slot WebContent CPU/RSS attribution or private WebKit process APIs;
- remote telemetry/upload or automatic AI analysis;
- automatic reload/reset/rejuvenation or any performance optimization.

## Current posture

```text
ACTIVE_PRODUCT_TASK=FT-DIAG-HISTORY-001
LAST_COMPLETED_TASK=FT-SHELL-INNER-DRAG-001
TASK_STATE=ACTIVE
TASK_BRANCH=product/ft-diagnostics-history-001
TASK_PR=124_DRAFT
ROOT_CAUSE=UNKNOWN
PERFORMANCE_OPTIMIZATION_AUTHORIZED=NO
LONG_RUNNING_BASELINE_AUTHORIZED=NO
```

## Acceptance posture

This task must prove that optional periodic observation is bounded, privacy-safe, identity-safe and low overhead. Existing RuntimeDiagnostics privacy/rotation tests remain required, and a short Real-Mac Release smoke must show that enabling observation produces sparse checkpoints and a reload marker without obvious interaction regression or unbounded log growth.
