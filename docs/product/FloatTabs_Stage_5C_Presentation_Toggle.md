# FloatTabs Stage 5C — Presentation + Explicit Panel Toggle

Status: Draft implementation contract for Real-Mac validation.

## 1. Purpose

Stage 5C does not redesign the accepted Hot / Warm / Cold residency model. It makes two targeted changes:

1. **Inactive Hot presentation hiding** — preserve Hot runtime state while stopping inactive Hot Slots from remaining visually presented.
2. **Explicit panel visibility control** — the panel is shown or hidden only by an explicit user toggle, rather than inferred focus/deactivation behavior.

The goal is to reduce unnecessary rendering/energy cost without sacrificing predictable panel interaction or Hot instant-return behavior.

## 2. Panel Visibility Contract

FloatTabs has two explicit panel states:

```text
Visible
Hidden
```

The global toggle is:

```text
⌘ + `
```

Behavior:

- When Hidden, `⌘ + \`` summons FloatTabs.
- When Visible, `⌘ + \`` hides FloatTabs.
- The existing menu-bar toggle remains valid.
- Clicking another application does **not** automatically hide FloatTabs.
- There is no Pin mode in Stage 5C.
- Existing floating/all-spaces/full-screen auxiliary behavior remains unchanged.

This is intentionally deterministic: FloatTabs does not guess whether a focus change means the user wants the panel dismissed.

## 3. Slot Switching Contract

While FloatTabs is active, existing app-local shortcuts remain:

```text
⌘1 … ⌘9
```

for direct Slot selection.

Bare `1 … 9` are intentionally not intercepted because the active WKWebView may contain text fields, forms, search boxes, editors, chat inputs, or other controls where numeric typing must continue to work normally.

## 4. Slot Presentation

The Active Slot is the only Slot that should be visually presented.

### Active

- Presentation visible.
- Existing WebView/host geometry and Website Mode/Zoom chain remain unchanged.

### Inactive Hot

- Preserve the same independent `WebSlotHostView` and `WKWebView`.
- Preserve the frozen outgoing frame.
- Do not detach or migrate the WebView.
- Do not destroy DOM/session/SPA state.
- Hide only the independent Hot presentation host while inactive.
- On reactivation, unhide the same host and bring it to front.

Implementation boundary:

```text
inactive Hot
→ same host
→ same WKWebView
→ same frame
→ host.isHidden = true
```

This remains narrower than the rejected Stage 4 shared-host residency experiments.

### Inactive Warm

Existing accepted behavior remains unchanged: retain the WKWebView in the pool and detach its presentation.

### Inactive Cold

Existing accepted behavior remains unchanged: detach, start the inactivity grace period, then release the runtime after the grace period.

## 5. Background Media Risk Boundary

Presentation hiding may cause a site or WebKit to pause media even when `Background Media = Allow Background Audio`.

Stage 5C does not add site-specific workarounds. Real-Mac acceptance must explicitly check:

- ChatGPT: Hot + Pause When Inactive — return remains immediate and layout-correct.
- YouTube Desktop: Hot + Allow Background Audio — determine whether audio survives inactive Hot host hiding.
- Bilibili: same observation where useful.

If hiding a Hot host breaks an explicitly allowed background-media use case, media policy and presentation policy must be reconciled explicitly. Do not mask this with autoplay overrides or JavaScript `play()` forcing.

## 6. Interaction Contract

```text
⌘ + `
  ↓
Panel Visible
  ↓
Active Slot = presented
Inactive Hot = resident + hidden presentation
Inactive Warm = resident + detached
Inactive Cold = detached → grace → released
```

Another `⌘ + \``:

```text
Panel Hidden
```

No focus-loss heuristic participates in this state transition.

## 7. Non-goals

Stage 5C does not:

- change Hot / Warm / Cold persistence semantics;
- add Pin or Auto-hide-on-focus-loss behavior;
- intercept bare number keys for Slot switching;
- introduce a browser toolbar;
- change Website Mode, pageZoom, viewport sizing or Slot preferred-size behavior;
- add shared variable-size presentation hosts;
- add site-specific background-media hacks;
- set final Hot count warnings/caps;
- make Safari/Chrome comparison a release blocker.

## 8. Acceptance Gates

Automated:

- inactive Hot host remains attached to the same window and preserves its frame;
- inactive Hot host becomes hidden;
- reactivating the same Hot Slot unhides the same host/WebView;
- `KeyboardShortcuts.Key.backtick` with Command compiles as the global toggle;
- existing Stage 4/5 unit tests remain green.

Real Mac:

1. `⌘ + \`` summons FloatTabs from another application.
2. Pressing `⌘ + \`` again hides FloatTabs.
3. Clicking another application does not unexpectedly hide the panel.
4. `⌘1 … ⌘9` continues to switch Slots while FloatTabs is active.
5. Full-screen auxiliary behavior still works.
6. ChatGPT Hot switch-back remains immediate and scale/layout/input/scroll correct.
7. YouTube Desktop Hot + Allow background-media behavior is observed with the inactive Hot host hidden.
8. After functional acceptance, rerun the PR #10 benchmark to compare Hot CPU/memory against the previous baseline.
