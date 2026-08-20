# FloatTabs — Stage 1 Interaction Baseline

> Status: Accepted Stage 1 engineering baseline
> Supplements: `FloatTabs_Technical_Architecture_v1.2.md` and `FloatTabs_UI_Design_System_v1.2.md`
> Purpose: Record the concrete native-window interaction decisions validated during Stage 1 before the Stage 2 external shell is implemented.

## 1. Geometry

User-visible Window Size continues to mean WKWebView viewport size, not total `NSPanel` frame size.

```text
External Control Zone = 76 pt
Default WebView       = 430 × 820 pt
Default Panel         ≈ 506 × 820 pt
Minimum WebView       = 320 × 400 pt
Minimum Panel         = 396 × 400 pt
```

The left control zone is visually transparent and is outside the viewport width.

The visible website rectangle remains zero-padding FloatTabs chrome: no permanent address bar, top tab strip, toolbar or title bar is introduced.

## 2. Window movement

Stage 1 uses a predictable perimeter drag model instead of a hidden single-point drag target.

Accepted metrics:

```text
perimeterDragResizeInset     = 6 pt
perimeterDragBandWidth       = 12 pt
perimeterDragCornerExclusion = 28 pt
```

Semantics:

```text
outermost edge lane
→ reserved for native resize

next inward edge band
→ window movement through NSWindow.performDrag(with:)

corners
→ excluded from drag to preserve diagonal resize
```

All four sides participate.

## 3. Hit-test priority

Required interaction priority:

```text
future visible external controls
(Tab / + / Gear / FT)
        ↑
perimeter movement layer
        ↑
WKWebView / web content
```

The movement layer must return no hit away from its narrow perimeter bands.

The external control zone must not become a conventional invisible sidebar. Blank space without a real control must remain non-interactive/click-through where the platform behavior allows it.

## 4. Website-interaction guardrail

The four-sided perimeter model is an accepted Stage 1 engineering baseline, not permission to sacrifice website usability.

Stage 2/3 must revalidate it against real Web Apps, especially:

- right-edge overlay/visible scrollbars;
- bottom-edge horizontal scrolling controls;
- top-edge website buttons/navigation;
- left-edge site controls;
- tab/control hit regions that overlap the panel perimeter.

If a real website edge interaction conflicts with the movement band, website interaction wins. The implementation should narrow, relocate or remove the conflicting drag band rather than consume website controls.

## 5. Multi-display and frame behavior

First show after process launch:

- restore a valid saved frame on its still-connected display;
- otherwise clamp/fallback to the current valid target display.

Subsequent show/hide summons in the same process:

- follow the current target display behavior established by Stage 0;
- preserve current size while clamping the frame into the target `visibleFrame`.

Persist frame only after the panel has actually been positioned; never persist the implementation-only initial `.zero` origin.

## 6. Stage boundary

Stage 1 intentionally contains only one WKWebView and no real persistent slots.

Stage 2 is responsible for introducing:

- `TabStore`;
- persistent Web App profiles;
- external index tabs;
- `+` Add;
- Edit/Rename/Remove;
- drag reorder;
- `⌘1…⌘9`;
- `⌃Tab` navigation;
- current URL persistence and relaunch restore.

When those controls exist, the external-zone and perimeter interaction rules in this document must be revalidated with real visible controls rather than only the empty Stage 1 shell.
