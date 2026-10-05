# FloatTabs Current Task

**Task ID:** FT-DIAG-004
**Title:** Bounded Page-App Failure Probe Foundation
**Status:** `REMOTE_AUDIT_PASS — MERGE_READY; EXACT_HEAD_CI_REQUIRED`

**Task branch:** `codex/ft-diag-004-page-app-probe`  
**Base:** `caacc3b143ef3a5ba41d642b0a8aee3eaeacec4e`  
**Implementation commit:** `cbea3705fbcd2de089c425b2aa45dde3914aca4d`  
**Real-WKWebView amendment test commit:** `55d6a9cc2238bb8c873c3d7cfc0ebef11d3841e3`  
**Pull request:** #111

## Objective

Add the minimum observation-only ChatGPT page-application diagnostics needed to classify a future `CHATGPT_APP_NOT_READY_WITH_RESPONSIVE_RENDERER` incident without Web Inspector or mutation of the affected runtime.

This task does not authorize a stuck-tab fix.

## Independent remote audit

**VERDICT: PASS**

The prior independent-audit blocker is closed. A real `WKWebView` test now exercises the production `ChatGPTAttentionBridge` user script in its named isolated `WKContentWorld` and reads the recorder through the existing `captureIncidentPageAppDiagnostics` path.

Verified page-world → isolated-world signals:

- uncaught JavaScript error → `javascript_error / global_error`;
- unhandled Promise rejection → `unhandled_rejection`;
- deterministic test-only script-resource failure → `resource_load_failure / script_load`.

The test also verifies that raw message, rejection reason, and resource-URL sentinels are not returned as diagnostic evidence. Stale runtime/navigation context returns `stale` with no values. Existing document/runtime/WebView stale guards remain green.

No production implementation changed in the audit amendment. No fetch/XHR/WebSocket/application API monkey-patch was added.

## Accepted implementation contract

FT-DIAG-004 remains observation-only:

- bounded current-document recorder: maximum 16 retained events;
- counters saturate at 255;
- diagnostic categories and coarse timing/status metadata only;
- incident evidence correlates with existing session/Slot/WKWebView/runtime/navigation/document identity;
- stale evidence is rejected;
- persistence continues through the existing `RuntimeDiagnostics` authority and `RuntimeDiagnosticPrivacy` boundary;
- existing attention/response/navigation/lifecycle/focus/recovery ownership is unchanged;
- no reload, reset, rebuild, retry, recovery, navigation, cache, or website-data behavior is driven by these diagnostics.

## Privacy boundary

Do not persist raw exception/rejection messages, stack traces, request/response bodies or headers, cookies, credentials, authorization/tokens, prompt/assistant/page/DOM text, conversation identifiers, or response identifiers.

Request URLs and resource/chunk identifiers remain intentionally omitted from this probe.

## Accepted remaining gaps

These are not FT-DIAG-004 merge blockers:

- page-handled fetch/XHR failures cannot be passively observed without prohibited interception;
- HTTP status may be unavailable/opaque in WebKit resource timing;
- raw exception/rejection detail is intentionally not collected;
- request URL/chunk identity is intentionally not collected.

**ROOT_CAUSE_CONFIRMED: NO**

## Validation evidence

The independent audit accepted the amendment evidence:

- real WKWebView boundary test passed, including repeated runs;
- focused bridge/privacy/capture tests passed;
- full FloatTabs suite passed without failures;
- Debug and Release macOS arm64 builds passed;
- binaries were arm64-only;
- `git diff --check` passed;
- QA DMG passed;
- prior reviewed PR head passed `Build & Test (Apple Silicon arm64)` in PR context.

The current control-plane closeout commit is docs-only. Because it changes the PR head, repository rule 23 still requires `Build & Test (Apple Silicon arm64)` to pass in PR context on this exact new head before merge.

## Merge gate

PR #111 is **remote-audit approved** but must remain OPEN and unmerged until all of the following are simultaneously true:

1. live PR head equals the reviewed control-plane closeout head;
2. `main`/PR base has not unexpectedly drifted;
3. required `Build & Test (Apple Silicon arm64)` is recorded PASS by GitHub for that exact PR head;
4. no new product/test changes were added after the real-WKWebView amendment review;
5. PR remains mergeable.

Once those conditions hold, **MERGE IS AUTHORIZED without another audit amendment**. Do not add another controls-only status commit merely to restate the CI result, because that would create a new exact head and reopen the same check loop.

Do not install the PR build as the QA baseline before merge.

## Post-merge boundary

After merge, FT-DIAG-004 construction closes. A separate control-plane task must authorize any QA-baseline build/install and natural incident observation. Recovery/fix construction remains unauthorized until new incident evidence supports it.

## Separate work

PR #102 remains separate MemoX durable-outbox work. Do not modify, merge, rebase, or use it as a base for FT-DIAG-004.
