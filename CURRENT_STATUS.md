# FloatTabs Current Status

**Status date:** `2026-11-02`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 7 MACHINE TEST CORRECTIVE**

Current program/task: `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

Current execution state: `V5 CONTRACT FROZEN / PHASE 6 MERGED / PHASE 7 PRODUCT CORRECTIVE COMPLETE / MACHINE TEST CORRECTIVE ACTIVE`.

## Canonical state

```text
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
JSC_ROOT_CAUSE=UNKNOWN

PHASE_1_SAFE_HIBERNATE_RESTORE=COMPLETE / MERGED
PHASE_2_READY_UNREAD_DECOUPLING=COMPLETE / MERGED
PHASE_3_NATIVE_COMPLETION_NOTIFICATION=COMPLETE / MERGED
PHASE_4_REFERENCE_DERIVED_RUNTIME_MANAGEMENT=DELIVERED FOUNDATION / TARGET POLICY SUPERSEDED BY V5 PHASE 7
PHASE_5_BACKGROUND_GENERATION_THRIFT=COMPLETE / MERGED
PHASE_6_PERCEIVED_FAST_RESTORE=COMPLETE / MERGED
PHASE_6_PR=#187 MERGED
PHASE_6_MERGE_COMMIT=54f2e43b0fbc224affa52d9662ac2ba5aa5b963c

PROGRAM_CONTRACT=V5 ACCEPTED / FROZEN
TARGET_POLICY=AUTOMATIC + KEEP_LOADED
NORMAL_AUTOMATIC_TARGET=2
AUTOMATIC_INACTIVE_GRACE=30S
WARNING_AUTOMATIC_TARGET=1
CRITICAL_AUTOMATIC_TARGET=0

PHASE_7_CONTRACT=ACCEPTED / FROZEN / RECONCILED
PHASE_7_BRANCH=codex/ft-runtime-lifecycle-phase7-automatic-001
PHASE_7_PR=#188 OPEN / DRAFT / UNMERGED
PHASE_7_LITERAL_HEAD=f3ac1d98041b9f6d42ab2c22ba583d26642d1ade
PHASE_7_PRODUCT_CORRECTIVE=COMPLETE
PHASE_7_MACHINE_TEST_CORRECTIVE=ACTIVE
PHASE_7_REQUIRED_CI_RUN=1322 / FAIL / UNIT_TEST_TARGET_COMPILE
PROGRAM_HUMAN_ACCEPTANCE=NOT_STARTED
CI_RUNNER=macmini-floattabs-01 / self-hosted / macOS / ARM64 / mac-mini-ci
```

## Current authority

Program contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V5.md`

Phase 7 execution contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase7_Automatic_Lifecycle_Implementation_Contract_V1.md`

`CURRENT_TASK.md` is the only active mutation authorization.

## Phase 7 product state at `f3ac1d98...`

The bounded product corrective is already present:

- current Hot/Warm/Cold keyboard shortcut bindings are removed;
- Shortcuts Settings no longer exposes a Mode section;
- dead Hot-only hidden WebView host ownership is removed;
- production hidden-active grace is no longer the historical 120-second second retention boundary;
- legacy `setResidency` remains only as a bounded compatibility adapter and no longer projects current-product HUD semantics;
- Browser Profile/session/cache safety boundaries remain unchanged.

No current evidence authorizes further production-runtime mutation in this corrective.

## Current machine blocker

Fresh XCTest diagnostics from required CI run `1322` show that the test target fails to compile before runtime tests execute. The bounded stale assertions are:

```text
FloatTabsTests/WebsiteCacheCleanupTests.swift:674
PerformanceSettingsViewController has no member displayedWarmRetention

FloatTabsTests/WebsiteCacheCleanupTests.swift:675
PerformanceSettingsViewController has no member displayedColdRelease

FloatTabsTests/AppCommandControllerTests.swift:115
AppShortcutCatalog has no member residencyBindings
```

These failures are obsolete Phase 4 / legacy Hot-Warm-Cold product assertions. They must be rewritten or retired to validate the accepted Phase 7 Automatic / Keep Loaded product contract. Do not restore removed production APIs merely to keep stale tests green.

## Current execution order

```text
control-state sync
→ bounded test-contract corrective only
→ full XCTest
→ Debug/Release arm64 verification
→ literal-head required CI + QA DMG
→ bounded Real-Mac lifecycle evidence where remotely provable
→ fresh exact-diff self-audit
→ merge-readiness decision
```

## Safety boundary

This corrective must not:

- clear or migrate Browser Profile cookies/session/site data;
- add a second lifecycle writer;
- restore Hot/Warm/Cold as current product policy;
- add hidden persistent WebViews;
- modify release/version metadata;
- use compatibility shims to preserve obsolete current-product tests.
