# FloatTabs Current Task

**Task ID:** FT-DIAG-004
**Title:** Bounded Page-App Failure Probe Foundation
**Status:** `WAITING_FOR_INDEPENDENT_AUDIT`

**Task branch:** `codex/ft-diag-004-page-app-probe`

**Base:** `caacc3b143ef3a5ba41d642b0a8aee3eaeacec4e`

**Implementation commit:** `cbea3705fbcd2de089c425b2aa45dde3914aca4d`

**Pull request:** #111

## Objective

Add the minimum observation-only page-application diagnostics needed to classify a future `CHATGPT_APP_NOT_READY_WITH_RESPONSIVE_RENDERER` incident without requiring Web Inspector or mutation of the affected runtime.

The task exists because FT-DIAG-003 closed with:

`CURRENT_INCIDENT_PAGE_EVIDENCE_UNAVAILABLE_WITHOUT_MUTATION`

This task does not authorize a stuck-tab fix.

## Construction scope

Build a bounded ChatGPT-specific diagnostic surface that can preserve, for the current document and without page-content capture:

1. application-level JavaScript error occurrence/category;
2. unhandled rejection occurrence/category without rejection text;
3. script/resource load-failure metadata;
4. passive resource timing/status metadata where the browser exposes it without replacing or monkey-patching application networking APIs;
5. document lifecycle correlation relevant to the H3 hypothesis, including visibility and page show/hide transitions.

The implementation may use a dedicated diagnostic bridge/component or another clearly isolated observation path. It must not change the semantics or ownership of the existing attention, response, navigation, lifecycle, focus, or recovery systems.

## Required identity binding

Every persisted page-diagnostic event or explicit incident snapshot must be correlatable, where available, to the existing:

- session ID;
- Slot ID;
- physical WKWebView instance ID;
- runtime generation;
- navigation generation;
- ChatGPT document epoch/current-document guard;
- monotonic/timestamp ordering.

Stale events from an earlier document/runtime/navigation must be dropped or explicitly classified stale; they must never be attributed to a later document.

## Privacy and boundedness gate

The diagnostic path must use the existing `RuntimeDiagnostics` persistence authority and `RuntimeDiagnosticPrivacy` boundary.

It must never persist:
- raw exception/rejection messages;
- stack traces;
- request or response bodies;
- request/response headers;
- cookies, credentials, authorization or tokens;
- prompt/assistant/page/DOM text;
- conversation/response identifiers.

If resource URL metadata is retained, it must pass through the existing URL sanitization policy before persistence.

Use bounded counters/ring-buffered metadata or equivalently bounded state. Do not create an unbounded console/network recorder.

## Passive-observation gate

Do not wrap or replace `fetch`, `XMLHttpRequest`, WebSocket, navigation functions, or ChatGPT application functions in this task.

Do not alter page request behavior, retry behavior, caching, timing, lifecycle, focus, navigation or recovery policy.

If a desired discriminator cannot be obtained passively with supported WebKit/browser surfaces, record it as a remaining gap rather than introducing behavioral interception.

## Incident capture integration

Extend the existing explicit QA stuck-tab capture so that a future incident can emit the bounded page-app evidence alongside the existing:
- stuck-tab snapshot;
- ChatGPT health probe;
- renderer probe.

Normal healthy operation must not require periodic polling. Event listeners/observers may keep only bounded diagnostic metadata for the current document.

## Acceptance criteria

Construction is acceptable only when all of the following are demonstrated:

- observation-only behavior; no recovery/navigation behavior added;
- exact current-document/runtime identity correlation and stale rejection;
- bounded page-error/rejection/resource/lifecycle metadata available in an explicit incident capture;
- raw sensitive exception/request/page content cannot cross the persistence boundary;
- privacy tests cover malicious/sensitive values and URL sanitization;
- focused tests cover current-document replacement/stale events and bounded storage;
- existing FT-DIAG-002 renderer/health probe behavior remains intact;
- existing attention/response/lifecycle semantics remain unchanged;
- package lock unchanged unless separately authorized;
- focused tests pass;
- full FloatTabs test suite and required Debug/Release builds pass on the exact proposed head.

## Mandatory STOP conditions

Stop construction and return for remote review if:

- passive supported WebKit/browser surfaces cannot observe a required class without monkey-patching application networking/runtime APIs;
- the design would require persisting raw exception messages, stack traces, request content, auth/session data or page text;
- diagnostics would become a second authority for application/lifecycle state;
- implementation would change reload/reset/recovery/navigation behavior;
- PR #102 or unrelated production behavior would need modification;
- authoritative `main`/control-plane state drifts before construction.

A stopped discriminator may be documented as a remaining gap; do not broaden scope to solve it speculatively.

## Handoff state

Implementation and local validation are complete. The PR is open for independent
audit. The branch head will include this control-plane synchronization commit;
verify the live `origin/codex/ft-diag-004-page-app-probe` head against the checked
out branch before review.

### Executor result

- `ChatGPTAttentionBridge` installs passive listeners and a resource
  `PerformanceObserver` in the existing isolated content world. The recorder
  keeps a 16-entry ring and saturating counters (255 maximum), emits only fixed
  categories, coarse timing, resource type, and exposed HTTP status.
- `Capture Stuck Tab Snapshot (QA)` emits the page-app snapshot under the same
  incident ID and frozen Slot/WebView/runtime/navigation fields. Capture also
  binds the document epoch and opaque identity in memory; stale identity or
  runtime/navigation completion drops page evidence.
- Persistence remains through `RuntimeDiagnostics`; privacy tests cover
  malicious messages, stacks, URLs, headers, bodies, tokens, prompts, and
  answers. The generated JavaScript recorder test exercises ring eviction and
  counter saturation.
- Focused tests on the implementation source commit: 315 executed, 3 skipped,
  0 failures. Final full FloatTabs tests at PR head
  `1fabef84819225cc30fe7f047bb7e455d0498c9e`: 1,290 executed, 3 skipped,
  0 failures. Debug and Release builds at that PR head passed on macOS arm64;
  both binaries contain arm64 only. `git diff --check` passed.
- One earlier full run had a timing-sensitive failure in the unrelated
  `WebsiteCacheCleanupTests.testAutomaticCapacityRunUsesItsLocalMeasurementDuringSettingsRefresh`;
  the isolated retry and the subsequent final full suite passed.

### Remaining passive-observation gaps

- Failures already caught and handled by page fetch/XHR code cannot be observed
  without forbidden API interception.
- HTTP status is unknown when WebKit does not expose
  `PerformanceResourceTiming.responseStatus` or exposes an opaque value.
- Exception/rejection class names and raw details are not inspected. Request
  URLs and resource/chunk identifiers are omitted.

No fix or recovery behavior was added; no new QA baseline was installed. The
root cause remains unknown. Stop at `WAITING_FOR_INDEPENDENT_AUDIT`; do not merge.
