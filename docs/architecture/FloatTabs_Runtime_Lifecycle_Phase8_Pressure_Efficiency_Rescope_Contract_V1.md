# FloatTabs Runtime Lifecycle — Phase 8 Pressure + Efficiency Re-scope Contract V1

**Program:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Re-scope:** `Phase 8 measurement-independent continuation`  
**Status:** `HISTORICAL RE-SCOPE / TECHNICAL EVIDENCE; SUPERSEDED WHERE POLICY V7 DIFFERS`  
**User decision:** `D_COMBINE = B now + A later`  
**Parent design authority:** `FloatTabs_Runtime_Lifecycle_Memory_Contract_V6.md`  
**Gate 0 evidence:** `FloatTabs_Runtime_Lifecycle_Phase8_WP0_Measurement_Feasibility_Report_V1.md`

> **WP2 policy status (2026-11-02):** This delivered Phase 8 re-scope remains historical evidence for pressure/background-efficiency implementation and the aggregate-memory attribution boundary. Its preserved healthy-state fixed-count target and Keep Loaded critical-reclaim semantics are superseded for WP2 by [Runtime Lifecycle Policy V7](FloatTabs_Runtime_Lifecycle_Policy_V7.md). The original pre-WP2 body is preserved in the architecture archive.

## 1. Decision and purpose

Phase 8 Gate 0 proved that FloatTabs cannot, with supported public production APIs, deterministically attribute the dominant WebContent/GPU helper processes to the host app. Therefore the aggregate-memory-budget track remains blocked.

The user selected `D_COMBINE` on 2026-11-02:

```text
B now  = execute only measurement-independent lifecycle improvements
A later = revisit aggregate memory budget only if a supported deterministic
          attribution capability becomes available
```

The original decision limited the design to measurement-independent improvements; it did not relax the deterministic WebContent attribution requirement. It is historical design evidence, not present implementation permission.

## 2. Long-term budget track disposition

The following original Phase 8 packages remain deferred / platform-blocked:

- WP1 aggregate resource monitor and budget configuration;
- WP2 aggregate-memory budget scheduler;
- WP4 memory-budget UI / persistence projection;
- WP6 aggregate-memory A/B claims that require attributable FloatTabs/WebKit working-set evidence.

The V6 adaptive memory-budget architecture remains a future design target, not current production truth.

Reopen that track only when a supported production-safe mechanism can deterministically attribute the required WebKit helper footprint to FloatTabs. Private WebKit SPI, root-only tools, restricted entitlements, guessed per-tab memory, Runtime-count substitution, and transition-correlation heuristics are not acceptable substitutes.

## 3. Current production policy preserved during this re-scope

At the original re-scope baseline, healthy/normal memory conditions used the Phase 7 policy:

```text
runtimeRetentionPreference = Automatic | Keep Loaded
normal Automatic resident target = 2
Automatic inactive release path = 30s
```

This was a constraint of the original re-scope, **not current product truth**. Current normal and pressure behavior is defined by [Runtime Lifecycle Policy V7](FloatTabs_Runtime_Lifecycle_Policy_V7.md) and current source/tests.

The original proposed change replaced Phase 7 `warning target = 1 / critical target = 0` count targets with progressive memory-pressure reclaim.

## 4. Historical Package R1 / original WP3 — progressive system-pressure ladder

This section records the **pre-WP2** proposal. Its Critical fallback to Keep Loaded is superseded by Policy V7; Keep Loaded is not a current pressure-reclaim candidate.

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

Other Web/Attention/runtime dependencies are product-specific only when they contribute to the verified lifecycle behavior. `PanelController.swift` is not a lifecycle-policy writer.

Expected tests to inspect/update/add include the current equivalents of:

```text
FloatTabsTests/WebViewPoolTests.swift
FloatTabsTests/WebAttentionLifecycleTests.swift
FloatTabsTests/ChatGPTAttentionBridgeTests.swift
```

Add focused coordinator/pressure tests in the existing appropriate test owner if current coverage is elsewhere.

This historical design did not require Settings, memory-budget preference, backup schema, Browser Profile or website-data migration changes.

## 7. Product evidence and supersession

The original R1/R2 work emphasized deterministic warning/critical pressure injection, single in-flight reclaim, generation-safe continuation, hidden-generation scheduling bounds, and unchanged session/unread/restore semantics. That evidence remains useful for current product regressions.

The **current** FloatTabs pressure behavior is governed by [Policy V7](FloatTabs_Runtime_Lifecycle_Policy_V7.md) and the implementation in `SlotLifecycleCoordinator`:

- Warning: reclaim only eligible inactive, unprotected Automatic Runtime in IDLE / LONG_IDLE.
- Critical: reclaim eligible inactive, unprotected Automatic Runtime; **never Keep Loaded**, even at critical pressure.
- Pressure normalizes: cancel not-yet-started reclaim continuation; do not mass-restore.
- Any claim of exact app-owned WebContent/GPU memory usage requires an independently supported attribution capability. Runtime count is not a measured GiB budget.
- Efficiency evidence must measure actual affected host-side scheduling/probe work, without implying WebContent memory reclamation.
- Runtime ownership, stale-callback rejection, Browser Profile/session durability, and generating/Attention protection remain intact.

These are product-specific regression expectations. This historical document no longer defines CI breadth, task authorization, PR construction order, release decisions, or merge gates.

## 8. Original re-scope record

The 2026-11-02 decision was `D_COMBINE = B now + A later`. The aggregate memory-budget track remained blocked by public WebKit process-attribution limitations. The original normal fixed-count and critical Keep Loaded behaviors have since been superseded; the original text remains available in `archive/FloatTabs_Runtime_Lifecycle_Phase8_Pressure_Efficiency_Rescope_Contract_V1_Pre_WP2_2026-11-02.md`.

This historical decision does not grant present task permission or prescribe repository delivery.
