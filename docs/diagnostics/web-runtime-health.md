# Web Runtime Health Diagnostics Contract

This contract adds observation to the existing WebKit runtime. It does not
change navigation authority, reload or Home behavior, session storage,
residency policy, fullscreen recovery, or content-process recovery.

## Correlation

- `runtime_generation` is a process-local, monotonically increasing integer
  assigned when the pool creates a `WKWebView`. Reuse preserves it; release,
  rendering rebuild, and later recreation produce a new value. It is diagnostic
  metadata only and is never persisted.
- `navigation_generation` advances on each `didStartProvisionalNavigation` for
  that runtime. Commit, finish, failure, and watchdog events carry the current
  generation. Delayed callbacks must match both runtime and navigation identity.
- Reload and Home requests are recorded at their existing user-action
  boundaries with the runtime and navigation generations observed before the
  request, active/loading state, and no URL.

## Stall observation

- A single one-shot watchdog is armed for a provisional navigation. If no commit,
  finish, failure, process termination, newer navigation, release, or rebuild is
  observed for 120 seconds, record one `navigation.stalled` event.
- Reload and Home also arm a one-shot 120-second no-progress check. A subsequent
  provisional start replaces that check with the navigation watchdog. A newer
  user action replaces the previous action check.
- The watchdog never polls and never reloads or rebuilds a WebView. A generation
  can report at most one stall. Release, rebuild, and newer navigation make old
  watchdog callbacks stale.
- A stall and a content-process termination each produce one compact,
  observation-only `web_runtime.incident_snapshot` containing runtime/navigation
  identity, load/progress state, view attachment/geometry, source-window
  visibility/key state, fullscreen state, residency, active state, and pending
  Warm/Cold release flags. Geometry is sampled only for these incidents.

## Renderer probe

- Only a stall starts a renderer probe. The probe reads `document.readyState` and
  `document.visibilityState`; it reads no page text, DOM content, title, form
  values, cookies, storage, or URL.
- The probe has a five-second timeout and emits `renderer_probe.success`,
  `renderer_probe.failed`, or `renderer_probe.timeout` with runtime/navigation
  generations, latency, and the two safe state values when available.
- Completion, timeout, and runtime-replacement callbacks are token-guarded. A
  late callback after timeout or replacement is ignored.

## Logging and privacy

- User actions and navigation start/finish are visible in Standard mode; Off
  suppresses them. Stall, snapshot, and failed/timeout probe events are warning
  level; a successful probe is informational.
- New events contain no URL, query, fragment, page content, input, or cookie
  values. Existing URL events continue to use the shared sanitizer.
- All diagnostic state is transient. `RuntimeDiagnostics` remains
  observation-only, and writer I/O remains on its existing utility queue.
