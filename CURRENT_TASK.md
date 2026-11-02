# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001-PHASE8-DESIGN`  
**Title:** Adaptive Runtime Memory Budget + Background Efficiency — design freeze  
**Status:** `COMPLETE / DESIGN FROZEN / WAITING FOR IMPLEMENTATION AUTHORIZATION`  
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

That design work is now complete. This task does **not** authorize `FloatTabs/**` production construction. A new bounded implementation authorization is required before Phase 8 WP0/WP1 mutation begins.

## Frozen authority

Program contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V6.md`

Phase 8 implementation contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase8_Adaptive_Memory_Budget_Implementation_Contract_V1.md`

Historical Phase 7/V5 snapshot:

`docs/architecture/archive/FloatTabs_Runtime_Lifecycle_Phase7_Closeout_Snapshot_2026-11-02.md`

Navigation/status:

- `docs/README.md`
- `docs/architecture/README.md`
- `docs/architecture/DOMAIN_MAP.md`

## Current shipped vs target boundary

Current shipped `main@2b414982...` still implements Phase 7 fixed-count tuning until Phase 8 lands:

```text
normal Automatic target = 2
inactive release path = 30s
warning target = 1
critical target = 0
```

Frozen Phase 8 target:

```text
Memory Budget = Auto | Custom | Unlimited
no normal fixed Runtime-count ceiling
high watermark = 105%
low watermark = 90%
progressive one-at-a-time reclaim
fresh resource remeasurement after each reclaim
system memory pressure = independent ladder
proactive long-idle cleanup = OFF by default
```

Initial Auto reference formula:

```text
clamp(physical RAM × 20%, 1.5 GiB, 6 GiB)
```

This formula is frozen as the first implementation assumption, not claimed as measured optimum. WP6 must validate/tune through Real-Mac A/B evidence before program-final acceptance.

## Protection contract

Hard-protected Runtime:

- active / actually presented;
- fullscreen source;
- supplemental visible Web surface;
- Attention Generating;
- active/pending allowed-background-media protection;
- current materialization/restoring ownership.

Keep Loaded:

- excluded from normal budget reclaim;
- may make the soft budget temporarily unsatisfied;
- warning still prefers Automatic reclaim;
- critical may reclaim inactive/unprotected Keep Loaded after eligible Automatic Runtime.

## Background-generation contract

Generating remains hard-protected because arbitrary WKWebView JS/network work cannot be safely destroyed while generation must continue.

Phase 8 may optimize:

- event-first sensing;
- fallback watchdog cadence;
- redundant hidden health/diagnostic probes;
- response-identity work;
- obsolete observer/task cancellation;
- presentation-only hidden work.

It must not claim deep renderer-memory freeze without a supported public WebKit mechanism.

After generation completes:

```text
Ready/unread + native notification survives
→ generating protection ends
→ normal budget lifecycle resumes
```

The implementation contract sets an initial bounded 15s post-completion normal-budget recall grace; warning/critical may bypass it.

## Resource-measurement Gate

Phase 8 Gate 0 is mandatory before budget enforcement.

It must prove a production-safe aggregate measurement mechanism for:

```text
FloatTabs host + FloatTabs-attributable WebKit helpers
```

Rules:

- aggregate only; no exact per-Slot WebContent RSS claim;
- read-only resource monitor; no direct kill/reload/reclaim;
- explicit measurement-unavailable state;
- no substitution of Runtime count for GiB;
- no private WebKit SPI.

If Gate 0 cannot be proven, STOP and reconcile before WP2.

## Frozen work packages

```text
WP0 measurement feasibility + exact source audit
WP1 additive budget configuration + passive resource monitor
WP2 budget scheduler + progressive normal reclaim
WP3 system-pressure ladder + anti-thrash integration
WP4 Advanced → Runtime & Memory UI + persistence/backup
WP5 background-generation / observer efficiency corrective
WP6 Real-Mac + Phase7-vs-Phase8 identical-workload A/B acceptance
```

## Frozen acceptance principles

Phase 8 must prove at minimum:

1. 3+ Automatic Runtimes can remain resident beyond the old 30s window while under budget;
2. budget crossing reclaims one Runtime at a time;
3. each reclaim is followed by fresh measurement;
4. reclaim stops at/below low watermark or no-candidate boundary;
5. active/generating/fullscreen/media/restoring protections hold;
6. Keep Loaded behavior remains explicit/honest when it blocks convergence;
7. repeated switching does not cause reclaim/restore thrash;
8. reclaim/restore preserves Browser Profile login/session and exact Slot identity;
9. hidden completion still yields unread/native notification and later budget eligibility;
10. Phase 7 baseline vs Phase 8 candidate is compared under an identical workload for aggregate memory, helper count, CPU, hibernate/restore cycles, resident switch latency and restore latency;
11. required self-hosted Apple Silicon CI passes on literal merge head;
12. fresh ownership/exact-diff audit finds no second lifecycle writer/private WebKit workaround/destructive data coupling.

## Historical/document disposition

V5 and the Phase 7 implementation contract are preserved unchanged as delivered historical evidence. They no longer define the future target policy.

The old Phase 7 acceptance criterion that expected convergence to a fixed resident count is historical and must not be reused as Phase 8 success criteria.

## STOP conditions

STOP before implementation if work would require:

- deleting/resetting Browser Profile, cookies, session, website data, or user configuration;
- a second canonical lifecycle writer;
- private WebKit SPI;
- exact per-Slot memory attribution as required policy truth;
- a disguised fixed resident-count budget;
- normal reclaim of active/generating/fullscreen/protected-media/current-restoring Runtime;
- arbitrary reload/reset/restart as memory management;
- product mutation before a new implementation task is authorized.

## Current execution state

```text
BASELINE_MAIN=2b414982710b3f042fc7d6e9c88eb2d7117b4e38
PHASE7=MERGED
V6=ACCEPTED_FROZEN
PHASE8_CONTRACT=ACCEPTED_FROZEN
DESIGN_DELIVERABLES=COMPLETE
PRODUCT_MUTATION=NOT_AUTHORIZED
TARGET_NORMAL_POLICY=MEMORY_BUDGET_DRIVEN
FIXED_NORMAL_RESIDENT_COUNT=SUPERSEDED_TARGET
NEXT_GATE=DESIGN_DOCS_MERGE_THEN_STOP
NEXT_PRODUCT_WORK=REQUIRES_EXPLICIT_PHASE8_IMPLEMENTATION_AUTHORIZATION_STARTING_WITH_WP0
```
