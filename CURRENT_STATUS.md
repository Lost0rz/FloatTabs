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

- Earlier semantic implementation head: `2c0b6b282f0b3b67c3fea315181206e1b20d4b47`.
- Current semantic implementation head: `c8e77d16c1dc349eeeedfb96058e2442d6c9e4de`, including the bounded focus-failure identity probe. Full XCTest (1317/1317), Debug and Release arm64 builds passed. Exact-head hosted macOS CI run `39027508459` and QA DMG run `39027508440` passed; PR #124 remains OPEN / Draft.
- Exact-head hosted verification passed: `Build & Test (Apple Silicon arm64)` run `39004297098`; `build-dmg` run `39004297194`.
- A clean-source Release arm64 candidate for the semantic head was built and verified (`source_revision_exact=true`).
- The prior installed app was `0.5.2` build `20`, arm64, source `b21a83fb40bf86a55c8aa6186150797166fc6981`. After normal user quit, a bundle-only rollback archive was validated and the exact Release arm64 candidate for `2c0b6b282f0b3b67c3fea315181206e1b20d4b47` was installed and launched (`source_revision_exact=true`).
- Real-Mac Gate 5 was started on the exact Release candidate. Through the existing Settings UI, `Keep local diagnostic history` remained ON and detail remained `Standard`. Long-term observation was ON during the smoke window (its original default was OFF), then returned to OFF through Settings at about 05:45:41 UTC after the capture was blocked. Seven-day writer retention and rotation policy were unchanged.
- The observation baseline at 2026-10-17 05:28:36 UTC was one JSONL file, `runtime-20261017-001.jsonl`, at 254,234 bytes. At 05:46:23 UTC it remained one file at 315,174 bytes (+60,940 bytes), with no rotation. Sixteen `diagnostics.performance_checkpoint` records were written from 05:29:32 through 05:45:14 UTC at 60–63-second intervals; the records totaled 23,258 bytes and measured 1,448–1,455 bytes each. No `web_runtime.created`, `web_runtime.create.begin`, `web_runtime.released`, or manual-reload boundary event occurred during the observation window. After disabling observation, no further checkpoint appeared through 05:46:23 UTC, beyond the next expected interval.
- Each observed checkpoint captured the single pre-existing resident runtime (`resident_slot_count=1`, `capture_availability=captured`), but the page projection remained `other_or_unknown`; the ChatGPT origin check was false and `slot_visible=false`. `panel_visible` was false from the 05:33:44 checkpoint onward. The user was asked to open the existing ChatGPT Slot but did not confirm it was selected and visible. The main menu-bar panel was not exposed through the available CUA accessibility controls.
- The existing `Export Recent Diagnostics…` flow succeeded and wrote `/tmp/FloatTabs-Diagnostics-20261017-053521.jsonl`. That snapshot contains six checkpoints and no manual-reload event. Structural inspection found no prompt/response/DOM/input/cookie/auth field names; all URL/origin projections had empty path, query, and fragment; no string value exceeded 256 characters. Values were not printed in this report.
- The log grew by 60,940 bytes overall, of which 23,258 bytes were checkpoint records; the remaining growth includes existing UI/focus diagnostics and is not attributed to periodic sampling. Short CPU snapshots ranged from 0.0% to 13.8%; cumulative process CPU rose from 2.48s to 3.53s across samples within the panel-interaction period and then to 4.18s by 05:42:43 UTC. These samples include UI activity and do not isolate observation overhead. Several panel presentation/dismissal and focus-failure events occurred during attempted panel interaction; cause and user-visible impact remain unknown.
- In the first 05:28–05:46 UTC smoke window, no Browser Profile/session reset, deletion, or intentional mutation occurred. The already-resident Slot runtime remained in use, so incidental profile reads by the app are not independently observable. `USER_DATA_TOUCHED=YES`: the opt-in preference was enabled and then restored OFF through Settings, diagnostics logs grew, and a temporary local diagnostics export was created. At that stage Gate 5 remained incomplete because the normal ChatGPT Slot, reload boundary and post-reload checkpoint had not been verified.
- Gate 5 continuation (2026-10-17 07:12–07:28 UTC): Settings showed local history ON, detail Standard, and long-term observation enabled during sampling, then returned OFF. Nine additional checkpoints were emitted at 61–63-second intervals (22,602 bytes total; 2,511 bytes average). They used the existing resident runtime; resident count stayed 2, with no runtime creation/release caused by sampling. The 07:17:27 UTC manual-reload boundary preceded navigation commit at 07:17:28 and a captured/current ChatGPT checkpoint at 07:17:41. The exported snapshot contained 870 records, 50 event types and 25 checkpoints; structural privacy inspection found no forbidden content-bearing keys, sanitized origins had empty path/query/fragment, and the maximum string length was 40. After observation was turned off, no later checkpoint appeared through 07:23:14 UTC.
- Gate 5 did not pass. The user reported that Tab focus did not respond. A screenshot at 07:28:02 UTC shows the Runtime Diagnostics Settings window with observation OFF and the adjacent Slot as a blank white surface. The live log records a network-category `navigation.failed` (`NSURLErrorDomain`, code `-1001`) at 07:22:04 UTC; its Slot/runtime identity matches a later manual-reload boundary at 07:25:57 UTC, whose captured navigation phase was already failed. The later boundary's actor is not identified by the event, and the executor did not invoke another reload in this continuation. Seventeen `web_focus.failed` and seventeen `presentation_focus.failed` events were logged from 07:24:40 through 07:28:36 UTC; those records do not carry enough runtime identity to attribute them to the screenshot's visible Slot. The user-visible blank surface and focus report block the required no-obvious-regression acceptance. The reload/navigation failure is direct diagnostic evidence, not a root-cause finding; `ROOT_CAUSE=UNKNOWN`. No further app interaction, reload, restart, or settings change was performed after the report. `USER_DATA_TOUCHED=YES`; no Browser Profile/session reset, deletion, or intentional mutation was performed, though incidental website/session activity cannot be excluded. PR #124 remains OPEN / Draft and the task remains ACTIVE pending a separately authorized diagnosis or correction and a new Gate 5 result.
- `CURRENT_TASK.md` remains `ACTIVE`; PR #124 remains Draft. Gate 5 now has an observed failure; reconcile terminal state after a separately authorized diagnosis/correction and a new Gate 5 result.

## Incident diagnosis and next authorized gate (2026-10-17)

A read-only offline correlation of the preserved Gate 5 live JSONL established that the evidence is still insufficient to select a product correction, but it is sufficient to authorize one bounded correlation probe.

- The failed navigation is identified as Slot `00B689D3-8403-43D2-A571-949FD8FA827B`, runtime generation 1, WebView `0F7690AE-2EAB-4D82-9477-B228DBD42606`, navigation generation 1.
- Later presentation traces select that same Slot, and no runtime release/recreation or WebContent-process termination is recorded across the incident window.
- The paired `web_focus.failed` / `presentation_focus.failed` records lack runtime/WebView/navigation identity, so same-physical-runtime attribution at each focus failure is not proven.
- The 07:25:57 reload boundary belongs to an explicit production reload command path; `WebViewPool.reload(slotID:)` is not used by lifecycle or automatic recovery, so the existing `manual/user_requested` semantics are accepted.
- PR #124 does not change existing focus logic, Tab selection, key-window ownership, navigation policy, WebView lifecycle/residency, or recovery policy. Long-term observation causality is weakened by the absence of checkpoints during the later focus-failure window, but it is not falsified because the navigation failure occurred earlier.

```text
EVIDENCE_SUFFICIENCY=INSUFFICIENT
MISSING_FACT=ACTIVE_SLOT_RUNTIME_AND_NAVIGATION_IDENTITY_AT_PRESENTATION_FOCUS_FAILURE
BLOCKED_DECISION=WEB_RUNTIME_NAVIGATION_FAULT_VS_PRESENTATION_FOCUS_FAULT_BOUNDARY
INCIDENT_PROBE_AUTHORIZED=YES
INCIDENT_PROBE_SCOPE=PRESENTATION_FOCUS_FAILURE_IDENTITY_ONLY
FOCUS_IDENTITY_PROBE=IMPLEMENTED_VERIFIED
GATE5=PRIOR_FAILURE;CURRENT_RERUN=BLOCKED_BEFORE_OBSERVATION
ROOT_CAUSE=UNKNOWN
```

The bounded focus-failure identity probe was implemented in semantic candidate `c8e77d16c1dc349eeeedfb96058e2442d6c9e4de` and passed its automated verification gate. A later exact-candidate install/launch was attempted, but CUA could not bind the FloatTabs UI; no Settings change, observation window, or Gate 5 interaction was performed. Gate 5 remains unpassed, with no new candidate presentation/focus failure established. The current authorized scope refinement is the user-managed daily-JSONL handoff below; it authorizes no focus, navigation, recovery, or performance correction.

## Acceptance posture

This task must prove that optional periodic observation is bounded, privacy-safe, identity-safe and low overhead. Existing RuntimeDiagnostics privacy/rotation tests remain required, and a short Real-Mac Release smoke must show that enabling observation produces sparse checkpoints and a reload marker without obvious interaction regression or unbounded log growth.

## User-managed saved-log and offline-analysis refinement (2026-10-17)

The active `FT-DIAG-HISTORY-001` task and Draft PR #124 now also support this user-owned workflow: sanitized JSONL remains on this Mac for up to seven days; the user opens the canonical Logs folder, selects one or more date-grouped JSONL files, and may provide those files later for offline AI analysis. FloatTabs does not run resident AI monitoring, upload logs automatically, copy logs to another store, or rewrite their contents. `Export Recent Diagnostics…` remains available.

Settings will label the folder action `Open Saved Logs Folder` and explain that logs are normally grouped into one JSONL file per UTC day, large daily logs may be split automatically, and the user can select one or more days for later analysis. Opening the folder must ensure `RuntimeDiagnosticWriter.defaultDirectory` exists before asking Finder to open it.

This refinement leaves `RuntimeDiagnosticWriter` ownership, daily segmentation, the 10 MiB segment limit, `maxSegments`, seven-day retention, checkpoint cadence, and privacy rules unchanged. The revised Gate 5 contract is recorded in `CURRENT_TASK.md`; the historical Gate 5 failure remains a failure and `ROOT_CAUSE=UNKNOWN`.
