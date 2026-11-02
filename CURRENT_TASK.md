# FloatTabs Current Task

**Task ID:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001`  
**Title:** Adaptive Runtime lifecycle + fast restore + background efficiency  
**Status:** `ACTIVE / WP1 CORRECTIVE-002 + CI DIAGNOSIS AUTHORIZED`  
**Mode:** `EXECUTE / DIAGNOSE — WP1 PRESENTATION READINESS CORRECTIVE`  
**Task class:** `WEB RUNTIME / LIFECYCLE / PERFORMANCE / RESTORE UX`  
**Execution baseline:** `main@7e179aaf4dbf0c538c7c2221101fc74d16e49b98`  
**Task branch:** `codex/adaptive-lifecycle-restore-001`

## Authorization

This remains the same task and the same WP1 product objective. No successor task, new lifecycle phase, or WP2 authority is created.

The implementation head `1a457adccf10fce3631963caad8aa5cfb30f4561` corrects the prior navigation-failure and cold-unread findings, but a fresh independent audit found one remaining WP1 correctness gap: rapid A→B→A can reuse an existing but not-yet-ready Runtime as though residency implied presentation readiness.

The same literal head also fails the required self-hosted macOS CI gate despite a green local full-XCTest run. CI root cause is not yet established.

This file authorizes only:

1. **WP1 Corrective-002** — establish exact-Runtime presentation readiness so existing but loading/failed Runtime cannot bypass the canonical cold gate; and
2. **bounded CI diagnosis** if the next exact implementation head reproduces the broad self-hosted CI failure.

Durable design authority remains:

`docs/architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md`

V2 is amended for the new readiness invariant; V1 remains superseded.

## Authority

- Project rules: `AGENTS.md`
- Current state: `CURRENT_STATUS.md`
- Active authorization: this file
- Durable design contract: `docs/architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md`
- Documentation routing: `docs/README.md`
- Architecture routing: `docs/architecture/README.md`
- Domain navigation: `docs/architecture/DOMAIN_MAP.md`
- Production source/tests/fresh runtime and CI evidence remain implementation truth.

## Current evidence head

```text
implementation_head = 1a457adccf10fce3631963caad8aa5cfb30f4561
prior_corrective_parent = 1d0d2e040dae38a7b468f9edcb32dd55825428fa
PR_194 = OPEN / DRAFT / UNMERGED
```

Verified results at `1a457ad…`:

- navigation-failure presentation corrective: PASS;
- failed-WebView focus exclusion: PASS for that path;
- stale/foreign failure isolation: PASS;
- cold explicit unread readiness acknowledgement: PASS;
- cold notification unread readiness acknowledgement: PASS;
- stale unread intent replacement: PASS;
- resident fast path: PASS in focused regression;
- notification routing/privacy regressions: PASS;
- generation-protection regressions: PASS;
- local full XCTest: `1149 passed / 4 skipped / 0 failed`;
- local Debug/Release/native arm64/package-lock: PASS;
- QA DMG: PASS;
- literal-head self-hosted macOS CI: FAIL on two attempts;
- independent exact-diff audit: `FINDINGS / STOP` due rapid-switch readiness gap.

## Corrective C — Runtime residency is not presentation readiness

### Defect

The current generic resident path can infer readiness from `webViewPool.existingWebView(for:) != nil`.

A concrete A→B→A race proves that inference is invalid:

```text
A starts cold materialization
→ A Runtime is created and attached under Restoring
→ select B
→ A presentation generation is cancelled
→ A Runtime remains resident in WebViewPool
→ select A before A navigation finishes
→ generic existing-WebView path can show/focus A as resident
→ A is still loading/unready
→ old A finish callback is stale for the cancelled presentation generation
```

### Frozen invariant

```text
RUNTIME_RESIDENCY != PRESENTATION_READINESS
EXISTING_WEBVIEW != READY_TO_REVEAL
```

`WebViewPool` may prove that an exact Runtime exists. Only `PanelController` may decide whether that exact Runtime is ready to be presented.

### Required readiness model

Maintain bounded presentation-readiness state for the exact current Runtime identity, with at least the semantic states:

```text
loading
ready
failed
```

The concrete Swift representation is an implementation choice, but it must be identity-bound rather than Slot-only.

Required transitions:

1. cold Runtime attach → exact Runtime identity becomes `loading`;
2. navigation finish for that identity → `ready` if the identity still matches the Runtime currently owned by `WebViewPool`, even when the presentation generation that originally created it has since been cancelled;
3. navigation failure for that identity → `failed` under the same exact identity rule;
4. Runtime identity replacement/removal → stale readiness cannot authorize the replacement Runtime;
5. presentation/UI mutation still requires the current selected target and the current presentation/materialization transaction.

### Re-entry behavior

When synchronizing a selected Slot with an existing Runtime:

- exact Runtime `ready` → preserve resident fast path;
- exact Runtime `loading` → establish/continue native Restoring ownership around that same Runtime, do not create a duplicate Runtime, and do not expose/focus the WebView until its exact readiness transition;
- exact Runtime `failed` → use the truthful existing native bounded failure/empty presentation and do not give that WebView focus;
- unknown readiness must not be silently treated as ready merely because a WebView exists. Resolve the unknown state from trustworthy existing-runtime provenance or stop and return the concrete compatibility gap rather than weakening the invariant.

### Callback separation

Navigation finish/failure has two distinct responsibilities and they must not be conflated:

```text
A. exact Runtime readiness fact update
B. current presentation reveal/error mutation
```

A may occur for an exact still-owned Runtime even if the originating presentation generation is stale.

B may occur only for the exact current selected presentation/materialization ownership.

This separation is required so A can finish in the background after selecting B, allowing a later return to A to use the ready fast path without letting stale A mutate B's current UI.

### Explicit prohibition

Do not solve this race by calling normal `release`/`hibernate` on A merely because its presentation generation was cancelled. That would turn a presentation correctness problem into Runtime lifecycle teardown and would cross the WP1 lifecycle-policy boundary.

## Corrective-002 regression requirements

Add focused regressions proving at minimum:

1. **A loading → B → A before finish:** returning A re-enters Restoring around the same existing Runtime; no duplicate Runtime is created; A is not focus-eligible or revealed as ready before its exact finish.
2. **A loading → B; A finishes while B selected; return A:** stale presentation does not mutate B, but exact A readiness becomes ready; returning A uses the resident ready fast path.
3. **Runtime replacement identity:** old Runtime finish/failure cannot mark a replacement Runtime ready/failed.
4. **Failed resident re-entry:** exact failed Runtime returns to truthful native failure/empty state and receives no Web focus.
5. prior navigation-failure regressions remain PASS.
6. prior cold explicit/notification unread readiness regressions remain PASS.
7. stale unread intent replacement remains PASS.
8. resident-ready fast path remains PASS.
9. notification exact-Slot/privacy/content regressions remain PASS.
10. generation/Attention protection regressions remain PASS.

## Machine verification gate

After Corrective-002:

- focused rapid-switch/readiness regressions;
- affected presentation/materialization/failure/unread/notification/Attention regressions;
- full local XCTest;
- Debug arm64;
- Release arm64;
- native arm64 verification;
- package-lock unchanged unless separately reconciled;
- push the existing task branch and verify remote delivery;
- run one clean literal-head self-hosted macOS CI;
- run literal-head QA DMG.

### CI diagnosis boundary

The current `1a457ad…` CI failures are a real gate blocker but their root cause is `UNKNOWN`. Local success does not prove CI is flaky, and the current evidence does not prove task causality either.

If the next exact implementation head passes the literal-head CI, proceed to a fresh independent exact-diff/ownership/data-safety audit.

If the broad WebKit-focused CI failure repeats, **STOP before further product mutation or blind rerun** and return a bounded evidence package containing:

```text
CI_RUN_ID
CI_JOB_ID
FIRST_10_FAILING_TESTS
FAILURE_SIGNATURE_GROUPS
FOCUSED_NEW_TESTS_RESULT
REPEATED_FAILURE_OVERLAP
LOCAL_FULL_XCTEST_RESULT
OBSERVABLE_RUNNER_HOST_PRECONDITIONS
TASK_CAUSALITY = PROVEN / DISPROVEN / UNKNOWN
```

Do not perform destructive runner cleanup, delete user/session data, or repeatedly rerun until green.

## Human UI acceptance

```text
HUMAN_UI_ACCEPTANCE=BLOCKED_NOT_STARTED
```

Human acceptance may begin only after:

1. Corrective-002 machine gates are green, including literal-head CI and QA DMG; and
2. a fresh independent exact-diff audit returns PASS with no Blocking/Important WP1 finding.

## WP2 / WP3 / WP4 — NOT AUTHORIZED

Do not change or implement:

- fixed normal Runtime `target=2`;
- 30-second Automatic reclaim semantics;
- pressure ordering / Keep Loaded semantics;
- explicit `WKPreferences.inactiveSchedulingPolicy`;
- adaptive warm-set or long-idle policy;
- memory-budget logic;
- snapshot/screenshot restore layer.

Current lifecycle-policy direction remains `A_FAVORED_NOT_FROZEN` and is not part of WP1.

## STOP conditions

STOP and reconcile if Corrective-002 requires or introduces:

- Runtime release/hibernate as a presentation-race workaround;
- lifecycle retention/reclaim policy mutation;
- a second lifecycle or presentation/readiness writer;
- readiness keyed only by Slot when exact Runtime identity is available;
- existing WebView residency treated as sufficient readiness;
- unready/failed WebView exposure outside native restoring/error ownership;
- stale Runtime reveal/focus or stale identity readiness transfer;
- duplicate Runtime creation for an existing loading Runtime;
- polling/timer loops instead of navigation/readiness events;
- weakened unread visibility/readiness semantics;
- private WebKit SPI or WebKit helper killing;
- reload/reset/restart recovery;
- Browser Profile/cookie/session/cache/configuration deletion/reset;
- notification privacy/exact-Slot regression;
- generation-protection regression;
- unexplained repeated literal-head CI failure without bounded diagnosis.

## Required return contract

```text
BASELINE_IDENTITY
FINAL_BRANCH_HEAD
CHANGED_FILES
REMOTE_DELIVERY

EXACT_RUNTIME_READINESS_MODEL
A_B_A_LOADING_RETURN_RESULT
BACKGROUND_FINISH_THEN_RETURN_RESULT
RUNTIME_IDENTITY_REPLACEMENT_RESULT
FAILED_RUNTIME_REENTRY_RESULT
DUPLICATE_RUNTIME_RESULT
FOCUS_REVEAL_GATING_RESULT

NAVIGATION_FAILURE_REGRESSION
COLD_UNREAD_READINESS_REGRESSION
NOTIFICATION_UNREAD_READINESS_REGRESSION
RESIDENT_FAST_PATH_RESULT
NOTIFICATION_REGRESSION_RESULT
GENERATION_PROTECTION_REGRESSION_RESULT

FOCUSED_TESTS
LOCAL_FULL_XCTEST
DEBUG_BUILD
RELEASE_BUILD
ARM64_VERIFICATION
PACKAGE_LOCK
CI_STATE
QA_DMG_STATE

IF_CI_FAILS_AGAIN:
CI_FAILURE_TAXONOMY
TASK_CAUSALITY

INDEPENDENT_AUDIT
HUMAN_UI_ACCEPTANCE=BLOCKED_OR_PENDING

WP2_POLICY_MUTATION=NOT_STARTED
WP3_SCHEDULING_MUTATION=NOT_STARTED
WP4_INTEGRATION_MUTATION=NOT_STARTED
PR_STATE
```

Stop after machine evidence and independent review. Do not merge #194 and do not start WP2–WP4.
