# FloatTabs Current Task

**Task ID:** `FT-DIAG-POST-FINISH-STALL-001`
**Title:** Discriminate post-finish Web runtime stalls with cross-world liveness and bounded resource evidence
**Status:** `ACTIVE — GATE 5 REAL-MAC CAPTURE`
**Mode:** `DIAGNOSTIC`
**Task class:** `INCIDENT_INVESTIGATION`
**Base:** `main@3511297d5f573598556739519bae859322578768`
**Branch:** `codex/ft-post-finish-stall-diag-001`
**Draft PR:** `#138`
**Validated semantic head:** `292d6225808ebc66a12dd36e100fe309e53a335d`

## Evidence boundary

Fresh v0.5.4 / Build 22 evidence proves a post-navigation runtime failure boundary: an active ChatGPT WKWebView can remain `navigation_phase=finished`, `is_loading=false`, and progress `1` while bounded JavaScript execution stops responding. Native host processing continues and the fresh stall did not emit a WebContent termination callback.

The causal root cause remains **UNKNOWN**. Remote code audit and implementation have now supplied the missing discriminator rather than changing recovery behavior.

## Remote implementation disposition

Remote diagnostic implementation is complete for this task stage:

- ordinary main page-world and FloatTabs isolated-world liveness are sampled independently on the same Web Runtime authority;
- in-flight results are stale-guarded by runtime/navigation context;
- a single finished-state dual timeout is candidate evidence only;
- two consecutive finished-state dual timeouts are required for confirmed `POST_FINISH_RUNTIME_STALL` evidence;
- observed Web-process epoch/termination count is distinct from WKWebView object identity and advances only on the documented termination callback;
- host resident memory/system physical memory are recorded with public APIs;
- WebContent child-process attribution is explicitly unavailable in production when it cannot be proven;
- no page text, prompt, response, document token, cookie, session, or other user content is logged.

Ownership remains in `SlotNavigationObserver` / Web Runtime. Focus and persistence ownership were not broadened.

## Remote validation

Exact semantic head: `292d6225808ebc66a12dd36e100fe309e53a335d`

- macOS CI `#1062` / run `39193066565`: PASS
  - Debug build PASS
  - Release build PASS
  - arm64 verification PASS
  - XCTest PASS
- QA DMG `#487` / run `39193066576`: PASS
- XCTest artifact independently confirmed all four new regression tests executed and passed.

## Gate 5 — Fresh Air real-Mac capture

This is the only active construction/validation gate now.

Required:

1. Check out the exact remote diagnostic head authorized by the latest control state.
2. Audit the currently installed `/Applications/FloatTabs.app` before replacement; do not assume its version/build.
3. Build/install the diagnostic app for arm64 without deleting or rewriting any FloatTabs user data.
4. Verify the running process uses the diagnostic source revision and that standard runtime logs include `web_runtime.cross_world_liveness`.
5. Confirm expected fields are present:
   - `main_world_probe_outcome`
   - `isolated_world_probe_outcome`
   - `navigation_phase`
   - `observed_web_process_epoch`
   - `observed_web_process_termination_count`
   - `host_resident_size_bytes`
   - `web_process_resource_attribution`
6. Pre-validate the repository's external benchmark/process-attribution harness before an incident, but do not stress the app or mutate Slot policies.
7. Use FloatTabs normally.
8. If a fresh stall occurs, preserve raw runtime diagnostics and external memory/process evidence before any recovery action.
9. If recovery is necessary after evidence capture, one manual reload may be recorded as a recovery-boundary observation. Do not infer root cause from recovery.
10. Return the raw files and execution receipt for Web-side joint audit.

## Forbidden actions

- No automatic reload, hard rebuild, reset, restart, eviction, cache clearing, or session clearing as a diagnostic shortcut.
- No change to Hot / Warm / Cold policy merely to reproduce the issue.
- No deletion/recreation of Browser Profiles, cookies, WebsiteData, sessions, backups, preferences, Slots, or configuration.
- No private WebKit API and no guessed WebContent PID/RSS attribution.
- No page-content logging.
- No merge of PR #138 before fresh real-Mac evidence is audited.

## Gate 5 acceptance

`CAPTURED` only when a fresh incident has raw diagnostics plus process/resource context sufficient to classify at least:

- main world success/timeout/stale;
- isolated world success/timeout/stale;
- candidate/confirmed post-finish stall state;
- observed Web-process epoch/termination count;
- host RSS and independently attributable WebContent RSS/CPU when attribution is proven;
- whether a documented WebContent termination callback occurred.

If no incident occurs during normal use, report `NO_INCIDENT_YET`; that is not a failure and does not authorize synthetic stress.

The task remains open until fresh real-Mac evidence (or sufficient negative evidence) supports the next causal decision.
