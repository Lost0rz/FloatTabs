# FloatTabs — Stage 3 Rendering Profile V3 Product Addendum

> **HISTORICAL STAGE DOCUMENT — NOT THE CURRENT v0.1.0 RENDERING SOURCE OF TRUTH**  
> The Stage 3 `pageZoom` fitting model and Stage 3 viewport sizes recorded below were superseded by PR #16 and PR #18. For current Desktop logical-host rendering, viewport presets, and navigation behavior, use `docs/product/FloatTabs_v0.1.0_Release_Baseline.md`. This document remains as accepted Stage 3 history and must not be used to reintroduce the superseded implementation.

> Status: **ACCEPTED STAGE 3 OVERRIDE (HISTORICAL)**  
> Supersedes: `FloatTabs_Stage_3_Rendering_Profile_V2_Addendum.md` where rendering semantics conflict  
> Base: accepted Stage 2 runtime  
> Detailed design: `docs/design/Stage_3_Rendering_Profile_V3.md`  
> Acceptance: `docs/validation/Stage_3_V3_Acceptance.md`

## Why V3 exists

Real-Mac testing rejected the V2 interpretation of Website Mode.

V2 could change browser identity while a narrow FloatTabs window still caused responsive sites to render a narrow/mobile layout. The accepted Stage 3 meaning is:

```text
Website Mode     = actual website layout class requested from the page
Window Size      = visible FloatTabs Web surface only
Browser Identity = compatibility / User-Agent identity
Zoom             = explicit user-controlled zoom
```

These responsibilities are independent.

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

Valid combinations include:

```text
Desktop + 390 × 780
Desktop + 900 × 850
Mobile  + 390 × 780
Mobile  + 900 × 850
```

Changing Website Mode must not resize FloatTabs. Changing Window Size must not change Website Mode.

Automatic identity continues to resolve by Website Mode:

```text
Desktop → macOS Safari compatibility
Mobile  → iPhone Safari compatibility
```

The actual engine remains WebKit for every identity.

## 2. Accepted website-layout fitting model

Stage 3 uses the public WebKit `WKWebView.pageZoom` API for the final mapping between the visible Web surface and the website's requested CSS layout width.

The AppKit/WKWebView geometry remains 1:1 with the real visible surface:

```text
visible FloatTabs Web surface
        ↓  same physical geometry
WebPanelContainerView
        ↓
WKWebView frame = visible Window Size
        ↓
public WKWebView.pageZoom
        ↓
website observes Desktop/Mobile target CSS width
```

Canonical target CSS widths:

```text
Desktop target width = max(1280, visibleWidth)
Mobile target width  = min(390, visibleWidth)
```

The fitting factor is:

```text
websiteLayoutScale = visibleWidth / targetCSSWidth
```

The persisted user Zoom remains an independent product value. Runtime presentation composes both values only at the final WebKit boundary:

```text
effectivePageZoom = websiteLayoutScale × userPageZoom
```

Example:

```text
Visible width: 430
Website Mode: Desktop
Target CSS width: 1280
Stored user Zoom: 100%
Effective pageZoom ≈ 430 / 1280 ≈ 0.336
```

This replaced the earlier parent AppKit logical-host scaling interpretation. Do not reintroduce parent magnification/frame-bounds scaling as the canonical website-layout mechanism.

No private WebKit SPI is used.

## 3. Interaction is part of Website Mode acceptance

Website Mode is not accepted merely because `innerWidth` changes. The fitted page must remain normally interactive.

Required behavior includes:

- links, buttons, menus and media controls clickable at the visual point;
- text input and selection;
- Command+A / Command+C;
- wheel/trackpad scrolling;
- website-owned right-edge interaction;
- native WebKit hit testing.

Controlled tests verified native clicks at `pageZoom < 1`. A prior CI failure was a test race caused by reading the DOM click counter before WebContent had asynchronously processed the click; the test now waits for the observable effect instead of using a fixed sleep.

## 4. Window presets remain visible sizes

```text
Small   390 × 780
Medium  430 × 820
Large   600 × 800
Wide    900 × 850
Custom  >= 320 × 400
```

These values refer only to the visible FloatTabs Web surface.

Device presets remain advanced visible-size shortcuts. They do not silently redefine Website Mode or Browser Identity.

## 5. WebView lifecycle and mode switching

A Website Mode or Browser Identity change rebuilds only the affected Slot when required to apply configuration/identity cleanly.

Window Size, device preset, orientation and user Zoom do not rebuild an otherwise warm Slot.

A rebuilt Slot must:

- retain `WKWebsiteDataStore.default()`;
- preserve cookies/session data;
- preserve other warm Slots;
- preserve Slot order and identity;
- restore an appropriate navigation URL.

The existing rebuild path prefers the current back/forward item's `initialURL`, then visible URL, persisted current URL, and home URL, and uses `reloadIgnoringLocalCacheData` for the rebuilt navigation.

Redirect-sensitive sites may still have site-specific behavior. The observed Sina Desktop → Mobile → Desktop issue is **deferred compatibility work** and is not represented as solved by Stage 3 acceptance.

## 6. Element fullscreen

Each WKWebView configuration enables:

```swift
configuration.preferences.isElementFullscreenEnabled = true
```

Real-Mac acceptance confirmed YouTube can enter and exit video/element fullscreen and return to an interactive FloatTabs panel.

## 7. Stage 3 new-window compatibility fallback

Real-Mac testing showed Bilibili Desktop could receive trusted DOM clicks while link actions appeared to do nothing. The confirmed Stage 3 fix handles HTTP/HTTPS navigation actions with `targetFrame == nil` by loading the request in the current Slot.

This restores normal interaction for desktop sites that open ordinary content using a new browsing context.

This is an intentional **Stage 3 compatibility fallback**, not the final V1 navigation architecture. It does not supersede the canonical Product/Architecture policy that ultimately distinguishes:

```text
OAuth/login popup      → temporary child WKWebView when appropriate
same-site popup        → current Slot or child WebView
external/research link → default browser by default
```

That full classification belongs to the next Web Compatibility / Navigation stage and should be centralized rather than expanded ad hoc inside `SlotNavigationObserver`.

## 8. Accepted real-Mac evidence

Stage 3 real-Mac acceptance confirms:

- narrow Desktop remains desktop-class;
- wide Mobile remains mobile-class;
- Bilibili's previous browser-version warning stays absent;
- Bilibili Desktop page interaction works after the new-window fallback;
- Bilibili Mobile remains interactive;
- YouTube ordinary controls work;
- YouTube enters/exits element fullscreen correctly;
- user Zoom remains separate from Website Mode and Window Size;
- the maintained macOS CI lane is green.

Deferred, not claimed as fixed:

- redirect-sensitive Sina Website Mode switching edge case;
- final popup/OAuth/external-link routing policy.

## 9. Stage 0–2 invariants

Stage 3 must not regress:

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

Stage 3 is accepted with the explicitly deferred compatibility items above carried into subsequent work.
