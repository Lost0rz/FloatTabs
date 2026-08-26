# FloatTabs Pending Fixes — 2026-08-26

This log records fixes that are intentionally left in the working tree for
later combined acceptance and merge. It is not a release note and does not
mean the changes have been merged.

## Host application enters full screen while FloatTabs is already visible

### Symptom

After FloatTabs opened a browser floating window, entering full screen in the
host desktop application could leave only the FloatTabs frame and controls
visible. The browser page inside the frame appeared blank or showed the
underlying application.

### Root cause

The visible shell and the actual `WKWebView` are separate AppKit windows. The
shell could join all Spaces and other applications' full-screen Spaces, while
the source window used only `managed + fullScreenNone`. When the host
application created a new full-screen Space, WindowServer could therefore
present the shell without the source window that carries the page. The first
attempt only added the cross-Space flags while retaining `fullScreenNone`, which
did not resolve the real-Mac reproduction.

### Fix

The normal source window now also uses `canJoinAllSpaces` and
`canJoinAllApplications` without `fullScreenNone`, so it can follow the shell
into host-application full-screen Spaces. When WebKit itself owns element
fullscreen, the source temporarily switches to a separate `fullScreenNone`
restore-owner behavior and returns to the normal Space-joinable behavior after
restoration. `NSWorkspace.activeSpaceDidChangeNotification` also triggers a
non-activating source-window re-order on the immediate and settled run-loop
turns, repairing a stale child-window Space membership.

### Validation status

- Added a regression assertion in `ExternalShellTests` for the source-window
  collection behavior.
- Focused `ExternalShellTests` passed: 82 tests, 0 failures.
- Full XCTest passed: 638 tests, 0 failures.
- Debug build passed on the local arm64 Mac target.
- Running Debug app visually confirmed the menu bar shows the FloatTabs icon
  followed by `Test`.
- Real-Mac acceptance is still pending: open FloatTabs over a normal browser
  window, enter that browser's macOS full screen, verify the page remains
  visible and interactive, then exercise WebKit element fullscreen separately.
- This fix remains uncommitted and unmerged for the next combined acceptance.

## Test build marker

Debug builds now force the menu bar status item to show the FloatTabs icon
followed by `Test`, including when the icon-only preference is selected. Release
builds keep the existing menu bar presentation unchanged.
