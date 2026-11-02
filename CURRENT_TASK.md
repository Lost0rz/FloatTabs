# FloatTabs Current Task

**Task ID:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001`  
**Title:** Adaptive Runtime lifecycle + fast restore + background efficiency  
**Status:** `ACTIVE / WP1 MACHINE CORRECTIVE AUTHORIZED`  
**Mode:** `EXECUTE — WP1 PRESENTATION CORRECTIVE`  
**Task class:** `WEB RUNTIME / LIFECYCLE / PERFORMANCE / RESTORE UX`  
**Execution baseline:** `main@7e179aaf4dbf0c538c7c2221101fc74d16e49b98`  
**Task branch:** `codex/adaptive-lifecycle-restore-001`

## Authorization

This remains the same task and the same WP1 objective. No new task is created.

Current implementation head `28dcfe420c5b262405de18aa1e40ca886dcf897d` substantially converges ordinary cold summon, explicit cold selection and exact-Slot notification routing on the canonical `PanelController` cold-presentation gate. Machine verification is green, but the independent exact-diff audit found two correctness gaps inside the already-authorized WP1 contract.

This file authorizes only the bounded correction of those two findings before human UI acceptance.

Durable design authority remains:

`docs/architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md`

No V3 design contract is required because the findings are implementation violations of already-frozen V2 invariants, not a design change.

## Authority

- Project rules: `AGENTS.md`
- Current state: `CURRENT_STATUS.md`
- Active authorization: this file
- Durable design contract: `docs/architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md`
- Documentation routing: `docs/README.md`
- Architecture routing: `docs/architecture/README.md`
- Domain navigation: `docs/architecture/DOMAIN_MAP.md`
- Production source/tests/fresh runtime evidence remain implementation truth.

## Current verified implementation evidence

Observed implementation/audit head:

`28dcfe420c5b262405de18aa1e40ca886dcf897d`

Verification at that head:

```text
focused presentation/notification/lifecycle/Attention regressions = PASS
full XCTest = 1146 passed / 4 skipped / 0 failed
Debug arm64 = PASS
Release arm64 = PASS
native arm64 = PASS
package lock = unchanged
self-hosted macOS CI = PASS
QA DMG = PASS
independent exact-diff audit = FINDINGS / STOP
human UI acceptance = PENDING / NOT STARTED
```

## Corrective A — navigation failure must not reveal failed Web content

Current exact-current navigation failure path clears pending materialization ownership, hides Restoring and then makes the failed WebView current.

Required behavior:

```text
cold navigation failure for exact-current Runtime
→ preserve identity validation
→ do not transition failed WebView to ready/current user-facing ownership
→ terminate the pending cold transaction into a truthful native bounded failure/empty state
   using existing presentation mechanisms
→ no failed WebView focus/interaction ownership
→ stale/foreign Runtime failure remains ignored
```

Implementation constraints:

- reuse `PanelController` / `WebPanelContainerView` ownership;
- do not add another presentation writer;
- do not reload/reset/restart automatically;
- do not clear Browser Profile/session/cache/configuration;
- do not change lifecycle retention policy.

## Corrective B — unread acknowledgement must complete at exact cold readiness

Current explicit/notification cold selection may initiate unread acknowledgement while the target presentation is still restoring. The one-turn deferred retry can terminate as `presentationNotReady` before a multi-second cold restore completes, with no readiness-time retry.

Required behavior:

```text
selected unread cold target
→ preserve existing visibility/readiness rules
→ retain bounded pending acknowledgement intent only while the exact selection/presentation remains current
→ exact-current materialization readiness succeeds
→ retry/complete acknowledgement exactly once using normal presentation facts
→ stale target/materialization replacement cancels or invalidates the old intent
```

Do not acknowledge merely because navigation finished if the normal presentation facts still say the Slot is not actually presented/eligible.

The preferred correction is to connect the existing explicit-selection acknowledgement lifecycle to the exact-current readiness boundary in `PanelController`, not to introduce timers or repeated polling.

## Acceptance for this corrective

Add/update focused regressions proving at minimum:

1. exact-current navigation failure does not hide restoring and expose the failed WebView as ready/current;
2. failure resolves into the existing bounded native error/empty presentation and leaves Web focus unavailable for the failed Runtime;
3. stale/foreign navigation failure cannot mutate the current restoring presentation;
4. cold explicit selection with unread remains unread while restoring and acknowledges after exact-current readiness when normal visibility/readiness facts are satisfied;
5. cold completion-notification selection follows the same unread readiness behavior;
6. rapid A→B→A or target replacement does not allow stale pending unread acknowledgement to clear the wrong Slot;
7. resident fast path remains unchanged;
8. notification exact-Slot/privacy/content semantics remain unchanged;
9. generation protection remains unchanged.

## Verification gate

After the corrective implementation:

- focused failure-boundary and unread-readiness regressions;
- affected presentation/materialization/notification/Attention regressions;
- full XCTest;
- Debug arm64;
- Release arm64;
- native arm64 verification;
- package-lock unchanged unless separately reconciled;
- push the existing task branch and verify remote delivery;
- literal-head self-hosted macOS CI;
- literal-head QA DMG;
- fresh independent exact-diff/ownership/data-safety audit.

Human UI acceptance remains **PENDING** and must not begin until the fresh independent audit returns PASS with no Blocking/Important WP1 finding.

## WP2 / WP3 / WP4 — NOT AUTHORIZED

Do not change or implement:

- fixed normal Runtime `target=2`;
- 30-second Automatic reclaim semantics;
- pressure ordering / Keep Loaded semantics;
- explicit `WKPreferences.inactiveSchedulingPolicy`;
- adaptive warm-set or long-idle policy;
- memory-budget logic;
- snapshot/screenshot restore layer.

Current lifecycle-policy direction remains `A_FAVORED_NOT_FROZEN` and is not part of this corrective.

## STOP conditions

STOP and reconcile if the corrective requires or introduces:

- a second lifecycle or presentation writer;
- lifecycle-policy mutation;
- failed/unready WebView exposure outside native restoring/error ownership;
- timer/polling loop for unread acknowledgement instead of event-driven readiness;
- weakening actual-presentation/readiness requirements for unread clearing;
- stale Runtime/Slot acknowledgement or focus;
- private WebKit SPI or WebKit helper killing;
- reload/reset/restart recovery;
- Browser Profile/cookie/session/cache/configuration deletion/reset;
- notification privacy/exact-Slot regression;
- generation-protection regression;
- required test/build/CI failure attributable to the corrective.

## Required return contract

```text
BASELINE_IDENTITY
FINAL_BRANCH_HEAD
CHANGED_FILES
REMOTE_DELIVERY

NAVIGATION_FAILURE_PRESENTATION_RESULT
FAILED_WEBVIEW_FOCUS_RESULT
STALE_FAILURE_RESULT
COLD_UNREAD_READINESS_RESULT
NOTIFICATION_UNREAD_READINESS_RESULT
STALE_UNREAD_INTENT_RESULT
RESIDENT_FAST_PATH_RESULT
NOTIFICATION_REGRESSION_RESULT
GENERATION_PROTECTION_REGRESSION_RESULT

FOCUSED_TESTS
FULL_XCTEST
DEBUG_BUILD
RELEASE_BUILD
ARM64_VERIFICATION
PACKAGE_LOCK
CI_STATE
QA_DMG_STATE
INDEPENDENT_AUDIT
HUMAN_UI_ACCEPTANCE=PENDING

WP2_POLICY_MUTATION=NOT_STARTED
WP3_SCHEDULING_MUTATION=NOT_STARTED
WP4_INTEGRATION_MUTATION=NOT_STARTED
PR_STATE
```

Stop after machine evidence and independent review. Do not merge #194 and do not start WP2–WP4.
