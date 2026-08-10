# FloatTabs Stage 6C — Page Context Menu Contract

Status: implementation plan for Draft PR.

Base: `main @ 820b69439a05260ef7b040a23714f8150fe1878d`.

## 1. Goal

Stage 6C refines the Web App tab context menu into the canonical page/Slot-level control surface. It does not implement Global Settings.

The product boundary is:

```text
Tab context menu
= page / Slot behavior

Global Settings
= FloatTabs application behavior
```

## 2. Context-menu contract

Keep these page-level controls directly accessible from a Web App tab right click:

```text
Return to Home
Reload
────────────
Website Mode
Window Size
Zoom
────────────
Residency
Background Media
────────────
Edit Web App…
────────────
Remove Web App…
```

### Rendering controls

Website Mode, Window Size, and Zoom remain in the context menu because they are frequent per-page adjustments. They remain independent dimensions of the existing `WebRenderingProfile`.

Browser Identity, Device Preset, Orientation, and Custom User Agent remain under `Edit Web App…`; Stage 6C does not expand the context menu with those lower-frequency compatibility controls.

### Resource controls

Residency and Background Media remain per-Slot controls and remain in the context menu. Stage 6C does not change lifecycle behavior.

Accepted Stage 5 lifecycle contract:

- Hot: strict resident runtime; no proactive eviction.
- Warm: 120-second inactive TTL, max 2 inactive non-media-protected runtimes, LRU/memory-pressure eviction.
- Cold: 30-second inactive grace, then release live WKWebView runtime.
- Selected + hidden: 120-second recent-active grace before the selected Slot follows its own Residency policy.
- Warm/Cold release is protected while WebKit reports media actually playing; a fresh policy timer starts after playback stops.

## 3. Shortcut presentation

Native macOS menu shortcut presentation is the source of truth for context-menu hints. Use `NSMenuItem.keyEquivalent` and `keyEquivalentModifierMask`; do not draw custom shortcut labels in the menu.

Accepted page shortcuts in this stage:

```text
Return to Home    ⌘⇧H
Reload            ⌘R
Zoom In           ⌘+
Zoom Out          ⌘-
Reset Zoom        ⌘0
```

The Zoom submenu may expose the standard zoom commands plus fixed percentage choices. The 100% command must map to the same reset behavior as `⌘0`.

## 4. Command-path rule

Keyboard and menu actions must converge on one business behavior where practical. Do not maintain a second reload implementation only for the menu.

Stage 6C therefore adds a first-class `Reload` app command and routes both `⌘R` and the context-menu Reload item to the same active/target Slot reload behavior.

## 5. Non-goals

This PR must not:

- change the frozen Stage 5D shell geometry, hit areas, tab animation, resize/move behavior, rainbow outline, Pin behavior, Website Mode semantics, Window Size semantics, or Zoom semantics;
- change Hot/Warm/Cold lifecycle timings or media-protection behavior;
- implement the new left-bottom Gear → Global Settings migration;
- implement Appearance, Shortcuts, Account, or Language settings pages;
- redesign Add/Edit Web App;
- add site-specific behavior.

## 6. Source-of-truth cleanup

Stage 5 closeout changed Warm from the older retained/180-second drafts to the accepted 120-second opportunistic cache. Stage 6C must remove stale user-facing/documentation text encountered in the files it touches so later Settings work does not inherit contradictory lifecycle descriptions.

## 7. Validation

Automated gate:

- `git diff --check`;
- Debug build;
- full Unit Tests;
- AppCommand regression coverage for `⌘R`;
- context-menu regression coverage for retained rendering/resource groups and native shortcut bindings.

Real-Mac acceptance after CI:

- right click retains Website Mode / Window Size / Zoom;
- Residency / Background Media still update the selected Slot correctly;
- Return to Home displays `⌘⇧H` and works;
- Reload displays `⌘R` and works both from context menu and keyboard;
- Zoom commands/hints behave consistently;
- Edit / Remove grouping remains clear;
- no Stage 5D or Stage 5E regression.
