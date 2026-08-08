# Stage 3 Rendering Profile V3 — Two-Layer Website Layout

> Status: IMPLEMENTED FOR REAL-MAC RETEST
> Product source: `docs/product/FloatTabs_Stage_3_Rendering_Profile_V3_Addendum.md`
> Acceptance: `docs/validation/Stage_3_V3_Acceptance.md`

## 1. Problem found on real Mac

V2 changed the effective UA and WebKit preferred content mode, but the visible WKWebView width was also the CSS layout viewport.

That meant a 430 px FloatTabs window could still cause responsive sites to render a narrow/mobile layout even after choosing Desktop.

The V3 correction separates those geometries.

## 2. Geometry model

```text
visible FloatTabs Web surface
    width = user Window Size
    height = user Window Size

WebPanelContainerView / NSScrollView
    fits the logical website surface into the visible surface

WKWebView real logical frame
    width = Website Mode layout width
    height = proportional logical height
```

The outer container remains the actual on-screen Window Size.
The WKWebView itself receives a real logical frame so WebKit and page CSS observe the requested Desktop/Mobile layout width.

Public `NSScrollView` magnification maps the logical WebView into the visible FloatTabs surface. `FloatTabsWebView` does not apply a second bounds transform.

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

To keep the fit uniform:

```text
scale = logicalWidth / visibleWidth
logicalHeight = visibleHeight × scale
```

The container then uses the inverse fit scale to display that logical surface without independent X/Y distortion.

## 3. Implementation ownership

`WebsiteLayoutViewport` owns the pure logical-size calculation.

`WebPanelContainerView` is the single owner of Stage 3 viewport geometry:

- its visible bounds remain the selected FloatTabs Window Size;
- it sets the WKWebView to the real logical frame calculated for Website Mode;
- it uses public `NSScrollView.magnification` to fit that logical frame into the visible surface;
- it recomputes the logical frame and fit scale when the visible window changes size.

`FloatTabsWebView` stores the effective Website Mode and retains WebKit/scroller behavior, but does not independently alter its own bounds or frame-to-bounds scale.

No private WebKit SPI is used.

## 4. Zoom separation

The container magnification is internal layout fitting.

User Zoom remains:

```text
WKWebView.pageZoom
```

A stored 100% remains 100% user zoom even when the internal desktop layout is being fitted into a narrow visible window.

Changing Zoom does not change the logical website layout width or the container fit scale.

## 5. Existing WebKit content mode and UA

V3 keeps the existing WebKit preferred content-mode request and User-Agent compatibility layer.

These are additional site signals, not substitutes for the internal layout viewport.

Automatic identity remains:

```text
Desktop → macOS Safari
Mobile  → iPhone Safari
```

For macOS Safari compatibility, FloatTabs keeps the native WKWebView UA path and appends the resolved Safari/WebKit suffix through `applicationNameForUserAgent`. Chrome/Edge/mobile identities remain explicit compatibility UAs. The engine remains WebKit for every identity.

## 6. Expected examples

### Narrow Desktop

```text
Window Size: 430 × 820
Website Mode: Desktop
visible surface width: 430
WKWebView logical/CSS width: 1280
```

### Wide Mobile

```text
Window Size: 900 × 850
Website Mode: Mobile
visible surface width: 900
WKWebView logical/CSS width: 390
```

Switching between those modes does not alter the stored Window Size.

## 7. Automated evidence

The maintained tests verify both geometry and actual WebKit-observed page width:

- narrow Desktop: real WKWebView logical frame is 1280 CSS px and `document.body.clientWidth` is approximately 1280;
- wide Mobile: real WKWebView logical frame is 390 CSS px and `document.body.clientWidth` is approximately 390;
- visible container size remains independent;
- visible-to-logical pointer coordinate conversion remains consistent;
- user `pageZoom` remains independent from internal fit magnification;
- Desktop Safari runtime identity is validated from page-observed `navigator.userAgent`, not from unstable internal storage of `customUserAgent`.

## 8. Known compatibility boundary

A current-looking Safari/Chrome UA does not guarantee that a site accepts WKWebView as that browser.

The Bilibili browser-version warning observed on real Mac remains a separate compatibility investigation and must not be marked solved solely from UA generation tests.

## 9. Regression requirements

The logical viewport host must be retested for:

- pointer hit testing and text selection;
- vertical/horizontal scrolling;
- reload/navigation;
- right-edge website interaction;
- transient scrollers;
- page Zoom shortcuts;
- slot switching and WebView reuse;
- native-full-screen overlay and focus restore.
