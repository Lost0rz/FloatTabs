# Native fullscreen baseline diagnostics

Baseline: `dad0ee79e6b70d07e659814aefde6d4f4701e221`.

This branch intentionally changes no fullscreen behavior. It adds passive observation only.

## Non-interference constraints

The diagnostics must not participate in the input or page event path:

- no `NSWindow.sendEvent` override
- no local/global mouse monitor
- no injected JavaScript or `WKScriptMessageHandler`
- no wrapping/replacing `requestFullscreen` or `exitFullscreen`
- no media/fullscreen API calls
- no WKWebView/window hierarchy or geometry mutation
- file writes run on a dedicated background serial queue

## What is recorded

- `WKWebView.fullscreenState` transitions with numbered attempts.
- `WKWebView` frame changes.
- WKWebView superview/window/frame/bounds snapshots.
- AppKit window class/number/frame/screen/key/main/visibility/level/collection behavior.
- app activation, window screen/key/fullscreen notifications, and active Space changes.
- `NSApp.currentEvent` is read only after WebKit reports a fullscreen-state transition.

Log path:

`~/Library/Logs/FloatTabs/fullscreen-baseline-debug.log`

## Failure classification

- `attempt_started`: WebKit entered `.enteringFullscreen`.
- `attempt_succeeded`: WebKit reached `.inFullscreen`.
- `attempt_enter_aborted`: WebKit moved from entering toward exit before reaching fullscreen.
- `attempt_failed`: the attempt returned to `.notInFullscreen` without reaching `.inFullscreen`.

If ordinary page clicking differs from the baseline, this diagnostic build is invalid and must not be used for fullscreen root-cause conclusions.
