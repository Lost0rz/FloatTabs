# FloatTabs Current Status

**Status date:** `2026-11-02`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: ADAPTIVE LIFECYCLE + RESTORE PERFORMANCE — WP1 COMPLETE / MERGE CLOSEOUT**

Current task: `FT-ADAPTIVE-LIFECYCLE-RESTORE-001` — **WP1 COMPLETE / HUMAN ACCEPTED / PR #194 MERGE-READY SUBJECT TO FINAL CONTROL-HEAD CHECKS**.

Task branch:

`codex/adaptive-lifecycle-restore-001`

PR:

`#194 — design: adaptive lifecycle and restore performance`

Execution baseline:

`main@7e179aaf4dbf0c538c7c2221101fc74d16e49b98`

WP1 semantic implementation head:

`e187f83fd2c4198d3e2baa64ef5074037c87c410`

Pre-closeout final branch head with green machine gates:

`1a77fae92c53708e2c6c373301c825187fdb1de4`

## Repository / delivery state

```text
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
TASK=FT-ADAPTIVE-LIFECYCLE-RESTORE-001
WP1_CANONICAL_COLD_PRESENTATION_GATE=COMPLETE
WP1_EXACT_RUNTIME_READINESS=COMPLETE
WP1_MACHINE_GATE=PASS
WP1_INDEPENDENT_AUDIT=PASS
WP1_HUMAN_UI_ACCEPTANCE=PASS
WP1=COMPLETE
PR_194=OPEN_UNMERGED_CLOSEOUT
WP2_POLICY_MUTATION=NOT_STARTED
WP3_SCHEDULING_MUTATION=NOT_STARTED
WP4_INTEGRATION_MUTATION=NOT_STARTED
PRIOR_CI_FAILURE_ROOT_CAUSE=UNKNOWN
WEBKIT_FIRST_PIXEL=UNMEASURED
AGGREGATE_GIB_BUDGET=DEFERRED_PLATFORM_BLOCKED
PRIVATE_WEBKIT_SPI=FORBIDDEN
```

Current durable WP1 contract:

`docs/architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md`

V1 remains historical/superseded.

## WP1 final evidence

WP1 Corrective-002 established exact-Runtime presentation readiness (`loading / ready / failed`) owned by `PanelController`, preserving the native `WebPanelContainerView` Restoring surface and resident-ready fast path.

Machine and independent evidence:

```text
focused affected suites = PASS (381 passed / 4 skipped / 0 failed)
full XCTest = PASS (1153 passed / 4 skipped / 0 failed)
Debug arm64 = PASS
Release arm64 = PASS
native arm64 verification = PASS
package lock = unchanged
implementation-head macOS CI = PASS (run 41464559708 / job 125341924174)
implementation-head QA DMG = PASS (run 41464559462)
control-head macOS CI at 1a77fae = PASS (run 41466335384 / job 125348105768)
control-head QA DMG at 1a77fae = PASS (run 41466335512)
fresh independent exact-diff / ownership / data-safety audit = PASS
```

User-owned real-Mac acceptance on the exact WP1 build is **PASS**. The uploaded acceptance log `FloatTabs-WP1-Human-20261102-231725.jsonl` records:

- `23` `panel.materialization.deferred` events;
- `23` `panel.restoring_surface.window_visible` events;
- `23` `panel.materialization.attached` events;
- `0` `panel.materialization.readiness_failed` events;
- notification cold routing entering the canonical restoring/materialization path;
- rapid switching exercising cancellation/re-entry without a reported WP1 blank/stale/focus defect.

The user reports the WP1 presentation/focus/notification behavior as acceptable and explicitly requested WP1 closeout.

## Separate lifecycle-policy evidence for WP2

The same human run confirms a **separate lifecycle-policy problem**, not a WP1 presentation failure.

During a three-Runtime frequent-switch window, the log records nine `slot_lifecycle.runtime_budget` reconciliations in roughly 50 seconds with:

```text
managed_resident_count = 3
target = 2
eviction_count = 1
reason = reconcile
```

Each reconciliation can immediately hibernate an Automatic Runtime and cause the next revisit to cold-restore. This proves the current normal-policy fixed resident count can create Runtime thrash for a legitimate multi-Slot working set.

Durable product direction for the next lifecycle-policy work:

- normal healthy-state lifecycle must **not** use a fixed resident-count cap as the reclaim trigger;
- user-pinned / `Keep Loaded` Slots are a strong retention request and do not participate in automatic exit;
- non-pinned `Automatic` Slots follow staged inactivity / pressure-driven automatic lifecycle rules;
- time/state/pressure determine eligibility and reclaim; the number of currently resident Tabs is not itself a normal reclaim reason;
- Browser Profile/session/configuration data safety and WP1 cold-presentation correctness remain regression boundaries.

This evidence belongs to the next WP2 design/authorization. WP2 implementation has not started on PR #194.

## Preserved boundaries

- `SlotLifecycleCoordinator` remains the sole lifecycle/reclaim policy writer.
- `WebViewPool` remains Runtime mechanism and identity owner.
- `PanelController` remains presentation/materialization/readiness owner.
- `WebAttentionCoordinator` remains generation/Attention protection authority.
- Browser Profile/cookies/session/configuration are never cleared as lifecycle recovery.
- notification exact-Slot/privacy semantics remain unchanged.
- no private WebKit SPI, helper killing, reload/reset/restart workaround, or fake per-Slot/aggregate RAM attribution is authorized.

## Next gate

```text
WP1 = COMPLETE
→ finish PR #194 closeout on an exact control head
→ merge #194 only after the final control-head checks are green
→ create a clean post-merge WP2 lifecycle-policy task/branch/PR
→ freeze WP2 staged lifecycle contract before product mutation
```

Do not add WP2 implementation to PR #194.
