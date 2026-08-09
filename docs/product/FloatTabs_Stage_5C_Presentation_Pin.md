# FloatTabs Stage 5C — Presentation + Pin

Status: Draft implementation contract for Real-Mac validation.

## 1. Purpose

Stage 5C keeps the accepted Hot / Warm / Cold residency model and adds two targeted behaviors:

1. **Inactive Hot presentation hiding** — keep Hot runtime state resident while hiding inactive Hot presentation.
2. **Panel Auto-hide / Pin** — unpinned panels dismiss on outside interaction; pinned panels remain floating.

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
- When the frontmost application does **not** change but the user clicks outside FloatTabs, an unpinned visible FloatTabs panel also orders out.
- The outside-click path covers the full-screen/same-background-app case where FloatTabs was pinned, then unpinned, while the application behind it remained frontmost the entire time.
- The auto-hide path does not reactivate a previously focused application; the application the user selected remains focused.

Auto-hide therefore uses two signals:

1. `NSWorkspace.didActivateApplicationNotification` for actual frontmost-application changes, including keyboard application switching.
2. `NSEvent.addGlobalMonitorForEvents` for left/right/other mouse-down events delivered to other applications, including clicks into an already-frontmost application.

`NSApplication.didResignActiveNotification` is not used. FloatTabs uses a non-activating floating panel, so app-active state is not a reliable proxy for the user's actual interaction target.

### Pinned

- The existing external control zone exposes `pin` / `pin.fill`.
- Pin is session-only and is not persisted.
- Pinned means another application may become frontmost while FloatTabs remains visible above it.
- `⌘⇧P` remains the app-local Pin toggle.
- The global show/hide command may still explicitly hide a pinned panel.
- Turning Pin OFF does not itself hide FloatTabs; the next outside click or frontmost-application change applies Auto-hide normally.

### Full-screen

Existing all-spaces / full-screen auxiliary behavior remains unchanged. Pin controls persistence, not whether FloatTabs is allowed to appear over a full-screen application.

## 3. Temporary Global Summon Shortcut

Until the Settings redesign introduces a dedicated Hotkeys page, Stage 5C uses this temporary default:

```text
⌘ + `
```

Behavior:

- Hidden → `⌘ + \`` shows FloatTabs.
- Visible → `⌘ + \`` explicitly hides FloatTabs.

The summon shortcut is registered as a hard-coded `KeyboardShortcuts.Shortcut` event stream in Stage 5C. It intentionally does not use the persisted `KeyboardShortcuts.Name("toggleFloatTabs", initial: ...)` path, because earlier builds already stored that Name in `UserDefaults` and changing only the `initial` value does not replace an existing stored shortcut.

This hard-coded default is provisional. A later Settings rebuild will replace it with a dedicated Hotkeys section using user-recordable shortcuts, alongside Appearance, global preferences, About/help, and other application-level settings. That Settings redesign is outside Stage 5C.

Existing app-local direct Slot shortcuts remain:

```text
⌘1 … ⌘9
```

Bare `1 … 9` are not intercepted because WKWebView text fields, forms, search boxes and chat editors must retain normal numeric input.

## 4. Slot Presentation

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

## 5. Background Media Risk Boundary

Presentation hiding may cause a site or WebKit to pause media even when `Background Media = Allow Background Audio`.

Stage 5C does not add site-specific workarounds. Real-Mac acceptance must explicitly check:

- ChatGPT: Hot + Pause When Inactive — return remains immediate and layout-correct.
- YouTube Desktop: Hot + Allow Background Audio — determine whether audio survives inactive Hot host hiding.
- Bilibili: same observation where useful.

If hiding an inactive Hot host breaks an explicitly allowed background-media use case, media policy and presentation policy must be reconciled explicitly rather than masked with autoplay overrides or JavaScript `play()` forcing.

## 6. Non-goals

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

## 7. Acceptance Gates

Automated:

- inactive Hot host remains attached to the same window and preserves its frame;
- inactive Hot host becomes hidden;
- reactivating the same Hot Slot unhides the same host/WebView;
- Pin control and `⌘⇧P` mapping are present;
- frontmost-app Auto-hide requires another process and Pin OFF;
- external-mouse Auto-hide requires panel visible and Pin OFF, with no frontmost-app transition requirement;
- `⌘ + \`` uses the hard-coded KeyboardShortcuts event path rather than the persisted Name/initial path;
- existing Stage 4/5 unit tests remain green.

Real Mac:

1. `⌘ + \`` summons FloatTabs from another application and explicitly hides it when pressed again.
2. Pin OFF: clicking another application makes that app frontmost and FloatTabs disappears.
3. Pin ON: clicking another application leaves FloatTabs visible while the other application remains usable.
4. Same-app regression: while the same full-screen application remains frontmost, turn Pin ON, then OFF, then click that same underlying application; FloatTabs must disappear immediately.
5. `⌘1 … ⌘9` continues to switch Slots while FloatTabs is active.
6. Full-screen auxiliary behavior still works in both Pin states.
7. ChatGPT Hot switch-back remains immediate and scale/layout/input/scroll correct.
8. YouTube Desktop Hot + Allow background-media behavior is observed with inactive Hot presentation hidden.
9. After functional acceptance, rerun the PR #10 benchmark to compare Hot CPU/memory against the previous baseline.
