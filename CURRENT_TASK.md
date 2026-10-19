# FloatTabs Current Task

**Task ID:** `FT-DIAG-POST-FINISH-STALL-001`
**Title:** Prepare bounded post-finish Web runtime diagnostics for long-term Air observation
**Status:** `WAITING — WEB AUDIT BEFORE MERGE`
**Mode:** `DIAGNOSTIC`
**Task class:** `INCIDENT_INVESTIGATION`
**Base:** `main@3511297d5f573598556739519bae859322578768`
**Branch:** `codex/ft-post-finish-stall-diag-001`
**Draft PR:** `#138`
**Initial diagnostic source identity:** `292d6225808ebc66a12dd36e100fe309e53a335d`
**Control reconciliation commit:** `e7e790a98fc7da473a99d7c289ecd6bf39b3c908`
**Final semantic implementation identity:** `0bfb2be83adda65e883931a49806c5c12364eaf2`

## Objective

Audit and, only if needed, minimally correct PR #138 so the diagnostic infrastructure can be published for long-term normal-use observation on the Air. A fresh Air stall is not a prerequisite for merging diagnostic infrastructure; it remains evidence for the later causal investigation. Root cause remains `UNKNOWN`, and this task does not claim the bug is fixed.

Mac mini is the development, probe, audit, build, and release-preparation machine. Air is the long-term real-use observation and fresh-incident capture target.

## Current verified basis

- Gate 5 Air host verification passed on 2026-10-19 with the exact arm64 Release app built from branch revision `4265baa34bec55cbd74171fe78a4162675dc7e05`.
- Installed/running identity was `/Applications/FloatTabs.app`, v0.5.4 / Build 22, PID `91025`, arm64, exact embedded source revision.
- Release runtime logs contained `web_runtime.cross_world_liveness` and the required fields. No stall occurred (`NO_INCIDENT_YET`).
- External harness attributed one WebContent, one Networking, and one GPU process to the host PID; its five-sample/five-second passive capture completed without warnings and reported 430.1 MB average combined RSS.
- Exact semantic-head macOS CI run `39208850435` and QA DMG run `39208850566` both passed; PR #138 is OPEN, DRAFT, and MERGEABLE.
- Full XCTest passed: 1,342 passed, 3 skipped, 0 failed. The two focused callback-budget/classification tests also passed. Debug arm64 and clean-head Release arm64 builds passed. The Release QA DMG passed codesign and image verification and remains local-only under `/private/tmp`.
- Gate 5 Release runtime evidence remains from revision `4265baa34bec55cbd74171fe78a4162675dc7e05`; the final correction only bounds hung probe callbacks and distinguishes `suppressed` from timeout. The Release build of final semantic head is `0bfb2be83adda65e883931a49806c5c12364eaf2`, version 0.5.4 / Build 22, arm64, with exact source revision and clean tree metadata.
- Root cause remains `UNKNOWN`; no recovery behavior is authorized.

## Authorized scope

1. Reconcile this task's status and merge gate in `CURRENT_STATUS.md` and `CURRENT_TASK.md`, commit those control-only changes, and push the existing task branch before semantic work.
2. Audit PR #138 for Release probe availability, incident-state discrimination, bounded diagnostic retention, a usable Release export/log access path, provenance, privacy, and long-run probe/task/observer lifecycle safety.
3. If a concrete gap blocks reliable first-round incident evidence, make only the smallest diagnostics-related correction and focused regression tests within PR #138.
4. Run verification proportional to the changed boundary. Required for final readiness: relevant focused diagnostics/Web Runtime tests, Debug arm64 build, Release arm64 build, Release-field verification, privacy regression, and applicable retention/export regression. Run full XCTest if semantic production code changes.
5. Push the exact authorized branch head, keep PR #138 Draft, and return an evidence-based release-readiness report for Web audit before merge.

## Merge and release gate

PR #138 may enter merge review when all of the following pass on the final semantic head:

- diagnostic-observability audit;
- required tests and Debug/Release arm64 validation;
- exact-head CI and QA DMG checks;
- live PR base/head, required review, and mergeability checks at the repository-host boundary.

A fresh Air incident is not a merge prerequisite. It is required only for the later causal investigation. This task does not authorize merging PR #138 or publishing an observation release. Keep the PR Draft through this work.

## Audit outcome and current handoff

- Probe availability: Release production code records both world outcomes and the required navigation, Web-process, host-memory, and attribution fields in standard Runtime Diagnostics. Gate 5 observed 70 such Release events.
- Incident discrimination: main success / isolated timeout, dual timeout, and Web-process termination/epoch changes remain distinguishable. Both worlds succeeding cannot establish a responsive UI. No single event establishes cause.
- Retention/export: local history uses 10 MiB segments, a 10-segment cap, and 7-day retention. Warning/error/fault events flush immediately; export flushes pending data first. Release Settings → Advanced provides `Export Recent Diagnostics…` and `Open Saved Logs Folder`.
- Provenance/privacy: exported metadata includes app version, build number, source revision, exact/tree state, architecture, session ID, and schema version. Sanitization is applied before OSLog and again before disk persistence; no content, cookie, token, session, or Browser Profile secret is recorded by this instrumentation.
- Lifecycle gap found and corrected: WebKit JavaScript completion handlers cannot be cancelled after the Swift timeout. The new per-world request budget caps outstanding callbacks at two, emits `suppressed` after saturation, and does not count suppression as a timeout. The periodic observer remains one cancelable task per observer at 30-second intervals.
- Changed files: `FloatTabs/Web/SlotNavigationObserver.swift` and `FloatTabsTests/WebFocusAdapterTests.swift` in semantic commit `0bfb2be8`; `CURRENT_STATUS.md` and `CURRENT_TASK.md` contain the control reconciliation and final audit state.
- Release XCTest could not compile the existing test target because unrelated tests reference `DEBUG`-only helper methods. The production Release app/DMG build passes, and Gate 5 supplied actual Release runtime field evidence.
- No fresh stall was observed. `ROOT_CAUSE=UNKNOWN`; no product recovery behavior or user data changes were made.

All task-local technical gates are complete. The remaining handoff is independent Web audit before PR #138 can enter merge review. The task remains unmerged and unpublished.

## Diagnostic evidence requirements

The standard Release diagnostic path must emit `web_runtime.cross_world_liveness` with:

- `main_world_probe_outcome`;
- `isolated_world_probe_outcome`;
- `navigation_phase`;
- `observed_web_process_epoch`;
- `observed_web_process_termination_count`;
- `host_resident_size_bytes`;
- `web_process_resource_attribution` (remain explicitly unavailable when public APIs cannot prove child attribution).

The audit must establish that evidence can distinguish main success / isolated timeout, dual timeout, and Web-process termination/epoch changes. “Both success but UI frozen” must remain a possible reported observation that does not establish root cause. No single event is causal proof.

Local diagnostic history must be bounded through rotation/retention and normal flush behavior. An Air user must be able to save first-round evidence from the Release app without Xcode, a repository checkout, sudo, or the benchmark harness. Exported evidence must preserve app/build/source identity, exact/tree state, architecture, session ID, and schema version.

Instrumentation must remain privacy-safe and bounded over long runtimes: no prompt/response body, page text, cookies, session/token, or Browser Profile secrets; no unbounded polling/task/observer accumulation or repeated timer leak.

## Explicitly unauthorized

- Root-cause claims or claims that the stall is fixed before evidence supports them.
- Automatic or new reload/reset/rebuild/recovery behavior; changes to WebView recovery semantics.
- Hot/Warm/Cold product-policy changes or synthetic stress/stall reproduction.
- Deleting, clearing, resetting, or rewriting Browser Profiles, cookies, sessions, WebsiteData, Slots, preferences, backups, or user configuration.
- Unrelated product fixes, merging PR #138, or publishing a release.

## Stop conditions

Stop and report if the task branch/PR/authority changes materially, the worktree contains unknown work, a proposed correction expands beyond diagnostics, safe lifecycle ownership cannot be established, or a required exact-head validation fails. Keep unsupported required claims `UNKNOWN`; do not infer root cause from a recovery boundary.

## Handoff acceptance

Return audit findings, any concrete gaps and minimal corrections, changed files, test/build/CI/QA evidence, exact local and remote head, PR state, root-cause status, and remaining merge/release gates. Final state is a Web-audit handoff, not merge or release.
