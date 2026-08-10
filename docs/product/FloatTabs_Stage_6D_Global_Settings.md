# FloatTabs Stage 6D — Global Settings Contract

Status: implementation plan for stacked Draft PR.

Base: `feat/stage-6c-page-context-menu @ 545e99180afb35d52bb995aa5d838b6a4006af4e`.

## 1. Goal

Stage 6D completes the application-level settings entry that Stage 6C intentionally deferred.

The boundary is:

```text
Tab context menu
= page / Slot behavior

Global Settings
= FloatTabs application behavior
```

The left-bottom Gear is no longer a duplicate Current Web App Controls surface. Per-Slot Website Mode / Window Size / Zoom / Residency / Background Media already have canonical page-level entry points in the Slot context menu and Edit Web App.

## 2. Entry contract

Global Settings must open from all three application-level entries:

```text
left-bottom Gear
Menu Bar → Settings…
⌘,
```

All three converge on one `GlobalSettingsController` and one reusable Settings window instance.

Settings is a normal native macOS app window, not:

- an attached sheet over the active Web App;
- an in-page overlay;
- a large browser-style sidebar/dashboard;
- a second copy of per-Slot controls.

The Gear remains in the frozen bottom system group and is available even when no Slot is active.

## 3. Root information architecture

Use a compact native macOS tab/toolbar settings pattern with three roots:

```text
Appearance
Shortcuts
Account & Language
```

### Appearance

Stage 6D implements one real global preference:

```text
Interface Appearance
- System
- Light
- Dark
```

Rules:

- stored in `UserDefaults` through a dedicated preferences store;
- applied immediately to FloatTabs-owned AppKit windows;
- restored on next launch;
- does not inject CSS or change website/WKWebView content appearance;
- does not change frozen shell geometry.

Accent customization is not required in this patch; the existing visual seam remains available for later Appearance work.

### Shortcuts

The Global Show/Hide shortcut becomes user-configurable using the already pinned `KeyboardShortcuts 3.0.1` package and its native Cocoa recorder.

Migration rule:

```text
existing accepted shortcut: ⌘`
→ named stored shortcut
→ initial value remains ⌘`
```

This is a migration of an existing behavior, not a new default introduced into a public app.

The page-local shortcuts remain fixed in Stage 6D and are shown as a read-only reference:

```text
⌘1…⌘9    Select Slot
⌃Tab      Next Slot
⌃⇧Tab     Previous Slot
⌘T        Add Web App
⌘L        Quick URL
⌘⇧H       Return Home
⌘R        Reload
⌘+ / ⌘- / ⌘0  Zoom
⌘⇧P       Pin / Auto-hide
⌘,        Global Settings
```

Do not build a second custom shortcut-recording system.

### Account & Language

Stage 6D must not fabricate features that do not exist.

The page is informational only and states the real V1 boundary:

- FloatTabs V1 is local-only and does not require a cloud account;
- Web App profiles/preferences live on this Mac;
- website login/session data remains in the persistent WebKit data store;
- no per-app language override is implemented in this stage.

There are no fake Sign In, Sync, or Language popups.

## 4. Architecture

Add a dedicated global preferences layer rather than scattering new `UserDefaults` keys through controllers.

```text
AppPreferencesStore
  └─ appearanceMode

GlobalSettingsController
  ├─ Appearance
  ├─ Shortcuts
  └─ Account & Language

AppCoordinator
  ├─ owns GlobalSettingsController
  ├─ routes Gear → Settings
  ├─ routes Menu Bar → Settings
  └─ routes ⌘, → Settings
```

`PanelController` may expose an `onOpenGlobalSettings` callback, but it must not own the Settings window or global preference persistence.

Remove obsolete Current Web App Controls presentation code once Gear no longer uses it.

## 5. Shortcut architecture

Register a named global shortcut:

```text
KeyboardShortcuts.Name.toggleFloatTabs
```

The recorder owns persistence through KeyboardShortcuts. `GlobalHotkeyController` listens to the named shortcut instead of a hard-coded `Shortcut` value.

App-local `⌘,` is a first-class `AppCommand.settings` command. It is allowed whenever FloatTabs is the active application, even if the floating panel itself is hidden and the Settings window is key. Other page commands keep the existing panel-visible gate.

## 6. Menu Bar

Right-click / Control-click menu becomes:

```text
Show / Hide FloatTabs
────────────
Settings…                     ⌘,
────────────
Quit FloatTabs                ⌘Q
```

Left click continues to Show/Hide and is not changed.

## 7. Source-of-truth migration

Stage 6D updates stale documentation that still says:

```text
⚙ = Current Web App / Window Controls
```

to the accepted Stage 6D meaning:

```text
⚙ = Global Settings
```

Per-Slot page controls remain in the Stage 6C context-menu contract.

## 8. Non-goals

This patch must not implement:

- Launch at Login;
- Website Data clearing;
- updater UI;
- account/cloud sync;
- per-app language override/localization migration;
- accent picker;
- lifecycle/resource policy changes;
- rendering semantics changes;
- Stage 5D shell geometry/hit-area changes;
- page-level controls inside Global Settings.

## 9. Validation

Automated gate:

- `git diff --check`;
- package lock unchanged;
- Debug build;
- full Unit Tests;
- `⌘,` command regression;
- Gear remains real visible hit area and is enabled without an active Slot;
- preference persistence/default tests;
- no Stage 5D/5E behavior changes.

Real-Mac acceptance:

1. Gear opens one native Settings window;
2. Gear works with and without an active Slot;
3. Menu Bar → Settings opens the same window;
4. `⌘,` opens/raises the same window;
5. Appearance System/Light/Dark changes FloatTabs chrome immediately and persists after relaunch;
6. Global Show/Hide recorder starts at the existing `⌘`` binding, can be changed, and the new binding works globally;
7. old binding stops triggering after replacement;
8. page shortcuts still work and remain unchanged;
9. Account & Language contains no fake controls;
10. resize/move/tab hover/rainbow seam/Pin/residency behavior remains unchanged.
