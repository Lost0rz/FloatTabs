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
- Gate 0: post-merge macOS CI for `main@7d473a4567ec0a7fa000c6b29dfeab95a36ebab6` passed (GitHub run `39002537996`).
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

## Execution progress (2026-10-17)

- Semantic implementation head: `2c0b6b282f0b3b67c3fea315181206e1b20d4b47`.
- Exact-head hosted verification passed: `Build & Test (Apple Silicon arm64)` run `39004297098`; `build-dmg` run `39004297194`.
- A clean-source Release arm64 candidate for the semantic head was built and verified (`source_revision_exact=true`).
- The prior installed app was `0.5.2` build `20`, arm64, source `b21a83fb40bf86a55c8aa6186150797166fc6981`. After normal user quit, a bundle-only rollback archive was validated and the exact Release arm64 candidate for `2c0b6b282f0b3b67c3fea315181206e1b20d4b47` was installed and launched (`source_revision_exact=true`).
- Real-Mac Gate 5 was started on the exact Release candidate. Through the existing Settings UI, `Keep local diagnostic history` was confirmed ON, detail was `Standard`, and `Long-term performance observation` was enabled (its default had been OFF). Seven-day writer retention and rotation policy were unchanged.
- The observation baseline at 2026-10-17 05:28:36 UTC was one JSONL file, `runtime-20261017-001.jsonl`, at 254,234 bytes. At 05:38:02 UTC it remained one file at 304,989 bytes (+50,755 bytes). Nine `diagnostics.performance_checkpoint` records were written at 05:29:32, 05:30:35, 05:31:38, 05:32:41, 05:33:44, 05:34:47, 05:35:50, 05:36:50, and 05:37:53 UTC (60–63-second intervals; 13,073 bytes total, 1,448–1,455 bytes each). No `web_runtime.created`, `web_runtime.create.begin`, `web_runtime.released`, or manual-reload boundary event occurred during this observation window.
- Each observed checkpoint captured the single pre-existing resident runtime (`resident_slot_count=1`, `capture_availability=captured`), but the page projection remained `other_or_unknown`; the ChatGPT origin check was false and `slot_visible=false`. `panel_visible` became false at the 05:33:44 checkpoint and remained false in later checkpoints. The user was asked to open the existing ChatGPT Slot, but has not confirmed that it is selected and visible. The main menu-bar panel is not exposed through the available CUA accessibility controls.
- The existing `Export Recent Diagnostics…` flow succeeded and wrote `/tmp/FloatTabs-Diagnostics-20261017-053521.jsonl`. That snapshot contains six checkpoints and no manual-reload event. Structural inspection found no prompt/response/DOM/input/cookie/auth field names; all URL/origin projections had empty path, query, and fragment; no string value exceeded 256 characters. Values were not printed or retained in this report.
- During the observation window the log grew by 50,755 bytes overall, of which 13,073 bytes were checkpoint records; the remaining growth includes existing UI/focus diagnostics and is not attributed to periodic sampling. Short CPU snapshots ranged from 0.0% to 13.8%, with cumulative process CPU increasing from 2.48s to 3.53s across samples; those samples include UI activity and do not isolate observation overhead. Several panel presentation/dismissal and focus-failure events occurred during the attempted panel interaction; cause and user-visible impact remain unknown.
- No Browser Profile/session reset, deletion, or intentional mutation occurred. The already-resident Slot runtime remained in use, so incidental profile reads by the app are not independently observable. `USER_DATA_TOUCHED=YES`: the opt-in preference was changed through Settings, diagnostics logs grew, and a temporary local diagnostics export was created. Gate 5 remains incomplete because a normal ChatGPT Slot, manual reload boundary, post-reload checkpoint, and normal page/focus responsiveness have not been verified.
- `CURRENT_TASK.md` remains `ACTIVE`; PR #124 remains Draft. Reconcile terminal state only after Gate 5 has an observed result.

## Acceptance posture

This task must prove that optional periodic observation is bounded, privacy-safe, identity-safe and low overhead. Existing RuntimeDiagnostics privacy/rotation tests remain required, and a short Real-Mac Release smoke must show that enabling observation produces sparse checkpoints and a reload marker without obvious interaction regression or unbounded log growth.
