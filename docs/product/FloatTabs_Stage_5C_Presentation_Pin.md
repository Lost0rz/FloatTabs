# FloatTabs Stage 5C — Presentation + Pin

Status: Draft implementation contract for Real-Mac validation.

## 1. Purpose

Stage 5C keeps the accepted Hot / Warm / Cold residency model and adds two targeted behaviors:

1. **Inactive Hot presentation hiding** — keep Hot runtime state resident while hiding inactive Hot presentation.
2. **Panel Auto-hide / Pin** — unpinned panels dismiss when another application becomes frontmost; pinned panels remain floating.

The goal is a lightweight summonable panel that can also become persistent when the user explicitly needs side-by-side reference.

## 2. Panel Visibility Model

Panel visibility and Slot residency are separate concepts.

```text
Panel
├─ Auto-hide (Pin off)
└─ Pinned

Slot Residency
├─ Hot
├─ Warm
└─ Cold
```

### Auto-hide — default

- Pin is OFF on every app launch.
- FloatTabs is summoned with the global shortcut or menu-bar control.
- When another macOS application becomes the frontmost application, an unpinned visible FloatTabs panel orders out.
- The auto-hide path does not reactivate a previously focused application; the application the user selected remains focused.

Auto-hide is driven by `NSWorkspace.didActivateApplicationNotification`, not by `NSApplication.didResignActiveNotification`. FloatTabs uses a non-activating floating panel, so app-active state is not a reliable proxy for the user's actual frontmost-application transition.

### Pinned

- The existing external control zone exposes `pin` / `pin.fill`.
- Pin is session-only and is not persisted.
- Pinned means another application may become frontmost while FloatTabs remains visible above it.
- `⌘⇧P` remains the app-local Pin toggle.
- The global show/hide command may still explicitly hide a pinned panel.

### Full-screen

Existing all-spaces / full-screen auxiliary behavior remains unchanged. Pin controls persistence, not whether FloatTabs is allowed to appear over a full-screen application.

## 3. Temporary Global Summon Shortcut

Until the Settings redesign introduces a dedicated Hotkeys page, Stage 5C uses this temporary default:

```text
⌥ Space
```

Behavior:

- Hidden → `⌥ Space` shows FloatTabs.
- Visible → `⌥ Space` explicitly hides FloatTabs.

This default is intentionally provisional. Existing app-local direct Slot shortcuts remain:

```text
⌘1 … ⌘9
```

Bare `1 … 9` are not intercepted because WKWebView text fields, forms, search boxes and chat editors must retain normal numeric input.

## 4. Deferred Settings Rebuild

The current SwiftUI `Settings` scene is only a placeholder and is **not** rebuilt in Stage 5C.

A later dedicated Settings stage should create an application-level Settings experience separate from per-Slot/Web-App controls. The intended information architecture includes at least:

- **Appearance**;
- **Hotkeys** with user-recordable shortcuts, including global Show/Hide and direct Slot shortcuts;
- **Global behavior/preferences**;
- **About / help / explanatory content**.

Settings should be reachable from normal macOS application entry points, including the application menu / app-name menu, and from an explicit Settings entry in the product shell where appropriate. Per-Slot settings remain separate and should not be conflated with application Settings.

## 5. Slot Presentation

The Active Slot is the only Slot that should be visually presented.

### Active

- Presentation visible.
- Existing WebView/host geometry and Website Mode/Zoom chain remain unchanged.

### Inactive Hot

- Preserve the same independent `WebSlotHostView` and `WKWebView`.
- Preserve the frozen outgoing frame.
- Do not detach or migrate the WebView.
- Do not destroy DOM/session/SPA state.
- Hide only the independent Hot presentation host while inactive.
- On reactivation, unhide the same host and bring it to front.

```text
inactive Hot
→ same host
→ same WKWebView
→ same frame
→ host.isHidden = true
```

### Inactive Warm

Existing accepted behavior remains unchanged: retain the WKWebView in the pool and detach its presentation.

### Inactive Cold

Existing accepted behavior remains unchanged: detach, start the inactivity grace period, then release the runtime after the grace period.

## 6. Background Media Risk Boundary

Presentation hiding may cause a site or WebKit to pause media even when `Background Media = Allow Background Audio`.

Stage 5C does not add site-specific workarounds. Real-Mac acceptance must explicitly check:

- ChatGPT: Hot + Pause When Inactive — return remains immediate and layout-correct.
- YouTube Desktop: Hot + Allow Background Audio — determine whether audio survives inactive Hot host hiding.
- Bilibili: same observation where useful.

If hiding an inactive Hot host breaks an explicitly allowed background-media use case, media policy and presentation policy must be reconciled explicitly rather than masked with autoplay overrides or JavaScript `play()` forcing.

## 7. Non-goals

Stage 5C does not:

- rebuild Settings;
- persist Pin across launches;
- allow user-recordable Hotkeys yet;
- change Hot / Warm / Cold persistence semantics;
- intercept bare number keys;
- change Website Mode, pageZoom, viewport sizing or Slot preferred-size behavior;
- add shared variable-size presentation hosts;
- add site-specific background-media hacks;
- make Safari/Chrome comparison a release blocker.

## 8. Acceptance Gates

Automated:

- inactive Hot host remains attached to the same window and preserves its frame;
- inactive Hot host becomes hidden;
- reactivating the same Hot Slot unhides the same host/WebView;
- Pin control and `⌘⇧P` mapping are present;
- Auto-hide requires a different frontmost process and Pin OFF;
- `⌥ Space` global shortcut compiles;
- existing Stage 4/5 unit tests remain green.

Real Mac:

1. `⌥ Space` summons FloatTabs from another application and explicitly hides it when pressed again.
2. Pin OFF: clicking another application makes that app frontmost and FloatTabs disappears.
3. Pin ON: clicking another application leaves FloatTabs visible while the other app remains usable.
4. `⌘1 … ⌘9` continues to switch Slots while FloatTabs is active.
5. Full-screen auxiliary behavior still works in both Pin states.
6. ChatGPT Hot switch-back remains immediate and scale/layout/input/scroll correct.
7. YouTube Desktop Hot + Allow background-media behavior is observed with inactive Hot presentation hidden.
8. After functional acceptance, rerun the PR #10 benchmark to compare Hot CPU/memory against the previous baseline.
