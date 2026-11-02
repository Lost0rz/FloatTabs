# FloatTabs Domain Map

This file is a **derived navigation map**. It does not replace `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`, accepted current contracts, production source or tests.

## Authority order

1. `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`;
2. `docs/README.md`;
3. current lifecycle authority: `FloatTabs_Runtime_Lifecycle_Memory_Contract_V6.md` + active Phase 8 implementation contract;
4. `docs/architecture/README.md`;
5. this map for navigation;
6. production source/tests/fresh evidence;
7. historical V5/Phase 7/Stage/archive material as evidence only.

## Domain routes

| Domain | Owns | Primary source / entry points | Key boundaries |
| --- | --- | --- | --- |
| App Composition | dependency wiring, launch/termination, top-level services | `FloatTabs/App/AppCoordinator.swift`, `AppDelegate.swift`, `FloatTabsApp.swift` | coordinates domains; does not own Tab/Web/Attention truth |
| Tabs & Profiles | Slot identity, selection, ordering, Web App / Browser Profile config, persisted `lastUsedAt`, Runtime retention preference | `FloatTabs/Tabs/TabStore.swift`, `WebAppProfile.swift`, `BrowserProfile.swift`, `WebRenderingProfile.swift` | durable Slot/config state; Runtime lifecycle remains Web-owned |
| Web Runtime | `WKWebView` creation/reuse, Runtime identity, hibernate/restore/release, renderer recovery, bridge lifetime | `FloatTabs/Web/WebViewPool.swift`, `SlotNavigationObserver.swift`, `BrowserProfileDataStoreProvider.swift` | mechanism owner; does not own lifecycle policy or durable product state |
| Runtime Lifecycle | lifecycle execution, inactivity/protection boundaries, memory-budget/pressure reclaim | `FloatTabs/Web/SlotLifecycleCoordinator.swift` | sole canonical Runtime lifecycle writer |
| Runtime Budget Policy | deterministic read-only decision from resource/protection/recency facts | current private policy in `SlotLifecycleCoordinator.swift`; Phase 8 may refactor into a pure helper | no WebKit/persistence side effects |
| Runtime Resource Observation | **Phase 8 target:** aggregate FloatTabs/WebKit working-set observation | expected new Web/performance read-only component after Gate 0 | input only; cannot kill/reload/reclaim or claim per-Slot RSS |
| Attention / Generation Sensing | ChatGPT generation sensing, native Attention state, liveness fallback | `ChatGPTAttentionBridge.swift`, `WebAttentionCoordinator.swift` | Generating protects Runtime; Ready/unread does not own Runtime |
| Response / Unread | response identity/extraction and durable unread handoff | `ChatGPTResponseBridge.swift`, `ChatGPTResponseExtraction.swift`, `ChatGPTUnreadResponseCoordinator.swift`, `UnreadResponseStore.swift` | durable unread survives Runtime reclamation |
| Native Notification Projection | completion alert delivery and exact-Slot response routing | `FloatTabs/App/ChatGPTCompletionNotificationCoordinator.swift` | projection only; never owns Runtime/Profile state |
| Window / Panel / Fullscreen | shell visibility, synchronization, fullscreen hosting, exact-Slot presentation | `FloatTabs/Panel/PanelController.swift`, `FloatingPanel.swift`, `FullscreenSourceHost.swift`, `ScreenPositioning.swift` | presentation truth only; no Runtime policy ownership |
| Focus / Input / Commands | native/Web focus, shortcuts, commands, click/drag routing | `FloatTabs/Web/WebFocusRouter.swift`, `FloatTabs/Hotkeys/AppCommandController.swift`, `GlobalHotkeyController.swift` | native focus and DOM focus remain distinct; no Runtime ownership |
| Persistence & Recovery | durable Slot/Profile state, app preferences, backups, recovery data | `ProfileRepository.swift`, `AppPreferencesStore.swift`, `FloatTabsBackupService.swift` | memory-budget config is global app config; migration must not destroy user data |
| Diagnostics | diagnostic events, incidents, privacy filtering, snapshots, long-term observation | `RuntimeDiagnostics.swift`, `RuntimeDiagnosticWriter.swift`, `RuntimeDiagnosticEvent.swift`, `LongTermPerformanceObservationCoordinator.swift` | evidence only; never memory/lifecycle policy truth |
| Website Cache / Storage | re-downloadable website-cache measurement/cleanup | `FloatTabs/Storage/WebsiteCacheCleanupCoordinator.swift`, `WebsiteCacheCleanupService.swift`, `WebsiteCachePolicy.swift` | cache cleanup is not Runtime cleanup |
| Menu / Status Projection | menu-bar/status projection and entry actions | `FloatTabs/MenuBar/StatusItemController.swift` | projection only |
| Tab Rail / Runtime Retention Controls | Automatic/Keep Loaded projection, Browser Profile/media controls | `FloatTabs/UI/ExternalTabRail.swift` | per-Slot preference only; does not decide global memory budget |
| Global Settings | app settings, Browser/Performance/Advanced presentation | `FloatTabs/UI/GlobalSettingsController.swift`, `SettingsInformationArchitecture.swift` | Phase 8 target adds Advanced → Runtime & Memory; UI does not execute reclaim |

## Current shipped lifecycle truth

The merged production baseline is:

`main@2b414982710b3f042fc7d6e9c88eb2d7117b4e38`

Current shipped lifecycle:

```text
Slot persistent configuration
→ runtimeRetentionPreference = Automatic | Keep Loaded
→ WebViewPool owns live Runtime cache
→ SlotLifecycleCoordinator owns lifecycle decisions/execution
→ Phase 6 restores reclaimed Runtime on demand
```

Current shipped Phase 7 tuning remains:

```text
normal Automatic target = 2
inactive release path = 30s
warning target = 1
critical target = 0
```

This is **current source truth**, not the future design target.

## Frozen Phase 8 target lifecycle

V6/Phase 8 target:

```text
persistent Slot/Profile/session
→ Runtime materializes on demand
→ resource monitor supplies aggregate FloatTabs/WebKit footprint fact
→ memory-budget policy + protection facts choose at most one reclaim candidate
→ SlotLifecycleCoordinator revalidates and executes
→ WebViewPool hibernates
→ fresh resource observation
→ continue only if still required
→ Phase 6 restores on next use
```

Normal target:

```text
Memory Budget = Auto | Custom | Unlimited
no fixed resident-count ceiling
high watermark = 105%
low watermark = 90%
proactive long-idle cleanup = OFF by default
```

Initial Auto reference:

```text
clamp(physical RAM × 20%, 1.5 GiB, 6 GiB)
```

The existing 30-second value becomes a **normal budget candidate anti-thrash grace**, not an unconditional Runtime lifetime.

## Protection route

Hard protections:

```text
active / actually presented
fullscreen source
supplemental visible Web surface
Attention Generating
active/pending allowed-background-media protection
current materialization/restoring ownership
```

These do not by themselves require Runtime residency after generation finishes:

```text
Attention Ready
durable unread
native completion notification
mere restore snapshot
```

Keep Loaded:

- excluded from normal budget reclaim;
- may cause normal budget oversubscription;
- warning still prefers Automatic reclaim;
- critical may reclaim inactive/unprotected Keep Loaded after Automatic candidates.

## Resource measurement route

Phase 8 Gate 0 must prove a supported production-safe aggregate measurement mechanism before budget-based reclaim is enabled.

Desired fact:

```text
FloatTabs host
+ FloatTabs-attributable WebKit helper processes
= aggregate observed footprint
```

Constraints:

- no exact per-Slot WebContent memory attribution;
- no direct process killing;
- no lifecycle side effect from the monitor;
- unavailable measurement must be explicit;
- do not substitute Runtime count for GiB.

The existing Python benchmark's launchd responsible-PID attribution is evidence/reference only until a production-safe in-app mechanism is proven.

## Background-generation route

Current semantic ownership remains:

```text
ChatGPTAttentionBridge
→ normalized generation observation
→ WebAttentionCoordinator
→ Generating hard protection query
→ SlotLifecycleCoordinator
```

Phase 8 WP5 may reduce hidden observer/probe/diagnostic cost but may not deep-freeze/destroy a Runtime while arbitrary generation must continue.

On completion:

```text
Generating ends
→ Ready/unread + native notification
→ hard generating protection ends
→ normal budget lifecycle resumes
```

## Persistence route

### Per-Slot

- `WebAppProfile.runtimeRetentionPreference` remains `Automatic | Keep Loaded`;
- legacy Hot/Warm/Cold stays compatibility-only.

### Global Phase 8 target

- `AppPreferencesStore` owns `Auto / Custom / Unlimited` memory-budget configuration;
- missing value defaults to Auto;
- Custom is validated/clamped;
- backup includes the new global preference when global performance settings are within backup scope;
- old Warm/Cold stored keys remain non-destructively retained but unused.

Browser Profile/session data is outside this configuration migration.

## Verification routes

Phase 8 expected coverage includes:

- `AppPreferencesStoreTests.swift` — budget defaults/normalization/change projection;
- new resource-monitor/policy tests — deterministic observations and one-at-a-time decisions;
- `WebAttentionLifecycleTests.swift` — hard protection + pressure ordering;
- `WebViewPoolTests.swift` — hibernate/restore/runtime identity;
- `SettingsInformationArchitectureTests.swift` — Advanced Runtime & Memory surface;
- `FloatTabsBackupServiceTests.swift` — only if backup scope changes;
- `ChatGPTAttentionBridgeTests.swift` — hidden generation efficiency/completion correctness;
- `ExternalShellTests.swift` — restore/presentation regression where relevant.

Required repository host gate remains `Build & Test (Apple Silicon arm64)` on `macmini-floattabs-01`.

Phase 8 must use a new acceptance path/criteria; the Phase 7 benchmark remains historical evidence and must not assert `resident target = 2` as Phase 8 success.

## Incident routing

For runtime/performance failures, classify before mutation:

```text
Slot/config
vs memory-budget configuration
vs aggregate resource observation
vs budget decision
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

Reload/reset/restart prove only a recovery boundary. Preserve root cause `UNKNOWN` when evidence cannot prove causation.

## Structural notes

- `SlotLifecycleCoordinator` remains the only Runtime reclaim executor.
- `WebViewPool.onResidentSetChange` remains an event trigger, not policy authority.
- resource observation is read-only policy input.
- diagnostics may record budget/measurement/reclaim events but cannot drive product truth.
- Phase 6 restore and Phase 8 reclaim policy remain separate ownership concerns.
- V5/Phase 7 fixed-count behavior is historical once Phase 8 lands; preserve it in Git/history/archive rather than compatibility product branches.
