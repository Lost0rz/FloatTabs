# FloatTabs Current Status

**Status date:** `2026-11-02`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 8 ADAPTIVE MEMORY BUDGET DESIGN FROZEN**

Current design task: `FT-RUNTIME-LIFECYCLE-MEMORY-001-PHASE8-DESIGN`.

Phase 7 is merged. A post-merge product review found that the delivered structural Runtime architecture is valid, but the initial Phase 7 fixed-count normal policy is too rigid for the intended product behavior. V6/Phase 8 now freezes the replacement design before any new production mutation.

## Repository / delivery state

```text
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
JSC_ROOT_CAUSE=UNKNOWN

MAIN=2b414982710b3f042fc7d6e9c88eb2d7117b4e38
PHASE_7_PR=#188_MERGED
PHASE_7_DELIVERY=COMPLETE

CURRENT_DESIGN_BRANCH=codex/ft-runtime-memory-budget-phase8-design
CURRENT_PROGRAM_CONTRACT=V6_ACCEPTED_FROZEN
CURRENT_PHASE8_CONTRACT=ACCEPTED_FROZEN_IMPLEMENTATION_NOT_STARTED
PRODUCT_MUTATION=NOT_AUTHORIZED_IN_CURRENT_DESIGN_TASK
```

## Current production truth

Until Phase 8 implementation lands, merged `main` still runs the Phase 7 policy:

```text
runtimeRetentionPreference = Automatic | Keep Loaded
normal Automatic resident target = 2
Automatic inactive release path = 30s
warning Automatic target = 1
critical Automatic target = 0
```

The structural foundations remain accepted:

- persistent Slot/Profile/session is separate from live `WKWebView` Runtime;
- `SlotLifecycleCoordinator` is the sole lifecycle writer/executor;
- `WebViewPool` owns Runtime materialize/hibernate/restore;
- Phase 6 restore path is preserved;
- Attention `Generating` is hard Runtime protection;
- `Ready`/durable unread/native completion notification do not require Runtime residency;
- Keep Loaded has no hidden Hot host and does not preload at launch;
- Runtime reclaim does not clear Browser Profile/login/cookie/session data;
- website-cache cleanup is separate from Runtime reclaim.

## Post-merge policy finding

Fresh source review confirms:

```swift
RuntimeBudgetPolicy.defaultManagedResidentTarget = 2
```

The current normal decision logic can reclaim an eligible Automatic Runtime when resident Automatic count exceeds `2`, even when the Mac has healthy memory headroom.

This is now classified as a **policy-design limitation**, not a failure of the Phase 1-7 Runtime architecture.

The user clarified the intended behavior:

> FloatTabs should allow multiple pages to remain open while resources permit. The user should control an approximate memory budget, not a maximum page/runtime count. When budget or system pressure requires it, inactive work should be reclaimed progressively.

## V6 target product truth

Current design authority:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V6.md`

Target normal policy:

```text
Memory Budget = primary normal resource control

Auto      = clamp(physical RAM × 20%, 1.5 GiB, 6 GiB) initial reference default
Custom    = user-selected approximate GiB budget
Unlimited = no normal budget-driven reclaim

high watermark = 105% of effective budget
low watermark  = 90% of effective budget
```

Target behavior:

```text
healthy + under budget
→ no fixed Runtime-count ceiling
→ 3/4/5+ useful Runtimes may remain resident

above high watermark
→ choose one safest eligible inactive Automatic Runtime
→ revalidate
→ hibernate through WebViewPool
→ fresh measurement
→ stop <= low watermark
→ otherwise repeat one at a time
```

The old `2 / 1 / 0` resident-count targets are historical Phase 7 values and are **not** the Phase 8 target.

## Protection hierarchy under V6 target

Hard protection remains:

- active / actually presented;
- fullscreen source;
- supplemental visible Web surface;
- Attention Generating;
- active/pending allowed-background-media protection;
- current materialization/restoring ownership.

Keep Loaded remains a strong normal-operation preference:

- normal budget reclaims Automatic first;
- Keep Loaded may temporarily prevent meeting the soft budget;
- warning still prefers Automatic reclaim;
- critical may reclaim inactive/unprotected Keep Loaded after Automatic candidates.

## Background-generation truth

Current production already provides:

```text
Generating
→ Runtime protected
→ hidden liveness fallback work is reduced
→ generation completes
→ Ready/unread + native notification
→ generating protection ends
→ Runtime may later be reclaimed
```

The current mechanism does **not** deeply reduce the WebContent heap while arbitrary page generation continues. Phase 8 therefore separates:

- host/observer/probe efficiency work — authorized design target;
- true renderer/WebContent deep-freeze while JS/network generation continues — not claimed and not authorized through private WebKit SPI.

Phase 8 will audit event-first sensing, fallback watchdog cadence, redundant hidden diagnostics, response-identity work and task/observer cancellation while preserving generation continuity.

## Resource measurement Gate

The memory budget requires an aggregate FloatTabs/WebKit footprint estimate, not exact per-Slot attribution.

Existing benchmark tooling can externally observe only processes whose launchd responsible PID belongs to the current FloatTabs host. That proves useful Real-Mac evidence, but it does not by itself authorize a production implementation.

Phase 8 Gate 0 must prove a supported production-safe measurement mechanism before GiB budget enforcement is enabled.

If production-safe aggregate measurement cannot be proven:

- do not guess memory from Runtime count;
- do not disguise Runtime count as Custom GiB;
- preserve system memory-pressure handling;
- STOP and reconcile the budget implementation.

## Reference review

Current external reference review supports the direction:

- Chrome exposes Memory Saver aggressiveness and eligibility exceptions rather than a fixed tab-count ceiling;
- current Chromium separates proactive inactivity heuristics from memory-pressure discard behavior and uses revisit/recency signals;
- Kylmora uses lazy tabs, idle/memory-pressure sleep and per-tab Keep Awake;
- Kestrel demonstrates WKWebView Runtime destruction/restoration with `interactionState` and memory-pressure-triggered sleep.

These are design references, not FloatTabs Authority. Engine-level Chromium freeze/discard capabilities that require private/unsupported WebKit controls are not adopted.

## Frozen Phase 8 plan

Current implementation contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase8_Adaptive_Memory_Budget_Implementation_Contract_V1.md`

Frozen sequence:

```text
WP0 measurement feasibility + exact source audit
WP1 additive budget configuration + passive resource monitor
WP2 memory-budget decision engine + progressive normal reclaim
WP3 system-pressure ladder + anti-thrash integration
WP4 Advanced Runtime & Memory UI + persistence/backup
WP5 background-generation / observer efficiency corrective
WP6 Real-Mac + identical-workload Phase7-vs-Phase8 A/B acceptance
```

No production construction begins from this design branch/task.

## Historical backup / routing

Phase 7/V5 delivered policy is preserved, not rewritten:

`docs/architecture/archive/FloatTabs_Runtime_Lifecycle_Phase7_Closeout_Snapshot_2026-11-02.md`

V5 and the Phase 7 contract remain historical evidence for why the delivered architecture exists. Their fixed-count policy values must not be used as current Phase 8 goals.

## Current next gate

```text
finish documentation/control alignment
→ verify design branch contains docs/control only
→ freeze design receipt
→ STOP
→ user explicitly authorizes Phase 8 implementation
→ then create bounded implementation branch/PR and execute WP0 first
```

No release/version change and no `FloatTabs/**` product mutation is authorized by the current design task.
