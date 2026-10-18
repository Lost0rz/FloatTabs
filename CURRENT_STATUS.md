# FloatTabs Current Status

**Status date:** 2026-10-18
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: TAB_ATTENTION_VISUAL_REFINEMENT_ACTIVE**

`FT-TAB-ATTENTION-HIGHLIGHT-001` remains active in Draft PR #125. The live implementation candidate at the start of this iteration is `b57bbd4c65942aaccb24845b5d8d058e7885729d` (freshly verified against the task branch and PR). Human Real-Mac review requests a bounded refinement of Dot, Beacon, Orbit and Sweep; Halo keeps its existing structure.

## Verified baseline

- Current `main`: `7d473a4567ec0a7fa000c6b29dfeab95a36ebab6`.
- Task branch: `product/ft-tab-attention-highlight-001`.
- Draft PR #125 — `Make unread Tabs visually prominent`.
- Candidate at the start of this refinement: `b57bbd4c65942aaccb24845b5d8d058e7885729d`.
- Latest scope/control baseline: `15c743efded8be0a6c2c1f0eca8847bcbbf58e7e`.
- Resolve the current implementation candidate from a fresh `origin/product/ft-tab-attention-highlight-001` ref; do not hard-code the commit containing this status file.
- The candidate requires exact-head macOS CI and QA DMG before Human Real-Mac Gate 5.
- Diagnostics/history PR #124 remains separate and untouched.
- Browser Profile color remains removed from Tab presentation; persisted Profile color metadata remains compatibility data only.

## Latest Human Real-Mac visual review

- Enlarge the classic red Dot to approximately 10–12 pt so it remains visible on high-resolution displays.
- Move Beacon to a thicker, clearer leading-side accent strip while keeping the emphasis local.
- Keep Halo's existing structural concept; only minor polish is in scope.
- Replace Orbit's moving point-run appearance with a continuous full Tab perimeter outline and slow color/brightness flow.
- Add a tinted base and broad, longer moving color band to Sweep, with a calm interval between passes.

These refinements stay within the existing task and preserve the six-style family, Style/Palette separation, symmetric Settings preview geometry, Reduce Motion, shared preview/runtime effect primitives, real rail geometry, and all protected attention/runtime/Profile/session/focus/navigation/recovery ownership.

## Latest accepted product direction

Unread attention becomes a set of **structurally distinct reminder styles**, not merely several whole-surface gradients.

The first-version style family should include:

- **Dot** — classic red unread dot; minimal, static, proven-effective baseline;
- **Beacon** — a thick, localized leading-side accent strip that points to the Tab without filling the whole surface;
- **Halo** — soft whole-Tab glow/breathing emphasis without a hard solid fill;
- **Orbit** — a continuous full-perimeter outline with slow color/brightness flow while geometry remains fixed;
- **Pulse** — restrained whole-surface brightness/breathing emphasis;
- **Sweep** — a tinted base under a broad moving color band, separated by calm intervals.

Color is a separate presentation dimension where practical. The intended palette family is Red, Amber, Blue, Violet, Mint, and Spectrum. The exact supported palette/style compatibility may be narrowed during implementation if a combination is visually invalid, but style identity must come from structure/motion, not merely different gradients.

The current implementation is a visual candidate only; the Human Real-Mac refinements above are the newest acceptance direction for this same Draft PR.

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
CURRENT_IMPLEMENTATION_HEAD=RESOLVE_FROM_FRESH_ORIGIN_PRODUCT_FT_TAB_ATTENTION_HIGHLIGHT_001
GATE5_VISIBILITY_FUNCTION=PASS
GATE5_CURRENT_VISUAL_FAMILY=DOT_BEACON_ORBIT_SWEEP_REFINEMENT
CLASSIC_RED_DOT=RETAIN_AS_SELECTABLE_STYLE
NEXT_STYLE_FAMILY=DOT_BEACON_HALO_ORBIT_PULSE_SWEEP
PALETTE_DIMENSION=RED_AMBER_BLUE_VIOLET_MINT_SPECTRUM
NEXT_GATE=FOCUSED_AND_FULL_XCTEST_DEBUG_RELEASE_EXACT_HEAD_CI_QA_THEN_HUMAN_REAL_MAC_ACCEPTANCE
DIAGNOSTICS_PR_124=PARKED_UNCHANGED
ROOT_CAUSE=N/A
```

## Acceptance direction

The next candidate must implement the latest Dot, Beacon, Orbit and Sweep refinements, retain the accepted Halo concept and the complete six-style family, preserve the symmetric previews and all runtime/profile/session behavior, pass renewed automated verification, and then return to Human Real-Mac visual acceptance.
