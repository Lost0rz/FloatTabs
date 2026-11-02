# FloatTabs Domain Map

This file is a **derived navigation map**. It does not replace `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`, accepted current contracts, production source or tests.

## Authority order

1. AGENTS.md, CURRENT_STATUS.md, CURRENT_TASK.md;
2. docs/README.md;
3. current WP2 policy: FloatTabs_Runtime_Lifecycle_Policy_V7.md;
4. WP1 presentation/readiness regression contract: FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md;
5. docs/architecture/README.md;
6. this map for navigation;
7. production source/tests/fresh evidence;
8. older lifecycle/notification contracts and archive material as bounded historical/delivered evidence.

## Domain routes

| Domain | Owns | Primary source / entry points | Current-task boundary |
| --- | --- | --- | --- |
| App Composition | dependency wiring, launch/termination, top-level services | `FloatTabs/App/AppCoordinator.swift`, `AppDelegate.swift`, `FloatTabsApp.swift` | composition only; not lifecycle policy |
| Tabs & Profiles | persistent Slot identity, selection, ordering, Web App / Browser Profile config, `lastUsedAt`, `Automatic | Keep Loaded` preference | `FloatTabs/Tabs/TabStore.swift`, `WebAppProfile.swift`, `BrowserProfile.swift`, `WebRenderingProfile.swift` | persistent truth; does not decide Runtime reclaim |
| Runtime Lifecycle | inactivity/protection policy, normal reclaim policy, system-pressure progression | `FloatTabs/Web/SlotLifecycleCoordinator.swift` | **sole canonical lifecycle writer**; primary owner for WP2/WP4 |
| Web Runtime | WKWebView creation/reuse, Runtime identity, hibernate/restore/release, bridge/observer lifetime | `FloatTabs/Web/WebViewPool.swift`, `SlotNavigationObserver.swift` | Runtime mechanism owner; supports WP1 restore and WP2 reclaim regressions |
| Web Runtime Configuration | supported WKWebView/WKPreferences configuration, rendering/UA | `FloatTabs/Web/WebViewFactory.swift` | mechanism only; WP2 leaves inactive scheduling unchanged; future overrides require separate authority |
| Window / Panel / Restore Presentation | shell visibility, selected-Slot synchronization, deferred materialization, restoring surface, fullscreen hosting | `FloatTabs/Panel/PanelController.swift`, `FloatTabs/Web/WebViewContainer.swift`, `FloatingPanel.swift`, `FullscreenSourceHost.swift` | WP1 restore-first-frame owner; no WP2 reclaim ownership |
| Attention / Generation | ChatGPT generation sensing, native Attention state, liveness fallback | `ChatGPTAttentionBridge.swift`, `WebAttentionCoordinator.swift` | generation protection fact; must remain correct under any background scheduling policy |
| Response / Unread / Notification | assistant semantics, unread truth, native completion projection | `ChatGPTResponseExtraction.swift`, `ChatGPTResponseBridge.swift`, `ChatGPTUnreadResponseCoordinator.swift`, `ChatGPTCompletionNotificationCoordinator.swift` | delivered #193 behavior is a regression boundary; current task does not redesign notification semantics |
| Focus / Input / Commands | native/Web focus, shortcuts, command/event routing | `FloatTabs/Web/WebFocusRouter.swift`, `FloatTabs/Hotkeys/AppCommandController.swift`, `GlobalHotkeyController.swift` | cold/warm restore must not enable focus before exact-current readiness |
| Persistence & Recovery | durable Slot/Profile state, preferences, backup/restore | `ProfileRepository.swift`, `AppPreferencesStore.swift`, `FloatTabsBackupService.swift` | no destructive session/config mutation; new policy persistence only after policy is authorized |
| Diagnostics | diagnostic events, incidents, privacy filtering, long-term observation | `RuntimeDiagnostics.swift`, `RuntimeDiagnosticWriter.swift`, `RuntimeDiagnosticEvent.swift`, `LongTermPerformanceObservationCoordinator.swift` | evidence only; may record bounded WP2 stage/reclaim facts, never policy |
| Website Cache / Storage | re-downloadable website-cache measurement/cleanup | `FloatTabs/Storage/WebsiteCacheCleanupCoordinator.swift`, `WebsiteCacheCleanupService.swift`, `WebsiteCachePolicy.swift` | cache cleanup is not Runtime memory lifecycle |
| Tab Rail / Retention Projection | Automatic/Keep Loaded control, Browser Profile/media projection | `FloatTabs/UI/ExternalTabRail.swift` | preserve current preference semantics during WP2 |
| Global Settings | app settings presentation | `FloatTabs/UI/GlobalSettingsController.swift`, `SettingsInformationArchitecture.swift` | no new lifecycle/memory settings until policy evidence is accepted |

## Current WP1 and WP2 routes

WP1 accepted presentation route remains a regression boundary:

~~~text
nonresident Slot presentation request
→ exact target + restoring ownership
→ visible native Restoring surface
→ exact Runtime materialization/restore
→ exact-current readiness
→ ready Web surface reveal, focus, and readiness-gated acknowledgement
~~~

WP2 policy route:

~~~text
SlotLifecycleCoordinator inactivity/protection facts
→ exact-token Automatic stage plan
→ normal: only unprotected LONG_IDLE Automatic may hibernate
→ warning: oldest eligible IDLE/LONG_IDLE Automatic, progressively
→ critical: oldest eligible inactive Automatic, RECENT may be bypassed
→ revalidate pressure, Runtime identity, preference, and protections after each reclaim
~~~

Keep Loaded / Pinned is never a FloatTabs automatic reclaim candidate. Runtime count is not a policy input. WP1 owns presentation/readiness; WebViewPool remains the Runtime mechanism.

## Current lifecycle policy and pressure route

~~~text
RECENT    <30s       resident under normal; warning protected
IDLE      30–<600s   resident under normal; warning eligible if unprotected Automatic
LONG_IDLE >=600s     normal reclaim eligible if unprotected Automatic
~~~

The 30s boundary is anti-thrash protection. The 600s long-idle threshold is an initial tunable implementation default. Reconcile, activation, deactivation, and presentation do not evict by resident count.

Memory pressure uses the existing signal and SlotLifecycleCoordinator:

- warning: inactive, unprotected Automatic at IDLE or LONG_IDLE only;
- critical: inactive, unprotected Automatic at any stage, including RECENT;
- Keep Loaded / Pinned and every existing hard protection are excluded;
- reclaim oldest-first, one transaction at a time, with fresh-fact revalidation;
- pressure normal cancels pending continuation and does not mass-restore.

Generation/Attention, active media, fullscreen, supplemental visibility, current/visible ownership, and restore/materialization protections remain authoritative. No Runtime-count-derived RAM estimate or aggregate GiB budget is introduced.

## WebKit inactive scheduling route

Current `WebViewFactory` does not set `WKPreferences.inactiveSchedulingPolicy`.

On macOS 14+ the public WebKit default for a WebView not in a window is documented as `suspend`; idle suspended views pause JavaScript/layout, with activity exemptions such as media/loading/interactive work.

Therefore current routing is:

```text
lifecycle decides resident vs hibernate
→ presentation detach may make a resident WebView inactive
→ WebKit owns default scheduling mechanics
```

An explicit `.suspend` / `.throttle` / `.none` override, if ever accepted, belongs to WebView configuration mechanism but must be driven by an accepted lifecycle intent and evidence from a separately authorized phase. It must not become a second state writer.

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

WP2 does not change snapshot or screenshot behavior. Runtime restore continues through the existing exact Browser Profile data store and WP1 presentation/readiness gate.

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

## Current WP2 verification route

1. Multiple resident Automatic Runtime under normal pressure; count-only reconcile causes no reclaim.
2. Exact 29s, 30s, and 600s inactivity boundaries.
3. Normal long-idle reclaim exactly once and stale-token/reactivation safety.
4. Keep Loaded retention through normal, warning, and critical pressure.
5. Warning stage eligibility and critical RECENT bypass.
6. Generation, media, fullscreen, supplemental-visibility, and WP1 restore protections.
7. Progressive continuation cancellation on pressure normalization.
8. WP1 cold restore, A→B→A, focus, unread, and notification regressions.
9. Full XCTest, Debug/Release arm64, native architecture, package lock, exact-head CI/QA DMG, and independent exact-diff/data-safety audit.

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
