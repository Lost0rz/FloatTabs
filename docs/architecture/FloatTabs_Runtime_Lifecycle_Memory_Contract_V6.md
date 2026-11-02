# FloatTabs Runtime Lifecycle & Memory Contract V6

**Status:** `ACCEPTED / FROZEN / DESIGN AUTHORITY`  
**Accepted:** `2026-11-02`  
**Program:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Baseline:** `main@2b414982710b3f042fc7d6e9c88eb2d7117b4e38`  
**Supersedes:** `FloatTabs_Runtime_Lifecycle_Memory_Contract_V5.md` for future lifecycle/performance construction  
**Preserves:** delivered Phase 1-7 architecture and user/session safety boundaries

> **WP2 policy status (2026-11-02):** The fixed-count healthy-state lifecycle, 30s destructive-release semantics, and Keep Loaded critical-pressure reclaim rules below are historical and superseded for WP2 by [Runtime Lifecycle Policy V7](FloatTabs_Runtime_Lifecycle_Policy_V7.md). V6 remains reference authority for aggregate-memory feasibility and non-conflicting lifecycle architecture. The original pre-WP2 body is preserved in the architecture archive.

## 1. Why V6 exists

Phase 7 successfully established the structural lifecycle foundation:

- persistent Slot/Profile/session state is independent from live `WKWebView` Runtime lifetime;
- Runtime can hibernate and restore through the existing `WebViewPool` / Phase 6 path;
- Attention `Generating` protects live work while `Ready`/unread does not require Runtime residency;
- Keep Loaded no longer depends on hidden Hot-host presentation;
- Browser Profile/login/cookie/session data survives Runtime reclaim;
- Real-Mac evidence proved that reclaiming an idle WebContent Runtime materially reduces aggregate FloatTabs/WebKit memory.

However, Phase 7 also made the initial engineering tuning values into the normal product policy:

```text
normal Automatic resident target = 2
Automatic inactivity grace       = 30s
warning target                    = 1
critical target                   = 0
```

Fresh source review confirms that the normal target `2` is enforced as a resident-count budget. Therefore, a third eligible Automatic Runtime may be reclaimed even when the Mac still has healthy memory headroom.

That is too rigid for FloatTabs' product objective and is not the desired browser-like lifecycle. The product must allow several live pages when resources permit, then progressively reclaim the safest inactive work when the FloatTabs memory budget or macOS memory pressure requires it.

V6 therefore supersedes **the Phase 7 fixed-count policy**, while preserving the delivered Phase 1-7 Runtime architecture.

## 2. Final product objective

FloatTabs is a persistent Web App workspace whose live WebKit Runtime working set adapts to available resources.

```text
Persistent Slot / Browser Profile / session / unread / configuration
                              │
                              ▼
                     Runtime materialization
                              │
             ┌────────────────┼────────────────┐
             ▼                ▼                ▼
       ACTIVE/PROTECTED   IDLE RESIDENT     NO RUNTIME
             │                │                │
             │                └── budget / ────┘
             │                    pressure
             └──────── Phase 6 restore ─────────┘
```

The product model is:

- open Slot count is not a memory-policy ceiling;
- live Runtime count is not the primary user setting;
- a user-configurable **memory budget** is the primary normal-operation resource control;
- the budget is a best-effort soft working-set target, not an OS-enforced hard cap;
- when healthy and under budget, several inactive Runtimes may remain resident;
- when over budget, eligible inactive Runtime is reclaimed progressively, one at a time, with re-measurement after each release;
- macOS memory pressure is a separate higher-priority signal;
- active work and other hard protections always beat the user budget;
- Keep Loaded remains a strong normal-operation retention preference and may cause temporary budget overshoot;
- critical system pressure may still reclaim inactive Keep Loaded Runtime after eligible Automatic Runtime is exhausted.

## 3. Non-negotiable invariants

The following remain frozen:

1. Browser Profile / `WKWebsiteDataStore` identity is independent from Runtime lifetime.
2. Runtime reclaim never authorizes deletion/reset of cookies, sessions, website data, Slot configuration, preferences, backups or recovery material.
3. `WebViewPool` remains the live Runtime creation/hibernate/restore mechanism owner.
4. `SlotLifecycleCoordinator` remains the sole canonical Runtime lifecycle writer/executor.
5. `WebAttentionCoordinator` remains native Attention authority.
6. `PanelController` remains presentation/actual-visibility authority.
7. Diagnostics records evidence only; diagnostics must not become the memory/lifecycle policy writer.
8. `WKWebView.interactionState` remains opaque transient restore state and is not persisted/logged as product content.
9. Website cache cleanup remains independent from Runtime reclaim.
10. No private WebKit SPI is authorized as a required production dependency.
11. Reload/reset/restart is not an ordinary memory-management mechanism.
12. Public WebKit does not provide trustworthy exact per-Slot WebContent RSS attribution; policy must not pretend otherwise.
13. Historical JSC/WebContent stall root cause remains `UNKNOWN` unless fresh evidence proves otherwise.

## 4. Current production vs V6 target

### Current merged production baseline

At V6 freeze time, `main@2b414982...` still implements the delivered Phase 7 policy:

```text
normal target 2
30s unconditional Automatic reclaim path
warning target 1
critical target 0
```

This remains runtime truth until Phase 8 implementation lands.

### V6 target

```text
NORMAL
→ budget-driven
→ no fixed Runtime-count ceiling
→ several pages may stay resident while resource use is healthy

OVER BUDGET
→ reclaim one eligible inactive Automatic Runtime
→ re-measure
→ stop when safely below low watermark
→ otherwise repeat

SYSTEM WARNING
→ progressively reclaim eligible Automatic Runtime more aggressively

SYSTEM CRITICAL
→ reclaim eligible Automatic Runtime first
→ then inactive/unprotected Keep Loaded if still required

HARD PROTECTED
→ never normal-reclaim because of budget
```

## 5. User memory-budget model

### 5.1 Canonical preference

Introduce an additive global configuration concept equivalent to:

```swift
enum RuntimeMemoryBudgetMode: String, Codable {
    case auto
    case custom
    case unlimited
}

struct RuntimeMemoryBudgetConfiguration: Codable, Equatable {
    var mode: RuntimeMemoryBudgetMode
    var customBytes: UInt64?
}
```

The exact Swift representation may vary if persistence/tests justify a safer shape, but product semantics are frozen.

### 5.2 Modes

#### Auto — recommended

Auto derives an approximate normal-operation target from physical memory.

Initial reference default:

```text
budget = clamp(physicalMemory × 20%, 1.5 GiB, 6 GiB)
```

Examples:

```text
8 GiB  Mac → ~1.6 GiB
16 GiB Mac → ~3.2 GiB
24 GiB Mac → ~4.8 GiB
32+ GiB    → capped at 6 GiB by the initial reference default
```

This formula is an initial product assumption selected for the first implementation. It is not claimed as a machine-independent optimum and must be validated by Phase 8 Real-Mac/A-B evidence before program-final acceptance.

#### Custom

The user chooses the approximate FloatTabs/WebKit working-set budget in GiB.

Initial UI/validation range:

```text
minimum = 1 GiB
maximum = min(32 GiB, 75% of physical memory)
```

A stored value outside the supported range is clamped for effective policy without destructively rewriting unknown/older data unless migration tests authorize it.

#### Unlimited

Normal budget-based reclaim is disabled.

`Unlimited` does **not** disable:

- macOS warning/critical memory-pressure handling;
- Runtime teardown for Slot deletion/profile changes/rebuild requirements;
- explicit user sleep/reset/recovery actions that already own their own semantics.

### 5.3 Soft target, not hard cap

The budget is intentionally approximate because:

- WebKit uses multiple processes;
- some helper memory may be shared or change independently;
- compressed memory and allocator behavior can delay observed RSS reduction;
- hard-protected Runtime may legitimately exceed the target;
- public APIs do not provide exact per-Slot WebContent ownership/memory.

UI wording must say **Memory Budget** / **Approximate working-set budget**, not “hard memory limit”.

## 6. Aggregate Runtime resource measurement

### 6.1 Required production fact

Budget policy may consume one read-only aggregate footprint estimate:

```text
FloatTabs host
+ FloatTabs-attributable WebContent processes
+ FloatTabs-attributable WebKit Networking/GPU/other helper processes
= observed aggregate FloatTabs/WebKit footprint
```

This is an application-level estimate only. It is not per-Slot attribution.

### 6.2 Measurement ownership

A new read-only Web/performance input component may be introduced, e.g. `RuntimeResourceMonitor`.

It may:

- sample host memory;
- enumerate only processes that can be safely and deterministically attributed to the running FloatTabs host through supported macOS process metadata;
- classify attributable WebKit helpers;
- return a bounded observation with timestamp/availability/footprint.

It must not:

- own lifecycle decisions;
- kill processes directly;
- persist private process identity as product state;
- claim a WebContent PID belongs to a particular Slot when public evidence cannot prove it.

### 6.3 Measurement feasibility Gate

Before budget-driven production reclaim is enabled, Phase 8 must prove that the selected process-attribution mechanism is appropriate for production use on supported macOS versions.

The existing benchmark harness uses launchd `responsible pid` attribution and is strong Real-Mac evidence, but benchmark tooling is not automatically a production API contract.

If a production-safe aggregate measurement cannot be proven:

- do not guess aggregate memory from Runtime count;
- do not silently reinterpret Custom GiB as “number of tabs”;
- keep system memory-pressure reclaim operational;
- STOP and reconcile the Custom/Auto enforcement implementation before shipping it.

## 7. Watermarks and hysteresis

For an effective budget `B`:

```text
high watermark = 1.05 × B
low watermark  = 0.90 × B
```

Normal budget reclaim starts only after a stable sample exceeds the high watermark.

Once reclaim starts, continue progressively until one of these is true:

1. observed footprint is at or below the low watermark;
2. there is no eligible Automatic candidate;
3. a hard protection or ownership transition invalidates the current reclaim decision;
4. measurement becomes unavailable;
5. the app exits/reset boundary changes identity.

This hysteresis prevents repeated hibernate/restore oscillation around one threshold.

A single transient spike must not trigger a multi-Runtime purge. Implementation must use bounded stabilization/re-measurement rather than interpreting one sample as proof that every inactive Runtime must go.

## 8. Runtime lifecycle classes

V6 uses lifecycle facts, not old Hot/Warm/Cold classes.

Conceptual Runtime states:

```text
NOT_MATERIALIZED
RESIDENT_ACTIVE
RESIDENT_PROTECTED
RESIDENT_IDLE
HIBERNATING
NO_RUNTIME_WITH_RESTORE_STATE
RESTORING
```

This state description does not require a new persisted state machine if current ownership can project the facts safely.

FloatTabs must **not** invent a fake Chromium-like `FROZEN` state using private WebKit controls. A public, supported API may be adopted later only through a separately evidenced contract.

## 9. Protection hierarchy

### 9.1 Hard protection

A Runtime is not eligible for normal budget reclaim while any of these is true:

- active / actually presented;
- fullscreen source;
- supplemental visible Web surface;
- Attention `Generating`;
- allowed background media is actively playing;
- an allowed-background-media protection query is pending at the current lifecycle boundary;
- current materialization/restoring ownership requires Runtime stability;
- any other current accepted contract explicitly marks the Runtime as non-reclaimable for correctness.

Hard protection may temporarily cause footprint to exceed the configured budget.

### 9.2 Keep Loaded

Keep Loaded remains a strong normal-operation preference:

- normal budget reclaim selects eligible Automatic Runtime first;
- if only Keep Loaded/hard-protected Runtime remains, normal Custom/Auto budget may remain oversubscribed and diagnostics/UI may report the budget as blocked;
- warning pressure still prefers reclaiming Automatic Runtime;
- critical pressure may reclaim inactive/unprotected Keep Loaded after eligible Automatic Runtime is exhausted.

This preserves the Phase 7 user meaning while making the memory budget honest about cases it cannot satisfy.

## 10. Normal budget reclaim algorithm

### 10.1 Trigger

Normal budget reclaim is considered when:

- mode is `auto` or `custom`;
- aggregate resource measurement is available;
- a stable sample is above the high watermark.

It is **not** triggered merely because resident Runtime count is `3`, `5`, or any other number.

### 10.2 Anti-thrash inactivity grace

The existing `30s` value changes meaning under V6.

It is no longer an unconditional “release every Automatic Runtime after 30 seconds” timer.

Instead, the initial normal-budget candidate rule is:

```text
inactive Automatic Runtime
AND inactive for at least 30s
AND no hard protection
→ eligible for normal budget reclaim
```

This is a switch-thrash guard, not a resident lifetime ceiling.

System warning/critical pressure may bypass the normal inactivity grace when required for stability.

A severe normal-budget overshoot policy (for example >125% of budget) may bypass or shorten grace only if Phase 8 tests/Real-Mac evidence prove the need; it is not authorized implicitly by this contract.

### 10.3 Candidate order

Initial deterministic ordering:

1. eligible inactive Automatic only;
2. longest inactive duration first;
3. older `lastUsedAt` first;
4. stable Slot UUID lexical order.

Revisit/heat heuristics are desirable but are **not required to ship before the base budget scheduler is correct**. If added, they must remain transient read-only facts and receive deterministic tests.

### 10.4 Progressive execution

```text
sample > high watermark
→ choose exactly one current candidate
→ revalidate protection + runtime identity
→ hibernate through existing WebViewPool boundary
→ wait for current release/resident-set transition
→ take a fresh aggregate sample
→ <= low watermark? stop
→ still high and another candidate exists? repeat
```

Only one budget-driven reclaim transaction may be in flight at a time.

Do not precompute and purge an entire LRU list from one stale memory sample.

## 11. macOS memory-pressure ladder

System memory pressure remains independent of user budget.

### Normal

Use the configured memory budget. No fixed resident-count target.

### Warning

- reevaluate immediately;
- Automatic inactivity grace may be bypassed;
- progressively reclaim eligible inactive Automatic Runtime one at a time;
- re-check current pressure/resource evidence between releases where available;
- do not reclaim active/hard-protected Runtime;
- Keep Loaded remains preferred at warning level unless a future accepted contract changes this explicitly.

### Critical

- progressively reclaim all eligible inactive Automatic Runtime first;
- then inactive/unprotected Keep Loaded may become eligible;
- continue one at a time while current evidence still requires reclaim;
- active/hard-protected Runtime remains protected even if the budget cannot be met.

The old `warning target = 1 / critical target = 0` count policy is superseded by this pressure ladder once Phase 8 lands.

## 12. Background-generation efficiency

### 12.1 Continuity contract

While ChatGPT (or another supported provider) is actively generating:

```text
Attention = Generating
→ Runtime hard-protected
→ generation/stream continuity wins over memory budget
```

FloatTabs must not hibernate the Runtime merely to hit the configured memory budget because destroying the live WebContent Runtime would terminate JS/network/application state.

### 12.2 What Phase 8 may optimize while generation remains live

Phase 8 should reduce **host-side and observation overhead** where correctness permits:

- keep bridge/event-driven generation transitions as primary evidence;
- reduce fallback watchdog frequency for long-running hidden generation when the event bridge is healthy;
- suppress redundant health/diagnostic probes unless incident/explicit measurement requires them;
- avoid repeated expensive response-identity work when generation state has not changed;
- stop unnecessary presentation-only work for detached hidden Runtime;
- cancel obsolete observer/tasks promptly across navigation/runtime generations;
- keep bounded fallback probes so missed completion cannot leave a Runtime protected forever.

The current hidden long-running watchdog already backs off compared with ordinary generation. Phase 8 may extend that idea only with deterministic liveness/completion tests.

### 12.3 What Phase 8 must not claim

Do not claim “background generation uses little memory” merely because probe CPU falls.

With public `WKWebView`, FloatTabs currently cannot safely deep-freeze the WebContent heap while expecting arbitrary page JS/network streaming to continue.

A private WebKit inactive-scheduling SPI or renderer control is not authorized.

### 12.4 Completion boundary

When generation completes while hidden:

```text
Generating
→ Ready/unread + native completion notification
→ generating hard protection ends
→ Runtime becomes normal lifecycle input
```

If the app is over budget, the completed Runtime may become a budget candidate after a short bounded notification-recall grace defined by the Phase 8 implementation contract. If memory is healthy, it may remain resident.

Durable unread/notification must not require keeping the completed Runtime alive.

## 13. Proactive long-idle cleanup

V6 separates long-idle cleanup from memory-budget enforcement.

Phase 8 baseline:

```text
proactive idle cleanup = OFF by default
```

Therefore, an inactive Automatic Runtime under budget is not destroyed solely because 30 seconds elapsed.

A later bounded implementation may add Chrome-like user aggressiveness (`Moderate / Balanced / Maximum`) or long-idle thresholds only after the base budget scheduler is proven. Such a feature must remain a distinct policy input rather than recreating a hidden fixed-count ceiling.

This decision intentionally favors predictable persistent Web App switching while the explicit memory budget provides the main resource bound.

## 14. Advanced settings contract

Primary location:

```text
Settings
→ Advanced
→ Runtime & Memory
```

Required primary control:

```text
Memory Budget
[ Auto — Recommended ]
[ Custom… ]
[ Unlimited ]
```

When Custom is selected, expose a GiB value/stepper or equivalent bounded control.

Required explanatory semantics:

- the budget is approximate;
- active/protected work can temporarily exceed it;
- FloatTabs reclaims inactive Runtime when the budget/system pressure requires it;
- reclaim does not sign the user out or clear Browser Profile/session data;
- Keep Loaded may prevent ordinary budget convergence and critical memory pressure may still reclaim it.

Optional read-only UI, if measurement is production-safe:

```text
Observed FloatTabs/WebKit footprint: ~X.X GiB
Budget state: Healthy / Above budget / Protected work exceeds budget / Measurement unavailable
```

Do not expose “maximum live tabs/runtimes” as the primary product control.

## 15. Persistence / backup contract

New memory-budget preference is global application configuration.

Rules:

- missing value → `Auto`;
- additive UserDefaults/config keys only unless evidence proves a schema migration is necessary;
- existing retired Warm/Cold preference keys remain stored but unused for rollback/history safety;
- backup/export must include the new global memory-budget configuration if global performance preferences are already within backup scope;
- restore validates/clamps the effective Custom value without touching website/session data;
- Browser Profile WebKit data is out of scope.

## 16. Ownership map under V6

### Canonical writers

- `AppPreferencesStore` — durable global budget configuration only.
- `SlotLifecycleCoordinator` — sole lifecycle execution writer.

### Read-only policy inputs

- aggregate resource monitor — observed application/WebKit footprint;
- current macOS memory-pressure state;
- `TabStore.lastUsedAt` / current inactivity facts;
- `WebAttentionCoordinator` generating protection;
- media/fullscreen/presentation/materialization protection facts.

### Mechanism owner

- `WebViewPool` — hibernate/restore/rebuild/release only.

Diagnostics may record every decision/input/result but must not define lifecycle truth.

## 17. Reference-derived mechanisms adopted or rejected

Current reference review supports these directions:

### Adopt

- Chrome-style separation between proactive inactivity policy and urgent memory-pressure reclaim;
- user-facing resource aggressiveness/budget rather than fixed tab count;
- eligibility exceptions for active work/media/etc.;
- revisit/recency as a potential later ranking signal;
- Kylmora-style lazy/non-materialized tabs and per-tab Keep Awake/Keep Loaded semantics;
- Kestrel-style real Runtime sleep/restore using WebKit state rather than pretending a destroyed renderer remains live;
- one-at-a-time progressive reclaim with re-evaluation.

### Reject / defer

- Chromium renderer `freeze` semantics that require engine-level controls unavailable through supported public WKWebView API;
- private WebKit inactive-scheduling SPI;
- exact per-Slot RSS policy decisions;
- direct renderer-process killing;
- arbitrary refresh/reload as memory management;
- hard fixed resident-count ceilings as the normal product model.

External projects are design references only. Production truth remains FloatTabs source/tests/current evidence.

## 18. Phase 8 work packages

V6 is implemented through the separately frozen Phase 8 contract.

Program-level sequence:

```text
WP0  measurement feasibility + exact source audit
WP1  additive budget configuration + read-only resource monitor
WP2  memory-budget decision engine + progressive reclaim
WP3  system-pressure ladder + anti-thrash integration
WP4  Advanced UI + persistence/backup projection
WP5  background-generation/observer efficiency corrective
WP6  Real-Mac/A-B performance acceptance + integrated audit
```

No work package may reintroduce a second lifecycle writer.

## 19. Program verification requirements

Before V6 program acceptance:

1. three or more Automatic Runtimes remain resident while aggregate footprint is healthy and under budget;
2. crossing the high watermark triggers progressive reclaim rather than count-based purge;
3. each reclaim is followed by fresh measurement/re-evaluation;
4. reclaim stops at/below low watermark or when no eligible candidate exists;
5. active/generating/fullscreen/media/materializing protections hold;
6. Keep Loaded behavior matches Section 9.2;
7. warning/critical pressure ordering is deterministic;
8. repeated switching does not produce reclaim/restore thrash around the watermark;
9. reclaim/restore preserves login/session/current Slot identity;
10. hidden generation completion still produces unread/native notification and becomes reclaimable afterward;
11. old Phase 7 count targets are not consulted by current normal policy;
12. identical-workload A/B evidence compares the merged Phase 7 baseline with the V6 implementation using aggregate FloatTabs/WebKit footprint, helper counts, CPU and restore/switch latency;
13. required self-hosted Apple Silicon CI passes on every merge candidate.

## 20. STOP conditions

STOP and reconcile before continuing if implementation requires:

- destructive Browser Profile/session/config migration;
- a second Runtime lifecycle writer;
- private WebKit SPI or unsupported renderer control;
- exact per-Slot memory attribution as a required policy input;
- fixed resident-count target as the main normal policy;
- reclaim of active/generating/fullscreen/protected media/current restoring work merely to meet the user budget;
- treating a single transient RSS sample as authorization to purge multiple Runtime without remeasurement;
- shelling out to arbitrary commands from production solely to implement resource accounting without a separately reviewed production-safety decision;
- weakening Phase 6 restore/session guarantees to obtain better memory numbers;
- claiming background generation memory reduction when only observer CPU/probe work was reduced.

## 21. Frozen V6 outcome

```text
V6_STATUS=ACCEPTED_FROZEN
CURRENT_PRODUCTION_BASELINE=PHASE7_MERGED
CURRENT_PRODUCTION_POLICY=FIXED_COUNT_UNTIL_PHASE8_LANDS
TARGET_NORMAL_POLICY=SOFT_MEMORY_BUDGET
NORMAL_FIXED_RUNTIME_COUNT=RETIRED_BY_TARGET
AUTO_BUDGET_REFERENCE=20_PERCENT_PHYSICAL_CLAMP_1_5_TO_6_GIB
CUSTOM_BUDGET=SUPPORTED_TARGET
UNLIMITED_NORMAL_BUDGET=SUPPORTED_TARGET
HIGH_WATERMARK=105_PERCENT
LOW_WATERMARK=90_PERCENT
NORMAL_RECLAIM=ONE_AT_A_TIME_REMEASURE
SYSTEM_PRESSURE=SEPARATE_LADDER
PROACTIVE_IDLE_DEFAULT=OFF
GENERATING=HARD_PROTECTED
PRIVATE_WEBKIT_SPI=FORBIDDEN
NEXT_AUTHORITY=PHASE8_IMPLEMENTATION_CONTRACT
```
