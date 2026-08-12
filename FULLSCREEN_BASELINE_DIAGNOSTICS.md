# Native fullscreen baseline diagnostics

Baseline: `dad0ee79e6b70d07e659814aefde6d4f4701e221`.

This branch intentionally changes no fullscreen behavior. It adds observation only.

## What is recorded

- DOM `dblclick`, `fullscreenchange`, `fullscreenerror`, Escape, page show/hide.
- `WKWebView.fullscreenState` transitions with numbered attempts.
- `WKWebView` frame changes, including a call stack when they occur during fullscreen.
- WKWebView superview/window/frame/bounds snapshots.
- AppKit window class/number/frame/screen/key/main/visibility/level/collection behavior.
- app activation, window screen/key/fullscreen notifications, and active Space changes.
- panel pointer/key input and current mouse/main/key-window screen context.

Log path:

`~/Library/Logs/FloatTabs/fullscreen-baseline-debug.log`

## Failure classification

- `attempt_started`: WebKit entered `.enteringFullscreen`.
- `attempt_succeeded`: WebKit reached `.inFullscreen`.
- `attempt_enter_aborted`: WebKit moved from entering toward exit before reaching fullscreen.
- `attempt_failed`: the attempt returned to `.notInFullscreen` without reaching `.inFullscreen`.

The DOM script only observes events. It does not replace or wrap `requestFullscreen`, `exitFullscreen`, Escape, or any WebKit/AppKit fullscreen API.
