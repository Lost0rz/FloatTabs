# Stage 3 Rendering Profile V3 — Two-Layer Website Layout

> Status: IMPLEMENTED FOR RETEST / CI REQUIRED
> Product source: `docs/product/FloatTabs_Stage_3_Rendering_Profile_V3_Addendum.md`
> Acceptance: `docs/validation/Stage_3_V3_Acceptance.md`

## 1. Problem found on real Mac

V2 changed the effective UA and WebKit preferred content mode, but the visible WKWebView frame was also the CSS layout viewport.

That meant a 430 px FloatTabs window could still cause responsive sites to render a narrow/mobile layout even after choosing Desktop.

The V3 correction separates those geometries.

## 2. Geometry model

```text
visible FloatTabs Web frame
    width = user Window Size
    height = user Window Size

WKWebView logical bounds
    width = Website Mode layout width
    height = proportional logical height
```

The frame remains the actual on-screen size.
The bounds become the website's logical coordinate system.

AppKit maps frame coordinates and bounds coordinates with its public view-coordinate transform.

### Desktop

```text
logicalWidth = max(1280, visibleWidth)
```

A 430 px visible window therefore still exposes a desktop-class logical width.

### Mobile

```text
logicalWidth = min(390, visibleWidth)
```

A 900 px visible window therefore still exposes a phone-class logical width.

### Logical height

To keep the transform uniform:

```text
scale = logicalWidth / visibleWidth
logicalHeight = visibleHeight × scale
```

This preserves aspect ratio and avoids independent X/Y distortion.

## 3. Implementation location

`WebsiteLayoutViewport` owns the pure geometry calculation.

`FloatTabsWebView` owns the frame/bounds bridge:

- Auto Layout continues to size its `frame` to the visible FloatTabs Web surface;
- `setFrameSize` recomputes logical bounds whenever the window changes size;
- `setWebsiteMode` reapplies the appropriate logical website layout width;
- `viewDidMoveToWindow` reasserts layout and transient-scroller state.

No private API is used.

## 4. Zoom separation

The internal frame↔bounds transform is layout fitting.

User Zoom remains:

```text
WKWebView.pageZoom
```

A stored 100% remains 100% user zoom even when the internal desktop layout is being fitted into a narrow visible window.

Changing Zoom does not change the logical website layout width.

## 5. Existing WebKit content mode and UA

V3 keeps the existing WebKit preferred content-mode request and User-Agent generation.

These are additional site signals, not substitutes for the internal layout viewport.

Automatic identity remains:

```text
Desktop → macOS Safari
Mobile  → iPhone Safari
```

The engine remains WebKit for every identity.

## 6. Expected examples

### Narrow Desktop

```text
Window Size: 430 × 820
Website Mode: Desktop
visible frame width: 430
logical CSS/layout width: 1280
```

### Wide Mobile

```text
Window Size: 900 × 850
Website Mode: Mobile
visible frame width: 900
logical CSS/layout width: 390
```

Switching between those modes does not alter the stored Window Size.

## 7. Known compatibility boundary

A current-looking Safari/Chrome UA does not guarantee that a site accepts WKWebView as that browser.

The Bilibili browser-version warning observed on real Mac remains a separate compatibility investigation and must not be marked solved solely from UA generation tests.

## 8. Regression requirements

The new bounds transform must be retested for:

- pointer hit testing and text selection;
- vertical/horizontal scrolling;
- reload/navigation;
- right-edge website interaction;
- transient scrollers;
- page Zoom shortcuts;
- slot switching and WebView reuse;
- native-full-screen overlay and focus restore.
