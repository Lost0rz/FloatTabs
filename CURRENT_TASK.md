# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001-PHASE8-DESIGN`  
**Title:** Adaptive Runtime Memory Budget + Background Efficiency — design freeze  
**Status:** `ACTIVE / DESIGN FREEZE / NO PRODUCT MUTATION`  
**Mode:** `ARCHITECTURE / POLICY DESIGN / DOCUMENT ALIGNMENT`  
**Task class:** `WEB RUNTIME / LIFECYCLE / MEMORY / PERFORMANCE`  
**Baseline:** `main@2b414982710b3f042fc7d6e9c88eb2d7117b4e38`

## Authorization state

The user explicitly authorized a redesign of FloatTabs performance/lifecycle policy after Phase 7 merge, with these goals:

1. replace the fixed normal resident-count policy (`2`) with a memory-budget-driven policy;
2. let the user configure an approximate FloatTabs/WebKit memory budget rather than a maximum number of open pages;
3. reclaim inactive Runtime progressively only when budget/system pressure requires it;
4. preserve active/generating/fullscreen/media/materializing hard protections;
5. keep the Phase 1-7 hibernate/restore/session/notification foundations;
6. reassess background-generation thrift and other Chrome/open-source lifecycle mechanisms that Phase 7 does not yet implement;
7. freeze the new plan and update documentation before any production-code construction.

This task authorizes **design/control/document changes only**. No `FloatTabs/**` production mutation is authorized until the new frozen contract and phase implementation gate are accepted.

## Current baseline truth

Phase 7 is merged at `main@2b414982710b3f042fc7d6e9c88eb2d7117b4e38`.

The current production policy still contains:

```text
normal Automatic target = 2
Automatic grace = 30s
warning target = 1
critical target = 0
```

Fresh source review confirms `RuntimeBudgetPolicy.defaultManagedResidentTarget = 2`, so opening a third eligible Automatic Runtime can cause immediate LRU reclaim even when memory is healthy. This behavior is now treated as a policy limitation to be superseded by Phase 8, not as the target design.

Phase 7 foundations remain valid and must be preserved:

- persistent Slot/Profile/session separated from disposable Runtime;
- `SlotLifecycleCoordinator` is the sole lifecycle writer;
- `WebViewPool` owns materialize/hibernate/restore;
- `interactionState`-based restore support;
- Attention `Generating` protects Runtime while `Ready`/unread does not;
- completion notification/unread survives Runtime reclaim;
- Browser Profile/login/cookie/session data is never ordinary reclaim data;
- Keep Loaded is a preference, not launch-time preload.

## Design scope

The design freeze must define:

### A. Memory-budget model

- `Auto` memory budget (recommended);
- user `Custom` memory budget in bytes/GiB;
- optional `Unlimited` normal-budget mode while still respecting system memory pressure;
- high/low watermark hysteresis;
- aggregate owned-process footprint estimation without claiming exact per-Slot WebContent attribution;
- clear fallback behavior when aggregate attribution is temporarily unavailable.

### B. Progressive reclaim

Normal operation must not reclaim merely because resident Runtime count exceeds a fixed number.

When the memory budget or system pressure requires reclaim:

```text
choose safest eligible candidate
→ hibernate/release one Runtime
→ re-measure / re-evaluate
→ stop when pressure is relieved
→ otherwise continue one at a time
```

Candidate ordering must prioritize protection/safety first, then inactivity/recency and restore cost. Fixed Runtime count may remain only as a deterministic test seam or emergency safety guard if separately justified; it must not be the user-facing normal policy.

### C. Background-generation efficiency

Preserve generating continuity. Audit and optimize only work that can safely be reduced while the Runtime must remain alive, including observation/probe cadence and other host-side work. Do not claim that WKWebView memory itself can be deeply frozen while generation continues unless supported by public WebKit APIs and fresh evidence.

### D. Lifecycle aggressiveness / idle policy

Separate:

- memory-budget pressure;
- system memory-pressure response;
- proactive long-idle cleanup.

Do not reuse the Phase 7 `30s` grace as an unconditional browser-wide long-idle discard rule. The new contract must define whether proactive idle cleanup is off by default, tied to Auto aggressiveness, or separately user-configurable.

### E. Advanced settings

The intended user-facing location is `Advanced → Runtime & Memory` (or an equivalent bounded Advanced section after IA review), with memory budget as the primary control. The UI must not expose implementation-level resident-count knobs as the main product model.

### F. Verification

The plan must define:

- deterministic policy/unit tests;
- aggregate footprint measurement tests/harness;
- Real-Mac budget crossing/reclaim/restore scenarios;
- active/generating/media/fullscreen protections;
- no-thrash hysteresis evidence;
- session continuity;
- old-vs-new A/B performance benchmark on identical Slot workload;
- required self-hosted Apple Silicon CI before merge.

## Research inputs accepted for design

Current external reference review may inform the plan but does not become repository authority by itself:

- Chrome Memory Saver uses user-selectable aggressiveness and eligibility exceptions rather than a fixed count ceiling;
- current Chromium Memory Saver combines inactivity timers with revisit heuristics and separate memory-pressure/discard machinery;
- Kylmora uses lazy materialization, idle/memory-pressure sleep and per-tab Keep Awake;
- Kestrel demonstrates WKWebView hibernate/restore using `interactionState` and memory-pressure-triggered sleep.

Any mechanism requiring private WebKit SPI, exact private renderer accounting, or unsafe process control must be rejected or separately gated.

## Authorized paths for this design-freeze task

Primary:

- `CURRENT_STATUS.md`
- `CURRENT_TASK.md`
- `docs/README.md`
- `docs/architecture/README.md`
- `docs/architecture/DOMAIN_MAP.md`
- new current architecture/performance contract(s)
- new archive/status snapshot documents needed to preserve Phase 7/V5 history

No production source/test/tooling mutation is authorized in this task unless needed only to read evidence; write scope remains documentation/control only.

## Deliverables

1. frozen V6 lifecycle/memory program contract;
2. frozen Phase 8 implementation plan/contract with work packages and Gates;
3. archived Phase 7/V5 closeout snapshot and routing so superseded policy cannot be mistaken for current target behavior;
4. updated `CURRENT_STATUS.md`, `docs/README.md`, `docs/architecture/README.md`, and `DOMAIN_MAP.md`;
5. final design receipt with exact branch/head and next implementation Gate.

## STOP conditions

STOP before production construction if the design would require:

- deleting/resetting Browser Profile, cookies, session, website data, or user configuration;
- a second canonical lifecycle writer;
- private WebKit SPI as a required production dependency;
- pretending exact per-Slot memory attribution is available when it is not;
- killing a Runtime that is active, generating, fullscreen, protected background media, or in current materialization/restore ownership;
- making reload/reset/restart an ordinary memory-management mechanism;
- interpreting the user memory budget as a hard OS-enforced cap rather than a best-effort soft working-set target;
- product/source mutation before this design-freeze task is closed and a bounded implementation task is authorized.

## Current execution state

```text
BASELINE_MAIN=2b414982710b3f042fc7d6e9c88eb2d7117b4e38
PHASE7=MERGED
PHASE8_DESIGN=ACTIVE
PRODUCT_MUTATION=NOT_AUTHORIZED
TARGET_NORMAL_POLICY=MEMORY_BUDGET_DRIVEN
FIXED_NORMAL_RESIDENT_COUNT=TO_BE_SUPERSEDED
NEXT_GATE=FREEZE_V6_AND_PHASE8_CONTRACTS_THEN_CONTROL_ALIGNMENT
```
