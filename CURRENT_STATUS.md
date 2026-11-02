# FloatTabs Current Status

**Status date:** `2026-11-02`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: ADAPTIVE LIFECYCLE + RESTORE PERFORMANCE — WP1 MACHINE GATE PASS; HUMAN ACCEPTANCE PENDING**

Current task: `FT-ADAPTIVE-LIFECYCLE-RESTORE-001` — **ACTIVE / WP1 MACHINE GATE PASS; HUMAN UI ACCEPTANCE PENDING (USER-OWNED)**.

Task branch:

`codex/adaptive-lifecycle-restore-001`

Draft PR:

`#194 — design: adaptive lifecycle and restore performance`

Execution baseline:

`main@7e179aaf4dbf0c538c7c2221101fc74d16e49b98`

Latest implementation / fresh audit evidence head:

`e187f83fd2c4198d3e2baa64ef5074037c87c410`

## Repository / delivery state

```text
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
MAIN_BASELINE=7E179AAF
TASK=FT-ADAPTIVE-LIFECYCLE-RESTORE-001
TASK_STATE=ACTIVE_WAITING_USER_OWNED_HUMAN_UI_ACCEPTANCE
PR_194=OPEN_DRAFT_UNMERGED
WP1_CANONICAL_COLD_PRESENTATION_GATE=IMPLEMENTED
WP1_FINDING_A_NAVIGATION_FAILURE=CORRECTED_AT_1A457AD
WP1_FINDING_B_COLD_UNREAD_READINESS=CORRECTED_AT_1A457AD
WP1_FINDING_C_RAPID_SWITCH_READINESS=CORRECTED_AT_E187F83
WP1_MACHINE_GATE=PASS
LOCAL_FULL_XCTEST=PASS_1153_4_SKIPPED_0_FAILED
LITERAL_HEAD_CI=PASS_RUN_41464559708_JOB_125341924174
PRIOR_CI_FAILURE_ROOT_CAUSE=UNKNOWN
QA_DMG=PASS_RUN_41464559462
INDEPENDENT_EXACT_DIFF_AUDIT=PASS
HUMAN_UI_ACCEPTANCE=PENDING_USER_OWNED
WP2_POLICY_MUTATION=NOT_STARTED
WP3_SCHEDULING_MUTATION=NOT_STARTED
WP4_INTEGRATION_MUTATION=NOT_STARTED
COLD_RESTORE_PRESENTATION_ROOT_CAUSE=KNOWN
COLD_RESTORE_LATENCY_ROOT_CAUSE=NARROWED
WEBKIT_FIRST_PIXEL=UNMEASURED
NORMAL_POLICY_RECOMMENDATION=A_FAVORED_NOT_FROZEN
AGGREGATE_GIB_BUDGET=DEFERRED_PLATFORM_BLOCKED
PRIVATE_WEBKIT_SPI=FORBIDDEN
```

Current durable task contract:

`docs/architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md`

V1 remains historical/superseded.

## WP1 corrective evidence at `1a457ad…`

The first two independent-audit findings are corrected:

1. exact-current cold navigation failure transitions to the native bounded empty/failure presentation and does not promote the failed WebView to current/focus ownership;
2. cold explicit/notification unread acknowledgement is retained as a bounded event-driven intent and completed only after exact-current readiness under normal presentation facts; stale replacement invalidates the old intent.

Focused regressions for those corrections pass locally. Notification routing/privacy and generation-protection regressions remain green.

Local machine verification on the literal source head:

```text
focused corrective regressions = PASS
full XCTest = 1149 passed / 4 skipped / 0 failed
Debug arm64 = PASS
Release arm64 = PASS
native arm64 verification = PASS
package lock = unchanged
QA DMG = PASS
```

## WP1 Corrective-002 evidence at `e187f83…`

The exact-Runtime readiness gate closes the rapid-switch finding while preserving the existing WebPanelContainerView Restoring surface and the resident-ready fast path. The A→B→A regression confirms same-Runtime re-entry under a fresh restoring generation, no duplicate creation or pre-ready focus/reveal, and reveal only after the exact-current finish. Background finish isolation, Runtime identity replacement rejection, and failed Runtime re-entry are also covered.

Machine verification and independent review:

```text
focused affected suites = PASS (381 passed / 4 skipped / 0 failed)
full XCTest = PASS (1153 passed / 4 skipped / 0 failed)
Debug arm64 = PASS
Release arm64 = PASS
native arm64 verification = PASS
package lock = unchanged
literal-head self-hosted macOS CI = PASS (run 41464559708 / job 125341924174)
QA DMG = PASS (run 41464559462)
fresh independent exact-diff / ownership / data-safety audit = PASS
```

The audit found no blocking or important code findings. Human UI acceptance is pending for the user and was not performed by the agent. WP2–WP4 remain not started.

## Historical WP1 finding C — Runtime residency is not presentation readiness (corrected)

The fresh exact-diff audit found an A→B→A path that can still bypass the cold presentation gate:

```text
A starts cold materialization
→ exact A WebView is created/attached under Restoring ownership
→ user selects B
→ A's presentation/materialization generation is cancelled
→ A WebView remains resident in WebViewPool
→ user returns to A before A navigation readiness
→ generic existing-WebView path treats residency as readiness
→ A WebView can be shown/focused while still unready
→ old A navigation-finish callback is ignored because its presentation generation is stale
```

This violates the V2 invariant that unready Web content must never become the user-facing surface.

Durable correction direction:

```text
RUNTIME_RESIDENCY != PRESENTATION_READINESS
EXISTING_WEBVIEW != READY_TO_REVEAL
```

`PanelController` must own exact-Runtime presentation-readiness state. `WebViewPool` continues to own Runtime existence/identity only; `SlotLifecycleCoordinator` remains the sole lifecycle/reclaim writer.

For an exact Runtime identity, presentation readiness must distinguish at least:

```text
loading
ready
failed
```

Required semantics:

- cold attach records the exact Runtime identity as loading;
- navigation finish/failure may update readiness for that exact still-current pool Runtime even if an older presentation generation was cancelled;
- only the currently selected exact presentation transaction may reveal/focus or mutate current UI;
- returning to a resident loading Runtime must re-enter Restoring around that same Runtime rather than expose it or create a duplicate Runtime;
- returning to a resident ready Runtime preserves the fast path;
- returning to a resident failed Runtime presents the truthful native failure/empty state without Web focus;
- Runtime identity replacement invalidates stale readiness state;
- Runtime residency alone never authorizes reveal or focus.

Do not solve this presentation race by releasing/hibernating A. Runtime teardown/reclaim is lifecycle policy/mechanism and is outside WP1 corrective scope.

## Historical literal-head CI failures

The literal-head self-hosted macOS CI for `1a457ad…` failed twice while the same source passed the full local XCTest suite. The reported failures were broad and concentrated in WebKit focus/page-load/geometry tests; the new WP1 corrective tests themselves passed. The next implementation head `e187f83…` passed the single required literal-head CI attempt. The cause of the earlier failures remains unknown; this pass does not retrospectively establish their cause.

Historical classification of the prior run:

```text
PRIOR_CI_FAILURE=REAL_GATE_BLOCKER
PRIOR_CI_ROOT_CAUSE=UNKNOWN
PRIOR_TASK_ATTRIBUTION=UNPROVEN
```

The required next-head check after the rapid-switch correction completed successfully at `e187f83…`. The prior failure cause remains unknown and is not inferred from the later pass.

No destructive runner cleanup, Browser Profile/session deletion, or blind rerun loop is authorized.

## Preserved boundaries

- `PanelController` owns presentation/materialization/readiness policy.
- `WebPanelContainerView` owns native Web/restoring/error surfaces.
- `WebViewPool` owns Runtime create/reuse/hibernate/restore/release and exact Runtime identity, not readiness-to-present policy.
- `SlotLifecycleCoordinator` remains the sole lifecycle/reclaim writer.
- `TabStore` owns persistent Slot selection/configuration only.
- `WebAttentionCoordinator` remains generation protection authority.
- Browser Profile/cookies/session/configuration are not cleared or reset.
- notification preview/privacy/exact-Slot behavior is unchanged.
- fixed `target=2`, 30-second reclaim semantics, pressure ordering, inactive scheduling, long-idle policy and snapshot policy remain out of WP1 scope.

## Next gate

```text
WP1 Corrective-002 machine gate and independent audit = PASS at e187f83…
→ user-owned human real-Mac acceptance is PENDING
→ no merge before human acceptance

WP2 / WP3 / WP4 remain not started and unauthorized.
```
