# FloatTabs Current Task

**Task ID:** `FT-DIAG-POST-FINISH-STALL-001`
**Title:** Discriminate post-finish Web runtime stalls with cross-world liveness and bounded resource evidence
**Status:** `ACTIVE`
**Mode:** `DIAGNOSTIC`
**Task class:** `INCIDENT_INVESTIGATION`
**Base:** `main@3511297d5f573598556739519bae859322578768`
**Branch:** `codex/ft-post-finish-stall-diag-001`

## Evidence boundary

Fresh release logs from v0.5.4 / Build 22 prove that an active, visible ChatGPT Slot can remain `navigation_phase=finished`, `is_loading=false`, and `estimated_progress=1` while FloatTabs' bounded ChatGPT JavaScript probes time out. Native window/focus/lifecycle callbacks continue, and no `web_content_process_terminated` callback is emitted for the fresh 2026-10-19 stall.

The latest audit further narrows the incident:

- the normal page-world focus script still completed around 00:55:00 and trusted page interaction was observed around 00:55:01;
- the first bounded health probe then stopped responding within the following tens of seconds;
- the memory-pressure warning arrived after the failed probe cycle had already begun, so it is not proven to be the direct trigger;
- reload created a fresh admitted ChatGPT document epoch, yet the next checkpoint could still time out before a later navigation recovered normally.

**Initial causal root cause remains UNKNOWN.** The next safe decision requires discriminating main-page-world execution from FloatTabs' isolated content world and correlating the result with bounded runtime/resource facts.

## Authorized scope

Implement diagnostic evidence only:

1. Add a minimal **main page-world liveness probe** using ordinary `WKWebView.evaluateJavaScript`, returning only bounded document state such as `document.readyState` / `document.visibilityState`.
2. Retain the existing FloatTabs ChatGPT isolated-world probe and record both outcomes in one long-term checkpoint so the worlds can be compared on the same Slot/runtime/navigation context.
3. Emit an explicit diagnostic classification for `navigation_phase=finished` plus repeated liveness timeout, without changing product navigation or recovery ownership.
4. Add bounded resource/lifecycle snapshot fields that are reliable in production without private WebKit APIs. Prefer host-process footprint and product-owned residency-policy counts; record unavailable child-process attribution as unavailable rather than guessing.
5. Add a per-WKWebView content-process epoch / termination counter that advances only when `webViewWebContentProcessDidTerminate` is observed, so WKWebView identity is no longer confused with WebContent-process replacement history.
6. Add focused regression tests for probe timeout/success/stale handling, post-finish classification, identity/epoch behavior, and data-bounding/privacy.
7. Update `CURRENT_STATUS.md` / `CURRENT_TASK.md` with exact final branch/head and validation evidence when implementation closes.

## Forbidden actions

- Do not change Hot / Warm / Cold residency semantics.
- Do not add automatic reload, automatic hard rebuild, reset, eviction, cache clearing, or session clearing.
- Do not delete/recreate Browser Profiles, cookies, website data, backups, preferences, Slots, or user configuration.
- Do not use private WebKit APIs or claim WebContent PID/RSS attribution that cannot be proven.
- Do not log page text, prompts, responses, URLs beyond the existing privacy contract, DOM content, cookies, tokens, or other user content.
- Do not treat a diagnostic event, reload recovery, or memory-pressure warning as proof of root cause.

## Gates

### Gate 0 — Baseline
- Branch must descend exactly from `main@3511297d5f573598556739519bae859322578768` unless main advances and the task is explicitly rebased/re-authorized.
- Control files must identify this task before product-source edits.

### Gate 1 — Read-only design verification
- Confirm Web Runtime / Diagnostics / Focus ownership through `docs/architecture/DOMAIN_MAP.md` and current production source.
- Confirm the ordinary page-world focus path and isolated ChatGPT probe use distinct content-world execution routes.

### Gate 2 — Diagnostic implementation
- Cross-world probes are bounded, stale-safe, privacy-safe, and do not create/rebuild runtimes.
- Post-finish stall classification is evidence only and has no recovery side effects.
- Content-process epoch/counter is diagnostic metadata only.

### Gate 3 — Focused tests
- Run the narrowest matching Web runtime / ChatGPT bridge / diagnostics tests.
- New tests must cover success, timeout, stale runtime/navigation context, and content-process epoch progression.

### Gate 4 — Broader validation
- Run the required Apple Silicon build/test route for the changed Web lifecycle/diagnostics boundary.
- No merge while required CI is failing or unknown.

### Gate 5 — Fresh real-Mac incident capture
- Build/install the diagnostic version on the Air without touching Browser Profile/session data.
- Normal-use capture must distinguish `MAIN_WORLD` vs `ISOLATED_WORLD`, record post-finish classification and bounded resource/residency evidence, and preserve the raw runtime log for Web-side review.

## Acceptance criteria

This task is ready for local incident capture when:

- a single checkpoint can distinguish main-world success/timeout/stale from isolated-world success/timeout/stale;
- a finished-navigation dual-timeout can be labeled as post-finish runtime stall evidence without triggering recovery;
- content-process termination history is represented separately from WKWebView runtime identity;
- resource fields are bounded and truthfully mark unavailable attribution;
- focused tests and required CI pass on the exact diagnostic head;
- no user data or persistence behavior changes.

The task is **not** complete merely because the diagnostic build runs. Final root-cause disposition waits for a fresh real-Mac incident or sufficient negative evidence.
