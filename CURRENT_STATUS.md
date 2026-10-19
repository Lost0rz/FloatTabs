# FloatTabs Current Status

**Status date:** 2026-10-19
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: WAITING — WEB AUDIT BEFORE MERGE**
Active task: `FT-DIAG-POST-FINISH-STALL-001` on `codex/ft-post-finish-stall-diag-001`.
Draft PR: `#138 — Diagnose post-finish Web runtime stalls across JavaScript worlds`.

## Baseline and implementation identity

- Protected baseline: `main@3511297d5f573598556739519bae859322578768`.
- Latest public release: `v0.5.4` / Build 22.
- Initial diagnostic source identity: `292d6225808ebc66a12dd36e100fe309e53a335d`.
- Control reconciliation commit: `e7e790a98fc7da473a99d7c289ecd6bf39b3c908`.
- Final semantic implementation identity: `0bfb2be83adda65e883931a49806c5c12364eaf2`; its remote branch ref matched exactly before this final control-only audit receipt.
- Exact semantic-head macOS CI run `39208850435` and QA DMG run `39208850566` both PASS. PR #138 remains OPEN, DRAFT, and MERGEABLE.
- Current repository head additionally contains only the final `CURRENT_STATUS.md` / `CURRENT_TASK.md` audit receipt; it does not change the semantic implementation identity.
- Local validation on the exact semantic head: full XCTest 1,342 passed / 3 skipped / 0 failed; Debug arm64 build passed; Release arm64 QA DMG passed signature and image verification. The DMG is local-only under `/private/tmp`; it was not installed or published.

## Release observability audit

- Release standard diagnostics include `web_runtime.cross_world_liveness`, both world outcomes, navigation phase, Web-process epoch/termination count, host RSS, and the explicit attribution value `unavailable_public_api` when public APIs cannot prove child attribution. Gate 5 had already emitted 70 standard Release events with these fields; no stall was observed.
- Main success / isolated timeout and dual timeout remain distinct outcomes. Only two consecutive finished-state dual timeouts produce a confirmed diagnostic. Web-process termination/epoch changes are separately recorded. Both probes succeeding does not prove that the UI is responsive, and no event is treated as root-cause proof.
- Cross-world sampling is one task per observer at a 30-second interval. Restart cancels the previous task and observer teardown cancels it. Each JavaScript world now has at most two outstanding WebKit evaluation callbacks; a saturated request is recorded as `suppressed`, not timeout. This bounds callbacks retained by a non-returning WebKit completion while preserving candidate/confirmation samples.
- Runtime history rotates at 10 MiB per segment, retains at most 10 managed segments, and prunes after 7 days. Notice events use a 1.5-second debounced flush; warning/error/fault events flush immediately. Export requests a flush before copying history.
- Release Settings → Advanced contains `Export Recent Diagnostics…` and `Open Saved Logs Folder`. Export appends sanitized app/build/source revision, exact/tree state, architecture, session ID, and schema version metadata. Standard diagnostics default to enabled; the independent long-term performance checkpoint toggle is optional for these cross-world samples.
- Privacy sanitization applies before logging and again at the writer boundary; sensitive key families include prompts, response/body/content/page text, cookies, tokens, and profile/session secrets. No product data or preferences were changed in this task.
- A Release XCTest attempt could not compile the existing test target because unrelated test cases depend on `DEBUG`-only helpers. The production Release arm64 build and QA DMG passed; Release field availability is also supported by the Gate 5 Release runtime log and the production code path is not guarded by `DEBUG`.

```text
OBSERVABILITY_AUDIT=PASS_WITH_CALLBACK_BUDGET_CORRECTION
ROOT_CAUSE=UNKNOWN
INCIDENT_STATE=NO_INCIDENT_YET
```

## Gate 5 Air host verification

Gate 5 host verification passed on 2026-10-19 against the exact installed Release build from diagnostic branch revision `4265baa34bec55cbd74171fe78a4162675dc7e05`:

- Installed and running app: `/Applications/FloatTabs.app`, v0.5.4 / Build 22, arm64, PID `91025`; executable and embedded source revision match the diagnostic head.
- Standard Release runtime diagnostics emitted `web_runtime.cross_world_liveness`; 70 events were present in the local runtime log at the last inspection. The required probe, navigation, Web-process epoch/termination, host RSS, and attribution fields were observed.
- The public runtime field `web_process_resource_attribution` remains `unavailable_public_api`; this is an explicit boundary, not a guessed PID attribution.
- The external benchmark harness independently attributed one WebContent, one Networking, and one GPU helper to PID `91025`. A five-sample, five-second passive capture completed without warnings; average combined host/helper RSS was 430.1 MB.
- A stale Debug-only `BenchmarkControl.json` record for absent PID `50104` was removed after confirming its recorded loopback port had no listener. No Profile, Slot, cookie, session, WebsiteData, preference, or other product data was changed.
- No fresh stall occurred: `INCIDENT_STATE=NO_INCIDENT_YET`.

## Diagnostic boundary and incident state

For supported ChatGPT runtimes, the Web Runtime records bounded, content-free main-page and FloatTabs-isolated-world liveness results, navigation/runtime context, observed Web-process epoch and termination count, and host resident memory. A first finished-state dual timeout is candidate evidence; a second consecutive timeout is required for confirmed `POST_FINISH_RUNTIME_STALL` evidence. Instrumentation does not trigger recovery.

```text
FAULT_BOUNDARY=POST_FINISH_WEB_RUNTIME_JS_EXECUTION
FAULT_BOUNDARY_CONFIDENCE=HIGH
ROOT_CAUSE=UNKNOWN
MEMORY_PRESSURE_DIRECT_TRIGGER=NOT_PROVEN
FRESH_INCIDENT=NOT_OBSERVED
PRODUCT_RECOVERY_CHANGE_AUTHORIZED=NO
USER_DATA_CHANGE_AUTHORIZED=NO
BROWSER_PROFILE_DATA_CHANGE_AUTHORIZED=NO
```

## Observation release path

The user-approved deployment strategy is:

- Mac mini: development, probes, audit, builds, and release preparation.
- Air: long-term normal-use observation and fresh incident capture.

Fresh Air incident evidence is for the subsequent causal investigation and no longer blocks publication of the diagnostic infrastructure. PR #138 may enter merge review only after the diagnostic-observability audit, required tests, and exact-head CI/QA gates pass. It remains Draft during this preparation; this task does not authorize merging or publishing a release. Any observation release must state that root cause is unknown and the stall is not claimed fixed.

Next: Web audit of the pushed exact head before any merge review. Fresh Air incident evidence remains for later causal investigation; no merge or observation release has been performed or authorized here.
