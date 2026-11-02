# FloatTabs — Architecture Document Status

Read [`../README.md`](../README.md) first. It is the repository-wide documentation authority/status index.

## Current active lifecycle/performance authority

Current task:

`FT-ADAPTIVE-LIFECYCLE-RESTORE-001`

Current contract:

- [`FloatTabs_Adaptive_Lifecycle_Restore_Contract_V1.md`](FloatTabs_Adaptive_Lifecycle_Restore_Contract_V1.md) — **CURRENT / ACCEPTED / FROZEN FOR WP0 EVIDENCE GATE**.

Current stage is evidence-first:

```text
WP0 runtime characterization + restore timing
→ evidence review / policy convergence
→ only then authorize product behavior mutation
```

## Preserved lifecycle foundations

Delivered architecture remains:

- persistent Slot/Profile/session state is separate from disposable `WKWebView` Runtime lifetime;
- `SlotLifecycleCoordinator` is the sole lifecycle policy/reclaim writer;
- `WebViewPool` owns Runtime create/reuse/hibernate/restore/release mechanics;
- `PanelController` owns selected-Slot presentation/materialization;
- `WebAttentionCoordinator` owns generation protection truth;
- Browser Profile/session data survives Runtime reclaim;
- notification/unread truth does not require completed Runtime residency;
- system warning/critical pressure reclaim is progressive;
- `Automatic | Keep Loaded` remains the shipped per-Slot retention preference.

## Current production tuning under review

Production currently implements:

```text
normal Automatic resident target = 2
Automatic inactive release       = 30s
```

These are current runtime facts, not final accepted product tuning.

The current task explicitly investigates replacing the universal normal target `2` and the unconditional 30s destructive-reclaim interpretation.

## Restore architecture under review

Current hibernate path:

```text
live WKWebView
→ capture transient compatible interactionState
→ teardown live Runtime
→ NO_RUNTIME_WITH_RESTORE_STATE
```

Current cold revisit:

```text
select/summon nonresident Slot
→ PanelController deferred materialization
→ native Restoring… presentation
→ create fresh WKWebView
→ apply compatible interactionState or load URL
→ exact-current Runtime readiness
→ reveal Web content / focus
```

The user has observed an approximately one-second-or-more interval where the shell can be visible before useful Web content after long inactivity. Eventual restore is correct; causal layer remains `UNKNOWN` until WP0 measures first-frame/materialization timing.

## Public WebKit scheduling boundary

`WebViewFactory` does not currently override `WKPreferences.inactiveSchedulingPolicy`.

On macOS 14+, public WebKit documents the default policy as `suspend` for an idle WebView detached from windows. Suspended idle views pause JavaScript and page layout; media/loading/interactive activity may be exempt.

Therefore:

- do not invent a second FloatTabs lifecycle writer around this API;
- do not claim explicit `.suspend` is a new FloatTabs Frozen state;
- characterize current detached idle/generating/media behavior before deciding whether any explicit override is necessary;
- preserve macOS 13+ compatibility and use no private SPI.

## Aggregate-memory platform boundary

The following prior evidence remains current:

- [`FloatTabs_Runtime_Lifecycle_Phase8_WP0_Measurement_Feasibility_Report_V1.md`](FloatTabs_Runtime_Lifecycle_Phase8_WP0_Measurement_Feasibility_Report_V1.md) — dominant WebContent/GPU helper attribution to FloatTabs is not deterministically available through supported ordinary production APIs.

Therefore a production GiB budget remains deferred/platform-blocked. Runtime count must not be relabeled as RAM.

Long-term design evidence remains available in:

- [`FloatTabs_Runtime_Lifecycle_Memory_Contract_V6.md`](FloatTabs_Runtime_Lifecycle_Memory_Contract_V6.md).

The delivered pressure/background implementation remains recorded in:

- [`FloatTabs_Runtime_Lifecycle_Phase8_Pressure_Efficiency_Rescope_Contract_V1.md`](FloatTabs_Runtime_Lifecycle_Phase8_Pressure_Efficiency_Rescope_Contract_V1.md).

Where these overlap the current task, `CURRENT_TASK.md` plus `FloatTabs_Adaptive_Lifecycle_Restore_Contract_V1.md` govern new mutation.

## Current conceptual lifecycle facts

Use observable ownership facts rather than old Hot/Warm/Cold labels:

```text
ACTIVE_OR_PROTECTED
RESIDENT_BACKGROUND
NO_RUNTIME_WITH_RESTORE_STATE
RESTORING
```

`RESIDENT_BACKGROUND` does not automatically mean a guaranteed product-level `FROZEN` state; WebKit scheduling must be characterized for platform/activity facts.

## Current WP0 evidence sequence

```text
resident quick-revisit timing
→ cold/nonresident restore timing
→ first restoring/content visible boundary
→ detached idle scheduling/resource behavior
→ detached generation continuity
→ background media behavior if available
→ hibernated vs resident relative-resource comparison
→ optional bounded memory-only WKWebView snapshot spike
→ choose healthy-state policy:
     pressure-first + long-idle cleanup
     OR adaptive soft warm-set
     OR narrowly evidenced hybrid
```

Only after this evidence is reconciled may WP1–WP4 mutate product lifecycle behavior.

## Current ownership

- `SlotLifecycleCoordinator` — sole Runtime lifecycle decision/reclaim writer;
- `WebViewPool` — live Runtime and transient restore-state mechanism;
- `WebViewFactory` — supported WKWebView configuration mechanism;
- `PanelController` / `WebPanelContainerView` — restoring/presentation ownership;
- `TabStore` / `WebAppProfile` — persistent Slot configuration and retention preference;
- `WebAttentionCoordinator` / `ChatGPTAttentionBridge` — generation protection facts;
- Runtime Diagnostics — evidence only;
- Website Cache domain — re-downloadable cache cleanup only.

## Historical/deferred routing

Treat as historical/deferred for current construction unless explicitly referenced by current Authority:

- Phase 1–7 implementation contracts after their delivered boundaries;
- original Phase 8 adaptive GiB-budget implementation contract beyond its Gate-0 evidence;
- V1–V5 lifecycle contracts;
- old Hot/Warm/Cold policy and benchmark plans;
- old fixed-count policy documents that present `2` as permanent product truth.

Preserve them as evidence. Current mutation follows `CURRENT_TASK.md` plus the adaptive lifecycle/restore V1 contract.
