# FloatTabs Current Task

**Task ID:** `FT-DIAG-HISTORY-001`
**Title:** Add optional long-running diagnostics/performance history
**Status:** `ACTIVE`
**Mode:** `DIAGNOSTICS_PRODUCT_IMPLEMENTATION`

## Objective

Make local diagnostic history explicit and useful for long-running performance observation without creating a second logging platform or adding high-frequency observer overhead.

The user should be able to understand whether local diagnostic history is kept, opt into low-cadence long-term performance observation, run FloatTabs normally for a period, and later choose locally retained JSONL files for offline analysis. Manual reloads must remain visible as recovery boundaries so an intermittent slowdown is not erased from the timeline merely because the user reloads the page.

## Authority / baseline

- Project rules: `AGENTS.md`.
- Domain navigation: `docs/architecture/DOMAIN_MAP.md`.
- Diagnostics contract: `docs/product/FloatTabs_Runtime_Diagnostics_Contract_V1.md`.
- Existing Settings information architecture and Runtime Diagnostics Settings surface on current `main`.
- Authorization-time `main`: `7d473a4567ec0a7fa000c6b29dfeab95a36ebab6`.
- PR #123 is merged at that baseline after Real-Mac acceptance and exact-head CI.
- Post-merge macOS CI for that merge commit was still running at authorization; observe it green before product-code mutation.
- Authorized task branch: `product/ft-diagnostics-history-001`.
- Draft PR: #124 — `Add optional long-term diagnostics history`.

## Audited baseline

Existing production diagnostics already provide:

- structured schema-v1 JSONL events with session/trace/sequence identity;
- `off / standard / verbose` collection gating;
- seven-day local retention using 10 MiB segments and at most 10 managed segments;
- sanitized export and Open Logs Folder actions;
- strict privacy filtering at both diagnostics and persistence boundaries;
- event coverage for app/panel/focus/fullscreen/tab/WebView/lifecycle/navigation/attention/recovery boundaries;
- bounded ChatGPT incident health and page-app probes with current runtime/navigation identity guards;
- focused tests for diagnostics mode/schema/export, privacy, rotation/retention/failure isolation/order, traces and preference persistence.

The DEBUG-only ChatGPT benchmark measurement counters remain a separate benchmark capability and are not production logging authority.

## Product contract for this task

### Settings

Refine the existing Advanced → Runtime Diagnostics surface without creating competing settings:

1. Make the existing `runtimeDiagnosticsMode` understandable as local-history ownership:
   - diagnostics OFF = no Runtime Diagnostics event output/history;
   - enabled = Standard or Verbose detail;
   - communicate that retained JSONL history is local, sanitized and currently kept for up to seven days.
2. The UI may present this as an explicit `Keep local diagnostic history` enable/disable control plus `Detail level: Standard / Verbose`, but it must project the existing `runtimeDiagnosticsMode` rather than introducing a second canonical retain-history boolean.
3. Add one new preference: `longTermPerformanceObservationEnabled`, default `false`.
4. Add a `Long-term performance observation` control. It is effective only while diagnostics mode is not `.off` and must clearly state that it records low-frequency content-free health/performance checkpoints for later analysis.
5. Preserve `Export Recent Diagnostics…`.
6. Provide `Open Saved Logs Folder` for the existing canonical Logs directory. Its description must state that sanitized diagnostics are saved locally for up to seven days, normally grouped into one JSONL file per UTC day with automatic splitting for large daily logs, and that the user can choose one or more days for later offline analysis.

### User-managed saved-log and offline-analysis refinement (2026-10-17)

This is an authorized scope refinement of the same task and PR #124. The product workflow is local rolling save → user-selected daily JSONL files → optional later offline AI analysis. FloatTabs must not require AI to remain running, analyze logs continuously, upload automatically, or change log contents as part of opening the folder.

The Settings description is:

> Sanitized diagnostics are saved on this Mac and retained for up to 7 days. Logs are normally grouped into one JSONL file per UTC day; large daily logs may be split automatically. Open the saved logs folder and choose one or more daily files to provide later for offline AI analysis.

The action label is `Open Saved Logs Folder`. Keep `Export Recent Diagnostics…` unchanged and available.

The existing `AppCoordinator` open-folder seam must continue to use `RuntimeDiagnosticWriter.defaultDirectory`. Before invoking Finder, ensure that directory exists. This is a folder-opening responsibility only: do not change `RuntimeDiagnosticWriter` ownership, segment naming/rotation, 10 MiB segment size, `maxSegments`, seven-day retention, checkpoint cadence, or privacy behavior; do not copy, export, or rewrite log content in this seam.

Focused tests must cover the Settings action title and description, invocation of its existing handler, and safe creation of a missing directory if an ensure-directory helper is introduced. Keep the existing privacy, rotation, and retention tests unchanged and passing. No focus identity probe, Web runtime, navigation/recovery, Browser Profile/session, or performance behavior change is authorized by this refinement.

### Periodic observation

When `longTermPerformanceObservationEnabled == true` and diagnostics mode is enabled:

- use an approximately 60-second cadence;
- allow at most one periodic observation operation in flight at a time;
- observe the currently selected Slot only in this first version;
- never create/materialize a WebView/runtime solely for diagnostics;
- if no current runtime exists, record only a bounded availability/native checkpoint or skip the Web probe rather than creating one;
- reuse existing owner projections such as `WebViewPool.diagnosticSnapshotFields` and the current-identity-guarded ChatGPT health/page-app probes;
- periodic ChatGPT page-app output must use compact aggregate counters, not repeat the full bounded recent-event list on every tick;
- stale/replaced runtime/navigation results must remain identifiable and must not be represented as current success.

A clean implementation may introduce one small observation/scheduling coordinator or equivalent bounded component. It must remain read-only and must not become a Tab/Web/runtime authority.

### Checkpoint data

Retain only bounded diagnostic facts needed for later correlation, including where available:

- existing event envelope/session/build/source metadata;
- Slot UUID and sanitized host/origin;
- active/visible/residency/presentation facts;
- runtime generation, WebView instance identity, navigation generation/phase;
- runtime availability/resident count and relevant fullscreen/presentation facts;
- ChatGPT health-probe outcome/latency, document epoch, generating state;
- document ready/visibility state and shell/composer/loading/error booleans;
- page-app aggregate counters: JavaScript errors, unhandled rejections, resource-load failures, HTTP errors, slow resources, lifecycle events, dropped-event count, and capability/availability flags.

Do not add content-bearing fields merely because the sanitizer might remove them later.

### Reload correlation

Before a user/manual `reloadSlot` mutates the runtime/navigation state, emit one standard semantic diagnostic event carrying the Slot ID and current safe runtime/navigation diagnostic projection plus a bounded reload source/reason.

Do not delay reload waiting for a Web/JavaScript probe. The prior periodic checkpoint plus the reload boundary must be enough to reconstruct the pre/post intervention timeline. Existing navigation/recovery events remain the post-reload evidence.

## Retention decision

Keep `RuntimeDiagnosticWriter` retention/rotation defaults unchanged in this task:

- 10 MiB per segment;
- at most 10 managed segments;
- seven-day retention.

Do not add 30/90-day retention or redesign writer storage in the same task. Revisit retention only after actual long-term checkpoint volume is known.

## Privacy / non-goals

Never persist:

- prompt/response/page text, DOM/HTML or form/input values;
- cookies, website session data, auth/tokens, request/response bodies or raw headers;
- raw error messages/stacks;
- window/document titles, IP literals, precise location or other existing forbidden fields.

This task must not:

- upload telemetry or logs remotely;
- automatically send logs to ChatGPT/AI;
- implement periodic AI analysis;
- promote DEBUG benchmark mutation/detector/response-identity/liveness counters into Release;
- add per-mutation/per-frame/high-frequency diagnostics;
- use private WebKit APIs or claim reliable per-Slot WebContent CPU/RSS attribution;
- change Browser Profiles, cookies, sessions, persistence/backups or user website data;
- change WebView lifecycle/residency/recovery behavior;
- automatically reload/reset/rejuvenate runtimes;
- implement a performance optimization or claim a root cause.

`ROOT CAUSE UNKNOWN` remains the correct performance conclusion.

## Verification gates

### Gate 0 — baseline / ownership

Before product-code mutation:

- refresh `main` and task branch;
- verify the post-merge macOS CI for `main@7d473a4567ec0a7fa000c6b29dfeab95a36ebab6` is green;
- inspect local worktree and preserve unknown local/untracked work;
- stop on material Authority drift or overlapping unique writer work.

### Gate 1 — preference / Settings behavior

Focused tests must prove:

- long-term observation defaults OFF and persists when changed;
- local-history UI remains a projection of `runtimeDiagnosticsMode`, not a competing retain boolean;
- observation is ineffective when diagnostics mode is OFF;
- existing export/open-folder actions remain available;
- Settings information architecture remains Advanced → Runtime Diagnostics.

### Gate 2 — observation correctness

Tests with controllable clock/probes must prove:

- disabled mode schedules/emits no periodic checkpoints;
- enabled mode emits only at the bounded cadence;
- no overlapping periodic probe operations occur;
- no missing WebView is materialized;
- exact current runtime/navigation identity is preserved and stale results are not accepted as current;
- generic native fields remain useful for non-ChatGPT active Slots;
- ChatGPT periodic fields use bounded health/page-app aggregate data only;
- stopping/termination cancels future sampling cleanly.

### Gate 3 — reload evidence

Tests must prove the manual reload diagnostic boundary is recorded before the actual reload call and contains only sanitized/current diagnostic identity fields. Reload behavior and focus after reload must remain unchanged.

### Gate 4 — existing diagnostics safety

Run the existing Runtime Diagnostics schema/mode/export, privacy, rotation/retention, trace and AppPreferences tests. No weakening of the existing privacy contract is allowed.

Then run the broader project macOS tests plus Debug and Release arm64 builds and exact-head hosted CI.

### Gate 5 — Real-Mac Release saved-log handoff

On the exact Release task build, verify the complete user-managed workflow:

1. In Settings, enable local diagnostic history at Standard and enable long-term performance observation. Use a normal ChatGPT Slot for several scheduled checkpoints.
2. Confirm a date-grouped JSONL log exists in the canonical Logs directory. Logs are normally grouped into one JSONL file per UTC day and may split automatically when a daily log is large. Check that checkpoints remain sparse, approximately one per minute.
3. Perform one normal manual Reload and confirm the reload boundary precedes subsequent navigation/recovery evidence.
4. Use `Open Saved Logs Folder` and confirm Finder opens `RuntimeDiagnosticWriter.defaultDirectory`, creating the directory first when it did not exist.
5. Select one or more relevant daily JSONL files and verify they contain the expected sparse checkpoint, reload, and runtime/navigation evidence. Keep the file content private during inspection.
6. Confirm the selected files can be provided later for offline AI analysis. No AI process must remain running, and FloatTabs must not upload or analyze files automatically.
7. Structurally inspect the saved logs for the existing privacy boundary. Confirm normal Tab, focus, reload, and page interaction remain responsive; report observed log growth and qualitative UI/CPU impact without inventing a pass threshold.

Keep the existing seven-day retention and rotation behavior. `Export Recent Diagnostics…` remains available as a separate on-demand action; it does not replace user selection of daily files.

### Gate 5 execution result (2026-10-17)

Gate 5 was attempted on the exact Release task build and did not pass. During the 07:12–07:23 UTC observation window, nine additional checkpoints were recorded at 61–63-second intervals, totaling 22,602 bytes (2,511 bytes average). Observation was turned OFF through Settings, and no later checkpoint appeared through 07:23:14 UTC. The retained export passed the structural content-free inspection recorded in `CURRENT_STATUS.md`. The first authorized manual-reload boundary at 07:17:27 UTC preceded navigation commit and a captured/current ChatGPT checkpoint.

The user reported that Tab focus did not respond and provided a screenshot captured at 07:28:02 UTC showing a blank white Slot beside Runtime Diagnostics Settings. The live log contains a network-category `navigation.failed` (`NSURLErrorDomain`, `-1001`) at 07:22:04 UTC and a later manual-reload boundary at 07:25:57 UTC while that Slot/runtime was already in a failed navigation phase. The later boundary's actor is not attributable from the diagnostic event; the executor did not invoke another reload during this continuation. Focus-failure records were also observed, but do not carry enough runtime identity to tie them to the screenshot's Slot. These observations block the required normal-display/focus acceptance and do not establish a root cause (`ROOT_CAUSE=UNKNOWN`). No product fix or further runtime interaction was authorized by this task; keep the PR Draft and task ACTIVE until diagnosis/correction is separately authorized and Gate 5 is rerun.

## STOP conditions

STOP and report evidence if:

- safe implementation requires a second durable logging store/authority;
- periodic observation materially alters Web runtime, lifecycle, attention or page semantics;
- sampling requires high-frequency callbacks or synchronous disk I/O on MainActor;
- current-runtime identity cannot reject stale probe results;
- privacy tests reveal content/user-data persistence;
- reload must wait materially on JavaScript/health probes;
- log output becomes unbounded or materially perturbs the behavior being observed;
- post-merge baseline CI or required exact-head verification fails;
- overlapping unique writer work appears.

## Completion boundary

This task is complete only when:

- Settings clearly expose local history semantics and optional long-term observation;
- Settings and Finder support the user-managed daily-JSONL handoff for later offline analysis;
- long-term observation is opt-in, low-cadence, bounded and Release-capable;
- manual reload boundaries are preserved in diagnostic history;
- existing writer retention/privacy/export authority is reused unchanged;
- focused and full automated verification plus exact-head CI pass;
- Real-Mac Release smoke establishes sparse usable output with no observed content leak or obvious interaction regression;
- implementation is remotely delivered through one Draft PR;
- terminal Control Alignment reconciles STATUS/TASK and PR/workspace lifecycle.

## Incident evidence gate and bounded probe authorization (2026-10-17)

The read-only incident diagnosis following the failed Gate 5 result is accepted as evidence. It established:

- `EVIDENCE_SUFFICIENCY=INSUFFICIENT` for selecting a product correction;
- the 07:22:04 `navigation.failed` event belongs to Slot `00B689D3-8403-43D2-A571-949FD8FA827B`, runtime generation 1, WebView `0F7690AE-2EAB-4D82-9477-B228DBD42606`, navigation generation 1;
- subsequent presentation traces select that same Slot, but the paired focus-failure records do not carry physical runtime/navigation identity, so same-runtime attribution at the failure boundary is not proven;
- no runtime recreation/release or WebContent-process termination was observed across the incident window;
- `WebViewPool.reload(slotID:)` production callsites are explicit user/command paths; recovery/lifecycle uses separate paths, so the existing `manual/user_requested` event semantics are valid;
- no evidence establishes that long-term observation caused the failure. Observation causality remains weakened but not falsified; `ROOT_CAUSE=UNKNOWN`.

`MISSING_FACT`: the active Slot's exact runtime/WebView identity and navigation generation/phase at each presentation focus-failure boundary.

`BLOCKED_DECISION`: whether the focus failures belong to the already-failed WebView/navigation context or to a separate presentation/focus condition, which determines the minimum safe fault boundary.

### Authorized probe — single existing failure boundary only

The same task and PR were re-authorized for one bounded diagnostic-instrumentation correction before Gate 5 was rerun.

Implement the probe at the existing `presentation_focus.failed` event in `PanelController`, because that presentation owner already has access to `TabStore` and `WebViewPool` identity projections. Do not move Web runtime ownership into `WebFocusRouter` and do not create a second failure event stream.

On `presentation_focus.failed`, add only a read-only correlation projection derived synchronously from the already-current owners:

- active/selected Slot ID;
- whether an active Slot exists;
- whether a resident runtime exists for that Slot;
- `runtime_generation` when available;
- `webview_instance_id` when available;
- `navigation_generation` when available;
- `navigation_phase` when available.

Use `tabStore.activeTabID` plus the existing `webViewPool.existingWebView(for:)` / `diagnosticSnapshotFields(for:)` seam or an equally bounded existing projection. A missing Slot/runtime must produce a bounded availability fact; it must not create/materialize a WebView.

The probe must not:

- run JavaScript or a page health probe;
- add timers, retries, async work, polling, or high-frequency output;
- change focus attempts, focus ownership, Tab selection, navigation, WebView lifecycle, residency, recovery, reload, window/key-window behavior, or presentation timing;
- add content-bearing fields;
- change `web_focus.failed` semantics solely to obtain Web runtime ownership;
- change the long-term observation cadence/retention/settings implementation;
- attempt a product fix or claim root cause.

### Probe verification gate

Before a new Real-Mac Gate 5 attempt:

1. Add focused regression coverage proving a presentation focus failure includes the active Slot and current runtime/navigation identity when resident.
2. Add focused coverage for missing active Slot / missing resident runtime proving no WebView is materialized.
3. Preserve existing focus result, trace, generation, owner and `dom_input_unavailable` semantics.
4. Run the relevant presentation/focus and Runtime Diagnostics privacy tests.
5. Run the broader macOS XCTest suite plus Debug and Release arm64 builds.
6. Push to the same branch / PR #124 and require exact-head hosted CI success.
7. Keep PR #124 Draft.

The focus-failure identity probe was completed in semantic candidate `c8e77d16c1dc349eeeedfb96058e2442d6c9e4de` and passed its automated verification gate. The attempted Real-Mac rerun could not proceed because CUA did not expose a bindable FloatTabs UI; no Gate 5 observation or product-level result was established. `ROOT_CAUSE=UNKNOWN` remains unchanged. The current authorized implementation is the saved-log/offline-analysis workflow refinement above, with no focus, navigation, recovery, or performance correction.

STOP before expanding beyond the authorized saved-log/offline-analysis workflow if implementation requires a second durable logging authority, new runtime ownership, new asynchronous Web work, a broader logging redesign, or any focus, navigation, recovery, or performance behavior correction.
