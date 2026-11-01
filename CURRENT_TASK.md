# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Title:** Runtime Lifecycle / Memory redesign — Phase 7 automatic lifecycle retirement  
**Status:** `ACTIVE / PHASE 7 CONSTRUCTION AUTHORIZED`  
**Mode:** `IMPLEMENTATION / VERIFY / SELF-AUDIT TO MERGE-READY`  
**Task class:** `WEB RUNTIME / LIFECYCLE / MEMORY`  
**JSC root cause:** `UNKNOWN`

## Authorization state

Phase 6 PR #187 passed its bounded merge gate and merged to `main` as `54f2e43b0fbc224affa52d9662ac2ba5aa5b963c`.

The user explicitly authorized remote Phase 7 construction on 2026-11-01 and instructed the executor to continue through implementation, verification and self-audit until merge-ready.

This remains the same task `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

## Current authority

Program contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V5.md`

Phase 7 frozen execution contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase7_Automatic_Lifecycle_Implementation_Contract_V1.md`

Fresh implementation base:

`main@54f2e43b0fbc224affa52d9662ac2ba5aa5b963c`

Implementation branch:

`codex/ft-runtime-lifecycle-phase7-automatic-001`

## Final objective

Deliver a persistent-Slot architecture where live `WKWebView` Runtime is disposable and automatically managed by default:

```text
persistent Slot/Profile/session
→ Automatic Runtime policy
→ active/protected/recent Runtime may stay live
→ inactive Runtime reclaimed deterministically
→ Phase 6 fast restore when selected again
```

Legacy Hot/Warm/Cold must cease to be current product policy.

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

### Hard protection

- active / actually presented;
- fullscreen source;
- supplemental visible surface;
- Attention generating;
- active/pending allowed-background-media protection;
- current materialization/restoring ownership boundary.

Keep Loaded resists ordinary reclaim but may be reclaimed under critical pressure when inactive and otherwise unprotected.

## Authorized implementation scope

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

Persistence/backup files may change only if deterministic compatibility evidence requires it.

## Work packages

### WP1 — canonical model / persistence compatibility

- introduce `SlotRuntimeRetentionPreference`;
- new Slot default Automatic;
- legacy Hot -> Keep Loaded;
- legacy Warm/Cold -> Automatic;
- transitional derived legacy encoding for rollback;
- duplicate/derived Slot copy canonical preference;
- preserve Browser Profile/session/config data.

### WP2 — automatic lifecycle / container simplification

- one 30s Automatic grace;
- normal/warning/critical targets 2/1/0;
- deterministic LRU reclaim;
- Keep Loaded normal preference + critical fallback;
- remove Hot-only hidden host retention;
- keep `SlotLifecycleCoordinator` sole lifecycle writer.

### WP3 — current UI/settings retirement

- replace Residency menu with Automatic / Keep Loaded;
- remove active Warm/Cold retention controls/current product copy;
- leave old preference values stored only for rollback compatibility;
- keep presentation Pin semantics separate.

### WP4 — recovery/cache integration

- renderer termination recovery uses canonical retention preference;
- remove legacy Cold-only website-cache cleanup coupling;
- preserve Phase 6 restore, Attention, media, focus and fullscreen ownership.

### WP5 — verification / evidence

- focused migration/lifecycle/UI tests;
- full XCTest;
- Debug/Release native arm64;
- required literal-head CI;
- bounded Real-Mac lifecycle/memory evidence where remotely provable;
- fresh user-authorized self-audit;
- merge-readiness decision.

## Acceptance criteria

Merge readiness requires:

- no current Hot/Warm/Cold UI or active lifecycle decision path;
- new Slots default Automatic;
- compatibility decode/encode is deterministic and data-safe;
- 3 Automatic loaded Slots converge to one resident after grace when only one is active and no protection applies;
- rapid switching remains bounded;
- protected generation/media/fullscreen Runtime remains resident;
- Keep Loaded does not preload at launch or require hidden presentation ownership;
- critical pressure can reclaim inactive Keep Loaded after Automatic candidates;
- Phase 6 restore/session continuity remains correct;
- Runtime reclaim does not clear website/session data;
- focused/full tests, builds and required CI pass;
- fresh self-audit passes;
- any truly user-owned final runtime/UI acceptance remains `PENDING` until the user explicitly performs it.

## STOP conditions

STOP/reconcile if implementation requires:

- Browser Profile/cookie/session reset or destructive migration;
- a second lifecycle writer;
- hidden persistent WebViews as continuity objects;
- restoring Hot/Warm/Cold as current policy;
- private WebKit memory attribution/API;
- weakening hard protection semantics outside the contract;
- an unplanned persistence schema/version bump;
- material product scope outside the frozen Phase 7 paths;
- release/version work.

## Current execution state

```text
PROGRAM_CONTRACT=V5_ACCEPTED_FROZEN
PHASE6=MERGED
PHASE7_CONTRACT=ACCEPTED_FROZEN
PHASE7_IMPLEMENTATION=ACTIVE
PHASE7_BRANCH=codex/ft-runtime-lifecycle-phase7-automatic-001
NEXT_REQUIRED_GATE=WP1 IMPLEMENTATION
PROGRAM_HUMAN_ACCEPTANCE=PENDING
```
