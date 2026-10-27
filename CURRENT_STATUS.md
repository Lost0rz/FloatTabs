# FloatTabs Current Status

**Status date:** 2026-10-27
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: GOVERNANCE CLOSEOUT / MERGE AUTHORIZED**

Current task: `FT-RUNTIME-INCIDENT-DIAGNOSTICS-001` — `TERMINAL / ACCEPTED`

## Current verified baseline

```text
PUBLIC_RELEASE=v0.5.7
PUBLIC_BUILD=25
RELEASE_STATE=PUBLISHED / VERIFIED
ACCEPTED_SEMANTIC_IMPLEMENTATION=b6d9e6841da92033dbc2f5fbd5c325915e1e3864
DELIVERY_PR=#153
LAST_CORRECTIVE_CI_HEAD=7f1f9e76d66776e8772376375034ff96f85c7080
ROOT_CAUSE=UNKNOWN
```

FloatTabs v0.5.7 / Build 25 remains the current public release. No version bump or release is authorized by the completed diagnostics task.

## Accepted diagnostics outcome

The runtime incident diagnostics work is complete and accepted. The implementation now provides bounded incident-oriented evidence for the known runtime failure classes while preserving existing product behavior and data safety.

Accepted coverage includes:

- shared incident IDs and bounded automatic cross-domain snapshots;
- WebContent termination → recovery disposition → navigation progress → first healthy closure under one incident identity;
- post-finish/navigation stall terminal outcomes including healthy recovery, superseding navigation, stale context and runtime replacement;
- memory-pressure host/process-boundary evidence and per-Slot lifecycle decision reasoning without unsupported WebContent attribution;
- Attention timeout/failure/invalid/stale/suppressed/late-callback evidence with typed semantic separation;
- previous-application restore terminal outcomes;
- page-app age-at-capture correctness, bounded category-diverse retention, per-kind drop counters and privacy-safe structural error categories;
- rate limiting of redundant low-value diagnostic records without reducing health-probe cadence.

## Verification state

Final accepted semantic head: `b6d9e6841da92033dbc2f5fbd5c325915e1e3864`

Verified evidence:

```text
CORRECTIVE_HEAD=7f1f9e76d66776e8772376375034ff96f85c7080
FOCUSED_SINGLE_TEST=1 PASS / 0 FAIL
FOCUSED_REPETITION=20/20 PASS
WEBFOCUSADAPTERTESTS=26 PASS / 0 FAIL
FULL_LOCAL_SUITE=1382 EXECUTED / 0 FAIL
MACOS_CI_RUN=40426931567 / SUCCESS
REQUIRED_ARM64_JOB=SUCCESS
QA_DMG_RUN=40426931534 / SUCCESS
FRESH_CONTEXT_AUDIT=PASS
UNRESOLVED_BLOCKERS=NONE
```

The final governance closeout modifies only `CURRENT_STATUS.md` / `CURRENT_TASK.md`. Under `AGENTS.md`, this is `CONTROL_ONLY_DRIFT`; semantic implementation evidence remains valid. The repository-required CI must still succeed on the literal final PR head before merge.

## Safety / unchanged product semantics

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

The diagnostics work does not claim to have found or fixed the historical runtime root cause. `ROOT_CAUSE=UNKNOWN` is intentionally preserved until a future real incident provides causal evidence.

## CI stability corrective closeout

The same-Task `TEST_ONLY_CI_STABILIZATION` is complete. The accepted production semantic implementation remains `b6d9e6841da92033dbc2f5fbd5c325915e1e3864`; the only intervening difference is `TEST_ONLY_CI_STABILIZATION + CONTROL_ONLY_DRIFT`.

The flaky test was caused by WebKit runner timing leaving `WKWebView.url` unavailable when the production supported-ChatGPT admission guard ran. A test-target-only `WKWebView` fixture now returns a deterministic supported ChatGPT URL while the real production liveness method and incident assertions remain in use. No production source or CI workflow changed.

## Repository lifecycle

- Historical cleanup PR #151: `MERGED`.
- Diagnostics authorization PR #152: `MERGED`.
- Diagnostics implementation PR #153: accepted for merge closeout after final literal-head required CI.
- Accepted implementation branch/worktree ownership remains `codex/ft-runtime-incident-diagnostics-001` / dedicated worktree until PR #153 merges and lifecycle cleanup is separately verified.
- No release/distribution action is authorized by this closeout.

## Closeout disposition

The prior closeout authorization is restored after the corrective passed its focused repetition, full-suite and exact-literal-head CI gates.

PR #153 remains the existing delivery vehicle. No new PR is authorized. Its merge disposition is `MERGE AUTHORIZED`; this execution did not merge it.

Any subsequent product/runtime engineering work requires a new `CURRENT_TASK.md` authorization.
