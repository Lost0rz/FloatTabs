# FloatTabs Domain Map

This file is a **derived navigation map**. It does not replace `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`, accepted contracts, production source or tests.

## Authority order

1. `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`;
2. current accepted architecture/design contract, currently `FloatTabs_Runtime_Lifecycle_Memory_Contract_V4.md` plus the active Phase 5 plan;
3. `docs/README.md` / `docs/architecture/README.md`;
4. this map for navigation;
5. production source/tests/fresh evidence;
6. historical Stage/archive material as evidence only.

## Domain routes

| Domain | Owns | Primary source / entry points | Key boundaries |
|---|---|---|---|
| App Composition | dependency wiring, launch/termination, top-level services | `FloatTabs/App/AppCoordinator.swift`, `AppDelegate.swift`, `FloatTabsApp.swift` | coordinates domains; does not own Tab/Web/Attention truth |
| Tabs & Profiles | Slot identity, selection, ordering, Web App / Browser Profile config, persisted `lastUsedAt` | `FloatTabs/Tabs/TabStore.swift`, `WebAppProfile.swift`, `BrowserProfile.swift`, `WebRenderingProfile.swift` | durable product/config state; Runtime lifecycle remains Web-owned |
| Web Runtime | `WKWebView` creation/reuse, Runtime identity, hibernate/restore/release mechanism, bridge lifetime | `FloatTabs/Web/WebViewPool.swift`, `SlotNavigationObserver.swift`, `BrowserProfileDataStoreProvider.swift` | mechanism owner; does not own lifecycle policy or durable product state |
| Runtime Lifecycle | residency execution, inactive timers, protection boundaries, memory-pressure and automatic-budget execution | `FloatTabs/Web/SlotLifecycleCoordinator.swift` | sole canonical Runtime lifecycle writer |
| Runtime Budget Policy | Phase 4 deterministic managed-budget decision | private `RuntimeBudgetPolicy` in `FloatTabs/Web/SlotLifecycleCoordinator.swift` | pure/read-only decision; no WebKit/persistence side effects |
| Attention / Generation Sensing | ChatGPT generation sensing, native Attention state, liveness fallback | `ChatGPTAttentionBridge.swift`, `WebAttentionCoordinator.swift` | `WebAttentionCoordinator` owns Attention state; bridge senses only; Generating protects Runtime |
| Background Generation Thrift | Phase 5 bounded reduction of FloatTabs-owned liveness fallback work | `ChatGPTAttentionBridge.swift` | may alter watchdog scheduling only; never provider generation, lifecycle ownership or canonical visibility |
| Response / Unread | response identity/extraction and durable unread handoff | `ChatGPTResponseBridge.swift`, `ChatGPTResponseExtraction.swift`, `ChatGPTUnreadResponseCoordinator.swift`, `UnreadResponseStore.swift` | durable unread remains independent from Runtime residency |
| Native Notification Projection | completion alert delivery and exact-Slot response routing | `FloatTabs/App/ChatGPTCompletionNotificationCoordinator.swift` | projection only; never owns unread/Runtime/Profile state |
| Window / Panel / Fullscreen | shell visibility, window synchronization, fullscreen hosting, exact-Slot presentation | `FloatTabs/Panel/PanelController.swift`, `FloatingPanel.swift`, `FullscreenSourceHost.swift`, `ScreenPositioning.swift` | owns product/presentation visibility truth; page `visibilityState` is not a replacement |
| Focus / Input / Commands | native/Web focus, shortcuts, commands, click/drag routing | `FloatTabs/Web/WebFocusRouter.swift`, `FloatTabs/Hotkeys/AppCommandController.swift`, `GlobalHotkeyController.swift` | native focus and DOM focus remain distinct; no Runtime ownership |
| Persistence & Recovery | durable Slot/Profile state, preferences, backups, durable unread | `ProfileRepository.swift`, `AppPreferencesStore.swift`, `FloatTabsBackupService.swift`, `UnreadResponseStore.swift` | no Runtime persistence workaround; no Phase 5 schema change |
| Diagnostics | diagnostic events, incident context, privacy filtering, bounded snapshots, long-term observation | `RuntimeDiagnostics.swift`, `RuntimeDiagnosticWriter.swift`, `RuntimeDiagnosticEvent.swift`, `LongTermPerformanceObservationCoordinator.swift` | evidence only; never lifecycle/Attention/thrift authority |
| Website Cache / Storage | re-downloadable website-cache measurement/cleanup | `FloatTabs/Storage/WebsiteCacheCleanupCoordinator.swift`, `WebsiteCacheCleanupService.swift`, `WebsiteCachePolicy.swift` | cache cleanup is not Runtime cleanup and cannot destroy Profile/session data |
| Menu / Status Projection | menu-bar/status projection and entry actions | `FloatTabs/MenuBar/StatusItemController.swift` | projection only; unread truth comes from durable unread |

## Runtime lifecycle flow after Phase 4

```text
TabStore owns persistent Slot/config + lastUsedAt
→ WebViewPool owns live WKWebView Runtime cache
→ SlotLifecycleCoordinator gathers resident/protection/recency facts
→ private RuntimeBudgetPolicy returns deterministic ranked decision
→ SlotLifecycleCoordinator performs eligible existing hibernate boundary
→ Persistence retains user product/session state
```

Phase 4 hard protection sources:

```text
active / actually presented
fullscreen source
supplemental visible Web surface
media protection / pending media query
Attention Generating
Hot explicit pin
```

These are not Runtime protections:

```text
Attention Ready
durable unread
native completion notification
```

Current normal/warning managed target defaults to 3 Warm/Cold runtimes. Critical pressure targets 0 eligible inactive Warm/Cold. The target may be exceeded by Hot/hard protections.

## Phase 5 generation-thrift flow

```text
ChatGPT page event/mutation detector
→ ChatGPTAttentionBridge observation
→ WebAttentionCoordinator owns .generating
→ SlotLifecycleCoordinator sees Runtime protection
→ Runtime stays live

in parallel:
ChatGPTAttentionBridge liveness watchdog
→ small read-only isolated-world probe
→ page visibility hint + generation state
→ cadence selector
→ 2s normally / 5s only after 30s of hidden generation
→ false result still requires existing 250ms confirmation
```

Important boundaries:

- `document.visibilityState` is **local scheduling metadata only**.
- `PanelController.isAttentionUserVisible(slotID:)` remains canonical product/presentation visibility.
- Phase 5 never calls Runtime hibernate/release/reload.
- Phase 5 never pauses/cancels provider generation.
- the primary mutation-driven detector remains event-driven; Phase 5 does not replace it with polling.

## Verification routes

Relevant tests:

- `FloatTabsTests/ChatGPTAttentionBridgeTests.swift` — Phase 5 cadence/liveness/stale-callback and detector contract;
- `FloatTabsTests/WebAttentionCoordinatorTests.swift` — Generating/Ready Attention semantics;
- `FloatTabsTests/WebAttentionLifecycleTests.swift` — lifecycle protection/reclaim ordering;
- `FloatTabsTests/WebAttentionCrossFeatureTests.swift` — cross-domain non-regression;
- `FloatTabsTests/WebViewPoolTests.swift` — Runtime identity/hibernate/restore mechanism;
- Browser Profile tests — persistent user-data boundaries.

Required repository host gate remains `Build & Test (Apple Silicon arm64)` on `macmini-floattabs-01`.

## Performance / benchmark routing

The former Phase 4 strict budget-selection benchmark route is historical/deferred tuning, not active Phase 5 authority.

Current Phase 5 correctness is established by deterministic cadence behavior plus regression/build/CI evidence. Future numeric memory/CPU tuning and user-adjustable thresholds belong to a separately authorized Settings-backed performance task.

## Incident routing

For runtime failures, classify the boundary before changing code:

```text
Slot/config
vs Runtime budget decision
vs lifecycle execution
vs WebView runtime/navigation
vs Attention sensing/liveness fallback
vs Response/Unread
vs Window/Fullscreen
vs Focus/Input
vs Persistence
vs Native Notification
```

Correlate fresh evidence by Slot/session/runtime/navigation generation and time where available. Treat reload/reset/restart only as recovery evidence; keep root cause `UNKNOWN` when evidence cannot prove causation.

## Known structural notes

- `SlotLifecycleCoordinator` is the only release/hibernate decision executor.
- the Phase 4 `RuntimeBudgetPolicy` currently lives privately inside `SlotLifecycleCoordinator.swift`; there is no standalone production `RuntimeBudgetPolicy.swift`.
- `WebViewPool.onResidentSetChange` is an event trigger, not a policy writer.
- `LongTermPerformanceObservationCoordinator` remains diagnostics-only.
- `TabStore.lastUsedAt` remains the LRU fact source.
- Hot remains an explicit user pin; Warm/Cold remain automatic-budget managed.
- Browser Profile/session/configuration data remains outside Runtime/thrift mutation.
- public WebKit APIs do not provide trustworthy exact per-Slot WebContent memory attribution.
