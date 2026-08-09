# Stage 3 V3 Acceptance — Website Layout vs Window Size

> Status: **PASSED — DEFERRED COMPATIBILITY ITEMS RECORDED**  
> Scope: Stage 3 V3 rendering correction and real-Mac acceptance  
> Product: `docs/product/FloatTabs_Stage_3_Rendering_Profile_V3_Addendum.md`  
> Design: `docs/design/Stage_3_Rendering_Profile_V3.md`

## Acceptance principle

Website Mode and Window Size must be visibly and technically independent.

A mode switch is accepted only when the requested website layout remains interactive in the same persistent Slot and does not resize FloatTabs.

## Final implementation baseline

The accepted runtime model is:

```text
WKWebView physical frame = visible FloatTabs Web surface

Desktop target CSS width = max(1280, visibleWidth)
Mobile target CSS width  = min(390, visibleWidth)

websiteLayoutScale = visibleWidth / targetCSSWidth
effective pageZoom = websiteLayoutScale × stored user Zoom
```

Public `WKWebView.pageZoom` is the final fitting boundary. AppKit parent-view magnification/frame-bounds scaling is not the canonical Stage 3 website-layout mechanism.

## Automated acceptance

The maintained macOS lane passes:

```text
Resolve Swift packages       PASS
Package lock unchanged       PASS
Debug Build                  PASS
Full Unit Tests              PASS
```

Automated coverage includes:

- canonical rendering-profile defaults and Codable persistence;
- Website Mode / visible Window Size independence;
- 430 px visible Desktop surface → approximately 1280 CSS px;
- 900 px visible Mobile surface → approximately 390 CSS px;
- fitting-factor recomputation on visible resize;
- stored user Zoom composed independently at the pageZoom boundary;
- browser identity generation and preferred-content-mode mapping;
- WebKit element fullscreen enabled before creation;
- mode/identity rebuild isolation and persistent website data;
- original request URL preference for rebuilds;
- transient scroll-bar and Quick URL regressions;
- native click delivery at pageZoom < 1;
- asynchronous native-click test stabilization via observable-state polling;
- `targetFrame == nil` HTTP/HTTPS current-slot compatibility fallback;
- Stage 0–2 test suite.

## Real-Mac acceptance

### 1. Narrow Desktop

Configuration:

```text
Website Mode = Desktop
Window Size = Medium 430 × 820
Zoom = 100%
```

Result: **PASS**.

The site remains desktop-class while the visible FloatTabs Web surface remains the selected narrow size.

### 2. Wide Mobile

Configuration:

```text
Website Mode = Mobile
Window Size = Wide 900 × 850
Zoom = 100%
```

Result: **PASS** for the accepted Website Mode / Window Size separation behavior.

### 3. Window Size and Zoom independence

Result: **PASS** through automated and real-Mac evidence.

Window resizing does not implicitly change Website Mode. User Zoom remains a persisted independent setting and is composed with internal fitting only at runtime.

### 4. Pointer and input regression

Result: **PASS**.

Controlled probes showed:

```text
pageZoom=1.000 + direct mouseDown/up   PASS
pageZoom≈0.336 + direct mouseDown/up   PASS
pageZoom=1.000 + NSWindow.sendEvent    PASS
pageZoom≈0.336 + NSWindow.sendEvent    PASS
```

The earlier failing click XCTest was a test race, not a production pageZoom bug. WebContent handles native mouse delivery asynchronously; the test now waits for the resulting DOM state instead of reading immediately.

### 5. Bilibili Desktop

Result: **PASS**.

Confirmed on real Mac:

- desktop layout is correct;
- previous browser-version warning remains absent;
- playback works;
- hover feedback works;
- page interaction works after the new-window compatibility fallback;
- Mobile mode remains interactive.

Root cause of the apparent inert Desktop links: trusted DOM clicks were delivered, but desktop content could request a new browsing context (`targetFrame == nil`) while FloatTabs had no auxiliary target. Stage 3 routes ordinary HTTP/HTTPS requests of that form into the current Slot.

This is a temporary compatibility fallback, not the final popup/external-link architecture.

### 6. YouTube element fullscreen

Result: **PASS**.

Real-Mac retest confirmed:

- ordinary controls work;
- video/element fullscreen can be entered;
- fullscreen can be exited;
- FloatTabs returns to an interactive panel state.

### 7. Navigation and reload

Result: **PASS** for the Stage 3 rendering scope.

Website Mode survives normal navigation/reload and persistent website data remains shared across required WebView rebuilds.

## Deferred compatibility items

The following are deliberately **not claimed as fixed** and do not block Stage 3 acceptance by current product decision:

### Sina / redirect-sensitive mode switching

Observed edge case:

```text
same Slot: Desktop → Mobile → Desktop
```

may remain sensitive to site redirect/canonical URL behavior.

Status: **DEFERRED**.

Carry this into later web-compatibility work rather than adding more rendering hacks to Stage 3.

### Final popup / external-link / OAuth policy

Current Stage 3 behavior routes HTTP/HTTPS `targetFrame == nil` requests into the current Slot so normal desktop links are not silently dropped.

The canonical V1 architecture still requires a centralized policy that distinguishes:

```text
OAuth/login popup      → temporary child WKWebView when appropriate
same-site popup        → current Slot or child WebView
external/research link → default system browser by default
```

Status: **DEFERRED TO WEB COMPATIBILITY / NAVIGATION STAGE**.

## Stage 0–2 invariants

No accepted regression is recorded for:

- Menu Bar-only lifecycle;
- native-full-screen visibility;
- show/type/hide/focus restore;
- inactive-app first-drag movement;
- movement/resize separation;
- protected right-edge website interaction;
- external Slot / `+` interaction priority;
- persistent Slot identity/order/current URL;
- persistent website data;
- Quick URL and keyboard shortcuts.

## Merge gate

Stage 3 V3 is **accepted for merge**.

Requirements before merge:

1. cleanup commit lands on the Stage 3 branch;
2. maintained macOS CI is green on the cleanup head;
3. PR description reflects the accepted public-pageZoom architecture and deferred items;
4. PR may then be marked Ready and merged.
