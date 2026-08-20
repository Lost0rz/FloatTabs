# FloatTabs — Stage 1 Interaction Baseline

> **Status: HISTORICAL.**  
> This document records the pre-Slot Stage 1 engineering baseline and must not be treated as the current shell / interaction authority.

Current production interaction and geometry are defined by:

- [`../design/FloatTabs_UI_Design_System_v1.3.md`](../design/FloatTabs_UI_Design_System_v1.3.md)
- current `main` code and regression tests
- the current release record under `docs/release/`

The complete original Stage 1 baseline is preserved at:

- [`archive/Stage_1_Interaction_Baseline.md`](archive/Stage_1_Interaction_Baseline.md)

## Historical context

Stage 1 established several ideas that still explain the architecture:

- user-facing Window Size means WKWebView viewport size rather than total panel frame;
- FloatTabs-owned permanent browser chrome stays outside the Web surface;
- narrow perimeter regions provide window movement without turning the page into a title bar;
- visible controls must win hit testing over generic movement regions;
- multi-display positioning clamps the panel into the target display's visible frame.

However, the original Stage 1 numbers and interaction assumptions predate persistent Slots, the current external rail, the separate Web source window, fold/reclaim geometry, first-click rail controls and current fullscreen lifecycle.

## Current overrides

Do **not** derive current implementation from the old Stage 1 geometry.

Current rail geometry is:

```text
expanded nominal rail reservation = 76 pt
collapsed physical leading inset  = 12 pt
reclaimed Web content width       = 64 pt
```

The 12 pt collapsed gutter remains a movement target, while reclaimed Web content must not be intercepted by shell drag hit testing.

Bottom-right resize remains ordinary floating-window resize and does not auto-maximize or auto-slide the panel to full visible width.
