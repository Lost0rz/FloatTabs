# FloatTabs Runtime Lifecycle & Memory Contract V5

**Status:** `ACCEPTED / FROZEN`  
**Accepted:** `2026-11-01`  
**Program:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Supersedes:** `FloatTabs_Runtime_Lifecycle_Memory_Contract_V4.md` for current program execution

## 1. Why V5 exists

V5 reconciles the program with fresh Real-Mac QA and current production source after Phase 6 implementation.

The installed Phase 6 corrective build proved that the restore architecture can be exercised on a real Mac, but the memory objective remains structurally blocked by the legacy residency product model. Current production still persists and exposes `Hot / Warm / Cold`; `Hot` is excluded from automatic budget eviction, Warm/Cold retain separate timers, and the normal managed budget defaults to three Warm/Cold runtimes. A user with several legacy Hot ChatGPT Slots can therefore keep several heavyweight WebContent runtimes alive indefinitely by design.

That behavior is internally consistent with V4, but it is no longer consistent with the final product objective: Runtime lifetime should be automatic by default, while persistent Slot/Profile/session state survives Runtime reclamation.

**Audit disposition:** V4 is `STOP` for program-final acceptance. Phase 6 itself remains a valid prerequisite and is not rolled back.

## 2. Final product objective

FloatTabs is a persistent Web App container, not a persistent WebView container.

```text
Persistent Slot / Browser Profile / configuration / session / unread
                         │
                         ▼
              automatic Runtime policy
                         │
            ┌────────────┴────────────┐
            ▼                         ▼
       LIVE WKWebView              NO RUNTIME
            │                         │
            └──── Phase 6 restore ────┘
```

A Slot must remain useful, addressable and session-safe even when no live `WKWebView` exists.

The steady-state product expectation is:

- Runtime residency is **Automatic by default**;
- inactive heavyweight Runtime is disposable cache;
- active work, visible presentation, generation and allowed background media remain protected;
- recent switching receives a short automatic grace to avoid thrash;
- one explicit per-Slot **Keep Loaded** preference may opt out of normal reclaim, but it is not an absolute system-memory guarantee;
- reclaimed Slots restore through the Phase 6 two-stage native shell rather than by retaining hidden heavyweight WebViews.

## 3. Non-negotiable invariants

The following remain unchanged from earlier contracts:

- Browser Profile / `WKWebsiteDataStore` identity is independent from Runtime lifetime.
- Runtime reclamation never authorizes deleting cookies, sessions, website data, Slot configuration, preferences, backups or recovery material.
- `WebViewPool` remains the live Runtime creation/hibernate/restore mechanism owner.
- `SlotLifecycleCoordinator` remains the sole Runtime lifecycle execution boundary.
- `WebAttentionCoordinator` remains the native Attention authority.
- `PanelController` remains product/presentation visibility authority.
- Diagnostics records evidence only and never becomes a lifecycle policy writer.
- one canonical writer per semantic state remains mandatory.
- `WKWebView.interactionState` remains opaque transient runtime state and is not persisted/logged as product data.
- cache cleanup is not Runtime cleanup.
- no private WebKit API is authorized.
- historical JSC/WebContent stall root cause remains `UNKNOWN`.

## 4. User / project decisions preserved by V5

1. Persistent Web App Slots and Browser Profiles remain durable while live WebKit Runtime is disposable.
2. The old Hot/Warm/Cold lifecycle is retired as the current product policy rather than being further tuned.
3. Phase 6 perceived-fast restore remains the continuity mechanism after reclaim.
4. User/session data safety has priority over automatic cleanup convenience.
5. Final acceptance remains one integrated Real-Mac pass after the structural lifecycle program is complete.

## 5. Selected engineering model

### 5.1 Canonical per-Slot preference

Replace current product-facing `Hot / Warm / Cold` with one canonical preference:

```swift
enum SlotRuntimeRetentionPreference: String, Codable {
    case automatic
    case keepLoaded
}
```

Product semantics:

- `Automatic` — default; Runtime is governed entirely by lifecycle policy.
- `Keep Loaded` — normal-operation preference to retain an already materialized inactive Runtime when possible.

Use **Keep Loaded**, not **Pin**, in UI because FloatTabs already uses Pin for panel/window presentation semantics.

`Keep Loaded` does not proactively materialize an inactive Slot at application launch. It applies only after that Slot has a live Runtime.

### 5.2 Initial automatic policy defaults

These are conservative engineering defaults selected for the first automatic-policy implementation. They are not claimed as measured machine-independent optima.

```text
normal automatic resident target = 2
inactive automatic grace          = 30 seconds
memory-pressure warning target    = 1 automatic runtime
memory-pressure critical target   = 0 automatic runtimes
```

With one active ordinary Slot and no protection, normal operation may briefly retain one recent inactive Runtime. After the 30-second inactive grace, an Automatic inactive Runtime becomes reclaimable even when the numeric budget has spare capacity.

If automatic resident count exceeds the current target, eligible inactive Runtime may be reclaimed earlier than grace expiry using deterministic recency ranking.

### 5.3 Protection hierarchy

**Hard protection** remains non-evictable while the fact is true:

- active / actually presented Slot;
- fullscreen source;
- supplemental visible Web surface;
- Attention `generating`;
- active background media when `allowBackgroundAudio` and media is actually playing or its bounded protection query is pending;
- a current Phase 6 materialization/restoring transaction until ownership safely resolves.

**Keep Loaded** is a normal-operation preference, not hard protection:

- normal: inactive Keep Loaded Runtime is not reclaimed by ordinary automatic budget/timer policy;
- warning: Automatic Runtime is reclaimed first; Keep Loaded remains preferred;
- critical: an inactive Keep Loaded Runtime may be reclaimed after eligible Automatic Runtime, provided no hard protection applies.

This prevents an old-style permanent Hot pin from defeating system-stability recovery.

### 5.4 Deterministic ranking

For ordinary Automatic eviction:

1. eligible inactive Automatic Runtime only;
2. older `lastUsedAt` first;
3. stable Slot UUID lexical order as final tie-break.

For critical-pressure fallback after Automatic candidates are exhausted:

1. eligible inactive Keep Loaded Runtime;
2. older `lastUsedAt` first;
3. stable Slot UUID lexical order.

Do not guess per-Slot WebContent RSS; public WebKit does not provide trustworthy exact Slot-to-process memory attribution.

## 6. Persistence and rollback compatibility

Retiring Hot/Warm/Cold must not turn user configuration into destructive migration work.

The new canonical model is `SlotRuntimeRetentionPreference`, but legacy data remains readable.

### 6.1 Decode compatibility

When reading a Slot:

```text
new runtimeRetentionPreference present
→ use it

otherwise legacy residencyPolicy == hot
→ keepLoaded

otherwise legacy residencyPolicy in {warm, cold}
→ automatic

missing both
→ automatic
```

### 6.2 Transitional encode compatibility

During the compatibility window, encode the canonical new field and a derived legacy projection for rollback safety:

```text
automatic  → legacy residencyPolicy = warm
keepLoaded → legacy residencyPolicy = hot
```

The legacy field is compatibility projection only; it is not a second policy authority.

No user-visible behavior may consult Warm-vs-Cold once Phase 7 lands.

### 6.3 Global preference compatibility

Existing stored keys for Warm retention and Cold release delay are not deleted. Phase 7 stops consulting or presenting them. Keeping the raw values is intentional rollback safety and is not permission to retain the old policy path.

A state/backup schema bump is not required merely for this additive compatibility representation if decoding/encoding tests prove old and new documents remain safe. If implementation evidence proves a schema bump is required, STOP and reconcile before changing persisted state versions.

## 7. Runtime lifecycle algorithm

### Automatic Slot becomes inactive

```text
deactivate
→ preserve hard-protection checks
→ start one automatic 30s grace
→ evaluate global automatic budget
→ if over budget, reclaim eligible LRU inactive Automatic Runtime early
→ otherwise reclaim when grace expires
→ hibernate through existing WebViewPool boundary
```

### Automatic Slot becomes active again

```text
resident Runtime exists
→ direct existing path

Runtime reclaimed
→ Phase 6 native restoring shell
→ fresh/compatible Runtime restore through WebViewPool
→ exact-current readiness
→ normal focus/input resumes
```

### Keep Loaded Slot becomes inactive

```text
deactivate
→ detach from presentation normally
→ keep Runtime resident during normal operation
→ do not create a hidden presentation owner
→ warning keeps preference after Automatic reclaim
→ critical may reclaim if inactive and otherwise unprotected
```

Keep Loaded must not require the old Hot-only hidden host architecture.

## 8. Website cache boundary

Legacy Cold semantics coupled Runtime release to website-cache cleanup. Phase 7 retires that coupling.

Runtime reclaim is not authorization to delete re-downloadable cache. Website cache measurement/cleanup continues through the existing Website Storage policy and explicit/automatic cache-cleanup coordinator.

Removing Cold therefore must not silently clear or reset Browser Profile/session data and must not invent a new cache-cleanup side effect.

## 9. Phase 6 disposition

Phase 6 remains structurally valid and retains its own bounded merge gate.

Its responsibility is only:

```text
reclaimed Slot selected/summoned
→ native shell/restoring state immediately
→ deferred current request revalidation
→ WebViewPool materializes/restores Runtime
→ exact-current Runtime readiness
→ restoring surface removed
→ canonical focus/input resumes
```

Phase 7 changes **which Runtime becomes reclaimable**, not the Phase 6 restore ownership model.

PR #187 therefore remains a prerequisite to Phase 7 and should not absorb Phase 7 product-source mutation.

## 10. Program phases under V5

- Phase 1 — Safe Hibernate + Restore: `COMPLETE / MERGED`.
- Phase 2 — Ready / Unread Decoupling: `COMPLETE / MERGED`.
- Phase 3 — Native Completion Notification: `COMPLETE / MERGED`.
- Phase 4 — Reference-derived managed budget: `DELIVERED FOUNDATION / POLICY SUPERSEDED BY PHASE 7 TARGET`.
- Phase 5 — Background Generation Thrift: `COMPLETE / MERGED`.
- Phase 6 — Perceived-fast Restore: `IMPLEMENTED ON PR #187 / CLOSEOUT PENDING`.
- Phase 7 — Automatic Lifecycle Simplification + Legacy Residency Retirement: `CONTRACT FROZEN / IMPLEMENTATION NOT STARTED`.

Phase 4 code remains valid source evidence and reusable mechanism. Its Hot/Warm/Cold product semantics and default target `3` are superseded only when Phase 7 implementation lands.

## 11. Phase 7 objective

Phase 7 must:

1. introduce canonical Automatic / Keep Loaded preference;
2. safely map legacy Hot/Warm/Cold persisted values;
3. remove Hot/Warm/Cold from current user-facing controls;
4. remove Warm/Cold retention settings from active Performance UI;
5. replace legacy policy/timer branches with one automatic grace + deterministic budget;
6. remove Hot-only hidden-host retention behavior;
7. preserve existing hard protections and Browser Profile/session safety;
8. decouple website-cache cleanup from legacy Cold Runtime release;
9. preserve Phase 6 restore behavior for every reclaimed Slot;
10. add deterministic lifecycle and migration evidence plus bounded Real-Mac memory acceptance.

Exact implementation scope and gates are frozen in:

`FloatTabs_Runtime_Lifecycle_Phase7_Automatic_Lifecycle_Implementation_Contract_V1.md`.

## 12. Verification and final acceptance sequence

```text
finish Phase 6 bounded smoke + fresh exact-diff audit
→ merge PR #187
→ Phase 7 implementation on fresh main
→ focused migration/lifecycle/UI tests
→ full XCTest + Debug/Release arm64
→ literal-head required CI
→ bounded Real-Mac 3-Slot lifecycle/memory evidence
→ fresh integrated independent program audit
→ one user-owned final runtime/UI acceptance pass
→ closeout / release decision
```

The Real-Mac Phase 7 evidence must prove deterministic Runtime behavior first. Aggregate process-tree RSS/helper-count trends are supporting evidence; they must not be mislabeled as exact per-Slot memory attribution.

## 13. Program-final acceptance requirements

At minimum:

- no current Hot/Warm/Cold UI or active policy path remains;
- newly created Slots default to Automatic;
- legacy Hot decodes to Keep Loaded; legacy Warm/Cold decode to Automatic;
- with three loaded Automatic ChatGPT Slots, one active and no other protections, steady state after the grace window converges to one live Automatic Runtime;
- rapid switching may temporarily retain at most the bounded recent set rather than permanently materializing every Slot;
- a Generating/background-media/fullscreen protected Slot is not reclaimed while protection is valid;
- a reclaimed Slot restores through Phase 6 without losing Browser Profile login/session truth;
- Keep Loaded is explicit and does not preload at launch;
- critical-pressure policy can reclaim inactive Keep Loaded Runtime when no hard protection applies;
- website cache/session data is not cleared by Runtime reclaim;
- no duplicate lifecycle writer, hidden persistent continuity WebView or private WebKit shortcut is introduced;
- full tests/build/CI and integrated audit pass;
- final human acceptance remains user-owned.

## 14. Non-goals

V5 does not authorize:

- full-browser tab/process architecture;
- exact per-Slot WebContent RSS accounting via private API;
- predictive prewarming;
- screenshot continuity cache;
- deleting Browser Profile/session data to reduce memory;
- content-aware site-specific eviction heuristics;
- a user-tunable matrix of multiple residency tiers;
- arbitrary reload/reset as lifecycle policy;
- release/version work before program closeout.

## 15. Consequences and reversibility

**Consequences:** FloatTabs favors bounded memory over indefinite inactive DOM/runtime preservation. Inactive Automatic Slots may restore more often, which is why Phase 6 is a prerequisite. Keep Loaded remains an explicit escape hatch but cannot permanently defeat critical memory recovery.

**Reversibility:** legacy persistence projection and retained old preference values provide a bounded rollback path without clearing user data.

**Reversal trigger:** if Real-Mac evidence shows Phase 6 restore latency or provider behavior makes Automatic steady-state reclaim unusable, STOP and revise the numeric grace/budget defaults without restoring Hot/Warm/Cold as the product model.

## 16. Final disposition

```text
PROGRAM_CONTRACT=V5_ACCEPTED_FROZEN
CURRENT_PRODUCT_POLICY=LEGACY_HOT_WARM_COLD_UNTIL_PHASE7_LANDS
TARGET_PRODUCT_POLICY=AUTOMATIC_PLUS_KEEP_LOADED
NORMAL_AUTOMATIC_TARGET=2
AUTOMATIC_INACTIVE_GRACE=30S
WARNING_AUTOMATIC_TARGET=1
CRITICAL_AUTOMATIC_TARGET=0
PHASE6=PR187_CLOSEOUT_PENDING
PHASE7=CONTRACT_FROZEN_IMPLEMENTATION_NOT_STARTED
TASK_RECONCILIATION_REQUIRED=YES_COMPLETED_BY_CONTROL_UPDATE
PROGRAM_HUMAN_ACCEPTANCE=PENDING
```
