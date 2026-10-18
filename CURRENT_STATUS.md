# FloatTabs Current Status

**Status date:** 2026-10-18
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: TAB_ATTENTION_VISUAL_REFINEMENT_ACTIVE**

`FT-TAB-ATTENTION-HIGHLIGHT-001` remains active in Draft PR #125. Automated implementation through `fce121e5d95faaadc1f84467735b9589edbb2be8` passed, and the exact Release candidate was installed for Real-Mac review. Human review confirmed that the current Settings previews are too similar because they mostly vary color/gradient while sharing the same whole-surface geometry.

## Verified baseline

- Current `main`: `7d473a4567ec0a7fa000c6b29dfeab95a36ebab6`.
- Task branch: `product/ft-tab-attention-highlight-001`.
- Draft PR #125 — `Make unread Tabs visually prominent`.
- Current semantic candidate: `fce121e5d95faaadc1f84467735b9589edbb2be8`.
- Exact-head macOS CI and QA DMG: PASS.
- Diagnostics/history PR #124 remains separate and untouched.
- Browser Profile color remains removed from Tab presentation; persisted Profile color metadata remains compatibility data only.

## Human visual review

The user accepted the product need for a stronger unread signal but rejected the current preview family as insufficiently diverse. The large preview also exposes the rail Tab surface geometry as visually awkward when stretched horizontally.

The user explicitly wants the **classic red unread dot retained as a valid reminder option** because it remains a simple, effective cue. The task is therefore refined again in-place rather than removing the dot concept entirely.

## Latest accepted product direction

Unread attention becomes a set of **structurally distinct reminder styles**, not merely several whole-surface gradients.

The first-version style family should include:

- **Dot** — classic red unread dot; minimal, static, proven-effective baseline;
- **Beacon** — a bounded edge/accent light that points to the Tab without filling the whole surface;
- **Halo** — soft whole-Tab glow/breathing emphasis without a hard solid fill;
- **Orbit** — a moving highlight around the Tab perimeter while geometry remains fixed;
- **Pulse** — restrained whole-surface brightness/breathing emphasis;
- **Sweep** — a bounded highlight sweep across the Tab, separated by calm intervals.

Color is a separate presentation dimension where practical. The intended palette family is Red, Amber, Blue, Violet, Mint, and Spectrum. The exact supported palette/style compatibility may be narrowed during implementation if a combination is visually invalid, but style identity must come from structure/motion, not merely different gradients.

The existing `Signal / Ember / Aurora / Spectrum` implementation at `fce121e...` is now an intermediate candidate, not the final accepted visual contract.

## Preview direction

Settings previews must stop stretching the production rail Tab surface into a long asymmetric/trapezoid-like shape. Preview cards should use a compact, symmetric rounded preview surface appropriate to Settings while sharing the same attention-effect renderer/configuration as the real Tab.

Preview requirements:

- each style must be visibly different before reading its label;
- Dot preview must visibly show the classic red unread dot;
- animated styles must demonstrate their actual effect;
- selected state must remain clear and native;
- Reduce Motion must produce a static representative treatment;
- preview geometry is presentation-only and must not alter real rail geometry.

## Protected behavior

This refinement must not change:

- ChatGPT attention state transitions or acknowledgement timing;
- unread source of truth or attention residency protection;
- Tab selection/order/reorder behavior;
- favicon resident/released semantics;
- Web runtime/navigation/focus/recovery;
- Browser Profile/session/WebKit data ownership;
- real rail geometry, Dock magnification, movement, resize, fullscreen or speech behavior.

The selected attention style/palette are ordinary app UI preferences only and must not be stored in Browser Profile or Slot/session data.

## Current posture

```text
ACTIVE_PRODUCT_TASK=FT-TAB-ATTENTION-HIGHLIGHT-001
TASK_STATE=ACTIVE
TASK_BRANCH=product/ft-tab-attention-highlight-001
TASK_PR=125_DRAFT
CURRENT_IMPLEMENTATION_HEAD=fce121e5d95faaadc1f84467735b9589edbb2be8
GATE5_VISIBILITY_FUNCTION=PASS
GATE5_CURRENT_VISUAL_FAMILY=REFINE
CLASSIC_RED_DOT=RETAIN_AS_SELECTABLE_STYLE
NEXT_STYLE_FAMILY=DOT_BEACON_HALO_ORBIT_PULSE_SWEEP
PALETTE_DIMENSION=RED_AMBER_BLUE_VIOLET_MINT_SPECTRUM
DIAGNOSTICS_PR_124=PARKED_UNCHANGED
ROOT_CAUSE=N/A
```

## Acceptance direction

The next candidate must make the six reminder styles structurally distinct in Settings and on real unread Tabs, retain the classic red dot as a selectable baseline, avoid stretched trapezoid-like previews, preserve existing runtime/profile/session behavior, pass renewed automated verification, and then return to Human Real-Mac visual acceptance.
