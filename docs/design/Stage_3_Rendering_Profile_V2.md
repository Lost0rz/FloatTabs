# Stage 3 Rendering Profile V2

> Status: IMPLEMENTED / AUTOMATED VALIDATION PASSED / REAL-MAC ACCEPTANCE REQUIRED
> Canonical product override: `docs/product/FloatTabs_Stage_3_Rendering_Profile_V2_Addendum.md`
> Replaces the original Stage 3 `Browser + View Mode + Window Size` interaction model.
> Stage 0–2 accepted behavior remains invariant.

## Product principle

FloatTabs exposes a simple default workflow and keeps exact browser/device simulation optional.

The four user-facing dimensions are independent:

```text
Website Mode      = whether the site should see a desktop-class or mobile-class identity
Window Size       = actual WKWebView viewport
Browser Identity  = optional exact User-Agent compatibility identity
Zoom              = WKWebView.pageZoom
```

Changing Website Mode must never force Window Size.
Changing Window Size or Device Preset must never force Website Mode or Browser Identity.

The real engine is always:

```text
WKWebView / WebKit
```

Exact Chrome/Edge/Windows/Android choices are compatibility identities, not Blink/Chromium engine replacement.

## Default UI

Add/Edit and Current Web App Controls show only:

```text
Website Mode
[ Desktop | Mobile ]

Window Size
[ Small | Medium | Large | Wide | Custom ]

Zoom
[ 100% ]

Advanced…
```

Defaults:

```text
Website Mode = Desktop
Window Size  = Medium 430 × 820
Zoom         = 100%
Identity     = Automatic → macOS Safari
```

Simple viewport presets:

```text
Small   390 × 780
Medium  430 × 820
Large   600 × 800
Wide    900 × 850
Custom  >= 320 × 400
```

## Advanced UI

`Advanced…` is a transient popover and does not enlarge the default Add/Edit form.

It exposes:

```text
Browser Identity
Device Preset
Orientation
Custom User Agent
Effective Engine
Effective User Agent
```

Browser identities:

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

Automatic mapping:

```text
Desktop → macOS Safari
Mobile  → iPhone Safari
```

If an exact advanced identity has a fixed class, the simple Website Mode reflects it:

```text
Windows Chrome → Desktop
Android Chrome → Mobile
```

If the user later changes simple Website Mode to the opposite class, the conflicting exact identity returns to Automatic. The viewport does not change.

## User-Agent generation

`UserAgentProvider` is the single source of truth.

Safari compatibility identities must use a complete Safari-style UA including `Version/... Safari/...`; FloatTabs must not use the incomplete default macOS WKWebView UA as the advertised Safari identity.

Browser version resolution:

```text
Safari  → installed Safari.app version, fallback 26.0
Chrome  → installed Google Chrome.app version, fallback 150.0.0.0
Edge    → installed Microsoft Edge.app version, fallback 150.0.0.0
```

The installed browser version is read at runtime when available so compatibility identities do not become stale merely because FloatTabs has not been updated recently.

The real engine remains WebKit and the Advanced panel always says so.

## Device presets

Device presets are advanced viewport shortcuts only. They do not change UA automatically.

Foldables are deliberately excluded from V2.

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

Orientation rotates the selected viewport by swapping logical width and height.

Reference DPR is catalog metadata only in Stage 3 V2. FloatTabs does not claim full DPR/touch/device-fingerprint emulation.

If the user manually resizes a Slot after selecting a device preset, the Slot becomes Custom and the device association is cleared.

## Persistence model

Per Slot:

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

The following original Stage 3 fields are no longer the canonical persisted model:

```text
browserCompatibility
contentMode
ViewModeViewportPolicy
```

## Legacy migration

The storage container remains version 1 for compatibility with the accepted Stage 2 data file.

`WebRenderingProfile` decodes both V2 and original Stage 3 JSON.

Legacy mapping:

```text
Safari + Responsive/Desktop → macOS Safari / Desktop
Safari + Mobile             → iPhone Safari / Mobile
Chrome + Responsive/Desktop → macOS Chrome / Desktop
Chrome + Mobile             → iPhone Chrome / Mobile
```

Existing viewport width, viewport height and zoom are preserved exactly subject to the existing minimum clamp and canonical zoom steps.

Exact old preset sizes migrate to the new simple names when possible; other sizes become Custom.

## WebView lifecycle

A WebView rebuild is required only when the effective browser identity / custom UA / effective Website Mode changes.

No rebuild for:

```text
Window Size
Device Preset
Orientation
Zoom
```

Rebuilt WebViews remain isolated to the affected Slot, keep `WKWebsiteDataStore.default()`, and restore the Slot current URL.

## Stage 0–2 invariants

Do not regress:

- native-full-screen overlay behavior;
- show/type/hide/focus restore;
- inactive-app first-drag movement;
- movement cursor / resize separation;
- right Web edge ownership;
- transient scroll bars, including after reload;
- animated single outline without gray halo;
- persistent Slot order/current URL/active Slot;
- one warm WKWebView per Slot unless identity changes require rebuilding it.

## Explicitly out of scope

```text
Foldable / dual-screen simulation
Safe-area / Dynamic Island masking
True DPR emulation
Touch event emulation
Network / CPU throttling
Geolocation
WebGL or GPU fingerprint spoofing
Full Chromium Client Hints emulation
Blink/Chromium engine parity
```

## Remote validation result

The V2 implementation has passed the original macOS CI workflow after the implementation and post-change audit:

```text
Resolve Swift packages       PASS
Package lock unchanged       PASS
Debug Build                  PASS
Full Unit Tests              PASS
```

Automated coverage includes the V2 rendering model, old Stage 3 migration, complete Safari compatibility UA, exact desktop/mobile UA profiles, device preset independence, WebView rebuild isolation, transient scroller reload behavior, Quick URL regression and Stage 0–2 suites.

## Real-Mac acceptance focus

Before PR #4 can merge:

1. Desktop/Mobile switches must be reversible and must change effective UA without changing viewport.
2. Default Desktop UA must be a complete macOS Safari identity and must no longer trigger the known incomplete-WKWebView-UA compatibility path.
3. Advanced Windows Chrome / Android Chrome / iPhone Safari identities must produce visibly different effective UA strings while the engine stays WebKit.
4. Small/Medium/Large/Wide/Custom must work independently of Website Mode.
5. Device presets must fill the expected logical viewport and never change UA automatically.
6. Manual resize after a device preset must become Custom.
7. Legacy Stage 3 Slot data must relaunch without losing URL/order/size/zoom.
8. Quick URL, transient scroll bars and all Stage 0–2 interaction regressions must remain green.
