# FloatTabs — Stage 3 Rendering Profile V3 Product Addendum

> Status: Canonical Stage 3 product override after real-Mac V2 rejection
> Supersedes: `FloatTabs_Stage_3_Rendering_Profile_V2_Addendum.md` where rendering semantics conflict
> Base: accepted Stage 2 runtime
> Detailed design: `docs/design/Stage_3_Rendering_Profile_V3.md`
> Acceptance: `docs/validation/Stage_3_V3_Acceptance.md`

## Why V3 exists

Real-Mac testing rejected the V2 interpretation of Website Mode.

V2 successfully changed User-Agent identity, but a narrow FloatTabs window could still trigger a site's responsive/mobile CSS even when Website Mode was Desktop. That does not satisfy the product requirement.

The required meaning is now explicit:

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

These layers have different jobs.

### Website Mode

Controls the website layout viewport/class.

Desktop must continue to receive a desktop-class layout even when FloatTabs is narrow.
Mobile must continue to receive a mobile-class layout even when FloatTabs is wide.

### Window Size

Controls only the visible WKWebView frame inside FloatTabs.

Examples that must be valid:

```text
Desktop website + 390 × 780 FloatTabs window
Desktop website + 900 × 850 FloatTabs window
Mobile website  + 390 × 780 FloatTabs window
Mobile website  + 900 × 850 FloatTabs window
```

Changing Website Mode must not resize FloatTabs.
Changing Window Size must not change Website Mode.

### Browser Identity

Controls the compatibility identity/User-Agent sent to the site. The real engine remains WebKit.

Automatic continues to use the simple mode as its compatibility default:

```text
Desktop → macOS Safari identity
Mobile  → iPhone Safari identity
```

Exact advanced identities remain compatibility identities, not a claim that WebKit becomes Blink/Chromium.

### Zoom

Zoom remains explicit user intent and is applied with `WKWebView.pageZoom`.

Internal layout fitting/scaling must not overwrite or reinterpret the user's stored Zoom value.

## 2. Internal website layout viewport

FloatTabs now has two separate geometries:

```text
Visible Window Size
        ↓
FloatTabs Web surface frame

Website Mode
        ↓
Internal CSS/layout viewport
```

Canonical V3 layout widths:

```text
Desktop: never narrower than 1280 CSS px
Mobile:  never wider than 390 CSS px
```

If the visible window is already wider than the Desktop minimum, Desktop may use that wider width.
If the visible window is narrower than the Mobile maximum, Mobile may use the narrower visible width.

The logical layout height is derived proportionally so AppKit can apply a uniform frame-to-bounds transform without stretching one axis differently from the other.

## 3. Window presets remain visible sizes

The existing simple sizes remain:

```text
Small   390 × 780
Medium  430 × 820
Large   600 × 800
Wide    900 × 850
Custom  >= 320 × 400
```

These values refer to the visible FloatTabs Web surface, not the website's CSS layout width.

Device presets remain advanced visible-size shortcuts in Stage 3 V3. They do not silently redefine Website Mode.

## 4. WebView lifecycle

A Website Mode change still rebuilds only the affected Slot so WebKit content-mode preferences and automatic UA identity are applied cleanly.

Window Size, device preset, orientation and user Zoom must not rebuild an otherwise warm Slot.

Every rebuilt Slot must:

- retain `WKWebsiteDataStore.default()`;
- restore current URL;
- preserve other warm Slots;
- preserve persisted Slot order and identity.

## 5. Bilibili compatibility finding

Real-Mac V2 testing showed that Bilibili can still report a browser-version/compatibility warning even when FloatTabs advertises current-looking identities such as Safari 26.6 or Chrome 151.

Therefore Stage 3 must not claim that this warning is solved merely because the UA version string is current.

The Bilibili warning is a separate WebKit compatibility investigation. V3 must first make Desktop/Mobile layout semantics correct; browser compatibility claims require real-site evidence rather than UA-string tests alone.

## 6. Stage 0–2 invariants

V3 must not regress:

- native-full-screen visibility;
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
