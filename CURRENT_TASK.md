# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001-PHASE8-PRESSURE-EFFICIENCY`  
**Title:** Phase 8 measurement-independent continuation — pressure ladder + background efficiency  
**Status:** `CLOSED / PR #191 MERGED / MACHINE + INDEPENDENT AUDIT COMPLETE`  
**Mode:** `CLOSEOUT / NO FURTHER PRODUCT MUTATION AUTHORIZED`  
**Task class:** `WEB RUNTIME / LIFECYCLE / PERFORMANCE`  
**Execution baseline:** `main@065d2923f0516694689ee71f2787b76c8719bfe8 after merged PR #190`  
**Merged result:** `main@5bd54ef63266dafff8f1a36f4b883367f2158516 via PR #191`

## Authorization and disposition

The user selected `D_COMBINE` on 2026-11-02 and authorized the measurement-independent continuation only:

1. progressive system-memory-pressure reclaim in the existing lifecycle owner;
2. bounded host-side background observer/task/generation efficiency corrections.

The aggregate-memory-budget track remains deferred/platform-blocked by Phase 8 Gate 0.

The task was implemented, independently audited, corrected once for sustained-pressure eligibility re-entry, re-audited, passed the literal-head repository gates, and was squash-merged as PR #191. This task is now closed.

## Frozen authority

- Project rules: `AGENTS.md`
- Program design: `docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V6.md`
- Original Phase 8 budget contract: `docs/architecture/FloatTabs_Runtime_Lifecycle_Phase8_Adaptive_Memory_Budget_Implementation_Contract_V1.md` — stopped at Gate 0 for budget construction
- Gate 0 evidence: `docs/architecture/FloatTabs_Runtime_Lifecycle_Phase8_WP0_Measurement_Feasibility_Report_V1.md`
- Implemented re-scope contract: `docs/architecture/FloatTabs_Runtime_Lifecycle_Phase8_Pressure_Efficiency_Rescope_Contract_V1.md`
- Navigation: `docs/architecture/DOMAIN_MAP.md`, `docs/README.md`

## Delivered scope

### R1 — progressive system-memory-pressure ladder

Merged behavior:

- warning reclaims only eligible inactive/unprotected `Automatic` Runtime;
- warning preserves `Keep Loaded`;
- critical reclaims eligible Automatic first, then inactive/unprotected Keep Loaded;
- active/presented, fullscreen, supplemental-visible, generating, protected background-media and other hard-protected Runtime remain protected;
- at most one reclaim continuation is pending;
- every continuation re-evaluates latest pressure and current Runtime/protection facts;
- pressure returning to normal cancels not-yet-started progression and does not mass-restore;
- healthy-state Automatic target=2 and 30s inactive release remain unchanged.

### R1 corrective

Independent audit identified one blocking sustained-pressure defect: after progression stopped at `no_candidate`, later eligibility changes did not re-enter the pressure ladder unless another same-level pressure event arrived.

Merged corrective:

```text
reconcileProgressivePressureIfNeeded()
  guard latestMemoryPressureLevel != nil
  guard pressureReclaimWorkItem == nil
  → beginProgressivePressureReclaim(latest level)
```

Eligibility re-entry is driven from the inactive-plan creation choke point and media-protection-ended boundary. No polling, second scheduler or second lifecycle writer was added.

Focused regressions prove:

- sustained warning + generation protection ends without new warning event;
- sustained critical + Keep Loaded protection ends without new critical event;
- warning → critical immediate takeover and Automatic-before-Keep-Loaded ordering;
- normal clears stale pressure state before later eligibility changes;
- repeated eligibility boundaries produce one reclaim chain.

The pressure diagnostics field is `normal_managed_resident_target`, not an implied warning/critical budget target.

### R2 — background lifecycle efficiency

Merged bounded fallback behavior:

```text
hidden generation <30s    → 2s watchdog interval
hidden generation 30–120s → 5s watchdog interval
hidden generation >=120s  → 10s watchdog interval
```

Event-driven completion remains primary. No provider-semantic redesign, WebContent-memory claim, generation-protection change or session/data mutation was introduced.

## Deferred / out of scope

Not delivered and not authorized under this closed task:

- aggregate FloatTabs/WebKit memory monitor as lifecycle input;
- Auto/Custom/Unlimited memory budget;
- budget watermarks;
- memory-budget Settings UI or persistence/backup schema;
- aggregate-memory A/B acceptance claims;
- best-effort WebContent/GPU process attribution;
- healthy-state target=2 / 30s redesign;
- private WebKit SPI, root-only helpers or restricted-entitlement attribution;
- Browser Profile/session/site-data reset or migration.

## Final gates

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
GATE_R4_SELF_HOSTED_CI_LITERAL_HEAD=PASS_RUN_41389550011
QA_DMG_LITERAL_HEAD=PASS_RUN_41389550006
GATE_R5_INDEPENDENT_EXACT_DIFF_OWNERSHIP_AUDIT=PASS
BLOCKING_FINDINGS=0
IMPORTANT_FINDINGS=0
PR_191=MERGED
PR_191_HEAD=1C86E62B
PR_191_SQUASH_MERGE=5BD54EF6
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

## Human acceptance / next program gate

`HUMAN_UI_ACCEPTANCE=PENDING_PROGRAM_FINAL`.

The accepted re-scope contract places human runtime/UI acceptance at the broader lifecycle program-final boundary. The next program action is human validation of the merged result; that validation is not part of this closed construction task.

## Final execution state

```text
USER_DECISION=D_COMBINE
BUDGET_TRACK=DEFERRED_PLATFORM_BLOCKED
DELIVERED_SCOPE=PRESSURE_LADDER_PLUS_BACKGROUND_EFFICIENCY
R0=PASS
R1=PASS
R1_CORRECTIVE=PASS
R2=PASS
R3=PASS
R4=PASS
R5=PASS
NORMAL_POLICY_TARGET2_30S=PRESERVED
WARNING_KEEP_LOADED=PRESERVED
CRITICAL_ORDER=AUTOMATIC_THEN_KEEP_LOADED
BEST_EFFORT_ATTRIBUTION=FORBIDDEN
PRIVATE_SPI_ADDED=NO
PRODUCT_DATA_MUTATION=NO
PR_191=MERGED_AT_MAIN_5BD54EF6
TASK_STATE=CLOSED
HUMAN_UI_ACCEPTANCE=PENDING_PROGRAM_FINAL
NEXT_ACTION=PROGRAM_FINAL_HUMAN_RUNTIME_UI_ACCEPTANCE
```
