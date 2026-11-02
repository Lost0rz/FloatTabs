# FloatTabs Runtime Lifecycle — Phase 8 Pressure + Efficiency Re-scope Contract V1

**Program:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`
**Re-scope:** `Phase 8 measurement-independent continuation`
**Status:** `ACCEPTED / FROZEN / IMPLEMENTATION AUTHORIZED AFTER PR #190 CLOSEOUT MERGE`
**User decision:** `D_COMBINE = B now + A later`
**Parent design authority:** `FloatTabs_Runtime_Lifecycle_Memory_Contract_V6.md`
**Gate 0 evidence:** `FloatTabs_Runtime_Lifecycle_Phase8_WP0_Measurement_Feasibility_Report_V1.md`

## 1. Decision and purpose

Phase 8 Gate 0 proved that FloatTabs cannot, with supported public production APIs, deterministically attribute the dominant WebContent/GPU helper processes to the host app. Therefore the aggregate-memory-budget track remains blocked.

The user selected `D_COMBINE` on 2026-11-02:

```text
B now  = execute only measurement-independent lifecycle improvements
A later = revisit aggregate memory budget only if a supported deterministic
          attribution capability becomes available
```

This contract authorizes only the measurement-independent continuation. It does not weaken the Gate 0 determinism requirement and does not authorize best-effort process attribution.

## 2. Long-term budget track disposition

The following original Phase 8 packages remain deferred / platform-blocked:

- WP1 aggregate resource monitor and budget configuration;
- WP2 aggregate-memory budget scheduler;
- WP4 memory-budget UI / persistence projection;
- WP6 aggregate-memory A/B claims that require attributable FloatTabs/WebKit working-set evidence.

The V6 adaptive memory-budget architecture remains a future design target, not current production truth.

Reopen that track only when a supported production-safe mechanism can deterministically attribute the required WebKit helper footprint to FloatTabs. Private WebKit SPI, root-only tools, restricted entitlements, guessed per-tab memory, Runtime-count substitution, and transition-correlation heuristics are not acceptable substitutes.

## 3. Current production policy preserved during this re-scope

Until a future budget track is separately authorized and proven feasible, healthy/normal memory conditions retain the merged Phase 7 normal policy:

```text
runtimeRetentionPreference = Automatic | Keep Loaded
normal Automatic resident target = 2
Automatic inactive release path = 30s
```

This re-scope MUST NOT retire or redesign that normal policy.

The only lifecycle-policy mutation authorized here is replacement of the Phase 7 `warning target = 1 / critical target = 0` count targets with a progressive system-memory-pressure ladder.

## 4. Package R1 / original WP3 — progressive system-pressure ladder

**Primary owner:** `FloatTabs/Web/SlotLifecycleCoordinator.swift`.

Use the existing supported system memory-pressure signal as the only pressure trigger. No aggregate FloatTabs memory estimate is required.

### Warning

When the latest pressure state is warning:

1. preserve active/presented, fullscreen, supplemental-visible, generating, protected background-media, restoring/materializing and other existing hard protections;
2. select only an inactive/unprotected `Automatic` Runtime;
3. choose candidates deterministically using existing lifecycle recency/ownership facts;
4. reclaim through the existing `WebViewPool.hibernate` / release boundary;
5. allow at most one reclaim transaction in flight;
6. after completion, revalidate the latest pressure state and current Runtime/protection ownership before any further step;
7. preserve `Keep Loaded` at warning.

A bounded delayed continuation is allowed only while the latest observed pressure state remains warning/critical. A single stale event must not cause a precomputed multi-Runtime purge.

### Critical

When the latest pressure state is critical:

1. reclaim eligible inactive/unprotected `Automatic` first;
2. only after no eligible Automatic remains may inactive/unprotected `Keep Loaded` be considered;
3. keep active/hard-protected Runtime untouched;
4. execute one Runtime at a time with current pressure/ownership revalidation between steps.

### Pressure cleared

When pressure returns to normal:

- cancel/stop any not-yet-started progressive continuation;
- do not proactively restore every reclaimed Runtime;
- future restore remains demand-driven by existing Slot selection/materialization behavior.

### R1 anti-goals

Do not:

- use Runtime count as a replacement memory budget or pressure target;
- add a second lifecycle writer;
- use private WebKit scheduling/freeze APIs;
- reload/reset website data as reclaim;
- modify the healthy-state target=2 / 30s normal policy in this task.

## 5. Package R2 / original WP5 — background lifecycle efficiency

This package reduces host-side work while preserving runtime/generation correctness. It does not claim WebContent memory savings.

Audit and correct only verified cost centers such as:

- hidden `ChatGPTAttentionBridge` liveness/fallback probing;
- repeated detector scheduling/evaluation;
- response identity resolution work repeated without a state change;
- incident/health probes or diagnostics that continue unnecessarily while hidden;
- navigation/observer tasks that survive document/runtime generation changes;
- presentation-only host work for detached/reclaimed Runtime;
- duplicate observer registration or uncancelled Swift concurrency tasks across hibernate/restore/rebuild.

Allowed implementation patterns:

- event-first completion sensing with bounded fallback;
- adaptive fallback backoff while the bridge is healthy;
- suppression/coalescing of redundant hidden host-side work;
- prompt cancellation when document/runtime generation changes invalidate ownership;
- exact-current ownership checks before callbacks mutate state.

Required invariants:

- live `Generating` remains Runtime-protected;
- completion/unread/native notification routing remains correct;
- selecting/restoring the exact Slot preserves session/login state;
- no Browser Profile, cookie, website session or persisted Slot configuration is cleared;
- diagnostics remain evidence-only and never become lifecycle truth.

Forbidden:

- provider-semantic redesign;
- invasive page mutation for performance;
- hibernating an actively generating Runtime merely to save resources;
- claiming renderer/WebContent memory reduction from host-side timer/observer improvements.

## 6. Expected source/test boundary

Expected production owners to inspect first:

```text
FloatTabs/Web/SlotLifecycleCoordinator.swift
FloatTabs/Web/WebViewPool.swift
FloatTabs/Web/ChatGPTAttentionBridge.swift
```

Mechanically related Web/Attention/runtime files may change only when the focused source audit proves the dependency. `PanelController.swift` may be touched only for an exact wiring/ownership dependency already proven by the audit; it is not a new lifecycle writer.

Expected tests to inspect/update/add include the current equivalents of:

```text
FloatTabsTests/WebViewPoolTests.swift
FloatTabsTests/WebAttentionLifecycleTests.swift
FloatTabsTests/ChatGPTAttentionBridgeTests.swift
```

Add focused coordinator/pressure tests in the existing appropriate test owner if current coverage is elsewhere.

No Settings, memory-budget preference, backup schema, Browser Profile, or website-data migration change is authorized.

## 7. Verification gates

### Gate R0 — focused source reconciliation

Before product mutation, confirm against fresh main after PR #190 merge:

- `SlotLifecycleCoordinator` is still the sole lifecycle writer;
- current pressure source and its normal/warning/critical state path;
- current candidate/protection facts and `WebViewPool` reclaim boundary;
- current hidden generation observer/task owners;
- exact affected tests.

If the owner map materially differs from the WP0 report, update Authority before implementation.

### Gate R1 — pressure ladder tests

Deterministically inject pressure states and prove:

- warning reclaims eligible Automatic progressively, not by fixed target count;
- warning preserves Keep Loaded;
- critical orders Automatic before inactive/unprotected Keep Loaded;
- active/hard-protected Runtime is never selected;
- only one reclaim transaction is in flight;
- each continuation revalidates latest pressure/ownership;
- normal pressure cancels pending continuation and does not mass-restore.

Unsafe real system-pressure forcing is not required.

### Gate R2 — background-efficiency tests

Prove for each changed cost center:

- task/observer lifecycle is bounded to current document/runtime ownership;
- stale callbacks/tasks are cancelled or harmless;
- generation continuity and completion routing remain intact;
- hidden fallback work is no worse and, where the change is intended to reduce work, observable scheduling/probe counts are lower or bounded by deterministic tests.

### Gate R3 — broad machine verification

Required:

- full XCTest PASS;
- Debug arm64 build PASS;
- Release arm64 build PASS;
- native arm64 architecture verification PASS;
- package lock unchanged unless separately authorized.

### Gate R4 — repository host

Literal PR head passes required `Build & Test (Apple Silicon arm64)` on the established self-hosted runner labels `[self-hosted, macOS, ARM64, mac-mini-ci]`.

### Gate R5 — fresh exact-diff / ownership audit

Before merge readiness, verify:

- no aggregate/best-effort memory attribution was introduced;
- no second lifecycle writer;
- no private WebKit SPI;
- no healthy-state normal target=2 / 30s policy change;
- no destructive session/cache coupling;
- Phase 6 restore and generation protection remain intact;
- any efficiency claim is limited to the host-side work actually measured/tested.

Human final runtime/UI acceptance remains owned by the broader lifecycle program unless a later task explicitly requires an earlier human gate.

## 8. Construction order

```text
1. merge/close PR #190 after its literal new head is green
2. start from fresh main containing this contract/control reconciliation
3. create one bounded implementation branch/PR for this re-scope
4. Gate R0 focused source reconciliation
5. implement R1 pressure ladder + focused tests
6. verify R1
7. implement R2 background lifecycle efficiency + focused tests
8. verify R2
9. Gate R3 broad machine verification
10. Gate R4 literal-head self-hosted macOS CI
11. Gate R5 fresh exact-diff / ownership audit
12. merge-readiness decision
```

Do not create a parallel aggregate-memory-budget implementation branch while this re-scope is active.

## 9. STOP conditions

STOP and reconcile before further mutation if:

- a supported deterministic aggregate memory capability is claimed but not independently proven;
- implementation needs private WebKit SPI, root, restricted entitlement, or guessed process attribution;
- current source no longer has a single clear lifecycle writer;
- pressure progression cannot be made one-at-a-time with current-state revalidation;
- normal target=2 / 30s policy must change to make R1 work;
- generation correctness requires provider-semantic redesign;
- Browser Profile/session/site data would be reset, migrated or destructively cleaned;
- a required machine or repository-host gate fails.

## 10. Frozen re-scope state

```text
USER_DECISION=D_COMBINE
BUDGET_TRACK=DEFERRED_PLATFORM_BLOCKED
BEST_EFFORT_ATTRIBUTION=FORBIDDEN
CURRENT_IMPLEMENTATION_SCOPE=PRESSURE_LADDER_PLUS_BACKGROUND_EFFICIENCY
NORMAL_POLICY=PHASE7_TARGET2_PLUS_30S_PRESERVED
PRESSURE_POLICY=PROGRESSIVE_ONE_AT_A_TIME
WARNING_KEEP_LOADED=PRESERVED
CRITICAL_ORDER=AUTOMATIC_THEN_INACTIVE_UNPROTECTED_KEEP_LOADED
PRODUCT_UI_CHANGE=NONE
PRODUCT_DATA_MIGRATION=NONE
FIRST_PRODUCT_GATE=R0_FOCUSED_SOURCE_RECONCILIATION
```
