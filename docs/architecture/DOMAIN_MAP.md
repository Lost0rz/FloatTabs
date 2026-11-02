# FloatTabs Domain Map

This file is a **derived navigation map**. It does not replace `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`, accepted current contracts, production source or tests.

## Authority order

1. `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`;
2. `docs/README.md`;
3. current task contract: `FloatTabs_Native_Completion_Notification_Reliability_Rich_Preview_Contract_V1.md`;
4. durable lifecycle contracts where they define preserved runtime boundaries;
5. `docs/architecture/README.md`;
6. this map for navigation;
7. production source/tests/fresh evidence;
8. historical Stage/archive material as evidence only.

## Domain routes

| Domain | Owns | Primary source / entry points | Key boundaries |
| --- | --- | --- | --- |
| App Composition | dependency wiring, launch/termination, top-level services | `FloatTabs/App/AppCoordinator.swift`, `AppDelegate.swift`, `FloatTabsApp.swift` | coordinates domains; does not own Tab/Web/Attention truth |
| Tabs & Profiles | Slot identity, selection, ordering, Web App / Browser Profile config, persisted `lastUsedAt`, Runtime retention preference | `FloatTabs/Tabs/TabStore.swift`, `WebAppProfile.swift`, `BrowserProfile.swift`, `WebRenderingProfile.swift` | durable Slot/config state; Runtime lifecycle remains Web-owned |
| Web Runtime | `WKWebView` creation/reuse, Runtime identity, hibernate/restore/release, renderer recovery, bridge lifetime | `FloatTabs/Web/WebViewPool.swift`, `SlotNavigationObserver.swift`, `BrowserProfileDataStoreProvider.swift` | mechanism owner; does not own lifecycle policy or durable product state |
| Runtime Lifecycle | lifecycle execution, inactivity/protection boundaries, system-pressure reclaim | `FloatTabs/Web/SlotLifecycleCoordinator.swift` | sole canonical Runtime lifecycle writer |
| Attention / Generation Sensing | ChatGPT generation sensing, native Attention state, liveness fallback | `ChatGPTAttentionBridge.swift`, `WebAttentionCoordinator.swift` | Generating protects Runtime; notification task must not change detector semantics |
| Response Semantics / Unread | assistant-response DOM semantics, response identity/status, trusted interaction and durable unread handoff | `ChatGPTResponseExtraction.swift`, `ChatGPTResponseBridge.swift`, `ChatGPTUnreadResponseCoordinator.swift`, `UnreadResponseStore.swift` | current task may add one-shot non-persistent preview snapshot; durable unread remains separate truth |
| Native Notification Projection | completion alert settings/auth/submission/replacement and default-action payload parsing | `FloatTabs/App/ChatGPTCompletionNotificationCoordinator.swift` | projection only; may receive Slot name + ephemeral preview; routing payload remains version/kind/slot_id only |
| Window / Panel / Fullscreen | shell visibility, completion handoff, exact-Slot presentation, fullscreen hosting | `FloatTabs/Panel/PanelController.swift`, `FloatingPanel.swift`, `FullscreenSourceHost.swift`, `ScreenPositioning.swift` | presentation truth only; may resolve Slot name/request one-shot preview, but owns no notification-center or Runtime policy |
| Focus / Input / Commands | native/Web focus, shortcuts, commands, click/drag routing | `FloatTabs/Web/WebFocusRouter.swift`, `FloatTabs/Hotkeys/AppCommandController.swift`, `GlobalHotkeyController.swift` | native focus and DOM focus remain distinct; no Runtime ownership |
| Persistence & Recovery | durable Slot/Profile state, app preferences, backups, recovery data | `ProfileRepository.swift`, `AppPreferencesStore.swift`, `FloatTabsBackupService.swift` | current notification task adds no persisted preview/name/history |
| Diagnostics | diagnostic events, incidents, privacy filtering, snapshots, long-term observation | `RuntimeDiagnostics.swift`, `RuntimeDiagnosticWriter.swift`, `RuntimeDiagnosticEvent.swift`, `LongTermPerformanceObservationCoordinator.swift` | evidence only; notification diagnostics may record bounded system-setting enums, never Slot name/preview text |
| Website Cache / Storage | re-downloadable website-cache measurement/cleanup | `FloatTabs/Storage/WebsiteCacheCleanupCoordinator.swift`, `WebsiteCacheCleanupService.swift`, `WebsiteCachePolicy.swift` | cache cleanup is not Runtime cleanup |
| Menu / Status Projection | menu-bar/status projection and entry actions | `FloatTabs/MenuBar/StatusItemController.swift` | projection only |
| Tab Rail / Runtime Retention Controls | Automatic/Keep Loaded projection, Browser Profile/media controls | `FloatTabs/UI/ExternalTabRail.swift` | per-Slot preference only |
| Global Settings | app settings, Browser/Performance/Advanced presentation | `FloatTabs/UI/GlobalSettingsController.swift`, `SettingsInformationArchitecture.swift` | notification task adds no settings UI |

## Current active notification route

```text
ChatGPTAttentionBridge
→ generationStarted / generationFinished
→ WebAttentionCoordinator
→ PanelController completion handoff
→ ChatGPTUnreadResponseCoordinator
→ hidden valid completion becomes durable unread .marked
→ one-shot notification preview snapshot
   ChatGPTResponseExtraction = assistant-root semantics
   ChatGPTResponseBridge     = current WebView/document validity
→ AppCoordinator composition
→ ChatGPTCompletionNotificationCoordinator
   settings/auth preflight
   same-Slot withdrawal/replacement
   system submission
→ macOS notification center
```

Click route:

```text
UNNotificationDefaultActionIdentifier
→ bounded payload parse
→ persistent Slot UUID
→ PanelController.presentSlotFromCompletionNotification(slotID)
→ TabStore exact Slot selection
→ existing presentation/materialization
→ WebViewPool restores Runtime if non-resident
```

A stale/deleted Slot fails closed. Never fall back to the current Slot.

## Notification content/privacy route

Current task target:

```text
notification title
= normalized Slot/Web App display name

notification body
= bounded plain-text latest assistant preview
  OR generic fallback when preview unavailable
```

App-owned routing payload remains:

```text
version
kind
slot_id
```

Do not place Slot name, preview text, prompt, URL, Browser Profile identity, document token, response identity or Runtime identity in `userInfo`.

Do not persist or log Slot name/preview text.

## Notification settings / diagnostics route

`ChatGPTCompletionNotificationCoordinator` remains the only native notification system owner.

It may read public `UNNotificationSettings` through its injected backend and record bounded enum facts for:

- authorization status;
- alert setting;
- alert style;
- Notification Center setting;
- show-previews setting.

System submission success does not prove a visible banner. Focus/DND suppression is not a supported directly-proven app fact and must not be diagnosed as root cause without evidence.

## Current lifecycle truth preserved by the notification task

Merged lifecycle state after Phase 8 re-scope:

```text
Slot persistent configuration
→ runtimeRetentionPreference = Automatic | Keep Loaded
→ WebViewPool owns live Runtime cache
→ SlotLifecycleCoordinator owns lifecycle decisions/execution
→ Phase 6 restores reclaimed Runtime on demand
```

Healthy normal behavior:

```text
Automatic resident target = 2
Automatic inactive release = 30s
```

System pressure:

```text
warning
→ progressively reclaim eligible inactive/unprotected Automatic
→ Keep Loaded preserved

critical
→ Automatic first
→ then inactive/unprotected Keep Loaded

normal
→ cancel pending pressure progression
→ no mass restore
```

Generating remains hard-protected.

## Background-generation route

```text
ChatGPTAttentionBridge
→ event-first generation observation
→ hidden fallback watchdog only while needed
   <30s       = 2s
   30–120s    = 5s
   >=120s     = 10s
→ WebAttentionCoordinator protection
→ SlotLifecycleCoordinator
```

The current notification task may perform one post-completion preview snapshot. It must not add polling or keep a completed Runtime resident solely for preview.

## Deferred aggregate-memory route

The aggregate-memory budget track remains platform-blocked. Do not implement:

- guessed/correlation per-tab memory;
- Runtime-count-as-GiB proxy;
- private WebKit SPI;
- root-only/restricted-entitlement attribution;
- destructive Browser Profile/session reset.

The accepted Phase 8 feasibility report remains the evidence boundary.

## Current verification routes

Notification task focused tests:

- `ChatGPTCompletionNotificationTests.swift` — content, settings/auth, payload, replacement, foreground presentation;
- `ChatGPTResponseExtractionTests.swift` — assistant-only preview semantics/normalization/cap;
- `ChatGPTResponseBridgeTests.swift` — one-shot snapshot identity/invalidation/stale-result rejection;
- `WebAttentionCrossFeatureTests.swift` — hidden `.marked` composition, exact Slot route, non-resident restore, sound/unread regressions;
- diagnostics/privacy regression only if new fields require it.

Broad gate:

- full XCTest;
- Debug arm64;
- Release arm64;
- native arm64 architecture;
- exact scope/ownership/privacy audit;
- literal-head `Build & Test (Apple Silicon arm64)` on `[self-hosted, macOS, ARM64, mac-mini-ci]`;
- QA DMG when triggered;
- independent review;
- final human native-notification acceptance before merge.

## Incident routing

For notification failures classify before mutation:

```text
generation completion detected?
→ hidden/visible presentation classification?
→ durable unread .marked?
→ preview snapshot trusted/fallback?
→ notification settings/auth state?
→ system request submitted?
→ macOS may present banner/list according to system policy
→ default action received?
→ exact Slot route succeeded?
→ Runtime restore/presentation succeeded?
```

Do not equate “no visible banner” with “FloatTabs did not submit”.

## Structural notes

- `SlotLifecycleCoordinator` remains the only Runtime reclaim writer.
- `WebViewPool` remains Runtime mechanism owner.
- `ChatGPTCompletionNotificationCoordinator` remains native notification system owner.
- `ChatGPTResponseBridge` may expose one-shot preview data but does not become notification policy or unread truth.
- `PanelController` may compose current Slot facts but does not own system notification settings/submission.
- diagnostics remain evidence only.
