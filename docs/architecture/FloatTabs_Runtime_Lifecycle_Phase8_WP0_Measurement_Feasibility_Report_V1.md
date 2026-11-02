# FloatTabs Phase 8 — WP0 Measurement Feasibility + Source Audit Report V1

**Program:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Task:** `FT-RUNTIME-LIFECYCLE-MEMORY-001-PHASE8-IMPLEMENT`  
**Status:** `WP0 EXECUTED / GATE 0 VERDICT: FAIL — AGGREGATE ATTRIBUTION NOT PROVABLE / PRODUCTION CONSTRUCTION STOPPED`  
**Date:** `2026-11-02`  
**Execution baseline:** `main@8372d12271946ff3a85b43a5fcc7e78fc1407e0c`  
**Governing contracts:** V6 (`FloatTabs_Runtime_Lifecycle_Memory_Contract_V6.md`) §6, Phase 8 contract §6 (Gate 0), §7 (WP0)  
**Evidence machine:** user's development Mac, `Darwin 25.6` (macOS current at execution time), Apple Silicon, live `WKWebView` probe hosts under `/tmp/wkprobe/` (outside the repository)

This report records the WP0 read-only feasibility investigation and exact source audit. No `FloatTabs/**` production file was modified.

## 1. Gate 0 verdict

**FAIL — STOP.**

A production-safe aggregate FloatTabs/WebKit footprint measurement cannot be proven on current macOS:

- **Footprint reading per process IS available and validated** with public APIs (`proc_pid_rusage`, `ri_phys_footprint`) for the host and for same-user WebKit helper processes.
- **Attribution of the dominant memory consumer is NOT available**: there is no supported, non-private, in-app way to determine which `com.apple.WebKit.WebContent` (or GPU) XPC instances belong to the FloatTabs host.
- Without WebContent attribution, any "aggregate budget" input either (a) silently omits the dominant memory consumer, (b) guesses by Runtime count, or (c) uses nondeterministic heuristics — all explicitly forbidden by V6 §6/§20 and Phase 8 contract §6/§12.

Per Phase 8 contract §6 (Gate 0 STOP), budget enforcement construction is stopped before WP2 behavior mutation. Per the user's Phase 8 implementation authorization (2026-11-02), the executor must not guess, must not fall back to Runtime count, and must report the missing capability. This report is that report.

## 2. What was proven AVAILABLE (public, production-safe)

All items below were validated empirically on the evidence machine with small C/Swift probes, not inferred from documentation alone.

| Capability | Public API | Evidence |
| --- | --- | --- |
| Own-host physical footprint | `proc_pid_rusage(getpid(), RUSAGE_INFO_CURRENT)` → `ri_phys_footprint` | probe `probe.c`: host footprint read OK |
| Foreign same-uid helper footprint | `proc_pid_rusage` on WebContent/Networking/GPU pids of other same-user apps | `rusage=OK` for all helper pids, values plausible (9–47 MiB) |
| System-wide process enumeration | `proc_listallpids` / `proc_pidpath` | classified all `com.apple.WebKit.{WebContent,Networking,GPU}` instances system-wide |
| Helper fd paths (foreign, same-uid) | `proc_pidinfo(pid, PROC_PIDLISTFDS, …)` + `proc_pidfdinfo(pid, fd, PROC_PIDFDVNODEPATHINFO, …)` | full store-DB fd paths of a foreign Networking process readable |
| **Networking attribution** | same fd APIs; `WKWebsiteDataStore(forIdentifier:)` (macOS 14+) or default store under the app's own WebKit root | probe Networking process held open fds under `~/Library/WebKit/<app-root>/WebsiteDataStore/<uuid>/…` (LocalStorage/IDB/ResourceLoadStatistics DBs), persistently open |
| Per-app WebKit root uniqueness | on-disk layout | `~/Library/WebKit/` contains one root per app bundle id, including `com.lost0rz.FloatTabs`; bundle ids are unique, so store-path fd matching deterministically identifies the FloatTabs-attributable Networking process |
| Physical memory (Auto budget input) | `NSProcessInfo.physicalMemory` / `sysctl hw.memsize` | standard; only the budget *input* needs it |
| System memory pressure | existing `DispatchSource.makeMemoryPressureSource` in production | already shipped |

**The FloatTabs-attributable subset that CAN be measured today:** host + Networking helper (fd-attributed). GPU and WebContent cannot.

## 3. What was proven UNAVAILABLE (the missing capability)

The missing production capability, stated precisely:

> A supported public API that reveals which WebKit XPC helper processes (WebContent, GPU) belong to this host application — the equivalent of launchd "responsible pid" or the WebContent process identifier — for an ordinary, non-entitled, non-root production app on current macOS.

Every candidate path was ruled out, most empirically:

| Mechanism | Result | Evidence |
| --- | --- | --- |
| ppid lineage | dead — all WebKit helpers are launchd XPC children (`ppid = 1`) | probe host spawned GPU/Networking/WebContent, all `ppid=1` |
| pgid lineage | dead — each helper has its own pgid; host has its own | `ps -o pgid` on probe helpers |
| `proc_info` responsible flavor | does not exist — SDK `sys/proc_info.h` + `libproc.h` contain no responsible-pid concept | full-header grep, zero hits |
| Public WebContent pid from WebKit | does not exist — no `processIdentifier` symbol anywhere in public WebKit headers | SDK WebKit framework Headers grep, zero hits; only private SPI `_webProcessIdentifier` exists (forbidden by V6 §3.10) |
| `launchctl procinfo` (benchmark's mechanism) | root-gated on Darwin 25.6 (`This subcommand requires root privileges`); benchmark wraps it in `sudo -n` | live `launchctl procinfo <pid>` test; `tools/benchmark/floattabs_benchmark.py` `OwnershipResolver` uses `sudo -n /bin/launchctl procinfo` |
| `launchctl print` user domain | shows registered agents only; XPC service instances not enumerable as user | `launchctl print gui/<uid>/` test |
| WebContent fd attribution | structurally impossible — WebContent holds zero fds beyond stdio (`/dev/null` ×3) even for pages that use LocalStorage + IndexedDB + CacheStorage; all persistent storage lives in the Networking process in modern WebKit | `probe5` on storage-heavy probe's WebContent: 3 fd entries, no app paths; same for another app's WebContent |
| EndpointSecurity responsible tokens | restricted entitlement (`com.apple.developer.endpoint-security.client`), not viable for direct distribution | known platform constraint; not testable without entitlement |
| `task_for_pid` on Apple-signed helpers | blocked (SIP/hardened runtime) for non-root | known platform constraint |
| `sysctl KERN_PROCARGS2` env discrimination | not accessible / not discriminative for XPC instances | live sysctl test |
| Spawn/teardown correlation heuristics | nondeterministic (races with other apps' WebViews; shared WebContent processes across same-site runtimes); violates V6 §6.2 "safely and deterministically attributed" and the user's "do not guess" instruction | analysis; deliberately NOT adopted |

## 4. Why partial measurement cannot support the budget product

- WebContent processes are the dominant memory consumers (ChatGPT-class slots run far beyond the observed 45.5 MiB idle WebContent baseline; Networking ≈ 5–10 MiB; GPU ≈ 6–10 MiB).
- A budget input of `host + Networking` would systematically ignore nearly all reclaimable Web memory and would drive reclaim decisions on a signal that barely moves when runtimes hibernate — the opposite of the V6 objective.
- Guessing WebContent by Runtime count is exactly the "disguised fixed-count budget" the contracts forbid.
- Making attributionAvailable permanently `false` in practice (Safari or any other WebKit app running) reduces the entire budget feature to dead UI.

## 5. Exact source audit (baseline `main@8372d122`)

Frozen owner map confirmed for later resumption; no mutation performed:

- **`FloatTabs/Web/SlotLifecycleCoordinator.swift`** — sole lifecycle writer; `RuntimeBudgetPolicy.defaultManagedResidentTarget = 2` (line 12), warning target 1 (via `RuntimeBudgetPolicy.warningManagedResidentTarget`), critical target 0 (`budgetDecision` line 747), `defaultAutomaticReleaseDelay = 30`/`defaultColdReleaseDelay = 30` (lines 78–80), `enforceRuntimeBudget(reason:)`, `handleMemoryPressure` (line 409) fed by `DispatchSource.makeMemoryPressureSource` (lines 490–502). WP2/WP3 primary owner as contracted.
- **`FloatTabs/Web/WebViewPool.swift`** — mechanism owner; `hibernate(slotID:)` (line 553), `release(slotID:)` (line 567), `onResidentSetChange` callback (lines 119/865/1110/1274), `interactionState` provider/applier seams (lines 188–192, Phase 6 restore).
- **`FloatTabs/Panel/PanelController.swift`** — constructs `SlotLifecycleCoordinator` at line 222 (audit note: the Phase 8 contract's WP0 list said "AppCoordinator lifecycle wiring"; the literal construction owner today is `PanelController`; `AppCoordinator` wires `WebViewPool` at lines 115–136). Any future WP must freeze wiring against this actual owner map.
- **`FloatTabs/Persistence/AppPreferencesStore.swift`** — legacy retention keys `FloatTabs.performance.warmWebViewRetentionDelay` / `coldWebViewReleaseDelay` (lines 204–207), Warm/Cold enums (94–118), `NotificationCenter` posts on change; no memory-budget concept yet; additive key pattern established.
- **`FloatTabs/UI/SettingsInformationArchitecture.swift`** — `GlobalSettingsPage.advanced` sections = `[.runtimeDiagnostics, .backupRestore, .about]` (line 64); a WP4 `Runtime & Memory` section would be added to this enum/composition.
- **`FloatTabs/Persistence/FloatTabsBackupService.swift`** — export/restore of Slots + global settings with schema/rollback handling; global preference backup scope exists (WP4-conditional path valid).
- **`tools/benchmark/floattabs_benchmark.py`** — external attribution only: `OwnershipResolver` runs `sudo -n /bin/launchctl procinfo <pid>` per WebKit helper and parses `responsible pid`; requires sudo elevation; root-gated on current macOS without it.
- **Production `FloatTabs/**`** — contains NO aggregate footprint measurement today; only the memory-pressure dispatch source.
- **Data-store ownership** — `FloatTabs/Web/BrowserProfileDataStoreProvider.swift`: Default profile → `WKWebsiteDataStore.default()`; custom profiles → `WKWebsiteDataStore(forIdentifier:)` (macOS 14+). Both persist under FloatTabs' unique per-app WebKit root, which is what makes Networking attribution possible (Section 2).

## 6. Consequence for the frozen WP sequence

Blocked until reconciliation (require aggregate measurement):

- WP1 resource-monitor component (monitor without aggregate input is dead weight);
- WP2 budget scheduler / progressive normal reclaim;
- WP4 budget UI (Auto/Custom/Unlimited would not honestly enforce);
- WP6 A/B aggregate-memory claims.

Not measurement-dependent (candidates for re-scope, require a new accepted contract, not silently absorbed here):

- WP3 system-pressure ladder (progressive warning/critical reclaim driven by the existing dispatch source; replaces `warning=1 / critical=0`);
- WP5 background-generation / observer / task efficiency corrective;
- retiring the normal fixed-count `2` target in favor of a system-pressure-only normal policy (the "Unlimited"-equivalent semantics) — a material policy change that only the user can authorize.

## 7. Reconciliation options (user decision required)

- **A — Hold.** Stop Phase 8 budget implementation; keep merged Phase 7 policy; revisit when Apple ships a public app↔WebKit-helper attribution API. Zero product construction now.
- **B — Re-scope.** Authorize a new bounded contract implementing only the measurement-independent packages (pressure ladder + background efficiency, and optionally normal = pressure-only). Budget feature deferred.
- **C — Amend.** Explicitly amend the contracts to accept best-effort transition-correlation attribution with honest `attributionAvailable=false` states. This contradicts the current determinism bar and the executor recommends against it; recorded only because it is the user's product decision.
- **D — Combine.** e.g. B now, A on top when the API appears.

## 8. Disposition

- No `FloatTabs/**` file changed. Probes lived in `/tmp/wkprobe/` (scratch, outside repo).
- Control files (`CURRENT_STATUS.md`, `CURRENT_TASK.md`) and doc routing updated to reflect WP0 outcome on the implementation branch.
- Phase 8 budget construction is **STOPPED** at Gate 0. Next gate is the user's reconciliation decision, not an implementation step.
