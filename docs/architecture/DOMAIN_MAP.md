# FloatTabs Domain Map

This file is a **derived navigation map**. It does not replace `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`, accepted current contracts, production source or tests.

## Authority order

1. `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`;
2. `docs/README.md`;
3. current lifecycle authority: `FloatTabs_Runtime_Lifecycle_Memory_Contract_V5.md` plus the active Phase 6/Phase 7 implementation contracts;
4. `docs/architecture/README.md`;
5. this map for navigation;
6. production source/tests/fresh evidence;
7. historical Stage/archive material as evidence only.

## Domain routes

| Domain | Owns | Primary source / entry points | Key boundaries |
| --- | --- | --- | --- |
| App Composition | dependency wiring, launch/termination, top-level services | `FloatTabs/App/AppCoordinator.swift`, `AppDelegate.swift`, `FloatTabsApp.swift` | coordinates domains; does not own Tab/Web/Attention truth |
| Tabs & Profiles | Slot identity, selection, ordering, Web App / Browser Profile config, persisted `lastUsedAt`, Runtime retention preference | `FloatTabs/Tabs/TabStore.swift`, `WebAppProfile.swift`, `BrowserProfile.swift`, `WebRenderingProfile.swift` | durable product/config state; Runtime lifecycle remains Web-owned |
| Web Runtime | `WKWebView` creation/reuse, Runtime identity, hibernate/restore/release, renderer recovery, bridge lifetime | `FloatTabs/Web/WebViewPool.swift`, `SlotNavigationObserver.swift`, `BrowserProfileDataStoreProvider.swift` | mechanism owner; does not own lifecycle policy or durable product state |
| Runtime Lifecycle | inactivity/grace execution, protection boundaries, memory pressure and automatic-budget execution | `FloatTabs/Web/SlotLifecycleCoordinator.swift` | sole canonical Runtime lifecycle writer |
| Runtime Budget Policy | deterministic read-only residency decision | policy/value logic in `SlotLifecycleCoordinator.swift` until refactored | no WebKit/persistence side effects |
| Attention / Generation Sensing | ChatGPT generation sensing, native Attention state, liveness fallback | `ChatGPTAttentionBridge.swift`, `WebAttentionCoordinator.swift` | Generating protects Runtime; Ready/unread does not own Runtime |
| Response / Unread | response identity/extraction and durable unread handoff | `ChatGPTResponseBridge.swift`, `ChatGPTResponseExtraction.swift`, `ChatGPTUnreadResponseCoordinator.swift`, `UnreadResponseStore.swift` | durable unread survives Runtime reclamation |
| Native Notification Projection | completion alert delivery and exact-Slot response routing | `FloatTabs/App/ChatGPTCompletionNotificationCoordinator.swift` | projection only; never owns Runtime/Profile state |
| Window / Panel / Fullscreen | shell visibility, synchronization, fullscreen hosting, exact-Slot presentation | `FloatTabs/Panel/PanelController.swift`, `FloatingPanel.swift`, `FullscreenSourceHost.swift`, `ScreenPositioning.swift` | presentation truth only; no Runtime policy ownership |
| Focus / Input / Commands | native/Web focus, shortcuts, commands, click/drag routing | `FloatTabs/Web/WebFocusRouter.swift`, `FloatTabs/Hotkeys/AppCommandController.swift`, `GlobalHotkeyController.swift` | native focus and DOM focus remain distinct; no Runtime ownership |
| Persistence & Recovery | durable Slot/Profile state, preferences, backups, recovery data | `ProfileRepository.swift`, `AppPreferencesStore.swift`, `FloatTabsBackupService.swift` | migration/compatibility must not destroy user data |
| Diagnostics | diagnostic events, incidents, privacy filtering, snapshots, long-term observation | `RuntimeDiagnostics.swift`, `RuntimeDiagnosticWriter.swift`, `RuntimeDiagnosticEvent.swift`, `LongTermPerformanceObservationCoordinator.swift` | evidence only; never product/lifecycle truth |
| Website Cache / Storage | re-downloadable website-cache measurement/cleanup | `FloatTabs/Storage/WebsiteCacheCleanupCoordinator.swift`, `WebsiteCacheCleanupService.swift`, `WebsiteCachePolicy.swift` | cache cleanup is not Runtime cleanup; Phase 7 retires legacy Cold coupling |
| Menu / Status Projection | menu-bar/status projection and entry actions | `FloatTabs/MenuBar/StatusItemController.swift` | projection only |
| Tab Rail / Current Runtime Controls | Tab menu, Automatic/Keep Loaded control projection, Browser Profile/media controls | `FloatTabs/UI/ExternalTabRail.swift` | UI projects Tab configuration; does not decide lifecycle |
| Global Settings | application settings and Browser/Performance presentation | `FloatTabs/UI/GlobalSettingsController.swift`, `SettingsInformationArchitecture.swift` | Phase 7 removes active Warm/Cold timing controls |

## Current production lifecycle truth before Phase 7 lands

Current source still implements the legacy Phase 4 hybrid model:

```text
Hot       -> explicit automatic-eviction exclusion + hidden attached Hot host
Warm/Cold -> managed budget + separate timers
normal managed target -> 3
```

This is **current production truth**, but it is no longer the accepted final product target.

## Accepted Phase 7 target

```text
Slot persistent configuration
→ runtimeRetentionPreference = Automatic | Keep Loaded
→ WebViewPool owns live Runtime cache
→ SlotLifecycleCoordinator gathers protection/recency facts
→ deterministic automatic policy
→ existing hibernate boundary releases eligible Runtime
→ Phase 6 restores reclaimed Runtime on demand
```

Initial target policy:

```text
Automatic default
normal target 2
inactive grace 30s
warning target 1
critical target 0
```

Keep Loaded:

- does not preload at launch;
- does not require hidden attached presentation;
- resists ordinary reclaim;
- may be reclaimed under critical pressure when inactive and otherwise unprotected.

Hard protections:

```text
active / actually presented
fullscreen source
supplemental visible Web surface
Attention Generating
active/pending allowed-background-media protection
current Phase 6 materialization/restoring ownership boundary
```

These do not protect Runtime:

```text
Attention Ready
durable unread
native completion notification
mere presence of a restore snapshot
```

## Persistence compatibility route for Phase 7

Primary files:

- `FloatTabs/Tabs/WebAppProfile.swift` — canonical Automatic/Keep Loaded + legacy decode/encode projection;
- `FloatTabs/Tabs/TabStore.swift` — configuration mutation/copy/default behavior;
- `FloatTabs/Persistence/ProfileRepository.swift` / `FloatTabsBackupService.swift` — touch only if additive compatibility requires it.

Mapping:

```text
legacy hot       -> Keep Loaded
legacy warm/cold -> Automatic
```

Browser Profile/session data is outside this migration.

## Verification routes

Relevant tests include:

- `TabStoreTests.swift` — Slot defaults/copy/config mutation;
- `ProfileRepositoryTests.swift` / `FloatTabsBackupServiceTests.swift` — compatibility/data safety;
- `WebAttentionLifecycleTests.swift` — protection/reclaim ordering;
- `WebViewPoolTests.swift` — Runtime identity/hibernate/restore/renderer recovery;
- `ExternalShellTests.swift` — Phase 6 restore/presentation integration;
- `SettingsInformationArchitectureTests.swift` — current Settings controls;
- `WebsiteCacheCleanupTests.swift` — cache boundary.

Required repository host gate remains `Build & Test (Apple Silicon arm64)` on `macmini-floattabs-01`.

## Incident routing

For runtime failures, classify the boundary before changing code:

```text
Slot/config
vs automatic lifecycle decision
vs lifecycle execution
vs WebView runtime/navigation
vs Phase 6 materialization/readiness
vs Attention sensing
vs Response/Unread
vs Window/Fullscreen
vs Focus/Input
vs Persistence/migration
vs Website Cache
vs Native Notification
```

Correlate fresh evidence by Slot/session/runtime/navigation generation and time where available. Reload/reset/restart prove only a recovery boundary; preserve root cause `UNKNOWN` when evidence cannot prove causation.

## Structural notes

- `SlotLifecycleCoordinator` remains the only release/hibernate decision executor.
- current private `RuntimeBudgetPolicy` is reusable decision machinery, but its Hot/Warm/Cold semantics are Phase 7 migration targets.
- `WebViewPool.onResidentSetChange` is an event trigger, not a policy writer.
- `TabStore.lastUsedAt` remains the LRU fact source.
- Phase 6 restore and Phase 7 reclaim policy are separate ownership concerns.
- public WebKit APIs do not provide trustworthy exact per-Slot WebContent memory attribution.
