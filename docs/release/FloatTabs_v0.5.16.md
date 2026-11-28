# FloatTabs v0.5.16

Build: **34**

## Summary

Separate group-label colors from the floating window border, and make window presets responsive to the available display area.

## Changes

- Global border appearance controls the window frame and rail fold controls; group colors affect only the group label. Existing group color preferences are retained.
- Window size presets: Portrait (9:16, 85% of usable display height), Landscape (16:9, 50% of usable display width), Large (4:3, 85% of usable display height), and Custom (width and height percentages). Minimum size and usable display limits apply.
- Recalculate responsive dimensions on cross-display presentation and completed window movement. Support shared and per-Web-App sizing, custom resize persistence, and backup/restore.
- Retain legacy custom point sizes until an explicit size edit and preserve advanced device presets.
- Picture-in-picture behavior is unchanged.

## Verification

- Product PR #222: seven affected macOS test lanes and the governed Ready checks passed (run 46167507675).
- This release's package build and checksums are verified by the existing Publish Release workflow. Actual multi-display interaction and installed-app acceptance remain manual checks.
