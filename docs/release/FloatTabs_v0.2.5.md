# FloatTabs v0.2.5

Release date: 2026-09-04

Build: **13**

## Summary

v0.2.5 narrows the expanded left Tab-side movement hit area so empty space
beside the actual panel edge no longer advertises window movement or intercepts
clicks intended for content behind the panel.

## Highlights

### Precise movement hit area

- The expanded left side keeps only the 12 pt leading movement gutter.
- The rest of the reserved Tab column is no longer a blank drag target.
- Collapsed-rail movement behavior remains unchanged.
- Regression coverage verifies both the leading gutter and the reclaimed blank
  rail area.

## Validation

- Full local XCTest: **647 tests, 0 failures**.
- Universal 2 Release build and DMG verification: **passed**.

## Distribution

FloatTabs v0.2.5 Build 13 is distributed as an unsigned, unnotarized Universal
2 DMG.
