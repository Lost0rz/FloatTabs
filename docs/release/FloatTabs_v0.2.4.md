# FloatTabs v0.2.4

Release date: 2026-09-01

Build: **12**

## Summary

v0.2.4 preserves the user's FloatTabs window size when connected displays or
display resolutions change.

## Highlights

### Display configuration resilience

- Screen topology and resolution changes reposition the panel without treating
  temporary visible-frame constraints as a user resize.
- Stored fixed and per-Web-App viewport sizes remain authoritative.
- Temporary display-induced size changes are not persisted as new user
  dimensions.
- Manual resizing still clamps to the active visible display and updates the
  selected size preference.

## Validation

- Full local XCTest: **647 tests, 0 failures**.
- Regression coverage for a smaller display and origin-only relocation.
- Main stable Release build: passed.
- Universal 2 architecture verification: passed.
- DMG verification: passed.
- Manual monitor and resolution transition validation remains the next QA step.

## Distribution

FloatTabs v0.2.4 Build 12 is distributed as an unsigned, unnotarized Universal
2 DMG.
