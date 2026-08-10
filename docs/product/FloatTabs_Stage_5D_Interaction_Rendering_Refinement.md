# FloatTabs Stage 5D — Interaction & Rendering Refinement

Status: automated implementation validation complete; Real-Mac acceptance and final benchmark pending.

## Resize and movement acquisition
- Bottom-right visual grip remains small and is shifted inward toward the Web corner, while its live acquisition view is 40 × 40 pt. The full gap between the grip and the visible Web corner is operational rather than click-through whitespace.
- Transparent pixels inside the FloatTabs window are consumed by the panel shell instead of falling through to the desktop.
- Resize accepts first mouse and keeps an `activeAlways` tracking area. Top/bottom/left movement uses the exact same `PanelPerimeterDragView.dragRects` geometry for cursor discovery and hit testing, including explicit superview→local coordinate conversion.

## Rendering contract
- Website Mode selects WebKit Desktop/Mobile content mode and browser identity.
- Window Size is the real WKWebView/CSS viewport.
- Zoom is the only input to `WKWebView.pageZoom`.
- FloatTabs does not synthesize hidden 1280/390 CSS widths, does not use `WKWebView.magnification`, and does not inject site-specific layout CSS/JavaScript.

## Tab rail
- Resting active and inactive tabs are favicon-only.
- Hover expands the tab and reveals its Web App name; the native tooltip retains the full name when it exceeds the fixed external rail width.
- The animated rainbow frame is one continuous silhouette around the Web surface and the active tab; the active tab no longer draws an independent static outline.
- The presentation-only rainbow layer is above the tab rail, so inactive tabs cannot cover the Web frame. Only the active tab makes the frame detour outward into the rail.
- Favicons are fetched generically from the Web App origin `/favicon.ico`, cached in memory, and fall back to a system globe. The active favicon remains full color; inactive favicons render grayscale/neutral. No third-party favicon service or site-specific mapping is used.

## Tab context menu
Common controls are available directly from the Web App tab and persist through `TabStore`:
- Website Mode
- Window Size
- Zoom
- Residency
- Background Media

`Edit Web App…` is reduced to Name, URL, and low-frequency Browser Identity / compatibility controls. Those controls are fully expanded inline—there is no nested Advanced popover in Edit. Add Web App retains the complete initial rendering form.

## Deferred
Global Settings is a later independent screen (Appearance / Hotkeys / Global / About). Stage 5D does not build it.

## Automated validation
- Stage 5D construction validation: package resolve PASS, Debug build PASS, full Unit Tests PASS.
- Clean PR validation: Benchmark Tool CI PASS; macOS package-lock check, Debug build and full Unit Tests PASS.

## Real-Mac acceptance before benchmark
1. Resize an inactive FloatTabs panel from another app/full-screen space on the first drag; verify no dead corner areas.
2. Verify favicon-only resting tabs, hover name reveal, active attached accent, inactive sticky-note presentation, context menu, drag reorder, +, gear and Pin.
3. Verify right-click Website Mode / Window Size / Zoom apply immediately and survive restart; Edit remains low-frequency; Add remains complete.
4. Verify Google Desktop 100%, Bilibili Mobile, and ChatGPT Desktop/Mobile no longer show synthetic-scale typography/cropping; verify native clicking at 50/100/150/200% zoom.
5. Re-run Stage 5C summon/Pin/Hot-state and background-audio regressions.
6. Only after acceptance run the automated Stage 5B benchmark against the previous baseline.
