# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001-PHASE8-IMPLEMENT`  
**Title:** Adaptive Memory Budget — Phase 8 implementation (WP0 Gate 0 STOP)  
**Status:** `ACTIVE / STOPPED AT GATE 0 / WAITING USER RECONCILIATION`  
**Mode:** `WP0 MEASUREMENT FEASIBILITY + EXACT SOURCE AUDIT (EXECUTED READ-ONLY)`  
**Task class:** `WEB RUNTIME / LIFECYCLE / MEMORY / PERFORMANCE`  
**Baseline:** `main@8372d12271946ff3a85b43a5fcc7e78fc1407e0c`

## Authorization state

The user explicitly authorized `PHASE 8 IMPLEMENTATION` on 2026-11-02, with the binding constraints:

1. start strictly at `WP0 — Production-safe aggregate memory measurement feasibility + exact source audit`;
2. do not jump to mutating `SlotLifecycleCoordinator` reclaim policy;
3. if Gate 0 fails: do not guess, do not fall back to Runtime count, stop production construction, and report exactly which production-grade measurement capability is missing.

WP0 executed read-only (source audit + live-machine probes in `/tmp/wkprobe/`, outside the repo). **Gate 0 verdict: FAIL.** Production construction is stopped before WP2 per Phase 8 contract §6.

## Frozen authority

- Program contract: `docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V6.md`
- Phase 8 implementation contract: `docs/architecture/FloatTabs_Runtime_Lifecycle_Phase8_Adaptive_Memory_Budget_Implementation_Contract_V1.md`
- WP0 evidence report: `docs/architecture/FloatTabs_Runtime_Lifecycle_Phase8_WP0_Measurement_Feasibility_Report_V1.md`
- Navigation: `docs/architecture/DOMAIN_MAP.md`, `docs/README.md`

## WP0 outcome

Proven available (public, production-safe, empirically validated):

- `proc_pid_rusage` footprint for host and same-user WebKit helpers;
- `proc_listallpids` + `proc_pidpath` helper enumeration;
- deterministic **Networking** attribution via fd paths under FloatTabs' unique per-app WebKit root;
- `NSProcessInfo.physicalMemory`; existing memory-pressure dispatch source.

Missing production capability (Gate 0 blocker):

> A supported public API that reveals which WebKit WebContent/GPU XPC instances belong to this host app. ppid/pgid lineage, SDK responsible-pid flavors, public WebContent pid, `launchctl procinfo` (root-gated on current macOS), EndpointSecurity (entitlement-gated), `task_for_pid` (SIP), and WebContent fd attribution (structurally zero app fds) are all ruled out — most empirically.

Because WebContent is the dominant memory consumer, no honest aggregate budget input exists. Therefore WP1 (monitor), WP2 (budget scheduler), WP4 (budget UI) and WP6 A/B memory claims are blocked. No `FloatTabs/**` file was modified.

## Awaiting user decision (reconciliation options)

```text
A HOLD      keep Phase 7 merged policy; revisit when Apple ships public attribution API
B RE-SCOPE  new accepted contract for measurement-independent packages only:
            WP3 pressure ladder, WP5 background-generation/observer efficiency,
            optional normal policy = system-pressure-only (retire fixed count 2)
C AMEND     accept best-effort transition-correlation attribution with explicit
            unavailable states (violates current determinism bar; executor
            recommends against)
D COMBINE   e.g. B now + A later
```

No production mutation may proceed under this task until one option is explicitly chosen and, for B/C/D, the scope is re-frozen in repository authority.

## STOP conditions triggered (from V6 §20 / Phase 8 contract §12)

- Gate 0 cannot prove production-safe aggregate footprint measurement.

## Authorized paths (already exercised, read-only + control)

- `CURRENT_STATUS.md`, `CURRENT_TASK.md`
- `docs/architecture/FloatTabs_Runtime_Lifecycle_Phase8_WP0_Measurement_Feasibility_Report_V1.md`
- `docs/README.md`, `docs/architecture/README.md` routing lines for the WP0 report

## Current execution state

```text
BASELINE_MAIN=8372d12271946ff3a85b43a5fcc7e78fc1407e0c
PHASE8_CONTRACT=ACCEPTED_FROZEN
WP0=EXECUTED
GATE0=FAIL_AGGREGATE_ATTRIBUTION_NOT_PROVABLE
BUDGET_CONSTRUCTION=STOPPED_BEFORE_WP2
FLOATTABS_PRODUCT_MUTATION=NONE
CURRENT_STAGE=WAITING_USER_RECONCILIATION_DECISION
AUTHORIZED_MUTATION=CONTROL_DOCS_ONLY
NEXT_GATE=USER_RECONCILIATION_DECISION
```
