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

### Tab surface and unread attention

- Normal and active/read Tabs use neutral rail surfaces independent of assigned Browser Profile color; the shared page+Tab outline and active typography continue to own selection.
- A visible Tab with `Unread/Ready` set uses the selected whole-Tab **Attention Style**. `Signal` is restrained and static; `Ember` uses warm red/orange/pink; `Aurora` uses purple/blue/magenta; `Spectrum` uses a full-spectrum rainbow with gentle breathing. Animated styles drift slowly on a roughly 3–6 second cycle and remain in force during hover.
- The attention surface uses a contrasting foreground for its label and template icon. Favicon color continues to represent runtime residency: resident icons stay full color and released icons stay grayscale/dim.
- The visible Tab rail does not add a favicon unread dot. In compact layout, the overflow control uses the selected Attention Style when any hidden Tab is unread; its menu item retains a semantic unread marker and accessibility label.
- Browser Profile color metadata remains persisted for compatibility, but Profile color is not presented as a Tab distinction and has no chooser in Browser Profiles Settings.
- The Notifications settings surface presents all four Attention Styles as miniature Tab previews in a compact 2×2 choice layout. Previews and real Tabs use the same style renderer, and selection has a clear native accent treatment.
- Attention motion changes only gradient coordinates and gentle opacity. It never moves, shakes, scales, flashes or re-lays out a Tab. macOS Reduce Motion keeps a static representative treatment for animated styles; `Signal` is already static.
- The selected style is a single app preference with `Signal` as the default and fallback. It is independent of Browser Profile and Slot data.

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
- the 12 pt leading strip remains physical layout geometry, but is not a window-movement target;
- the reclaimed 64 pt belongs to Web content and must not be covered by shell movement hit testing.

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

The only supported window-movement target is the bounded four-edge band **inside the Web surface**, owned by `WebSourceEdgeDragView` in the ordinary Web source window.

- The external shell perimeter, including its top, right and bottom gutters, is not a movement target.
- The complete left Tab rail is not a movement target in expanded or collapsed state, including uncovered gaps, hover-expanded Tab surroundings and the leading strip.
- The 12 pt collapsed leading inset remains physical layout geometry; it is not a movement target.
- The shell has no move cursor, synthetic acquisition drawing or movement hit target.
- Visible rail controls retain their own click and cursor behavior. Tab drag continues to reorder Tabs.
- The inner Web-edge movement band retains its bottom-right resize exclusion.

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
- hover-expanded Tabs remain fully clickable, and Tab drag continues to reorder Tabs;
- fold/unfold is visually synchronized;
- collapsed content begins after the 12 pt leading gutter;
- the collapsed 12 pt leading gutter and complete expanded/collapsed rail do not move the window;
- outer top / right / bottom gutters do not move the window or advertise the move cursor;
- inner Web-edge drag still moves the window and bottom-right resize remains independent;
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
