# FloatTabs Current Status

**Status date:** 2026-10-17
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: TAB_ATTENTION_VISUAL_REFINEMENT_ACTIVE**

A new bounded product/UI task is active to simplify Tab color semantics and make unread ChatGPT attention visible at Retina/high-resolution scale.

## Verified baseline

- Current `main`: `7d473a4567ec0a7fa000c6b29dfeab95a36ebab6` — PR #123 merge commit.
- New task branch: `product/ft-tab-attention-highlight-001`.
- The previous shell movement task is completed/merged and grants no further authority.
- Diagnostics/history PR #124 remains a separate OPEN/Draft line of work pending later user acceptance; it is deliberately not a dependency/base for this task and must not be modified here.

## Audited current behavior

Production source on `main` currently shows:

- `ExternalWebAppTabView` renders unread/Ready state as a `6 pt` red dot over the favicon.
- the active Tab background is derived from the assigned Browser Profile color using a strong profile-color blend;
- Browser Profiles Settings expose per-profile color selection;
- attention Ready/acknowledgement, residency protection, runtime color semantics, Tab selection, and Browser Profile session isolation are separate existing authorities.

The small unread dot is insufficiently legible on high-resolution displays. Profile-specific Tab background color no longer serves a useful product purpose and competes with attention color as a visual signal.

## Product direction

The rail should have one clear visual hierarchy:

```text
NORMAL / ACTIVE TAB     = neutral surface; active selection remains identifiable by existing selection treatment
UNREAD / READY TAB      = whole-tab attention-red surface
BROWSER PROFILE COLOR   = no longer a Tab-rail visual signal
```

Unread/Ready visual treatment must be large enough to identify without resolving a tiny favicon badge. The whole visible Tab surface becomes the attention indicator. The old favicon red dot is removed from visible Tabs.

Browser Profile color controls should be removed from the user-facing Browser Profiles Settings because the color no longer drives Tab presentation. Existing persisted color metadata is retained for compatibility in this task; no migration, rewrite, or Browser Profile/session data deletion is authorized.

For compact overflow, a hidden unread Tab must still be discoverable. The overflow control should use the same whole-control attention treatment when any hidden Tab is unread. Individual overflow menu items may retain a bounded semantic unread marker/label because they are menu rows rather than rail Tabs.

## Protected behavior

This task is presentation-only. It must not change:

- ChatGPT attention state transitions or acknowledgement timing;
- unread source of truth or persistence semantics;
- attention residency protection;
- Tab selection/order/reorder behavior;
- favicon resident/released full-color vs grayscale semantics;
- Web runtime/navigation/focus/recovery;
- Browser Profile identity, WebKit data stores, cookies, login/session data, or backup compatibility;
- rail geometry, Dock magnification, fold/unfold, movement, resize, fullscreen, or speech state behavior.

## Current posture

```text
ACTIVE_PRODUCT_TASK=FT-TAB-ATTENTION-HIGHLIGHT-001
TASK_STATE=ACTIVE
TASK_BRANCH=product/ft-tab-attention-highlight-001
TASK_PR=PENDING_DRAFT
DIAGNOSTICS_PR_124=PARKED_UNCHANGED
ROOT_CAUSE=N/A
```

## Acceptance direction

Automated and Real-Mac acceptance must establish that unread Tabs are unmistakable on Retina/high-resolution displays, Browser Profile assignment/color no longer changes Tab background, attention clears through the existing acknowledgement path, normal/active/hover states remain legible in Light and Dark appearance, and no protected runtime/profile/session behavior changes.
