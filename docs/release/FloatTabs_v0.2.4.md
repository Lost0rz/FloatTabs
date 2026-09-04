# FloatTabs v0.2.4

Release date: 2026-09-04

Build: **13**

## Summary

v0.2.4 preserves the user's FloatTabs window size across display changes and
keeps the left Tab-side movement hit area close to the actual panel edge.

## Highlights

### Display configuration resilience

- Screen topology and resolution changes reposition the panel without treating
  temporary visible-frame constraints as a user resize.
- Stored fixed and per-Web-App viewport sizes remain authoritative.
- Temporary display-induced size changes are not persisted as new user
  dimensions.
- Manual resizing still clamps to the active visible display and updates the
  selected size preference.

### Precise movement hit area

- The expanded left side keeps only the 12 pt leading movement gutter.
- The rest of the reserved Tab column is no longer a blank drag target.
- Collapsed-rail movement behavior remains unchanged.
- Regression coverage verifies both the leading gutter and the reclaimed blank
  rail area.

## Validation

- Full local XCTest: **647 tests, 0 failures**.
- Regression coverage for a smaller display and origin-only relocation.
- Main stable Release build: passed.
- Universal 2 architecture verification: passed.
- DMG verification: passed.
- Manual monitor and resolution transition validation remains the next QA step.

## Distribution

FloatTabs v0.2.4 Build 13 is distributed as an unsigned, unnotarized Universal
2 DMG.
