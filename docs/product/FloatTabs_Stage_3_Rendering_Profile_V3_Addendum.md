# FloatTabs — Stage 3 Rendering Profile V3 Product Addendum

> Status: Canonical Stage 3 product override after real-Mac V2 rejection
> Supersedes: `FloatTabs_Stage_3_Rendering_Profile_V2_Addendum.md` where rendering semantics conflict
> Base: accepted Stage 2 runtime
> Detailed design: `docs/design/Stage_3_Rendering_Profile_V3.md`
> Acceptance: `docs/validation/Stage_3_V3_Acceptance.md`

## Why V3 exists

Real-Mac testing rejected the V2 interpretation of Website Mode.

V2 successfully changed User-Agent identity, but a narrow FloatTabs window could still trigger a site's responsive/mobile CSS even when Website Mode was Desktop. That does not satisfy the product requirement.

The required meaning is explicit:

```text
Website Mode = actual website layout class requested from the page
Window Size  = only the visible FloatTabs Web surface size
Browser Identity = compatibility/User-Agent identity
Zoom = user-controlled page zoom
```

Window Size is not allowed to decide whether the page is Desktop or Mobile.

## 1. Canonical four-layer model

```text
Website Mode
Desktop | Mobile

Window Size
Small | Medium | Large | Wide | Custom

Browser Identity
Automatic | exact advanced identity | custom UA

Zoom
50% ... 200%
```

### Website Mode

Controls the website layout viewport/class.

Desktop must continue to receive a desktop-class layout even when FloatTabs is narrow. Mobile must continue to receive a mobile-class layout even when FloatTabs is wide.

### Window Size

Controls only the visible FloatTabs Web surface.

Examples that must be valid:

```text
Desktop website + 390 × 780 FloatTabs window
Desktop website + 900 × 850 FloatTabs window
Mobile website  + 390 × 780 FloatTabs window
Mobile website  + 900 × 850 FloatTabs window
```

Changing Website Mode must not resize FloatTabs. Changing Window Size must not change Website Mode.

### Browser Identity

Controls the compatibility identity/User-Agent sent to the site. The real engine remains WebKit.

Automatic continues to use Website Mode as its compatibility default:

```text
Desktop → macOS Safari identity
Mobile  → iPhone Safari identity
```

Exact advanced identities remain compatibility identities, not a claim that WebKit becomes Blink/Chromium.

### Zoom

Zoom remains explicit user intent and is applied with `WKWebView.pageZoom`.

Internal layout fitting must not overwrite or reinterpret the user's stored Zoom value.

## 2. Internal website layout viewport

FloatTabs has separate visible and logical geometries:

```text
Visible Window Size
        ↓
WebPanelContainerView / clipView
        ↓
logicalHostView frame = visible size
logicalHostView bounds = logical Website Mode size
        ↓
WKWebView frame = logical Website Mode size
```

Canonical V3 layout widths:

```text
Desktop: never narrower than 1280 CSS px
Mobile:  never wider than 390 CSS px
```

If the visible window is already wider than the Desktop minimum, Desktop may use that wider width. If the visible window is narrower than the Mobile maximum, Mobile may use the narrower visible width.

The logical layout height is derived proportionally. A parent AppKit frame/bounds mapping fits the real logical WKWebView frame into the visible FloatTabs surface. The WKWebView itself remains at ordinary frame-sized bounds and is not wrapped in `NSScrollView.magnification`.

This means WebKit and responsive CSS see the logical Website Mode width while the user still sees the selected Window Size.

## 3. Interaction is part of Website Mode acceptance

Website Mode is not accepted merely because `clientWidth` changes. The fitted page must remain normally interactive.

Desktop/Mobile fitting must preserve:

- clickable links, buttons, menus, and media controls;
- text input and selection;
- wheel/trackpad scrolling;
- website-owned right-edge interaction;
- correct pointer-to-DOM hit testing.

The logical host transform is intentionally outside WKWebView to avoid depending on `NSScrollView.magnification` for WebKit event routing.

## 4. Window presets remain visible sizes

The simple sizes remain:

```text
Small   390 × 780
Medium  430 × 820
Large   600 × 800
Wide    900 × 850
Custom  >= 320 × 400
```

These values refer to the visible FloatTabs Web surface, not the website's CSS layout width.

Device presets remain advanced visible-size shortcuts in Stage 3 V3. They do not silently redefine Website Mode.

## 5. WebView lifecycle and mode switching

A Website Mode or Browser Identity change rebuilds only the affected Slot so WebKit configuration and request identity are applied cleanly.

Window Size, device preset, orientation and user Zoom must not rebuild an otherwise warm Slot.

Every rebuilt Slot must:

- retain `WKWebsiteDataStore.default()`;
- preserve cookies/session data;
- preserve other warm Slots;
- preserve persisted Slot order and identity;
- reload the appropriate page under the new Website Mode rather than remaining pinned to a previous redirect variant.

When rebuilding an existing Slot, FloatTabs prefers the current back/forward item's `initialURL` before the final redirected URL. This allows sites that redirect canonical URLs to mobile/desktop-specific destinations to re-evaluate the new UA/mode. The rebuild request ignores local HTTP cache, but persistent WebKit website data is retained.

For Automatic Desktop identity, FloatTabs uses the native WKWebView UA path plus a resolved Safari/WebKit `applicationNameForUserAgent` suffix. Automatic Mobile and exact compatibility identities may use explicit custom UA strings.

## 6. Element fullscreen

Website media fullscreen is part of normal browser behavior. FloatTabs enables WebKit element fullscreen on each WKWebView configuration before creation.

A site such as YouTube must be able to enter and leave video/element fullscreen, and FloatTabs must return to a usable panel state afterward.

This is separate from FloatTabs itself being visible over another application's native fullscreen Space.

## 7. Automated acceptance evidence

Before real-Mac retest, automated validation must prove:

- a 430 px visible Desktop surface gives the page an approximately 1280 CSS px layout width;
- a 900 px visible Mobile surface gives the page an approximately 390 CSS px layout width;
- resizing the visible surface recomputes fit geometry without changing Website Mode;
- visible-to-logical coordinate conversion remains consistent;
- `WKWebView.pageZoom` remains independent from internal layout fitting;
- element fullscreen support is enabled before WKWebView creation;
- mode/identity rebuild prefers the original request URL and ignores local HTTP cache;
- pooled WebViews rebuild only when required and preserve the correct identity path.

## 8. Current real-Mac evidence

Real-Mac retesting has provided positive evidence that the prior Bilibili “browser version too low” warning no longer appears and that Bilibili and YouTube visibly switch layouts between Desktop and Mobile.

That same retest identified remaining Stage 3 acceptance failures:

- Bilibili Desktop layout rendered correctly but some page controls were not clickable;
- YouTube page interaction worked but video fullscreen could not be entered;
- a Sina site respected its initial Website Mode when the Slot was created, but an existing Slot could not reliably switch Desktop/Mobile without deletion and recreation.

The follow-up implementation targets those three failures. They remain real-Mac acceptance gates until retested.

## 9. Stage 0–2 invariants

V3 must not regress:

- native-full-screen visibility over other apps;
- show/type/hide/focus restore;
- inactive-app first-drag movement;
- movement/resize separation;
- protected website right edge;
- transient scroll bars;
- animated outline;
- persistent Slot identity/order/current URL;
- persistent website data;
- Quick URL and keyboard shortcuts.

Stage 4 remains blocked until V3 real-Mac acceptance passes.
