# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-INCIDENT-DIAGNOSTICS-001`
**Title:** Complete incident-oriented diagnostics for known runtime failures
**Status:** `TERMINAL / ACCEPTED / MERGE AUTHORIZED`
**Mode:** `CLOSEOUT`
**Task class:** `DIAGNOSTICS / RUNTIME OBSERVABILITY`
**Original authorized baseline:** `main@547fa103536a0e33bdea7aa21c5d5e5faaaf3bb7`
**Accepted semantic implementation:** `b6d9e6841da92033dbc2f5fbd5c325915e1e3864`
**Delivery PR:** `#153`
**Root cause:** `UNKNOWN`

## Final disposition

The bounded diagnostics implementation is complete and accepted. The final fresh-context audit returned `PASS` after two corrective rounds, and no blocking implementation finding remains.

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

PR #153 is authorized to leave Draft and merge only when all of the following are true for its literal final head:

1. only the accepted diagnostics implementation plus this control-only closeout drift is present;
2. base remains `main` with no material authority drift;
3. GitHub reports the PR mergeable;
4. required `Build & Test (Apple Silicon arm64)` succeeds on the literal final PR head;
5. no new blocking review finding exists.

After those gates are observed, mark PR #153 Ready and merge it using its observed exact head identity. Do not release under this task.

## Terminal state

After PR #153 merges, this task remains `TERMINAL / ACCEPTED`. No follow-on engineering work is authorized by this file; any new product/runtime task requires a new `CURRENT_TASK.md` authorization.
