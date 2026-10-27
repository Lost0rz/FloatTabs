# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-INCIDENT-DIAGNOSTICS-001`
**Title:** Complete incident-oriented diagnostics for known runtime failures
**Status:** `ACTIVE / BOUNDED CI-TEST CORRECTIVE`
**Mode:** `EXECUTE`
**Task class:** `DIAGNOSTICS / RUNTIME OBSERVABILITY`
**Original authorized baseline:** `main@547fa103536a0e33bdea7aa21c5d5e5faaaf3bb7`
**Accepted semantic implementation:** `b6d9e6841da92033dbc2f5fbd5c325915e1e3864`
**Delivery PR:** `#153`
**Current literal PR head:** `914a6e80c0a6aa847b24ccd88cdb2c0daa8955b4`
**Root cause:** `UNKNOWN`

## Bounded CI/test corrective authorization

This is a same-Task, test-only stabilization corrective for the terminal closeout blocker. The accepted production semantic implementation remains `b6d9e6841da92033dbc2f5fbd5c325915e1e3864`; this corrective must not reopen product implementation scope.

Allowed changes are limited to `CURRENT_TASK.md`, `CURRENT_STATUS.md` and `FloatTabsTests/WebFocusAdapterTests.swift`. Production source under `FloatTabs/**`, recovery policy, Slot/runtime ownership, Attention semantics, timeout thresholds, Browser Profiles, persistence, sessions, user data, CI workflows, versioning and release behavior are prohibited.

Merge remains `BLOCKED` until the new literal final head passes the required macOS arm64 CI. The accepted semantic identity and historical runtime `ROOT_CAUSE=UNKNOWN` must be preserved.

## Final disposition

The bounded diagnostics implementation is complete and accepted. The final fresh-context audit returned `PASS` after two corrective rounds, and no blocking implementation finding remains.

The closeout is temporarily suspended by `FT-RUNTIME-INCIDENT-DIAGNOSTICS-001-CI-STABILITY-CORRECTIVE-03` for one bounded XCTest fixture-stability correction. This does not alter the accepted production semantics.

The user explicitly authorized governance closeout, Ready-for-review transition, and merge on 2026-10-26. This closeout authorization supersedes the construction-phase prohibition on merging under the active implementation task. It does **not** authorize a version bump, release, distribution, Browser Profile/session reset, or any product-data mutation.

Control-only changes to `CURRENT_STATUS.md` / `CURRENT_TASK.md` after the accepted semantic implementation are `CONTROL_ONLY_DRIFT` under `AGENTS.md`; they do not invalidate the accepted implementation evidence. The literal final PR head must still pass the repository-required `Build & Test (Apple Silicon arm64)` check before merge.

## Accepted outcome

The implementation completes the planned incident-oriented diagnostic evidence without changing product recovery or user-data semantics:

1. shared incident identity and bounded automatic cross-domain snapshots;
2. one correlated incident across WebContent termination, recovery disposition, navigation progress and healthy closure;
3. post-finish/navigation stall trigger plus explicit healthy/superseded/stale/runtime-replaced terminal outcomes;
4. memory-pressure evidence with host RSS, per-Slot decision reasoning and explicit unavailable public WebContent attribution;
5. Attention timeout, failure, invalid, stale, suppression and late-callback evidence with suppression/timeout kept semantically distinct;
6. previous-application restore terminal outcome evidence;
7. page-app age-at-capture correctness, bounded category-diverse retention, per-kind drop accounting and privacy-safe structural classifications;
8. redundant low-value logging reduction without reducing actual health-probe cadence.

## Final verification evidence

Accepted semantic head: `b6d9e6841da92033dbc2f5fbd5c325915e1e3864`

Observed verification:

- focused Attention suite: `95 passed / 0 failed` on the final corrective;
- full local suite: `1,382 passed / 0 failed`;
- exact-semantic-head macOS CI run `40335936727` / run `#1131`: `SUCCESS`;
- required `Build & Test (Apple Silicon arm64)`: `SUCCESS`;
- exact-semantic-head QA DMG run `40335936732` / run `#525`: `SUCCESS`;
- third fresh-context evidence audit: `PASS`;
- unresolved blocking findings: `NONE`.

The final literal PR head may advance only through this governance closeout control update. Required CI must be reread on that literal head before merge.

The corrective must establish a deterministic test-only supported ChatGPT URL fixture for `testStallTerminationRecoveryClosesSameIncidentWhenRuntimeIsHealthy()` while continuing to call the real `SlotNavigationObserver.captureCrossWorldLivenessOnce()` and asserting the same incident ID and `healthy_current_runtime` closure. No sleep, retry, skip, weakened assertion, production URL eligibility change or timeout change is authorized.

## Preserved safety boundaries

The accepted change does **not** modify:

```text
RECOVERY_POLICY=UNCHANGED
RELOAD_RESET_BEHAVIOR=UNCHANGED
RESIDENCY_POLICY=UNCHANGED
ATTENTION_BUSINESS_STATE=UNCHANGED
FOCUS_POLICY=UNCHANGED
TIMEOUT_THRESHOLDS=UNCHANGED
BROWSER_PROFILES=UNCHANGED
WEBSITE_SESSIONS_DATA=UNCHANGED
PERSISTENCE=UNCHANGED
USER_DATA=UNTOUCHED
WEB_CONTENT_PROCESS_MEMORY_ATTRIBUTION=unavailable_public_api
```

The historical runtime root cause remains unknown. Diagnostics improve future incident evidence; they do not claim a causal fix.

## Merge closeout gate

PR #153 remains merge-blocked during this corrective. It may be marked Ready and merged only after all of the following are true for its new literal final head:

1. only the accepted diagnostics implementation plus this control-only closeout drift is present;
2. base remains `main` with no material authority drift;
3. GitHub reports the PR mergeable;
4. required `Build & Test (Apple Silicon arm64)` succeeds on the literal final PR head;
5. no new blocking review finding exists.

The corrective-specific gates are:

1. the named single test passes once;
2. the named single test passes `20/20` consecutive repetitions without skip;
3. the full `WebFocusAdapterTests` suite passes;
4. the full FloatTabs XCTest suite passes with `1,382 tests`, `0 failures` and existing deliberate skips only;
5. production source and CI workflow are unchanged;
6. exact-head macOS arm64 CI succeeds, with QA DMG recorded if automatically triggered.

After those gates are observed, mark PR #153 Ready and merge it using its observed exact head identity. Do not release under this task.

## Terminal state

After the corrective gates pass, this task may return to `TERMINAL / ACCEPTED / MERGE AUTHORIZED`, with the difference recorded as `TEST_ONLY_CI_STABILIZATION + CONTROL_ONLY_DRIFT`. No follow-on product/runtime engineering work is authorized by this file; any new product/runtime task requires a new `CURRENT_TASK.md` authorization.
