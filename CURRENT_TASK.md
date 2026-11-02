# FloatTabs Current Task

**Task ID:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001`  
**Title:** Adaptive Runtime lifecycle + fast restore + background efficiency — WP1  
**Status:** `COMPLETE / HUMAN ACCEPTED / MERGE CLOSEOUT ONLY`  
**Mode:** `CLOSEOUT — NO FURTHER WP1 PRODUCT IMPLEMENTATION AUTHORIZED`  
**Task class:** `WEB RUNTIME / LIFECYCLE / PERFORMANCE / RESTORE UX`  
**Execution baseline:** `main@7e179aaf4dbf0c538c7c2221101fc74d16e49b98`  
**Task branch:** `codex/adaptive-lifecycle-restore-001`

## Authorization

WP1 is complete. The canonical cold-presentation gate, exact-Runtime readiness, navigation-failure truthfulness, unread readiness gating, rapid A→B→A re-entry, notification exact-Slot routing, and generation protection have passed machine verification, independent audit, and user-owned real-Mac acceptance.

This file authorizes **closeout only** for PR #194. No additional WP1 behavior change and no WP2 product mutation may be added to this branch.

Durable WP1 design authority:

`docs/architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md`

## Final accepted evidence

Semantic implementation head:

`e187f83fd2c4198d3e2baa64ef5074037c87c410`

Pre-closeout branch head with green machine gates:

`1a77fae92c53708e2c6c373301c825187fdb1de4`

Accepted machine evidence:

```text
focused affected suites = PASS (381 passed / 4 skipped / 0 failed)
full XCTest = PASS (1153 passed / 4 skipped / 0 failed)
Debug arm64 = PASS
Release arm64 = PASS
native arm64 verification = PASS
package lock = unchanged
implementation-head macOS CI = PASS (41464559708 / 125341924174)
implementation-head QA DMG = PASS (41464559462)
control-head macOS CI at 1a77fae = PASS (41466335384 / 125348105768)
control-head QA DMG at 1a77fae = PASS (41466335512)
independent exact-diff / ownership / data-safety audit = PASS
```

Human acceptance:

```text
HUMAN_UI_ACCEPTANCE=PASS
WP1_PRESENTATION=PASS
WP1_EXACT_RUNTIME_READINESS=PASS
WP1_NOTIFICATION_COLD_ROUTE=PASS
WP1_RAPID_SWITCH_PRESENTATION=PASS
WP1_DATA_SAFETY=PASS
```

The user's acceptance log `FloatTabs-WP1-Human-20261102-231725.jsonl` shows 23 deferred cold materializations, 23 actually-visible restoring-surface events, 23 attachments, zero readiness failures, and the notification route using the canonical cold gate. The user explicitly requested WP1 closeout.

## Separate next-phase evidence — not WP1 work

The same run proves the shipped healthy-state lifecycle policy is too aggressive for legitimate multi-Slot usage: nine reconciliations in roughly 50 seconds observed `managed_resident_count=3`, fixed `target=2`, and `eviction_count=1` with `reason=reconcile`.

This is **WP2 lifecycle-policy evidence**, not a reason to reopen WP1.

The next-phase design direction requested by the user is:

```text
NO_FIXED_NORMAL_RESIDENT_COUNT
PINNED_KEEP_LOADED = NO_AUTOMATIC_EXIT
AUTOMATIC = STAGED_AUTOMATIC_LIFECYCLE
NORMAL_RECLAIM = TIME/STATE BASED, NOT TAB-COUNT BASED
MEMORY_PRESSURE = PROGRESSIVE AUTOMATIC RECLAIM SIGNAL
```

This direction is not implementation authority on PR #194. It must be reconciled into a clean post-merge WP2 task/branch/PR before code changes.

## Closeout gate

Required closeout sequence:

1. update `CURRENT_STATUS.md`, this task file, V2, and PR #194 description to final WP1 PASS;
2. run/observe exact final control-head macOS CI and QA DMG;
3. if both are green and PR identity is unchanged, mark PR #194 ready and merge using the repository's normal merge method;
4. verify fresh `origin/main` contains the merge;
5. only then create the clean WP2 task/branch/PR and new lifecycle-policy design authority.

## STOP conditions

- do not add WP2 code or policy changes to PR #194;
- do not modify fixed `target=2`, 30-second reclaim, pressure ordering, Keep Loaded semantics, scheduling policy, or snapshot behavior during WP1 closeout;
- do not merge if the exact final control-head machine gate is red or PR head moved unexpectedly;
- do not release a public build as part of this closeout;
- do not clear Browser Profile/cookies/session/cache/configuration;
- do not infer a cause for the historical CI failures; it remains unknown.

## Final state

```text
WP1=COMPLETE
HUMAN_UI_ACCEPTANCE=PASS
PR_194=MERGE_CLOSEOUT
WP2=NOT_STARTED
WP3=NOT_STARTED
WP4=NOT_STARTED
```
