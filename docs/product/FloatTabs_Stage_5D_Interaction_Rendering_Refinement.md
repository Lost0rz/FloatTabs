# FloatTabs Stage 5D — Interaction & Rendering Refinement

Status: **FROZEN after Real-Mac acceptance.**

Stage 5D interaction, rendering, resize, movement, tab-rail and editor behavior is now the accepted baseline. Performance work may instrument or optimize resource lifecycle, but must not change these user-visible contracts unless a reproducible regression is found and explicitly reopened.

## Resize and movement acquisition — FROZEN
- Bottom-right resize is a single 40 × 40 pt acquisition target placed fully **inside the visible Web corner**. The three diagonal grip lines are drawn inside that same target; FloatTabs does not rely on the transparent outer gutter for this precision interaction.
- Resize accepts first mouse and keeps an `activeAlways` tracking area, so an inactive panel can be acquired without a preliminary activation click.
- Top/bottom movement uses a 22 pt acquisition band: 12 pt shell gutter plus 10 pt inside the visible Web edge.
- Cursor discovery and actual movement hit testing use the exact same `PanelPerimeterDragView.dragRects` geometry, including explicit superview→local coordinate conversion.
- The bottom movement band excludes the complete internal resize target, and the website right edge remains protected from the movement layer.
- Transparent pixels that are still inside the FloatTabs window remain owned by the panel shell instead of falling through to the desktop.

## Rendering contract — FROZEN
- Website Mode selects WebKit Desktop/Mobile content mode and browser identity.
- Window Size is the real WKWebView/CSS viewport.
- Zoom is the only input to `WKWebView.pageZoom`.
- FloatTabs does not synthesize hidden 1280/390 CSS widths, does not use `WKWebView.magnification`, and does not inject site-specific layout CSS/JavaScript.
- Desktop/Mobile Real-Mac behavior passed the final Stage 5D acceptance.

## Tab rail — FROZEN
- Resting active and inactive tabs are favicon-only.
- Hover expands the tab and reveals its Web App name; the native tooltip retains the full name when it exceeds the fixed external rail width.
- Hover ownership is centralized in `ExternalControlZoneView`, allowing the rail to explicitly clear stale child hover state after animated geometry changes.
- The animated rainbow frame is one continuous silhouette around the Web surface and the active tab; the active tab remains attached to the page-side seam.
- The rainbow outline centerline sits 0.5 pt outside the Web surface with a 2.5 pt stroke, deliberately overlapping the Web edge so no transparent antialiasing hairline remains.
- Inactive tabs stop at the animated outline seam rather than protruding through it.
- Add, Settings and Pin are treated as members of the same rail: 40 × 32 pt resting geometry, 76 pt hover width, the same non-active outline seam, and a flat page-side edge instead of an independent fully rounded pill.
- Favicons are fetched generically from the Web App origin `/favicon.ico`, cached in memory, and fall back to a system globe. The active favicon remains full color; inactive favicons render grayscale/neutral. No third-party favicon service or site-specific mapping is used.

## Tab context menu / editor — FROZEN
Common controls are available directly from the Web App tab and persist through `TabStore`:
- Website Mode
- Window Size
- Zoom
- Residency
- Background Media

`Edit Web App…` is reduced to Name, URL, and low-frequency Browser Identity / compatibility controls. Those controls are fully expanded inline—there is no nested Advanced popover in Edit. Add Web App retains the complete initial rendering form.

## Deferred
Global Settings is a later independent screen (Appearance / Hotkeys / Global / About). Stage 5D does not build it.

## Validation / acceptance record
- Revised Stage 5D Real-Mac follow-up: package resolve PASS, package lock unchanged, Debug build PASS, focused `ExternalShellTests` PASS, full Unit Tests PASS.
- Final clean PR validation before freeze: Benchmark Tool CI PASS; macOS package-lock check, Debug build and full Unit Tests PASS.
- Real-Mac acceptance confirmed resize acquisition, top/bottom movement, transparent-shell safety, tab hover collapse, active/inactive rail geometry, embedded Add/Settings/Pin controls, rainbow/Web seam, and Desktop/Mobile behavior with no remaining reported Stage 5D blocker.
- Temporary construction workflows and validation triggers were removed after the validated product commits.

## Freeze rule
From this point forward, performance work must treat the Stage 5D behavior above as a regression boundary. In particular, resource-lifecycle changes must not alter:

1. resize / movement hit areas or shell click ownership;
2. tab geometry, hover behavior, rainbow outline or Add/Settings/Pin presentation;
3. Website Mode / Window Size / Zoom semantics;
4. Browser Identity behavior or site compatibility fixes already accepted;
5. Pin / summon interaction behavior.

A Stage 5D contract may be reopened only for a reproducible Real-Mac regression, a failing regression test, or a separately reviewed product decision. Performance tuning should otherwise be isolated to lifecycle/resource modules such as `SlotLifecycleCoordinator`, `WebViewPool`, benchmark instrumentation and related tests.
