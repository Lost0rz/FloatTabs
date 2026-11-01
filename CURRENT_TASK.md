# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Title:** Runtime Lifecycle / Memory redesign — Phase 6 closeout + Phase 7 automatic lifecycle retirement  
**Status:** `ACTIVE / CONTRACT RECONCILED / PHASE 7 READY AFTER PREDECESSOR GATE`  
**Mode:** `DESIGN FROZEN / PRODUCT MUTATION HOLD`  
**Task class:** `WEB RUNTIME / LIFECYCLE / MEMORY`  
**JSC root cause:** `UNKNOWN`

## Authorization state

This remains the same Runtime Lifecycle / Memory task. The user requested a fresh audit of the final contract after Real-Mac QA showed that several legacy Hot ChatGPT Slots remained resident and memory stayed high.

The audit verified a material policy mismatch: V4 preserved Hot/Warm/Cold and therefore cannot be the program-final automatic lifecycle contract.

Task reconciliation is complete through the accepted V5 program contract and Phase 7 implementation contract.

Current product-source mutation remains held until:

1. Phase 6 PR #187 finishes its own merge gate and is merged;
2. the user explicitly starts Phase 7 construction.

## Current authority

Program contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V5.md`

Phase 6 bounded authority for PR #187:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Implementation_Contract_V1.md`

Phase 7 frozen execution contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase7_Automatic_Lifecycle_Implementation_Contract_V1.md`

## Final objective

Deliver a persistent-Slot architecture where live `WKWebView` Runtime is disposable and automatically managed by default:

```text
persistent Slot/Profile/session
→ Automatic Runtime policy
→ active/protected/recent Runtime may stay live
→ inactive Runtime reclaimed deterministically
→ Phase 6 fast restore when selected again
```

Legacy Hot/Warm/Cold is not the final product model.

## Frozen product policy

### Per-Slot preference

```text
Automatic   (default)
Keep Loaded (normal-operation opt-out)
```

Legacy compatibility:

```text
hot        -> Keep Loaded
warm/cold  -> Automatic
```

### Automatic lifecycle defaults

```text
normal target   = 2
inactive grace  = 30 seconds
warning target  = 1
critical target = 0
```

### Protection

Hard protection remains:

- active / actually presented;
- fullscreen source;
- supplemental visible surface;
- Attention generating;
- active/pending allowed-background-media protection;
- current materialization/restoring ownership boundary.

Keep Loaded is protected from ordinary Automatic reclaim but is reclaimable under critical pressure when inactive and not hard-protected.

## Predecessor gate — Phase 6 PR #187

Current PR state:

```text
PR=#187
STATE=OPEN / DRAFT / UNMERGED
PRODUCT_HEAD=76c092523fe343eacc0592bfac25086da0d0d83d
CORRECTIVE=C1-C4 APPLIED
REQUIRED_CI=PASS / RUN 1312
QA_DMG=PASS / RUN 637
REAL_MAC_RESTORE_SMOKE=PENDING COMPLETION
FRESH_EXACT_DIFF_AUDIT=PENDING
```

Do not merge until the remaining bounded Phase 6 gates pass.

Do not add Phase 7 product-source mutation to PR #187.

## Phase 7 implementation scope

Expected production owners:

- `FloatTabs/Tabs/WebAppProfile.swift`
- `FloatTabs/Tabs/TabStore.swift`
- `FloatTabs/Web/SlotLifecycleCoordinator.swift`
- `FloatTabs/Web/WebViewContainer.swift`
- `FloatTabs/Web/WebViewPool.swift`
- `FloatTabs/Panel/PanelController.swift`
- `FloatTabs/UI/ExternalTabRail.swift`
- `FloatTabs/UI/GlobalSettingsController.swift`
- `FloatTabs/Persistence/AppPreferencesStore.swift`

Persistence/backup files may change only if compatibility evidence requires it.

## Phase 7 work packages

### WP0 — predecessor / fresh-main gate

- finish PR #187 smoke;
- fresh exact-diff audit PASS;
- merge PR #187;
- refresh main/control identity;
- create one Phase 7 implementation branch/worktree.

### WP1 — canonical model / persistence compatibility

- add `SlotRuntimeRetentionPreference`;
- default Automatic;
- legacy Hot -> Keep Loaded;
- legacy Warm/Cold -> Automatic;
- transitional derived legacy encoding for rollback;
- preserve Browser Profile/session/config data.

### WP2 — automatic lifecycle / container simplification

- one 30s Automatic grace;
- targets 2 / 1 / 0;
- deterministic LRU reclaim;
- Keep Loaded normal preference + critical fallback;
- remove Hot-only hidden host retention;
- keep `SlotLifecycleCoordinator` as sole lifecycle writer.

### WP3 — current UI/settings retirement

- replace Residency menu with Automatic / Keep Loaded;
- remove Warm/Cold retention controls/current product copy;
- retain old preference values only for rollback compatibility;
- keep existing presentation Pin semantics separate.

### WP4 — recovery/cache integration

- update renderer-termination recovery metadata to new preference;
- remove legacy Cold-only website-cache cleanup coupling;
- preserve Phase 6 restore, Attention, media, focus and fullscreen ownership.

### WP5 — verification / Real-Mac evidence

- focused migration/lifecycle/UI tests;
- full XCTest;
- Debug/Release native arm64;
- required literal-head CI;
- 3-Automatic-ChatGPT Real-Mac resident/PID/memory evidence;
- fresh exact-diff audit.

## Acceptance criteria

Phase 7 merge readiness requires all of the following:

- no current Hot/Warm/Cold UI or active lifecycle policy remains;
- new Slots default Automatic;
- compatibility decode/encode is deterministic and data-safe;
- one active/no-protection 3-Slot scenario converges to one Automatic resident after grace;
- rapid switching stays bounded rather than materializing every Slot indefinitely;
- protected generation/media/fullscreen Runtime is preserved;
- Keep Loaded does not preload at launch or require hidden presentation ownership;
- critical pressure can reclaim inactive Keep Loaded after Automatic candidates;
- Phase 6 restore/session continuity remains correct;
- Runtime reclaim does not clear website/session data;
- focused/full tests, builds, CI and Real-Mac evidence pass;
- fresh exact-diff audit passes.

## STOP conditions

STOP/reconcile if Phase 7 requires:

- Browser Profile/cookie/session reset or destructive migration;
- a second lifecycle writer;
- hidden persistent WebViews as continuity objects;
- restoring Hot/Warm/Cold as current policy;
- private WebKit memory attribution/API;
- weakening hard protection semantics outside this contract;
- an unplanned persistence schema/version bump;
- material product scope outside the frozen Phase 7 paths;
- release/version work.

## Current execution state

```text
PROGRAM_CONTRACT=V5_ACCEPTED_FROZEN
PHASE6_PR187=OPEN_DRAFT_CLOSEOUT_PENDING
PHASE7_CONTRACT=ACCEPTED_FROZEN
PHASE7_IMPLEMENTATION=NOT_STARTED
PHASE7_PRODUCT_MUTATION=HELD
NEXT_REQUIRED_GATE=PHASE6_REAL_MAC_SMOKE + FRESH EXACT_DIFF AUDIT + MERGE
NEXT_USER_START_REQUIRED=YES
PROGRAM_HUMAN_ACCEPTANCE=PENDING
```
