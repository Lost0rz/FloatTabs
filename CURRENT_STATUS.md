# FloatTabs Current Status

**Status date:** `2026-11-02`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: ADAPTIVE LIFECYCLE + RESTORE PERFORMANCE — WP1 MACHINE CORRECTIVE**

Current task: `FT-ADAPTIVE-LIFECYCLE-RESTORE-001` — **ACTIVE / WP1 CORRECTIVE REQUIRED BEFORE HUMAN ACCEPTANCE**.

Task branch:

`codex/adaptive-lifecycle-restore-001`

Draft PR:

`#194 — design: adaptive lifecycle and restore performance`

Execution baseline:

`main@7e179aaf4dbf0c538c7c2221101fc74d16e49b98`

Latest implementation/audit evidence head:

`28dcfe420c5b262405de18aa1e40ca886dcf897d`

## Repository / delivery state

```text
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
MAIN_BASELINE=7E179AAF
TASK=FT-ADAPTIVE-LIFECYCLE-RESTORE-001
TASK_STATE=ACTIVE_WP1_MACHINE_CORRECTIVE
PR_194=OPEN_DRAFT_UNMERGED
WP1_CANONICAL_COLD_PRESENTATION_GATE=PARTIAL
WP1_MACHINE_TESTS=PASS_AT_28DCFE42
WP1_INDEPENDENT_AUDIT=FINDINGS_STOP
HUMAN_UI_ACCEPTANCE=NOT_STARTED
WP2_POLICY_MUTATION=BLOCKED
WP3_SCHEDULING_MUTATION=BLOCKED
WP4_POLICY_INTEGRATION=BLOCKED
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

## WP1 implementation evidence at `28dcfe42…`

Implemented paths now converge substantially on the `PanelController` cold-presentation gate:

- ordinary cold summon;
- explicit cold Slot selection;
- exact-Slot completion-notification route;
- resident ready Runtime retains the fast path;
- stale materialization generation and rapid target replacement have focused regression coverage.

Machine verification on the exact implementation head passed:

```text
focused regressions = PASS
full XCTest = 1146 passed / 4 skipped / 0 failed
Debug arm64 = PASS
Release arm64 = PASS
native arm64 verification = PASS
package lock = unchanged
self-hosted macOS CI = PASS
QA DMG = PASS
```

The independent exact-diff audit returned **FINDINGS / STOP**. Human acceptance must not begin until both findings below are corrected and the exact corrective head is reverified.

## Corrective finding A — navigation failure presentation boundary

Current `handleSlotNavigationFailure` clears pending materialization ownership, hides the native restoring surface, and then makes the failed WebView current.

That violates the WP1 V2 invariant that an unready/failed fresh Web surface must never become the truthful user-facing presentation outside restoring/error ownership.

Required corrective outcome:

```text
exact-current cold navigation failure
→ do not reveal failed/unready Web content as ready
→ leave the cold transaction in an explicit truthful native failure/restoring state
   or transition to the existing bounded native empty/error presentation
→ no failed WebView focus/interaction ownership
→ stale/foreign failure still ignored by existing identity gates
```

The corrective should reuse existing native presentation mechanisms. Do not introduce reload/reset/restart or a second presentation writer.

## Corrective finding B — unread acknowledgement after cold readiness

Cold explicit/notification selection calls `acknowledgeUnreadAfterExplicitSelection` while the target is still restoring. Its current deferred retry runs only on the next main-queue turn. If the multi-second cold restore is still not presentation-ready, the attempt ends as `presentationNotReady` and is not retried when exact-current navigation readiness later succeeds.

Required corrective outcome:

```text
cold selected unread Slot
→ selection may record a pending acknowledgement intent
→ no acknowledgement while presentation is unready
→ exact-current readiness for the same Slot/materialization/Runtime
→ retry/complete acknowledgement exactly once under normal visibility/readiness facts
→ stale target replacement cancels/invalidates the old pending intent
```

Do not weaken unread visibility/readiness rules merely to clear the marker.

## Preserved WP1 boundaries

- `PanelController` remains the canonical presentation/materialization coordinator.
- `WebPanelContainerView` remains native Web/restoring/error-surface mechanism owner.
- `WebViewPool` remains Runtime mechanism owner.
- `SlotLifecycleCoordinator` remains the sole lifecycle/reclaim writer.
- `TabStore` remains persistent Slot selection/configuration owner.
- `WebAttentionCoordinator` remains generation protection authority.
- Browser Profile/cookies/session/configuration are not cleared or reset.
- notification preview/privacy/exact-Slot contract remains unchanged.
- fixed `target=2`, 30-second reclaim semantics, pressure ordering, inactive scheduling and snapshot policy are out of WP1 corrective scope.

## Next gate

```text
WP1 corrective A + B on existing PR #194
→ focused regressions for failure boundary + readiness-time unread acknowledgement
→ affected notification/presentation/Attention regressions
→ full XCTest
→ Debug/Release arm64 + native architecture verification
→ exact-head self-hosted macOS CI + QA DMG
→ fresh independent exact-diff audit
→ only if audit PASS: user real-Mac human acceptance
→ no merge before human acceptance

WP2 / WP3 / WP4 remain blocked.
```
