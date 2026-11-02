# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001-PHASE8-PRESSURE-EFFICIENCY`  
**Title:** Phase 8 measurement-independent continuation — pressure ladder + background efficiency  
**Status:** `ACTIVE / R0-R5 PASS / CORRECTIVE CLOSED / MERGE AUTHORIZED`  
**Mode:** `CONTROL CLOSEOUT / LITERAL-HEAD CI / MERGE`  
**Task class:** `WEB RUNTIME / LIFECYCLE / PERFORMANCE`  
**Execution baseline:** `main@065d2923f0516694689ee71f2787b76c8719bfe8 after merged PR #190`

## Authorization

The user selected `D_COMBINE` on 2026-11-02 and authorized the measurement-independent continuation only:

1. progressive system-memory-pressure reclaim in the existing lifecycle owner;
2. bounded host-side background observer/task/generation efficiency corrections.

The aggregate-memory-budget track remains deferred/platform-blocked by Phase 8 Gate 0.

After independent audit and one bounded R1 corrective, the user explicitly authorized merge closeout for PR #191.

## Frozen authority

- Project rules: `AGENTS.md`
- Program design: `docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V6.md`
- Original Phase 8 budget contract: `docs/architecture/FloatTabs_Runtime_Lifecycle_Phase8_Adaptive_Memory_Budget_Implementation_Contract_V1.md` — stopped at Gate 0 for budget construction
- Gate 0 evidence: `docs/architecture/FloatTabs_Runtime_Lifecycle_Phase8_WP0_Measurement_Feasibility_Report_V1.md`
- **Current implementation contract:** `docs/architecture/FloatTabs_Runtime_Lifecycle_Phase8_Pressure_Efficiency_Rescope_Contract_V1.md`
- Navigation: `docs/architecture/DOMAIN_MAP.md`, `docs/README.md`

The re-scope contract owns the bounded implementation where it differs from the blocked original Phase 8 budget sequence. V6 remains long-term architecture direction; blocked budget semantics are not current production truth.

## Completed implementation scope

### R1 — progressive system-memory-pressure ladder

Primary owner: `FloatTabs/Web/SlotLifecycleCoordinator.swift`.

Implemented and verified:

- warning reclaims only eligible inactive/unprotected `Automatic` Runtime;
- warning preserves `Keep Loaded`;
- critical reclaims eligible Automatic first, then inactive/unprotected Keep Loaded;
- active/presented, fullscreen, supplemental-visible, generating, protected background-media and other hard-protected Runtime remain protected;
- at most one reclaim continuation is pending;
- every continuation re-evaluates latest pressure and current Runtime/protection facts;
- pressure returning to normal cancels not-yet-started progression and does not mass-restore;
- healthy-state Automatic target=2 and 30s inactive release remain unchanged.

### R1 independent-audit corrective

The first independent audit found one blocking sustained-pressure defect: after progression stopped at `no_candidate`, later eligibility changes did not re-enter the pressure ladder unless the system emitted another same-level pressure event.

Corrective design:

```text
reconcileProgressivePressureIfNeeded()
  guard latestMemoryPressureLevel != nil
  guard pressureReclaimWorkItem == nil
  → beginProgressivePressureReclaim(latest level)
```

Eligibility re-entry is driven from the inactive-plan creation choke point and the media-protection-ended boundary. It does not add polling, a second scheduler or a second lifecycle writer.

Mandatory regressions passed:

- sustained warning + generation protection ends without new warning event;
- sustained critical + Keep Loaded protection ends without new critical event;
- warning → critical immediate takeover with stale warning continuation cancelled;
- normal pressure clears stale state before later eligibility changes;
- repeated eligibility boundaries produce a single reclaim chain.

The diagnostics field `budget_target` was renamed to `normal_managed_resident_target` so pressure diagnostics do not imply a warning/critical count target.

### R2 — background lifecycle efficiency

Primary changed owner: `FloatTabs/Web/ChatGPTAttentionBridge.swift`.

Verified bounded change:

```text
hidden generation <30s    → 2s fallback watchdog
hidden generation 30–120s → 5s fallback watchdog
hidden generation >=120s  → 10s fallback watchdog
```

Event-driven completion remains primary. No provider-semantic redesign, WebContent-memory claim, generation-protection change or session/data mutation is authorized or present.

## Deferred / out of scope

Do NOT implement under this task:

- aggregate FloatTabs/WebKit memory monitor as lifecycle input;
- Auto/Custom/Unlimited memory budget;
- budget watermarks;
- memory-budget Settings UI or persistence/backup schema;
- aggregate-memory A/B acceptance claims;
- best-effort WebContent/GPU process attribution;
- healthy-state target=2 / 30s redesign;
- private WebKit SPI, root-only helpers or restricted-entitlement attribution;
- Browser Profile/session/site-data reset or migration.

## Gate results

```text
GATE_R0_FOCUSED_SOURCE_RECONCILIATION=PASS
GATE_R1_PRESSURE_LADDER=PASS
R1_SUSTAINED_PRESSURE_CORRECTIVE=PASS
GATE_R2_BACKGROUND_EFFICIENCY=PASS
GATE_R3_FULL_XCTEST=PASS
GATE_R3_DEBUG_ARM64=PASS
GATE_R3_RELEASE_ARM64=PASS
GATE_R3_NATIVE_ARCH=PASS
GATE_R3_PACKAGE_LOCK=UNCHANGED
GATE_R4_SELF_HOSTED_CI_IMPLEMENTATION_HEAD=PASS
QA_DMG_IMPLEMENTATION_HEAD=PASS
GATE_R5_INDEPENDENT_EXACT_DIFF_OWNERSHIP_AUDIT=PASS
BLOCKING_FINDINGS=0
IMPORTANT_FINDINGS=0
CODE_MERGE_READY=YES
```

Independent audit confirmed:

- sustained-pressure eligibility re-entry coverage is sufficient;
- warning → critical takeover preserves single-chain semantics and ordering;
- R2 was unchanged by the corrective;
- no aggregate/best-effort attribution was introduced;
- no private WebKit SPI was introduced;
- no second lifecycle writer was introduced;
- no destructive Browser Profile/session/cache coupling exists;
- healthy-state target=2 / 30s remains intact.

## Current merge closeout gate

This control-plane closeout changes the literal PR head. Therefore the prior implementation-head CI/QA PASS cannot be reused as the final repository-host identity gate.

Before merge:

```text
1. literal control-closeout #191 head required Build & Test (Apple Silicon arm64) = PASS
2. QA DMG = PASS if triggered on that literal head
3. fresh #191 head/base/mergeability = clean
4. mark PR Ready for Review if still Draft
5. squash merge using expected literal head SHA
6. verify fresh main contains merged Phase 8 re-scope
```

No further product-source mutation is authorized before merge unless a new blocking gate failure is discovered.

## Human acceptance

`HUMAN_UI_ACCEPTANCE=PENDING_PROGRAM_FINAL`.

The accepted re-scope contract keeps human runtime/UI acceptance at the broader lifecycle program-final boundary; it is not an earlier blocker for PR #191 merge.

## Current execution state

```text
USER_DECISION=D_COMBINE
BUDGET_TRACK=DEFERRED_PLATFORM_BLOCKED
CURRENT_SCOPE=PRESSURE_LADDER_PLUS_BACKGROUND_EFFICIENCY
PR_190=MERGED_AT_MAIN_065D2923
SUCCESSOR_PR=#191
SUCCESSOR_BRANCH=codex/ft-pressure-efficiency-phase8-rescope-001
R0=PASS
R1=PASS
R1_CORRECTIVE=PASS
R2=PASS
R3=PASS
R4_IMPLEMENTATION_HEAD=PASS
R5_INDEPENDENT_AUDIT=PASS
NORMAL_POLICY_TARGET2_30S=PRESERVED
WARNING_KEEP_LOADED=PRESERVED
CRITICAL_ORDER=AUTOMATIC_THEN_KEEP_LOADED
BEST_EFFORT_ATTRIBUTION=FORBIDDEN
PRIVATE_SPI_ADDED=NO
PRODUCT_DATA_MUTATION=NO
HUMAN_UI_ACCEPTANCE=PENDING_PROGRAM_FINAL
PR_191_MERGE_READY=YES
MERGE_AUTHORIZATION=USER_GRANTED
NEXT_ACTION=LITERAL_CONTROL_CLOSEOUT_HEAD_CI_THEN_SQUASH_MERGE
```
