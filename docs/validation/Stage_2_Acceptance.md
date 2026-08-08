# Stage 2 Acceptance — Persistent Web App Slots

> Status: ACCEPTED — AUTOMATED VALIDATION + REAL-MAC ACCEPTANCE PASSED
> Scope: Stage 2 — Persistent Web App Slots
> Base: `6d2d48b855f3dcba3c9a4845368413edf98ff29a`
> Accepted: 2026-08-08

## Acceptance decision

Stage 2 is accepted for merge and Stage 3 may begin.

The project owner approved Stage 2 closure after iterative real-Mac validation of the floating-window interaction model, persistent Slot workflow, movement/resize separation, inactive-app first-drag behavior, animated shell outline, and explicitly transient WebView scroll bars. Automated CI also passes on the final Stage 2 tree.

## Scope implemented

Stage 2 introduces the first persistent multi-Web-App runtime while preserving the accepted Stage 0/1 native floating-window architecture.

Implemented scope:

- versioned persistent `WebAppProfile` metadata;
- `@MainActor TabStore` with normalized stable ordering and active-slot repair;
- one stable lazy-created `WKWebView` per warm Slot via `WebViewPool`;
- persistent `WKWebsiteDataStore.default()` for every Slot;
- minimal current-URL observation and relaunch restore;
- left-edge External Index Tabs and `+` Add control;
- Add/Edit/Rename/Remove;
- vertical drag reorder;
- `⌘1…⌘9`, `⌃Tab`, `⌃⇧Tab`, and `⌘T` app-local commands;
- native Empty State when no Slot exists;
- Dock-like proximity magnification for the external tab rail;
- direct global-pointer-delta window movement;
- inactive-app movement hover feedback and first-drag delivery;
- single thin animated multicolor Web-card outline;
- explicitly transient WebView scroll bars;
- bottom-right dedicated resize handle;
- live resize feedback showing Web viewport width × height and W/H ratio.

Stage 3+ rendering behavior, OAuth/popup handling, upload/download, external routing, memory optimization, Global Settings and release work remain intentionally out of scope.

## Final movement / resize interaction model

Native `.resizable` edge handling remains disabled so native edge resizing cannot compete with custom movement acquisition.

Real-Mac testing established these constraints:

1. movement cannot cover the website's right edge because that blocks direct scrollbar dragging;
2. `NSWindow.performDrag(with:)` is not reliable enough for this borderless floating panel;
3. normal cursor rectangles alone are insufficient while another application is active;
4. first-drag from another active application requires non-activating panel semantics.

Final behavior:

```text
12 pt transparent outer gutter above the Web viewport
+ up to 4 pt deliberate top-edge Web overlap
→ 16 pt effective movement target
→ four-way move cursor
→ first click-drag works while another application is frontmost

12 pt transparent outer gutter below the Web viewport
+ up to 4 pt deliberate bottom-edge Web overlap
→ 16 pt effective movement target
→ four-way move cursor
→ first click-drag works while another application is frontmost

76 pt External Zone to the left of the Web viewport
→ real Tab / + controls keep priority
→ blank space can move the window

website center and middle-right edge / scrollbar
→ no FloatTabs movement target
→ right-edge interaction remains reserved for the website

12 pt transparent right utility gutter
→ no middle-right movement target
→ separates the Web edge from the resize corner

single 2.5 pt animated multicolor outline around the Web card
→ presentation only; never participates in hit testing
→ no persistent gray structural border or shell halo

bottom-right 18 × 18 pt striped handle
→ the only resize target
```

Window movement uses global pointer deltas and direct `setFrameOrigin` updates rather than `NSWindow.performDrag(with:)`.

## Final WebView scrollbar behavior

At rest:

```text
hasVerticalScroller = false
hasHorizontalScroller = false
```

This prevents idle AppKit scroll bars from reserving or painting persistent UI regardless of the user's macOS scroll-bar preference.

During active wheel / trackpad scrolling:

```text
vertical delta   → temporarily enable vertical scroller
horizontal delta → temporarily enable horizontal scroller
→ AppKit overlay style + flashScrollers()
→ approximately 0.6 s after scrolling stops, disable both scrollers again
```

The website's right-edge interaction remains WebKit-owned and is never reused as a FloatTabs movement target.

## Automated validation — PASSED

Automated tests cover:

- TabStore add/select/remove/reorder/wrap/keyboard-index correctness;
- continuous normalized order and active-ID repair;
- persistence round-trip, corruption safety and relaunch restore;
- stable/different WebView identities and persistent website data store;
- actual-sized external control hit regions and blank-zone behavior;
- external controls winning over the movement layer;
- native `.resizable` being disabled;
- top/bottom movement geometry and blank External Zone movement;
- website center and right Web edge remaining outside movement/resize overlays;
- direct global-pointer-delta window-origin calculation;
- `.activeAlways` movement hover tracking configuration;
- hit-test-transparent animated outline;
- disabled gray structural border;
- WebView scrollers fully disabled at rest;
- independent vertical/horizontal transient scroller enabling;
- bottom-right resize handle priority;
- exact control-zone/Web-viewport/gutter/resize-handle layout;
- minimum viewport clamping;
- live resize readout formatting;
- Stage 1 frame and multi-display geometry regressions.

Final macOS CI passes Debug Build and Unit Tests.

## Real-Mac acceptance — PASSED

Stage 2 closure was explicitly approved after iterative real-Mac testing. The final accepted behavior includes:

- FloatTabs remains usable above native full-screen applications;
- keyboard selection/copy/input remains functional;
- another application may remain frontmost and the FloatTabs movement frame can be grabbed on the first click-drag without a preliminary activation click;
- four-way cursor feedback identifies movement targets;
- top/bottom and blank-left movement do not take over the website's right edge;
- the right scrollbar remains WebKit-owned;
- the animated multicolor outline is the only persistent shell outline;
- horizontal and vertical AppKit scroll bars are absent while idle and appear only transiently during active scrolling;
- resize remains isolated to the bottom-right striped handle;
- Stage 2 is approved to merge and development may proceed to Stage 3.

Any future regression of full-screen focus behavior, first-drag delivery, right-edge Web interaction, transient scrollbar behavior, Slot identity/state preservation, movement/resize separation, or External Zone control priority should be treated as a release blocker.