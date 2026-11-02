# FloatTabs Current Status

**Status date:** `2026-11-02`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 8 IMPLEMENTATION / WP0 EXECUTED / GATE 0 FAIL / BUDGET CONSTRUCTION STOPPED / WAITING USER RECONCILIATION**

Current task: `FT-RUNTIME-LIFECYCLE-MEMORY-001-PHASE8-IMPLEMENT`.

The user explicitly authorized Phase 8 implementation (2026-11-02) starting strictly at WP0 (measurement feasibility + exact source audit). WP0 was executed read-only. The measurement feasibility Gate (Gate 0) **failed**: aggregate FloatTabs/WebKit footprint attribution for the dominant WebContent processes cannot be built from supported public APIs. Production budget construction is stopped before WP2 per the frozen Phase 8 contract §6.

## Repository / delivery state

```text
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
JSC_ROOT_CAUSE=UNKNOWN

PHASE_7_PR=#188_MERGED
PHASE_7_DELIVERY=COMPLETE
PROGRAM_CONTRACT=V6_ACCEPTED_FROZEN
PHASE8_CONTRACT=ACCEPTED_FROZEN
PHASE8_WP0=EXECUTED_2026-11-02
PHASE8_GATE0=FAIL_AGGREGATE_ATTRIBUTION_NOT_PROVABLE
PHASE8_BUDGET_CONSTRUCTION=STOPPED_BEFORE_WP2
PRODUCT_MUTATION=NONE_IN_WP0
NEXT_GATE=USER_RECONCILIATION_DECISION
```

WP0 evidence report (authoritative detail):

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase8_WP0_Measurement_Feasibility_Report_V1.md`

## WP0 verdict summary

Available and validated (public APIs, live-machine evidence):

- per-pid footprint via `proc_pid_rusage` (`ri_phys_footprint`) for host and same-user WebKit helpers;
- system-wide helper enumeration via `proc_listallpids` + `proc_pidpath`;
- **deterministic Networking-helper attribution** via helper fd paths under FloatTabs' unique per-app WebKit root (`~/Library/WebKit/com.lost0rz.FloatTabs/...`);
- physical memory and existing system memory-pressure dispatch source.

Missing production capability (the Gate 0 blocker):

- no supported public way to attribute `com.apple.WebKit.WebContent` (or GPU) XPC instances to the host app. ppid/pgid lineage dead (helpers are launchd children in own groups), no responsible-pid API in SDK, no public WebContent pid in WebKit headers (only private SPI), `launchctl procinfo` root-gated on current macOS (benchmark uses `sudo`), WebContent holds zero app-path fds even for storage-heavy pages.

Because WebContent is the dominant memory consumer, partial aggregate (host + Networking only) cannot honestly drive the budget product. Per contract and user instruction: no guessing, no Runtime-count substitution, STOP.

## Current production truth (unchanged)

Merged `main` still runs the Phase 7 policy until a reconciled Phase 8 lands:

```text
runtimeRetentionPreference = Automatic | Keep Loaded
normal Automatic resident target = 2
Automatic inactive release path = 30s
warning Automatic target = 1
critical Automatic target = 0
```

All Phase 1-7 structural foundations remain accepted and untouched (see V6 §1). WP0 mutated no `FloatTabs/**` file.

## Source audit owner map (frozen at WP0, baseline main@8372d122)

- `SlotLifecycleCoordinator` — sole lifecycle writer; count targets 2/1/0 at lines 12/81, 30s graces lines 78-80, pressure handling lines 409/490-502.
- `WebViewPool` — `hibernate` line 553, `release` line 567, `onResidentSetChange` lines 119/865/1110/1274, Phase 6 `interactionState` seams 188-192.
- `PanelController.swift:222` constructs the lifecycle coordinator (AppCoordinator wires `WebViewPool` 115-136) — the literal wiring owner differs from the contract's WP0 wording; any future WP must freeze against this map.
- `AppPreferencesStore` — legacy Warm/Cold keys lines 204-207 + NotificationCenter routes; additive-key pattern established; no budget concept yet.
- Settings Advanced sections today: `[.runtimeDiagnostics, .backupRestore, .about]`.
- Benchmark attribution is external-only: `sudo -n launchctl procinfo` responsible-pid parsing in `tools/benchmark/floattabs_benchmark.py`.
- Production has no aggregate footprint measurement today.

## Blocked vs unblocked Phase 8 packages

Blocked (need aggregate measurement): WP1 monitor, WP2 budget scheduler, WP4 budget UI, WP6 A/B memory claims.

Measurement-independent candidates for a possible re-scope (require a new accepted contract, not authorized here): WP3 system-pressure ladder, WP5 background-generation/observer efficiency, optional retirement of the normal fixed-count `2` target in favor of a pressure-only normal policy.

## Reconciliation options awaiting user decision

```text
A HOLD      keep Phase 7 policy; revisit when Apple ships a public attribution API
B RE-SCOPE  new contract for pressure ladder + background efficiency only; budget deferred
C AMEND     accept best-effort transition-correlation attribution (executor recommends against)
D COMBINE   e.g. B now + A later
```

## Safety boundary

Do not:

- implement budget enforcement on host+Networking-only measurement or Runtime-count heuristics;
- use private WebKit SPI (`_webProcessIdentifier`) or root-gated `launchctl` in production;
- mutate production lifecycle/runtime code while the task is STOPPED at Gate 0;
- clear, migrate or overwrite Browser Profile cookies/session/site data;
- treat the WP0 probes (`/tmp/wkprobe/`, outside the repo) as product evidence of anything beyond the reported matrix.
