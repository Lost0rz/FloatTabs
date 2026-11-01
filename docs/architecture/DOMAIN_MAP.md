# FloatTabs Domain Map

This file is a **derived navigation map**. It does not replace `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`, accepted contracts, production source or tests.

## Authority order

1. `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`;
2. current accepted architecture/design contracts, including `FloatTabs_Runtime_Lifecycle_Memory_Contract_V3.md` and the active phase plan;
3. `docs/README.md` / `docs/architecture/README.md`;
4. this map for navigation;
5. production source/tests/fresh evidence;
6. historical Stage/archive material as evidence only.

## Domain routes

| Domain | Owns | Primary source / entry points | Key boundaries |
|---|---|---|---|
| App Composition | dependency wiring, launch/termination, top-level services, DEBUG benchmark control composition | `FloatTabs/App/AppCoordinator.swift`, `AppDelegate.swift`, `FloatTabsApp.swift`, `BenchmarkControlServer.swift` | coordinates domains; does not own Tab/Web/Unread/Runtime-budget truth |
| Native Notification Projection | ChatGPT completion native alert delivery and response parsing | `FloatTabs/App/ChatGPTCompletionNotificationCoordinator.swift` | projection only; Slot UUID routes; never owns unread, Runtime or Profile/session state |
| Tabs & Profiles | Slot identity, selection, ordering, Web App / Browser Profile configuration, persisted `lastUsedAt` | `FloatTabs/Tabs/TabStore.swift`, `WebAppProfile.swift`, `BrowserProfile.swift`, `WebRenderingProfile.swift` | product/config state; Runtime lifecycle remains Web-domain owned |
| Runtime Budget Policy | Phase 4 pure budget/eviction ranking decision | Phase 4 target `FloatTabs/Web/RuntimeBudgetPolicy.swift` | deterministic read-only decision only; no AppKit/WebKit/persistence/release side effects |
| Web Runtime | `WKWebView` creation/reuse, Runtime identity, hibernate/restore/release mechanism | `FloatTabs/Web/WebViewPool.swift`, `SlotNavigationObserver.swift`, `BrowserProfileDataStoreProvider.swift` | mechanism owner; Phase 4 must not change hibernate/restore contract without reconciliation |
| Runtime Lifecycle | residency execution, inactive timers, protection boundaries, memory-pressure/budget execution | `FloatTabs/Web/SlotLifecycleCoordinator.swift` | sole canonical Runtime lifecycle writer; consumes pure budget decision and executes existing hibernate boundary |
| Window / Panel / Fullscreen | shell visibility, panel/window synchronization, fullscreen hosting, exact-Slot presentation, bounded cross-domain handoffs | `FloatTabs/Panel/PanelController.swift`, `FloatingPanel.swift`, `FullscreenSourceHost.swift`, `ScreenPositioning.swift` | one writer per presentation state; supplies current presentation/protection facts but does not become policy/persistence owner |
| Focus / Input / Commands | native/Web focus, shortcuts, commands, click/drag routing | `FloatTabs/Web/WebFocusRouter.swift`, `FloatTabs/Hotkeys/AppCommandController.swift`, `GlobalHotkeyController.swift` | native focus and DOM focus remain distinct; no Runtime ownership |
| Persistence & Recovery | durable Slot/Profile state, preferences, backups, durable unread | `ProfileRepository.swift`, `AppPreferencesStore.swift`, `FloatTabsBackupService.swift`, `UnreadResponseStore.swift` | no Runtime persistence workaround; Phase 4 adds no Runtime-budget preference/schema |
| Attention / Response | ChatGPT Attention sensing, response identity/extraction, durable unread handoff | `ChatGPTAttentionBridge.swift`, `ChatGPTResponseBridge.swift`, `ChatGPTResponseExtraction.swift`, `ChatGPTUnreadResponseCoordinator.swift`, `WebAttentionCoordinator.swift` | Generating protects Runtime; Ready/unread do not; Phase 4 does not change sensing/unread semantics |
| Diagnostics | diagnostic events, incident context, privacy filtering, bounded snapshots | `RuntimeDiagnostics.swift`, `RuntimeDiagnosticWriter.swift`, `RuntimeDiagnosticEvent.swift`, `LongTermPerformanceObservationCoordinator.swift` | evidence only; never policy authority or causal proof |
| Benchmark / Performance Evidence | DEBUG-safe Real-Mac aggregate process-tree measurement and policy evidence | `tools/benchmark/`, `BenchmarkControlServer.swift`, bounded DEBUG handlers in App/Panel | aggregate responsible-process evidence only; never claim exact per-Slot WebContent memory; restore temporary settings |
| Website Cache / Storage | re-downloadable website-cache measurement/cleanup | `FloatTabs/Storage/WebsiteCacheCleanupCoordinator.swift`, `WebsiteCacheCleanupService.swift`, `WebsiteCachePolicy.swift` | cache cleanup is not Runtime cleanup and cannot destroy Profile/session data outside explicit policy |
| Menu / Status Projection | menu-bar/status projection and entry actions | `FloatTabs/MenuBar/StatusItemController.swift` | projection only; unread truth comes from durable unread |

## Runtime flow through Phase 4

```text
AppCoordinator
→ TabStore owns persistent Slot/config + lastUsedAt
→ PanelController owns shell/presentation facts
→ WebViewPool owns live WKWebView Runtime cache
→ SlotLifecycleCoordinator owns lifecycle execution
→ RuntimeBudgetPolicy receives read-only candidate/protection/recency facts
→ pure ranked decision returns
→ SlotLifecycleCoordinator performs any eligible existing hibernate boundary
→ Persistence retains user product/session state
→ Diagnostics/benchmark record bounded evidence only
```

## Protection / budget navigation

Phase 4 hard protection sources:

```text
active/actually presented
fullscreen source
supplemental visible Web surface
media protection
Attention Generating
```

These are not Runtime protections:

```text
Attention Ready
durable unread
native completion notification
```

Residency meaning:

```text
Hot  -> explicit user pin, outside automatic eviction candidates
Warm -> automatic-budget managed, normal maximum retention timer remains
Cold -> automatic-budget managed, first eviction priority, normal maximum retention timer remains
```

The automatic managed budget can be exceeded by Hot/hard protections; diagnostics must report that oversubscription rather than violating the protection/user-pin contract.

## Phase 4 benchmark route

Use:

- existing `tools/benchmark/floattabs_benchmark.py` / `floattabs_lifecycle_benchmark.py` as infrastructure/history;
- Phase 4 target `tools/benchmark/floattabs_runtime_budget_benchmark.py` for strict `1 / 2 / 4 / 8`, control drift, candidate-budget and restore/materialization evidence;
- Debug `BenchmarkControlServer` and product-path configuration/selection only;
- aggregate FloatTabs-responsible WebKit helper attribution via existing responsible-PID tooling.

Do not directly edit persisted profile JSON or synthesize exact per-Slot WebContent byte ownership.

## Verification routes

Relevant tests under `FloatTabsTests/`:

- Phase 4 target `RuntimeBudgetPolicyTests.swift` — pure ranking/budget/protection rules;
- `WebAttentionLifecycleTests.swift` — lifecycle timers, protection, memory pressure, hibernate ordering;
- `WebViewPoolTests.swift` — Runtime identity/hibernate/restore mechanism evidence; production contract should remain unchanged in Phase 4;
- Attention/Unread/Notification tests — cross-phase non-regression only;
- Browser Profile tests — persistent user-data boundaries;
- Phase 3 notification tests — notification projection/routing remains independent from Runtime residency.

## Incident routing

For runtime failures, classify the boundary before changing code:

```text
Slot/config
vs Runtime budget decision
vs lifecycle execution
vs WebView runtime/navigation
vs Window/Fullscreen
vs Focus/Input
vs Persistence
vs Attention/Response
vs Native Notification
```

Correlate fresh evidence by Slot/session/runtime/navigation generation and time where available. Treat reload/reset/restart only as recovery evidence; keep root cause `UNKNOWN` when evidence cannot prove causation.

## Known structural notes

- `SlotLifecycleCoordinator` remains the only release/hibernate decision executor in Phase 4.
- `RuntimeBudgetPolicy` is a pure policy object and must never mutate WebKit or persistence.
- `WebViewPool.onResidentSetChange` is a read-only/event trigger; it does not transfer lifecycle ownership to the pool.
- `LongTermPerformanceObservationCoordinator` remains diagnostics-only and cannot become automatic budget authority.
- `TabStore.lastUsedAt` is the accepted LRU fact source for Phase 4; do not infer recency from diagnostics timestamps.
- Hot is an explicit user pin; Warm/Cold are automatic-budget managed under the active Phase 4 plan.
- Browser Profile/session/configuration data remains outside Runtime budget mutation.
- public WebKit APIs do not provide trustworthy exact per-Slot WebContent memory attribution.

If a future task proves a route stale, update only the affected mapping after verifying the replacement owner/source.
