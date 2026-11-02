# FloatTabs Current Status

**Status date:** `2026-11-02`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 8 GATE 0 CLOSED / D_COMBINE SELECTED / PRESSURE + EFFICIENCY RE-SCOPE AUTHORIZED / WAITING PR #190 CLOSEOUT MERGE**

Current task: `FT-RUNTIME-LIFECYCLE-MEMORY-001-PHASE8-PRESSURE-EFFICIENCY`.

The user selected `D_COMBINE` on 2026-11-02: execute the measurement-independent work now (`B`) and defer the aggregate-memory-budget track until a supported deterministic attribution capability exists (`A`). Best-effort/correlation attribution (`C`) is rejected.

## Repository / delivery state

```text
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
JSC_ROOT_CAUSE=UNKNOWN

PHASE_7_PR=#188_MERGED
PHASE_7_DELIVERY=COMPLETE
PROGRAM_CONTRACT=V6_ACCEPTED_FROZEN
ORIGINAL_PHASE8_BUDGET_CONTRACT=STOPPED_AT_GATE0
PHASE8_WP0=COMPLETE_2026-11-02
PHASE8_GATE0=FAIL_AGGREGATE_ATTRIBUTION_NOT_PROVABLE
USER_RECONCILIATION=D_COMBINE
BUDGET_TRACK=DEFERRED_PLATFORM_BLOCKED
BEST_EFFORT_ATTRIBUTION=FORBIDDEN
RESCOPE_CONTRACT=ACCEPTED_FROZEN
RESCOPE_SCOPE=PRESSURE_LADDER_PLUS_BACKGROUND_EFFICIENCY
PR_190=OPEN_DRAFT_CLOSEOUT_RECONCILIATION
PRODUCT_MUTATION_AFTER_RECONCILIATION=NOT_STARTED
NEXT_GATE=PR190_LITERAL_NEW_HEAD_CI_THEN_MERGE_THEN_R0_SOURCE_RECONCILIATION
```

Current re-scope contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase8_Pressure_Efficiency_Rescope_Contract_V1.md`

WP0 evidence report:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase8_WP0_Measurement_Feasibility_Report_V1.md`

## WP0 closeout

Gate 0 established:

- supported public APIs can read per-pid physical footprint and enumerate same-user WebKit helpers;
- the Networking helper can be deterministically attributed through FloatTabs' unique WebKit data-root fd paths;
- no supported public production API can deterministically attribute the dominant WebContent/GPU XPC instances to the FloatTabs host app;
- therefore an honest aggregate FloatTabs/WebKit working-set cannot drive the proposed GiB budget.

The previous PR #190 head `b775975968f7eecc46940ed69e1b2fab0e41cab3` passed macOS CI run `41380640917`. This reconciliation changes documentation/control on top of that head, so the **literal new PR head must pass fresh required CI before merge**.

No `FloatTabs/**` product file was changed by WP0 or this reconciliation.

## User decision — D_COMBINE

```text
B NOW
→ implement only measurement-independent lifecycle work:
   1. progressive system-memory-pressure ladder
   2. bounded background observer/task/generation efficiency

A LATER
→ keep aggregate memory-budget architecture deferred/platform-blocked
→ reopen only if a supported deterministic helper-attribution capability appears

C REJECTED
→ no best-effort transition correlation
→ no guessed per-tab MB
→ no Runtime-count substitution for aggregate memory
```

## Current production truth preserved during re-scope

Until a future budget implementation is separately proven feasible and authorized, healthy/normal conditions keep the merged Phase 7 policy:

```text
runtimeRetentionPreference = Automatic | Keep Loaded
normal Automatic resident target = 2
Automatic inactive release path = 30s
```

The re-scope does **not** retire that healthy-state normal policy.

The authorized lifecycle policy change is bounded to system memory pressure:

```text
warning
→ progressive one-at-a-time reclaim of eligible inactive Automatic
→ Keep Loaded preserved
→ current pressure/ownership revalidated between steps

critical
→ Automatic first
→ then inactive/unprotected Keep Loaded if still required
→ active/hard-protected untouched
→ one Runtime at a time

normal pressure restored
→ stop pending pressure progression
→ no mass restore; restore remains demand-driven
```

## Background-efficiency scope

The second authorized package may reduce verified host-side work involving hidden liveness/fallback probes, repeated detector evaluation, observer/task lifetime, stale callbacks and presentation-only work for detached Runtime.

Required invariants:

- live `Generating` remains Runtime-protected;
- completion/unread/native notification routing remains correct;
- current document/runtime ownership remains exact;
- hibernate/restore does not duplicate observers/tasks;
- Browser Profile, cookies, website session data and persisted Slot configuration remain untouched;
- efficiency claims are limited to the host-side work actually measured/tested.

## Source owner map carried forward from WP0

- `SlotLifecycleCoordinator` — sole lifecycle writer; current healthy/pressure count policy owner.
- `WebViewPool` — hibernate/release/resident-set mechanics and runtime ownership seams.
- `PanelController` constructs the lifecycle coordinator; it is not a second lifecycle writer.
- `ChatGPTAttentionBridge` / Attention runtime — bounded provider sensing and hidden liveness/fallback work.
- `RuntimeDiagnostics` — evidence only.

The successor implementation must begin with Gate R0 focused source reconciliation against **fresh main after PR #190 merge**. If this owner map materially changed, update Authority before product mutation.

## Deferred / blocked work

Blocked until a supported deterministic aggregate measurement capability exists:

- aggregate resource monitor as budget input;
- Auto/Custom/Unlimited memory-budget scheduler;
- memory-budget Advanced UI/persistence projection;
- aggregate-memory A/B claims requiring attributable FloatTabs/WebKit working-set evidence.

The V6 budget model remains a future architecture direction, not current shipped behavior.

## Safety boundary

Do not:

- implement budget enforcement from host+Networking-only measurement;
- use transition correlation, guessed per-tab memory or Runtime count as aggregate-memory substitutes;
- use private WebKit SPI, root-gated `launchctl`, EndpointSecurity entitlement paths or `task_for_pid` in production;
- change the healthy-state normal target=2 / 30s policy under the current re-scope;
- add a second lifecycle writer;
- hibernate an actively generating Runtime merely to save resources;
- clear, migrate or overwrite Browser Profile cookies/session/site data;
- claim WebContent memory reduction from host-side observer/timer reductions.

## Immediate next state

PR #190 is the WP0 + reconciliation closeout vehicle. After this documentation/control update:

1. wait for the literal new #190 head to pass required self-hosted macOS CI;
2. perform fresh PR identity/exact-diff/mergeability check;
3. merge #190 if those gates pass;
4. start the authorized pressure+efficiency implementation from fresh merged `main` on one bounded successor branch/PR;
5. run Gate R0 before any `FloatTabs/**` mutation.
