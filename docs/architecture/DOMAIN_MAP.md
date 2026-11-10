# FloatTabs — Domain and Source Navigation Map

Derived map only: this document identifies FloatTabs Domain responsibilities and code entry points, not task authorization or a separate engineering workflow. See [AGENTS.md](../../AGENTS.md), the [documentation index](../README.md) and [architecture contract index](README.md).

This map names ownership and likely source entry points, not a task-specific WP0/WP1 plan or literal source-head guarantee. Verify paths and tests against the intended PR/commit before work.

## Domain routes

| Domain | Owns | Primary source / entry points | Domain boundary |
| --- | --- | --- | --- |
| App Composition | dependency wiring, launch/termination, top-level services | `FloatTabs/App/AppCoordinator.swift`, `AppDelegate.swift`, `FloatTabsApp.swift` | composition only; not lifecycle policy |
| Tabs & Profiles | persistent Slot identity, selection, ordering, Web App / Browser Profile config, `lastUsedAt`, `Automatic | Keep Loaded` preference | `FloatTabs/Tabs/TabStore.swift`, `WebAppProfile.swift`, `BrowserProfile.swift`, `WebRenderingProfile.swift` | persistent truth; does not decide Runtime reclaim |
| Runtime Lifecycle | inactivity/protection policy, normal reclaim policy, system-pressure progression | `FloatTabs/Web/SlotLifecycleCoordinator.swift` | **sole canonical lifecycle writer**; lifecycle policy entry |
| Web Runtime | WKWebView creation/reuse, Runtime identity, hibernate/restore/release, bridge/observer lifetime | `FloatTabs/Web/WebViewPool.swift`, `SlotNavigationObserver.swift` | mechanism owner; runtime restore/resource evidence route |
| Web Runtime Configuration | supported WKWebView/WKPreferences configuration, rendering/UA | `FloatTabs/Web/WebViewFactory.swift` | mechanism only; any inactive-scheduling override needs accepted evidence and lifecycle intent from coordinator |
| Window / Panel / Restore Presentation | shell visibility, selected-Slot synchronization, deferred materialization, restoring surface, fullscreen hosting | `FloatTabs/Panel/PanelController.swift`, `FloatTabs/Web/WebViewContainer.swift`, `FloatingPanel.swift`, `FullscreenSourceHost.swift` | restore-first-frame route; no reclaim ownership |
| Attention / Generation | ChatGPT generation sensing, native Attention state, liveness fallback | `ChatGPTAttentionBridge.swift`, `WebAttentionCoordinator.swift` | generation protection fact; must remain correct under any background scheduling policy |
| Response / Unread / Notification | assistant semantics, unread truth, native completion projection | `ChatGPTResponseExtraction.swift`, `ChatGPTResponseBridge.swift`, `ChatGPTUnreadResponseCoordinator.swift`, `ChatGPTCompletionNotificationCoordinator.swift` | delivered #193 behavior is a regression boundary; current task does not redesign notification semantics |
| Focus / Input / Commands | native/Web focus, shortcuts, command/event routing | `FloatTabs/Web/WebFocusRouter.swift`, `FloatTabs/Hotkeys/AppCommandController.swift`, `GlobalHotkeyController.swift` | cold/warm restore must not enable focus before exact-current readiness |
| Persistence & Recovery | durable Slot/Profile state, preferences, backup/restore | `ProfileRepository.swift`, `AppPreferencesStore.swift`, `FloatTabsBackupService.swift` | no destructive session/config mutation; new policy persistence only after policy is authorized |
| Diagnostics | diagnostic events, incidents, privacy filtering, long-term observation | `RuntimeDiagnostics.swift`, `RuntimeDiagnosticWriter.swift`, `RuntimeDiagnosticEvent.swift`, `LongTermPerformanceObservationCoordinator.swift` | evidence only; only an authorized task may add narrowly necessary timing events, never policy |
| Website Cache / Storage | re-downloadable website-cache measurement/cleanup | `FloatTabs/Storage/WebsiteCacheCleanupCoordinator.swift`, `WebsiteCacheCleanupService.swift`, `WebsiteCachePolicy.swift` | cache cleanup is not Runtime memory lifecycle |
| Tab Rail / Retention Projection | Automatic/Keep Loaded control, Browser Profile/media projection | `FloatTabs/UI/ExternalTabRail.swift` | retain accepted preference semantics |
| Global Settings | app settings presentation | `FloatTabs/UI/GlobalSettingsController.swift`, `SettingsInformationArchitecture.swift` | no new lifecycle/memory settings without approved policy evidence |

## Canonical runtime and restore flow

```text
PanelController summon/select / notification exact-Slot route
→ selected Slot has exact ready resident Runtime?
   YES → fast reattach/show
   NO  → native Restoring… presentation
          → WebViewPool create/restore with exact Browser Profile
          → current navigation/epoch/readiness verification
          → reveal correct WebView and route focus
```

```text
SlotLifecycleCoordinator → sole lifecycle policy/reclaim writer
WebViewPool → create / hibernate / restore / release mechanism
WebViewFactory → WKWebView supported configuration mechanism
PanelController / WebPanelContainerView → window and presentation ownership
TabStore/Profile repositories → durable user data, never implicit reset
Diagnostics → evidence, not root-cause truth
```

## Memory pressure and background WebKit boundary

Warning/critical reclaim remains progressive for eligible, unprotected inactive Slots. `Automatic | Keep Loaded` are retention preferences, not two sources of runtime policy. A detached but resident WebView follows public system/WebKit inactive-scheduling semantics; macOS 13 needs a supported fallback.

The Phase-8 public-API evidence did **not** prove deterministic app-owned WebContent/GPU attribution. Reject any proposed exact RAM budget based on Runtime count, private SPI, root-only process identifiers or guessed per-Slot helper RSS.

## Persistent and recovery safety

A hibernated Slot may retain bounded **transient** interaction/restore state, then create a fresh exact-profile WebView; it must not persist a snapshot of private site content as product state or clear Browser Profile/session/cookies as routine recovery. `reload/reset/restart fixed it` demonstrates a recovery boundary only.

## Historical route labels

Old `WP0`, `WP1`, `WP2`, `WP4`, `target=2`, `30s`, and optional snapshot investigation statements in previous phase plans are tied to their historical scopes. They are not current implementation authorization, RAM-budget truth, or permanent UX policy. See archived V1–V6 contracts and the accepted V2 restore contract for their evidence context.
