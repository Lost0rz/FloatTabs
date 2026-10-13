# FloatTabs — Architecture Document Status

Use this file to distinguish current navigation/contracts from historical stage documents.

## Current navigation

For source/Authority routing, use:

- [`DOMAIN_MAP.md`](DOMAIN_MAP.md) — derived Domain/source/test navigation map;
- production code and regression tests on the current Delivery / Semantic HEAD.

`DOMAIN_MAP.md` is navigation only. It does not override product/design contracts or `CURRENT_TASK.md`.

## Current behavior

For shell interaction, rail geometry, movement, resize and fullscreen coordination, use:

- [`../design/FloatTabs_UI_Design_System_v1.3.md`](../design/FloatTabs_UI_Design_System_v1.3.md)
- production code and regression tests on `main`
- the current release record under `../release/`

The supported runtime and release architecture is Apple Silicon arm64 only.

## Existing architecture references

### `FloatTabs_Technical_Architecture_v1.2.md`

Still useful for the broader native/WebKit architecture and module boundaries, but older shell-interaction details yield to the current v1.3 interaction contract and production code.

### `Stage_1_Interaction_Baseline.md`

Historical pointer only. The complete original pre-Slot baseline is retained at [`archive/Stage_1_Interaction_Baseline.md`](archive/Stage_1_Interaction_Baseline.md).

## Archived design history

The superseded UI Design System v1.2 is retained at [`../design/archive/FloatTabs_UI_Design_System_v1.2.md`](../design/archive/FloatTabs_UI_Design_System_v1.2.md).

## Rule

When a versioned architecture/design document disagrees with current production code or a newer accepted contract, treat the older statement as historical unless explicitly restored.
