# FloatTabs — Architecture Document Status

Use this file to distinguish current contracts from historical stage documents.

## Current behavior

For shell interaction, rail geometry, movement, resize and fullscreen coordination, use:

- [`../design/FloatTabs_UI_Design_System_v1.3.md`](../design/FloatTabs_UI_Design_System_v1.3.md)
- production code and regression tests on `main`
- the current release record under `../release/`

## Existing architecture references

### `FloatTabs_Technical_Architecture_v1.2.md`

Still useful for the broader native/WebKit architecture and module boundaries, but its older shell-interaction details must yield to the current v1.3 interaction contract and production code.

### `Stage_1_Interaction_Baseline.md`

Historical pointer only. The complete original pre-Slot baseline is retained at [`archive/Stage_1_Interaction_Baseline.md`](archive/Stage_1_Interaction_Baseline.md).

## Archived design history

The complete superseded UI Design System v1.2 is retained at [`../design/archive/FloatTabs_UI_Design_System_v1.2.md`](../design/archive/FloatTabs_UI_Design_System_v1.2.md).

## Rule

When a versioned architecture/design document disagrees with current `main`, treat the older statement as historical unless a newer accepted contract explicitly restores it.
