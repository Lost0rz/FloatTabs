# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Title:** Runtime Lifecycle / Memory redesign — Phase 7 automatic lifecycle retirement  
**Status:** `ACTIVE / MACHINE TEST CORRECTIVE`  
**Mode:** `IMPLEMENTATION / VERIFY / SELF-AUDIT TO MERGE-READY`  
**Task class:** `WEB RUNTIME / LIFECYCLE / MEMORY`  
**JSC root cause:** `UNKNOWN`

## Authorization state

Phase 6 PR #187 merged to `main` as `54f2e43b0fbc224affa52d9662ac2ba5aa5b963c`.

The user authorized remote Phase 7 construction and has now authorized continuation of the bounded machine-test corrective on PR #188.

This remains the same task `FT-RUNTIME-LIFECYCLE-MEMORY-001`; no new product scope is opened.

## Current authority

Program contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V5.md`

Phase 7 frozen execution contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase7_Automatic_Lifecycle_Implementation_Contract_V1.md`

Implementation branch:

`codex/ft-runtime-lifecycle-phase7-automatic-001`

Current PR:

`#188 OPEN / DRAFT / UNMERGED`

Last product-corrective literal head before this control sync:

`f3ac1d98041b9f6d42ab2c22ba583d26642d1ade`

## Final objective

Deliver persistent Slots whose disposable `WKWebView` Runtime is automatically managed by default:

```text
persistent Slot/Profile/session
→ Automatic Runtime policy
→ active/protected/recent Runtime may stay live
→ inactive Runtime reclaimed deterministically
→ Phase 6 restore when selected again
```

Current user-facing policy is only:

```text
Automatic   (default)
Keep Loaded
```

Legacy Hot/Warm/Cold exists only as bounded compatibility input/projection where required for rollback or external protocol compatibility.

## Frozen lifecycle defaults

```text
normal Automatic target = 2
Automatic grace         = 30 seconds
warning target           = 1
critical target          = 0
```

Hard protection remains:

- active / actually presented;
- fullscreen source;
- supplemental visible surface;
- Attention generating;
- active/pending allowed-background-media protection;
- current materialization/restoring ownership.

Keep Loaded resists ordinary reclaim but may be reclaimed under critical pressure when inactive and otherwise unprotected.

## Completed Phase 7 product corrective

At `f3ac1d98...`, the bounded product corrective already removed/reconciled:

- current Hot/Warm/Cold shortcut bindings;
- Shortcuts Settings legacy Mode section;
- dead Hot-only hidden WebView host architecture;
- historical 120-second production hidden-active grace;
- stale Cold-only runtime-release callback behavior;
- current-product HUD projection from legacy `setResidency` compatibility input.

No new production-runtime defect is proven by the current failing CI evidence.

## Current machine-test corrective evidence

Required CI run `1322` uploaded XCTest diagnostics and failed while compiling the test target. Exact blockers:

```text
WebsiteCacheCleanupTests.swift:674
PerformanceSettingsViewController has no member displayedWarmRetention

WebsiteCacheCleanupTests.swift:675
PerformanceSettingsViewController has no member displayedColdRelease

AppCommandControllerTests.swift:115
AppShortcutCatalog has no member residencyBindings
```

The test build stops before runtime XCTest execution. Therefore the authorized corrective is to update/retire obsolete legacy-product assertions, not to restore removed production APIs.

## Authorized corrective scope

### Test files

Primary bounded paths:

- `FloatTabsTests/AppCommandControllerTests.swift`
- `FloatTabsTests/WebsiteCacheCleanupTests.swift`

Other test-only files may change only if a fresh compiler/test failure proves another obsolete Phase 7 assertion.

### Control files

- `CURRENT_STATUS.md`
- `CURRENT_TASK.md`

### Production files

**No production-file mutation is currently authorized by this corrective evidence.**

If a fresh machine failure proves a real production defect, STOP and reconcile before changing runtime/product code.

## Corrective requirements

### Shortcut test contract

- remove assumptions that current `AppShortcutCatalog` contains Hot/Warm/Cold residency bindings;
- current shortcut count must reflect the retired Mode bindings;
- retain coverage for bounded external `setResidency` compatibility protocol separately from user-configurable shortcut catalog;
- do not recreate `residencyBindings` merely for tests.

### Performance Settings test contract

- remove assertions that Warm retention and Cold release timing are current UI rows;
- legacy stored timing values may remain in persistence for rollback compatibility but must not project back into current Performance Settings;
- keep Website Storage/cache tests intact;
- do not add test-only or production compatibility properties that emulate removed UI.

## Verification gates

After the bounded test corrective:

1. `git diff --check` equivalent hygiene;
2. full XCTest PASS;
3. Debug arm64 build PASS;
4. Release arm64 build PASS;
5. literal PR head passes required `Build & Test (Apple Silicon arm64)`;
6. QA DMG for the same literal head PASS;
7. bounded Real-Mac lifecycle evidence where remotely provable;
8. fresh exact-diff self-audit PASS;
9. only then decide merge readiness.

Human UI/runtime acceptance remains `NOT_STARTED` until explicitly performed by the user.

## STOP conditions

STOP/reconcile if the test corrective would require:

- modifying Browser Profile/cookie/session data;
- restoring Hot/Warm/Cold current controls or policy;
- a production runtime behavior change not proven by fresh machine evidence;
- hidden persistent WebViews;
- release/version work;
- an unplanned persistence schema migration.

## Current execution state

```text
PROGRAM_CONTRACT=V5_ACCEPTED_FROZEN
PHASE6=MERGED
PHASE7_CONTRACT=ACCEPTED_FROZEN_RECONCILED
PHASE7_PR=#188_OPEN_DRAFT_UNMERGED
PHASE7_PRODUCT_CORRECTIVE=COMPLETE
PHASE7_LAST_PRODUCT_HEAD=f3ac1d98041b9f6d42ab2c22ba583d26642d1ade
CURRENT_STAGE=MACHINE_TEST_CORRECTIVE
CURRENT_BLOCKER=STALE_LEGACY_TEST_TARGET_COMPILE
NEXT_REQUIRED_GATE=BOUNDED_TEST_CORRECTIVE_THEN_FULL_XCTEST
PROGRAM_HUMAN_ACCEPTANCE=NOT_STARTED
```
