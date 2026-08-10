# FloatTabs Stage 5D — Interaction & Rendering Refinement

Status: automated implementation validation complete; revised Real-Mac acceptance and final benchmark pending.

## Resize and movement acquisition
- Bottom-right resize is a single 40 × 40 pt acquisition target placed fully **inside the visible Web corner**. The three diagonal grip lines are drawn inside that same target; FloatTabs no longer relies on the transparent outer gutter for this precision interaction.
- Resize accepts first mouse and keeps an `activeAlways` tracking area, so an inactive panel can be acquired without a preliminary activation click.
- Top/bottom movement uses a 22 pt acquisition band: 12 pt shell gutter plus 10 pt inside the visible Web edge. This intentionally gives real pointer use more in-page tolerance than the earlier 4 pt overlap.
- Cursor discovery and actual movement hit testing use the exact same `PanelPerimeterDragView.dragRects` geometry, including explicit superview→local coordinate conversion.
- The bottom movement band excludes the complete internal resize target, and the website right edge remains protected from the movement layer.
- Transparent pixels that are still inside the FloatTabs window remain owned by the panel shell instead of falling through to the desktop.

## Rendering contract
- Website Mode selects WebKit Desktop/Mobile content mode and browser identity.
- Window Size is the real WKWebView/CSS viewport.
- Zoom is the only input to `WKWebView.pageZoom`.
- FloatTabs does not synthesize hidden 1280/390 CSS widths, does not use `WKWebView.magnification`, and does not inject site-specific layout CSS/JavaScript.
- The latest Real-Mac verification reported Desktop/Mobile behavior working; the interaction follow-up does not change this rendering path.

## Tab rail
- Resting active and inactive tabs are favicon-only.
- Hover expands the tab and reveals its Web App name; the native tooltip retains the full name when it exceeds the fixed external rail width.
- Hover ownership is centralized in `ExternalControlZoneView`, allowing the rail to explicitly clear stale child hover state after animated geometry changes rather than depending only on child tracking-area exit timing.
- The animated rainbow frame is one continuous silhouette around the Web surface and the active tab; the active tab remains attached to the page-side seam.
- Inactive tabs stop at the animated outline seam rather than protruding through it.
- Add, Settings and Pin are treated as members of the same rail: 40 × 32 pt resting geometry, 76 pt hover width, the same non-active outline seam, and a flat page-side edge instead of an independent fully rounded pill.
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
- Revised Stage 5D Real-Mac follow-up helper: package resolve PASS, package lock unchanged, Debug build PASS, focused `ExternalShellTests` PASS, full Unit Tests PASS.
- Clean PR validation before this documentation-only commit: Benchmark Tool CI PASS; macOS package-lock check, Debug build and full Unit Tests PASS.
- Temporary construction workflows and validation trigger were removed after the validated product commit.

## Revised Real-Mac acceptance before benchmark
1. Verify the three diagonal resize lines are visibly inside the Web corner and that the complete in-page corner target resizes on the first drag without desktop click-through.
2. Verify the top and bottom visible edge plus the roughly 10 pt in-page strip reliably move the panel, including while the panel is inactive; clicking those operation areas must not activate the desktop behind FloatTabs.
3. Sweep the pointer quickly across multiple tabs and away from the rail; inactive tabs must collapse promptly and no stale expanded gray tab may remain behind.
4. Verify active/inactive rail geometry: active remains attached to the animated outline; inactive tabs do not protrude beyond the rainbow seam.
5. Verify Add, Settings and Pin use the same rail proportions and appear embedded at the page-side seam rather than as separate rounded pills.
6. Regression-check Desktop/Mobile, tab context menu, drag reorder, Website Mode / Window Size / Zoom persistence, Pin, summon, Hot-state and background audio.
7. Only after acceptance run the automated Stage 5B benchmark against the previous baseline.
