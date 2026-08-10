# FloatTabs Stage 5D — Interaction & Rendering Refinement

Status: automated implementation validation complete; Real-Mac acceptance and final benchmark pending.

## Resize
- Bottom-right visual grip remains small, but the acquisition view is 32 × 32 pt.
- The resize view accepts first mouse, keeps AppKit frame-based hit testing, and uses an `activeAlways` tracking area so an inactive FloatTabs panel can be acquired on the first drag.

## Rendering contract
- Website Mode selects WebKit Desktop/Mobile content mode and browser identity.
- Window Size is the real WKWebView/CSS viewport.
- Zoom is the only input to `WKWebView.pageZoom`.
- FloatTabs does not synthesize hidden 1280/390 CSS widths, does not use `WKWebView.magnification`, and does not inject site-specific layout CSS/JavaScript.

## Tab rail
- Resting active and inactive tabs are favicon-only.
- Hover expands the tab and reveals its Web App name; the native tooltip retains the full name when it exceeds the fixed external rail width.
- Active presentation uses the app accent seam and an attached open-right-edge silhouette; inactive tabs use a quieter sticky-note silhouette.
- Favicons are fetched generically from the Web App origin `/favicon.ico`, cached in memory, and fall back to a system globe. No third-party favicon service or site-specific mapping is used.
- The active accent is centralized at `ExternalTabVisualPalette.activeAccent` so a future Settings → Appearance screen can replace it without changing tab behavior.

## Tab context menu
Common controls are available directly from the Web App tab and persist through `TabStore`:
- Website Mode
- Window Size
- Zoom
- Residency
- Background Media

`Edit Web App…` is reduced to Name, URL, and advanced Browser Identity / compatibility. Add Web App retains the complete initial rendering form.

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
