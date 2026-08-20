# FloatTabs — UI Design System v1.2

> **Status: SUPERSEDED for current shell interaction and geometry.**  
> This file was the accepted UI foundation before the v0.1.3 rail / fullscreen refinements.

The current production interaction and geometry contract is:

- [`FloatTabs_UI_Design_System_v1.3.md`](FloatTabs_UI_Design_System_v1.3.md)
- repository `main` production code and regression tests
- the current release record under `docs/release/`

The complete original v1.2 specification is preserved at:

- [`archive/FloatTabs_UI_Design_System_v1.2.md`](archive/FloatTabs_UI_Design_System_v1.2.md)

Do not use the archived file's old collapsed-rail, Gear/FT persistence, rail timing, or early shell-geometry statements to override v1.3 or current code.

In particular, the following v1.2-era assumptions are no longer canonical:

- collapsed mode keeping the Settings/Gear control visible;
- treating the entire 76 pt rail reservation as physically occupied while collapsed;
- an approximately 180 ms rail fold timing;
- early frozen-shell interaction details that predate the current first-click rail controls and geometry-aware source-window architecture.

For current implementation work, start with v1.3.
