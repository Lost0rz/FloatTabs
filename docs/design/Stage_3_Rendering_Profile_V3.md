# Stage 3 Rendering Profile V3 — Two-Layer Website Layout

> Status: IMPLEMENTED FOR REAL-MAC RETEST
> Product source: `docs/product/FloatTabs_Stage_3_Rendering_Profile_V3_Addendum.md`
> Acceptance: `docs/validation/Stage_3_V3_Acceptance.md`

## 1. Problem found on real Mac

V2 changed the effective UA and WebKit preferred content mode, but the visible WKWebView width was also the CSS layout viewport.

That meant a 430 px FloatTabs window could still cause responsive sites to render a narrow/mobile layout even after choosing Desktop.

V3 separates the physical FloatTabs surface from the website's logical layout viewport.

## 2. Geometry model

```text
visible FloatTabs Web surface
    frame = user Window Size

logicalHostView
    frame  = visible Window Size
    bounds = Website Mode logical size

WKWebView
    frame = Website Mode logical size
    bounds = ordinary frame-sized WebKit bounds
```

The outer container remains the actual on-screen Window Size. The WKWebView itself receives a real logical frame so WebKit and page CSS observe the requested Desktop/Mobile layout width.

The parent `logicalHostView` performs the visual fit through standard AppKit frame/bounds coordinate mapping. The WKWebView is not embedded in a magnified `NSScrollView`, and `FloatTabsWebView` does not apply its own independent bounds transform.

This keeps one presentation transform outside WebKit while preserving a real 1280/390-class WKWebView layout surface.

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

The host uses the corresponding frame/bounds ratio so the logical website surface fills the visible surface without independent X/Y distortion.

## 3. Implementation ownership

`WebsiteLayoutViewport` owns the pure logical-size calculation.

`WebPanelContainerView` is the single owner of Stage 3 viewport presentation:

- `clipView` owns the visible FloatTabs Web surface and clipping;
- `logicalHostView.frame` stays equal to the visible Window Size;
- `logicalHostView.bounds` becomes the logical Website Mode size;
- the WKWebView receives that same real logical size as its frame;
- visible-window resize recomputes both logical size and host coordinate mapping.

`FloatTabsWebView` stores the effective Website Mode and retains WebKit/scroller behavior, but does not independently change its bounds scale.

No private WebKit SPI is used.

## 4. Interaction requirement

A DOM/CSS viewport test is not enough. The presentation host must also preserve real WebKit interaction semantics.

The host therefore avoids `NSScrollView.magnification` around WKWebView. Standard ancestor coordinate conversion must map visible pointer locations into the logical child coordinate system. Real-Mac acceptance includes links, buttons, player controls, text selection, scrolling, and right-edge interaction.

## 5. Zoom separation

Host frame/bounds mapping is internal layout fitting.

User Zoom remains:

```text
WKWebView.pageZoom
```

A stored 100% remains 100% user zoom even when a desktop layout is fitted into a narrow visible window.

Changing Zoom does not change the logical website layout width or host fit ratio.

## 6. WebKit content mode and browser identity

V3 keeps the WebKit preferred content-mode request and User-Agent compatibility layer as additional site signals.

Automatic identity remains:

```text
Desktop → macOS Safari
Mobile  → iPhone Safari
```

For macOS Safari compatibility, FloatTabs keeps the native WKWebView UA path and appends the resolved Safari/WebKit suffix through `applicationNameForUserAgent`. Chrome/Edge/mobile identities remain explicit compatibility UAs. The engine remains WebKit for every identity.

## 7. Element fullscreen

Web content fullscreen is an explicit WebKit capability. `WebViewFactory` enables:

```text
WKWebViewConfiguration.preferences.isElementFullscreenEnabled = true
```

before WKWebView creation.

This is required for sites such as YouTube to request element/video fullscreen through WebKit. Real-Mac acceptance must verify both entering and leaving fullscreen and returning to the FloatTabs panel correctly.

## 8. Website Mode rebuild and redirect handling

Website Mode or Browser Identity changes rebuild only the affected Slot because these settings affect WebKit configuration and request identity.

For a rebuild, FloatTabs chooses the navigation URL in this order:

```text
1. existing back/forward current item's initialURL
2. existing visible URL
3. persisted current URL
4. Slot home URL
```

`initialURL` is preferred so a server redirect from a canonical URL to a mobile/desktop-specific URL does not permanently pin the next Website Mode to the previous variant.

Mode/identity rebuild navigation uses `reloadIgnoringLocalCacheData`, while ordinary initial Slot creation keeps normal protocol cache behavior. Shared `WKWebsiteDataStore.default()` remains unchanged, so cookies and sessions survive the rebuild.

## 9. Expected examples

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

## 10. Automated evidence

The maintained tests verify:

- narrow Desktop: real WKWebView frame and `document.body.clientWidth` are approximately 1280 CSS px;
- wide Mobile: real WKWebView frame and `document.body.clientWidth` are approximately 390 CSS px;
- visible container size remains independent;
- visible-to-logical coordinate conversion remains consistent through the logical host;
- user `pageZoom` remains independent from layout fitting;
- element fullscreen support is enabled before WKWebView creation;
- mode/identity rebuild prefers the original request URL and bypasses local HTTP cache;
- pooled WebViews rebuild only the affected Slot while retaining persistent website data.

## 11. Real-Mac findings and remaining gate

Real-Mac testing has already shown that Bilibili's previous “browser version too low” warning no longer appears and that Bilibili/YouTube visibly change layout between Desktop and Mobile.

The same retest also exposed three remaining acceptance issues that this revision targets:

- Bilibili Desktop controls must remain clickable after logical viewport fitting;
- YouTube element/video fullscreen must enter and exit correctly;
- redirect-sensitive sites such as Sina must switch Desktop → Mobile → Desktop in the same Slot without deleting/recreating it.

These are not considered accepted until the revised build passes real-Mac retest.

## 12. Regression requirements

Retest:

- pointer hit testing and text selection;
- vertical/horizontal scrolling;
- reload/navigation;
- right-edge website interaction;
- transient scrollers;
- page Zoom shortcuts;
- Slot switching and WebView reuse;
- YouTube/video element fullscreen;
- native-full-screen overlay and focus restore.
