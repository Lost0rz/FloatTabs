# Web Runtime Recovery v1 Contract

This contract extends the observation-only health diagnostics with one bounded
recovery escalation that is authorized by an explicit Reload or Home action.
It preserves the existing WebKit, navigation, lifecycle, and fullscreen owners.

## Incident classes

- `POST_COMMIT_NAVIGATION_STALL_WITH_RESPONSIVE_RENDERER` describes the
  confirmed incident: navigation committed, WebKit's renderer probe succeeded,
  and the navigation later finished. The available evidence does not identify
  a particular network subresource or prove a DNS, CDN, or WebSocket cause.
- `WEB_CONTENT_PROCESS_TERMINATION` remains a separate incident class with
  the existing active-now/inactive-deferred recovery policy.
- A failed renderer probe is not evidence that the renderer is dead. Only a
  probe timeout is classified as an unresponsive-renderer candidate.

## Passive navigation stalls

A normal navigation stall is observation only. It records the existing stall
and renderer-probe diagnostics, then takes no recovery action, including when
the renderer responds. It does not stop, reload, navigate Home, release, or
replace the WebView.

## User-action correlation

- Reload and Home keep their existing first action: `WKWebView.reload()` and
  the current Home navigation path.
- The observer retains the user action only until its resulting provisional
  navigation starts. That navigation is correlated with the current runtime,
  navigation, and user-action generations. A no-navigation action timeout is
  diagnostic only and cannot authorize recovery.
- If that correlated navigation stalls at the existing 120-second bound, a
  one-shot five-second renderer probe classifies it. There are no shorter new
  timeouts, polling loops, or repeated probes.
- A responsive renderer authorizes at most one soft recovery for the correlated
  action. Renderer-probe failure records evidence and stops. Renderer-probe
  timeout is an unresponsive-renderer candidate, but hard replacement is
  deferred in v1 because the existing pool rebuild is coupled to profile
  reconciliation and panel reattachment, while fullscreen source ownership is
  separately locked and restored by `FullscreenSourceHostController`.

## Soft recovery

- Reload recovery stops the stalled load and calls
  `WKWebView.reloadFromOrigin()`. This revalidates the current page using
  cache-validating conditionals when possible; it does not clear website data
  or cookies. The ordinary first Reload remains `reload()`.
- Home recovery stops the stalled load when needed and reissues the same
  captured Home URL through the existing `WebViewPool.navigate` path, including
  its existing inferred-scheme fallback permission. It never turns Home into a
  reload of the current page.
- A soft recovery is complete only after its resulting navigation commits or
  finishes. A failed navigation, a recovery navigation stall, or a bounded
  recovery-start timeout records one failure and does not trigger another
  escalation.
- If the original user-requested navigation finishes while a fullscreen
  deferral is pending, the deferred recovery becomes stale and is discarded.
- If the fullscreen source host is locked, soft execution is deferred until
  that host returns to `idle`. The deferred request is transient and is dropped
  if its ticket becomes stale, its Slot is released, or the Slot is no longer
  active. Recovery never activates a Slot.

## Tickets and invalidation

Each recovery request carries a transient ticket containing
`runtime_generation`, the stalled `navigation_generation`,
`user_action_generation`, `recovery_generation`, and action. It is control and
diagnostic correlation only; it is not persisted in `WebAppProfile`.

A ticket can be requested and executed at most once. A new user action or
navigation, a runtime replacement, release, or content-process termination
invalidates older work. Timer, renderer, and recovery callbacks must match the
current ticket before acting. Release continues through the existing pool and
lifecycle owners.

## Diagnostics and privacy

Recovery outcomes use bounded events for requested, deferred, started,
completed, failed, and stale recovery. Fields include only Slot and generation
identifiers, action, and a fixed reason category. They never include a URL,
query, fragment, title, page content, DOM, form value, cookie, or storage value.
The renderer probe remains limited to `document.readyState` and
`document.visibilityState`.

## Content-process termination

V1 leaves `WebViewPool.handleContentProcessTermination` unchanged. An active
Slot reloads its last known safe URL in the same `WKWebView`; an inactive Slot
defers the reload until activation. Existing bridge reset behavior remains in
place. V1 does not add a per-runtime termination counter or turn repeated
termination into a hard replacement policy.
