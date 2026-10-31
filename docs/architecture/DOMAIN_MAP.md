# FloatTabs Domain Map

This file is a **derived navigation map**. It does not replace product/design contracts, source code, tests, `CURRENT_STATUS.md`, or `CURRENT_TASK.md`.

## Authority order

For current behavior, use this order:

1. production source and regression tests on current Delivery / Semantic HEAD;
2. current accepted product/design/architecture contracts, including [`FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md`](FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md) for the Runtime Lifecycle / Memory program and `docs/design/FloatTabs_UI_Design_System_v1.3.md` for unaffected shell behavior;
3. `docs/architecture/README.md` and current architecture references;
4. current release / validation evidence;
5. historical stage/archive documents as evidence only.

The Runtime Lifecycle / Memory contract defines accepted target direction and phase gates. It does not make future, unimplemented behavior current production truth.

## Domain routes

| Domain | Owns | Primary source / entry points | Key boundaries |
|---|---|---|---|
| App Composition | dependency wiring, app launch/termination, top-level service composition | `FloatTabs/App/AppCoordinator.swift`, `AppDelegate.swift`, `FloatTabsApp.swift` | coordinates domains; should not become the semantic owner of Tab/Web/Focus state |
| Tabs & Profiles | Tab identity, selection, ordering, Web App / Browser Profile configuration | `FloatTabs/Tabs/TabStore.swift`, `WebAppProfile.swift`, `BrowserProfile.swift`, `WebRenderingProfile.swift` | Tab state is product/configuration state; Web runtime lifecycle remains under Web; persisted Hot/Warm/Cold values are compatibility state during the accepted lifecycle program, not a license to move runtime ownership into Tabs |
| Web Runtime | `WKWebView` creation/reuse, runtime identity, navigation observation, Slot residency/release/recovery | `FloatTabs/Web/WebViewPool.swift`, `SlotLifecycleCoordinator.swift`, `SlotNavigationObserver.swift`, `BrowserProfileDataStoreProvider.swift` | distinguish page-content failure, WebKit/runtime failure, and upper-layer projection; reload is not a substitute for runtime ownership; incident IDs correlate evidence but do not transfer runtime authority to Diagnostics; accepted program direction treats live WebViews as reclaimable cache only after safe restore is proven |
| Window / Panel / Fullscreen | shell visibility, panel/window synchronization, fullscreen source hosting, screen positioning | `FloatTabs/Panel/PanelController.swift`, `FloatingPanel.swift`, `FullscreenSourceHost.swift`, `ScreenPositioning.swift` | one writer per presentation state; fullscreen transitions must not create competing window authority; bounded diagnostic snapshots are observations only; lifecycle reclaim must not detach a currently visible/fullscreen/supplemental-visible runtime |
| Focus / Input / Commands | native/Web focus routing, global/app shortcuts, command dispatch, click/drag interaction routing | `FloatTabs/Web/WebFocusRouter.swift`, `FloatTabs/Hotkeys/AppCommandController.swift`, `GlobalHotkeyController.swift`, focus policy in `PanelController.swift` | distinguish native focus from DOM focus; event monitors/commands must not silently become window or Tab state owners |
| Persistence & Recovery | durable Tab/Profile state, app preferences, backups, unread durable state | `FloatTabs/Persistence/ProfileRepository.swift`, `AppPreferencesStore.swift`, `FloatTabsBackupService.swift`, `UnreadResponseStore.swift` | preserve user data; runtime/transient state must not be persisted as a workaround for runtime bugs; runtime hibernation must not delete Browser Profile/session/website data |
| Attention / Response Projection | ChatGPT attention/response extraction, unread projection, presentation routing | `FloatTabs/Web/ChatGPTAttentionBridge.swift`, `ChatGPTResponseBridge.swift`, `ChatGPTResponseExtraction.swift`, `ChatGPTUnreadResponseCoordinator.swift`, `WebAttentionCoordinator.swift` | provider observations, response identity, unread state, and presentation are separate responsibilities; durable unread must remain distinct from runtime Attention; the accepted lifecycle program may decouple `ready` from indefinite runtime residency only after completion/unread handoff is proven safe |
| Diagnostics | diagnostic event vocabulary, incident correlation context, privacy filtering, bounded snapshots, persistence/export | `FloatTabs/Diagnostics/RuntimeDiagnostics.swift`, `RuntimeDiagnosticWriter.swift`, `RuntimeDiagnosticEvent.swift`, `RuntimeDiagnosticPrivacy.swift`, `RuntimeDiagnosticSnapshot.swift`, `LongTermPerformanceObservationCoordinator.swift` | diagnostics records cross-domain evidence but never owns runtime/product state or root cause; correlate Slot/session/runtime/navigation identity; WebContent memory attribution remains unavailable through public WebKit APIs |
| Website Cache / Storage | website-cache measurement, cleanup policy, scheduling, usage state | `FloatTabs/Storage/WebsiteCacheCleanupCoordinator.swift`, `WebsiteCacheCleanupService.swift`, `WebsiteCachePolicy.swift`, `WebsiteCacheSizeMeasurer.swift`, `WebsiteCacheUsageStore.swift` | cache cleanup must not delete durable profile/session product data outside its explicit policy; cache cleanup is not a substitute for runtime reclamation |
| Menu / Status Projection | menu-bar/status presentation and user entry actions | `FloatTabs/MenuBar/StatusItemController.swift` | projection/command surface only; canonical runtime state remains in owning domains |

## Cross-domain flow

Current production runtime flow:

```text
AppCoordinator
→ TabStore selects/configures Slot
→ PanelController presents shell
→ WebViewPool owns WebView runtime
→ SlotNavigationObserver owns navigation/runtime observations
→ SlotLifecycleCoordinator manages residency/release/recovery decisions
→ WebFocusRouter / command layer manages input focus
→ Attention / Response consume bounded Web signals
→ Persistence saves durable user state
→ Diagnostics correlates privacy-filtered evidence across those owners
```

Accepted Runtime Lifecycle / Memory target flow preserves those ownership boundaries while adding a testable policy layer and safe restore primitive:

```text
runtime/protection/resource facts
→ pure residency policy / candidate decision
→ SlotLifecycleCoordinator executes lifecycle transition
→ WebViewPool captures/releases/restores disposable runtime
→ Browser Profile / durable unread / Slot configuration remain outside runtime lifetime
```

Exact implementation symbols for the future pure policy are intentionally not frozen here before the phase-specific implementation audit.

A diagnostic incident ID is a correlation key only. It is not a canonical product state and cannot make Diagnostics the writer for Web runtime, Attention, focus or persistence.

## Verification routes

Tests live under `FloatTabsTests/`. Prefer the narrowest matching tests first, then broaden when the changed boundary crosses lifecycle, persistence, WebKit, window/focus, or recovery behavior. Relevant routes include:

- `RuntimeDiagnosticsTests.swift`, `RuntimeDiagnosticsPrivacyTests.swift`, `RuntimeDiagnosticsTraceTests.swift`, `RuntimeDiagnosticsRotationTests.swift` — diagnostic vocabulary/privacy/writer behavior;
- `WebFocusAdapterTests.swift` — navigation/liveness incident correlation regression coverage;
- `WebViewPoolTests.swift` — runtime/recovery disposition, runtime identity, stale callback, and lifecycle evidence;
- `WebAttentionLifecycleTests.swift` — residency/Attention/memory-pressure interaction and release-order behavior;
- `ChatGPTAttentionBridgeTests.swift`, `ChatGPTResponseBridgeTests.swift`, `UnreadResponseTests.swift`, and `WebAttentionCrossFeatureTests.swift` — Attention/response/unread ownership and abnormal-path coverage;
- Browser Profile persistence/switch/settings tests — persistent user-data boundaries;
- `AppCommandControllerTests.swift`, `AppPreferencesStoreTests.swift` — adjacent domain ownership.

For `FT-RUNTIME-LIFECYCLE-MEMORY-001`, each implementation phase must additionally satisfy the focused audit and verification gate frozen in [`FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md`](FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md).

Before editing a domain, locate the exact matching tests/symbols on the current task branch; this map is a routing aid, not a frozen file inventory.

## Incident routing

For a real runtime failure, identify the boundary first:

```text
Tab/configuration
vs Web page content
vs WebView runtime/navigation
vs Window/Fullscreen
vs Focus/Input
vs Persistence
vs Attention/Response projection
```

Then correlate fresh evidence by Slot, session, runtime generation, navigation generation and time where available. Treat reload/reset/restart only as recovery evidence. Keep `ROOT_CAUSE=UNKNOWN` when the recorded evidence cannot prove causation.

Use normal Project Governance when evidence is sufficient. Use Incident Doctor only when a real failure blocks progress and existing evidence cannot support the next safe decision.

## Known structural notes

- `PanelController.swift` is a large integration/presentation owner. Treat new responsibilities cautiously; do not move unrelated domain state into it for convenience.
- `WebViewPool.swift` and `SlotLifecycleCoordinator.swift` are central runtime authorities and require higher verification for lifecycle/recovery changes. Phase 1 of the accepted lifecycle program must audit their complete create/rebuild/release/restore retain graph before product mutation.
- `SlotNavigationObserver.swift` is the navigation/runtime observation owner and now contributes incident/liveness evidence; it is still not a recovery-policy writer.
- `ChatGPTAttentionBridge.swift` owns Attention runtime behavior; diagnostic classification must remain observational.
- `UnreadResponseStore` / `ChatGPTUnreadResponseCoordinator` own durable unread projection independently from runtime Attention; future reclaim policy must preserve that split.
- `TabStore.swift` owns canonical Tab/Profile configuration projection and persistence mutations through `ProfileRepository`.
- `AppCoordinator.swift` is the composition root; it wires authorities but should not duplicate them.

If a future task discovers that any route above is stale, update only the affected mapping claim after verifying the replacement source/authority.
