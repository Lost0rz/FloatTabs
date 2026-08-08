# Stage 3 V3 Acceptance — Website Layout vs Window Size

> Status: RETEST REQUIRED
> Scope: Stage 3 V3 correction after V2 real-Mac rejection
> Product: `docs/product/FloatTabs_Stage_3_Rendering_Profile_V3_Addendum.md`
> Design: `docs/design/Stage_3_Rendering_Profile_V3.md`

## Acceptance principle

Website Mode and Window Size must be visibly and technically independent.

A mode switch is not accepted merely because the User-Agent string changes.

## Automated acceptance

Required before real-Mac retest:

- Debug build passes;
- full unit tests pass;
- package lock remains unchanged;
- Desktop logical layout width is at least 1280 CSS px for a narrow window;
- Mobile logical layout width is at most 390 CSS px for a wide window;
- frame size remains the selected visible Window Size;
- user `pageZoom` remains independent from layout fitting;
- existing WebView lifecycle and Stage 0–2 tests remain green.

## Real-Mac retest

### 1. Narrow Desktop is truly Desktop

Use the same test site and set:

```text
Website Mode = Desktop
Window Size = Medium 430 × 820
Zoom = 100%
```

Pass only if the site renders its desktop-class layout rather than simply falling into its narrow/mobile responsive layout.

The visible FloatTabs Web area must remain 430 × 820.

### 2. Wide Mobile is truly Mobile

Set:

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

must produce reversible website-layout changes without resizing FloatTabs.

### 4. Window Size does not change mode

At fixed Desktop mode:

```text
Small → Medium → Wide → Custom
```

must remain Desktop.

At fixed Mobile mode the same size changes must remain Mobile.

### 5. Zoom stays separate

At fixed mode and size:

```text
⌘+
⌘-
⌘0
```

must change user zoom only. It must not silently change Website Mode or Window Size.

### 6. Pointer and input regression

Because V3 uses a logical bounds transform, verify:

- clicking links targets the correct visual point;
- text input works;
- text selection works;
- Command+A / Command+C work;
- vertical and horizontal scrolling track the pointer correctly;
- website right-edge interaction remains owned by the website.

### 7. Navigation and reload

Navigate between pages and reload.

Website Mode must remain stable and idle scroll bars must return to hidden state.

### 8. Slot persistence

Quit and reopen.

Preserve:

- Website Mode;
- Window Size;
- Zoom;
- Browser Identity;
- current URL;
- active Slot and order.

### 9. Stage 0–2 regression

Recheck:

- native-full-screen Obsidian overlay;
- show/type/hide/focus restore;
- inactive-app first-drag movement;
- bottom-right resize;
- external tabs and current-app controls.

## Bilibili compatibility status

The previously observed Bilibili “browser version too low” warning is **not considered fixed** by V3 merely because Safari/Chrome UA versions are current.

Record it separately during retest. If it persists after Desktop/Mobile layout is correct, continue as a WebKit compatibility investigation rather than changing version numbers blindly.

## Merge gate

PR #4 remains Draft.

Do not merge and do not begin Stage 4 until this V3 real-Mac acceptance is explicitly approved.
