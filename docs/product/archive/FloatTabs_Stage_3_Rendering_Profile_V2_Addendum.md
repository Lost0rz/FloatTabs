# FloatTabs — Stage 3 Rendering Profile V2 Product Addendum

> Status: Canonical Stage 3 product override for PR #4
> Base product spec: `docs/product/FloatTabs_Product_Development_Spec_v0.5.md`
> Detailed interaction/data design: `docs/design/Stage_3_Rendering_Profile_V2.md`
> Acceptance: `docs/validation/Stage_3_Acceptance.md`

This addendum supersedes the Stage 3 rendering-related parts of v0.5, specifically:

- V1 product-goal wording that persists `Browser Compatibility (Safari / Chrome)` and `View Mode (Responsive / Desktop / Mobile)` as the primary user model;
- Section 7 `Rendering Profile`;
- rendering fields in Section 8 `Current Web App Controls`;
- rendering fields/defaults in Section 9 `Add / Edit Web App`.

All unrelated v0.5 product requirements remain in force.

## 1. User model

FloatTabs uses progressive disclosure.

### Default layer

```text
Website Mode
Desktop | Mobile

Window Size
Small | Medium | Large | Wide | Custom

Zoom

Advanced…
```

The default layer is intended for normal browsing and operations users. It must be understandable without knowing what User-Agent, WebKit content mode, DPR, or browser fingerprints are.

Canonical defaults:

```text
Website Mode = Desktop
Browser Identity = Automatic → macOS Safari
Window Size = Medium 430 × 820
Zoom = 100%
```

### Advanced layer

Advanced exposes exact compatibility controls only when requested:

```text
Browser Identity
Device Preset
Orientation
Custom User Agent
Effective Engine
Effective User Agent
```

The engine always remains WKWebView / WebKit.

## 2. Independence rule

The following are independent dimensions:

```text
Website identity
Viewport size
Zoom
```

Therefore all of the following are valid:

```text
Desktop + 390 × 780
Mobile + 900 × 850
Windows Chrome + 430 × 820
iPhone Safari + a wide custom viewport
```

Selecting Desktop must not resize the window.
Selecting Mobile must not resize the window.
Selecting a device preset must not change Browser Identity.
Changing Window Size must not change Browser Identity.

## 3. Website Mode

The simple Website Mode is:

```text
Desktop
Mobile
```

Automatic identity mapping:

```text
Desktop → macOS Safari compatibility identity
Mobile  → iPhone Safari compatibility identity
```

It also selects the matching internal WebKit content mode.

There is no user-facing `Responsive` mode in V2.
A narrow desktop-identity viewport may still trigger the website's own CSS responsive breakpoint; that is expected and does not change the HTTP/browser identity requested from the site.

## 4. Advanced Browser Identity

Supported V2 identities:

```text
Automatic
macOS Safari
macOS Chrome
Windows Chrome
Windows Edge
Linux Chrome
iPhone Safari
iPhone Chrome
Android Chrome
Custom User Agent
```

Exact desktop identities project the simple Website Mode to Desktop.
Exact mobile identities project it to Mobile.
If the user changes Website Mode to the opposite class, a conflicting exact identity returns to Automatic; viewport remains unchanged.

UA generation is centralized in `UserAgentProvider`.
Safari compatibility identity must be a complete Safari-style UA containing `Version/... Safari/...`; native incomplete macOS WKWebView UA is not the advertised Safari identity.

Browser versions are resolved from installed Safari / Chrome / Edge when available, with maintained fallbacks.

## 5. Simple Window Size

The default menu is intentionally small:

```text
Small   390 × 780
Medium  430 × 820
Large   600 × 800
Wide    900 × 850
Custom  >= 320 × 400
```

These are FloatTabs workspace sizes, not claims that a specific physical device is being simulated.

The user-facing width/height always refer to the actual WKWebView viewport and exclude FloatTabs external controls/gutters.

## 6. Advanced Device Presets

Device presets are optional viewport shortcuts for users who need more exact frontend checks.

```text
iPhone SE / Compact   375 × 667
iPhone 16e            390 × 844
iPhone 17 / 17 Pro    402 × 874
iPhone Air            420 × 912
iPhone 17 Pro Max     440 × 956
Android Standard      412 × 924
Android Large         448 × 997
iPad mini             744 × 1133
iPad Air 11"          820 × 1180
iPad Pro 13"         1032 × 1376
```

Foldables are excluded from Stage 3 V2.

Device presets:

- use logical viewport dimensions;
- support Portrait / Landscape by swapping width and height;
- never automatically change Website Mode or Browser Identity;
- become Custom if the user manually resizes away from the preset.

Reference DPR may exist as metadata, but Stage 3 V2 does not claim true DPR/touch/device-fingerprint emulation.

## 7. Current Web App Controls

The current-Slot control surface persists:

```text
Website Mode
Window Size
Zoom
Advanced browser/device settings
```

`Follow preferred Window Size when switching Web Apps` affects automatic resizing on Slot switch only.
Applying a new Window Size to the currently edited Slot is explicit user intent and must take effect regardless of the follow setting.

## 8. Add / Edit Web App

Default Add/Edit stays intentionally lightweight:

```text
Name
URL
Website Mode
Window Size
Zoom
Advanced…

Cancel
Add / Save
```

Exact browser/device options are not mandatory fields.

Normal Add flow should not require choosing a browser model or physical device.

## 9. Persistence and migration

Per-Slot V2 rendering state:

```text
websiteMode
browserIdentity
customUserAgent?
sizePreset
devicePresetID?
orientation
viewportWidth
viewportHeight
zoom
```

The accepted version-1 storage container remains readable.
Original Stage 3 rendering data is migrated without losing current URL, slot order, active slot, viewport size, or zoom.

Legacy mapping:

```text
Safari + Responsive/Desktop → macOS Safari / Desktop
Safari + Mobile             → iPhone Safari / Mobile
Chrome + Responsive/Desktop → macOS Chrome / Desktop
Chrome + Mobile             → iPhone Chrome / Mobile
```

## 10. WebView lifecycle

Rebuild only the affected Slot when effective Website Mode / exact Browser Identity / custom UA changes.

Do not rebuild for:

```text
Window Size
Device Preset
Orientation
Zoom
```

Every rebuilt Slot must continue to use `WKWebsiteDataStore.default()` and restore its current URL.
Other warm Slot WebViews must retain identity/state.

## 11. Explicit Stage 3 V2 non-goals

```text
Foldable / dual-screen simulation
Safe-area / Dynamic Island masking
True DPR emulation
Touch event emulation
CPU/network throttling
Geolocation simulation
GPU/WebGL fingerprint spoofing
Full Chromium Client Hints emulation
Blink/Chromium engine parity
```

Stage 4 OAuth/session work does not begin until Stage 3 V2 passes real-Mac acceptance.
