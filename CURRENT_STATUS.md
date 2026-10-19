# FloatTabs Current Status

**Status date:** 2026-10-19
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: ACTIVE — DIAGNOSTIC OBSERVATION RELEASE PREP**
Active task: `FT-DIAG-POST-FINISH-STALL-001` on `codex/ft-post-finish-stall-diag-001`.
Draft PR: `#138 — Diagnose post-finish Web runtime stalls across JavaScript worlds`.

## Baseline and implementation identity

- Protected baseline: `main@3511297d5f573598556739519bae859322578768`.
- Latest public release: `v0.5.4` / Build 22.
- Diagnostic implementation identity: `292d6225808ebc66a12dd36e100fe309e53a335d`.
- Current repository head `4265baa34bec55cbd74171fe78a4162675dc7e05` changes only `CURRENT_STATUS.md` and `CURRENT_TASK.md` relative to that implementation identity (`CONTROL_ONLY_DRIFT`).
- Exact current diagnostic branch head checks observed on 2026-10-19: macOS CI run `39193807897` PASS; QA DMG run `39193807895` PASS.

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

Next: complete the release-observability audit and any authorized minimal in-PR correction, run the required verification, push the exact task branch head, and return a readiness report for Web audit before merge.
