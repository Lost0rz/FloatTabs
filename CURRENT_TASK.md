# FloatTabs Current Task

**Task ID:** FT-DIAG-004
**Title:** Bounded Page-App Failure Probe Foundation
**Status:** `WAITING_FOR_INDEPENDENT_AUDIT`

**Task branch:** `codex/ft-diag-004-page-app-probe`

**Base:** `caacc3b143ef3a5ba41d642b0a8aee3eaeacec4e`

**Implementation commit:** `cbea3705fbcd2de089c425b2aa45dde3914aca4d`

**Amendment test commit:** 55d6a9cc2238bb8c873c3d7cfc0ebef11d3841e3

**Pull request:** #111

## Independent audit amendment result

**Verdict:** AMENDMENT_COMPLETE — WAITING_FOR_INDEPENDENT_AUDIT

The amendment adds one real WKWebView behavior test and changes no production code. It installs
the production ChatGPTAttentionBridge script through the production bridge into the named
isolated WKContentWorld, produces page-world uncaught JavaScript and unhandled Promise errors,
and fails a local script resource through a test-only WKURLSchemeHandler.

The existing captureIncidentPageAppDiagnostics path observed:

- javascript_error / global_error;
- unhandled_rejection / unhandled_rejection;
- resource_load_failure / script_load, resource type script.

The returned diagnostic metadata did not contain the test-only raw error message, rejection
reason, or resource-URL sentinels. A second real capture whose caller-owned runtime/navigation
context became stale returned stale and no evidence. Existing document/runtime/WebView stale
guards passed in the focused suite. No fetch/XHR/WebSocket patch or other page interception was
added.

Test amendment commit: 55d6a9cc2238bb8c873c3d7cfc0ebef11d3841e3

Validation on macOS 27.0.1 arm64:

- New boundary test: 1/1 passed plus three repeated 1/1 runs.
- Focused bridge/privacy/capture-integration tests: 102 passed, 0 skipped, 0 failed.
- Full FloatTabs suite: 1,288 passed, 3 skipped, 0 failed (1,291 total).
- Debug and Release builds passed; both binaries contain arm64 only.
- git diff --check passed.

The amendment code commit was pushed. This control-plane update is a later controls-only commit;
verify the live branch head before review. The PR-context required check must pass on the current
live head before merge. No merge or QA baseline installation is authorized.

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
audit. The branch contains this control-plane synchronization; verify the live
`origin/codex/ft-diag-004-page-app-probe` head against the checked out branch
before review.

### Executor result

- ChatGPTAttentionBridge keeps its passive listeners and bounded recorder unchanged.
- The new real-WKWebView test exercises the production script in the named isolated world and
  reads its result through captureIncidentPageAppDiagnostics.
- Page-world uncaught error, unhandled rejection, and local script-resource failure were all
  observed as the expected bounded categories. Test-only raw message/reason/URL sentinels were
  absent from the returned diagnostic fields.
- Stale caller-owned runtime/navigation context returns stale with no values; existing
  document/runtime/WebView stale-guard tests remain green.
- Only FloatTabsTests/ChatGPTAttentionBridgeTests.swift changed in the amendment code commit.
  No production implementation, package lock, monkey-patch, or QA baseline changed.
- Focused, full-suite, Debug, Release, arm64, and whitespace validation results are recorded above.

### Remaining passive-observation gaps

- Failures already caught and handled by page fetch/XHR code cannot be observed
  without forbidden API interception.
- HTTP status is unknown when WebKit does not expose
  `PerformanceResourceTiming.responseStatus` or exposes an opaque value.
- Exception/rejection class names and raw details are not inspected. Request
  URLs and resource/chunk identifiers are omitted.

No fix or recovery behavior was added; no new QA baseline was installed. The
root cause remains unknown. Stop at `WAITING_FOR_INDEPENDENT_AUDIT`; do not merge.
