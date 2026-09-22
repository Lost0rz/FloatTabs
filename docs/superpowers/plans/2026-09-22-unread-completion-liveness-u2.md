# U2 Background Completion Liveness Implementation Plan
> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add a native-only, lifecycle-safe liveness watchdog to `ChatGPTAttentionBridge` so a backgrounded ChatGPT WebContent runtime can be confirmed idle and emit the existing completion observation without changing unread persistence, response identity, or runtime recovery semantics.

**Architecture:** Keep `ChatGPTAttentionBridge` as the sole owner of the watchdog. Extend the document-start same-world attention script with a read-only `__floatTabsAttentionProbeV1` that returns only version, kind, token, and the current `isGenerating()` result. The native bridge starts one cancellable async watchdog only after an accepted generating baseline/transition, waits 2 seconds between cycles, and uses a two-sample false confirmation separated by 250 ms. Probe results pass the same bridge/document/WebView admission checks before touching the existing generation tracker. Lifecycle reset, navigation replacement, Instant Back confirmation, invalidation, WebContent termination, and bridge attachment replacement cancel and invalidate old cycles through generation/epoch identity checks. Tests inject the sleep/probe seam so no test waits real time.

**Tech Stack:** Swift, WebKit `WKWebView.evaluateJavaScript` in `ChatGPTAttentionBridge.contentWorld`, Swift concurrency `Task`, XCTest, existing `RuntimeDiagnosticRecording`.

**Spec:** Attached U2 request provided at task start.

## Global Constraints

- Preserve exact baseline `1b8cc1a28b9bcf35cf28b9e6cd7d3f6e0a7a2a87` and isolate all work on `fix/unread-completion-liveness-u2`.
- Do not modify `UnreadResponseStore.swift`, `ChatGPTUnreadResponseCoordinator.swift`, `ChatGPTResponseExtraction.swift`, `ChatGPTResponseBridge.swift`, `AttentionPresentation.swift`, or `Package.resolved`.
- Do not call `requestCurrentDocumentResync()` from the watchdog and do not alter the existing navigation/admission authority.
- Do not add JavaScript polling (`setInterval`, recursive JS `setTimeout`, or `requestAnimationFrame`). The existing DOM observer/coalescer remains unchanged.
- Do not add panel/app wake or residency redesign. Completion must flow through the existing `generationFinished` observation route.
- Probe and diagnostics must carry no page content, response text, prompt, URL, DOM, or token beyond bridge identity validation.

## Task 1 — Establish test seams and probe contract (TDD)

- [x] Add failing script-source assertions for `__floatTabsAttentionProbeV1`, its `{version: 1, kind: "baseline", token, generating}` shape, and read-only behavior with respect to `lastSent`, `postMessage`, DOM, observer, timers, token, and page state.
- [x] Add a bridge test seam for an injectable liveness sleeper and same-world snapshot provider (or equivalent single-cycle hook) so tests control time and probe values without a second state machine or real two-second waits.
- [x] Add failing tests that an idle baseline does not activate a watchdog, a generating baseline activates exactly one watchdog, and duplicate generating observations do not create a second cycle.
- [x] Run the focused bridge tests and record the expected failures before production implementation.

## Task 2 — Implement watchdog state and guarded probe admission

- [x] Add the production watchdog interval (`2000 ms`), false-confirmation delay (`250 ms`), watchdog generation/epoch identity, cancellation task, and one-in-flight cycle guard to `ChatGPTAttentionBridge`.
- [x] Start/stop the watchdog only from accepted generation transitions and the existing lifecycle boundaries; ensure natural finish stops it immediately.
- [x] Evaluate the probe in `ChatGPTAttentionBridge.contentWorld` through the attached WebView, parse only the strict baseline probe payload, and fail closed on errors, malformed data, unsupported admission, changed WebView, changed document token, changed epoch, or invalidation.
- [x] Keep `generating == true` as a no-op for tracker/output purposes; for `false`, perform the 250 ms same-document confirmation and only then call `document.tracker.observe(false)` and the existing `emit(.generationFinished)` path.
- [x] Make false→true cancel the idle candidate without emitting completion, and preserve exactly-once behavior when natural completion races a watchdog result.

## Task 3 — Wire diagnostics without changing runtime policy

- [x] Pass the existing `RuntimeDiagnosticRecording` from `WebViewPool` into `ChatGPTAttentionBridge`.
- [x] Record only the allowed liveness events: started, stopped, probe failed, and recovered completion. Include slot/confirmation/interval/delay/optional numeric elapsed fields only; never record token, URL, content, prompt, or DOM.
- [x] Verify WebContent termination and runtime replacement cancel old watchdogs and never synthesize a completion.

## Task 4 — Add lifecycle and cross-feature regression coverage

- [x] Add bridge tests for true probe, false/false completion, false/true transient gap, natural-finish race, stale document, navigation replacement, invalidation, WebContent termination, pending Instant Back current-document completion, and attachment replacement.
- [x] Add cross-feature tests proving hidden recovered completion transitions `generating → ready`, marks unread once, and records completion-observed/marked diagnostics; visible recovered completion transitions `generating → idle`, keeps unread clear, and records visible-completion skip.
- [x] Keep all U1 hover/scroll and trusted pointer/copy acknowledgement regression tests unchanged and passing.

## Task 5 — Verification and handoff

- [x] Run focused U2 and U1 regression XCTest groups, then the full XCTest suite.
- [x] Run Debug and Release arm64 builds, architecture verification, `git diff --check`, absolute-path scan, and verify `Package.resolved` is unchanged.
- [x] If full-suite failures occur, rerun the exact corresponding tests from a clean exact-main worktree before classifying them as baseline/flaky.
- [x] Commit, push, create the requested Draft PR against `main`, attach the PR artifact, and keep it Draft/Open/Unmerged.
- [x] Report the required U2 final schema with explicit PASS/FAIL evidence and `READY_FOR_U2_INDEPENDENT_AUDIT` only when all required checks pass.

## Review Focus

- The watchdog must never become a second authority for document admission or attention state.
- Every async callback must prove bridge validity, watchdog generation/epoch, attached WebView identity, active supported document, and current token before mutating tracker state.
- The two-sample false confirmation must be the only recovered-completion path, and natural/watchdog races must emit at most one completion.
- The diff must prove no forbidden files, JS polling, persistence changes, response identity changes, or content-process recovery changes.

---
