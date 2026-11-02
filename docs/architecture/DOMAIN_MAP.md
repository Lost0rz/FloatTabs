# FloatTabs Domain Map

This file is a **derived navigation map**. It does not replace `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`, accepted current contracts, production source or tests.

## Authority order

1. `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`;
2. `docs/README.md`;
3. current task contract: `FloatTabs_Adaptive_Lifecycle_Restore_Contract_V1.md`;
4. `docs/architecture/README.md`;
5. this map for navigation;
6. production source/tests/fresh evidence;
7. older lifecycle/notification contracts and archive material as bounded historical/delivered evidence.

## Domain routes

| Domain | Owns | Primary source / entry points | Current-task boundary |
| --- | --- | --- | --- |
| App Composition | dependency wiring, launch/termination, top-level services | `FloatTabs/App/AppCoordinator.swift`, `AppDelegate.swift`, `FloatTabsApp.swift` | composition only; not lifecycle policy |
| Tabs & Profiles | persistent Slot identity, selection, ordering, Web App / Browser Profile config, `lastUsedAt`, `Automatic | Keep Loaded` preference | `FloatTabs/Tabs/TabStore.swift`, `WebAppProfile.swift`, `BrowserProfile.swift`, `WebRenderingProfile.swift` | persistent truth; does not decide Runtime reclaim |
| Runtime Lifecycle | inactivity/protection policy, normal reclaim policy, system-pressure progression | `FloatTabs/Web/SlotLifecycleCoordinator.swift` | **sole canonical lifecycle writer**; primary owner for WP2/WP4 |
| Web Runtime | WKWebView creation/reuse, Runtime identity, hibernate/restore/release, bridge/observer lifetime | `FloatTabs/Web/WebViewPool.swift`, `SlotNavigationObserver.swift` | mechanism owner; primary restore/resource evidence route for WP0/WP4 |
| Web Runtime Configuration | supported WKWebView/WKPreferences configuration, rendering/UA | `FloatTabs/Web/WebViewFactory.swift` | mechanism only; any inactive-scheduling override needs WP0 evidence and lifecycle intent from coordinator |
| Window / Panel / Restore Presentation | shell visibility, selected-Slot synchronization, deferred materialization, restoring surface, fullscreen hosting | `FloatTabs/Panel/PanelController.swift`, `FloatTabs/Web/WebViewContainer.swift`, `FloatingPanel.swift`, `FullscreenSourceHost.swift` | primary WP0/WP1 restore-first-frame route; no reclaim ownership |
| Attention / Generation | ChatGPT generation sensing, native Attention state, liveness fallback | `ChatGPTAttentionBridge.swift`, `WebAttentionCoordinator.swift` | generation protection fact; must remain correct under any background scheduling policy |
| Response / Unread / Notification | assistant semantics, unread truth, native completion projection | `ChatGPTResponseExtraction.swift`, `ChatGPTResponseBridge.swift`, `ChatGPTUnreadResponseCoordinator.swift`, `ChatGPTCompletionNotificationCoordinator.swift` | delivered #193 behavior is a regression boundary; current task does not redesign notification semantics |
| Focus / Input / Commands | native/Web focus, shortcuts, command/event routing | `FloatTabs/Web/WebFocusRouter.swift`, `FloatTabs/Hotkeys/AppCommandController.swift`, `GlobalHotkeyController.swift` | cold/warm restore must not enable focus before exact-current readiness |
| Persistence & Recovery | durable Slot/Profile state, preferences, backup/restore | `ProfileRepository.swift`, `AppPreferencesStore.swift`, `FloatTabsBackupService.swift` | no destructive session/config mutation; new policy persistence only after policy is authorized |
| Diagnostics | diagnostic events, incidents, privacy filtering, long-term observation | `RuntimeDiagnostics.swift`, `RuntimeDiagnosticWriter.swift`, `RuntimeDiagnosticEvent.swift`, `LongTermPerformanceObservationCoordinator.swift` | evidence only; WP0 may add narrowly necessary timing events, never policy |
| Website Cache / Storage | re-downloadable website-cache measurement/cleanup | `FloatTabs/Storage/WebsiteCacheCleanupCoordinator.swift`, `WebsiteCacheCleanupService.swift`, `WebsiteCachePolicy.swift` | cache cleanup is not Runtime memory lifecycle |
| Tab Rail / Retention Projection | Automatic/Keep Loaded control, Browser Profile/media projection | `FloatTabs/UI/ExternalTabRail.swift` | retain current preference semantics during WP0 |
| Global Settings | app settings presentation | `FloatTabs/UI/GlobalSettingsController.swift`, `SettingsInformationArchitecture.swift` | no new lifecycle/memory settings until policy evidence is accepted |

## Current task route

```text
user-observed restore/resource problem
→ CURRENT_TASK / adaptive lifecycle contract
→ WP0 evidence only

WP0 restore route:
PanelController summon/select
→ selected Slot has resident Runtime?
   YES → WebPanelContainerView reattach path
   NO  → deferred materialization
          → native Restoring… surface
          → WebViewPool create/restore
          → exact-current navigation/runtime readiness
          → reveal/focus

WP0 background route:
SlotLifecycleCoordinator inactivity/protection facts
→ WebPanelContainerView detach presentation
→ resident WKWebView remains in WebViewPool
→ WebKit public inactive scheduling behavior applies according to platform/activity
→ later lifecycle policy may keep resident OR WebViewPool hibernate
```

## Current healthy-state production truth under review

```text
Automatic resident target = 2
Automatic inactive grace  = 30s
```

The new task explicitly rejects treating `2` as the final universal product target.

WP0 must choose an evidence-backed replacement direction before product mutation:

```text
A: pressure-first + bounded long-idle cleanup
B: adaptive soft warm-set using machine class + recency/revisit facts
C: narrowly evidenced hybrid
```

None may be described as an exact RAM/GiB budget.

## System-pressure route — preserved

```text
DispatchSourceMemoryPressure
→ SlotLifecycleCoordinator

warning
→ progressive eligible inactive/unprotected Automatic reclaim

critical
→ Automatic first
→ then inactive/unprotected Keep Loaded

normal
→ cancel pending continuation
→ no mass restore
```

This route remains independent from any future healthy-state soft policy.

## WebKit inactive scheduling route

Current `WebViewFactory` does not set `WKPreferences.inactiveSchedulingPolicy`.

On macOS 14+ the public WebKit default for a WebView not in a window is documented as `suspend`; idle suspended views pause JavaScript/layout, with activity exemptions such as media/loading/interactive work.

Therefore current routing is:

```text
lifecycle decides resident vs hibernate
→ presentation detach may make a resident WebView inactive
→ WebKit owns default scheduling mechanics
```

An explicit `.suspend` / `.throttle` / `.none` override, if ever accepted, belongs to WebView configuration mechanism but must be driven by an accepted lifecycle intent and WP0 evidence. It must not become a second state writer.

macOS 13 does not have the public inactive-scheduling API and must keep a supported fallback path.

## Restore-state route

Current hibernate:

```text
WebViewPool.hibernate
→ capture opaque memory-only interactionState + compatible identity facts
→ teardown live WKWebView/bridges/observer
→ no resident Runtime
```

Cold restore:

```text
new WKWebView
→ exact Browser Profile data store
→ bridges/observer
→ compatible interactionState apply OR URL load
→ readiness
```

The current task may investigate a bounded memory-only `WKWebView.takeSnapshot` visual continuity layer during WP0. A page image must never become persistent product state, diagnostics content or an interactive stale surface.

## Aggregate-memory boundary

Prior Phase 8 evidence remains authoritative:

```text
host footprint                         measurable
Networking helper attribution          measurable
WebContent/GPU attribution              unavailable as deterministic public production fact
```

Forbidden as production policy input:

- guessed/correlation per-tab memory;
- Runtime-count-as-GiB proxy;
- private WebKit process identifier SPI;
- root-only responsible-PID tooling;
- restricted entitlement dependencies;
- destructive Browser Profile/session reset.

## Current WP0 verification route

Evidence scenarios:

1. resident quick revisit;
2. >30s/nonresident cold revisit;
3. notification click to reclaimed Slot;
4. rapid A↔B↔A switching;
5. detached resident idle;
6. hidden 60–120s generation;
7. allowed background media when available;
8. hibernated resource state;
9. restoring state.

Correlate:

```text
panel visibility/request
panel.materialization.deferred / attached
web_runtime.create.begin / created
web_runtime.restore.completed or load path
navigation commit/finish
panel.materialization.readiness_completed / failed
restoring surface show/hide
```

If first-visible boundaries are not observable, add only a narrow diagnostic timing seam in WP0; do not alter product policy.

## Delivered notification route — regression only

PR #193 is merged and human accepted:

```text
hidden completion
→ unread .marked
→ native notification
→ exact Slot UUID click
→ selected Slot materialization if nonresident
```

The current task must preserve notification content/privacy/exact-route behavior while changing lifecycle/restore policy later.

## Structural notes

- `SlotLifecycleCoordinator` remains the only Runtime reclaim writer.
- `WebViewPool` remains Runtime teardown/restore mechanism owner.
- `WebViewFactory` remains WebKit configuration mechanism owner.
- `PanelController` / `WebPanelContainerView` own restore presentation, not lifecycle eligibility.
- Attention remains the hard-protection signal for generation.
- diagnostics remain evidence only.
- `RESIDENT_BACKGROUND` is a canonical ownership fact; `FROZEN` is not canonical product truth until a specific scheduling state is proven.
