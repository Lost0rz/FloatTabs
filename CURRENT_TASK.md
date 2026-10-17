# FloatTabs Current Task

**Task ID:** `FT-DIAG-HISTORY-001`
**Title:** Add optional long-running diagnostics/performance history
**Status:** `ACTIVE`
**Mode:** `DIAGNOSTICS_PRODUCT_IMPLEMENTATION`

## Objective

Make local diagnostic history explicit and useful for long-running performance observation without creating a second logging platform or adding high-frequency observer overhead.

The user should be able to understand whether local diagnostic history is kept, opt into low-cadence long-term performance observation, run FloatTabs normally for a period, and later export sanitized evidence for analysis. Manual reloads must remain visible as recovery boundaries so an intermittent slowdown is not erased from the timeline merely because the user reloads the page.

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
5. Preserve `Export Recent Diagnostics…` and `Open Logs Folder`.

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

### Gate 5 — Real-Mac Release smoke

On the exact Release task build:

- enable diagnostics Standard and long-term performance observation;
- keep a normal ChatGPT Slot running long enough to observe several scheduled checkpoints;
- confirm checkpoint cadence is sparse/approximately one per minute rather than callback-level output;
- manually reload once and confirm a reload boundary appears before the following navigation/recovery evidence;
- export the retained diagnostics and inspect that no prompt/response/DOM/input/cookie/auth content is present;
- confirm normal Tab, focus, reload and page interaction remain responsive;
- report observed log growth and any obvious CPU/UI impact without inventing a pass threshold.

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
- long-term observation is opt-in, low-cadence, bounded and Release-capable;
- manual reload boundaries are preserved in diagnostic history;
- existing writer retention/privacy/export authority is reused unchanged;
- focused and full automated verification plus exact-head CI pass;
- Real-Mac Release smoke establishes sparse usable output with no observed content leak or obvious interaction regression;
- implementation is remotely delivered through one Draft PR;
- terminal Control Alignment reconciles STATUS/TASK and PR/workspace lifecycle.
