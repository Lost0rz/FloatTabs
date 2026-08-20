# FloatTabs v0.1.3

Release date: 2026-08-20

## Summary

v0.1.3 is a focused interaction and presentation-stability release. It makes the left Tab rail behave like part of a compact floating browser rather than a permanently reserved sidebar, fixes first-click control activation, and closes the latest fullscreen restore edge cases verified on real hardware.

## Build 5 refresh

The existing v0.1.3 release is refreshed in place with **Build 5**. The marketing version remains `0.1.3`; the build number distinguishes this corrected package from the original Build 4 package.

Settings → Account & Language now ends with an **About FloatTabs** section that shows:

- the exact installed Version and Build from `CFBundleShortVersionString` and `CFBundleVersion`;
- a short **Latest fixes in this build** summary;
- the existing Account, Backup & Restore, and Language content in a scrollable settings page.

Build 5 validation:

- QA DMG #220: PASS;
- macOS CI #683: PASS;
- local real-Mac XCTest: PASS;
- local real-Mac Release build: PASS;
- local Settings acceptance confirmed `Version 0.1.3 (Build 5)` and the latest-fixes section are visible.

This is an in-place v0.1.3 package refresh, not a new release version.

## Highlights

### Collapsed rail now reclaims its width

The expanded shell continues to use a nominal 76 pt external control zone. When the rail is folded:

- Tabs, Add, Pin and Settings controls are hidden;
- the physical leading inset shrinks from 76 pt to 12 pt;
- Web content reclaims the remaining 64 pt;
- the shell `NSWindow` frame does not resize;
- persisted / nominal viewport math stays 76-pt based;
- expanding the rail returns to the exact nominal viewport instead of accumulating geometry drift.

The remaining 12 pt strip stays available as the left movement gutter.

### One rail-fold animation clock

Tab slide, rail alpha, fold-grip path, shell zone-width and separately hosted Web source-window frame now terminate on the same `0.22 s` clock. This removes the previous 0.22 / 0.25 / 0.26 second mismatch that made the fold look out of sync.

### First click switches Tabs

Tab, Add, Pin and Settings controls now accept the first mouse event when FloatTabs is behind another application. A click no longer needs to be spent only activating the accessory app before the control receives the next click.

### Fullscreen restore hardening

The source host now waits until both conditions are true before releasing fullscreen restore ownership:

1. the active `WKWebView` is back in the ordinary source hierarchy; and
2. WebKit's fullscreen presentation window is no longer visible.

The shell also re-arms the short workspace auto-hide suppression period when it is re-presented from fullscreen restore. Rail fold/unfold is rejected while fullscreen owns the source so shell and source geometry cannot diverge mid-transition.

Combined with the physical-visibility lifecycle guard shipped in v0.1.2, the previously reproduced post-fullscreen black-screen case passed the latest Real-Mac acceptance.

### Floating-window resize semantics remain intentional

An experimental change that tried to slide the panel's left edge automatically so a right-edge drag could fill the whole visible display was removed before merge.

v0.1.3 keeps normal floating-window behavior:

- bottom-right remains the resize affordance;
- the starting left edge remains fixed during the resize;
- size is clamped to the available display area from the current window origin;
- FloatTabs does not auto-maximize or auto-expand to full visible width.

## Other correctness work

- backup-restored rail-collapse state now uses the same geometry-aware controller path as the live in-app toggle;
- collapsed movement hit regions track the physical Web frame and do not consume the newly reclaimed content area;
- active Tab / rail cursor ownership is refreshed as hover magnification changes;
- rail geometry mutations fail closed while a fullscreen source session is locked.

## Validation

Functional integration PR #45 completed before this release branch:

- QA DMG #218: PASS
- macOS CI #679: PASS
  - Apple Silicon arm64 Debug / Release / XCTest: PASS
  - Intel x86_64 Debug / Release / XCTest: PASS
  - Universal 2 Release + architecture verification: PASS
- `git diff --check`: PASS
- latest Real-Mac fullscreen black-screen acceptance: PASS
- manual rail collapse / expand, 12 pt movement gutter, resize persistence, relaunch persistence and fullscreen rail-lock checks: PASS

The v0.1.3 release branch is additionally gated by the repository macOS CI and QA DMG workflows before merge. The post-merge `Publish Release` workflow builds and verifies the final Universal 2 package and checksum sidecars before creating or refreshing the GitHub Release.

## Distribution

FloatTabs v0.1.3 is distributed as an unsigned, unnotarized Universal 2 DMG for Apple Silicon and Intel Macs.

Expected release assets:

- `FloatTabs-0.1.3.dmg`
- `FloatTabs-0.1.3.dmg.sha256`
- `FloatTabs-0.1.3.dSYM.zip`
- `FloatTabs-0.1.3.dSYM.zip.sha256`

Verify the DMG with:

```bash
shasum -a 256 -c FloatTabs-0.1.3.dmg.sha256
```
