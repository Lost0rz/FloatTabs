# FloatTabs Current Task

**Task ID:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001`  
**Title:** Adaptive Runtime lifecycle + fast restore + background efficiency  
**Status:** `ACTIVE / WP1 MACHINE GATE PASS; HUMAN UI ACCEPTANCE PENDING`
**Mode:** `WAITING — USER-OWNED HUMAN UI ACCEPTANCE; NO FURTHER IMPLEMENTATION AUTHORIZED`
**Task class:** `WEB RUNTIME / LIFECYCLE / PERFORMANCE / RESTORE UX`  
**Execution baseline:** `main@7e179aaf4dbf0c538c7c2221101fc74d16e49b98`  
**Task branch:** `codex/adaptive-lifecycle-restore-001`

## Authorization

This remains the same task and the same WP1 product objective. No successor task, new lifecycle phase, or WP2 authority is created. WP1 Corrective-002 and its bounded CI gate are complete; the remaining acceptance step is user-owned.

The implementation head `e187f83fd2c4198d3e2baa64ef5074037c87c410` adds exact-Runtime presentation readiness and closes the rapid A→B→A gap. Local verification, the single required literal-head self-hosted CI run, QA DMG, and a fresh independent exact-diff audit all pass. The cause of the earlier broad CI failures at `1a457ad…` remains unknown; the later pass does not establish their cause.

Corrective-002 implementation and machine verification are complete. This card authorizes no further product implementation. Human UI acceptance is pending for the user; WP2–WP4 remain unauthorized.

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
implementation_head = e187f83fd2c4198d3e2baa64ef5074037c87c410
implementation_parent = 3152a606d81ce7764fbb28af15524d8effde2acd
PR_194 = OPEN / DRAFT / UNMERGED
```

Verified results at `e187f83…`:

- navigation-failure presentation corrective: PASS;
- failed-WebView focus exclusion: PASS for that path;
- stale/foreign failure isolation: PASS;
- cold explicit unread readiness acknowledgement: PASS;
- cold notification unread readiness acknowledgement: PASS;
- stale unread intent replacement: PASS;
- resident fast path: PASS in focused regression;
- notification routing/privacy regressions: PASS;
- generation-protection regressions: PASS;
- A→B→A loading return reuses the same Runtime under a fresh Restoring generation, without duplicate creation or pre-ready focus/reveal: PASS;
- background finish isolation, Runtime identity replacement rejection, and failed Runtime re-entry: PASS;
- focused affected suites: `381 passed / 4 skipped / 0 failed`;
- local full XCTest: `1153 passed / 4 skipped / 0 failed`;
- local Debug arm64, Release arm64, native arm64, and package-lock checks: PASS;
- literal-head self-hosted macOS CI: PASS, run `41464559708`, job `125341924174`;
- QA DMG: PASS, run `41464559462`;
- fresh independent exact-diff / ownership / data-safety audit: PASS, no blocking or important findings.

## Corrective C — Runtime residency is not presentation readiness (corrected at `e187f83…`)

### Historical defect

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

## Machine verification gate — completed

Corrective-002 results at `e187f83…`:

- focused rapid-switch/readiness and affected presentation/materialization/failure/unread/notification/Attention regressions: PASS;
- full local XCTest: PASS (1153 passed / 4 skipped / 0 failed);
- Debug arm64, Release arm64, and native arm64 verification: PASS;
- package-lock: unchanged;
- existing task branch pushed at `e187f83…`;
- one clean literal-head self-hosted macOS CI: PASS (run `41464559708`, job `125341924174`);
- literal-head QA DMG: PASS (run `41464559462`);
- fresh independent exact-diff / ownership / data-safety audit: PASS.

### CI diagnosis boundary

The two prior `1a457ad…` CI failures remain unexplained (`CI_ROOT_CAUSE=UNKNOWN`, `TASK_ATTRIBUTION=UNPROVEN`). The single authorized next-head CI run at `e187f83…` passed, followed by the required independent audit. This does not establish the cause of the earlier failures, and no blind rerun was performed.

Do not perform destructive runner cleanup, delete user/session data, or repeatedly rerun until green.

## Human UI acceptance

```text
HUMAN_UI_ACCEPTANCE=PENDING_USER_OWNED
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
HUMAN_UI_ACCEPTANCE=PENDING_USER_OWNED

WP2_POLICY_MUTATION=NOT_STARTED
WP3_SCHEDULING_MUTATION=NOT_STARTED
WP4_INTEGRATION_MUTATION=NOT_STARTED
PR_STATE
```

Stop after machine evidence and independent review. Do not merge #194 and do not start WP2–WP4.
