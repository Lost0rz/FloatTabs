# FloatTabs Runtime Lifecycle — Phase 8 Adaptive Memory Budget Implementation Contract V1

**Program:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Phase:** `8 — Adaptive Memory Budget + Background Efficiency`  
**Status:** `ACCEPTED / FROZEN / IMPLEMENTATION NOT STARTED`  
**Parent contract:** `FloatTabs_Runtime_Lifecycle_Memory_Contract_V6.md`  
**Execution baseline:** `main@2b414982710b3f042fc7d6e9c88eb2d7117b4e38`

This contract freezes the concrete construction sequence for replacing Phase 7 fixed-count normal reclaim with a memory-budget-driven lifecycle while preserving the delivered Phase 1-7 architecture.

## 1. Phase 8 objective

Replace:

```text
resident Automatic count > 2
→ immediate LRU reclaim

30s inactive
→ reclaim Automatic even when memory is healthy

warning → target 1
critical → target 0
```

with:

```text
healthy + under budget
→ keep useful resident Runtime alive

above soft memory budget
→ reclaim one safest eligible Automatic Runtime
→ re-measure
→ repeat only if still required

system memory pressure
→ independent progressive reclaim ladder
```

No product behavior in this contract authorizes destructive website/session cleanup or a second lifecycle writer.

## 2. Frozen user-facing behavior

### 2.1 Memory Budget in Advanced

Add one bounded settings section under:

```text
Settings → Advanced → Runtime & Memory
```

Primary control:

```text
Memory Budget
- Auto — Recommended
- Custom…
- Unlimited
```

Custom is expressed in GiB. Do not expose a “max tabs” or “max resident runtimes” product control.

### 2.2 Auto reference default

```text
effectiveBudget = clamp(physicalMemory × 20%, 1.5 GiB, 6 GiB)
```

This is an initial reference-derived default, not measured truth. Phase 8 acceptance must report whether this default is practical on the tested Mac; later tuning may adjust it through a separately authorized contract without changing the architecture.

### 2.3 Custom range

```text
1 GiB ... min(32 GiB, 75% physical memory)
```

### 2.4 Unlimited

No normal budget-triggered reclaim. System memory-pressure reclaim remains active.

### 2.5 Watermarks

```text
high = 105% of effective budget
low  = 90% of effective budget
```

Crossing high starts bounded progressive reclaim. Reclaim stops at/below low or when no eligible candidate remains.

## 3. Frozen Runtime eligibility semantics

### Hard-protected

Never normal-reclaim while true:

- active / actually presented;
- fullscreen source;
- supplemental visible Web surface;
- Attention `Generating`;
- allowed background media actively playing;
- current allowed-background-media protection query pending;
- current materialization/restoring ownership;
- any existing accepted exact-current navigation/runtime ownership protection required for correctness.

### Automatic

Eligible for normal budget reclaim only when:

```text
resident
AND inactive
AND inactive >= 30s normal anti-thrash grace
AND no hard protection
```

The 30-second value is no longer an unconditional release timer.

### Keep Loaded

- excluded from normal budget candidate selection;
- may cause the configured budget to remain oversubscribed;
- warning still reclaims Automatic first and preserves Keep Loaded preference;
- critical may reclaim inactive/unprotected Keep Loaded after eligible Automatic candidates are exhausted.

## 4. Frozen candidate ordering

Base Phase 8 ordering:

1. Automatic only;
2. longest inactive duration first;
3. older `lastUsedAt` first;
4. UUID lexical tie-break.

A transient revisit/heat signal may be added only in WP5 if the base scheduler produces measurable churn. It must not become persisted product state and must have deterministic tests.

## 5. Frozen progressive-reclaim transaction

Normal budget path:

```text
resource sample above high watermark
→ coordinator asks policy for one candidate
→ revalidate candidate/current protection/runtime identity
→ WebViewPool.hibernate(candidate)
→ wait for resident-set/release boundary
→ obtain fresh resource sample
→ if <= low: stop
→ if still above high/low recovery target and candidate exists: repeat
```

Rules:

- maximum one budget reclaim transaction in flight;
- no precomputed multi-Runtime purge from one memory sample;
- if measurement becomes unavailable, normal budget reclaim stops;
- system pressure remains allowed to take its separately frozen path;
- every reclaim decision/result emits bounded diagnostics without page content.

## 6. Resource measurement feasibility Gate

This is Phase 8 Gate 0 and blocks budget enforcement.

### Required investigation

Prove a production-safe method on supported macOS versions to estimate:

```text
FloatTabs host footprint
+ FloatTabs-attributable WebKit helpers
```

The existing Real-Mac benchmark proves that responsible-process attribution can be observed externally. Phase 8 must determine whether the chosen in-app mechanism is supported and safe for production.

### Allowed implementation direction

A read-only component may be added under the Web/performance ownership boundary, e.g.:

`FloatTabs/Web/RuntimeResourceMonitor.swift`

It may expose a value equivalent to:

```swift
struct RuntimeResourceObservation {
    let capturedAt: ContinuousClock.Instant
    let totalBytes: UInt64?
    let attributionAvailable: Bool
    let processCount: Int
}
```

Exact names/types are not frozen.

### Gate 0 PASS

Gate 0 passes only when:

- the mechanism uses supported macOS APIs acceptable for production;
- attribution does not require mapping a WebContent PID to a specific Slot;
- stale/dead processes are bounded safely;
- unavailable measurement is represented explicitly;
- tests can inject deterministic observations without launching real WebKit helpers.

### Gate 0 STOP

If aggregate production-safe measurement cannot be established, STOP before WP2 behavior mutation. Do not replace GiB budget with Runtime count or a guessed per-tab MB constant.

## 7. Work packages

### WP0 — exact baseline/source audit + measurement feasibility

Read-only first.

Audit exact owners/call paths for:

- `SlotLifecycleCoordinator` budget enforcement and memory-pressure handling;
- `WebViewPool.hibernate` / resident-set callback;
- `AppCoordinator` lifecycle wiring;
- `AppPreferencesStore` legacy Warm/Cold keys and notification routes;
- Settings IA and Advanced page composition;
- backup/export of global preferences;
- Phase 7 benchmark process-attribution implementation;
- Attention liveness/background-generation scheduling.

Deliverable before mutation:

```text
measurement source selected
ownership path confirmed
expected files/tests frozen
no private SPI
```

### WP1 — additive budget configuration + resource monitor

Expected production scope:

- `FloatTabs/Persistence/AppPreferencesStore.swift`
- `FloatTabs/App/AppCoordinator.swift` only for wiring if required
- new `FloatTabs/Web/RuntimeResourceMonitor.swift` or equivalent read-only Web/performance owner
- tests for preference normalization/resource observations

Requirements:

- `Auto` default for missing preference;
- Custom validation/clamp;
- Unlimited support;
- no lifecycle behavior change yet;
- old Warm/Cold stored values remain untouched/unused;
- resource monitor cannot reclaim/kill/reload anything.

Gate WP1:

- focused preference/resource tests PASS;
- Debug/Release build PASS;
- no change in Phase 7 lifecycle behavior while the new monitor/config is passive.

### WP2 — budget policy + progressive normal reclaim

Primary production scope:

- `FloatTabs/Web/SlotLifecycleCoordinator.swift`
- optional new pure decision type/file if separation materially improves testability
- `FloatTabs/App/AppCoordinator.swift` for preference/resource input wiring

Required change:

- retire `defaultManagedResidentTarget = 2` from current normal product decisions;
- remove normal count-over-budget early eviction;
- retire unconditional 30s Automatic release as current normal policy;
- retain 30s only as normal budget candidate grace;
- implement high/low watermark state;
- choose/reclaim one eligible Automatic candidate at a time;
- remeasure after each completed reclaim;
- no reclaim while under budget.

Focused acceptance:

1. 3/4/5 Automatic Runtimes under budget remain resident;
2. high watermark crossing selects one deterministic oldest eligible Runtime;
3. second candidate is not reclaimed until fresh over-budget evidence exists;
4. low watermark stops reclaim;
5. measurement unavailable stops normal budget reclaim;
6. hard-protected candidates are skipped;
7. Keep Loaded blocks ordinary convergence rather than being silently reclaimed.

### WP3 — system-pressure ladder

Primary owner:

- `FloatTabs/Web/SlotLifecycleCoordinator.swift`

Replace Phase 7 count targets:

```text
warning target 1
critical target 0
```

with progressive pressure behavior.

Warning:

- bypass normal 30s grace when needed;
- reclaim eligible inactive Automatic progressively;
- Keep Loaded remains preferred;
- active/hard-protected untouched.

Critical:

- Automatic first;
- then inactive/unprotected Keep Loaded;
- one at a time with current pressure/ownership revalidation;
- no active/hard-protected reclaim.

Focused tests must inject warning/critical deterministically; unsafe real system-pressure forcing is not required.

### WP4 — Advanced UI + persistence/backup projection

Expected scope:

- `FloatTabs/UI/SettingsInformationArchitecture.swift`
- `FloatTabs/UI/GlobalSettingsController.swift`
- `FloatTabs/Persistence/AppPreferencesStore.swift`
- `FloatTabs/Persistence/FloatTabsBackupService.swift` only if current backup owns global performance preferences
- corresponding tests

Required UI:

```text
Advanced
└── Runtime & Memory
    ├── Memory Budget: Auto / Custom / Unlimited
    ├── Custom GiB control when applicable
    └── explanatory soft-budget/session-safety text
```

Optional if measurement is available and cheap:

```text
Observed footprint: ~X.X GiB
Budget status: Healthy / Above budget / Blocked by protected work / Measurement unavailable
```

Do not place current budget in Browser/Profile data. It is app-global configuration.

### WP5 — background-generation / lifecycle-efficiency corrective

This package must not redesign provider semantics.

Audit current cost centers:

- `ChatGPTAttentionBridge` hidden liveness watchdog;
- repeated detector scheduling/evaluation;
- response identity resolution;
- incident/health probes;
- navigation/observer tasks that remain active while hidden;
- presentation-only work for detached Runtime.

Allowed changes:

- event-first completion sensing;
- adaptive fallback probe backoff while bridge is healthy;
- suppression of redundant hidden diagnostics/measurements;
- prompt task cancellation across document/runtime generation changes;
- bounded post-completion notification-recall grace before normal budget eligibility.

Initial post-completion normal-budget grace target:

```text
15 seconds
```

System warning/critical may bypass this grace.

Forbidden:

- hibernate while generation is active merely to save RAM;
- private WebKit freeze/scheduling APIs;
- claiming WebContent memory was reduced when only CPU/probe work changed;
- weakening completion correctness or native unread/notification routing.

Gate WP5:

- generation remains resident/protected throughout generation;
- completion is still detected/routed;
- background fallback work is measurably no worse and preferably lower;
- after completion, Runtime becomes budget-reclaimable without losing unread/session continuity.

### WP6 — integrated Real-Mac + A/B acceptance

Create/update a Phase 8-native benchmark path. Do not reuse Phase 7 `resident=2` success criteria.

Required Real-Mac scenarios:

#### A. Under-budget multi-Runtime residency

- open at least 3 real ChatGPT Slots;
- ensure observed footprint remains below high watermark using an appropriate test budget;
- verify all remain resident beyond the old 30s window;
- PASS proves fixed-count/unconditional-grace policy is gone.

#### B. Budget crossing

- configure a bounded Custom budget that can be crossed safely;
- establish multiple eligible inactive Automatic Runtimes;
- cross high watermark;
- verify exactly one candidate is reclaimed first;
- verify fresh measurement occurs before any next reclaim;
- verify reclaim stops at/below low watermark or no-candidate boundary.

#### C. Hard protection under budget pressure

- active Slot protected;
- generating Slot protected;
- inactive Automatic reclaimed first;
- generation continues normally.

#### D. Generation completion

- hidden generation completes;
- native unread/notification remains correct;
- generating protection ends;
- if still over budget, completion Runtime becomes reclaimable after bounded recall grace;
- selecting it restores exact Slot/session.

#### E. Keep Loaded

- normal budget does not reclaim inactive Keep Loaded;
- diagnostics/report clearly records if Keep Loaded prevents reaching low watermark;
- critical ordering remains machine-test proven unless a safe existing real-pressure trigger exists.

#### F. Thrash test

Repeated A → B → C → A switching around the budget boundary must not repeatedly hibernate the just-used Slot. Record reclaim/restore count and P50/P95 restore latency.

#### G. A/B baseline

Run identical workload against:

```text
Phase 7 merged baseline: 2b414982710b3f042fc7d6e9c88eb2d7117b4e38
Phase 8 candidate: exact PR semantic head
```

Compare at minimum:

- aggregate FloatTabs/WebKit RSS/footprint trend;
- WebContent/helper process count;
- host + helper CPU during hidden generation;
- number of hibernate/restore cycles;
- switch latency for resident Slot;
- restore latency for reclaimed Slot;
- session/login continuity.

Do not claim exact per-Slot memory savings.

## 8. Expected tests

At minimum inspect/update/add coverage in:

- `FloatTabsTests/AppPreferencesStoreTests.swift`
- `FloatTabsTests/WebAttentionLifecycleTests.swift`
- `FloatTabsTests/WebViewPoolTests.swift`
- `FloatTabsTests/SettingsInformationArchitectureTests.swift`
- `FloatTabsTests/FloatTabsBackupServiceTests.swift` when backup scope changes
- `FloatTabsTests/ChatGPTAttentionBridgeTests.swift`
- `FloatTabsTests/ExternalShellTests.swift` for restore/presentation regression where relevant
- new resource-monitor/policy tests if new production types are introduced

Retire/update tests that assert Phase 7 current-product count targets (`2/1/0`) or unconditional 30s release. Preserve Phase 7 behavior in Git history/contracts rather than compatibility shims that keep superseded policy alive.

## 9. Expected production file boundary

Primary expected files:

```text
FloatTabs/Persistence/AppPreferencesStore.swift
FloatTabs/Web/SlotLifecycleCoordinator.swift
FloatTabs/Web/RuntimeResourceMonitor.swift        (new, if Gate 0 selects this shape)
FloatTabs/App/AppCoordinator.swift
FloatTabs/UI/SettingsInformationArchitecture.swift
FloatTabs/UI/GlobalSettingsController.swift
FloatTabs/Persistence/FloatTabsBackupService.swift (conditional)
FloatTabs/Web/ChatGPTAttentionBridge.swift         (WP5 only)
```

Mechanically required related files/tests are allowed when the exact audit proves the dependency. Material product scope outside these areas is a reconciliation trigger.

## 10. Phase 8 verification gates

### Gate 0 — measurement feasibility

Production-safe aggregate measurement proven or STOP/reconcile.

### Gate A — pure policy/config tests

PASS for:

- Auto/Custom/Unlimited normalization;
- watermarks;
- candidate eligibility/ranking;
- under-budget no-reclaim;
- one-at-a-time decision sequence;
- measurement unavailable behavior.

### Gate B — lifecycle/protection tests

PASS for:

- active/presentation;
- generating;
- fullscreen;
- supplemental visibility;
- background media;
- materialization/restore;
- Keep Loaded normal/critical semantics;
- warning/critical progressive ordering.

### Gate C — Settings/persistence/backup

PASS for new Advanced UI, additive defaults, restore validation and no legacy Warm/Cold UI revival.

### Gate D — background efficiency

PASS for generation continuity/completion plus bounded observer/task work.

### Gate E — broad machine verification

- full XCTest PASS;
- Debug arm64 build PASS;
- Release arm64 build PASS;
- native architecture PASS;
- package lock unchanged unless separately authorized.

### Gate F — repository host

Literal PR head passes required `Build & Test (Apple Silicon arm64)` on `[self-hosted, macOS, ARM64, mac-mini-ci]`.

### Gate G — Real-Mac Phase 8 acceptance

WP6 scenarios A-G pass or have explicit NOT_PROVEN disposition accepted by Authority.

### Gate H — fresh exact-diff / ownership audit

Verify:

- no second lifecycle writer;
- no private WebKit SPI;
- no fixed-count normal policy remains;
- no destructive session/cache coupling;
- Phase 6 restore preserved;
- generation protection preserved;
- diagnostics remain evidence only;
- budget measurement does not claim per-Slot attribution.

Only after Gates 0/A-H pass may Phase 8 be merge-ready.

## 11. Construction sequence

The implementation must proceed in this order:

```text
1. control/task alignment
2. fresh WP0 source audit
3. freeze exact WP1 files/symbols/tests if audit differs materially
4. WP1 passive configuration/resource measurement
5. verify WP1
6. WP2 budget scheduler
7. verify WP2
8. WP3 pressure ladder
9. verify WP3
10. WP4 Advanced UI/persistence
11. verify WP4
12. WP5 background efficiency corrective
13. verify WP5
14. WP6 Real-Mac + A/B evidence
15. fresh exact-diff audit
16. merge-readiness decision
```

Do not combine all work packages into one unreviewed mutation if phase-local evidence shows a safer bounded split.

## 12. STOP conditions

STOP and reconcile if:

- Gate 0 cannot prove production-safe aggregate footprint measurement;
- implementation requires private WebKit SPI;
- lifecycle decisions move outside `SlotLifecycleCoordinator`;
- resource monitor kills/reloads Runtime directly;
- memory budget becomes a disguised resident-count setting;
- active/generating/fullscreen/protected-media/restoring Runtime is selected for normal budget reclaim;
- Keep Loaded semantics are weakened beyond this contract without explicit user decision;
- Browser Profile/session/site data would be reset/migrated/destructively cleaned;
- current Phase 6 restore would need redesign rather than integration;
- WP5 requires provider-specific invasive page mutation instead of bounded observation;
- a repository-host required Gate fails.

## 13. Frozen implementation state

```text
PHASE8_CONTRACT=ACCEPTED_FROZEN
IMPLEMENTATION=NOT_STARTED
BASELINE_MAIN=2b414982710b3f042fc7d6e9c88eb2d7117b4e38
FIRST_IMPLEMENTATION_GATE=WP0_MEASUREMENT_FEASIBILITY_AND_SOURCE_AUDIT
NORMAL_FIXED_COUNT_POLICY=SUPERSEDED_TARGET
NORMAL_UNCONDITIONAL_30S_RECLAIM=SUPERSEDED_TARGET
MEMORY_BUDGET=PRIMARY_NORMAL_CONTROL
PROGRESSIVE_RECLAIM=ONE_AT_A_TIME
SYSTEM_PRESSURE=INDEPENDENT_LADDER
PROACTIVE_IDLE_DEFAULT=OFF
BACKGROUND_GENERATING=HARD_PROTECTED
NEXT_MUTATION=ONLY_AFTER_DESIGN_CLOSEOUT_AND_EXPLICIT_IMPLEMENTATION_AUTHORIZATION
```
