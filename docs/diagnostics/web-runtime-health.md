# Web Runtime Health Diagnostics Contract

This contract adds observation to the existing WebKit runtime. It does not
change navigation authority, reload or Home behavior, session storage,
residency policy, fullscreen recovery, or content-process recovery.

## Correlation

- `runtime_generation` is a process-local, monotonically increasing integer
  assigned when the pool creates a `WKWebView`. Reuse preserves it; release,
  rendering rebuild, and later recreation produce a new value. It is diagnostic
  metadata only and is never persisted.
- `webview_instance_id` is a fresh opaque UUID for each physical `WKWebView`.
  Reuse preserves it; rebuild/recreation changes it. `document_epoch` is the
  attention bridge's current native document epoch. Neither value contains a
  URL or page identifier.
- `navigation_generation` advances on each `didStartProvisionalNavigation` for
  that runtime. Commit, finish, failure, and watchdog events carry the current
  generation. Delayed callbacks must match both runtime and navigation identity.
- Reload and Home requests are recorded at their existing user-action
  boundaries with the runtime and navigation generations observed before the
  request, active/loading state, and no URL.

## Stall observation

- A one-shot watchdog is armed for the provisional phase. A commit cancels that
  timer and immediately arms one bounded post-commit watchdog waiting for finish
  or failure. If either phase makes no further progress for 120 seconds before a
  process termination, newer navigation, release, or rebuild, record one
  `navigation.stalled` event. The event includes whether the tracked navigation
  had already committed.
- Reload and Home also arm a one-shot 120-second no-progress check. A subsequent
  provisional start replaces that check with the navigation watchdog. A newer
  user action replaces the previous action check.
- The watchdog never polls and never reloads or rebuilds a WebView. A generation
  can report at most one stall. Release, rebuild, and newer navigation make old
  watchdog callbacks stale.
- A stall and a content-process termination each produce one compact,
  observation-only `web_runtime.incident_snapshot` containing runtime/navigation
  identity, load/progress state, view attachment/geometry, the actual
  `webView.window` visibility/key state, the source-host window visibility/key
  state, fullscreen state, residency, active state, and pending Warm/Cold release
  flags. Geometry is sampled only for these incidents.

## Renderer probe

- Only a stall starts a renderer probe. The probe reads `document.readyState` and
  `document.visibilityState`; it reads no page text, DOM content, title, form
  values, cookies, storage, or URL.
- The probe has a five-second timeout and emits `renderer_probe.success`,
  `renderer_probe.failed`, or `renderer_probe.timeout` with runtime/navigation
  generations, latency, and the two safe state values when available.
- Completion, timeout, newer-navigation invalidation, and runtime-replacement
  callbacks are token-guarded. A late callback after timeout, replacement, or a
  newer navigation is ignored.

## Logging and privacy

- User actions and navigation start/finish are visible in Standard mode; Off
  suppresses them. Stall, snapshot, and failed/timeout probe events are warning
  level; a successful probe is informational.
- New events contain no URL, query, fragment, page content, input, or cookie
  values. Existing URL events continue to use the shared sanitizer.
- All diagnostic state is transient. `RuntimeDiagnostics` remains
  observation-only, and writer I/O remains on its existing utility queue.

## Wave 2 provenance and incident snapshots

- App launch diagnostics include the diagnostic schema, app version/build, source
  revision, build channel, QA label, host PID, macOS version, architecture, and
  session ID. The build phase derives source revision from the checkout and marks
  a dirty checkout with `-dirty`; build channel and QA label are bounded build
  metadata. These values do not alter marketing or build version metadata.
- Startup restore records the selected Slot and its page class (`root`,
  `conversation`, or `other`) before constructing that Slot's runtime. It does
  not record a URL or conversation identifier. Runtime creation and replacement
  events record a fixed creation reason, runtime generation, WebView instance
  ID, document epoch when available, navigation trigger, active state, residency
  policy, restore flag, and construction phase. WebKit exposes no supported
  public API that identifies a WebContent process PID; the app PID is not a
  substitute for that identity.
- `previous_exit` is `clean`, `unclean_suspected`, or `unknown`. A durable
  lifecycle marker records only whether termination reached the clean-exit
  callback; an interrupted session is not labeled as a confirmed crash.
- The QA-only **Capture Stuck Tab Snapshot (QA)** command is available in Debug
  builds and the explicitly labeled Wave 2 QA build for the current Slot. It
  creates an incident ID and records bounded native runtime state without
  navigating, reloading, rebuilding, or changing Slot selection. Correlation
  continues across the same Slot's manual QA reset; tab selection alone does not
  close it.
- A manual QA reset remains explicitly user initiated. Its diagnostics correlate
  the pre-reset snapshot, old and new runtime generations, and the resulting
  navigation outcome under the incident ID. Reset behavior is otherwise owned
  by the existing runtime replacement path.

## Bounded app health and network metadata

- For supported ChatGPT hosts only, each health sample records fixed
  state enums/booleans for document readiness and visibility, bridge readiness,
  conversation shell/composer/generation/loading/error indicators, and counts
  plus coarse classes for JavaScript errors and unhandled rejections. It also
  records bounded script/resource/other error counts, relative ages of the
  first/last error and rejection, activity batch counts/age from the existing
  filtered MutationObserver, and pageshow/visibility-change counts/ages. Event
  listeners observe and count only; they do not cancel or alter page events.
- Native health records include a bounded probe outcome and WebKit round-trip
  duration. A missing bridge, malformed snapshot, evaluation error, or a
  five-second timeout has a coarse outcome; late callbacks are ignored. The
  script's `probe_elapsed_ms` remains a separate in-document duration.
- A cached health snapshot is accompanied by its monotonic age, source, runtime,
  navigation, document epoch, and WebView instance ID. Explicit match/stale
  flags distinguish observations from an earlier runtime or document; the
  current incident capture retains its own live generation and network metadata.
- Periodic sampling runs only for the exact QA label
  `runtime-diagnostics-wave2`, at a 30-second monotonic cadence, and only for
  the currently active, resident slot whose current document has a supported
  ChatGPT host. There is at most one sample in flight. Inactive/unsupported
  slots are skipped; a delayed wake schedules from the wake time and does not
  generate catch-up samples. Ordinary Release labels do not enable this sampler.
  Sampling records diagnostics only and cannot trigger recovery.
- A representative serialized health event is about 1.5 KB: 120 samples/hour
  or 2,880/day is approximately 4.4 MB/day and 30.6 MB over seven days for one
  continuously active ChatGPT slot. The writer retains up to ten 10 MiB
  segments, so the estimate fits the existing rotation budget with room for
  other diagnostic events.
- The health observation reads no page text, title, prompt, response body,
  conversation/response identifier, input, cookie, storage, raw URL, query,
  fragment, error message, or stack. The privacy sanitizer rejects these fields
  at the diagnostic boundary.
- Network diagnostics emit only deduplicated path transitions: generation,
  status, coarse interface class, expensive, and constrained. They do not record
  addresses, DNS servers, SSIDs, routes, or per-request/network-resource data.

## Wave 2 incident observations

Capture acknowledges a successfully recorded snapshot in the existing nonblocking
HUD with an incident UUID prefix; the JSONL retains the full UUID. Capture never
navigates, transfers focus, copies to clipboard, or replaces a runtime.

One open incident binds UUID, slot and monotonic opened uptime. Tab selection
changes do not close it. A newer capture supersedes it. Actual runtime release,
app termination or a token-guarded 60-minute timeout closes it with an explicit
`diagnostic.incident.closed` reason. Manual replacement keeps correlation through
reset completion, replacement navigation and the first available application-health
snapshot triggered by navigation finish for that new runtime. Only then is it
closed as `post_recovery_evidence_complete`. Failed/unavailable health stays open
until a bounded close boundary. These are diagnostic observations, not recovery policy.

`loading_indicator_present` retains its DOM-existence semantics.
`loading_indicator_visible` separately checks the same loading selector for
connected, nonhidden elements with visible ancestor styles, positive opacity and
nonzero rendered rectangles. Neither field establishes that ChatGPT is stuck.
No element text, attributes containing content, HTML, URLs or JS error payloads
are exported; health contains only bounded booleans, counts and categories.
