# FloatTabs v0.2.6

Release date: 2026-09-07

Build: **15**

## Summary

v0.2.6 Build 15 closes the verified Remote Orbit integration baseline while
preserving the latest FloatTabs panel movement, presentation, and Web focus
behavior from `main`.

## Highlights

### Remote Orbit semantic command surface

- Remote commands remain independent from user-configurable keyboard shortcuts.
- Show/toggle, direct Slot selection, next/previous Slot navigation, scrolling,
  reload, settings, pinning, residency mode, zoom, address/home actions, and
  voice-input focus are exposed through the versioned external command surface.
- Same-turn next/previous Slot bursts are coalesced so intermediate WebViews are
  not synchronously activated and persisted.

### Voice and Web focus handoff

- Voice-input focus captures the active DOM editor and caret before FloatTabs
  presentation, then restores that exact target after the AppKit/WebKit focus
  handoff when it remains valid.
- ChatGPT and generic Web adapters recognize textarea, textbox-role, and usable
  contenteditable inputs, including `contenteditable="plaintext-only"`.
- Presentation focus uses event-driven AppKit/WebKit lifecycle signals plus one
  bounded settle pass instead of the former retry loops.

### Precise movement hit testing

- Expanded visible Tab and rail-control frames are excluded from window movement
  hit testing.
- The intended leading movement gutter and uncovered rail gaps remain movable.
- Collapsed rail movement behavior remains unchanged.
- Display and resolution changes continue to preserve the preferred panel size.

### Rendering and residency controls

- Zoom presets use 50% steps from 50% through 300%.
- Hot, Warm, and Cold residency modes remain available through the local UI,
  shortcuts, and Remote Orbit command surface.

## Validation

- Full local XCTest: **659 tests, 0 failures**.
- GitHub Intel x86_64 Build & Test: passed.
- GitHub Apple Silicon arm64 Build & Test: passed.
- Universal 2 Release Build: passed.
- QA DMG build and verification: passed.
- `git diff --check`: passed for the verified baseline.
- Independent baseline audit: two consecutive material-code clean rounds before
  merge to `main`.

## Distribution

FloatTabs v0.2.6 Build 15 is distributed as an unsigned, unnotarized Universal 2
DMG. The existing v0.2.6 Release is refreshed in place by the repository's
release workflow when the build number advances.
