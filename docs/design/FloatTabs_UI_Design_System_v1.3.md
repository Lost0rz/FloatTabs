# FloatTabs — UI Design System v1.3

> **Status:** Current production interaction / geometry contract  
> **Effective:** 2026-08-20 / FloatTabs v0.1.3  
> **Scope:** Shell interaction, Tab rail, folding, movement, resize, fullscreen coordination.  
> **Inheritance:** Visual tokens and unaffected component guidance from the archived [`v1.2`](archive/FloatTabs_UI_Design_System_v1.2.md) remain usable only where they do not conflict with this file or current production code.

## 1. Source-of-truth priority

For current behavior:

1. production code and regression tests on `main`;
2. this v1.3 document;
3. current README / release record;
4. older design, architecture and stage documents as historical context;
5. generated Stitch references.

`FloatTabs_UI_Design_System_v1.2.md` is superseded for shell interaction and geometry. Its full historical contents are retained under `docs/design/archive/`.

## 2. Product boundary

FloatTabs is a **persistent floating Web App switcher**, not a full browser and not a maximize-oriented window manager.

The Web surface stays visually dominant. FloatTabs-owned persistent controls live primarily on the left rail or in native transient UI.

## 3. Expanded rail

Nominal external control-zone width:

```text
76 pt
```

The expanded rail contains:

- persistent Web App Tabs;
- Add (`+`);
- Settings;
- Pin.

The bottom-left fold grip is a separate fold/unfold affordance tied to the Web corner.

Tabs are favicon-first and expand on hover. Tab / Add / Pin / Settings accept first mouse so a control click is not consumed only by application activation.

## 4. Collapsed rail

Collapsed state is a **physical presentation change**, not a persisted viewport-size change.

```text
expanded nominal rail reservation = 76 pt
collapsed physical leading inset  = 12 pt
reclaimed Web width               = 64 pt
```

When collapsed:

- Web App Tabs are hidden;
- Add is hidden;
- Settings is hidden;
- Pin is hidden;
- the bottom-left fold grip remains available to restore the rail;
- the 12 pt leading strip remains a window-movement target;
- the reclaimed 64 pt belongs to Web content and must not be intercepted by shell drag hit testing.

The shell `NSWindow` frame does **not** resize when the rail folds.

All persisted / nominal panel and viewport formulas remain based on the 76 pt expanded reservation. Therefore collapse → resize → expand → relaunch must not accumulate width drift or convert the physical 12 pt state into a new persisted viewport authority.

## 5. Fold animation

All user-visible rail-fold components share one clock:

```text
rail fold duration = 0.22 s
curve              = ease-out family
```

The shared duration applies to:

- Tab/control horizontal slide;
- Tab/control alpha transition;
- fold-grip path animation;
- external-zone constraint change;
- separately hosted Web source-window frame change.

Do not reintroduce independent 0.25 / 0.26 second fold durations.

## 6. Window movement

Movement hit regions follow the **physical Web frame**.

Expanded:

- the left control zone may participate in shell movement only where no visible control owns the hit;
- visible rail controls own their own cursor and click behavior.

Collapsed:

- only the 12 pt leading gutter remains the left-side shell movement target;
- the reclaimed content column is Web content, not an invisible drag lane.

## 7. Resize

Bottom-right remains the resize affordance.

Resize semantics are intentionally those of a floating utility window:

- the starting left edge stays fixed;
- the top edge stays fixed while the bottom-right corner moves;
- size is clamped to the available region of the current display;
- resizing does not automatically slide the window left;
- reaching the right edge does not trigger maximize or full-visible-width behavior.

The experimental auto-full-width / auto-slide behavior is explicitly **not part of the product contract**.

## 8. Fullscreen coordination

WebKit element fullscreen is separate from FloatTabs window resize/maximize behavior.

During a fullscreen source session:

- source geometry is frozen under fullscreen ownership;
- rail collapse / expand requests are rejected;
- shell and source geometry must not diverge.

Fullscreen restoration completes only after:

1. the active `WKWebView` has returned to the ordinary source hierarchy; and
2. the WebKit-owned fullscreen presentation window is no longer visible;
3. restoration remains stable for the required checks.

When the shell is re-presented after fullscreen, the normal short workspace auto-hide suppression is re-armed so stale activation events cannot immediately hide the restored shell.

## 9. Current acceptance contract

A release candidate changing shell geometry must verify at minimum:

- first click switches Tabs from a background application;
- fold/unfold is visually synchronized;
- collapsed content begins after the 12 pt leading gutter;
- the 12 pt gutter still moves the window;
- reclaimed Web content is not consumed by movement hit testing;
- repeated fold/unfold has no geometry drift;
- collapsed resize then expand restores nominal sizing correctly;
- collapse state survives relaunch without changing nominal viewport authority;
- fullscreen refuses rail geometry mutation;
- fullscreen exit restores shell, source, active Tab and Web content coherently;
- ordinary bottom-right resize does not auto-maximize or auto-slide.

## 10. Historical documents

Older files remain useful for design history but do not override this contract. In particular:

- `FloatTabs_UI_Design_System_v1.2.md` — superseded pointer for the prior shell interaction / geometry baseline;
- `archive/FloatTabs_UI_Design_System_v1.2.md` — complete archived v1.2 document;
- `../architecture/Stage_1_Interaction_Baseline.md` — historical pointer for the pre-Slot Stage 1 baseline;
- `../architecture/archive/Stage_1_Interaction_Baseline.md` — complete archived Stage 1 document;
- Stitch-generated screenshots / HTML — visual references only.
