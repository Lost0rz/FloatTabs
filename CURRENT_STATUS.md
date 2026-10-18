# FloatTabs Current Status

**Status date:** 2026-10-18
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: TAB_ATTENTION_STYLE_GRID_LAYOUT_CORRECTIVE_ACTIVE**

`FT-TAB-ATTENTION-HIGHLIGHT-001` remains active in Draft PR #125. The live candidate at the start of this responsive style-grid corrective is `e77de09db23753168c9eaa0d946592f1a19d681b`, freshly verified against the task branch and PR. Human Real-Mac review accepted the six attention effects. The previous Settings IA corrective placed Unread Tab Attention under General; this iteration makes its six-style chooser a responsive three-column, two-row grid. Final Gate 5 acceptance is a short Human Settings layout check on the exact Release.

## Verified baseline

- Current `main`: `7d473a4567ec0a7fa000c6b29dfeab95a36ebab6`.
- Task branch: `product/ft-tab-attention-highlight-001`.
- Draft PR #125 — `Make unread Tabs visually prominent`.
- Candidate at the start of this responsive style-grid corrective: `e77de09db23753168c9eaa0d946592f1a19d681b`.
- Latest scope/control baseline: `e77de09db23753168c9eaa0d946592f1a19d681b`.
- Resolve the current implementation candidate from a fresh `origin/product/ft-tab-attention-highlight-001` ref; do not hard-code the commit containing this status file.
- The candidate requires exact-head macOS CI and QA DMG before Human Real-Mac Gate 5.
- Diagnostics/history PR #124 remains separate and untouched.
- Browser Profile color remains removed from Tab presentation; persisted Profile color metadata remains compatibility data only.

## Human Real-Mac acceptance and remaining Settings layout corrective

- Human Real-Mac review accepted the attention visual effects: Dot, Beacon, Halo, Orbit, Pulse and Sweep.
- The previous corrective moved Unread Tab Attention out of Audio and into General alongside Interface Appearance.
- General owns Interface Appearance and Unread Tab Attention. Audio owns Ready Alerts and Speech.
- The remaining corrective changes only the Style chooser layout inside General: three equal-width cards per row, two rows, in canonical order `Dot / Beacon / Halo`, then `Orbit / Pulse / Sweep`.
- The grid follows available content width for resizable Settings windows, with about 10pt horizontal spacing and approximately 82–84pt card height. Keep preview readability, complete animation, and clear selected checks. Palette layout remains unchanged.
- Do not modify any attention effect, palette, preference, runtime, ownership, or rail geometry.

This responsive style-grid corrective preserves the accepted six-style family, Style/Palette separation, symmetric Settings preview geometry, Reduce Motion, shared preview/runtime effect primitives, real rail geometry, and all protected attention/runtime/Profile/session/focus/navigation/recovery ownership.

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

The current implementation's attention effects are Human-accepted. The remaining corrective changes only Settings ownership and page composition in this same Draft PR.

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
GATE5_ATTENTION_VISUAL_EFFECTS=ACCEPTED
GATE5_REMAINING_CORRECTIVE=RESPONSIVE_STYLE_CHOOSER_3_COLUMNS_X_2_ROWS
GENERAL_SETTINGS_SECTIONS=INTERFACE_APPEARANCE,UNREAD_TAB_ATTENTION
AUDIO_SETTINGS_SECTIONS=READY_ALERTS,SPEECH
CLASSIC_RED_DOT=RETAIN_AS_SELECTABLE_STYLE
CURRENT_STYLE_FAMILY=DOT_BEACON_HALO_ORBIT_PULSE_SWEEP
PALETTE_DIMENSION=RED_AMBER_BLUE_VIOLET_MINT_SPECTRUM
NEXT_GATE=STYLE_GRID_LAYOUT_TESTS_THEN_FOCUSED_AND_FULL_XCTEST_DEBUG_RELEASE_EXACT_HEAD_CI_QA_THEN_HUMAN_SETTINGS_LAYOUT_CHECK
DIAGNOSTICS_PR_124=PARKED_UNCHANGED
ROOT_CAUSE=N/A
```

## Acceptance direction

The current candidate must keep the accepted Unread Tab Attention controls under General, render Style as a responsive three-column, two-row chooser, keep Audio limited to Ready Alerts and Speech, preserve all accepted effects and protected runtime/profile/session behavior, pass renewed automated verification, and receive a short Human Real-Mac Settings layout check.
