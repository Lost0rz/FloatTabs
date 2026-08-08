# Stage 3 V3 Acceptance — Website Layout vs Window Size

> Status: REAL-MAC RETEST REQUIRED
> Scope: Stage 3 V3 correction after V2 real-Mac rejection
> Product: `docs/product/FloatTabs_Stage_3_Rendering_Profile_V3_Addendum.md`
> Design: `docs/design/Stage_3_Rendering_Profile_V3.md`

## Acceptance principle

Website Mode and Window Size must be visibly and technically independent.

A mode switch is not accepted merely because the User-Agent or CSS width changes. The resulting page must also remain fully interactive and reversible in the same Slot.

## Automated acceptance

Required before real-Mac retest:

- Debug build passes;
- full unit tests pass;
- package lock remains unchanged;
- Desktop logical layout width is at least 1280 CSS px for a narrow window;
- Mobile logical layout width is at most 390 CSS px for a wide window;
- the outer visible surface remains the selected Window Size;
- the WKWebView receives the real logical frame corresponding to Website Mode;
- page-observed CSS width matches the logical frame;
- the parent logical host maps visible coordinates into the logical WKWebView coordinate system without `NSScrollView.magnification`;
- user `pageZoom` remains independent from layout fitting;
- WebKit element fullscreen is enabled before WKWebView creation;
- Website Mode/Browser Identity rebuild prefers the original request URL and bypasses local HTTP cache;
- existing WebView lifecycle and Stage 0–2 tests remain green.

## Real-Mac retest

### 1. Narrow Desktop is truly Desktop

Use:

```text
Website Mode = Desktop
Window Size = Medium 430 × 820
Zoom = 100%
```

Pass only if the site renders its desktop-class layout rather than falling into a narrow/mobile responsive layout.

The visible FloatTabs Web area must remain 430 × 820, with no black or unfilled fitting region.

### 2. Wide Mobile is truly Mobile

Use:

```text
Website Mode = Mobile
Window Size = Wide 900 × 850
Zoom = 100%
```

Pass only if the site remains mobile-class even though the visible FloatTabs window is wide.

The visible FloatTabs Web area must remain 900 × 850.

### 3. Reversible mode switching

At a fixed Window Size:

```text
Desktop → Mobile → Desktop
```

must produce reversible website-layout changes without resizing FloatTabs and without deleting/recreating the Slot.

For redirect-sensitive sites, test a page that may move between canonical and mobile/desktop-specific URLs. The new mode must be evaluated from the original request path rather than remaining pinned to the previous redirect target.

### 4. Window Size does not change mode

At fixed Desktop mode:

```text
Small → Medium → Wide → Custom
```

must remain Desktop.

At fixed Mobile mode the same size changes must remain Mobile.

The Web surface must follow each selected visible size rather than leaving stale content dimensions or black space.

### 5. Zoom stays separate

At fixed mode and size:

```text
⌘+
⌘-
⌘0
```

must change user zoom only. It must not silently change Website Mode, Window Size, or logical layout fitting.

### 6. Pointer and input regression

Because V3 presents a real logical WKWebView through a parent logical host, verify on actual sites:

- clicking links targets the correct visual point;
- buttons, menus and media controls respond;
- text input works;
- text selection works;
- Command+A / Command+C work;
- vertical and horizontal scrolling track the pointer correctly;
- website right-edge interaction remains owned by the website.

Bilibili Desktop is a required interaction fixture because an earlier magnified-host build rendered the correct layout but page controls were not reliably clickable.

### 7. YouTube element fullscreen

On YouTube:

- start video playback;
- click the player's fullscreen control;
- verify element/video fullscreen is entered;
- exit fullscreen;
- verify the FloatTabs panel returns correctly and remains interactive;
- repeat after Desktop/Mobile switching.

Failure to enter WebKit element fullscreen is a Stage 3 acceptance failure.

### 8. Navigation and reload

Navigate between pages and reload.

Website Mode must remain stable and idle scroll bars must return to hidden state.

After a Website Mode change, the affected Slot may rebuild, but cookies/session state must remain available through the persistent website data store.

### 9. Browser identity runtime check

For Automatic Desktop/macOS Safari identity, verify the effective page-observed UA contains Safari-compatible `Version/... Safari/...` tokens. Do not require the identity to be stored in `WKWebView.customUserAgent`; the supported Safari path uses native WKWebView UA plus `applicationNameForUserAgent`.

For explicit Chrome/Edge/mobile compatibility identities, verify the selected identity is reflected in the effective UA while the engine remains WebKit.

### 10. Current Bilibili compatibility evidence

The previously observed Bilibili “browser version too low” warning no longer appeared in the latest real-Mac retest and normal playback became available.

This is positive real-site evidence. The next retest must confirm that the warning remains absent after the interaction-host changes; it must not be reintroduced while fixing click behavior.

### 11. Slot persistence

Quit and reopen.

Preserve:

- Website Mode;
- Window Size;
- Zoom;
- Browser Identity;
- current URL;
- active Slot and order.

### 12. Stage 0–2 regression

Recheck:

- native-full-screen Obsidian overlay;
- show/type/hide/focus restore;
- inactive-app first-drag movement;
- bottom-right resize;
- external tabs and current-app controls.

## Required focused fixtures for this revision

Before acceptance, explicitly retest:

```text
Bilibili Desktop
  layout correct + controls clickable + warning stays absent

YouTube
  Desktop/Mobile layout switch + ordinary controls + enter/exit video fullscreen

Sina / redirect-sensitive site
  same Slot: Desktop → Mobile → Desktop
  no delete/recreate workaround
```

## Merge gate

PR #4 remains Draft.

Do not merge and do not begin Stage 4 until this V3 real-Mac acceptance is explicitly approved.
