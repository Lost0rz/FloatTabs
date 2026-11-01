# FloatTabs Runtime Lifecycle — Phase 7 Automatic Lifecycle Implementation Contract V1

**Program:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Phase:** `7 — Automatic Lifecycle Simplification + Legacy Residency Retirement`  
**Status:** `ACCEPTED / FROZEN / IMPLEMENTATION NOT STARTED`  
**Parent contract:** `FloatTabs_Runtime_Lifecycle_Memory_Contract_V5.md`  
**Execution baseline:** fresh `main` after PR #187 is dispositioned and merged

This document freezes the Phase 7 product mutation boundary. It does not authorize product construction before the predecessor gate is complete and the user explicitly starts implementation.

## 1. Objective

Replace the current Hot/Warm/Cold residency product model with one automatic lifecycle and one explicit Keep Loaded preference, while preserving Browser Profile/session data and reusing the existing hibernate/restore architecture.

Target flow:

```text
persistent Slot
→ Automatic by default
→ active / protected = resident
→ inactive = short grace + bounded LRU budget
→ reclaim via existing hibernate boundary
→ Phase 6 restore on next use
```

## 2. Verified current-state findings

Current production on the Phase 6 branch still contains all of these legacy paths:

- `WebAppProfile.swift` — persisted `SlotResidencyPolicy.hot / warm / cold`; default `.warm`;
- `SlotLifecycleCoordinator.swift` — Hot excluded from automatic candidates; Warm/Cold separate timers; managed target `3`; critical pressure still excludes Hot;
- `WebViewContainer.swift` — Hot-only host views keep inactive Hot `WKWebView` attached and hidden;
- `ExternalTabRail.swift` — user-facing Residency submenu exposes Hot/Warm/Cold;
- `GlobalSettingsController.swift` — Performance Settings exposes Warm retention and Cold release controls;
- `AppPreferencesStore.swift` — Warm/Cold timing preferences remain active;
- `WebViewPool.swift` — inactive Hot renderer termination reloads immediately while other policies defer;
- `PanelController.swift` — Runtime release has a legacy Cold-only website-cache cleanup branch;
- current docs describe Hot as explicit permanent pin and Warm/Cold as managed classes.

The Phase 6 restore path itself does not depend on preserving these legacy classes.

## 3. Frozen product model

### Canonical preference

```swift
enum SlotRuntimeRetentionPreference: String, Codable, CaseIterable, Equatable {
    case automatic
    case keepLoaded
}
```

User-facing names:

- `Automatic`
- `Keep Loaded`

`Automatic` is the default for every newly created Slot.

Keep Loaded explanatory copy must state that critical memory pressure may still reclaim an inactive Runtime.

### No current Hot/Warm/Cold product controls

After Phase 7:

- no current Tab menu exposes Hot/Warm/Cold;
- no current Settings UI exposes Warm retention or Cold release delay;
- no Runtime decision may branch on legacy Warm-vs-Cold;
- old raw values remain decode/rollback compatibility only.

## 4. Persistence compatibility contract

`WebAppProfile` becomes canonical on `runtimeRetentionPreference`.

Decode order:

```text
runtimeRetentionPreference
else residencyPolicy hot  -> keepLoaded
else residencyPolicy warm -> automatic
else residencyPolicy cold -> automatic
else                       -> automatic
```

Transitional encoding writes:

```text
runtimeRetentionPreference = canonical value
residencyPolicy            = derived compatibility projection
```

Projection:

```text
automatic  -> warm
keepLoaded -> hot
```

Rules:

- the compatibility field is never consulted when the new canonical field is present;
- old Warm/Cold UserDefaults values remain stored but unused;
- do not clear, rewrite or migrate Browser Profile WebKit data;
- do not bump `StoredWebAppState` or backup schema unless implementation proves additive compatibility is insufficient;
- if a schema bump becomes necessary, STOP before mutation and reconcile the migration contract.

## 5. Lifecycle policy contract

### Automatic inactivity

Use one fixed automatic inactivity grace:

`30 seconds`.

This replaces user-configurable Warm/Cold timing as current policy.

### Managed targets

```text
normal  = 2 Automatic resident runtimes
warning = 1 Automatic resident runtime
critical = 0 Automatic resident runtimes
```

The count is a deterministic lifecycle target, not an RSS estimate.

### Ordinary eligibility

Automatic Runtime is reclaimable only when:

```text
resident
AND inactive / not actually presented
AND no fullscreen or supplemental-visible ownership
AND no Attention generating protection
AND no active/pending allowed-background-media protection
AND no current materialization/restoring transaction requiring ownership stability
```

### Ordinary ranking

```text
older lastUsedAt first
→ UUID lexical tie-break
```

If the normal target is exceeded, reclaim eligible inactive Automatic Runtime immediately even if its grace has not expired. If the target is not exceeded, reclaim when the grace expires.

### Keep Loaded

Normal/warning operation:

- do not reclaim merely because the Automatic budget is exceeded or normal grace expires;
- detach from presentation normally; do not retain a special hidden host view;
- renderer-termination recovery may continue to reload immediately for an already materialized Keep Loaded Slot if current ownership remains valid.

Critical pressure:

- first reclaim every eligible inactive Automatic Runtime;
- then inactive Keep Loaded Runtime becomes eligible if still necessary and no hard protection applies;
- hard-protected Runtime remains protected.

## 6. Container/runtime ownership simplification

`WebPanelContainerView` must stop encoding residency policy as presentation ownership.

Required direction:

- all ordinary selected Runtime uses the same presentation attachment path;
- inactive resident Runtime may remain alive in `WebViewPool` without remaining attached to a hidden Hot host;
- remove `hotHostViews`, `retainHotSlots` and Hot-only attach/deactivate behavior when no longer required by current behavior;
- `SlotLifecycleCoordinator` decides residency; the container only presents/detaches views.

Do not replace Hot hosts with another hidden-persistent-WebView continuity mechanism.

## 7. Website cache boundary

Remove the legacy assumption:

```text
Cold Runtime release -> website cache cleanup
```

Phase 7 Runtime reclaim must not trigger cache deletion based on retired residency class.

Website cache cleanup remains owned by existing Website Storage settings/coordinator and may operate independently under its own retention/size policy.

## 8. Phase 6 integration boundary

Phase 7 must not redesign Phase 6.

For reclaimed Automatic or critical-reclaimed Keep Loaded Slots:

```text
select/summon
→ Phase 6 restoring shell
→ current materialization generation
→ WebViewPool restore/create
→ exact-current navigation-backed readiness
→ restoring surface removed
→ canonical focus/input resumes
```

Resident Runtime remains direct.

## 9. Expected production scope

Primary expected production files:

- `FloatTabs/Tabs/WebAppProfile.swift`
- `FloatTabs/Tabs/TabStore.swift`
- `FloatTabs/Web/SlotLifecycleCoordinator.swift`
- `FloatTabs/Web/WebViewContainer.swift`
- `FloatTabs/Web/WebViewPool.swift`
- `FloatTabs/Panel/PanelController.swift`
- `FloatTabs/UI/ExternalTabRail.swift`
- `FloatTabs/UI/GlobalSettingsController.swift`
- `FloatTabs/Persistence/AppPreferencesStore.swift`

Persistence/backup files may change only if deterministic compatibility tests require it:

- `FloatTabs/Persistence/ProfileRepository.swift`
- `FloatTabs/Persistence/FloatTabsBackupService.swift`

Any production scope outside these paths is a STOP/reconciliation trigger unless mechanically required with no semantic expansion.

## 10. Expected test scope

At minimum:

- `FloatTabsTests/TabStoreTests.swift`
- `FloatTabsTests/ProfileRepositoryTests.swift`
- `FloatTabsTests/FloatTabsBackupServiceTests.swift`
- `FloatTabsTests/WebAttentionLifecycleTests.swift`
- `FloatTabsTests/WebViewPoolTests.swift`
- `FloatTabsTests/ExternalShellTests.swift`
- `FloatTabsTests/SettingsInformationArchitectureTests.swift`
- `FloatTabsTests/WebsiteCacheCleanupTests.swift`

Update or retire old tests that assert Hot/Warm/Cold current-product semantics. Preserve historical evidence in docs rather than keeping obsolete tests green through compatibility shims.

## 11. Work packages

### WP0 — predecessor and control gate

Before product mutation:

1. finish PR #187 bounded Real-Mac restore smoke;
2. clean/accept the known comment-only exact-diff churn;
3. obtain fresh independent Phase 6 exact-diff audit PASS;
4. merge PR #187;
5. refresh `main` and control files;
6. create Phase 7 implementation branch/worktree from fresh main.

No Phase 7 product mutation occurs before this gate.

### WP1 — canonical model + compatibility

Implement `SlotRuntimeRetentionPreference` and compatibility decode/encode.

Acceptance:

- new Slot defaults Automatic;
- legacy Hot -> Keep Loaded;
- legacy Warm/Cold -> Automatic;
- new data round-trips;
- derived legacy projection supports rollback;
- Browser Profile references/session data untouched;
- duplicate/derived Slot behavior copies the canonical new preference.

### WP2 — lifecycle policy + container simplification

Replace legacy timer/ranking branches and Hot-only host ownership.

Acceptance:

- one 30s Automatic grace;
- normal target 2, warning 1, critical 0;
- over-budget Automatic LRU reclaim works;
- Keep Loaded normal behavior works without hidden host attachment;
- critical may reclaim inactive Keep Loaded only after Automatic candidates and only when no hard protection applies;
- lifecycle mutation still executes only through `SlotLifecycleCoordinator` -> existing `WebViewPool.hibernate/release` boundaries.

### WP3 — current UI/settings retirement

Replace the Residency menu with Automatic / Keep Loaded and remove active Warm/Cold retention settings.

Acceptance:

- no current Hot/Warm/Cold product copy/control remains;
- no Warm/Cold timing control remains active;
- old UserDefaults values are not deleted;
- accessibility labels/tooltips reflect current semantics;
- no confusion with the existing presentation Pin feature.

### WP4 — recovery/cache integration + broad regressions

Reconcile WebContent termination recovery metadata and remove Cold-only cache cleanup coupling.

Acceptance:

- active/Keep Loaded renderer termination behavior remains bounded and correct;
- Automatic inactive renderer recovery does not recreate Runtime unnecessarily;
- Runtime reclaim does not delete website/session data;
- Phase 6 restore tests remain green;
- fullscreen/focus/Attention/media protections remain unchanged in authority.

### WP5 — verification / Real-Mac evidence

Run focused/full tests and Real-Mac lifecycle evidence.

Required Real-Mac scenarios:

1. **3 Automatic ChatGPT Slots** — load A/B/C, leave one active, no generating/media/fullscreen protection; after grace, product resident-set evidence converges to one Automatic Runtime and old WebContent PIDs for reclaimed Runtime disappear.
2. **Rapid A -> B -> A** — recent grace avoids unnecessary churn; stale Phase 6 requests cannot attach to newer selection.
3. **Background generation** — Automatic generating Slot stays resident; after completion/protection ends it becomes reclaimable normally.
4. **Keep Loaded** — after activation it survives normal inactivity without special hidden presentation; app relaunch does not proactively materialize it solely because of preference.
5. **Session continuity** — reclaim/restore preserves Browser Profile login/session state.
6. **Memory evidence** — capture aggregate FloatTabs/WebKit process-tree RSS/helper counts before and after reclaim. Use it as directional support, not exact per-Slot attribution.

Critical-pressure Keep Loaded ordering may be proven deterministically through existing/debug pressure injection plus tests rather than forcing unsafe real system pressure.

## 12. Verification gates

### Gate A — focused migration/model tests

PASS for legacy/new encode/decode and Slot copy/default behavior.

### Gate B — focused lifecycle tests

PASS for grace, budget, ranking, protection, warning/critical and Keep Loaded semantics.

### Gate C — UI/settings regressions

PASS for current controls/copy and removal of legacy current-product settings.

### Gate D — broad machine verification

- full XCTest PASS;
- Debug arm64 build PASS;
- Release arm64 build PASS;
- native architecture verification PASS.

### Gate E — required repository CI

Literal PR head passes `Build & Test (Apple Silicon arm64)` on the established self-hosted Apple Silicon runner.

### Gate F — bounded Real-Mac lifecycle/memory evidence

The WP5 scenarios above pass with content-free lifecycle/process evidence.

### Gate G — fresh exact-diff audit

Verify canonical ownership, migration safety, no legacy active policy, no hidden Runtime retention workaround, no session/cache destruction and no Phase 6 regression.

Only after Gates A-G pass may Phase 7 merge.

## 13. Program-final integrated audit after Phase 7 merge

After Phase 7 merge, run one fresh integrated audit across Phases 1-7 before final user acceptance.

It must cover:

- Slot/Profile/config vs disposable Runtime ownership;
- hibernate/restore and stale callback safety;
- Automatic/Keep Loaded policy and legacy compatibility;
- Attention generating protection vs Ready/unread decoupling;
- Phase 6 perceived-fast restore ordering;
- focus/fullscreen/media integration;
- website-cache/session boundary;
- Diagnostics evidence-only authority;
- no duplicate lifecycle writer/private WebKit/reset workaround;
- final required CI/source identity.

## 14. STOP conditions

STOP and reconcile if implementation requires:

- deleting/resetting Browser Profile, cookies, sessions or persisted website data;
- a second Runtime lifecycle writer;
- keeping hidden heavyweight WebViews solely for fast switching;
- restoring Hot/Warm/Cold as current user-facing policy;
- per-Slot private WebKit memory attribution;
- arbitrary reload/reset/double-navigation as lifecycle behavior;
- weakening Attention generating/media/fullscreen hard protections without separate authorization;
- schema/version migration not covered by the frozen compatibility contract;
- material production files outside Section 9;
- release/version work.

## 15. Execution hold

```text
PHASE7_CONTRACT=ACCEPTED_FROZEN
PHASE7_PRODUCT_IMPLEMENTATION=NOT_STARTED
PREDECESSOR_PR187=OPEN_DRAFT
NEXT_REQUIRED_GATE=PHASE6_CLOSEOUT_AND_MERGE
NEXT_USER_START_REQUIRED=YES
```

After the user explicitly starts Phase 7 construction and PR #187 is merged, execute this contract without reopening the Hot/Warm/Cold product-design question unless a STOP condition produces contrary evidence.
