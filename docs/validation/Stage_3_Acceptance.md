# Stage 3 Acceptance — Rendering Profiles V2

> Status: AUTOMATED VALIDATION PASSED / REAL-MAC RETEST REQUIRED
> Scope: Stage 3 — Rendering Profiles V2
> Base: Stage 2 accepted merge `18ed3603ec5b718595f13055570297fb3893c989`
> Canonical product override: `docs/product/FloatTabs_Stage_3_Rendering_Profile_V2_Addendum.md`
> Detailed design: `docs/design/Stage_3_Rendering_Profile_V2.md`

## Goal

Stage 3 V2 replaces the original Browser/View Mode coupling with progressive disclosure:

```text
Default
Website Mode + Window Size + Zoom

Advanced
Exact Browser Identity + Device Preset + Orientation + Effective UA
```

The real engine remains WKWebView/WebKit.

## Core independence rule

These dimensions must not force each other:

```text
Website Mode
Window Size / Device Preset
Zoom
```

Required examples:

```text
Desktop + 390 × 780 is valid.
Mobile + 900 × 850 is valid.
Windows Chrome + 430 × 820 is valid.
iPhone Safari + 1024-class custom viewport is valid.
```

No automatic Desktop→wide or Mobile→small resize is permitted.

## Default controls

```text
Website Mode
Desktop | Mobile

Window Size
Small   390 × 780
Medium  430 × 820
Large   600 × 800
Wide    900 × 850
Custom  >= 320 × 400

Zoom
50 60 67 75 80 90 100 110 125 133 150 175 200 %

Advanced…
```

Canonical default:

```text
Website Mode = Desktop
Browser Identity = Automatic → macOS Safari
Window Size = Medium 430 × 820
Zoom = 100%
```

## Advanced Browser Identity

Supported:

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

Requirements:

- `UserAgentProvider` is centralized;
- macOS Safari identity is a complete Safari-style UA containing `Version/... Safari/...` rather than native incomplete WKWebView UA;
- Automatic Desktop resolves to macOS Safari;
- Automatic Mobile resolves to iPhone Safari;
- exact desktop identities project Website Mode to Desktop;
- exact mobile identities project Website Mode to Mobile;
- changing the simple Website Mode to the opposite class resets a conflicting exact identity to Automatic;
- changing identity never changes viewport;
- installed Safari/Chrome/Edge versions are used when available, with maintained fallbacks;
- Windows Edge keeps independent Chrome-compatible and `Edg/...` tokens;
- Advanced visibly states the effective engine is WebKit.

## Advanced Device Presets

Device presets are viewport shortcuts only. They never change browser identity automatically.

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

Requirements:

- orientation swaps logical width/height;
- selecting a device stores its preset ID + orientation + viewport;
- selecting a device does not change Website Mode or Browser Identity;
- manual resize clears device preset association and becomes Custom;
- foldables are out of scope.

## Persistence and migration

V2 persists:

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

The existing version-1 state container remains readable.

Original Stage 3 fields migrate as follows:

```text
Safari + Responsive/Desktop → macOS Safari / Desktop
Safari + Mobile             → iPhone Safari / Mobile
Chrome + Responsive/Desktop → macOS Chrome / Desktop
Chrome + Mobile             → iPhone Chrome / Mobile
```

Viewport and zoom are preserved.

## WebView lifecycle

Rebuild only when effective browser identity / effective Website Mode / custom UA changes.

Do not rebuild for viewport, device preset, orientation or zoom changes.

Any rebuild must:

- affect only that Slot;
- retain `WKWebsiteDataStore.default()`;
- restore current URL;
- preserve other warm Slot WebViews.

## Other Stage 3 behavior retained

- per-Slot `WKWebView.pageZoom`;
- `⌘+`, `⌘-`, `⌘0` and transient Zoom HUD;
- preferred-size follow on Slot switching only;
- explicit Apply to current Slot changes its size regardless of follow preference;
- temporary `⌘L` Quick URL overlay;
- Esc / second `⌘L` / outside click dismiss Quick URL;
- scroll bars hidden at rest and re-hidden after navigation/reload.

## Stage 0–2 invariants

Must remain green:

- Menu Bar-only lifecycle;
- native-full-screen visibility;
- show/type/hide/focus restore;
- inactive-app first-drag movement;
- four-way cursor on movement targets;
- right Web edge / scrollbar ownership;
- animated single color outline without gray halo;
- bottom-right resize handle;
- External Tab / `+` interaction priority;
- stable per-Slot WebView identity unless rendering identity requires rebuild;
- persistent website data;
- current URL/order/active Slot restore;
- reorder + keyboard shortcut mapping.

## Automated acceptance result

Remote implementation and the post-change audit passed the canonical macOS workflow:

```text
Resolve Swift packages       PASS
Package lock unchanged       PASS
Debug Build                  PASS
Full Unit Tests              PASS
```

Automated coverage includes:

- canonical V2 default + Codable round trip;
- simple size presets and minimum clamp;
- Website Mode / viewport independence;
- exact identity projection to simple Website Mode;
- current device preset catalog values;
- device rotation and manual-resize clearing;
- legacy Stage 3 JSON migration at model and repository level;
- complete Safari UA with version token;
- macOS/Windows/Linux Chrome UA generation;
- Windows Edge UA generation with independent compatibility tokens;
- iPhone Safari / iPhone Chrome / Android Chrome generation;
- installed-version normalization + fallback behavior;
- WebKit preferred content mode mapping;
- identity/mode rebuild isolation;
- viewport/device/zoom no-rebuild behavior;
- persistent website data + current URL restore;
- scroll bar reload regression;
- Quick URL regression;
- full Stage 0–2 test suite.

Temporary diagnostic workflow edits used to isolate one test-fixture compile error were fully reverted; `.github/workflows/macos-ci.yml` matches the accepted Stage 2 workflow.

## Real-Mac acceptance after automated validation

1. Existing Slot opens with no data loss after pulling V2.
2. Default Add form is simple: Website Mode, Window Size, Zoom, Advanced only.
3. Desktop ↔ Mobile changes site identity while current Window Size remains unchanged.
4. Bilibili no longer receives the incomplete native WKWebView Safari identity in default Desktop mode.
5. Advanced shows a complete effective UA and `Engine: WebKit`.
6. Windows Chrome / Android Chrome / iPhone Safari can each be selected and retained per Slot.
7. Small/Medium/Large/Wide/Custom work independently from identity.
8. Device presets produce expected logical viewport sizes without changing identity.
9. Orientation works for device presets.
10. Manual resize after device preset becomes Custom.
11. `⌘L` dismisses via Esc, second `⌘L`, and outside click.
12. Reload leaves scroll bars hidden at rest.
13. Zoom shortcuts/HUD remain correct.
14. Quit/reopen preserves V2 profile values, current URL, order and active Slot.
15. Obsidian native-full-screen show/type/hide/focus-restore regression passes.
16. Inactive-app first-drag movement remains correct.

Google `Unusual Traffic` is not an acceptance criterion for UA V2 because that symptom can be driven by network/IP reputation; it should be investigated separately if it persists.

PR #4 remains Draft and Stage 4 must not begin until the real-Mac acceptance above is explicitly approved.
