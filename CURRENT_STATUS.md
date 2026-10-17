# FloatTabs Current Status

**Status date:** 2026-10-17
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: TAB_ATTENTION_VISUAL_REFINEMENT_ACTIVE**

`FT-TAB-ATTENTION-HIGHLIGHT-001` remains active. The first exact Release candidate proved that whole-Tab attention is visible and functionally correct, but Human Real-Mac review did not accept the visual quality of a single solid-red treatment. The task is therefore refined in-place rather than closed or split into a new task.

## Verified baseline

- Current `main`: `7d473a4567ec0a7fa000c6b29dfeab95a36ebab6` — PR #123 merge commit.
- Task branch: `product/ft-tab-attention-highlight-001`.
- Draft PR #125 — `Make unread Tabs visually prominent`.
- First implementation semantic head: `684ca4ec06b9d664e1017cd472cfdeef6ec2c591`.
- First implementation automated gates: focused/full XCTest, Debug/Release arm64, exact-head macOS CI and QA DMG all PASS.
- First exact Release candidate was installed and identity-verified on Real Mac.
- Human Real-Mac result: visibility/function direction accepted, visual design quality not accepted; Gate 5 remains open.
- Diagnostics/history PR #124 remains separate, parked and untouched.

## Accepted product direction

The rail keeps the simplified state hierarchy:

```text
NORMAL / ACTIVE TAB     = neutral profile-independent surface
UNREAD / READY TAB      = whole-Tab attention treatment
BROWSER PROFILE COLOR   = no longer a Tab-rail visual signal
```

The tiny favicon unread dot remains removed. Browser Profile color remains compatibility metadata only and is not reintroduced as a Tab signal.

The unread treatment is now a selectable **Attention Style** rather than one fixed red fill. The approved preset family is:

- **Signal** — static, restrained attention emphasis;
- **Ember** — warm red/orange/pink animated gradient;
- **Aurora** — purple/blue/magenta animated gradient;
- **Spectrum** — full-spectrum/rainbow animated gradient with gentle breathing.

Settings must show a live visual preview for each preset so the user can choose by appearance rather than by name alone. The selected style is an app preference and must update the rail without changing attention state ownership.

Animation is visual projection only:

- no Tab translation, shake, scale-jitter or layout movement;
- no flashing/high-frequency flicker;
- use bounded Core Animation-style layer animation rather than polling/display-link CPU work;
- animated styles degrade to a stable static representative treatment when macOS Reduce Motion is enabled;
- unread hover keeps the chosen attention style instead of reverting to neutral;
- acknowledgement still clears Ready through the existing authority and returns the Tab to neutral.

## Protected behavior

This task still must not change:

- ChatGPT attention state transitions or acknowledgement timing;
- unread source of truth or attention residency protection;
- Tab selection/order/reorder behavior;
- favicon resident/released full-color vs grayscale semantics;
- Web runtime/navigation/focus/recovery;
- Browser Profile identity, WebKit data stores, cookies, login/session data, or backup compatibility;
- rail geometry, Dock magnification, fold/unfold, movement, resize, fullscreen, or speech behavior.

The new persisted Attention Style preference is ordinary app UI preference data only. It must not be stored in Browser Profile or Slot data.

## Current posture

```text
ACTIVE_PRODUCT_TASK=FT-TAB-ATTENTION-HIGHLIGHT-001
TASK_STATE=ACTIVE
TASK_BRANCH=product/ft-tab-attention-highlight-001
TASK_PR=125_DRAFT
FIRST_VISUAL_CANDIDATE=684ca4ec06b9d664e1017cd472cfdeef6ec2c591
GATE5_VISIBILITY_FUNCTION=PASS
GATE5_VISUAL_QUALITY=REFINE
ATTENTION_STYLE_PRESETS=SIGNAL_EMBER_AURORA_SPECTRUM
DIAGNOSTICS_PR_124=PARKED_UNCHANGED
ROOT_CAUSE=N/A
```

## Acceptance direction

The next candidate must let the user preview and select Signal, Ember, Aurora or Spectrum in Settings, project that same style onto unread visible Tabs and compact overflow, respect Reduce Motion, preserve favicon/runtime semantics, and pass renewed Real-Mac visual review. Automated verification and hosted CI must be rerun for the new semantic head before Gate 5 resumes.
