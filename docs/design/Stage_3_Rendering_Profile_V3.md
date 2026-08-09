# Stage 3 Rendering Profile V3 — Public WebKit Layout Fitting

> Status: **IMPLEMENTED AND REAL-MAC ACCEPTED**  
> Product source: `docs/product/FloatTabs_Stage_3_Rendering_Profile_V3_Addendum.md`  
> Acceptance: `docs/validation/Stage_3_V3_Acceptance.md`

## 1. Problem found on real Mac

A Website Mode switch must change the website's actual layout class without changing the FloatTabs window size.

The accepted behavior is:

```text
Website Mode = website layout class
Window Size  = visible Web surface
Browser Identity = compatibility identity
Zoom = user preference
```

A narrow Desktop window still needs a desktop CSS layout; a wide Mobile window still needs a mobile CSS layout.

## 2. Final geometry and WebKit model

The current Stage 3 implementation keeps AppKit and WKWebView at the real visible geometry.

```text
visible FloatTabs Web surface
    size = selected Window Size

WebPanelContainerView
    geometry = visible size

WKWebView
    frame = visible size
    bounds = ordinary frame-sized WebKit bounds

WebsiteLayoutViewport
    computes target CSS width + fitting scale

FloatTabsWebView
    effective pageZoom = fitting scale × stored user Zoom
```

Canonical target widths:

```text
Desktop targetCSSWidth = max(1280, visibleWidth)
Mobile targetCSSWidth  = min(390, visibleWidth)
```

Fitting:

```text
websiteLayoutScale = visibleWidth / targetCSSWidth
effectivePageZoom  = websiteLayoutScale × userPageZoom
```

The page therefore observes the requested Desktop/Mobile CSS width while the physical FloatTabs surface remains unchanged.

This is a public WebKit implementation. It does not use private layout SPI, `NSScrollView.magnification`, or an AppKit parent transform as the canonical layout mechanism.

## 3. Ownership

### `WebsiteLayoutViewport`

Owns pure calculations for:

- Desktop minimum CSS width;
- Mobile maximum CSS width;
- target CSS width;
- internal fitting scale.

Its compatibility `logicalSize` hook currently returns the real visible size because AppKit no longer owns website-layout scaling.

### `FloatTabsWebView`

Owns runtime composition of:

```text
Website Mode
stored user Zoom
visible frame width
```

and applies the resulting effective value through public `WKWebView.pageZoom`.

Frame-size changes recompute only the fitting factor; they do not mutate Website Mode or the stored user Zoom.

### `WebPanelContainerView`

Owns visible clipping/presentation and WebView attachment. Under the accepted Stage 3 implementation it remains 1:1 with the visible surface. Historical `logicalHostView` naming is not a license to restore the rejected parent-scaling architecture.

## 4. Interaction requirement

A DOM width assertion is insufficient. Stage 3 requires real interaction to survive layout fitting.

Acceptance covers:

- native mouse clicks;
- links and buttons;
- media controls;
- text input/selection;
- Command+A / Command+C;
- scrolling;
- right-edge website interaction.

Controlled tests established that `pageZoom < 1` does not globally break WebKit native click delivery.

The earlier failing native-click XCTest was a synchronization bug: mouse delivery to WebContent is asynchronous, so the test now polls the resulting DOM state until success/timeout.

## 5. Zoom separation

The persisted product Zoom is never overwritten by internal fitting.

```text
stored user Zoom = user intent
effective pageZoom = internal fit × stored user Zoom
```

`⌘+`, `⌘-`, and `⌘0` change only the stored user Zoom step. They do not change Website Mode or Window Size.

## 6. Browser identity and content mode

Automatic identity remains:

```text
Desktop → macOS Safari
Mobile  → iPhone Safari
```

macOS Safari compatibility uses WKWebView's native UA path plus the resolved Safari/WebKit suffix through `applicationNameForUserAgent`. Chrome/Edge/mobile identities remain explicit compatibility UAs.

`WKWebpagePreferences.preferredContentMode` is still configured as an additional site signal. The rendering engine remains WebKit for all identities.

## 7. Element fullscreen

Before WKWebView creation:

```swift
configuration.preferences.isElementFullscreenEnabled = true
```

Real-Mac acceptance confirms YouTube can enter and exit video/element fullscreen and returns to a usable panel afterward.

## 8. Website Mode rebuild and redirects

Website Mode or Browser Identity changes may rebuild only the affected Slot.

For rebuild navigation, FloatTabs chooses:

```text
1. back/forward current item's initialURL
2. visible URL
3. persisted current URL
4. Slot home URL
```

The rebuild request ignores local HTTP cache while shared persistent website data remains intact.

The observed Sina redirect-sensitive Desktop → Mobile → Desktop case is deferred compatibility work. It is intentionally not treated as a Stage 3 merge blocker.

## 9. Bilibili interaction / new-window compatibility

Bilibili Desktop hover and trusted DOM clicks worked, but ordinary link actions could appear inert because desktop content used a new browsing context while FloatTabs had no window target to receive it.

Stage 3 therefore adds a generic current-slot fallback for HTTP/HTTPS `targetFrame == nil` navigation. Real-Mac testing confirms Bilibili Desktop interaction is restored.

This fallback is deliberately narrower than the final navigation architecture. The next compatibility/navigation stage must centralize classification for OAuth/login popups, same-site popups, and external/research links.

## 10. Automated evidence

Maintained tests cover:

- narrow Desktop → approximately 1280 CSS px;
- wide Mobile → approximately 390 CSS px;
- visible Window Size independence;
- fitting scale composition with stored user Zoom;
- native click delivery at public pageZoom values;
- async click-test synchronization;
- WebKit element fullscreen capability;
- mode/identity rebuild isolation;
- persistent website data;
- targetFrame=nil current-slot compatibility fallback;
- Stage 0–2 regressions.

## 11. Real-Mac result

Accepted:

```text
Bilibili Desktop layout + interaction + playback  PASS
Bilibili browser-version warning                  ABSENT
Bilibili Mobile                                   PASS
YouTube controls                                  PASS
YouTube enter/exit element fullscreen             PASS
```

Deferred:

```text
Sina redirect-sensitive mode-switch edge case
full popup/OAuth/external-link navigation policy
```
