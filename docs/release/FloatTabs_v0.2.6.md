# FloatTabs v0.2.6 — Remote Orbit Connector

Release date: 2026-09-04

Build: **14**

## Summary

The Remote Orbit Connector variant keeps its integration baseline while
narrowing the expanded left Tab-side movement hit area to the actual panel
edge.

## Highlights

### Precise movement hit area

- The expanded left side keeps only the 12 pt leading movement gutter.
- The rest of the reserved Tab column is no longer a blank drag target.
- Remote Orbit focus, scroll, and external command integration are unchanged.
- Regression coverage verifies both the leading gutter and the reclaimed blank
  rail area.

## Validation

- Full local XCTest: **654 tests, 0 failures**.
- Universal 2 Release build and DMG verification: **passed**.

## Distribution

FloatTabs v0.2.6 Build 14 is distributed as an unsigned, unnotarized Universal
2 DMG for the Remote Orbit Connector integration line.
