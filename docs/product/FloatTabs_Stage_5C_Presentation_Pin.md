# FloatTabs Stage 5C — Presentation + Panel Visibility

Status: Draft implementation contract for Real-Mac validation.

## 1. Purpose

Stage 5C does not redesign the accepted Hot / Warm / Cold residency model. It separates three concepts that were previously partially coupled:

1. **Panel Visibility** — whether the FloatTabs panel remains on screen after focus moves elsewhere.
2. **Slot Residency** — Hot / Warm / Cold resource policy.
3. **Slot Presentation** — Active / Inactive system-derived visual presentation state.

The goal is to reduce unnecessary rendering/energy cost without sacrificing the accepted instant-return behavior of Hot Web Apps.

## 2. Panel Visibility

### Auto-hide — default per launch

- Global summon/toggle shows FloatTabs as today.
- When FloatTabs loses application focus to another app, the panel hides automatically.
- This is a session behavior, not a persisted user preference in Stage 5C v1.

### Pinned

- A small `pin` / `pin.fill` control in the existing external control zone toggles Pin.
- Pinned means application deactivation does **not** hide the panel.
- Pin is session-only and resets to Auto-hide on a new app launch.
- Pin controls only panel persistence on screen. It does not change Hot / Warm / Cold.

### Full-screen

Both Auto-hide and Pinned modes retain the existing `.fullScreenAuxiliary` / all-spaces presentation ability. Pin determines whether the panel remains after focus moves away, not whether it may appear over a full-screen app.

## 3. Slot Presentation

The Active Slot is the only Slot that should be visually presented.

### Active

- Presentation visible.
- Uses the existing WebView/host geometry and Website Mode/Zoom chain unchanged.

### Inactive Hot

- Preserve the same independent `WebSlotHostView` and `WKWebView`.
- Preserve the frozen outgoing frame.
- Do not detach or move the WebView to another host.
- Do not destroy DOM/session/SPA state.
- Hide only the independent Hot presentation host while inactive.
- On reactivation, unhide the same host and bring it to the front.

This is intentionally narrower than the rejected Stage 4 shared-host residency experiments.

### Inactive Warm

Existing accepted behavior remains unchanged: retain the WKWebView in the pool and detach its presentation.

### Inactive Cold

Existing accepted behavior remains unchanged: detach, start the inactivity grace period, then release the runtime after the grace period.

## 4. Background Media Risk Boundary

Presentation hiding may cause a site or WebKit to pause media even when `Background Media = Allow Background Audio`.

Stage 5C v1 does **not** add site-specific workarounds. Real-Mac acceptance must explicitly check:

- ChatGPT: Hot + Pause When Inactive — return remains immediate and layout-correct.
- YouTube Desktop: Hot + Allow Background Audio — determine whether audio survives inactive Hot host hiding.
- Bilibili: same observation where useful.

If hiding a Hot host breaks an explicitly allowed background-media use case, media policy and presentation policy must be reconciled before Stage 5C is accepted. Do not mask this with global autoplay overrides or JavaScript `play()` forcing.

## 5. Interaction Contract

```text
Global summon
  ↓
Panel Visible / Auto-hide
  ↓
Active Slot = presented
Inactive Hot = resident + hidden presentation
Inactive Warm = resident + detached
Inactive Cold = detached → grace → released
```

Click another application while Auto-hide:

```text
FloatTabs application deactivates
  ↓
Panel orderOut
```

Pinned:

```text
FloatTabs application deactivates
  ↓
Panel remains visible
```

## 6. Non-goals

Stage 5C v1 does not:

- change Hot / Warm / Cold persistence semantics;
- introduce a new browser toolbar;
- persist Pin across launches;
- change Website Mode, pageZoom, viewport sizing or Slot preferred-size behavior;
- add shared variable-size presentation hosts;
- add site-specific background-media hacks;
- set final Hot count warnings/caps;
- make Safari/Chrome comparison a release blocker.

## 7. Acceptance Gates

Automated:

- inactive Hot host remains attached to the same window and preserves its frame;
- inactive Hot host becomes hidden;
- reactivating the same Hot Slot unhides the same host/WebView;
- Pin state updates the external control UI;
- Auto-hide decision is suppressed while Pinned;
- existing Stage 4/5 unit tests remain green.

Real Mac:

1. Auto-hide panel disappears when another application is selected.
2. Pinned panel stays visible when another application is selected.
3. Global shortcut can summon an auto-hidden panel again.
4. Full-screen auxiliary behavior still works.
5. ChatGPT Hot switch-back remains immediate and scale/layout correct.
6. YouTube/Bilibili background-media behavior is observed under Hot + Allow.
7. After functional acceptance, PR #10 benchmark is rerun to compare Hot visible/hidden CPU and memory.
